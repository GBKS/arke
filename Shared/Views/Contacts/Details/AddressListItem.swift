//
//  AddressListItem.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/5/25.
//

import SwiftUI
import ArkeUI

#if os(macOS)
import AppKit
#endif

struct AddressListItem: View {
    let address: ContactAddressModel
    let isEditable: Bool
    let onEdit: () -> Void
    let onSetPrimary: () -> Void
    let onSendTo: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Send button
                Button(action: onSendTo) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .accessibilityLabel(L10n.actionSendAddress)
                #if os(macOS)
                .help(L10n.actionSendAddress)
                #endif
                
                // Address info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(address.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                        
                        if address.isPrimary {
                            Image(systemName: "star.fill")
                                .font(.caption)
                        }
                    }
                    
                    // Address
                    Text(address.shortAddress)
                        .font(.body.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Edit button
                if isEditable {
                    Button(action: onEdit) {
                        Image(systemName: "paintbrush.pointed.fill")
                            .font(.body)
                            .tint(Color.Arke.gold4)
                    }
                    .accessibilityLabel(L10n.actionEditAddress)
                    .buttonStyle(.bordered)
                    #if os(macOS)
                    .help(L10n.actionEditAddress)
                    #endif
                }
            }
            .padding(.vertical, 8)
        }
        /*
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #else
        .background(Color(.secondarySystemBackground))
        #endif
        */
        .cornerRadius(8)
        .contextMenu {
            Button(action: copyAddress) {
                Label(String(localized: "action_copy", defaultValue: "Copy"), systemImage: "doc.on.doc")
            }
            
            if isEditable && !address.isPrimary {
                Button(action: onSetPrimary) {
                    Label(String(localized: "button_set_primary", defaultValue: "Set as Primary"), systemImage: "star.fill")
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func copyAddress() {
        copyToClipboard(address.address)
        print("📋 Copied address to clipboard: \(address.shortAddress)")
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
    
    private func networkColor(for network: BitcoinNetwork) -> Color {
        switch network {
        case .mainnet:
            return .Arke.green
        case .testnet, .signet:
            return .Arke.orange
        case .regtest:
            return .Arke.purple
        }
    }
}
