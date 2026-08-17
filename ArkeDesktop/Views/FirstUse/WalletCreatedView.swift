//
//  WalletCreatedView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/26/25.
//

import SwiftUI
import ArkeUI

struct WalletCreatedView: View {
    let onContinue: () -> Void
    let onShowRecoveryPhrase: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            // Success icon and title
            VStack(spacing: 24) {
                // Success checkmark
                ZStack {
                    Circle()
                        .fill(Color.Arke.gold.opacity(0.2))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.Arke.gold)
                }
                
                VStack(spacing: 8) {
                    Text(String(localized: "onboarding_ready_bitcoin", defaultValue: "You are ready for bitcoin!"))
                        .font(.system(size: 40, design: .serif))
                        .foregroundStyle(Color.Arke.gold)
                    
                    Text(String(localized: "onboarding_wallet_ready", defaultValue: "Your new wallet is ready to use."))
                        .font(.system(size: 21))
                        .lineSpacing(6)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)

                    Text(String(localized: "onboarding_backup_reminder", defaultValue: "Make sure to make a backup. You're in control of this wallet, and also responsible for it."))
                        .font(.system(size: 21))
                        .lineSpacing(6)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }
            
            Spacer()
            
            Button {
                onContinue()
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 27))
                    .foregroundStyle(Color.Arke.gold4)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Color.Arke.gold)
            .accessibilityLabel(L10n.accessibilityContinueToWallet)
            .accessibilityHint(L10n.accessibilityWalletReadyHint)
        }
        .padding(.horizontal, 40)
        .padding(.top, 60)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .colorScheme(.dark)
        .background(Color.Arke.gold4)
    }
}
