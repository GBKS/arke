//
//  OnchainTransactionMapperTests.swift
//  Arke
//
//  Tests for the bark WalletTransaction → OnchainTransactionModel mapping
//  that replaced the BDKTransactionReader history pipeline (see
//  Shared/Docs/Features/BDK_Transaction_Reader_Removal.md). The raw-tx
//  fixtures are real signet transactions from the Phase 0 A/B wallet, so
//  the expected values are network-verified.
//

import Testing
import Foundation
import Bark

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

// MARK: - Fixtures (real signet transactions)

private enum Fixture {
    /// Exit CPFP child 9c896296… — v3, two inputs (wallet UTXO + 0-value P2A
    /// anchor whose spend carries no witness), one 146,807-sat change output.
    /// bark reported net −3,193, fee 3,193, isCpfp true.
    static let cpfpChildHex = "030000000001029dfa53d7dc9e4895a6cc68bf0e08b8199b0a9c2df9a5a9362cbc47eb8a65b9a30100000000fdffffffc8b1c557e28877b26761651fbf0946462b004fb35eeef14e9496a6057cd9bf530200000000ffffffff01773d020000000000225120210c9d398303f4a75574f339e4ef153d98e019882efd48ae63189d92a22e1aa101401c0f11ec1842e008194c65fad6865394f1e4f797de5d45f9ac32b947c3f85bb9a830ab7e6d0a8845cc2b5dfb28e195e10bfee51427876af1bfff940537175c350014d40400"
    static let cpfpChildOutputSum: UInt64 = 146_807

    /// Plain send 818d4178… — v2 segwit, two inputs, one external
    /// 50,000-sat output plus 143,041-sat change. bark reported net −50,601,
    /// fee 601.
    static let sendHex = "0200000000010293cc0893d4b2ed31e82f23dac73d4998baa0c792f03540b9d06b7e9a982525500100000000fdfffffff57f63e0e7771ffc61739ab00821269cbbfb1cc914979ffd61a08ff22005a2f00000000000fdffffff0250c3000000000000160014ceade236a63ae3e5a50b005da61b4a11a029d9cec12e020000000000225120e50ae282644f5a14f01ab1961637f8a87d7ce0ee536d45bf16707eb2f7ccb7d90140b5dc89fc3931bb199ef3fe599225379c609bca013701f483ea946eb9d15ea9d2b750c984efac346adca7d43fa42f3d56ad668baef3da612c56e38c4a49a6509e0140ab618bd426502d00ce549e3880de202b6ba0cb4accef77ae0734e0f2795584c0d6724242c905c5daf29d610da20225ea12eded1d46a194742afa7b7d2b56f5cca7d70400"
    static let sendOutputSum: UInt64 = 193_041

    /// Hand-built legacy (pre-segwit) tx: one input, one 3,840-sat output.
    static let legacyHex = "0100000001"
        + "0000000000000000000000000000000000000000000000000000000000000000"  // prev txid
        + "00000000"          // prev vout
        + "00"                // scriptSig length
        + "ffffffff"          // sequence
        + "01"                // output count
        + "000f000000000000"  // 3,840 sats, little-endian
        + "0151"              // script: 1 byte, OP_TRUE
        + "00000000"          // locktime
    static let legacyOutputSum: UInt64 = 3_840
}

private func makeWalletTransaction(
    txid: String = "0000000000000000000000000000000000000000000000000000000000000000",
    txHex: String = "",
    fee: UInt64? = nil,
    net: Int64,
    confirmation: BlockRef? = nil,
    isCpfp: Bool = false
) -> WalletTransaction {
    WalletTransaction(
        txid: txid,
        txHex: txHex,
        onchainFeeSats: fee,
        balanceChangeSats: net,
        confirmation: confirmation,
        isCpfp: isCpfp
    )
}

// MARK: - Raw transaction parser

@Suite("RawTransactionParser")
struct RawTransactionParserTests {

    @Test func sumsSegwitCpfpChildOutputs() {
        #expect(RawTransactionParser.outputValueSum(txHex: Fixture.cpfpChildHex) == Fixture.cpfpChildOutputSum)
    }

    @Test func sumsMultiOutputSendOutputs() {
        #expect(RawTransactionParser.outputValueSum(txHex: Fixture.sendHex) == Fixture.sendOutputSum)
    }

    @Test func sumsLegacyTransactionOutputs() {
        #expect(RawTransactionParser.outputValueSum(txHex: Fixture.legacyHex) == Fixture.legacyOutputSum)
    }

    @Test func rejectsTruncatedTransaction() {
        let truncated = String(Fixture.sendHex.prefix(120))
        #expect(RawTransactionParser.outputValueSum(txHex: truncated) == nil)
    }

    @Test func rejectsOddLengthHex() {
        #expect(RawTransactionParser.outputValueSum(txHex: "abc") == nil)
    }

    @Test func rejectsNonHexCharacters() {
        #expect(RawTransactionParser.outputValueSum(txHex: "zz000000") == nil)
    }

    @Test func rejectsEmptyString() {
        #expect(RawTransactionParser.outputValueSum(txHex: "") == nil)
    }
}

// MARK: - Mapper

@Suite("OnchainTransactionMapper")
struct OnchainTransactionMapperTests {

    @Test func inboundReceiveUsesNetAndDropsBarkFee() {
        // bark reports fees even for pure receives (its esplora sync fetches
        // prevouts) - the model must not carry them
        let tx = makeWalletTransaction(fee: 165, net: 50_000)
        let model = OnchainTransactionMapper.map(transaction: tx, tipHeight: nil, blockTimestamps: [:])

        #expect(model.sent == 0)
        #expect(model.received == 50_000)
        #expect(model.fee == nil)
        #expect(model.isSelfTransfer == false)
        #expect(model.isIncoming == true)
    }

    @Test func walletFundedSendDerivesGrossAmounts() {
        // Real send 818d4178…: outputs 193,041 + fee 601 → sent 193,642;
        // received = sent + net = 143,041 (the change output)
        let tx = makeWalletTransaction(txHex: Fixture.sendHex, fee: 601, net: -50_601)
        let model = OnchainTransactionMapper.map(transaction: tx, tipHeight: nil, blockTimestamps: [:])

        #expect(model.sent == 193_642)
        #expect(model.received == 143_041)
        #expect(model.fee == 601)
        #expect(model.isSelfTransfer == false)
        #expect(model.netAmount == -50_601)
    }

    @Test func cpfpChildIsSelfTransferWithGrossAmounts() {
        // Real CPFP child 9c896296…: outputs 146,807 + fee 3,193 → sent
        // 150,000 (the anchor input is 0-value), received = the change
        let tx = makeWalletTransaction(txHex: Fixture.cpfpChildHex, fee: 3_193, net: -3_193, isCpfp: true)
        let model = OnchainTransactionMapper.map(transaction: tx, tipHeight: nil, blockTimestamps: [:])

        #expect(model.sent == 150_000)
        #expect(model.received == 146_807)
        #expect(model.fee == 3_193)
        #expect(model.isSelfTransfer == true)
    }

    @Test func selfTransferDetectedByNetEqualToNegatedFee() {
        // Even without the CPFP flag: all non-fee value stayed in the wallet
        let tx = makeWalletTransaction(txHex: Fixture.cpfpChildHex, fee: 3_193, net: -3_193, isCpfp: false)
        let model = OnchainTransactionMapper.map(transaction: tx, tipHeight: nil, blockTimestamps: [:])

        #expect(model.isSelfTransfer == true)
    }

    @Test func walletFundedWithoutFeeFallsBackToNet() {
        // A CPFP child right after creation: prevouts not indexed yet, so
        // bark reports no fee and gross amounts can't be derived
        let tx = makeWalletTransaction(txHex: "", fee: nil, net: -5_000)
        let model = OnchainTransactionMapper.map(transaction: tx, tipHeight: nil, blockTimestamps: [:])

        #expect(model.sent == 5_000)
        #expect(model.received == 0)
        #expect(model.fee == nil)
        #expect(model.netAmount == -5_000)
        #expect(model.isSelfTransfer == false)
    }

    @Test func confirmationCarriesResolvedBlockTimestamp() {
        let hash = "0000000b03551d859f3516fc1f624593b44503540c228ccdc0f7a3e4dc7d15f9"
        let tx = makeWalletTransaction(net: 1_000, confirmation: BlockRef(height: 316_437, hash: hash))
        let model = OnchainTransactionMapper.map(
            transaction: tx,
            tipHeight: 317_376,
            blockTimestamps: [hash: 1_786_000_000]
        )

        #expect(model.confirmationTime?.height == 316_437)
        #expect(model.confirmationTime?.timestamp == 1_786_000_000)
        #expect(model.confirmationTime?.blockHash == hash)
        #expect(model.confirmationTime?.currentHeight == 317_376)
        #expect(model.confirmations == 317_376 - 316_437 + 1)
        #expect(model.isConfirmed == true)
    }

    @Test func unresolvedBlockTimestampStaysNilButConfirmed() {
        let hash = "00000009c64bfa97b7cea7288d8b42cf326e8ffe3060a8f1355cc04f4c6ddd15"
        let tx = makeWalletTransaction(net: 1_000, confirmation: BlockRef(height: 316_438, hash: hash))
        let model = OnchainTransactionMapper.map(transaction: tx, tipHeight: nil, blockTimestamps: [:])

        #expect(model.isConfirmed == true)
        #expect(model.confirmationTime?.timestamp == nil)
        #expect(model.timestamp == nil)
    }

    @Test func unconfirmedTransactionHasNoConfirmationTime() {
        let tx = makeWalletTransaction(net: 1_000, confirmation: nil)
        let model = OnchainTransactionMapper.map(transaction: tx, tipHeight: 317_376, blockTimestamps: [:])

        #expect(model.confirmationTime == nil)
        #expect(model.isConfirmed == false)
        #expect(model.confirmations == 0)
    }
}

// MARK: - Sync-until-stable loop

@Suite("OnchainHistorySyncer")
struct OnchainHistorySyncerTests {

    /// Scripted wallet: each sync round makes the next entry of `script`
    /// visible to fetch, mimicking bark's incremental chain walk.
    private final class ScriptedWallet {
        private let script: [[String]]
        private(set) var syncCount = 0

        init(rounds script: [[String]]) {
            self.script = script
        }

        func sync() { syncCount += 1 }

        func fetch() -> [WalletTransaction] {
            let round = min(syncCount, script.count) - 1
            let txids = round >= 0 ? script[round] : []
            return txids.map { makeWalletTransaction(txid: $0, net: 1) }
        }
    }

    @Test func steadyStateExitsAfterOneRound() async throws {
        // Previous fetch already knew both txs - one sync, no extra rounds
        let wallet = ScriptedWallet(rounds: [["a", "b"]])
        let result = try await OnchainHistorySyncer.syncUntilStable(
            previousTxids: ["a", "b"],
            sync: { wallet.sync() },
            fetch: { wallet.fetch() }
        )

        #expect(result.rounds == 1)
        #expect(wallet.syncCount == 1)
        #expect(result.txids == ["a", "b"])
    }

    @Test func walksIncrementalDiscoveryUntilStable() async throws {
        // Fresh import: each sync reveals one more chained tx
        let wallet = ScriptedWallet(rounds: [["a"], ["a", "b"], ["a", "b", "c"], ["a", "b", "c"]])
        let result = try await OnchainHistorySyncer.syncUntilStable(
            previousTxids: [],
            sync: { wallet.sync() },
            fetch: { wallet.fetch() }
        )

        #expect(result.rounds == 4)  // 3 growth rounds + 1 confirming stability
        #expect(result.txids == ["a", "b", "c"])
        #expect(result.transactions.count == 3)
    }

    @Test func emptyWalletExitsAfterOneRound() async throws {
        let wallet = ScriptedWallet(rounds: [[]])
        let result = try await OnchainHistorySyncer.syncUntilStable(
            previousTxids: [],
            sync: { wallet.sync() },
            fetch: { wallet.fetch() }
        )

        #expect(result.rounds == 1)
        #expect(result.txids.isEmpty)
    }

    @Test func neverStableStopsAtMaxRounds() async throws {
        // Pathological: something new every round - the cap must hold
        let wallet = ScriptedWallet(rounds: (1...10).map { round in
            (0..<round).map { "tx\($0)" }
        })
        let result = try await OnchainHistorySyncer.syncUntilStable(
            previousTxids: [],
            sync: { wallet.sync() },
            fetch: { wallet.fetch() }
        )

        #expect(result.rounds == OnchainHistorySyncer.maxRounds)
        #expect(wallet.syncCount == OnchainHistorySyncer.maxRounds)
        // Returns the latest (largest) view it reached
        #expect(result.transactions.count == OnchainHistorySyncer.maxRounds)
    }

    @Test func syncErrorPropagates() async {
        struct SyncFailure: Swift.Error {}
        await #expect(throws: SyncFailure.self) {
            _ = try await OnchainHistorySyncer.syncUntilStable(
                previousTxids: [],
                sync: { throw SyncFailure() },
                fetch: { [] }
            )
        }
    }
}

// MARK: - Entity timestamp preservation

@Suite("OnchainTransactionEntity timestamp preservation")
@MainActor
struct OnchainTransactionEntityTimestampTests {

    private func makeModel(timestamp: UInt64?, blockHash: String?) -> OnchainTransactionModel {
        OnchainTransactionModel(
            txid: "cafe",
            received: 1_000,
            sent: 0,
            fee: nil,
            confirmationTime: ConfirmationTime(
                height: 100,
                timestamp: timestamp,
                blockHash: blockHash,
                currentHeight: 105
            ),
            isSelfTransfer: false
        )
    }

    @Test func keepsResolvedTimestampWhenRefreshLacksOneForSameBlock() {
        let entity = OnchainTransactionEntity(from: makeModel(timestamp: 1_786_000_000, blockHash: "hash-a"))

        entity.update(from: makeModel(timestamp: nil, blockHash: "hash-a"))

        #expect(entity.confirmationTimestamp == 1_786_000_000)
        #expect(entity.confirmationBlockHash == "hash-a")
    }

    @Test func dropsTimestampWhenBlockChanges() {
        let entity = OnchainTransactionEntity(from: makeModel(timestamp: 1_786_000_000, blockHash: "hash-a"))

        entity.update(from: makeModel(timestamp: nil, blockHash: "hash-b"))

        #expect(entity.confirmationTimestamp == nil)
        #expect(entity.confirmationBlockHash == "hash-b")
    }

    @Test func adoptsFreshTimestampWhenProvided() {
        let entity = OnchainTransactionEntity(from: makeModel(timestamp: nil, blockHash: "hash-a"))

        entity.update(from: makeModel(timestamp: 1_786_000_123, blockHash: "hash-a"))

        #expect(entity.confirmationTimestamp == 1_786_000_123)
    }

    @Test func clearsConfirmationWhenModelUnconfirmed() {
        let entity = OnchainTransactionEntity(from: makeModel(timestamp: 1_786_000_000, blockHash: "hash-a"))

        let unconfirmed = OnchainTransactionModel(
            txid: "cafe",
            received: 1_000,
            sent: 0,
            fee: nil,
            confirmationTime: nil,
            isSelfTransfer: false
        )
        entity.update(from: unconfirmed)

        #expect(entity.confirmationTimestamp == nil)
        #expect(entity.confirmationBlockHash == nil)
        #expect(entity.confirmationHeight == nil)
        #expect(entity.isConfirmed == false)
    }
}
