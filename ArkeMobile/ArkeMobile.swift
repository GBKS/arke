//
//  Arke__mobileApp.swift
//  Arké mobile
//
//  Created by Christoph on 11/27/25.
//

import SwiftUI
import SwiftData
import OSLog

@main
struct Arke_mobile: App {
    /// Logger for app lifecycle events
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "App")

    /// AppDelegate for handling APNs and notifications
    @UIApplicationDelegateAdaptor(AppDelegate_iOS.self) var appDelegate
    
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
    
    /// CloudKit-enabled model container for syncing data across devices
    let modelContainer: ModelContainer = {
        SwiftDataHelper.createModelContainer(
            for: PersistentTransaction.self,
                 ArkBalanceModel.self,
                 OnchainBalanceModel.self,
                 PersistentTag.self,
                 TransactionTagAssignment.self,
                 PersistentContact.self,
                 TransactionContactAssignment.self,
                 PersistentContactAddress.self,
                 WalletConfiguration.self,
                 DeviceRegistration.self,  // 📱 Device registry for cross-device management
                 BackupStatus.self,  // 💾 Backup reminder state
                 PersistentAddress.self,  // 📍 Address history for gap limit & internal transfers
                 UserProfile.self,  // 👤 User profile for personalization features
                 PersistentExitCache.self,  // 🚪 Exit cache for fast UI rendering
            cloudKitEnabled: true,  // 🌥️ CloudKit sync enabled for alpha
            cloudKitContainerIdentifier: "iCloud.gbks.sigma"  // Explicit container ID
        )
    }()
    
    // MARK: - Early Wallet Detection
    
    /// Performs lightweight wallet check before app initialization
    /// This determines whether to activate services and sync
    init() {
        let hasWallet = SecurityService.hasMnemonicInKeychain()
        
        // Store the detection result (must be done before calling serviceContainer.setActive)
        self.initialWalletDetected = hasWallet
        
        // Create WalletManager once during init
        Self.logger.debug("Creating WalletManager (init)")
        self._walletManager = State(initialValue: WalletManager())

        if hasWallet {
            Self.logger.info("Wallet detected - services will be activated")
            serviceContainer.setActive(true)
        } else {
            Self.logger.info("No wallet detected - services will remain passive")
            serviceContainer.setActive(false)
        }

        // Set up push notification observers early (before onAppear)
        // This ensures they're ready even if the app is launched by tapping a notification
        if hasWallet {
            Self.logger.debug("Setting up push notification observers...")
            self.setupPushNotificationObserversEarly()
        }
    }
    
    /// Sets up observers during init
    /// Note: The actual refresh will be handled by WalletManager once it's created
    private func setupPushNotificationObserversEarly() {
        // The mailbox notification observer will be set up by WalletManager
        // when it's initialized. This ensures proper lifecycle management.
        Self.logger.debug("Mailbox observer will be set up by WalletManager")
    }

    var body: some Scene {
        WindowGroup {
            MainView_iOS()
                .environment(walletManager)
                .environment(\.initialWalletDetected, initialWalletDetected)
                .withServiceContainer(serviceContainer)
                .onAppear {
                    // Start CloudKit sync if wallet exists
                    // This happens when app launches with an existing wallet
                    if initialWalletDetected {
                        Self.logger.info("Starting CloudKit sync (wallet exists)...")
                        serviceContainer.startCloudKitSync(modelContainer: modelContainer)

                        // Set up push notification observers
                        setupPushNotificationObservers()
                    } else {
                        Self.logger.info("Skipping CloudKit sync (no wallet yet)")
                    }
                }
                .task {
                    // Only register for CloudKit notifications if a wallet exists
                    if initialWalletDetected {
                        Self.logger.info("Registering for remote notifications...")
                        await registerForCloudKitNotifications()

                        // Register for push notifications with relay
                        await registerForPushNotifications()
                    } else {
                        Self.logger.info("Skipping remote notification registration (no wallet yet)")
                    }
                }
                .onDisappear {
                    serviceContainer.cleanup()
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                Task {
                    await (walletManager.wallet as? BarkWalletFFI)?.backupWallet()
                }
            } else if newPhase == .active && oldPhase == .background {
                // User brought app to foreground - check if we have active exits
                Task {
                    if let service = walletManager.exitProgressionService,
                       await service.hasActiveExits() {
                        await service.userCheckedIn()
                    }
                }
            }
        }
    }
    

    // MARK: - CloudKit Notification Registration
    
    /// Register for remote notifications to receive CloudKit push updates
    /// This allows the app to be notified immediately when changes occur on other devices
    private func registerForCloudKitNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
            Self.logger.info("Registered for remote notifications (iOS)")
        }
    }
    
    // MARK: - Push Notification Setup
    
    /// Registers device for push notifications with the relay
    private func registerForPushNotifications() async {
        await walletManager.registerForPushNotifications()
    }
    
    /// Sets up observer for APNs token changes
    /// Note: Mailbox update observer is already set up in init()
    private func setupPushNotificationObservers() {
        // Capture wallet manager reference for observers
        let manager = walletManager
        
        // Observer for when APNs token is received or changed
        Self.logger.debug("Setting up APNs token observer...")
        NotificationCenter.default.addObserver(
            forName: .apnsTokenReceived,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                Self.logger.info("APNs token received, registering with relay...")
                await manager.registerForPushNotifications()
            }
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
