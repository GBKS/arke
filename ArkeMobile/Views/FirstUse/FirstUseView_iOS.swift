//
//  FirstUseView_iOS.swift
//  Arké
//
//  Created by Christoph on 11/27/25.
//

import SwiftUI
import ArkeUI

struct FirstUseView_iOS: View {
    @Binding var isMainnet: Bool
    let onCreateWallet: () -> Void
    let onImportWallet: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background video covering entire view
            LoopingVideoPlayer_iOS(videoName: isMainnet ? "coffee-shop-chat-2": "experimenter-small", videoExtension: "mp4")
                .id(isMainnet)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
                .accessibilityHidden(true)
            
            VStack {
                HStack {
                    // Mainnet toggle in top-left corner
                    Button {
                        if reduceMotion {
                            isMainnet.toggle()
                        } else {
                            withAnimation {
                                isMainnet.toggle()
                            }
                        }
                        
                        // Announce network change for VoiceOver users
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            let announcement = isMainnet ? 
                                String(localized: "accessibility_switched_mainnet", defaultValue: "Switched to mainnet. You will create a real wallet.") : 
                                String(localized: "accessibility_switched_testnet", defaultValue: "Switched to testnet. You will create a test wallet.")
                            UIAccessibility.post(notification: .announcement, argument: announcement)
                        }
                    } label: {
                        Image(systemName: "testtube.2")
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityLabel(isMainnet ? String(localized: "accessibility_switch_to_testnet", defaultValue: "Switch to testnet") : String(localized: "accessibility_switch_to_mainnet", defaultValue: "Switch to mainnet"))
                    .accessibilityHint(String(localized: "accessibility_network_toggle_hint", defaultValue: "Toggle between mainnet and testnet"))
                    .buttonStyle(.glass)
                    .controlSize(.regular)
                    .tint(.Arke.gold)
                    .padding(.top, 60)
                    .padding(.leading, 20)
                    
                    Spacer()
                }
                
                Spacer()
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.8)))
             
            // Content overlaid at bottom
            VStack(spacing: 30) {
                VStack(spacing: 8) {
                    /*
                    Button {
                        withAnimation {
                            isMainnet.toggle()
                        }
                    } label: {
                        Text(L10n.appName)
                            .font(.system(size: 100, design: .serif))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Arke.gold)
                    }
                    .buttonStyle(.plain)
                    */
                    
                    if !isMainnet {
                        Text(String(localized: "onboarding_test_wallet_notice", defaultValue: "You will create a test wallet."))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black, radius: 4, x: 0, y: 2)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.smooth(duration: 0.5), value: isMainnet)
                
                VStack(spacing: 16) {
                    Button {
                        onCreateWallet()
                    } label: {
                        Text(String(localized: "button_create_wallet", defaultValue: "Create Wallet"))
                            .font(.system(.title2, weight: .semibold))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Arke.gold4)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(Color.Arke.gold)

                    Button {
                        onImportWallet()
                    } label: {
                        Text(L10n.buttonImportWallet)
                            .font(.system(.title2, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 50)
            .frame(maxWidth: .infinity)
        }
        .colorScheme(.dark)
        .background(Color.Arke.gold4)
        .safeAreaPadding([.top, .bottom])
    }
}
