//
//  WalletImportedView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/26/25.
//

import SwiftUI
import ArkeUI

struct WalletImportedView: View {
    let onContinue: () -> Void
    let onBackupReminder: () -> Void
    
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
                    Text(String(localized: "status_wallet_imported", defaultValue: "Wallet Imported!"))
                        .font(.system(size: 40, design: .serif))
                        .foregroundStyle(Color.Arke.gold)
                    
                    Text(String(localized: "onboarding_import_success", defaultValue: "Your Ark wallet has been successfully imported and is ready to use."))
                        .font(.system(size: 21))
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
