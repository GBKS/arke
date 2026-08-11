//
//  CreateWalletView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//

import SwiftUI
import ArkeUI

struct CreateWalletView: View {
    let isMainnet: Bool
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
                        .foregroundStyle(Color.Arke.gold)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            
            VStack(spacing: 8) {
                Text("firstuse_create_new_wallet")
                    .font(.system(size: 40, design: .serif))
                    .foregroundStyle(Color.Arke.gold)
                
                Text("firstuse_generate_wallet")
                    .font(.system(size: 21))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            
            // TODO: Add wallet creation UI here
            VStack(spacing: 16) {
                if !isMainnet {
                    Text("onboarding_signet_notice")
                        .fontWeight(.light)
                        .font(.system(size: 19))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Text("onboarding_server_notice")
                    .fontWeight(.light)
                    .font(.system(size: 19))
                    .foregroundStyle(.white.opacity(0.7))
                
                Text("onboarding_alpha_notice")
                    .fontWeight(.light)
                    .font(.system(size: 19))
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Color.Arke.red)
                        .font(.system(size: 16))
                        .padding(.bottom, 8)
                }
                
                Button("button_create_wallet") {
                    Task {
                        isCreatingWallet = true
                        errorMessage = nil
                        
                        do {
                            let networkConfig = isMainnet ? NetworkConfig.mainnet : NetworkConfig.signet
                            let result = try await walletManager.createWallet(networkConfig: networkConfig)
                            print("✅ Wallet created on \(networkConfig.name): \(result)")
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
                    ProgressView("progress_creating_wallet")
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.Arke.gold))
                        .foregroundStyle(Color.Arke.gold)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Arke.gold4)
    }
}
