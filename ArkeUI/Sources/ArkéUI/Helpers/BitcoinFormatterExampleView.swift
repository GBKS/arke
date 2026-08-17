//
//  BitcoinFormatterExampleView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/13/25.
//

import SwiftUI

/// A demonstration view showing how different Bitcoin amounts are formatted
/// across all four format types. Useful for testing and documentation.
struct BitcoinFormatterExampleView: View {
    
    @AppStorage(BitcoinAmountFormat.userDefaultsKey)
    private var selectedFormat: BitcoinAmountFormat = .defaultFormat
    
    private let exampleAmounts: [(label: String, sats: Int)] = [
        ("1 satoshi", 1),
        ("100 sats", 100),
        ("1,000 sats", 1_000),
        ("10,000 sats", 10_000),
        ("100,000 sats (0.001 BTC)", 100_000),
        ("1,000,000 sats (0.01 BTC)", 1_000_000),
        ("10,000,000 sats (0.1 BTC)", 10_000_000),
        ("1 BTC", 100_000_000),
        ("21 BTC", 2_100_000_000),
        ("21 Million BTC (max supply)", 2_100_000_000_000_000),
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                
                Divider()
                
                currentFormatSection
                
                Divider()
                
                examplesSection
                
                Divider()
                
                transactionExamplesSection
            }
            .padding()
        }
        .navigationTitle(String(localized: "nav_title_bitcoin_formatter_examples", defaultValue: "Bitcoin Formatter Demo", bundle: .module))
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "nav_title_bitcoin_formatter_examples", defaultValue: "Bitcoin Formatter Demo", bundle: .module))
                .font(.system(size: 28, weight: .bold, design: .serif))

            Text(String(localized: "description_bitcoin_formatter_demo", defaultValue: "This view demonstrates how Bitcoin amounts are formatted based on your selected format preference and system locale.", bundle: .module))
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Current Format Section
    
    private var currentFormatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "label_current_format", defaultValue: "Current Format", bundle: .module))
                .font(.headline)

            HStack {
                Text(String(localized: "label_selected", defaultValue: "Selected:", bundle: .module))
                    .foregroundColor(.secondary)
                Text(selectedFormat.displayName)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(localized: "format_example_with_placeholder %@", defaultValue: "Example: \(selectedFormat.exampleFormat)", bundle: .module))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(String(localized: "hint_change_settings_formats", defaultValue: "Change in Settings to see different formats", bundle: .module))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Examples Section
    
    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "label_amount_examples", defaultValue: "Amount Examples", bundle: .module))
                .font(.headline)
            
            ForEach(exampleAmounts, id: \.sats) { example in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(example.label)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(BitcoinFormatter.shared.formatAmount(example.sats))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    // MARK: - Transaction Examples Section
    
    private var transactionExamplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "label_transaction_formatting_examples", defaultValue: "Transaction Formatting Examples", bundle: .module))
                .font(.headline)

            Text(String(localized: "format_with_sign_prefixes", defaultValue: "With Sign Prefixes", bundle: .module))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Group {
                HStack {
                    Text(String(localized: "label_received", defaultValue: "Received:", bundle: .module))
                        .frame(width: 100, alignment: .leading)
                    Text(BitcoinFormatter.shared.formatTransactionAmount(
                        1_000_000,
                        transactionType: .received
                    ))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                    Spacer()
                }
                
                HStack {
                    Text(String(localized: "label_sent", defaultValue: "Sent:", bundle: .module))
                        .frame(width: 100, alignment: .leading)
                    Text(BitcoinFormatter.shared.formatTransactionAmount(
                        1_000_000,
                        transactionType: .sent
                    ))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.red)
                    Spacer()
                }
            }

            Divider()
                .padding(.vertical, 8)

            Text(String(localized: "format_accounting_style", defaultValue: "Accounting Style (Symbol at End)", bundle: .module))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Group {
                HStack {
                    Text(String(localized: "label_received", defaultValue: "Received:", bundle: .module))
                        .frame(width: 100, alignment: .leading)
                    Text(BitcoinFormatter.shared.formatAccountingAmount(
                        5_000_000,
                        transactionType: .received
                    ))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                    Spacer()
                }
                
                HStack {
                    Text(String(localized: "label_sent", defaultValue: "Sent:", bundle: .module))
                        .frame(width: 100, alignment: .leading)
                    Text(BitcoinFormatter.shared.formatAccountingAmount(
                        5_000_000,
                        transactionType: .sent
                    ))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.red)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BitcoinFormatterExampleView()
    }
}

#Preview("With Different Format") {
    NavigationStack {
        BitcoinFormatterExampleView()
    }
    .onAppear {
        UserDefaults.standard.set(
            BitcoinAmountFormat.satoshis.rawValue,
            forKey: BitcoinAmountFormat.userDefaultsKey
        )
    }
}
