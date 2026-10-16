//
//  AgentInvoice.swift
//  Arké
//
//  Minimal BOLT11 decoding for agent payments: network, amount, description,
//  payment hash and expiry. The app's LightningInvoiceParser doesn't read
//  expiry and maps signet (`lntbs`) to testnet, and the phone's checks need
//  both (Agent_Payments.md §7). Bark still validates the invoice fully when
//  it pays; this is only for the checks and the approval sheet.
//

import Foundation

nonisolated struct AgentInvoice: Sendable, Equatable {
    nonisolated enum Network: String, Sendable {
        case mainnet, testnet, signet, regtest, simnet
    }

    let network: Network
    /// nil for zero-amount invoices. Rounded up to whole sats.
    let amountSats: UInt64?
    let description: String?
    /// Hex, when the invoice carries one
    let paymentHash: String?
    let createdAt: Date
    let expirySeconds: UInt64

    var expiresAt: Date {
        createdAt.addingTimeInterval(TimeInterval(expirySeconds))
    }

    func isExpired(at date: Date = Date()) -> Bool {
        date >= expiresAt
    }

    // MARK: - Decoding

    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    /// Longest prefix first: `lnbcrt` before `lnbc`, `lntbs` before `lntb`
    private static let prefixes: [(String, Network)] = [
        ("lnbcrt", .regtest),
        ("lnbc", .mainnet),
        ("lntbs", .signet),
        ("lntb", .testnet),
        ("lnsb", .simnet),
    ]

    /// BOLT11 default when the invoice has no `x` field
    private static let defaultExpiry: UInt64 = 3600

    static func decode(_ raw: String) -> AgentInvoice? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("lightning:") {
            text.removeFirst("lightning:".count)
        }

        guard let separator = text.lastIndex(of: "1") else { return nil }
        let hrp = String(text[..<separator])

        var groups: [UInt8] = []
        for character in text[text.index(after: separator)...] {
            guard let index = charset.firstIndex(of: character) else { return nil }
            groups.append(UInt8(index))
        }

        // Layout: 7-group timestamp, tagged fields, 104-group signature, 6-group checksum
        let trailer = 104 + 6
        guard groups.count >= 7 + trailer else { return nil }

        guard let (prefix, network) = prefixes.first(where: { hrp.hasPrefix($0.0) }) else { return nil }

        let amountPart = String(hrp.dropFirst(prefix.count))
        let amountSats: UInt64?
        if amountPart.isEmpty {
            amountSats = nil
        } else {
            guard let msat = millisats(amountPart) else { return nil }
            amountSats = (msat + 999) / 1000
        }

        let body = Array(groups[0..<(groups.count - trailer)])
        let timestamp = value(of: body[0..<7])

        var description: String?
        var paymentHash: String?
        var expiry = defaultExpiry

        var cursor = 7
        while cursor + 3 <= body.count {
            let tag = body[cursor]
            let length = Int(body[cursor + 1]) << 5 | Int(body[cursor + 2])
            cursor += 3
            guard cursor + length <= body.count else { break }
            let field = body[cursor..<(cursor + length)]
            cursor += length

            switch tag {
            case 1: // p: payment hash, 52 groups = 32 bytes
                let bytes = bytes(of: field)
                if length == 52, bytes.count >= 32 {
                    paymentHash = bytes.prefix(32).map { String(format: "%02x", $0) }.joined()
                }
            case 13: // d: description
                description = String(bytes: bytes(of: field), encoding: .utf8)
            case 6: // x: expiry in seconds
                expiry = value(of: field)
            default:
                break
            }
        }

        return AgentInvoice(
            network: network,
            amountSats: amountSats,
            description: description,
            paymentHash: paymentHash,
            createdAt: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            expirySeconds: expiry
        )
    }

    /// Amount in millisatoshis from the HRP amount part, e.g. "21u" or "1500n"
    private static func millisats(_ amount: String) -> UInt64? {
        // 1 BTC = 100_000_000_000 msat
        let multipliers: [Character: UInt64] = ["m": 100_000_000, "u": 100_000, "n": 100]
        guard let last = amount.last else { return nil }

        if last.isNumber {
            guard let whole = UInt64(amount) else { return nil }
            let (result, overflow) = whole.multipliedReportingOverflow(by: 100_000_000_000)
            return overflow ? nil : result
        }

        guard let number = UInt64(amount.dropLast()) else { return nil }
        if last == "p" {
            // pico-BTC is a tenth of a millisat; BOLT11 requires a multiple of 10
            guard number % 10 == 0 else { return nil }
            return number / 10
        }
        guard let multiplier = multipliers[last] else { return nil }
        let (result, overflow) = number.multipliedReportingOverflow(by: multiplier)
        return overflow ? nil : result
    }

    /// Big-endian integer from 5-bit groups
    private static func value(of groups: ArraySlice<UInt8>) -> UInt64 {
        groups.reduce(UInt64(0)) { ($0 << 5) | UInt64($1) }
    }

    /// 5-bit groups to bytes, dropping the trailing padding bits
    private static func bytes(of groups: ArraySlice<UInt8>) -> [UInt8] {
        var accumulator = 0
        var bitCount = 0
        var result: [UInt8] = []
        for group in groups {
            // Only the low 12 bits are ever needed; masking keeps long fields from overflowing
            accumulator = ((accumulator << 5) | Int(group)) & 0xFFF
            bitCount += 5
            if bitCount >= 8 {
                bitCount -= 8
                result.append(UInt8((accumulator >> bitCount) & 0xFF))
            }
        }
        return result
    }
}
