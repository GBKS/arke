//
//  LightningSettlement.swift
//  Arké
//
//  Created by Assistant on 11/17/26.
//

import Foundation
import Bark

/// Waits for the outcome of a Lightning send started with `wait: false`.
/// `wait: true` polls the server every 2 s and does not wake on the mailbox's
/// "payment succeeded" message; this reads bark's local state instead, so
/// "Sent" shows within one poll of the preimage. What each state means at
/// `bark-0.8.1`: `Migrations/Bark-0.26.1-to-0.27.0/README.md` items 1-3.
nonisolated enum LightningSettlement {

    enum SettlementError: Swift.Error, LocalizedError, Equatable {
        /// bark's records show the payment failed
        case failed
        /// bark's state could not be read; the outcome is not known
        case statusUnreadable

        var errorDescription: String? {
            switch self {
            case .failed:
                return String(localized: "error_lightning_send_failed", defaultValue: "The payment did not go through. Nothing was sent.")
            case .statusUnreadable:
                return String(localized: "error_lightning_send_status_unreadable", defaultValue: "Arké could not check this payment. Look in Activity before you pay again.")
            }
        }
    }

    /// Returns the `.paid` status once bark has the preimage, or throws
    /// `SettlementError`.
    ///
    /// - Parameters:
    ///   - paymentHash: the hash when known before paying (a BOLT11 invoice),
    ///     so an `.unknown` straight from the pay call can be read again
    ///   - readState: bark's `lightningSendState(paymentHash:)`, a local read
    ///     that never advances the send
    static func wait(
        for started: LightningSendStatus,
        paymentHash knownHash: String? = nil,
        pollInterval: Duration = .milliseconds(100),
        readState: (String) async throws -> LightningSendStatus
    ) async throws -> LightningSendStatus {
        var paymentHash = knownHash
        if case .inProgress(let send) = started {
            paymentHash = send.paymentHash
        }
        var status = started
        var unknownReads = 0

        while true {
            switch status {
            case .paid:
                return status
            case .inProgress(let send) where send.hasFailedRevocation:
                // Failed; bark keeps retrying to get the HTLCs back
                throw SettlementError.failed
            case .inProgress:
                try await Task.sleep(for: pollInterval)
            case .unknown:
                // bark reads its paid record before the checkpoint, so one
                // `.unknown` can be a settlement that finished in between
                unknownReads += 1
                if unknownReads > 1 {
                    throw SettlementError.failed
                }
            }
            guard let paymentHash else {
                throw SettlementError.failed
            }
            do {
                status = try await readState(paymentHash)
            } catch {
                // Never report a payment as failed on a failed read
                throw SettlementError.statusUnreadable
            }
        }
    }
}
