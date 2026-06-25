//
//  AmountInputSection.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/18/25.
//

import SwiftUI
import ArkeUI

public struct AmountInputSection: View {
    @Binding var amount: String
    let maxSpendableAmount: Int
    let availableBalanceText: String
    let availableBalanceName: String
    let availableBalanceAmount: String
    let feeText: String
    let isAmountLocked: Bool
    let lockedAmountReason: String?
    let minimumSendAmount: Int
    let onCalculateMaxSendable: (() async -> Int?)?
    
    @FocusState.Binding var isAmountFieldFocused: Bool

    public init(
        amount: Binding<String>,
        maxSpendableAmount: Int,
        availableBalanceText: String,
        availableBalanceName: String,
        availableBalanceAmount: String,
        feeText: String,
        isAmountLocked: Bool,
        lockedAmountReason: String?,
        minimumSendAmount: Int,
        onCalculateMaxSendable: (() async -> Int?)?,
        isAmountFieldFocused: FocusState<Bool>.Binding
    ) {
        self._amount = amount
        self.maxSpendableAmount = maxSpendableAmount
        self.availableBalanceText = availableBalanceText
        self.availableBalanceName = availableBalanceName
        self.availableBalanceAmount = availableBalanceAmount
        self.feeText = feeText
        self.isAmountLocked = isAmountLocked
        self.lockedAmountReason = lockedAmountReason
        self.minimumSendAmount = minimumSendAmount
        self.onCalculateMaxSendable = onCalculateMaxSendable
        self._isAmountFieldFocused = isAmountFieldFocused
    }

    private var exceedsBalance: Bool {
        guard let enteredAmount = Int(amount) else { return false }
        return enteredAmount > maxSpendableAmount
    }
    
    private func handleMaxButtonTap() async {
        // If already at max, clear the amount
        if amount == "\(maxSpendableAmount)" {
            amount = "0"
            return
        }
        
        // If no calculator provided, use simple max
        guard let calculator = onCalculateMaxSendable else {
            amount = "\(maxSpendableAmount)"
            return
        }
        
        // Calculate max with fee estimation
        if let maxAmount = await calculator() {
            await MainActor.run {
                amount = "\(maxAmount)"
            }
        } else {
            // Fall back to simple max if calculation fails
            await MainActor.run {
                amount = "\(maxSpendableAmount)"
            }
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("placeholder_enter_amount")
                    .font(.body)
                    .fontWeight(.medium)
                
                if isAmountLocked, let reason = lockedAmountReason {
                    Text("(\(reason))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            TextField(String(localized: "format_zero"), text: $amount)
                .textFieldStyle(.plain)
                .font(.title)
                .foregroundColor(exceedsBalance ? .orange : .primary)
                #if os(iOS)
                .keyboardType(.numberPad)
                //.padding(.horizontal, 16)
                //.padding(.vertical, 12)
                #endif
                .focused($isAmountFieldFocused)
                //.background(Color.gray.opacity(isAmountLocked ? 0.05 : 0.1))
                //.cornerRadius(16)
                .disabled(isAmountLocked)
                .onChange(of: amount) { oldValue, newValue in
                    if newValue.count > 20 {
                        amount = String(newValue.prefix(20))
                    }
                }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                if !isAmountLocked {
                    HStack(spacing: 8) {
                        Button {
                            Task {
                                await handleMaxButtonTap()
                            }
                        } label: {
                            Text(availableBalanceName)
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(availableBalanceAmount)
                                .font(.body)
                        }
                        .buttonStyle(.plain)
                        .disabled(maxSpendableAmount == 0)
                    }
                } else {
                    Text("send_amount_fixed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if minimumSendAmount > 0 {
                    HStack(spacing: 8) {
                        Text("Minimum")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(BitcoinFormatter.shared.formatAmount(minimumSendAmount))
                            .font(.body)
                    }
                }
                
                /*
                if !feeText.isEmpty {
                    Text("Fee: " + feeText)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                */
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.arkeSeparatorColor.opacity(0.5), lineWidth: 1)
        )
    }
}

#Preview {
    @Previewable @FocusState var isFocused: Bool
    
    VStack(spacing: 40) {
        // Normal editable amount
        AmountInputSection(
            amount: .constant(""),
            maxSpendableAmount: 100000,
            availableBalanceText: "Ark balance: ₿ 1,000",
            availableBalanceName: "Ark balance",
            availableBalanceAmount: "₿ 1,000",
            feeText: "Fee: ₿ 100",
            isAmountLocked: false,
            lockedAmountReason: nil,
            minimumSendAmount: 330,
            onCalculateMaxSendable: nil,
            isAmountFieldFocused: $isFocused
        )
        
        // Locked amount (Lightning invoice)
        AmountInputSection(
            amount: .constant("50000"),
            maxSpendableAmount: 100000,
            availableBalanceText: "Ark balance: ₿ 1,000",
            availableBalanceName: "Ark balance",
            availableBalanceAmount: "₿ 1,000",
            feeText: "Fee: ₿ 100",
            isAmountLocked: true,
            lockedAmountReason: "set by Lightning invoice",
            minimumSendAmount: 330,
            onCalculateMaxSendable: nil,
            isAmountFieldFocused: $isFocused
        )
    }
    .padding()
    .frame(width: 600)
    .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("button_done") {
                isFocused = false
            }
        }
    }
}
