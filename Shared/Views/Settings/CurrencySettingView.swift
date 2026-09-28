//
//  CurrencySettingView.swift
//  Arké
//
//  Settings sub-page for the display currency (Docs/Features/Fiat_Rates.md,
//  Phase 2). A "None" row hides fiat everywhere; below it, one row per
//  code in the rates cache with the value of 1 BTC in that currency, so
//  its formatting is visible while choosing. The choice is stored on the
//  device only. The upstream data provider's required credit lives in
//  the footer.
//

import SwiftUI
import ArkeUI

struct CurrencySettingView: View {
    @AppStorage(UserDefaults.fiatCurrencyKey) private var storedCurrency: String = ""
    @Environment(\.ratesService) private var ratesService

    private var available: [String] {
        ratesService.availableCurrencies
    }

    private var selected: String {
        FiatCurrencyPreference.resolve(stored: storedCurrency, available: available)
    }

    private var orderedCodes: [String] {
        FiatCurrencyPreference.pickerOrder(available: available, selected: selected)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(String(localized: "settings_currency", defaultValue: "Currency"))
                    .font(.system(.title, design: .serif))

                Text(String(localized: "settings_currency_help", defaultValue: "Choose the currency for showing the value of your bitcoin. Amounts are always in bitcoin; the conversion is for reference only."))
                    .font(.body)
                    .lineSpacing(6)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    // One caption for the whole value column instead of
                    // "1 BTC ≈" repeated in every row; it heads the list
                    // as a whole, "None" included
                    Text(String(localized: "settings_currency_column_header", defaultValue: "1 BTC ≈"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 12)

                    noneRow

                    ForEach(orderedCodes, id: \.self) { code in
                        currencyRow(code)
                    }
                }

                if available.isEmpty {
                    Text(String(localized: "settings_currency_rates_pending", defaultValue: "Exchange rates haven't loaded yet. More currencies appear once they do."))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                footer
                    .padding(.top, 10)
            }
            .padding()
            #if os(macOS)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            #endif
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .task {
            await ratesService.refreshIfDue()
        }
    }

    // MARK: - Rows

    /// "None": bitcoin amounts only, no fiat anywhere
    private var noneRow: some View {
        let isSelected = FiatCurrencyPreference.isNone(selected)
        return optionRow(isSelected: isSelected) {
            storedCurrency = FiatCurrencyPreference.none
        } content: {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "settings_currency_none", defaultValue: "None"))
                    .font(.body)
                    .foregroundColor(.primary)
                Text(String(localized: "settings_currency_none_help", defaultValue: "Show bitcoin amounts only"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private func currencyRow(_ code: String) -> some View {
        let isSelected = code == selected
        return optionRow(isSelected: isSelected) {
            storedCurrency = code
        } content: {
            VStack(alignment: .leading, spacing: 2) {
                Text(code)
                    .font(.body)
                    .foregroundColor(.primary)
                Text(FiatCurrencyPreference.localizedName(for: code))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(valueText(for: code))
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// Shared row chrome: selection indicator, content, tinted background
    private func optionRow<Content: View>(
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: onSelect) {
            HStack(spacing: 15) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title3)

                content()
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
            // Spacer gaps and a clear fill are not hit-testable in a plain
            // button; make the whole padded row the tap target
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The value of 1 BTC in `code`, or an em dash when the cache has no rate for it
    private func valueText(for code: String) -> String {
        guard let snapshot = ratesService.rate(for: code) else {
            return L10n.symbolEmDash
        }
        return FiatConversion.formatted(snapshot.value, currency: code)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fileTime = ratesService.cache.newestUpdatedAt {
                Text(String(localized: "settings_currency_rates_as_of", defaultValue: "Rates as of \(fileTime.formatted(date: .abbreviated, time: .shortened))"))
            }

            // Required by the upstream data provider's free tier
            Link(destination: URL(string: "https://www.exchangerate-api.com")!) {
                Text(String(localized: "settings_currency_credit", defaultValue: "Rates by Exchange Rate API"))
                    .underline()
            }
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }
}

#Preview {
    CurrencySettingView()
}
