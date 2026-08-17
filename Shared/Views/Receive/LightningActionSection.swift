//
//  LightningActionSection.swift
//  Ark wallet prototype
//
//  Created by Christoph on 12/03/25.
//

import SwiftUI
import ArkeUI

struct LightningActionSection: View {
    let amount: String
    let lightningInvoice: String?
    let isGeneratingInvoice: Bool
    let onCreateInvoice: () -> Void
    let onShowQRCode: () -> Void
    let extractInvoiceFromJSON: (String) -> String
    
    var body: some View {
        VStack(spacing: 12) {
            if lightningInvoice == nil {
                // Create Invoice button
                Button {
                    onCreateInvoice()
                } label: {
                    HStack(spacing: 6) {
                        if isGeneratingInvoice {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(isGeneratingInvoice ? String(localized: "status_creating_invoice", defaultValue: "Creating Invoice...") : String(localized: "button_create_invoice", defaultValue: "Create Invoice"))
                    }
                }
                .buttonStyle(ArkeButtonStyle(size: ArkeButtonSize.medium))
                .controlSize(.large)
                .disabled(amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGeneratingInvoice)
            } else {
                // Share and QR buttons for generated invoice
                HStack(spacing: 12) {
                    if let rawInvoice = lightningInvoice {
                        let actualInvoice = extractInvoiceFromJSON(rawInvoice)
                        
                        ShareLink(item: actualInvoice) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                Text(L10n.buttonShare)
                            }
                        }
                        .buttonStyle(ArkeButtonStyle(size: .medium))
                        .controlSize(.large)
                    }
                    
                    Button {
                        onShowQRCode()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "qrcode")
                        }
                    }
                    .buttonStyle(ArkeIconButtonStyle(size: ArkeIconButtonSize.medium, variant: ArkeButtonVariant.ghost))
                }
            }
        }
    }
}
