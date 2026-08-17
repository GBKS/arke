//
//  OnboardingFlow.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//

/*

Create wallet sequence
1. firstUse
2. introVideos
3. createWallet
4. walletCreated

Import wallet sequence
1. firstUse
2. importWallet
3. walletImported

 */

import SwiftUI
import ArkeUI

enum OnboardingState {
    case firstUse
    case introVideos
    case importWallet
    case walletImported
    case usagePattern
    case selectServer
    case createWallet
    case walletCreated
}

enum NavigationDirection {
    case forward
    case backward
}

struct OnboardingFlow: View {
    @State private var currentState: OnboardingState = .firstUse
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var isMainnet: Bool = true
    @Environment(WalletManager.self) private var walletManager
    let onWalletReady: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                VStack {
                    switch currentState {
                    case .firstUse:
                        FirstUseView(
                            isMainnet: $isMainnet,
                            onCreateWallet: {
                                navigationDirection = .forward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .introVideos
                                }
                            },
                            onImportWallet: {
                                navigationDirection = .forward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .importWallet
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: navigationDirection == .forward ?
                                .move(edge: .trailing).combined(with: .opacity) :
                                    .move(edge: .leading).combined(with: .opacity),
                            removal: navigationDirection == .forward ?
                                .move(edge: .leading).combined(with: .opacity) :
                                    .move(edge: .trailing).combined(with: .opacity)
                        ))
                        .tag("firstUse")

                    case .introVideos:
                        IntroVideoView(
                            onBack: {
                                navigationDirection = .backward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .firstUse
                                }
                            },
                            onContinue: {
                                navigationDirection = .forward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .createWallet
                                }
                            },
                            onSkip: {
                                navigationDirection = .forward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .createWallet
                                }
                            },
                            isMainnet: isMainnet
                        )
                        .transition(.asymmetric(
                            insertion: navigationDirection == .forward ?
                                .move(edge: .trailing).combined(with: .opacity) :
                                    .move(edge: .leading).combined(with: .opacity),
                            removal: navigationDirection == .forward ?
                                .move(edge: .leading).combined(with: .opacity) :
                                    .move(edge: .trailing).combined(with: .opacity)
                        ))
                        .tag("introVideos")

                    case .importWallet:
                        ImportWalletView(
                            isMainnet: isMainnet,
                            onBack: {
                                navigationDirection = .backward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .firstUse
                                }
                            },
                            onWalletImported: {
                                navigationDirection = .forward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .walletImported
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: navigationDirection == .forward ?
                                .move(edge: .trailing).combined(with: .opacity) :
                                    .move(edge: .leading).combined(with: .opacity),
                            removal: navigationDirection == .forward ?
                                .move(edge: .leading).combined(with: .opacity) :
                                    .move(edge: .trailing).combined(with: .opacity)
                        ))
                        .tag("importWallet")

                    case .walletImported:
                        WalletImportedView(
                            onContinue: {
                                onWalletReady()
                            },
                            onBackupReminder: {
                                // TODO: Navigate to backup reminder view
                                // For now, we'll just continue to the main wallet
                                onWalletReady()
                            }
                        )
                        .transition(.asymmetric(
                            insertion: navigationDirection == .forward ?
                                .move(edge: .trailing).combined(with: .opacity) :
                                    .move(edge: .leading).combined(with: .opacity),
                            removal: navigationDirection == .forward ?
                                .move(edge: .leading).combined(with: .opacity) :
                                    .move(edge: .trailing).combined(with: .opacity)
                        ))
                        .tag("walletImported")

                    case .usagePattern:
                        Text(L10n.labelUsagePattern)
                        /*
                        UsagePatternView(
                            onBack: {
                                navigationDirection = .backward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .firstUse
                                }
                            },
                            onContinue: { profile in
                                usagePattern = profile
                                navigationDirection = .forward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .selectServer
                                }
                            },
                            usagePattern: usagePattern
                        )
                        .transition(.asymmetric(
                            insertion: navigationDirection == .forward ?
                                .move(edge: .trailing).combined(with: .opacity) :
                                    .move(edge: .leading).combined(with: .opacity),
                            removal: navigationDirection == .forward ?
                                .move(edge: .leading).combined(with: .opacity) :
                                    .move(edge: .trailing).combined(with: .opacity)
                        ))
                        .tag("usagePattern")
                        */
                    case .selectServer:
                        Text(L10n.labelUsagePattern)
                        /*
                        ServerSelectionView(
                            onBack: { profile in
                                usagePattern = profile
                                navigationDirection = .backward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .usagePattern
                                }
                            },
                            onServerSelected: {
                                navigationDirection = .forward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .createWallet
                                }
                            },
                            usagePattern: usagePattern
                        )
                        .transition(.asymmetric(
                            insertion: navigationDirection == .forward ?
                                .move(edge: .trailing).combined(with: .opacity) :
                                    .move(edge: .leading).combined(with: .opacity),
                            removal: navigationDirection == .forward ?
                                .move(edge: .leading).combined(with: .opacity) :
                                    .move(edge: .trailing).combined(with: .opacity)
                        ))
                        .tag("selectServer")
                        */
                    case .createWallet:
                        CreateWalletView(
                            isMainnet: isMainnet,
                            onBack: {
                                navigationDirection = .backward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .firstUse
                                }
                            },
                            onWalletCreated: {
                                onWalletReady()
                                /*
                                navigationDirection = .forward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .walletCreated
                                }
                                 */
                            },
                            walletManager: walletManager
                        )
                        .transition(.asymmetric(
                            insertion: navigationDirection == .forward ?
                                .move(edge: .trailing).combined(with: .opacity) :
                                    .move(edge: .leading).combined(with: .opacity),
                            removal: navigationDirection == .forward ?
                                .move(edge: .leading).combined(with: .opacity) :
                                    .move(edge: .trailing).combined(with: .opacity)
                        ))
                        .tag("createWallet")
                    case .walletCreated:
                        WalletCreatedView(
                            onContinue: {
                                onWalletReady()
                            },
                            onShowRecoveryPhrase: {
                                // TODO: Navigate to recovery phrase view
                                // For now, we'll just continue to the main wallet
                                onWalletReady()
                            }
                        )
                        .transition(.asymmetric(
                            insertion: navigationDirection == .forward ?
                                .move(edge: .trailing).combined(with: .opacity) :
                                    .move(edge: .leading).combined(with: .opacity),
                            removal: navigationDirection == .forward ?
                                .move(edge: .leading).combined(with: .opacity) :
                                    .move(edge: .trailing).combined(with: .opacity)
                        ))
                        .tag("walletCreated")
                    }
                }
                .frame(maxWidth: .infinity)
                .clipped()
            }
        }
        .background(Color.Arke.gold4)
        .clipped() // Prevents views from showing outside bounds during transition
    }
}
