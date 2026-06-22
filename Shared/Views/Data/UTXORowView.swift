//
//  UTXORowView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI
import ArkeUI

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
            return .Arke.orange
        case .confirming:
            return .Arke.blue
        case .confirmed:
            return .Arke.green
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
    let isSelected: Bool
    
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
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
            .cornerRadius(15)
        }
    }
}
