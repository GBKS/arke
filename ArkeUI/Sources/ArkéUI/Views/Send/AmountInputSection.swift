//
//  AmountInputSection.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/18/25.
//

import SwiftUI

/// The amount entry card of the send flow. `Accessory` is an optional slot
/// rendered beside the amount field — the app uses it for the fiat "≈"
/// line (and, in fiat entry, the sats line), which this package cannot
/// build itself since it has no access to the rates service.
///
/// The field is whole numbers by default (sats). For fiat entry the app
/// passes `allowsDecimals` (decimal pad), `maxFractionDigits` (the
/// currency's minor units) and a `prefixText` currency symbol; the field
/// then accepts the locale's decimal separator and caps the fraction.
/// `validateInput` lets the caller refuse a change (over budget, say) with
/// a warning haptic; `onSetAmountSats` routes the Max button to the sats
/// value when the field itself holds something else.
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
    let allowsDecimals: Bool
    let maxFractionDigits: Int?
    let prefixText: String?
    let suffixText: String?
    let exceedsBalanceOverride: Bool?
    let currentAmountSats: Int?
    let validateInput: ((String) -> Bool)?
    let onSetAmountSats: ((Int) -> Void)?
    let amountAccessory: () -> Accessory

    /// Most digits accepted in total, both sides of the separator — just
    /// under 100 BTC in every unit (9,999,999,999 sats, "99.99999999" BTC)
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
        allowsDecimals: Bool = false,
        maxFractionDigits: Int? = nil,
        prefixText: String? = nil,
        suffixText: String? = nil,
        exceedsBalance: Bool? = nil,
        currentAmountSats: Int? = nil,
        validateInput: ((String) -> Bool)? = nil,
        onSetAmountSats: ((Int) -> Void)? = nil,
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
        self.allowsDecimals = allowsDecimals
        self.maxFractionDigits = maxFractionDigits
        self.prefixText = prefixText
        self.suffixText = suffixText
        self.exceedsBalanceOverride = exceedsBalance
        self.currentAmountSats = currentAmountSats
        self.validateInput = validateInput
        self.onSetAmountSats = onSetAmountSats
        self._isAmountFieldFocused = isAmountFieldFocused
        self.amountAccessory = amountAccessory
    }

    /// Over budget: the caller's verdict when given (it knows the sats
    /// behind a fiat field), else the field's own integer read
    private var exceedsBalance: Bool {
        if let exceedsBalanceOverride { return exceedsBalanceOverride }
        guard let enteredAmount = Int(amount) else { return false }
        return enteredAmount > maxSpendableAmount
    }

    /// Write a sats value: through the caller when the field holds
    /// something other than sats (fiat entry), else into the field
    private func setSats(_ sats: Int) {
        if let onSetAmountSats {
            onSetAmountSats(sats)
        } else {
            amount = "\(sats)"
        }
    }
    
    private func handleMaxButtonTap() async {
        let current = currentAmountSats ?? Int(amount)

        // If already at max, clear the amount
        if current == maxSpendableAmount {
            setSats(0)
            return
        }
        
        // If no calculator provided, use simple max
        guard let calculator = onCalculateMaxSendable else {
            setSats(maxSpendableAmount)
            return
        }
        
        // Calculate max with fee estimation; fall back to simple max if it fails
        let maxAmount = await calculator() ?? maxSpendableAmount
        await MainActor.run {
            setSats(maxAmount)
        }
    }

    /// Keep the field to what the unit allows: digits, at most one decimal
    /// separator (the locale's, or "."), `maxAmountDigits` digits in total
    /// across both sides of it, and at most `maxFractionDigits` after it.
    /// Whole-number mode drops any separator. Ten digits in total means the
    /// same ceiling in every unit — just under 100 BTC whether typed as
    /// sats or as "99.99999999" — instead of ten whole coins' worth of
    /// digits under a decimal format.
    private func sanitized(_ text: String) -> String {
        let separator = Locale.autoupdatingCurrent.decimalSeparator ?? "."
        let fractionLimit = maxFractionDigits ?? 0
        var integerPart = ""
        var fractionPart = ""
        var sawSeparator = false
        for character in text {
            if character.isASCII, character.isNumber {
                if sawSeparator { fractionPart.append(character) } else { integerPart.append(character) }
            } else if (String(character) == separator || character == "."), !sawSeparator, fractionLimit > 0 {
                sawSeparator = true
            }
        }
        integerPart = String(integerPart.prefix(Self.maxAmountDigits))
        guard sawSeparator else { return integerPart }
        let remainingDigits = max(0, Self.maxAmountDigits - integerPart.count)
        fractionPart = String(fractionPart.prefix(min(fractionLimit, remainingDigits)))
        return integerPart + separator + fractionPart
    }

    /// A change the caller refuses (over budget) is rolled back and felt
    private func rejectChange(revertingTo oldValue: String) {
        amount = oldValue
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
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
            // other unit's line) on the right, sharing the field's baseline
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    // Over budget is signalled by the unit label, a plain view
                    // that redraws in the same pass; the text field's own
                    // colour lags a keystroke while editing
                    if let prefixText {
                        Text(verbatim: prefixText)
                            .font(.title)
                            .foregroundColor(exceedsBalance ? .orange : .secondary)
                    }

                    TextField(L10n.formatZero, text: $amount)
                        .textFieldStyle(.plain)
                        .font(.title)
                        .foregroundColor(.primary)
                        #if os(iOS)
                        // A focused field keeps its keyboard when the type
                        // changes; the caller unfocuses before a mode swap
                        // and refocuses after, which brings up the right pad
                        .keyboardType(allowsDecimals ? .decimalPad : .numberPad)
                        #endif
                        .focused($isAmountFieldFocused)
                        .disabled(isAmountLocked)
                        .onChange(of: amount) { oldValue, newValue in
                            let cleaned = sanitized(newValue)
                            if cleaned != newValue {
                                amount = cleaned
                                return
                            }
                            if let validateInput, newValue != oldValue, !validateInput(newValue) {
                                rejectChange(revertingTo: oldValue)
                            }
                        }
                        .accessibilityLabel(Text(String(localized: "accessibility_amount_field", defaultValue: "Send amount", bundle: .module)))
                        .accessibilityValue(exceedsBalance
                            ? Text(String(localized: "accessibility_value_exceeds_balance", defaultValue: "Exceeds available balance", bundle: .module))
                            : Text(verbatim: ""))

                    if let suffixText {
                        Text(verbatim: suffixText)
                            .font(.title3)
                            .foregroundColor(exceedsBalance ? .orange : .secondary)
                    }
                }

                // The other unit's line, supplied by the app. One line,
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
    /// The original initializer: whole sats, nothing beside the field
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
        // Sats entry with the unit trailing
        AmountInputSection(
            amount: .constant("12345"),
            maxSpendableAmount: 100000,
            availableBalanceText: "Ark balance: ₿ 1,000",
            availableBalanceName: "Ark balance",
            availableBalanceAmount: "₿ 1,000",
            feeText: "Fee: ₿ 100",
            isAmountLocked: false,
            lockedAmountReason: nil,
            minimumSendAmount: 330,
            onCalculateMaxSendable: nil,
            suffixText: "sats",
            isAmountFieldFocused: $isFocused
        ) {
            Text(verbatim: "≈ $10.60")
                .font(.body)
                .foregroundColor(.secondary)
        }
        
        // Fiat entry with the sats line beside the field
        AmountInputSection(
            amount: .constant("12.50"),
            maxSpendableAmount: 100000,
            availableBalanceText: "Ark balance: ₿ 1,000",
            availableBalanceName: "Ark balance",
            availableBalanceAmount: "₿ 1,000",
            feeText: "Fee: ₿ 100",
            isAmountLocked: false,
            lockedAmountReason: nil,
            minimumSendAmount: 330,
            onCalculateMaxSendable: nil,
            allowsDecimals: true,
            maxFractionDigits: 2,
            prefixText: "$",
            exceedsBalance: false,
            isAmountFieldFocused: $isFocused
        ) {
            Text(verbatim: "₿ 14,562")
                .font(.body)
                .fontWeight(.medium)
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
