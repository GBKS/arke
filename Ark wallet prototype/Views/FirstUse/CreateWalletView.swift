//
//  CreateWalletView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//

import SwiftUI

struct CreateWalletView: View {
    let onBack: () -> Void
    let onWalletCreated: () -> Void
    let walletManager: WalletManager
    
    @State private var isCreatingWallet = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 30) {
            // Top navigation area
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
                Text("Create New Wallet")
                    .font(.system(size: 40, design: .serif))
                    .foregroundStyle(Color.arkeGold)
                
                Text("We'll now generate a new wallet and recovery phrase for you.")
                    .font(.system(size: 21))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            
            // TODO: Add wallet creation UI here
            VStack(spacing: 16) {
                Text("It's going to be on signet. Not real bitcoin!")
                    .fontWeight(.light)
                    .font(.system(size: 19))
                    .foregroundStyle(.white.opacity(0.7))
                
                Text("It will connect to the Ark Service Provider by second.tech.")
                    .fontWeight(.light)
                    .font(.system(size: 19))
                    .foregroundStyle(.white.opacity(0.7))
                
                Text("This is all alpha and experimental. Play and have fun.")
                    .fontWeight(.light)
                    .font(.system(size: 19))
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.system(size: 16))
                        .padding(.bottom, 8)
                }
                
                Button("Create Wallet") {
                    Task {
                        isCreatingWallet = true
                        errorMessage = nil
                        
                        do {
                            let result = try await walletManager.createWallet()
                            print("✅ Wallet created: \(result)")
                            onWalletCreated()
                        } catch {
                            print("❌ Failed to create wallet: \(error)")
                            errorMessage = "Failed to create wallet: \(error.localizedDescription)"
                        }
                        
                        isCreatingWallet = false
                    }
                }
                .buttonStyle(ArkeButtonStyle(size: .large, isLoading: isCreatingWallet))
                .disabled(isCreatingWallet)
                
                if isCreatingWallet {
                    ProgressView("Creating wallet...")
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.arkeGold))
                        .foregroundStyle(Color.arkeGold)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 800, minHeight: 600)
        .background(Color.arkeDark)
    }
}

#Preview {
    CreateWalletView(
        onBack: {},
        onWalletCreated: {},
        walletManager: WalletManager(useMock: true)
    )
}
