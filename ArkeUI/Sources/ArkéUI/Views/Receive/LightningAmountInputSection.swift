//
//  LightningAmountInputSection.swift
//  Ark wallet prototype
//
//  Created by Christoph on 12/03/25.
//

import SwiftUI

public struct LightningAmountInputSection: View {
    @Binding var amount: String
    @Binding var note: String
    let lightningInvoice: String?
    let invoiceError: String?
    let onAmountChange: () -> Void
    let onNoteChange: () -> Void
    let onInvoiceTap: () -> Void
    let showCopySuccess: Bool

    public init(
        amount: Binding<String>,
        note: Binding<String>,
        lightningInvoice: String?,
        invoiceError: String?,
        onAmountChange: @escaping () -> Void,
        onNoteChange: @escaping () -> Void,
        onInvoiceTap: @escaping () -> Void,
        showCopySuccess: Bool
    ) {
        self._amount = amount
        self._note = note
        self.lightningInvoice = lightningInvoice
        self.invoiceError = invoiceError
        self.onAmountChange = onAmountChange
        self.onNoteChange = onNoteChange
        self.onInvoiceTap = onInvoiceTap
        self.showCopySuccess = showCopySuccess
    }

    public var body: some View {
        VStack(spacing: 12) {
            if lightningInvoice == nil {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        TextField(String(localized: "placeholder_amount_required"), text: $amount)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.plain)
                            .padding(.leading, 25)
                            .padding(.vertical, 12)
                            .onChange(of: amount) { _, _ in
                                onAmountChange()
                            }
                        Spacer()
                        Text("symbol_bitcoin")
                            .font(.system(.body, design: .monospaced))
                            .padding(.trailing, 25)
                    }
                    
                    if !note.isEmpty || lightningInvoice == nil {
                        Divider()
                            .padding(.horizontal, 25)
                        
                        HStack(spacing: 8) {
                            TextField(String(localized: "placeholder_note_optional"), text: $note)
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 25)
                                .padding(.vertical, 12)
                                .onChange(of: note) { _, _ in
                                    onNoteChange()
                                }
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            
            // Show generated invoice if available
            if let invoice = lightningInvoice {
                lightningInvoiceDisplay(invoice)
                    .transition(.opacity.combined(with: .slide))
            }
            
            // Show error if any
            if let error = invoiceError {
                Text(error)
                    .foregroundColor(.Arke.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func lightningInvoiceDisplay(_ invoice: String) -> some View {
        let actualInvoice = extractInvoiceFromJSON(invoice)
        
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.Arke.green)
                Text("status_invoice_generated")
                    .font(.title2)
                    .multilineTextAlignment(.center)
            }
            
            Text(actualInvoice)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial)
                .cornerRadius(6)
                .onTapGesture {
                    onInvoiceTap()
                }
            
            Text(showCopySuccess ? String(localized: "status_copied_exclaim") : String(localized: "action_tap_copy"))
                .font(.caption2)
                .foregroundColor(showCopySuccess ? .Arke.green : .secondary)
        }
        .padding(.horizontal, 25)
        .padding(.vertical, 20)
    }
    
    // MARK: - Helper Methods
    
    private func extractInvoiceFromJSON(_ input: String) -> String {
        // First, try to parse as JSON
        if let data = input.data(using: .utf8) {
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let invoice = json["invoice"] as? String {
                    return invoice
                }
            } catch {
                // If JSON parsing fails, treat as plain string
                print("Failed to parse Lightning invoice as JSON, using as plain string: \(error)")
            }
        }
        
        // If not JSON or parsing failed, return the original string
        return input
    }
}

#Preview("No Invoice") {
    @Previewable @State var amount = ""
    @Previewable @State var note = ""
    
    LightningAmountInputSection(
        amount: $amount,
        note: $note,
        lightningInvoice: nil,
        invoiceError: nil,
        onAmountChange: {},
        onNoteChange: {},
        onInvoiceTap: {},
        showCopySuccess: false
    )
    .frame(width: 400)
    .padding()
}

#Preview("With Invoice") {
    @Previewable @State var amount = "10000"
    @Previewable @State var note = "Test payment"
    
    LightningAmountInputSection(
        amount: $amount,
        note: $note,
        lightningInvoice: "{\"invoice\":\"lnbc100n1p3xyxa...\"}",
        invoiceError: nil,
        onAmountChange: {},
        onNoteChange: {},
        onInvoiceTap: {},
        showCopySuccess: false
    )
    .frame(width: 400)
    .padding()
}

#Preview("With Error") {
    @Previewable @State var amount = "999999999"
    @Previewable @State var note = ""
    
    LightningAmountInputSection(
        amount: $amount,
        note: $note,
        lightningInvoice: nil,
        invoiceError: "Amount too large. Maximum is 10,000,000 sats",
        onAmountChange: {},
        onNoteChange: {},
        onInvoiceTap: {},
        showCopySuccess: false
    )
    .frame(width: 400)
    .padding()
}
