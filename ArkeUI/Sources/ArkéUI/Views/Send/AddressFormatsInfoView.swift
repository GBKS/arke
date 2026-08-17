//
//  AddressFormatsInfoView.swift
//  Arké
//
//  Created by Christoph on 11/17/25.
//

import SwiftUI

public struct AddressFormatsInfoView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "receive_address_formats", defaultValue: "Address formats", bundle: .module))
                        .font(.system(size: 28, design: .serif))
                        .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: 12) {
                        AddressFormatRow(
                            title: String(localized: "address_format_ark_title", defaultValue: "Ark Address", bundle: .module),
                            examples: ["ark1q...", "tark1q..."],
                            description: String(localized: "address_format_ark_description", defaultValue: "Ark protocol addresses for off-chain payments", bundle: .module)
                        )

                        AddressFormatRow(
                            title: String(localized: "address_format_bitcoin_title", defaultValue: "Bitcoin Address", bundle: .module),
                            examples: ["bc1q...", "1...", "3...", "tb1q..."],
                            description: String(localized: "address_format_bitcoin_description", defaultValue: "Standard Bitcoin addresses (P2PKH, P2SH, Bech32)", bundle: .module)
                        )

                        /*
                         AddressFormatRow(
                         title: "Silent Payments (BIP-352)",
                         examples: ["sp1...", "tsp1..."],
                         description: "Privacy-enhanced reusable Bitcoin addresses"
                         )
                         */

                        AddressFormatRow(
                            title: String(localized: "address_format_bip353_title", defaultValue: "BIP-353 Address", bundle: .module),
                            examples: ["₿user.domain.com"],
                            description: String(localized: "address_format_bip353_description", defaultValue: "Human-readable Bitcoin addresses using DNS", bundle: .module)
                        )

                        AddressFormatRow(
                            title: String(localized: "address_format_lightning_address_title", defaultValue: "Lightning Address", bundle: .module),
                            examples: ["user@domain.com"],
                            description: String(localized: "address_format_lightning_address_description", defaultValue: "Human-readable Lightning payment addresses", bundle: .module)
                        )

                        AddressFormatRow(
                            title: String(localized: "address_format_lightning_invoice_title", defaultValue: "Lightning Invoice", bundle: .module),
                            examples: ["lnbc...", "lntb..."],
                            description: String(localized: "address_format_lightning_invoice_description", defaultValue: "Lightning network payment requests", bundle: .module)
                        )

                        AddressFormatRow(
                            title: String(localized: "address_format_bip21_title", defaultValue: "BIP-21 Payment URI", bundle: .module),
                            examples: ["bitcoin:bc1q...?amount=0.001"],
                            description: String(localized: "address_format_bip21_description", defaultValue: "Bitcoin URIs with embedded payment details", bundle: .module)
                        )
                    }
                    
                    Text(String(localized: "data_network_support_note", defaultValue: "Note: Network support includes mainnet, testnet, signet, and regtest where applicable.", bundle: .module))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel(Text(L10n.buttonClose))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct AddressFormatRow: View {
    let title: String
    let examples: [String]
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(examples, id: \.self) { example in
                    Text(example)
                        .font(.system(.callout, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
        // Combine title, description, and example chips into a single
        // VoiceOver element so the row reads coherently instead of
        // announcing each example token character by character.
        .accessibilityElement(children: .combine)
    }
}

#Preview("Address Formats Info") {
    AddressFormatsInfoView()
}

#Preview("Single Address Format Row") {
    AddressFormatRow(
        title: "Bitcoin Address",
        examples: ["bc1q...", "1...", "3...", "tb1q..."],
        description: "Standard Bitcoin addresses (P2PKH, P2SH, Bech32)"
    )
    .padding()
}
