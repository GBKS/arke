//
//  WalletImportedView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/26/25.
//

import SwiftUI

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
                        .fill(Color.arkeGold.opacity(0.2))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.arkeGold)
                }
                
                VStack(spacing: 8) {
                    Text("Wallet Imported!")
                        .font(.system(size: 40, design: .serif))
                        .foregroundStyle(Color.arkeGold)
                    
                    Text("Your Ark wallet has been successfully imported and is ready to use.")
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
        .frame(minWidth: 800, minHeight: 600)
        .background(Color.arkeDark)
    }
}

#Preview {
    WalletImportedView(
        onContinue: {},
        onBackupReminder: {}
    )
}
