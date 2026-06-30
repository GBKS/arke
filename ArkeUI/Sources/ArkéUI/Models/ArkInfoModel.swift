//
//  ArkInfoModel.swift
//  ArkéUI
//
//  Created by Christoph on 10/20/25.
//  Moved into ArkéUI as a pure, previewable presentation value type
//  (no SwiftData/Bark).
//

import Foundation

public struct ArkInfoModel: Codable, Sendable, Equatable {
    public let network: String
    public let serverPubkey: String
    public let roundInterval: String
    public let nbRoundNonces: Int
    public let vtxoExitDelta: Int
    public let vtxoExpiryDelta: Int
    public let htlcSendExpiryDelta: Int
    public let htlcExpiryDelta: Int
    public let maxVtxoAmount: Int?
    public let requiredBoardConfirmations: Int
    public let maxUserInvoiceCltvDelta: Int
    public let minBoardAmount: Int
    public let maxVtxoExitDepth: UInt16  // New in v0.6.3: maximum genesis chain length before server refuses to cosign OOR transactions
    public let lnReceiveAntiDosRequired: Bool
    public let feeSchedule: FeeSchedule?

    enum CodingKeys: String, CodingKey {
        case network
        case serverPubkey = "server_pubkey"
        case roundInterval = "round_interval"
        case nbRoundNonces = "nb_round_nonces"
        case vtxoExitDelta = "vtxo_exit_delta"
        case vtxoExpiryDelta = "vtxo_expiry_delta"
        case htlcSendExpiryDelta = "htlc_send_expiry_delta"
        case htlcExpiryDelta = "htlc_expiry_delta"
        case maxVtxoAmount = "max_vtxo_amount"
        case requiredBoardConfirmations = "required_board_confirmations"
        case maxUserInvoiceCltvDelta = "max_user_invoice_cltv_delta"
        case minBoardAmount = "min_board_amount"
        case maxVtxoExitDepth = "max_vtxo_exit_depth"
        case lnReceiveAntiDosRequired = "ln_receive_anti_dos_required"
        case feeSchedule = "fee_schedule"
    }

    public init(network: String, serverPubkey: String, roundInterval: String, nbRoundNonces: Int, vtxoExitDelta: Int, vtxoExpiryDelta: Int, htlcSendExpiryDelta: Int, htlcExpiryDelta: Int, maxVtxoAmount: Int?, requiredBoardConfirmations: Int, maxUserInvoiceCltvDelta: Int, minBoardAmount: Int, maxVtxoExitDepth: UInt16, lnReceiveAntiDosRequired: Bool, feeSchedule: FeeSchedule?) {
        self.network = network
        self.serverPubkey = serverPubkey
        self.roundInterval = roundInterval
        self.nbRoundNonces = nbRoundNonces
        self.vtxoExitDelta = vtxoExitDelta
        self.vtxoExpiryDelta = vtxoExpiryDelta
        self.htlcSendExpiryDelta = htlcSendExpiryDelta
        self.htlcExpiryDelta = htlcExpiryDelta
        self.maxVtxoAmount = maxVtxoAmount
        self.requiredBoardConfirmations = requiredBoardConfirmations
        self.maxUserInvoiceCltvDelta = maxUserInvoiceCltvDelta
        self.minBoardAmount = minBoardAmount
        self.maxVtxoExitDepth = maxVtxoExitDepth
        self.lnReceiveAntiDosRequired = lnReceiveAntiDosRequired
        self.feeSchedule = feeSchedule
    }

    // Computed properties for convenience
    public var maxVtxoAmountBTC: Double? {
        guard let maxVtxoAmount else { return nil }
        return Double(maxVtxoAmount) / 100_000_000
    }

    public var minBoardAmountBTC: Double {
        Double(minBoardAmount) / 100_000_000
    }

    // Return the network as a BitcoinNetwork enum
    public var bitcoinNetwork: BitcoinNetwork? {
        return BitcoinNetwork(networkType: network)
    }

    public var isSignetNetwork: Bool {
        bitcoinNetwork == .signet
    }

    public var isMainnetNetwork: Bool {
        bitcoinNetwork == .mainnet
    }

    public var isTestnetNetwork: Bool {
        bitcoinNetwork == .testnet
    }

    // Parse round interval (assumes format like "30s")
    public var roundIntervalSeconds: Int? {
        guard roundInterval.hasSuffix("s") else { return nil }
        let numberString = String(roundInterval.dropLast())
        return Int(numberString)
    }

    // Formatted server pubkey for display (first 8 and last 8 characters)
    public var serverPubkeyShort: String {
        guard serverPubkey.count >= 16 else { return serverPubkey }
        let start = serverPubkey.prefix(8)
        let end = serverPubkey.suffix(8)
        return "\(start)...\(end)"
    }
}
