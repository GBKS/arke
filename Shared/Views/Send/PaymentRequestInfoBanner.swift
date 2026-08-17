//
//  PaymentRequestInfoBanner.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/18/25.
//

import SwiftUI
import ArkeUI

struct PaymentRequestInfoBanner: View {
    let paymentRequest: PaymentRequest
    let onClear: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon based on payment format
            iconView
            
            VStack(alignment: .leading, spacing: 2) {
                Text(headerText)
                    .font(.title3)
                    .foregroundColor(.secondary)
                
                Text(displayTitle)
                    .font(.title2)
                    .fontWeight(.medium)
                
                if let message = paymentRequest.message {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "action_clear_payment_request", defaultValue: "Clear payment request"))
        }
    }
    
    // MARK: - Computed Properties
    
    private var headerText: String {
        if paymentRequest.label != nil {
            return "Payment to"
        } else {
            return "Payment via"
        }
    }
    
    private var displayTitle: String {
        // Priority: label > primary destination format > fallback
        if let label = paymentRequest.label {
            return label
        } else if let primary = paymentRequest.primaryDestination {
            return primary.format.displayName
        } else {
            return "Payment Request"
        }
    }
    
    @ViewBuilder
    private var iconView: some View {
        if let primary = paymentRequest.primaryDestination {
            Image(systemName: iconForFormat(primary.format))
                .font(.title3)
                .frame(width: 48, height: 48)
                .background(colorForFormat(primary.format).opacity(0.15))
                .foregroundColor(colorForFormat(primary.format))
                .clipShape(Circle())
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
                )
        } else {
            // Fallback icon
            Image(systemName: "doc.text.fill")
                .font(.title3)
                .frame(width: 48, height: 48)
                .background(Color.gray.opacity(0.1))
                .foregroundColor(.gray)
                .clipShape(Circle())
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
                )
        }
    }
    
    // MARK: - Helper Functions
    
    private func iconForFormat(_ format: AddressFormat) -> String {
        switch format {
        case .bitcoin:
            return "bitcoinsign.circle.fill"
        case .ark:
            return "cube.fill"
        case .lightning, .lightningInvoice, .lnurl:
            return "bolt.fill"
        case .silentPayments:
            return "eye.slash.fill"
        case .bip353:
            return "at.circle.fill"
        case .bip21:
            return "qrcode"
        case .bolt12:
            return "bolt.fill"
        }
    }
    
    private func colorForFormat(_ format: AddressFormat) -> Color {
        switch format {
        case .bitcoin:
            return .Arke.orange
        case .ark:
            return .Arke.purple
        case .lightning, .lightningInvoice, .lnurl:
            return .Arke.yellow
        case .silentPayments:
            return .Arke.blue
        case .bip353:
            return .Arke.green
        case .bip21:
            return .gray
        case .bolt12:
            return .Arke.orange
        }
    }
}
