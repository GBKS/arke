//
//  SendAmountInput.swift
//  Arké
//
//  The send flow's amount card with bitcoin/fiat entry
//  (Docs/Features/Fiat_Rates.md §7, Phase 4). Wraps ArkéUI's
//  AmountInputSection — which cannot see the rates service — and owns
//  both entry units: which buffer the field edits, the keyboard and
//  fraction digits for that unit (the unit format's 8 for decimal
//  bitcoin, the currency's minor units for fiat), the unit label, and the
//  tappable "other unit" line beside the field that swaps modes.
//
//  `amount` (whole sats) stays the flows' binding and the source of truth;
//  the view model writes it once per keystroke. Without a view model
//  (desktop) this is the raw sats field with the fiat "≈" line.
//
//  Over budget is shown, not blocked: the field turns orange, a warning
//  haptic fires once when the value crosses the balance, and Send stays
//  disabled (the flows check that). Blocking on a partial entry
//  refused "1" outright under a decimal format with a sub-coin balance.
//

import SwiftUI
import ArkeUI
#if os(iOS)
import UIKit
#endif

struct SendAmountInput: View {
    /// Nil → raw sats entry (the desktop flows)
    var viewModel: SendViewModel?
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
    var isAmountFieldFocused: FocusState<Bool>.Binding

    @Environment(\.ratesService) private var ratesService
    @AppStorage(UserDefaults.fiatCurrencyKey) private var storedCurrency: String = ""

    /// True while a unit swap is in flight; the field's setter drops writes
    /// then (see `swapUnits`)
    @State private var isSwapping = false

    // MARK: - Context

    private var currency: String {
        FiatCurrencyPreference.resolve(stored: storedCurrency, available: ratesService.availableCurrencies)
    }

    /// The rate fiat entry would use, or nil when fiat cannot be entered —
    /// the same decision every fiat line makes, so entry and display agree
    private var fiatRate: Decimal? {
        guard viewModel != nil,
              FiatAmountText.display(sats: 1, ratesService: ratesService, storedCurrency: storedCurrency) != nil else {
            return nil
        }
        return ratesService.rate(for: currency)?.value
    }

    private var isFiatMode: Bool {
        viewModel?.isFiatEntry ?? false
    }

    private var sats: Int {
        Int(amount) ?? 0
    }

    private var exceedsBalance: Bool {
        maxSpendableAmount > 0 && sats > maxSpendableAmount
    }

    private var fiatFractionDigits: Int {
        FiatConversion.fractionDigits(for: currency)
    }

    /// Reading the formatter here makes the card follow a unit-format change
    private var bitcoinAllowsDecimals: Bool {
        BitcoinFormatter.shared.allowsDecimalInput
    }

    /// The unit label beside the field in the active mode
    private var unit: (text: String, isPrefix: Bool) {
        isFiatMode ? (FiatConversion.symbol(for: currency), true) : BitcoinFormatter.shared.entryUnit
    }

    /// The active unit's typed text. Read in `body` (not only inside the
    /// binding's getter) so the view observes it and redraws when a
    /// back-fill changes it — Max in fiat mode left the euro text stale
    /// otherwise, because the getter runs after layout, outside tracking.
    private var fieldText: String {
        guard let viewModel else { return amount }
        return isFiatMode ? viewModel.fiatAmountText : viewModel.bitcoinAmountText
    }

    /// Swap entry units safely. When a focused text field ends editing, iOS
    /// writes its current text back through the binding — so the field is
    /// unfocused *first*, while the binding still routes to the old unit
    /// (a harmless same-value write), then the swap and back-fill run, then
    /// focus returns, which also brings up the new unit's keyboard.
    /// Without this, "500" sats became "500" euros on the swap.
    private func swapUnits(_ perform: @escaping () -> Void) {
        let wasFocused = isAmountFieldFocused.wrappedValue
        isSwapping = true
        isAmountFieldFocused.wrappedValue = false
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                perform()
            }
            DispatchQueue.main.async {
                isSwapping = false
                if wasFocused {
                    isAmountFieldFocused.wrappedValue = true
                }
            }
        }
    }

    /// Back-fill the active unit's typed text from `amount`
    private func syncTypedText() {
        guard let viewModel else { return }
        if isFiatMode, let rate = fiatRate {
            viewModel.syncFiatEntryIfNeeded(rate: rate, currency: currency)
        } else {
            viewModel.syncBitcoinTextIfNeeded()
        }
    }

    var body: some View {
        // Snapshot the observed text; the binding hands it back and routes
        // writes to the active unit
        let currentText = fieldText
        let fieldBinding = Binding<String>(
            get: { currentText },
            set: { newValue in
                // A field ending editing mid-swap writes its old text; drop it
                guard !isSwapping else { return }
                guard let viewModel else {
                    amount = newValue
                    return
                }
                if isFiatMode, let rate = fiatRate {
                    viewModel.setFiatText(newValue, rate: rate)
                } else {
                    viewModel.setBitcoinText(newValue)
                }
            }
        )

        AmountInputSection(
            amount: fieldBinding,
            maxSpendableAmount: maxSpendableAmount,
            availableBalanceText: availableBalanceText,
            availableBalanceName: availableBalanceName,
            availableBalanceAmount: availableBalanceAmount,
            feeText: feeText,
            isAmountLocked: isAmountLocked,
            lockedAmountReason: lockedAmountReason,
            minimumSendAmount: minimumSendAmount,
            onCalculateMaxSendable: onCalculateMaxSendable,
            allowsDecimals: isFiatMode ? fiatFractionDigits > 0 : (viewModel != nil && bitcoinAllowsDecimals),
            maxFractionDigits: isFiatMode ? fiatFractionDigits : (viewModel != nil && bitcoinAllowsDecimals ? 8 : nil),
            prefixText: unit.isPrefix ? unit.text : nil,
            suffixText: unit.isPrefix ? nil : unit.text,
            exceedsBalance: exceedsBalance,
            currentAmountSats: Int(amount),
            onSetAmountSats: { newSats in
                // Max writes sats, never the field's text, and the typed text
                // is back-filled right here, before the next layout pass
                amount = newSats > 0 ? String(newSats) : ""
                syncTypedText()
            },
            isAmountFieldFocused: isAmountFieldFocused
        ) {
            otherUnitLine
        }
        .onChange(of: amount) { _, _ in
            // A fixed request amount or a clear changed the sats from
            // outside the field: back-fill the active unit's typed text
            syncTypedText()
        }
        .onChange(of: bitcoinAllowsDecimals) { _, _ in
            // Unit format changed while on screen: the typed bitcoin text is
            // in the old unit, re-fill it from the sats
            viewModel?.syncBitcoinTextIfNeeded()
        }
        .onChange(of: exceedsBalance) { _, nowExceeds in
            // Felt once, at the moment the value crosses the balance
            if nowExceeds {
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                #endif
            }
        }
        .onChange(of: fiatRate == nil) { _, unavailable in
            // Rate gone or currency set to "None" mid-entry: back to bitcoin
            if unavailable && isFiatMode {
                swapUnits { viewModel?.switchToBitcoinEntry() }
            }
        }
        .task {
            // First appearance with an amount already set (a request's fixed
            // amount): show it in the unit format
            viewModel?.syncBitcoinTextIfNeeded()
        }
    }

    // MARK: - Other unit (tap to swap)

    /// Beside the field: the amount in the other unit, tappable to make that
    /// unit the field. In bitcoin mode the fiat "≈" line (present whenever a
    /// rate exists, "≈ $0.00" as placeholder); in fiat mode the bitcoin
    /// amount, kept primary and medium so the true amount stays readable
    /// while fiat is being typed — this is money leaving the wallet.
    @ViewBuilder
    private var otherUnitLine: some View {
        if isFiatMode {
            Button {
                swapUnits { viewModel?.switchToBitcoinEntry() }
            } label: {
                Text(BitcoinFormatter.shared.formatAmount(sats))
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(sats > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: sats)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "send_switch_to_bitcoin_entry", defaultValue: "Enter the amount in bitcoin instead"))
        } else {
            Button {
                guard let viewModel, let rate = fiatRate else { return }
                swapUnits { viewModel.switchToFiatEntry(rate: rate, currency: currency) }
            } label: {
                FiatAmountText(sats: sats)
                    .font(.body)
                    .foregroundStyle(sats > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .disabled(fiatRate == nil)
            .accessibilityLabel(String(localized: "send_switch_to_fiat_entry", defaultValue: "Enter the amount in \(FiatCurrencyPreference.localizedName(for: currency)) instead"))
        }
    }
}
