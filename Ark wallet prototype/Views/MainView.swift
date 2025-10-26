//
//  MainView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import SwiftData

struct MainView: View {
    @State private var hasWallet: Bool = false
    @State private var isCheckingWallet: Bool = true
    @State private var walletManager = WalletManager()
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Group {
            if isCheckingWallet {
                // Show loading state while checking for wallet
                LoadingView()
            } else if hasWallet {
                // Main application UI when wallet exists
                WalletView(onWalletDeleted: {
                    // Reset state to show onboarding flow
                    hasWallet = false
                })
                .environment(walletManager)
            } else {
                // Onboarding sequence when no wallet found
                OnboardingFlow(onWalletReady: {
                    Task {
                        // Initialize the wallet after creation
                        await walletManager.initialize()
                        hasWallet = true
                    }
                })
            }
        }
        .task {
            // Set model context first, then check for existing wallet
            walletManager.setModelContext(modelContext)
            await checkForExistingWallet()
        }
    }
    
    private func checkForExistingWallet() async {
        do {
            // Try to get the mnemonic from the wallet
            // If this succeeds, a wallet already exists
            _ = try await walletManager.getMnemonic()
            print("✅ Existing wallet found")
            hasWallet = true
        } catch {
            // If getMnemonic fails, no wallet exists yet
            print("ℹ️ No existing wallet found: \(error)")
            hasWallet = false
        }
        
        isCheckingWallet = false
    }
}

#Preview {
    MainView()
}
