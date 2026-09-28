//
//  CurrencySettingView.swift
//  Arké
//
//  Settings sub-page for the display currency (Docs/Features/Fiat_Rates.md,
//  Phase 2). Lists the codes present in the rates cache with each one's
//  "1 BTC ≈ …" so the currency's own formatting is visible while choosing.
//  The choice is stored on the device only. The upstream data provider's
//  required credit lives in the footer.
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

    private func currencyRow(_ code: String) -> some View {
        let isSelected = code == selected
        return Button {
            storedCurrency = code
        } label: {
            HStack(spacing: 15) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(code)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(FiatCurrencyPreference.localizedName(for: code))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(sampleText(for: code))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// "1 BTC ≈ $83,384.43", or an em dash when the cache has no rate for the code
    private func sampleText(for code: String) -> String {
        guard let snapshot = ratesService.rate(for: code) else {
            return L10n.symbolEmDash
        }
        return String(localized: "settings_currency_sample", defaultValue: "1 BTC ≈ \(FiatConversion.formatted(snapshot.value, currency: code))")
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
