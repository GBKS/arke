//
//  OnboardingFlow.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//

import SwiftUI

enum OnboardingState {
    case firstUse
    case importWallet
    case walletImported
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
    @Environment(WalletManager.self) private var walletManager
    let onWalletReady: () -> Void
    
    var body: some View {
        ZStack {
            Group {
                switch currentState {
                case .firstUse:
                    FirstUseView(
                        onCreateWallet: {
                            withAnimation(.smooth(duration: 0.4)) {
                                navigationDirection = .forward
                                currentState = .createWallet
                            }
                        },
                        onImportWallet: {
                            withAnimation(.smooth(duration: 0.4)) {
                                navigationDirection = .forward
                                currentState = .importWallet
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: navigationDirection == .forward ? 
                            .move(edge: .leading).combined(with: .opacity) :
                            .move(edge: .trailing).combined(with: .opacity),
                        removal: navigationDirection == .forward ? 
                            .move(edge: .trailing).combined(with: .opacity) :
                            .move(edge: .leading).combined(with: .opacity)
                    ))
                    .tag("firstUse")
                    
                case .importWallet:
                    ImportWalletView(
                        onBack: {
                            withAnimation(.smooth(duration: 0.4)) {
                                navigationDirection = .backward
                                currentState = .firstUse
                            }
                        },
                        onWalletImported: {
                            withAnimation(.smooth(duration: 0.4)) {
                                navigationDirection = .forward
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
                    
                case .createWallet:
                    CreateWalletView(
                        onBack: {
                            withAnimation(.smooth(duration: 0.4)) {
                                navigationDirection = .backward
                                currentState = .firstUse
                            }
                        },
                        onWalletCreated: {
                            withAnimation(.smooth(duration: 0.4)) {
                                navigationDirection = .forward
                                currentState = .walletCreated
                            }
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
        }
        .clipped() // Prevents views from showing outside bounds during transition
    }
}

#Preview {
    OnboardingFlow(
        onWalletReady: {
            // Preview completion action
        }
    )
    .environment(WalletManager(useMock: true))
}