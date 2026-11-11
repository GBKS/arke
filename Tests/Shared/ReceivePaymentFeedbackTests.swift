//
//  ReceivePaymentFeedbackTests.swift
//  ArkéTests
//
//  Which movements count as money arriving for the receive chime.
//

import Testing
import Bark

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Receive Payment Feedback")
struct ReceivePaymentFeedbackTests {

    private func movement(subsystemName: String, subsystemKind: String, effective: Int64) -> Movement {
        Movement(
            id: 1,
            status: "finished",
            subsystemName: subsystemName,
            subsystemKind: subsystemKind,
            metadataJson: "{}",
            intendedBalanceSats: effective,
            effectiveBalanceSats: effective,
            offchainFeeSats: 0,
            sentToAddresses: [],
            receivedOnAddresses: [],
            inputVtxoIds: [],
            outputVtxoIds: [],
            exitedVtxoIds: [],
            createdAt: "",
            updatedAt: "",
            completedAt: nil,
            paymentHash: nil,
            lightningInvoice: nil,
            lightningOffer: nil
        )
    }

    @Test("Incoming Ark transfers and Lightning receives chime")
    func incomingPayments() {
        #expect(ReceivePaymentFeedbackModifier.isIncomingPayment(
            movement(subsystemName: "bark.arkoor", subsystemKind: "receive", effective: 5_000)))
        #expect(ReceivePaymentFeedbackModifier.isIncomingPayment(
            movement(subsystemName: "bark.lightning_receive", subsystemKind: "receive", effective: 5_000)))
    }

    @Test("Outgoing Ark transfers do not chime")
    func outgoingTransfer() {
        #expect(!ReceivePaymentFeedbackModifier.isIncomingPayment(
            movement(subsystemName: "bark.arkoor", subsystemKind: "send", effective: -5_000)))
    }

    @Test("Own-funds movements with a positive balance do not chime")
    func ownFunds() {
        #expect(!ReceivePaymentFeedbackModifier.isIncomingPayment(
            movement(subsystemName: "bark.board", subsystemKind: "board", effective: 5_000)))
        #expect(!ReceivePaymentFeedbackModifier.isIncomingPayment(
            movement(subsystemName: "bark.round", subsystemKind: "refresh", effective: 10)))
        #expect(!ReceivePaymentFeedbackModifier.isIncomingPayment(
            movement(subsystemName: "bark.exit", subsystemKind: "exit", effective: 5_000)))
    }
}
