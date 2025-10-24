//
//  ClipboardAddressBanner.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//

import SwiftUI

struct ClipboardAddressBanner: View {
    let parsedAddress: ParsedAddress
    let onUseAddress: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Address found in clipboard")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("\(parsedAddress.type.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                    
                    Text(parsedAddress.originalString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    // Show additional info for BIP-21 URIs
                    if parsedAddress.type == .bip21 {
                        VStack(alignment: .leading, spacing: 2) {
                            if let amount = parsedAddress.amount {
                                Text("Amount: \(amount) sats")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if let label = parsedAddress.label {
                                Text("Label: \(label)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if let message = parsedAddress.message {
                                Text("Message: \(message)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            HStack {
                Button("Use Address") {
                    onUseAddress()
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            // Bitcoin address
            if let parsed = AddressValidator.parseAddress("bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh") {
                ClipboardAddressBanner(
                    parsedAddress: parsed,
                    onUseAddress: { print("Use Bitcoin address") },
                    onDismiss: { print("Dismiss") }
                )
            }
            
            // Lightning address
            if let parsed = AddressValidator.parseAddress("user@lightning.network") {
                ClipboardAddressBanner(
                    parsedAddress: parsed,
                    onUseAddress: { print("Use Lightning address") },
                    onDismiss: { print("Dismiss") }
                )
            }
            
            // BIP-21 URI with amount
            if let parsed = AddressValidator.parseAddress("bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh?amount=0.00100000&label=Test%20Payment") {
                ClipboardAddressBanner(
                    parsedAddress: parsed,
                    onUseAddress: { print("Use BIP-21 URI") },
                    onDismiss: { print("Dismiss") }
                )
            }
            
            // BIP-353 address
            if let parsed = AddressValidator.parseAddress("₿user.example.com") {
                ClipboardAddressBanner(
                    parsedAddress: parsed,
                    onUseAddress: { print("Use BIP-353 address") },
                    onDismiss: { print("Dismiss") }
                )
            }
        }
        .padding()
    }
}
