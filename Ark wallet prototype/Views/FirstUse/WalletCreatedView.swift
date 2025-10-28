//
//  WalletCreatedView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/26/25.
//

import SwiftUI

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
                        .fill(Color.arkeGold.opacity(0.2))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.arkeGold)
                }
                
                VStack(spacing: 8) {
                    Text("You are ready for bitcoin!")
                        .font(.system(size: 40, design: .serif))
                        .foregroundStyle(Color.arkeGold)
                    
                    Text("Your new wallet has been successfully created and is ready to use.")
                        .font(.system(size: 21))
                        .lineSpacing(6)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                    
                    Text("Once you have some funds in it, make sure to do a proper backup. You're in control of this wallet, and also responsible for it.")
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
                    Text("Let's go!")
                }
            }
            .buttonStyle(ArkeButtonStyle(size: .large))
        }
        .padding(.horizontal, 40)
        .padding(.top, 60)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.arkeDark)
    }
}

#Preview {
    WalletCreatedView(
        onContinue: {},
        onShowRecoveryPhrase: {}
    )
    .frame(width: 600, height: 700)
}
