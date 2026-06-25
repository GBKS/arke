//
//  PaymentRequestMetadataView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//

import SwiftUI

public struct PaymentRequestMetadataView: View {
    let label: String?
    let message: String?
    let amount: Int?

    public init(label: String?, message: String?, amount: Int?) {
        self.label = label
        self.message = message
        self.amount = amount
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let label = label, !label.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Text("label_label_colon")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(label)
                        .font(.body)
                    Spacer()
                }
                
                if (message != nil && !message!.isEmpty) || amount != nil {
                    Divider()
                }
            }
            if let message = message, !message.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Text("label_message_colon")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(message)
                        .font(.body)
                    Spacer()
                }
                
                if amount != nil {
                    Divider()
                }
            }
            if let amount = amount {
                HStack(alignment: .top, spacing: 10) {
                    Text("send_amount_to_pay")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(BitcoinFormatter.shared.formatAmount(amount))
                        .font(.body)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Full metadata
        PaymentRequestMetadataView(
            label: "Coffee Shop Payment",
            message: "Venti White Caramel Crunch Frappuccino with Almond Milk, Extra Hot, Caramel Drizzle and Extra Whip Cream",
            amount: 50000
        )
        
        // Partial metadata
        PaymentRequestMetadataView(
            label: "Donation",
            message: nil,
            amount: 100000
        )
        
        // Amount only
        PaymentRequestMetadataView(
            label: nil,
            message: nil,
            amount: 25000
        )
    }
    .padding()
    .frame(width: 400)
}
