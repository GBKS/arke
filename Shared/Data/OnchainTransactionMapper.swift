//
//  OnchainTransactionMapper.swift
//  Arké
//
//  Maps bark's OnchainWallet.transactions() output to OnchainTransactionModel,
//  replacing the BDKTransactionReader history pipeline.
//  See Shared/Docs/Features/BDK_Transaction_Reader_Removal.md.
//

import Foundation
import Bark

/// Maps bark `WalletTransaction`s to `OnchainTransactionModel`s.
///
/// Derivation rules (verified against the Phase 0 A/B run, 2026-08-12):
/// - bark reports `onchainFeeSats` for any tx whose prevouts its esplora
///   sync has fetched — including pure receives — so wallet-funded vs
///   inbound is classified by the sign of `balanceChangeSats`, not by
///   fee presence.
/// - For wallet-funded txs every value-bearing input is ours (P2A fee
///   anchors are 0-value), so gross amounts follow from the raw tx:
///   sent = sum(outputs) + fee, received = sent + net.
/// - Self-transfers: CPFP fee bumps (flagged by bark) or txs where all
///   non-fee value stayed in the wallet (net == -fee).
nonisolated enum OnchainTransactionMapper {

    /// Convert bark wallet transactions to app models.
    /// - Parameters:
    ///   - transactions: bark's full wallet transaction list
    ///   - tipHeight: current chain tip, for confirmation counts
    ///   - blockTimestamps: unix timestamps by block hash; a confirmed tx
    ///     whose hash is missing keeps a nil timestamp and gets it on a
    ///     later refresh
    static func map(
        transactions: [WalletTransaction],
        tipHeight: UInt32?,
        blockTimestamps: [String: UInt64]
    ) -> [OnchainTransactionModel] {
        transactions.map { map(transaction: $0, tipHeight: tipHeight, blockTimestamps: blockTimestamps) }
    }

    static func map(
        transaction tx: WalletTransaction,
        tipHeight: UInt32?,
        blockTimestamps: [String: UInt64]
    ) -> OnchainTransactionModel {
        let net = tx.balanceChangeSats
        let fee = tx.onchainFeeSats

        let sent: UInt64
        let received: UInt64
        let modelFee: UInt64?

        if net > 0 {
            // Inbound. No fee on the model: the wallet didn't pay it (bark
            // still reports it when prevouts are indexed), and the previous
            // pipeline never attached fees to receives.
            sent = 0
            received = UInt64(net)
            modelFee = nil
        } else if let fee,
                  let outputSum = RawTransactionParser.outputValueSum(txHex: tx.txHex),
                  let gross = deriveGrossAmounts(outputSum: outputSum, fee: fee, net: net) {
            sent = gross.sent
            received = gross.received
            modelFee = fee
        } else {
            // Wallet-funded but fee/prevouts not yet indexed (e.g. a CPFP
            // child right after creation). Net is all we know; the gross
            // figures self-heal once the next sync fetches the prevouts.
            sent = UInt64(-net)
            received = 0
            modelFee = fee
        }

        let isSelfTransfer = tx.isCpfp || (fee.map { net == -Int64($0) } ?? false)

        let confirmationTime = tx.confirmation.map { block in
            ConfirmationTime(
                height: block.height,
                timestamp: blockTimestamps[block.hash],
                blockHash: block.hash,
                currentHeight: tipHeight
            )
        }

        return OnchainTransactionModel(
            txid: tx.txid,
            received: received,
            sent: sent,
            fee: modelFee,
            confirmationTime: confirmationTime,
            isSelfTransfer: isSelfTransfer
        )
    }

    /// Gross amounts for a wallet-funded tx: every value-bearing input is
    /// ours, so sent = all outputs + fee and received = sent + net. Nil if
    /// the numbers don't reconcile (e.g. a tx bark only partially indexed).
    private static func deriveGrossAmounts(
        outputSum: UInt64,
        fee: UInt64,
        net: Int64
    ) -> (sent: UInt64, received: UInt64)? {
        let (sent, overflow) = outputSum.addingReportingOverflow(fee)
        guard !overflow, sent <= UInt64(Int64.max) else { return nil }
        let received = Int64(sent) + net
        guard received >= 0 else { return nil }
        return (sent, UInt64(received))
    }
}

/// Repeats sync + fetch rounds until the wallet's transaction set stops
/// changing between rounds.
///
/// Bark's onchain wallet discovers history incrementally: each sync scans
/// only *revealed* addresses, and applying a round's transactions reveals
/// the change addresses the next round needs. After a fresh seed import a
/// single sync therefore returns a partial (or empty) list; looping until
/// stable walks the whole chain in one fetch — what the old BDK reader's
/// full scan used to do in one pass.
nonisolated enum OnchainHistorySyncer {

    static let maxRounds = 5

    /// - Parameters:
    ///   - previousTxids: the txid set from the last completed fetch (empty
    ///     on first fetch after launch). A round matching it ends the loop
    ///     immediately, so the steady state costs a single sync.
    ///   - sync: one wallet sync round
    ///   - fetch: the wallet's current transaction list
    /// - Returns: the final transaction list, its txid set (pass back in as
    ///   `previousTxids` next time), and the number of rounds run.
    static func syncUntilStable(
        previousTxids: Set<String>,
        maxRounds: Int = OnchainHistorySyncer.maxRounds,
        sync: () async throws -> Void,
        fetch: () async throws -> [WalletTransaction]
    ) async throws -> (transactions: [WalletTransaction], txids: Set<String>, rounds: Int) {
        var previous = previousTxids
        var transactions: [WalletTransaction] = []
        var rounds = 0

        repeat {
            rounds += 1
            try await sync()
            transactions = try await fetch()

            let current = Set(transactions.map(\.txid))
            if current == previous {
                break
            }
            previous = current
        } while rounds < maxRounds

        return (transactions, previous, rounds)
    }
}

/// Minimal consensus-format Bitcoin transaction parser: sums output values.
/// Script contents are opaque; only lengths are read.
nonisolated enum RawTransactionParser {

    /// Sum of all output values (sats) of a consensus-serialized tx, or nil
    /// if the hex doesn't parse.
    static func outputValueSum(txHex: String) -> UInt64? {
        guard let data = Data(hexEncoded: txHex) else { return nil }
        var reader = ByteReader(data)

        guard reader.skip(4) else { return nil }  // version

        // BIP-144 segwit marker + flag (a 0x00 marker is impossible as an
        // input count, so this is unambiguous)
        guard let firstByte = reader.peek() else { return nil }
        if firstByte == 0x00 {
            guard reader.skip(2) else { return nil }
        }

        guard let inputCount = reader.readVarInt() else { return nil }
        for _ in 0..<inputCount {
            guard reader.skip(36),                          // outpoint
                  let scriptLength = reader.readVarInt(),
                  reader.skip(Int(clamping: scriptLength)), // scriptSig
                  reader.skip(4)                            // sequence
            else { return nil }
        }

        guard let outputCount = reader.readVarInt() else { return nil }
        var sum: UInt64 = 0
        for _ in 0..<outputCount {
            guard let value = reader.readUInt64LE(),
                  let scriptLength = reader.readVarInt(),
                  reader.skip(Int(clamping: scriptLength))
            else { return nil }
            let (partial, overflow) = sum.addingReportingOverflow(value)
            guard !overflow else { return nil }
            sum = partial
        }
        // Witnesses and locktime follow; not needed for the output sum
        return sum
    }
}

// MARK: - Byte-level helpers

private nonisolated struct ByteReader {
    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    func peek() -> UInt8? {
        offset < data.endIndex ? data[offset] : nil
    }

    mutating func skip(_ count: Int) -> Bool {
        guard count >= 0, data.endIndex - offset >= count else { return false }
        offset += count
        return true
    }

    mutating func readByte() -> UInt8? {
        guard offset < data.endIndex else { return nil }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt64LE() -> UInt64? {
        guard data.endIndex - offset >= 8 else { return nil }
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(data[offset + i]) << (8 * i)
        }
        offset += 8
        return value
    }

    mutating func readUInt16LE() -> UInt16? {
        guard data.endIndex - offset >= 2 else { return nil }
        let value = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        offset += 2
        return value
    }

    mutating func readUInt32LE() -> UInt32? {
        guard data.endIndex - offset >= 4 else { return nil }
        var value: UInt32 = 0
        for i in 0..<4 {
            value |= UInt32(data[offset + i]) << (8 * i)
        }
        offset += 4
        return value
    }

    /// Bitcoin CompactSize varint
    mutating func readVarInt() -> UInt64? {
        guard let first = readByte() else { return nil }
        switch first {
        case 0..<0xfd:
            return UInt64(first)
        case 0xfd:
            return readUInt16LE().map(UInt64.init)
        case 0xfe:
            return readUInt32LE().map(UInt64.init)
        default:
            return readUInt64LE()
        }
    }
}

private nonisolated extension Data {
    init?(hexEncoded hex: String) {
        let characters = Array(hex.utf8)
        guard characters.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(characters.count / 2)
        for i in stride(from: 0, to: characters.count, by: 2) {
            guard let high = characters[i].hexNibble, let low = characters[i + 1].hexNibble else {
                return nil
            }
            bytes.append((high << 4) | low)
        }
        self.init(bytes)
    }
}

private nonisolated extension UInt8 {
    var hexNibble: UInt8? {
        switch self {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return self - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return self - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return self - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}
