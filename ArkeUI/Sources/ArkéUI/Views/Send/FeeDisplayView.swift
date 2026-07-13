//
//  FeeDisplayView.swift
//  Arké
//
//  Created by Assistant on 3/24/26.
//

import SwiftUI

/// A reusable view component that displays transaction fee information
/// with optional disclosure indicator for interactive fee selection
public struct FeeDisplayView: View {
    let fee: Int?
    let showDisclosure: Bool
    let onTap: (() -> Void)?
    
    public init(
        fee: Int?,
        showDisclosure: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.fee = fee
        self.showDisclosure = showDisclosure
        self.onTap = onTap
    }
    
    public var body: some View {
        Group {
            if showDisclosure && onTap != nil {
                Button(action: onTap ?? {}) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        HStack(spacing: 8) {
            Text("label_fee", bundle: .module)
                .font(.body)
                .foregroundColor(.secondary)

            Spacer()

            Text(feeText)
                .font(.body)

            if showDisclosure {
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            if showDisclosure {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.arkeSeparatorColor.opacity(0.5), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(fee == nil
            ? Text("accessibility_value_fee_unavailable", bundle: .module)
            : Text(verbatim: ""))
        .accessibilityHint(showDisclosure && onTap != nil
            ? Text("accessibility_hint_change_fee", bundle: .module)
            : Text(verbatim: ""))
    }
    
    private var feeText: String {
        guard let fee = fee else {
            return "—"
        }
        return BitcoinFormatter.shared.formatAmount(fee)
    }
}

#Preview("Fee Available") {
    VStack(spacing: 20) {
        FeeDisplayView(fee: 250)
        
        FeeDisplayView(fee: 1500)
        
        FeeDisplayView(fee: 50000)
    }
    .padding()
    .frame(width: 400)
}

#Preview("Fee Unavailable") {
    VStack(spacing: 20) {
        FeeDisplayView(fee: nil)
    }
    .padding()
    .frame(width: 400)
}

#Preview("With Disclosure") {
    VStack(spacing: 20) {
        FeeDisplayView(
            fee: 250,
            showDisclosure: true,
            onTap: { print("Fee tapped") }
        )
        
        FeeDisplayView(
            fee: nil,
            showDisclosure: true,
            onTap: { print("Fee tapped") }
        )
    }
    .padding()
    .frame(width: 400)
}

#Preview("In Context") {
    VStack(alignment: .leading, spacing: 10) {
        Text("Payment Details")
            .font(.title2)
            .fontWeight(.medium)
        
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Available")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("₿ 1,000")
                    .font(.body)
            }
            
            HStack(spacing: 8) {
                Text("Minimum")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("₿ 330")
                    .font(.body)
            }
            
            FeeDisplayView(
                fee: 250,
                showDisclosure: true,
                onTap: { print("Fee tapped") }
            )
        }
    }
    .padding()
    .frame(width: 400)
}
