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
                    Text("receive_address_formats")
                        .font(.system(size: 28, design: .serif))
                    
                    VStack(alignment: .leading, spacing: 12) {
                        AddressFormatRow(
                            title: "Ark Address",
                            examples: ["ark1q...", "tark1q..."],
                            description: "Ark protocol addresses for off-chain payments"
                        )
                        
                        AddressFormatRow(
                            title: "Bitcoin Address",
                            examples: ["bc1q...", "1...", "3...", "tb1q..."],
                            description: "Standard Bitcoin addresses (P2PKH, P2SH, Bech32)"
                        )
                        
                        /*
                         AddressFormatRow(
                         title: "Silent Payments (BIP-352)",
                         examples: ["sp1...", "tsp1..."],
                         description: "Privacy-enhanced reusable Bitcoin addresses"
                         )
                         */
                        
                        AddressFormatRow(
                            title: "BIP-353 Address",
                            examples: ["₿user.domain.com"],
                            description: "Human-readable Bitcoin addresses using DNS"
                        )
                        
                        AddressFormatRow(
                            title: "Lightning Address",
                            examples: ["user@domain.com"],
                            description: "Human-readable Lightning payment addresses"
                        )
                        
                        AddressFormatRow(
                            title: "Lightning Invoice",
                            examples: ["lnbc...", "lntb..."],
                            description: "Lightning network payment requests"
                        )
                        
                        AddressFormatRow(
                            title: "BIP-21 Payment URI",
                            examples: ["bitcoin:bc1q...?amount=0.001"],
                            description: "Bitcoin URIs with embedded payment details"
                        )
                    }
                    
                    Text(String(localized: "data_network_support_note"))
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
