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
                    Text("receive_address_formats", bundle: .module)
                        .font(.system(size: 28, design: .serif))
                        .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: 12) {
                        AddressFormatRow(
                            title: "address_format_ark_title",
                            examples: ["ark1q...", "tark1q..."],
                            description: "address_format_ark_description"
                        )

                        AddressFormatRow(
                            title: "address_format_bitcoin_title",
                            examples: ["bc1q...", "1...", "3...", "tb1q..."],
                            description: "address_format_bitcoin_description"
                        )

                        /*
                         AddressFormatRow(
                         title: "Silent Payments (BIP-352)",
                         examples: ["sp1...", "tsp1..."],
                         description: "Privacy-enhanced reusable Bitcoin addresses"
                         )
                         */

                        AddressFormatRow(
                            title: "address_format_bip353_title",
                            examples: ["₿user.domain.com"],
                            description: "address_format_bip353_description"
                        )

                        AddressFormatRow(
                            title: "address_format_lightning_address_title",
                            examples: ["user@domain.com"],
                            description: "address_format_lightning_address_description"
                        )

                        AddressFormatRow(
                            title: "address_format_lightning_invoice_title",
                            examples: ["lnbc...", "lntb..."],
                            description: "address_format_lightning_invoice_description"
                        )

                        AddressFormatRow(
                            title: "address_format_bip21_title",
                            examples: ["bitcoin:bc1q...?amount=0.001"],
                            description: "address_format_bip21_description"
                        )
                    }
                    
                    Text("data_network_support_note", bundle: .module)
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
                    .accessibilityLabel(Text("button_close", bundle: .module))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct AddressFormatRow: View {
    let title: LocalizedStringKey
    let examples: [String]
    let description: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title, bundle: .module)
                    .font(.body)
                    .fontWeight(.semibold)

                Text(description, bundle: .module)
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
