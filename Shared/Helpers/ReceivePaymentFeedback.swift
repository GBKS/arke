//
//  ReceivePaymentFeedback.swift
//  Arké
//
//  Received-payment sound and haptic, scoped to the views that show a
//  receive QR code.
//

import SwiftUI
import Bark
import ArkeUI

/// Plays `PaymentFeedback.paymentReceived` for incoming movements while
/// `isActive` is true.
///
/// Meant for the views where the user is waiting for money: the Receive tab,
/// the tilt share overlay and the Lightning invoice sheet. The activity list
/// refreshing, a push wake or a cold-launch catch-up never trigger it: the
/// movement stream only runs in the foreground, and this subscription only
/// exists while the view is in front.
struct ReceivePaymentFeedbackModifier: ViewModifier {
    let isActive: Bool

    @Environment(WalletManager.self) private var walletManager
    @State private var subscriptionId: UUID?
    /// The service the subscription was taken out on. A reopened wallet
    /// builds a new service, where the old id means nothing.
    @State private var subscribedService: WalletNotificationService?

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive, initial: true) { _, active in
                if active {
                    subscribe()
                } else {
                    unsubscribe()
                }
            }
            .onChange(of: serviceIdentity) { _, _ in
                // The old service went away with its subscribers.
                unsubscribe()
                if isActive {
                    subscribe()
                }
            }
            .onDisappear {
                unsubscribe()
            }
    }

    private var serviceIdentity: ObjectIdentifier? {
        walletManager.walletNotificationService.map(ObjectIdentifier.init)
    }

    private func subscribe() {
        guard subscriptionId == nil, let service = walletManager.walletNotificationService else { return }
        subscribedService = service
        subscriptionId = service.onMovementCreated { movement in
            guard Self.isIncomingPayment(movement) else { return }
            PaymentFeedback.shared.paymentReceived(movementId: movement.id)
        }
    }

    private func unsubscribe() {
        if let id = subscriptionId {
            subscribedService?.removeSubscriber(id)
        }
        subscriptionId = nil
        subscribedService = nil
    }

    /// Incoming Ark transfers and Lightning receives. Boards, refreshes and
    /// exits also add offchain balance but move the user's own funds.
    nonisolated static func isIncomingPayment(_ movement: Movement) -> Bool {
        guard movement.effectiveBalanceSats > 0 else { return false }
        switch MovementCategory.from(subsystemName: movement.subsystemName, subsystemKind: movement.subsystemKind) {
        case .offchainTransfer, .lightningReceive:
            return true
        default:
            return false
        }
    }
}

extension View {
    /// Plays the received-payment sound and haptic for incoming movements
    /// while `isActive` is true. Apply to views that show a receive QR code.
    func receivePaymentFeedback(isActive: Bool) -> some View {
        modifier(ReceivePaymentFeedbackModifier(isActive: isActive))
    }
}
