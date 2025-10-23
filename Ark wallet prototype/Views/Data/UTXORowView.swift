//
//  UTXORowView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI

enum UTXOStatus {
    case unconfirmed
    case confirming(Int)
    case confirmed
    
    var displayText: String {
        switch self {
        case .unconfirmed:
            return "Unconfirmed"
        case .confirming(let confirmations):
            return "\(confirmations) confirmation\(confirmations == 1 ? "" : "s")"
        case .confirmed:
            return "Confirmed"
        }
    }
    
    var color: Color {
        switch self {
        case .unconfirmed:
            return .orange
        case .confirming:
            return .blue
        case .confirmed:
            return .green
        }
    }
    
    var systemImage: String {
        switch self {
        case .unconfirmed:
            return "clock"
        case .confirming:
            return "hourglass"
        case .confirmed:
            return "checkmark.circle.fill"
        }
    }
}

struct UTXORowView: View {
    let utxo: UTXOModel
    let showDivider: Bool
    
    private var utxoStatus: UTXOStatus {
        if let confirmationHeight = utxo.confirmationHeight {
            // You can adjust these thresholds based on your requirements
            let confirmations = max(0, confirmationHeight)
            if confirmations == 0 {
                return .unconfirmed
            } else if confirmations < 6 {
                return .confirming(confirmations)
            } else {
                return .confirmed
            }
        } else {
            return .unconfirmed
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(utxo.formattedAmount)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: utxoStatus.systemImage)
                            .font(.caption2)
                            .foregroundStyle(utxoStatus.color)
                        
                        Text(utxoStatus.displayText)
                            .font(.caption2)
                            .foregroundStyle(utxoStatus.color)
                    }
                }
                
                Spacer()
                
                Text(utxo.shortOutpoint)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                
            }
            .padding(.vertical, 12)
            
            if showDivider {
                Divider()
            }
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        // Confirmed UTXO
        UTXORowView(
            utxo: UTXOModel(
                outpoint: "a1b2c3d4e5f6789012345678901234567890123456789012345678901234567890:0",
                amountSat: 50000000,
                confirmationHeight: 10
            ),
            showDivider: true
        )
        
        // Confirming UTXO (3 confirmations)
        UTXORowView(
            utxo: UTXOModel(
                outpoint: "b2c3d4e5f6789012345678901234567890123456789012345678901234567890a1:1",
                amountSat: 25000000,
                confirmationHeight: 3
            ),
            showDivider: true
        )
        
        // Unconfirmed UTXO
        UTXORowView(
            utxo: UTXOModel(
                outpoint: "c3d4e5f6789012345678901234567890123456789012345678901234567890a1b2:2",
                amountSat: 10000000,
                confirmationHeight: nil
            ),
            showDivider: false
        )
    }
    .padding()
    .background(Color(NSColor.controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    .padding()
}
