//
//  WalletCreatedView_iOS.swift
//  Arké
//
//  Created by Christoph on 12/09/25.
//

import SwiftUI
import ArkeUI

struct WalletCreatedView_iOS: View {
    let onContinue: () -> Void
    let onShowRecoveryPhrase: () -> Void
    
    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                // Success icon and title
                VStack(alignment: .leading, spacing: 30) {
                    // Success checkmark
                    ZStack {
                        Circle()
                            .fill(Color.Arke.gold.opacity(0.2))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(Color.Arke.gold)
                    }
                    .accessibilityHidden(true)
                    
                    VStack(spacing: 8) {
                        Text(String(localized: "onboarding_ready_bitcoin", defaultValue: "You are ready for bitcoin!"))
                            .font(.largeTitle)
                            .fontDesign(.serif)
                            .foregroundStyle(Color.Arke.gold)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                        
                        Text(String(localized: "onboarding_wallet_ready", defaultValue: "Your new wallet is ready to use."))
                            .font(.title2)
                            .lineSpacing(4)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        
                        Text(String(localized: "onboarding_backup_reminder", defaultValue: "Make sure to make a backup. You're in control of this wallet, and also responsible for it."))
                            .font(.title2)
                            .lineSpacing(4)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                
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
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .padding(.top, safeAreaInsets.top)
            .padding(.bottom, safeAreaInsets.bottom)
        }
        .colorScheme(.dark)
        .background(Color.Arke.gold4)
        .ignoresSafeArea()
    }
}
