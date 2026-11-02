//
//  FirstUseView_iOS.swift
//  Arké
//
//  Created by Christoph on 11/27/25.
//

import SwiftUI
import ArkeUI

struct FirstUseView_iOS: View {
    /// The server (and chain) the wallet will be created or imported on.
    /// Chosen in `ArkServerSelectionSheet`; the chain drives the video and
    /// the test-wallet notice. The cover shows nothing else about the choice
    /// (DECIDED 2026-10-30); Create and Import name a non-default server.
    @Binding var networkConfig: NetworkConfig
    let onCreateWallet: () -> Void
    let onImportWallet: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showServerSheet = false

    private var isMainnet: Bool { networkConfig.isMainnet }

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
                    // Server sheet in the top-left corner. The lab vial stays: the
                    // server choice is still an experimental corner of the app
                    // (Features/Ark_Server_Selection.md §4.10, DECIDED 2026-10-30).
                    Button {
                        showServerSheet = true
                    } label: {
                        Image(systemName: "testtube.2")
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityLabel(String(localized: "accessibility_choose_server", defaultValue: "Server and network"))
                    .accessibilityValue(serverSummary)
                    .accessibilityHint(String(localized: "accessibility_choose_server_hint", defaultValue: "Opens the server choice for the new wallet"))
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
        .sheet(isPresented: $showServerSheet) {
            // The sheet sizes itself: compact for page one, full height for
            // the pushed pages (presentationDetents with a selection inside)
            ArkServerSelectionSheet(selection: $networkConfig)
        }
    }

    /// Spoken value of the server button: the current choice, for VoiceOver only.
    private var serverSummary: String {
        switch networkConfig.serverKind {
        case .secondMainnet:
            return String(localized: "server_summary_default", defaultValue: "Bitcoin, Second")
        case .secondSignet:
            return String(localized: "server_summary_second_signet", defaultValue: "Signet, Second")
        case .custom:
            let chain = networkConfig.isMainnet
                ? String(localized: "network_name_bitcoin", defaultValue: "Bitcoin")
                : String(localized: "server_summary_signet_short", defaultValue: "Signet")
            let host = NetworkConfig.serverHost(networkConfig.arkServerURL) ?? networkConfig.name
            return "\(chain), \(host)"
        }
    }
}
