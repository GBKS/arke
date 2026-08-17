//
//  ContactTransactionSummaryView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/13/25.
//

import SwiftUI
import ArkeUI

struct ContactTransactionSummaryView: View {
    let contact: ContactModel
    let onViewActivity: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "status_sent", defaultValue: "Sent"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(contact.formattedSentAmount ?? "0 ₿")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.Arke.red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(localized: "status_received", defaultValue: "Received"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(contact.formattedReceivedAmount ?? "0 ₿")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.Arke.green)
                }
            }
            
            if let transactionCount = contact.formattedTransactionCount {
                Button(action: onViewActivity) {
                    Text(transactionCount)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
