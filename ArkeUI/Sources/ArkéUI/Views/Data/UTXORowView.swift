//
//  UTXORowView.swift
//  ArkéUI
//
//  Created by Christoph on 10/17/25.
//  Moved into ArkéUI as a pure, previewable presentation view.
//

import SwiftUI

public enum UTXOStatus {
    case unconfirmed
    case confirming(Int)
    case confirmed

    public var displayText: String {
        switch self {
        case .unconfirmed:
            return String(localized: "status_unconfirmed", defaultValue: "Unconfirmed", bundle: .module)
        case .confirming(let confirmations):
            return String(localized: "\(confirmations) confirmations", bundle: .module)
        case .confirmed:
            return L10n.statusConfirmed
        }
    }

    public var color: Color {
        switch self {
        case .unconfirmed:
            return .Arke.orange
        case .confirming:
            return .Arke.blue
        case .confirmed:
            return .Arke.green
        }
    }

    public var systemImage: String {
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

public struct UTXORowView: View {
    let utxo: UTXOModel
    let isSelected: Bool

    public init(utxo: UTXOModel, isSelected: Bool = false) {
        self.utxo = utxo
        self.isSelected = isSelected
    }

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

    public var body: some View {
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

#Preview {
    List(UTXOModel.samples) { utxo in
        UTXORowView(utxo: utxo)
    }
}
