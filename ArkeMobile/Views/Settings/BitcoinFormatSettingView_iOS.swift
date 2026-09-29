//
//  BitcoinFormatSettingView_iOS.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/13/25.
//
//  Settings sub-page for the bitcoin unit format. Structured like
//  CurrencySettingView (scroll view, direct @AppStorage assignment, no
//  wrapper view) after the previous shape stopped redrawing its selection
//  highlight after the first tap while the write itself succeeded.
//

import SwiftUI
import ArkeUI

struct BitcoinFormatSettingView_iOS: View {
    @AppStorage(BitcoinAmountFormat.userDefaultsKey)
    private var selectedFormatRawValue: String = BitcoinAmountFormat.defaultFormat.rawValue

    private var selectedFormat: BitcoinAmountFormat {
        BitcoinAmountFormat(rawValue: selectedFormatRawValue) ?? .defaultFormat
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L10n.settingsBitcoinFormat)
                    .font(.system(.title, design: .serif))

                Text(String(localized: "settings_bitcoin_format_help", defaultValue: "Choose how bitcoin amounts are displayed throughout the app."))
                    .font(.body)
                    .lineSpacing(6)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(BitcoinAmountFormat.allCases, id: \.self) { format in
                        formatRow(format)
                    }
                }
            }
            .padding()
        }
        .contentMargins(.top, 0, for: .scrollContent)
    }

    private func formatRow(_ format: BitcoinAmountFormat) -> some View {
        let isSelected = format == selectedFormat
        return Button {
            selectedFormatRawValue = format.rawValue
        } label: {
            HStack(spacing: 15) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title3)

                Text(format.exampleFormat)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                Text(format.displayName)
                    .font(.body)
                    .foregroundColor(.secondary)
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
}
