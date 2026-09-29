//
//  LightningInvoiceFormView.swift
//  Arké
//
//  Created by Assistant on 1/28/26.
//
//  Fluent Lightning invoice creation form with numeric keypad and optional
//  note. The amount can be entered in bitcoin or, when a rate is available,
//  in the display currency: tapping the secondary line swaps which one is
//  the big field (Docs/Features/Fiat_Rates.md §7, Phase 4). Sats stay the
//  source of truth throughout — see AmountEntryState.
//

import SwiftUI
import ArkeUI

struct LightningInvoiceFormView_iOS: View {
    @Bindable var viewModel: ReceiveViewModel
    let onGenerateInvoice: () -> Void

    @State private var showNoteField = false
    @FocusState private var isNoteFocused: Bool
    @AppStorage(UserDefaults.appThemeKey) private var theme: AppTheme = .defaultTheme
    @AppStorage(UserDefaults.fiatCurrencyKey) private var storedCurrency: String = ""
    @Environment(\.ratesService) private var ratesService

    // MARK: - Fiat context

    private var currency: String {
        FiatCurrencyPreference.resolve(stored: storedCurrency, available: ratesService.availableCurrencies)
    }

    /// The rate fiat entry would use, or nil when fiat cannot be entered:
    /// currency "None", no snapshot, or a snapshot a day old. Uses the same
    /// decision as every fiat line so entry and display agree.
    private var fiatRate: Decimal? {
        guard FiatAmountText.display(sats: 1, ratesService: ratesService, storedCurrency: storedCurrency) != nil else {
            return nil
        }
        return ratesService.rate(for: currency)?.value
    }

    private var isFiatMode: Bool {
        viewModel.entry.mode == .fiat
    }

    private var amountSats: Int? {
        viewModel.amountSats
    }

    // MARK: - Display

    /// The big number: the bitcoin buffer in the unit format, or the fiat
    /// buffer in the currency's format, each keeping the digits typed so far
    private var primaryText: String {
        if isFiatMode {
            return FiatConversion.formatPartialInput(viewModel.entry.fiatInput, currency: currency)
        }
        let amount = viewModel.amount
        // A partial decimal ("0.", "0.50") shows the raw digits, localized
        if BitcoinFormatter.shared.allowsDecimalInput && amount.contains(".") {
            return BitcoinFormatter.shared.formatPartialDecimalInput(amount)
        }
        guard let sats = BitcoinFormatter.shared.parseUserInput(amount) else {
            return BitcoinFormatter.shared.formatAmount(0)
        }
        return BitcoinFormatter.shared.formatAmount(sats)
    }
    
    /// Dynamic font size that shrinks as text gets longer
    private var dynamicFontSize: CGFloat {
        let baseSize: CGFloat = 56
        let threshold = 6
        let length = primaryText.count
        
        if length <= threshold {
            return baseSize
        }
        
        // Reduce by 1 point for each character beyond threshold
        let reduction = CGFloat(length - threshold)
        return max(baseSize - reduction*1.5, 20) // Minimum size of 20 to keep it readable
    }

    /// Fraction digits the keypad allows in the current mode
    private var keypadDecimalPlaces: Int? {
        if isFiatMode {
            return FiatConversion.fractionDigits(for: currency)
        }
        return BitcoinFormatter.shared.allowsDecimalInput ? 8 : nil
    }

    /// The keypad writes into whichever buffer is active. A fiat keystroke
    /// recomputes sats once, at this moment's rate.
    private var keypadBinding: Binding<String> {
        Binding(
            get: { isFiatMode ? viewModel.entry.fiatInput : viewModel.amount },
            set: { newValue in
                if isFiatMode, let rate = fiatRate {
                    viewModel.setFiatInput(newValue, rate: rate)
                } else {
                    viewModel.amount = newValue
                }
            }
        )
    }

    /// Sats a candidate keypad string would produce, for the limit check
    private func candidateSats(_ candidate: String) -> Int? {
        if isFiatMode {
            guard let rate = fiatRate, let fiat = FiatConversion.parseInput(candidate) else { return nil }
            return FiatConversion.sats(fiatAmount: fiat, rate: rate)
        }
        return BitcoinFormatter.shared.parseUserInput(candidate)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Amount display area - fills available space
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    // Both numbers swap the entry unit when tapped; the big
                    // one only when there is another unit to swap to
                    Button {
                        swapEntryUnit()
                    } label: {
                        Text(primaryText)
                            .font(.system(size: dynamicFontSize, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.Arke.gold.opacity(viewModel.entry.isEmpty ? 0.5 : 1.0))
                            .frame(height: 56) // Fixed height to prevent layout shifts
                            .lineLimit(1)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.3), value: primaryText)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSwapEntryUnit)
                    .accessibilityLabel(String(localized: "receive_amount_entered", defaultValue: "Amount: \(primaryText)"))
                    .accessibilityHint(canSwapEntryUnit ? String(localized: "receive_swap_unit_hint", defaultValue: "Double-tap to enter the amount in the other currency") : "")

                    secondaryLine
                        // Roll the digits in step with the big number
                        .animation(.easeInOut(duration: 0.3), value: amountSats)
                }
                
                // Optional note toggle/field
                if showNoteField {
                    TextField(String(localized: "placeholder_note_optional", defaultValue: "Add note (optional)"), text: $viewModel.note)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNoteFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showNoteField = false
                                isNoteFocused = false
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if !viewModel.note.isEmpty {
                    // Show entered note as tappable text
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showNoteField = true
                            isNoteFocused = true
                        }
                    } label: {
                        Text(viewModel.note)
                            .font(.system(.body, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.horizontal, 40)
                } else {
                    // Show "+ Add note" button when empty
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showNoteField = true
                            isNoteFocused = true
                        }
                    } label: {
                        Text(String(localized: "receive_add_note", defaultValue: "Add note"))
                            .font(.system(.body, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            
            Spacer()
                .frame(minHeight: 0)
            
            // Keypad at bottom (hidden when note field is active)
            if !showNoteField {
                CustomNumericKeypad_iOS(
                    amount: keypadBinding,
                    onConfirm: {
                        onGenerateInvoice()
                    },
                    theme: .textured(imageName: theme.images.keypadTexture),
                    decimalPlaces: keypadDecimalPlaces,
                    validateInput: { newAmount in
                        // Allow partial input while typing; cap the resulting
                        // sats at the server's advertised invoice ceiling, if any
                        guard let sats = candidateSats(newAmount), let max = viewModel.maxInvoiceSats else { return true }
                        return sats <= max
                    },
                    allowEmptyConfirm: true
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.3), value: showNoteField)
        .onChange(of: fiatRate == nil) { _, unavailable in
            // Rate gone (or currency set to "None") while entering fiat:
            // fall back to bitcoin, sats carry over
            if unavailable && isFiatMode {
                viewModel.switchToBitcoin()
            }
        }
    }

    // MARK: - Swapping

    /// A swap is possible when fiat can be entered, or to leave fiat mode
    private var canSwapEntryUnit: Bool {
        isFiatMode || fiatRate != nil
    }

    private func swapEntryUnit() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if isFiatMode {
                viewModel.switchToBitcoin()
            } else if let rate = fiatRate {
                viewModel.switchToFiat(rate: rate, currency: currency)
            }
        }
    }

    // MARK: - Secondary line (tap to swap)

    /// Under the big number: the other unit. Tapping it makes that unit the
    /// field. In bitcoin mode this is the fiat "≈" line and only appears
    /// when a rate exists; in fiat mode it is the bitcoin amount.
    @ViewBuilder
    private var secondaryLine: some View {
        if isFiatMode {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.switchToBitcoin()
                }
            } label: {
                Text(BitcoinFormatter.shared.formatAmount(amountSats ?? 0))
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .opacity(viewModel.entry.isEmpty ? 0.5 : 1.0)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "receive_switch_to_bitcoin_entry", defaultValue: "Enter the amount in bitcoin instead"))
        } else if let rate = fiatRate {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.switchToFiat(rate: rate, currency: currency)
                }
            } label: {
                FiatAmountText(sats: amountSats ?? 0)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .opacity(viewModel.entry.isEmpty ? 0.5 : 1.0)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "receive_switch_to_fiat_entry", defaultValue: "Enter the amount in \(FiatCurrencyPreference.localizedName(for: currency)) instead"))
        }
    }
}
