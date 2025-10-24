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
    @State private var clipboardAddress: ParsedAddress?
    
    // MARK: - Computed Properties for Balance Display
    
    /// Returns the maximum spendable amount based on the recipient address type
    private var maxSpendableAmount: Int {
        if recipient.isEmpty {
            return manager.totalBalance?.totalSpendableSat ?? 0
        } else if AddressValidator.isBitcoinAddress(recipient) {
            return manager.onchainBalance?.trustedSpendableSat ?? 0
        } else {
            return manager.arkBalance?.spendableSat ?? 0
        }
    }
    
    /// Returns the appropriate balance text based on the recipient address type
    private var availableBalanceText: String {
        if recipient.isEmpty {
            let formattedBalance = BitcoinFormatter.formatAmount(manager.totalBalance?.totalSpendableSat ?? 0)
            return "Available: \(formattedBalance) (Total balance)"
        } else if AddressValidator.isBitcoinAddress(recipient) {
            let balance = manager.onchainBalance?.trustedSpendableSat ?? 0
            let formattedBalance = BitcoinFormatter.formatAmount(balance)
            return "Available: \(formattedBalance) (Savings balance)"
        } else {
            let balance = manager.arkBalance?.spendableSat ?? 0
            let formattedBalance = BitcoinFormatter.formatAmount(balance)
            return "Available: \(formattedBalance) (Spending balance)"
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Clipboard prompt banner
                if let parsedAddress = clipboardAddress {
                    ClipboardAddressBanner(
                        parsedAddress: parsedAddress,
                        onUseAddress: {
                            recipient = parsedAddress.address
                            // Pre-fill amount if it's a BIP-21 URI with amount
                            if let bip21Amount = parsedAddress.amount {
                                amount = "\(bip21Amount)"
                            }
                            clipboardAddress = nil
                        },
                        onDismiss: {
                            clipboardAddress = nil
                        }
                    )
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recipient")
                        .font(.title2)
                    
                    TextField("ark1q..., bc1q..., user@domain.com, or ₿user.domain.com", text: $recipient)
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
                    ErrorView(
                        errorMessage: error,
                        onRetry: {
                            sendPayment()
                        },
                        onDismiss: {
                            self.error = nil
                        }
                    )
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
            .frame(maxWidth: 600)
            .padding()
        }
        .navigationTitle("Send bitcoin")
        .onAppear {
            checkClipboardForAddress()
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
            if AddressValidator.isBitcoinAddress(recipient) {
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
                if AddressValidator.isBitcoinAddress(recipient) {
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
    
    /// Checks clipboard for valid Bitcoin, Ark, Lightning, BIP-353, or BIP-21 addresses
    private func checkClipboardForAddress() {
        // Only check if recipient field is empty
        guard recipient.isEmpty else { return }
        
        guard let clipboardString = NSPasteboard.general.string(forType: .string) else { return }
        
        let trimmedString = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if clipboard contains a valid address
        if let parsedAddress = AddressValidator.parseAddress(trimmedString) {
            clipboardAddress = parsedAddress
        }
    }
}

#Preview {
    NavigationStack {
        SendView()
            .environment(WalletManager())
    }
}
