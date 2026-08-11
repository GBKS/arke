//
//  OnboardingView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import ArkeUI
import Accessibility

struct FirstUseView: View {
    @Binding var isMainnet: Bool
    let onCreateWallet: () -> Void
    let onImportWallet: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            VStack {
                // Left column - Big video
                 LoopingVideoPlayer(videoName: isMainnet ? "coffee-shop-chat-2": "experimenter-small", videoExtension: "mp4")
                    .id(isMainnet)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityHidden(true)
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
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                    }

                    Button {
                        onCreateWallet()
                    } label: {
                        Text("button_create_wallet")
                            .font(.system(.title2, weight: .semibold))
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
                        Text("button_import_wallet")
                            .font(.system(.title2, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity)
        }
        .colorScheme(.dark)
        .background(Color.Arke.gold4)
        .animation(reduceMotion ? .none : .smooth(duration: 0.5), value: isMainnet)
        .overlay(alignment: .topLeading) {
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
                        String(localized: "accessibility_switched_mainnet") :
                        String(localized: "accessibility_switched_testnet")
                    AccessibilityNotification.Announcement(announcement).post()
                }
            } label: {
                Image(systemName: "testtube.2")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
            .tint(Color.Arke.gold)
            .accessibilityLabel(isMainnet ? String(localized: "accessibility_switch_to_testnet") : String(localized: "accessibility_switch_to_mainnet"))
            .accessibilityHint(String(localized: "accessibility_network_toggle_hint"))
            .padding(20)
        }
    }
}
