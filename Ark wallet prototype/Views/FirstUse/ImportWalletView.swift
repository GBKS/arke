//
//  ImportWalletView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//

import SwiftUI
import Foundation

struct ImportWalletView: View {
    let onBack: () -> Void
    let onWalletImported: () -> Void
    
    @Environment(WalletManager.self) private var walletManager
    @State private var mnemonicPhrase: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isImporting = false
    
    var body: some View {
        VStack(spacing: 30) {
            HStack {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.arkeGold)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            
            VStack(spacing: 8) {
                Text("Import Wallet")
                    .font(.system(size: 40, design: .serif))
                    .foregroundStyle(Color.arkeGold)
                
                Text("Restore your existing wallet with your 12-word recovery phrase.")
                    .fontWeight(.light)
                    .font(.system(size: 21))
                    .lineSpacing(6)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            
            TextEditor(text: $mnemonicPhrase)
                .padding(15)
                .scrollContentBackground(.hidden)
                .background(Color.primary.opacity(0.05))
                .foregroundStyle(.white)
                .font(.system(size: 21, design: .monospaced))
                .lineSpacing(4)
                .cornerRadius(8)
                .overlay(alignment: .topLeading) {
                    if mnemonicPhrase.isEmpty {
                        Text("Enter your 12-words here...")
                            .foregroundStyle(.gray)
                            .font(.system(size: 21, design: .monospaced))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 15)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.arkeGold.opacity(0.2), lineWidth: 1)
                )
                .frame(maxWidth: 400, minHeight: 80, maxHeight: 130)
            
            Spacer()            
            
            Button(isImporting ? "Importing..." : "Import Wallet") {
                Task {
                    await importWallet()
                }
            }
            .buttonStyle(ArkeButtonStyle(size: .large, isLoading: isImporting))
            .disabled(mnemonicPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 800, minHeight: 600)
        .background(Color.arkeDark)
        .alert("Import Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func importWallet() async {
        let trimmedMnemonic = mnemonicPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Basic validation
        guard !trimmedMnemonic.isEmpty else {
            showError("Please enter a recovery phrase")
            return
        }
        
        isImporting = true
        defer { isImporting = false }
        
        do {
            // Use WalletManager to import the wallet
            let result = try await walletManager.importWallet(mnemonic: trimmedMnemonic)
            print("✅ Wallet imported successfully: \(result)")
            
            // Success - call the completion handler
            onWalletImported()
            
        } catch {
            showError("Failed to import wallet: \(error.localizedDescription)")
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

#Preview {
    ImportWalletView(
        onBack: {},
        onWalletImported: {}
    )
    .environment(WalletManager(useMock: true))
}
