//
//  BitcoinFormatSettingView_macOS.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/13/25.
//

import SwiftUI
import ArkeUI

struct BitcoinFormatSettingView: View {
    @AppStorage(BitcoinAmountFormat.userDefaultsKey)
    private var selectedFormatRawValue: String = BitcoinAmountFormat.defaultFormat.rawValue
    
    private var selectedFormat: BitcoinAmountFormat {
        get { BitcoinAmountFormat(rawValue: selectedFormatRawValue) ?? .defaultFormat }
        nonmutating set { selectedFormatRawValue = newValue.rawValue }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.settingsBitcoinFormat)
                .font(.system(size: 24, design: .serif))
            
            Text(String(localized: "settings_bitcoin_format_help", defaultValue: "Choose how bitcoin amounts are displayed throughout the app."))
                .font(.body)
                .foregroundColor(.secondary)
            
            Picker("settings_bitcoin_format", selection: Binding(
                get: { selectedFormat },
                set: { selectedFormat = $0 }
            )) {
                ForEach(BitcoinAmountFormat.allCases, id: \.self) { format in
                    HStack(spacing: 15) {
                        Text(format.exampleFormat)
                            .font(.body)
                        Text("(\(format.displayName))")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .tag(format)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .padding(.top, 15)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
