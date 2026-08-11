//
//  OnboardingView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import ArkeUI

struct FirstUseView: View {
    @Binding var isMainnet: Bool
    let onCreateWallet: () -> Void
    let onImportWallet: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack {
                // Left column - Big video
                 LoopingVideoPlayer(videoName: isMainnet ? "coffee-shop-chat-2": "experimenter-small", videoExtension: "mp4")
                    .id(isMainnet)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
            .frame(maxWidth: .infinity)
            
            // Right column - Existing content
            VStack(spacing: 30) {
                VStack(spacing: 8) {
                    Text("firstuse_welcome_to")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("app_name")
                        .font(.system(size: 80, design: .serif))
                        .fontWeight(.regular)
                        .foregroundStyle(Color.Arke.gold)
                }
                
                Spacer()

                VStack(spacing: 16) {
                    if !isMainnet {
                        Text("onboarding_test_wallet_notice")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Button("button_create_wallet") {
                        onCreateWallet()
                    }
                    .buttonStyle(ArkeButtonStyle(size: .large))

                    Button("action_import_wallet") {
                        onImportWallet()
                    }
                    .buttonStyle(ArkeButtonStyle(size: .large, variant: .outline))
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity)
        }
        .background(Color.Arke.gold4)
        .animation(.smooth(duration: 0.5), value: isMainnet)
        .overlay(alignment: .topLeading) {
            Button {
                isMainnet.toggle()
            } label: {
                Image(systemName: "testtube.2")
                    .font(.system(size: 16))
                    .foregroundStyle(isMainnet ? Color.Arke.gold.opacity(0.5) : Color.Arke.gold)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMainnet ? String(localized: "accessibility_switch_to_testnet") : String(localized: "accessibility_switch_to_mainnet"))
            .accessibilityHint(String(localized: "accessibility_network_toggle_hint"))
            .padding(20)
        }
    }
}
