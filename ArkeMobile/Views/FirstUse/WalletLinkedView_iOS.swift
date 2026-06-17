//
//  WalletLinkedView_iOS.swift
//  Arké
//
//  Created by Christoph on 12/10/25.
//

import SwiftUI
import ArkeUI

struct WalletLinkedView_iOS: View {
    let onContinue: () -> Void
    
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
                        Text("status_wallet_connected")
                            .font(.largeTitle)
                            .fontDesign(.serif)
                            .foregroundStyle(Color.Arke.gold)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                        
                        Text("onboarding_continue_wallet")
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
                        .foregroundStyle(Color.Arke.gold3)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(Color.Arke.gold)
                .accessibilityLabel(String(localized: "accessibility_continue_to_wallet"))
                .accessibilityHint(String(localized: "accessibility_wallet_ready_hint"))
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .padding(.top, safeAreaInsets.top)
            .padding(.bottom, safeAreaInsets.bottom)
        }
        .colorScheme(.dark)
        .background(Color.Arke.gold3)
        .ignoresSafeArea()
    }
}
