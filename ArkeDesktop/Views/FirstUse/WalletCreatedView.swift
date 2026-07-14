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
                    Text("onboarding_ready_bitcoin")
                        .font(.system(size: 40, design: .serif))
                        .foregroundStyle(Color.Arke.gold)
                    
                    Text("firstuse_wallet_created")
                        .font(.system(size: 21))
                        .lineSpacing(6)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                    
                    Text("onboarding_backup_advice")
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
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right")
                    Text("onboarding_lets_go")
                }
            }
            .buttonStyle(ArkeButtonStyle(size: .large))
        }
        .padding(.horizontal, 40)
        .padding(.top, 60)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Arke.gold4)
    }
}
