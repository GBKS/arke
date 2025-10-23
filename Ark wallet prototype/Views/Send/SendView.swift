//
//  SendView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import AppKit

// MARK: - Color Extension
extension Color {
    init(r: Double, g: Double, b: Double, opacity: Double = 1.0) {
        self.init(red: r/255.0, green: g/255.0, blue: b/255.0, opacity: opacity)
    }
}

struct ModalState: Identifiable {
    let id = UUID()
    let state: SendModalState
}

struct SendView: View {
    @Environment(WalletManager.self) private var manager
    @Environment(\.dismiss) var dismiss
    
    @State private var recipient = ""
    @State private var amount = ""
    @State private var error: String?
    @State private var sendModalState: SendModalState?
    @State private var clipboardAddress: String?
    @State private var showClipboardPrompt = false
    
    // MARK: - Computed Properties for Balance Display
    
    /// Returns the maximum spendable amount based on the recipient address type
    private var maxSpendableAmount: Int {
        if recipient.isEmpty {
            return manager.totalBalance?.totalSpendableSat ?? 0
        } else if isBitcoinAddress(recipient) {
            return manager.onchainBalance?.trustedSpendableSat ?? 0
        } else {
            return manager.arkBalance?.spendableSat ?? 0
        }
    }
    
    /// Returns the appropriate balance text based on the recipient address type
    private var availableBalanceText: String {
        if recipient.isEmpty {
            return "Available: \(manager.totalBalance?.totalSpendableSat.formatted() ?? "0") ₿ (Total balance)"
        } else if isBitcoinAddress(recipient) {
            let balance = manager.onchainBalance?.trustedSpendableSat ?? 0
            return "Available: \(balance.formatted()) ₿ (Savings balance)"
        } else {
            let balance = manager.arkBalance?.spendableSat ?? 0
            return "Available: \(balance.formatted()) ₿ (Spending balance)"
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recipient")
                        .font(.title2)
                    
                    TextField("ark1q... or bc1q...", text: $recipient)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(16)
                        .font(.system(.title2, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Amount in satoshis (at least 330)")
                        .font(.title2)
                    
                    HStack {
                        TextField("0", text: $amount)
                            .textFieldStyle(.plain)
                            .font(.title2)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(16)
                        Text("₿")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Button(availableBalanceText) {
                            amount = "\(maxSpendableAmount)"
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .buttonStyle(.plain)
                        .disabled(maxSpendableAmount == 0)
                        
                        Spacer()
                    }
                }
                
                if let error = error {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Button("Send") {
                    sendPayment()
                }
                .buttonStyle(ArkeButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(sendModalState != nil || recipient.isEmpty || amount.isEmpty)
                .padding(.top, 16)
                
                Text("Fee calculation is not implemented yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Send bitcoin")
        .onAppear {
            checkClipboardForAddress()
        }
        .alert("Use clipboard address?", isPresented: $showClipboardPrompt) {
            Button("Use Address") {
                if let address = clipboardAddress {
                    recipient = address
                }
                clipboardAddress = nil
            }
            Button("Cancel", role: .cancel) {
                clipboardAddress = nil
            }
        } message: {
            if let address = clipboardAddress {
                let addressType = isBitcoinAddress(address) ? "Bitcoin" : "Ark"
                Text("Found \(addressType) address in clipboard:\n\(address)")
            }
        }
        .sheet(item: Binding(
            get: { sendModalState.map { ModalState(state: $0) } },
            set: { _ in sendModalState = nil }
        )) { modalState in
            SendModalView(state: modalState.state)
        }
    }
    
    func sendPayment() {
        guard let amountInt = Int(amount) else {
            error = "Invalid amount"
            return
        }
        
        // Validate against the appropriate balance
        if amountInt > maxSpendableAmount {
            if isBitcoinAddress(recipient) {
                error = "Amount exceeds onchain balance (\(maxSpendableAmount.formatted()) sats)"
            } else {
                error = "Amount exceeds ark balance (\(maxSpendableAmount.formatted()) sats)"
            }
            return
        }
        
        sendModalState = .sending
        error = nil
        
        Task {
            do {
                if isBitcoinAddress(recipient) {
                    _ = try await manager.sendOnchain(to: recipient, amount: amountInt)
                } else {
                    _ = try await manager.send(to: recipient, amount: amountInt)
                }
                sendModalState = .success
                // Dismiss after a brief delay to show success state
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            } catch {
                sendModalState = .error(error.localizedDescription)
                self.error = error.localizedDescription
            }
        }
    }
    
    /// Determines if the address is a Bitcoin network address (taproot, segwit, etc.)
    private func isBitcoinAddress(_ address: String) -> Bool {
        // Bitcoin address patterns
        let bitcoinPatterns = [
            "^bc1[a-z0-9]{39,59}$",  // Bech32 (segwit v0 and v1/taproot mainnet)
            "^tb1[a-z0-9]{39,59}$",  // Bech32 (segwit testnet)
            "^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$", // Legacy P2PKH and P2SH mainnet
            "^[2mn][a-km-zA-HJ-NP-Z1-9]{25,34}$" // Legacy testnet
        ]
        
        for pattern in bitcoinPatterns {
            if address.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        return false
    }
    
    /// Determines if the address is an Ark address
    private func isArkAddress(_ address: String) -> Bool {
        // Ark address pattern - starts with "ark1" followed by alphanumeric characters
        let arkPattern = "^ark1[a-z0-9]+$"
        return address.range(of: arkPattern, options: .regularExpression) != nil
    }
    
    /// Checks if the address is either a Bitcoin or Ark address
    private func isValidAddress(_ address: String) -> Bool {
        return isBitcoinAddress(address) || isArkAddress(address)
    }
    
    /// Checks clipboard for valid Bitcoin or Ark addresses
    private func checkClipboardForAddress() {
        // Only check if recipient field is empty
        guard recipient.isEmpty else { return }
        
        guard let clipboardString = NSPasteboard.general.string(forType: .string) else { return }
        
        let trimmedString = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if clipboard contains a valid address
        if isValidAddress(trimmedString) {
            clipboardAddress = trimmedString
            showClipboardPrompt = true
        }
    }
}

#Preview {
    NavigationStack {
        SendView()
            .environment(WalletManager())
    }
}
