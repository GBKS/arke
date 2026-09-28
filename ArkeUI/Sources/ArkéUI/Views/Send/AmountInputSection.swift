//
//  AmountInputSection.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/18/25.
//

import SwiftUI

/// The sats entry card of the send flow. `Accessory` is an optional slot
/// rendered directly under the amount field — the app uses it for the
/// fiat "≈" line, which this package cannot build itself (it has no
/// access to the rates service). Defaults to nothing.
public struct AmountInputSection<Accessory: View>: View {
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
    let amountAccessory: () -> Accessory

    /// Longest sats entry accepted (9,999,999,999 sats ≈ 99.99 BTC)
    public static var maxAmountDigits: Int { 10 }
    
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
        isAmountFieldFocused: FocusState<Bool>.Binding,
        @ViewBuilder amountAccessory: @escaping () -> Accessory
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
        self.amountAccessory = amountAccessory
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
                Text(L10n.placeholderEnterAmount)
                    .font(.body)
                    .fontWeight(.medium)
                
                if isAmountLocked, let reason = lockedAmountReason {
                    Text(verbatim: "(\(reason))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Field on the left taking the flexible width, accessory (the
            // fiat "≈" line) on the right, sharing the field's baseline
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField(L10n.formatZero, text: $amount)
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
                        // 10 digits = just under 100 BTC, far beyond what
                        // this wallet is for; keeps the row from overflowing
                        if newValue.count > Self.maxAmountDigits {
                            amount = String(newValue.prefix(Self.maxAmountDigits))
                        }
                    }
                    .accessibilityLabel(Text(String(localized: "accessibility_amount_field", defaultValue: "Send amount", bundle: .module)))
                    .accessibilityValue(exceedsBalance
                        ? Text(String(localized: "accessibility_value_exceeds_balance", defaultValue: "Exceeds available balance", bundle: .module))
                        : Text(verbatim: ""))

                // Fiat "≈" line or nothing — supplied by the app. One line,
                // shrinking before it wraps or crowds the field.
                amountAccessory()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(Text(String(localized: "accessibility_hint_set_max", defaultValue: "Sets the amount to your maximum spendable balance. Activate again to clear.", bundle: .module)))
                    }
                } else {
                    Text(String(localized: "send_amount_fixed", defaultValue: "Amount is fixed", bundle: .module))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if minimumSendAmount > 0 {
                    HStack(spacing: 8) {
                        Text(String(localized: "label_minimum", defaultValue: "Minimum", bundle: .module))
                            .font(.body)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(BitcoinFormatter.shared.formatAmount(minimumSendAmount))
                            .font(.body)
                    }
                    .accessibilityElement(children: .combine)
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

// MARK: - No accessory

extension AmountInputSection where Accessory == EmptyView {
    /// The original initializer: no accessory under the field
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
        self.init(
            amount: amount,
            maxSpendableAmount: maxSpendableAmount,
            availableBalanceText: availableBalanceText,
            availableBalanceName: availableBalanceName,
            availableBalanceAmount: availableBalanceAmount,
            feeText: feeText,
            isAmountLocked: isAmountLocked,
            lockedAmountReason: lockedAmountReason,
            minimumSendAmount: minimumSendAmount,
            onCalculateMaxSendable: onCalculateMaxSendable,
            isAmountFieldFocused: isAmountFieldFocused,
            amountAccessory: { EmptyView() }
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
        
        // Locked amount (Lightning invoice) with an accessory line
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
        ) {
            Text(verbatim: "≈ $41.79")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
    .padding()
    .frame(width: 600)
    .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button(L10n.buttonDone) {
                isFocused = false
            }
        }
    }
}
