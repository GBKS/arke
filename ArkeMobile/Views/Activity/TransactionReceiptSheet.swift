//
//  TransactionReceiptSheet.swift
//  Arké
//
//  Created by Christoph on 7/29/26.
//

import SwiftUI
import ArkeUI

/// Receipt-style sheet presented from the transaction swipe card's details
/// button. The card already shows the summary (amount, date, contact, tags,
/// notes), so this only carries what the card doesn't: the counterparty
/// address and the technical record of the transaction.
struct TransactionReceiptSheet: View {
    let transaction: TransactionModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("data_technical_details")
                    .font(.system(.title3))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .center)

                if let addressValue = displayAddress {
                    AddressCardExpandable(
                        address: addressValue,
                        shareContent: addressValue,
                        label: transaction.transactionType == .received
                            ? String(localized: "activity_from_address")
                            : String(localized: "activity_to_address")
                    )
                }

                TransactionTechnicalDetailRows(transaction: transaction)
            }
            .padding(20)
            .padding(.top, 8)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // Same visibility rules as the full detail view: lightning invoices
    // aren't useful to users, received offchain transfers would just show
    // the user's own address, and unilateral exits always go to it.
    private var displayAddress: String? {
        guard let address = transaction.address else { return nil }

        let isLightning = transaction.category?.isLightning ?? false
        let isReceivedOffchainTransfer = transaction.category == .offchainTransfer
            && transaction.transactionType == .received
        let isUnilateralExit = transaction.category == .exit

        guard !isLightning && !isReceivedOffchainTransfer && !isUnilateralExit else {
            return nil
        }

        // The address field may hold a PaymentMethod JSON object; extract
        // the actual address value, falling back to the raw string
        if let data = address.data(using: .utf8),
           let paymentMethod = try? JSONDecoder().decode(PaymentMethod.self, from: data) {
            return paymentMethod.value
        }
        return address
    }
}
