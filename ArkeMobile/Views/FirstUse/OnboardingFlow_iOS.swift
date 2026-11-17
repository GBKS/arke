//
//  OnboardingFlow_iOS.swift
//  Arké
//
//  Created by Christoph on 11/27/25.
//

/*
 
Create wallet sequence
1. firstUse
2. introVideos
3. createWallet
4. walletCreated
 
Import wallet sequence
1. firstUse
2. importWallet (recovery phrase grid)
3. importBackupFile (backup file, Skip for phrase-only; runs the import)
4. walletImported
 
 */

import SwiftUI
import OSLog
import ArkeUI
import Combine

enum OnboardingState {
    case firstUse
    case introVideos
    case importWallet
    case importBackupFile
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

struct OnboardingFlow_iOS: View {
    @State private var currentState: OnboardingState = .firstUse
    @State private var navigationDirection: NavigationDirection = .forward
    /// Server and chain for the wallet about to be created or imported. The
    /// cover screen's sheet sets it; create/import consume it and persist it
    /// once the wallet exists.
    @State private var networkConfig: NetworkConfig = .mainnet
    /// The validated recovery phrase, carried from the phrase step to the
    /// backup-file step and back; cleared when the import branch is left.
    @State private var importPhrase: [String] = []
    /// Restore mode (see `restoresExistingDatabase`): the phrase-only import
    /// is running, and its error if it failed
    @State private var isRestoring = false
    @State private var restoreError: String?
    @Environment(WalletManager.self) private var walletManager
    let onWalletReady: () -> Void
    /// The launch-check screen's restore exit (Device_Linking.md §4.5,
    /// range review I1): the wallet's database is still on this device, so
    /// the phrase step imports phrase-only and the backup-file step, whose
    /// default path replaces the database, is never shown.
    let restoresExistingDatabase: Bool
    /// Restore mode: the import refused because the account's wallet state
    /// changed since the launch check; the owner re-runs detection
    let onRestoreBlocked: (() -> Void)?

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "OnboardingFlow")

    /// - Parameter initialState: the launch-check screen's restore exit
    ///   (Device_Linking.md §4.5) opens the flow at the phrase step
    /// - Parameter restoresExistingDatabase: that exit keeps the local
    ///   database; the phrase step restores directly
    init(
        initialState: OnboardingState = .firstUse,
        initialNetworkConfig: NetworkConfig = .mainnet,
        restoresExistingDatabase: Bool = false,
        onRestoreBlocked: (() -> Void)? = nil,
        onWalletReady: @escaping () -> Void
    ) {
        _currentState = State(initialValue: initialState)
        _networkConfig = State(initialValue: initialNetworkConfig)
        self.restoresExistingDatabase = restoresExistingDatabase
        self.onRestoreBlocked = onRestoreBlocked
        self.onWalletReady = onWalletReady
    }

    /// Restore mode: open the existing database with the phrase typed.
    /// `importWallet` refuses another phrase against the link record before
    /// opening anything, refuses to wipe the directory while the record
    /// exists, and leaves `db.sqlite` untouched on success, so a wrong phrase
    /// or network costs nothing but the error. `isRestoring` is set by the
    /// tap handler, before the first hop, so Back and a second tap are
    /// blocked from the start.
    private func restoreExistingWallet(words: [String]) async {
        defer { isRestoring = false }
        do {
            let result = try await walletManager.importWallet(
                mnemonic: words.joined(separator: " "),
                networkConfig: networkConfig
            )
            Self.logger.info("✅ Existing wallet restored from the recovery phrase: \(result)")
            importPhrase = []
            navigationDirection = .forward
            withAnimation(.smooth(duration: 0.4)) {
                currentState = .walletImported
            }
        } catch BarkErrorArke.accountChangedSinceLaunchCheck {
            // Not a user error: the account moved on; hand back to detection,
            // which lands on the right screen (linked again, mismatch, or the
            // launch check with fresh inputs)
            Self.logger.notice("🔗 Restore refused: account wallet state changed since the launch check — handing back to detection")
            restoreError = BarkErrorArke.accountChangedSinceLaunchCheck.errorDescription
            onRestoreBlocked?()
        } catch {
            restoreError = String(format: String(localized: "error_import_wallet", defaultValue: "Failed to import wallet: %@"), error.localizedDescription)
        }
    }
    
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                VStack {
                    switch currentState {
                    case .firstUse:
                        FirstUseView_iOS(
                            networkConfig: $networkConfig,
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
                        IntroVideoView_iOS(
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
                            isMainnet: networkConfig.isMainnet
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
                        ImportPhraseView_iOS(
                            networkConfig: networkConfig,
                            initialWords: importPhrase,
                            onBack: {
                                importPhrase = []
                                navigationDirection = .backward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .firstUse
                                }
                            },
                            onContinue: { words in
                                if restoresExistingDatabase {
                                    importPhrase = words
                                    isRestoring = true
                                    Task { await restoreExistingWallet(words: words) }
                                    return
                                }
                                importPhrase = words
                                navigationDirection = .forward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .importBackupFile
                                }
                            },
                            restoresExistingDatabase: restoresExistingDatabase,
                            isBusy: isRestoring
                        )
                        .alert(String(localized: "error_import", defaultValue: "Import Error"), isPresented: Binding(
                            get: { restoreError != nil },
                            set: { if !$0 { restoreError = nil } }
                        )) {
                            Button(String(localized: "button_ok", defaultValue: "OK"), role: .cancel) { restoreError = nil }
                        } message: {
                            Text(restoreError ?? "")
                        }
                        .transition(.asymmetric(
                            insertion: navigationDirection == .forward ?
                                .move(edge: .trailing).combined(with: .opacity) :
                                    .move(edge: .leading).combined(with: .opacity),
                            removal: navigationDirection == .forward ?
                                .move(edge: .leading).combined(with: .opacity) :
                                    .move(edge: .trailing).combined(with: .opacity)
                        ))
                        .tag("importWallet")

                    case .importBackupFile:
                        ImportBackupFileView_iOS(
                            networkConfig: networkConfig,
                            phrase: importPhrase.joined(separator: " "),
                            onBack: {
                                navigationDirection = .backward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .importWallet
                                }
                            },
                            onWalletImported: {
                                importPhrase = []
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
                        .tag("importBackupFile")
                        
                    case .walletImported:
                        WalletImportedView_iOS(
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
                        CreateWalletView_iOS(
                            networkConfig: networkConfig,
                            onWalletCreated: {
                                onWalletReady()
                                /*
                                navigationDirection = .forward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .walletCreated
                                }
                                 */
                            },
                            onBack: {
                                navigationDirection = .backward
                                withAnimation(.smooth(duration: 0.4)) {
                                    currentState = .firstUse
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
                        WalletCreatedView_iOS(
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
        .ignoresSafeArea()
    }
}
