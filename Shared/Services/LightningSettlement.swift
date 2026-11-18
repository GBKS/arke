//
//  LightningSettlement.swift
//  Arké
//
//  Created by Christoph on 11/18/26.
//

import Foundation
import Bark

/// How a Lightning send ended when it did not end in `.paid`.
/// Read from bark's own records (`Features/Lightning_Send_Settlement.md` §3,
/// bark-0.8.1): a refunded failure removes the send's checkpoint, a stuck
/// revocation keeps it with `hasFailedRevocation`, and an `.unknown` without
/// a payment hash cannot be read again.
nonisolated enum LightningSendFailure: Swift.Error, LocalizedError, Equatable {
    /// bark's records show the payment failed and the HTLCs were revoked
    case notSent
    /// The payment failed but bark could not revoke the HTLCs yet; it keeps trying
    case heldByServer
    /// The pay call returned `.unknown` for a send whose hash the app never learns
    case outcomeUnknown
    /// bark's state could not be read; the outcome is not known
    case statusUnreadable

    /// The outcome is open, not a failure: the modal shows "Payment Not Confirmed"
    var isUnconfirmed: Bool {
        self == .outcomeUnknown || self == .statusUnreadable
    }

    var errorDescription: String? {
        switch self {
        case .notSent:
            return String(localized: "error_lightning_not_sent", defaultValue: "The payment did not go through. The amount is back in your balance.")
        case .heldByServer:
            return String(localized: "error_lightning_held_by_server", defaultValue: "The payment did not go through. The server still holds the amount; Arké keeps trying to get it back.")
        case .outcomeUnknown, .statusUnreadable:
            return String(localized: "error_lightning_not_confirmed", defaultValue: "Arké could not confirm this payment. Check Activity before you pay again.")
        }
    }
}

/// Starts a Lightning send with `wait: false` and waits for its outcome by
/// reading bark's local state. `wait: true` polled the server every 2 s and
/// did not wake on the mailbox's "payment succeeded" message; here bark's
/// daemon and mailbox drive the send and the app only reads.
nonisolated enum LightningSettlement {

    /// Runs `pay` and, when it throws, checks whether bark kept the send anyway.
    ///
    /// With `wait: false` bark returns a retryable error of the HTLC cosign or
    /// payment start instead of retrying inside the call, and leaves the
    /// checkpointed send for its daemon. Reporting that as a failure invites
    /// paying twice, so the send that appeared during the call is returned as
    /// `.inProgress` and the caller waits for it.
    ///
    /// - Parameters:
    ///   - knownHash: the payment hash when known before paying (BOLT11)
    ///   - pendingSends: bark's `pendingLightningSends()`
    ///   - pay: the `wait: false` pay call
    static func start(
        knownHash: String?,
        pendingSends: () async throws -> [LightningSend],
        pay: () async throws -> LightningSendStatus
    ) async throws -> LightningSendStatus {
        // Without a hash, the only way to find this call's send after an error
        // is to compare against the sends that existed before it
        var pendingBefore: Set<String>?
        if knownHash == nil {
            pendingBefore = try? await Set(pendingSends().map(\.paymentHash))
        }

        do {
            return try await pay()
        } catch {
            let appeared = (try? await pendingSends().filter { send in
                if let knownHash { return send.paymentHash == knownHash }
                guard let pendingBefore else { return false }
                return !pendingBefore.contains(send.paymentHash)
            }) ?? []
            guard appeared.count == 1, let send = appeared.first else {
                throw error
            }
            return .inProgress(send: send)
        }
    }

    /// Returns the `.paid` status once bark has the preimage, or throws a
    /// `LightningSendFailure`.
    ///
    /// - Parameters:
    ///   - started: what the pay call (or `start`) returned
    ///   - knownHash: the payment hash when known before paying (BOLT11), so an
    ///     `.unknown` straight from the pay call can be read again
    ///   - readState: bark's `lightningSendState(paymentHash:)`, a local read
    ///     that never advances the send
    static func wait(
        for started: LightningSendStatus,
        knownHash: String? = nil,
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
                throw LightningSendFailure.heldByServer
            case .inProgress:
                try await Task.sleep(for: pollInterval)
            case .unknown:
                // bark reads its paid record before the checkpoint and writes
                // them in the same order, so one `.unknown` can be a settlement
                // that finished between the two lookups
                unknownReads += 1
                if unknownReads > 1 {
                    throw LightningSendFailure.notSent
                }
            }
            guard let paymentHash else {
                throw LightningSendFailure.outcomeUnknown
            }
            do {
                status = try await readState(paymentHash)
            } catch {
                throw LightningSendFailure.statusUnreadable
            }
        }
    }
}
