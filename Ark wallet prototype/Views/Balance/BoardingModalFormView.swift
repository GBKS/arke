//
//  BoardingModalFormView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/19/25.
//

import SwiftUI

struct BoardingModalFormView: View {
    @State private var amountText: String = ""
    let errorMessage: String?
    let isLoading: Bool
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void
    
    private var enteredAmount: Int? {
        Int(amountText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private var isValidAmount: Bool {
        guard let amount = enteredAmount else { return false }
        return amount > 0
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 25) {
            Image("board")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: 150, maxHeight: .infinity)
                .cornerRadius(15)
                .clipped()
            
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transfer to payments")
                        .font(.system(size: 24, design: .serif))
                    
                    Text("Move funds to the Ark network for fast and low-fee payments.")
                        .font(.default)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Amount in satoshis")
                        .font(.headline)
                        .fontWeight(.medium)
                    
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
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
            }
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Confirm") {
                    if let amount = enteredAmount {
                        onConfirm(amount)
                    }
                }
                .disabled(!isValidAmount || isLoading)
            }
        }
    }
}

#Preview {
    BoardingModalFormView(
        errorMessage: nil,
        isLoading: false,
        onConfirm: { amount in
            print("Boarding \(amount) sats")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}
