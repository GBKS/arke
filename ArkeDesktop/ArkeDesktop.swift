//
//  Ark_wallet_prototypeApp.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import SwiftData

@main
struct Arke_desktop: App {
    /// Scene phase for detecting app lifecycle events
    @Environment(\.scenePhase) private var scenePhase
    
    /// Wallet manager - created during init to ensure single instance
    @State private var walletManager: WalletManager
    
    /// Shared service container for tag and contact management
    let serviceContainer = ServiceContainer.shared
    
    /// Early detection result - whether a wallet exists (based on keychain check)
    /// This is set during init() and can be used by views to avoid redundant checks
    /// Note: Using a let constant since we can't mutate @State in init()
    let initialWalletDetected: Bool
    
    /// CloudKit-enabled model container for syncing data across devices.
    /// The schema comes from SwiftDataHelper.appSchemaModels — the canonical
    /// list shared with ArkeMobile and the wipe-coverage test.
    let modelContainer: ModelContainer = {
        SwiftDataHelper.createAppModelContainer(
            cloudKitEnabled: true,  // 🌥️ CloudKit sync enabled for alpha
            cloudKitContainerIdentifier: "iCloud.gbks.sigma"  // Explicit container ID
        )
    }()
    
    // MARK: - Early Wallet Detection
    
    /// Performs lightweight wallet check before app initialization
    /// This determines whether to activate services and sync
    init() {
        // Anchor the launch-timing clock before any other work (see LaunchTiming)
        LaunchTiming.anchor()

        // Early check is a fast-path hint only: a positive result is trustworthy, a
        // negative one is not (keychain may be transiently unreadable). MainView's
        // deeper detection re-checks with retries whenever this is false.
        let earlyStatus = SecurityService.mnemonicKeychainStatus()
        if case .unavailable(let osStatus) = earlyStatus {
            print("⚠️ [App Init] Early wallet check indeterminate (OSStatus \(osStatus)) - deferring to deeper detection")
        }
        let hasWallet = earlyStatus == .found

        // Store the detection result (must be done before calling serviceContainer.setActive)
        self.initialWalletDetected = hasWallet
        
        // Create WalletManager once during init
        print("🔧 [App] Creating WalletManager (init)")
        self._walletManager = State(initialValue: WalletManager())
        
        if hasWallet {
            print("✅ [App Init] Wallet detected - services will be activated")
            serviceContainer.setActive(true)
        } else {
            print("⏭️ [App Init] No wallet detected - services will remain passive")
            serviceContainer.setActive(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(walletManager)
                .environment(\.initialWalletDetected, initialWalletDetected)
                .withServiceContainer(serviceContainer)
                .onAppear {
                    // Start CloudKit sync if wallet exists
                    // This happens when app launches with an existing wallet
                    if initialWalletDetected {
                        print("💻 [macOS App] Starting CloudKit sync (wallet exists)...")
                        serviceContainer.startCloudKitSync(modelContainer: modelContainer)
                    } else {
                        print("⏭️ [macOS App] Skipping CloudKit sync (no wallet yet)")
                    }
                }
                .task {
                    // Only register for CloudKit notifications if a wallet exists
                    if initialWalletDetected {
                        print("💻 [macOS App] Registering for remote notifications...")
                        await registerForCloudKitNotifications()
                    } else {
                        print("⏭️ [macOS App] Skipping remote notification registration (no wallet yet)")
                    }
                }
                .onDisappear {
                    serviceContainer.cleanup()
                }
        }
        .defaultSize(width: 800, height: 600)
        .windowResizability(.contentMinSize)
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                Task {
                    await (walletManager.wallet as? BarkWalletFFI)?.backupWallet()
                }
            }
        }
    }
    
    // MARK: - CloudKit Notification Registration
    
    /// Register for remote notifications to receive CloudKit push updates
    /// This allows the app to be notified immediately when changes occur on other devices
    private func registerForCloudKitNotifications() async {
        await MainActor.run {
            NSApplication.shared.registerForRemoteNotifications()
            print("🔔 [CloudKit] Registered for remote notifications (macOS)")
        }
    }
}

// MARK: - Environment Key for Initial Wallet Detection

/// Environment key for passing the initial wallet detection result to child views
private struct InitialWalletDetectedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var initialWalletDetected: Bool {
        get { self[InitialWalletDetectedKey.self] }
        set { self[InitialWalletDetectedKey.self] = newValue }
    }
}
