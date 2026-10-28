//
//  OnchainSendLabelTests.swift
//  ArkéTests
//
//  An onchain send through bark.offboard is a "move to Savings" only when it
//  pays one of the wallet's own addresses. A bitcoin address paid from the
//  Payments balance uses the same subsystem and must read as a payment
//  (`Features/Send_Onchain_From_Payments.md` §3.5).
//

import Testing
import Foundation
import ArkeUI

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Onchain send label: own address decides, not the subsystem")
@MainActor
struct OnchainSendLabelTests {

    private func offboardSend(toOwnAddress: Bool) -> TransactionModel {
        TransactionModel(
            txid: "tx", movementId: 1, type: .sent, amount: 10_000, date: Date(), status: .confirmed,
            address: "tb1p-recipient", subsystemCategory: "onchain_send", subsystemName: "bark.offboard",
            subsystemKind: "send_onchain", category: .onchainSend, sentToOwnAddress: toOwnAddress
        )
    }

    @Test("Own address: internal transfer, labelled as a move")
    func ownAddressIsAMove() {
        let tx = offboardSend(toOwnAddress: true)
        #expect(tx.isInternalTransfer)
        #expect(tx.shortDisplayText(includeStatusPrefix: false) == L10n.transactionMoved)
    }

    @Test("Third-party address from Payments: a send, not a move")
    func thirdPartyIsASend() {
        let tx = offboardSend(toOwnAddress: false)
        #expect(!tx.isInternalTransfer)
        #expect(tx.shortDisplayText(includeStatusPrefix: false) == L10n.transactionSent)
    }
}
