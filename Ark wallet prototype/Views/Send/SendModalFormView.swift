//
//  SendModalFormView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI

struct SendModalFormView: View {
    let manager: WalletManager
    @State private var recipientText: String = ""
    @State private var amountText: String = ""
    let errorMessage: String?
    let isLoading: Bool
    let onConfirm: (String, Int) -> Void
    let onCancel: () -> Void
    
    private var enteredAmount: Int? {
        Int(amountText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private var isValidInput: Bool {
        guard let amount = enteredAmount else { return false }
        return amount > 0 && !recipientText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Send Bitcoin")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Send bitcoin to an Ark address or on-chain Bitcoin address.")
                    .font(.default)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Recipient")
                    .font(.headline)
                    .fontWeight(.medium)
                
                TextField("ark1q... or bc1q...", text: $recipientText)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(16)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Amount in satoshis")
                    .font(.headline)
                    .fontWeight(.medium)
                
                HStack {
                    TextField("Enter amount", text: $amountText)
                        .textFieldStyle(.plain)
                        .font(.title)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(16)
                        .onChange(of: amountText) { oldValue, newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            if filtered != newValue {
                                amountText = filtered
                            }
                        }
                    
                    Text("₿")
                        .foregroundColor(.secondary)
                        .font(.title2)
                        .padding(.trailing, 8)
                }
                
                if let totalBalance = manager.totalBalance {
                    HStack {
                        Text("Available: \(totalBalance.totalSpendableSat.formatted()) sats")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Max") {
                            amountText = "\(totalBalance.totalSpendableSat)"
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Send") {
                    if let amount = enteredAmount {
                        onConfirm(recipientText.trimmingCharacters(in: .whitespacesAndNewlines), amount)
                    }
                }
                .disabled(!isValidInput || isLoading)
            }
        }
    }
}

#Preview {
    SendModalFormView(
        manager: WalletManager(useMock: true),
        errorMessage: nil,
        isLoading: false,
        onConfirm: { recipient, amount in
            print("Sending \(amount) sats to \(recipient)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}