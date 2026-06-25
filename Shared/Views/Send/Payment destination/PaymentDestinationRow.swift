//
//  PaymentDestinationRow.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/17/25.
//

import SwiftUI
import ArkeUI

/// Individual row for a payment destination option
struct PaymentDestinationRow: View {
    let ranked: PaymentDestinationSelector.RankedDestination
    let isRecommended: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Format icon and name
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .frame(width: 24)
                
                Text(ranked.destination.format.displayName)
                    .font(.headline)
                
                Spacer()
                
                // Recommended badge
                if isRecommended && ranked.viable {
                    Text("label_recommended")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.Arke.blue, in: Capsule())
                }
            }
            
            // Address preview
            Text(ranked.destination.shortAddress)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospaced()
            
            // Balance source and fee info
            HStack(spacing: 16) {
                Label {
                    Text(ranked.balanceSource.displayName)
                } icon: {
                    Image(systemName: "wallet.pass")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
                if let fee = ranked.estimatedFee, fee > 0 {
                    Label {
                        Text("~\(fee) sats")
                    } icon: {
                        Image(systemName: "bitcoinsign.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            
            // Viability reason
            if !ranked.viable {
                HStack(spacing: 4) {
                    //Image(systemName: "exclamationmark.triangle.fill")
                    //    .foregroundStyle(.orange)
                    Text(ranked.reason)
                }
                .font(.caption)
                .foregroundStyle(.orange)
            } else if !ranked.reason.isEmpty && ranked.reason != "Sufficient balance" {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text(ranked.reason)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var iconName: String {
        switch ranked.destination.format {
        case .ark:
            return "cube.fill"
        case .lightning, .lightningInvoice, .lnurl, .bolt12:
            return "bolt.fill"
        case .bitcoin:
            return "bitcoinsign.circle.fill"
        case .silentPayments:
            return "eye.slash.fill"
        case .bip353:
            return "at.circle.fill"
        case .bip21:
            return "qrcode"
        }
    }
    
    private var iconColor: Color {
        switch ranked.destination.format {
        case .ark:
            return .Arke.purple
        case .lightning, .lightningInvoice, .lnurl, .bolt12:
            return .Arke.orange
        case .bitcoin:
            return .Arke.orange
        case .silentPayments:
            return .Arke.blue
        case .bip353:
            return .Arke.green
        case .bip21:
            return .gray
        }
    }
}
