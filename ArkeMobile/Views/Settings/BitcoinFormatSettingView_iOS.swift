//
//  BitcoinFormatSettingView_iOS.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/13/25.
//

import SwiftUI
import ArkeUI

struct BitcoinFormatSettingView_iOS: View {
    @AppStorage(BitcoinAmountFormat.userDefaultsKey)
    private var selectedFormatRawValue: String = BitcoinAmountFormat.defaultFormat.rawValue
    
    private var selectedFormat: BitcoinAmountFormat {
        get { BitcoinAmountFormat(rawValue: selectedFormatRawValue) ?? .defaultFormat }
        nonmutating set { selectedFormatRawValue = newValue.rawValue }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("settings_bitcoin_format")
                .font(.system(size: 24, design: .serif))
            
            Text(String(localized: "settings_bitcoin_format_help"))
                .font(.body)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(BitcoinAmountFormat.allCases, id: \.self) { format in
                    formatOptionButton(format)
                }
            }
            .padding(.top, 15)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func formatOptionButton(_ format: BitcoinAmountFormat) -> some View {
        Button {
            selectedFormat = format
        } label: {
            buttonLabel(for: format)
        }
        .buttonStyle(.plain)
    }
    
    private func buttonLabel(for format: BitcoinAmountFormat) -> some View {
        HStack(spacing: 15) {
            selectionIndicator(for: format)
            
            HStack(spacing: 8) {
                Text(format.exampleFormat)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(format.displayName)")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 12)
        .background(backgroundForOption(format))
        .overlay(borderForOption(format))
    }
    
    private func selectionIndicator(for format: BitcoinAmountFormat) -> some View {
        Image(systemName: selectedFormat == format ? "checkmark.circle.fill" : "circle")
            .foregroundColor(selectedFormat == format ? .accentColor : .secondary)
            .font(.title3)
    }
    
    private func backgroundForOption(_ format: BitcoinAmountFormat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(selectedFormat == format ? Color.accentColor.opacity(0.1) : Color.clear)
    }
    
    private func borderForOption(_ format: BitcoinAmountFormat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(selectedFormat == format ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
    }
}
