//
//  ContentView.swift
//  Arké mobile
//
//  Created by Christoph on 11/27/25.
//

import SwiftUI
import SwiftData
import Combine
import CloudKit
import OSLog
import ArkeUI

struct MainView_iOS: View {
    /// Logger for main view operations
    nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "MainView")
    
    @State private var hasWallet: Bool = false
    @State private var isCheckingWallet: Bool = true
    @State private var walletState: WalletState = .unknown
    @State private var lateServicesActivated: Bool = false
    @State private var isLinkingDevice: Bool = false
    /// Where onboarding opens. The launch-check screen's restore exit starts
    /// it at the phrase step (Device_Linking.md §4.5).
    @State private var onboardingStart: OnboardingState = .firstUse
    /// Set by the launch-check restore exit: onboarding's phrase step opens
    /// the existing database instead of offering a backup file (I1)
    @State private var onboardingRestoresExistingDatabase = false
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.securityService) private var securityService
    @Environment(\.serviceContainer) private var serviceContainer
    @Environment(\.initialWalletDetected) private var initialWalletDetected
    
    // MARK: - Late Wallet Detection

    /// Starts the services that the App body gates on `initialWalletDetected`.
    /// When the early keychain check missed (keychain unavailable at launch) but deeper
    /// detection finds the wallet, CloudKit sync and remote notification registration
    /// would otherwise silently never run for this session.
    private func activateLateDetectedWalletServices() {
        guard !initialWalletDetected, !lateServicesActivated else { return }
        lateServicesActivated = true

        Self.logger.info("Wallet found after negative early check - starting CloudKit sync and notification registration")
        serviceContainer.startCloudKitSync(modelContainer: modelContext.container)
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - Device Registration Coordination
    
    /// Registers the current device after wallet detection or creation
    /// Should be called AFTER ServiceContainer has been configured with ModelContext
    /// - Returns: whether a registration was written (false when skipped or failed)
    @discardableResult
    private func registerDeviceIfNeeded() async -> Bool {
        // Hash from KVS, or from the seed in hand when KVS has not synced yet
        guard let hash = securityService.getWalletHashForRegistration() ?? seedDerivedWalletHash() else {
            Self.logger.debug("No wallet hash available for device registration")
            return false
        }

        // Determine if this device has the seed
        let hasSeed = securityService.hasMnemonic()

        // Register device (SwiftData operation). Detection never claims primary -
        // only the create/import flows do (registration inside WalletManager)
        let startTime = CFAbsoluteTimeGetCurrent()
        Self.logger.debug("Device registration starting...")
        do {
            try await serviceContainer.deviceRegistrationService.registerCurrentDevice(
                walletHash: hash,
                hasSeed: hasSeed,
                allowPrimaryClaim: false
            )

            Self.logger.info("Device registered with hasSeed=\(hasSeed) in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - startTime), privacy: .public)s")
            return true
        } catch {
            // Log but don't fail - device registration is not critical
            Self.logger.error("Device registration failed: \(error.localizedDescription)")
            return false
        }
    }
    
    private func seedDerivedWalletHash() -> String? {
        guard let mnemonic = (try? securityService.loadMnemonic()) ?? nil else { return nil }
        return securityService.hashMnemonic(mnemonic)
    }

    /// The link screen's one action (Device_Linking.md §4.2): record the
    /// link, register this device without a primary claim, and route again.
    /// A reinstalled primary regains its role through the registry's dedupe
    /// of its old row; everyone else becomes a secondary.
    private func linkThisDevice() async {
        isLinkingDevice = true
        defer { isLinkingDevice = false }

        // The waiting variant has nothing to link to yet; its button only
        // asks detection to look again (the mismatch has its own screen)
        if case .accountWalletAwaitingLink(let reason) = walletState,
           reason == .waitingForICloud {
            Self.logger.notice("🔗 Check again requested (\(String(describing: reason), privacy: .public)) — re-running detection")
            await checkForExistingWallet()
            return
        }
        guard let hash = securityService.getWalletHashForRegistration() ?? seedDerivedWalletHash() else {
            Self.logger.notice("🔗 Link requested without a wallet hash — re-running detection")
            await checkForExistingWallet()
            return
        }
        DeviceLinkStore.recordLink(walletHash: hash, replacingExisting: true)
        let registered = await registerDeviceIfNeeded()
        if !registered {
            // Without a row the record would route to "removed by another
            // device"; roll it back so the screen keeps its reason and the
            // user can try again
            DeviceLinkStore.clearLink()
            Self.logger.error("🔗 Link failed: device registration did not complete — link record rolled back")
        } else {
            Self.logger.notice("🔗 This install linked the account wallet")
        }
        await checkForExistingWallet()
    }

    // MARK: - Launch Check

    /// The launch-check screen's "Check Again" and post-removal routing
    private func recheckFromLaunchCheck() async {
        isLinkingDevice = true
        defer { isLinkingDevice = false }
        await checkForExistingWallet()
    }

    /// Deleted elsewhere: open onboarding at the phrase step with the local
    /// files untouched, in restore mode, so the phrase-only import opens the
    /// existing database and keeps its state (Device_Linking.md §15.1; the
    /// backup-file step is skipped because its default path replaces the
    /// database, range review I1). The link record stays until the import
    /// replaces it; a relaunch before that returns here, and the creation
    /// guard refuses while it exists.
    private func restoreFromLaunchCheck() {
        Self.logger.notice("🔗 Restore requested from the launch check — opening onboarding at the phrase step, keeping the local database")
        onboardingStart = .importWallet
        onboardingRestoresExistingDatabase = true
        walletState = .noWallet
        hasWallet = false
    }

    /// A detection re-run that lands on the mismatch while a wallet is open
    /// (iCloud sign-out or Apple ID switch mid-session): close bark without a
    /// backup, so this wallet's database is never written into another
    /// account's iCloud Drive (Device_Linking.md §15.2)
    private func closeOpenWalletOnMismatch(_ state: WalletState) async {
        guard case .accountWalletAwaitingLink(.walletMismatch) = state else { return }
        // Handle, initialised or initialising: `isInitialized` alone misses an
        // open in flight (adversarial pass 2026-11-16, F3)
        let handleOpen = (walletManager.wallet as? BarkWalletFFI)?.wallet != nil
        guard handleOpen || walletManager.isInitialized || walletManager.isInitializing else { return }
        Self.logger.warning("🔗 Account mismatch while the wallet is open — closing without a backup")
        try? await walletManager.closeWalletForMigration(backingUp: false)
    }

    /// Whether an iCloud account change can change the launch decision:
    /// the account hash no longer matches the link record, or this install
    /// is already on a link or launch-check screen. Detection re-runs
    /// `initialize()`, so a spurious account notification on a healthy
    /// linked wallet must not get that far.
    private func accountChangeMayAlterRoute() -> Bool {
        if case .accountWalletAwaitingLink = walletState { return true }
        guard let record = DeviceLinkStore.record() else { return true }
        return securityService.getUbiquitousHash() != record.walletHash
    }

    // MARK: - View Body
    
    var body: some View {
        ZStack {
            if isCheckingWallet {
                // Show loading state while checking for wallet
                LoadingView_iOS()
                    .transition(.opacity)
            } else if case .accountWalletAwaitingLink(.walletMismatch(let launchCase)) = walletState {
                // The link record names a wallet the account no longer has, or
                // a different one: the launch-check screen with its safe exits
                // (Device_Linking.md §4.5). Nothing opens, nothing registers.
                LaunchCheckView(
                    launchCase: launchCase,
                    isChecking: isLinkingDevice,
                    onCheckAgain: { Task { await recheckFromLaunchCheck() } },
                    onRestore: { restoreFromLaunchCheck() },
                    onRemoved: { Task { await recheckFromLaunchCheck() } }
                )
                .environment(walletManager)
                .transition(.opacity)
            } else if case .accountWalletAwaitingLink(let reason) = walletState {
                // The account has a wallet this install has not linked: a new
                // device, a reinstall, a local removal, or an unlink by another
                // device. Never onboarding, which would offer creating a second
                // wallet (Device_Linking.md §4.2)
                LinkWalletView(reason: reason, isLinking: isLinkingDevice) {
                    Task {
                        await linkThisDevice()
                    }
                }
                .environment(walletManager)
                .transition(.opacity)
            } else if case .walletActiveElsewhere = walletState {
                // Secondary device: Show wallet in read-only mode instead of blocking screen
                // User can view synced data but cannot perform wallet operations
                if walletManager.isInitialized {
                    WalletView_iOS(onWalletDeleted: {
                        // Stop CloudKit sync when wallet is deleted
                        serviceContainer.stopCloudKitSync()

                        // Deactivate services
                        serviceContainer.setActive(false)

                        withAnimation(.smooth(duration: 0.6)) {
                            hasWallet = false
                        }

                        // Re-run full detection instead of assuming onboarding:
                        // a full wipe routes there, but a local-only deletion
                        // routes to the rejoin screen (Wallet_Deletion_And_Rejoin.md)
                        Task {
                            await checkForExistingWallet()
                        }
                    })
                    .environment(walletManager)
                    .transition(.move(edge: .bottom))
                } else {
                    // Wallet not yet initialized in read-only mode
                    LoadingView_iOS()
                        .transition(.opacity)
                }
            } else if hasWallet {
                // Main application UI when wallet exists
                WalletView_iOS(onWalletDeleted: {
                    // Stop CloudKit sync when wallet is deleted
                    serviceContainer.stopCloudKitSync()

                    // Deactivate services
                    serviceContainer.setActive(false)

                    withAnimation(.smooth(duration: 0.6)) {
                        hasWallet = false
                    }

                    // Re-run full detection instead of assuming onboarding:
                    // a full wipe routes there, but a local-only deletion
                    // routes to the rejoin screen (Wallet_Deletion_And_Rejoin.md)
                    Task {
                        await checkForExistingWallet()
                    }
                })
                .environment(walletManager)
                .transition(.move(edge: .bottom))
            } else {
                // Onboarding sequence when no wallet found
                OnboardingFlow_iOS(
                    initialState: onboardingStart,
                    // The restore exit skips the cover screen's server picker,
                    // so it must carry the wallet's own network: importing a
                    // signet wallet as mainnet trips the import's network-
                    // mismatch retry, which wipes the directory (adversarial
                    // pass 2026-11-16, F1). Ordinary onboarding keeps mainnet.
                    initialNetworkConfig: onboardingStart == .importWallet ? (walletManager.networkConfig ?? .mainnet) : .mainnet,
                    restoresExistingDatabase: onboardingRestoresExistingDatabase,
                    onRestoreBlocked: {
                        onboardingStart = .firstUse
                        onboardingRestoresExistingDatabase = false
                        Task { await recheckFromLaunchCheck() }
                    },
                    onWalletReady: {
                        // The restore exit's mode is one-shot: a later onboarding in
                        // this session (after a deletion) starts at the cover screen
                        onboardingStart = .firstUse
                        onboardingRestoresExistingDatabase = false
                        // Transition to the wallet UI immediately - createWallet already
                        // set isInitialized and started services, so WalletView_iOS can
                        // render while the remaining setup completes in the background
                        withAnimation(.smooth(duration: 0.6)) {
                            hasWallet = true
                        }

                        Task {
                            // 1. Activate services now that wallet exists
                            serviceContainer.setActive(true)

                            // 2. Configure services with model context (CRITICAL: must happen before registration)
                            Self.logger.debug("Calling serviceContainer.configureServices()...")
                            serviceContainer.configureServices(with: modelContext)

                            // 3. Start the initial wallet sync immediately - it's the longest step
                            //    and drives the transaction list's first-load UI, so it must not
                            //    wait behind push/device registration below
                            Task {
                                Self.logger.debug("CALL #3: Initializing newly created wallet from onWalletReady callback")
                                await walletManager.initialize()
                                Self.logger.info("CALL #3: New wallet initialization complete")
                            }

                            // 4. Start CloudKit sync now that wallet exists
                            serviceContainer.startCloudKitSync(modelContainer: modelContext.container)

                            // 5. Register for remote notifications
                            await MainActor.run {
                                #if os(iOS)
                                UIApplication.shared.registerForRemoteNotifications()
                                Self.logger.info("Registered for remote notifications")
                                #endif
                            }

                            // 6. Register device (NOW ModelContext is available)
                            await registerDeviceIfNeeded()
                        }
                    }
                )
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.smooth(duration: 0.4), value: hasWallet)
        .onReceive(NotificationCenter.default.publisher(for: .walletClosedAfterUnlink)) { _ in
            // Another device unlinked this one while it ran; the wallet is
            // closed, and detection now routes to the link screen
            Task { await checkForExistingWallet() }
        }
        .task {
            Self.logger.debug(".task started")
            
            // Subscribe to NSUbiquitousKeyValueStore changes
            subscribeToUbiquitousStoreChanges()

            // No unconditional network-config sync here: reconciliation runs
            // before every wallet open (contract rule 22), which makes this
            // redundant pre-open — and harmful when it loses the race with the
            // open, flipping the local cache under runtime readers (metadata
            // export/import network stamping) while the wallet runs on the
            // old network. Removed 2026-09-25.

            // Subscribe to foreground notifications for heartbeat updates
            subscribeToForegroundNotifications()

            // Re-run detection when the keychain becomes readable, in case the launch
            // check ran while protected data was unavailable
            subscribeToProtectedDataNotifications()
            
            // Set model context first - fast operation
            Self.logger.debug("Calling walletManager.setModelContext()...")
            walletManager.setModelContext(modelContext)
            Self.logger.debug("Model context set")
            
            // CRITICAL: Always activate services before wallet detection
            // This ensures device registration works for both primary and secondary devices
            serviceContainer.setActive(true)
            serviceContainer.configureServices(with: modelContext)
            
            // Check for wallet and update UI immediately (fast path uses cached detection)
            await checkForExistingWallet()
            Self.logger.debug("checkForExistingWallet completed")
            
            // Update device heartbeat if needed (only if wallet exists)
            if hasWallet {
                await serviceContainer.deviceRegistrationService.updateHeartbeatIfNeeded()
            }
        }
        .onDisappear {
            unsubscribeFromUbiquitousStoreChanges()
            unsubscribeFromForegroundNotifications()
            unsubscribeFromProtectedDataNotifications()
        }
    }
    
    // MARK: - Protected Data Notification Handling

    private func subscribeToProtectedDataNotifications() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                // Only re-check if the last detection couldn't read the keychain
                guard !securityService.lastDetectionWasDefinitive else { return }
                Self.logger.info("Protected data became available after low-confidence detection - re-checking wallet")
                await checkForExistingWallet()
            }
        }

        Self.logger.debug("Subscribed to protected data notifications")
    }

    private func unsubscribeFromProtectedDataNotifications() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil
        )
    }

    // MARK: - Foreground Notification Handling
    
    private func subscribeToForegroundNotifications() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                // Re-check the wallet if the launch detection couldn't read the keychain,
                // or if a seed-not-synced device just received its key via iCloud Keychain.
                // The re-check updates the device registration (hasSeed) and re-derives
                // the wallet mode.
                let seedJustArrived = walletManager.connectionStatus.readOnlyReason == .seedNotSynced
                    && SecurityService.mnemonicKeychainStatus() == .found

                if !securityService.lastDetectionWasDefinitive || seedJustArrived {
                    Self.logger.info("Re-checking wallet on foreground (lowConfidence=\(!securityService.lastDetectionWasDefinitive), seedArrived=\(seedJustArrived))")
                    await checkForExistingWallet()
                }

                // Update heartbeat when app enters foreground
                await serviceContainer.deviceRegistrationService.updateHeartbeatIfNeeded()
            }
        }

        Self.logger.debug("Subscribed to foreground notifications")
    }
    
    private func unsubscribeFromForegroundNotifications() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        Self.logger.debug("Unsubscribed from foreground notifications")
    }
    
    // MARK: - NSUbiquitousKeyValueStore Observation
    
    private func subscribeToUbiquitousStoreChanges() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { notification in
            Task { @MainActor in
                await self.handleUbiquitousStoreChange(notification)
            }
        }
        
        // CloudKit's own account signal, the second re-detection trigger for
        // the launch check (Device_Linking.md §4.5)
        NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                guard self.accountChangeMayAlterRoute() else { return }
                Self.logger.notice("🔗 CKAccountChanged — re-running wallet detection")
                await self.checkForExistingWallet()
            }
        }

        Self.logger.debug("Subscribed to NSUbiquitousKeyValueStore changes")
    }
    
    private func unsubscribeFromUbiquitousStoreChanges() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        
        Self.logger.debug("Unsubscribed from NSUbiquitousKeyValueStore changes")
    }
    
    private func handleUbiquitousStoreChange(_ notification: Notification) async {
        guard let userInfo = notification.userInfo else { return }
        
        Self.logger.debug("handleUbiquitousStoreChange called")
        
        // Check if the change reason indicates an external change
        if let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int {
            let reason: String
            switch changeReason {
            case NSUbiquitousKeyValueStoreServerChange:
                reason = "Server change"
            case NSUbiquitousKeyValueStoreInitialSyncChange:
                reason = "Initial sync"
            case NSUbiquitousKeyValueStoreQuotaViolationChange:
                reason = "Quota violation"
            case NSUbiquitousKeyValueStoreAccountChange:
                reason = "Account change"
            default:
                reason = "Unknown change (\(changeReason))"
            }
            
            Self.logger.info("NSUbiquitousKeyValueStore change detected: \(reason)")

            // The account itself changed (sign-out, sign-in, Apple ID switch):
            // the whole launch decision may differ, not just the hash key
            // (Device_Linking.md §4.5). Guarded, because detection re-runs
            // initialize() on a linked wallet.
            if changeReason == NSUbiquitousKeyValueStoreAccountChange, accountChangeMayAlterRoute() {
                Self.logger.notice("🔗 iCloud KVS account change — re-running wallet detection")
                await checkForExistingWallet()
                return
            }
        }
        
        // Check if the ubiquitousHashKey was changed
        if let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
            let ubiquitousHashKey = "com.arke.wallet.mnemonicHash"
            
            if changedKeys.contains(ubiquitousHashKey) {
                // Check if the hash value exists or was deleted
                let store = NSUbiquitousKeyValueStore.default
                let hashValue = store.string(forKey: ubiquitousHashKey)
                
                if let _ = hashValue {
                    Self.logger.info("ubiquitousHashKey added - wallet created on another device, re-running wallet detection")
                } else {
                    Self.logger.info("ubiquitousHashKey removed - wallet deleted on another device, re-running wallet detection")
                }

                // Re-run the FULL detection path, not just detectWalletState():
                // checkForExistingWallet() also starts CloudKit sync + notification
                // registration (activateLateDetectedWalletServices), registers this
                // device, and initializes read-only mode. Setting walletState alone
                // wedges the view on the loading screen with
                // walletState == .walletActiveElsewhere and no initialization.
                await checkForExistingWallet()
            }
            
            // Check for device primary status changes
            let deviceId = try? serviceContainer.deviceRegistrationService.getOrCreateDeviceId()
            if let deviceId = deviceId,
               changedKeys.contains("device_\(deviceId)_isPrimary") {
                
                let kvStore = NSUbiquitousKeyValueStore.default
                let isPrimary = kvStore.bool(forKey: "device_\(deviceId)_isPrimary")
                
                if !isPrimary && kvStore.object(forKey: "device_\(deviceId)_isPrimary") != nil {
                    Self.logger.warning("⚠️ Device has been demoted from primary")
                    
                    // Set local UserDefaults flag
                    UserDefaults.standard.set(true, forKey: "device_\(deviceId)_wasDemoted")
                    
                    // Trigger wallet closure if currently running
                    NotificationCenter.default.post(name: .deviceDemotedFromPrimary, object: nil)
                } else if isPrimary {
                    Self.logger.info("✅ Device has been promoted to primary")
                    
                    // Clear demotion flag
                    UserDefaults.standard.removeObject(forKey: "device_\(deviceId)_wasDemoted")
                    
                    // Trigger re-initialization as primary
                    NotificationCenter.default.post(name: .devicePromotedToPrimary, object: nil)
                }
                // A removed flag (unlink or wipe by another device, since
                // 2026-11-13) is deliberately NOT acted on here: KVS reports
                // absent keys on initial sync and account change too, and a
                // demotion from this branch would leave no trace for the next
                // launch. The registry observer handles the live unlink from
                // the row deletion (DeviceRegistrationService.loadRegisteredDevices).
            }
        }
    }
    
    private func checkForExistingWallet() async {
        let checkStartTime = CFAbsoluteTimeGetCurrent()
        Self.logger.debug("checkForExistingWallet started")

        // Use the early detection result from app initialization
        // This avoids redundant keychain checks and SwiftData queries
        if initialWalletDetected {
            Self.logger.info("Using cached wallet detection result: wallet exists")

            // CRITICAL: Perform deeper check to determine if device is primary
            // This is necessary because the early detection only checks for mnemonic existence
            Self.logger.debug("Requesting deeper wallet state detection...")
            let state = await securityService.detectWalletState()
            walletState = state
            Self.logger.info("Deeper detection returned: \(String(describing: state))")
            
            // Handle both primary and secondary (read-only) devices
            if case .walletActiveElsewhere = state {
                Self.logger.info("📱 Wallet exists but device is not primary - initializing in read-only mode")
                hasWallet = false  // Keep false so we don't trigger normal wallet view yet

                // Disable animation for initial loading transition
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isCheckingWallet = false
                }

                // Register device before initialization - read-only mode reads the
                // device registration record during initialize()
                await registerDeviceIfNeeded()

                // Initialize wallet in read-only mode
                Task.detached { [weak walletManager] in
                    guard let walletManager = walletManager else { return }
                    Self.logger.debug("🔒 Initializing wallet in read-only mode (cached detection path)")
                    await walletManager.initialize()
                    Self.logger.info("✅ Read-only wallet initialization complete")
                }
            } else if case .accountWalletAwaitingLink = state {
                // Not linked: show the link screen. No initialization and no
                // registration until the user links (Device_Linking.md §4.2)
                Self.logger.info("🔗 Account wallet awaiting link - showing link screen (cached detection path)")
                await closeOpenWalletOnMismatch(state)
                hasWallet = false

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isCheckingWallet = false
                }
            } else if case .noWallet = state {
                // The wallet was deleted after launch (the cached early check
                // predates the deletion) — route to onboarding, not the wallet
                Self.logger.info("ℹ️ No wallet found despite positive early check (deleted this session)")
                hasWallet = false

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isCheckingWallet = false
                }
            } else {
                // Set UI state FIRST so view transitions immediately (without animation)
                hasWallet = true

                // Disable animation for initial loading transition
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isCheckingWallet = false
                }

                Self.logger.debug("UI transition complete - wallet will initialize in background")

                // Start the wallet sync immediately - primary mode doesn't depend on
                // device registration, which can take a while (CloudKit round trips)
                Task.detached { [weak walletManager] in
                    guard let walletManager = walletManager else { return }
                    Self.logger.debug("CALL #1: Initializing wallet in detached background task (cached detection path)")
                    await walletManager.initialize()
                    Self.logger.info("CALL #1: Wallet initialization complete")
                }

                // Register device (services are already configured at this point)
                await registerDeviceIfNeeded()
            }
        } else {
            // Perform deeper check only for edge cases (wallet on other device, etc.)
            Self.logger.info("No wallet detected in early check, performing deeper detection...")
            let state = await securityService.detectWalletState()
            walletState = state
            Self.logger.info("detectWalletState returned: \(String(describing: state))")
            
            switch state {
            case .walletWithSeed:
                // Wallet exists with mnemonic in local keychain
                Self.logger.info("✅ Wallet found with seed in keychain")

                // Early check missed this wallet - start the services it gates
                activateLateDetectedWalletServices()

                // Set UI state FIRST for immediate transition (without animation)
                hasWallet = true

                // Disable animation for initial loading -> wallet transition
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isCheckingWallet = false
                }

                // Start the wallet sync immediately - primary mode doesn't depend on
                // device registration, which can take a while (CloudKit round trips)
                Task.detached { [weak walletManager] in
                    guard let walletManager = walletManager else { return }
                    Self.logger.debug("CALL #2: Initializing wallet in detached background task (deep detection path, walletWithSeed)")
                    await walletManager.initialize()
                    Self.logger.info("CALL #2: Wallet initialization complete")
                }

                await registerDeviceIfNeeded()

            case .walletActiveElsewhere:
                // Wallet exists but device is not primary - initialize in read-only mode
                Self.logger.info("📱 Wallet exists but device is not primary - initializing in read-only mode")

                // Early check missed this wallet - start the services it gates
                activateLateDetectedWalletServices()

                hasWallet = false

                // Disable animation for initial loading transition
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isCheckingWallet = false
                }

                // Register device before initialization - read-only mode reads the
                // device registration record during initialize()
                await registerDeviceIfNeeded()

                // Initialize wallet in read-only mode
                Task.detached { [weak walletManager] in
                    guard let walletManager = walletManager else { return }
                    Self.logger.debug("🔒 Initializing wallet in read-only mode (deep detection path)")
                    await walletManager.initialize(forceReadOnly: true)
                    Self.logger.info("✅ Read-only wallet initialization complete")
                }

            case .accountWalletAwaitingLink:
                // Not linked: show the link screen. No initialization and no
                // registration until the user links. CloudKit sync starts now so
                // the first import can land behind the screen
                Self.logger.info("🔗 Account wallet awaiting link - showing link screen")
                activateLateDetectedWalletServices()
                await closeOpenWalletOnMismatch(state)
                hasWallet = false

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isCheckingWallet = false
                }

            case .noWallet:
                // No wallet found anywhere
                Self.logger.info("ℹ️ No wallet found")
                hasWallet = false

                // Disable animation for initial loading -> onboarding transition
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isCheckingWallet = false
                }

            case .unknown:
                // Unable to determine state
                Self.logger.warning("❓ Unable to determine wallet state")
                hasWallet = false
                
                // Disable animation for initial loading -> onboarding transition
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isCheckingWallet = false
                }
            }
        }
        
        // Single structured line summarizing how this launch was routed
        let route: String
        if case .walletActiveElsewhere = walletState {
            route = "read-only"
        } else if case .accountWalletAwaitingLink = walletState {
            route = "link"
        } else if hasWallet {
            route = "wallet"
        } else {
            route = "onboarding"
        }
        Self.logger.notice("🔍 Launch verdict: earlyDetected=\(initialWalletDetected), state=\(String(describing: walletState), privacy: .public), definitive=\(securityService.lastDetectionWasDefinitive), route=\(route, privacy: .public), took \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - checkStartTime), privacy: .public)s")
    }
}

struct LoadingView_iOS: View {
    private let randomWallpaper = "wallpaper-\(Int.random(in: 1...8))"
    @State private var shouldShow: Bool = false
    
    var body: some View {
        ZStack {
            if shouldShow {
                Image(randomWallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                
                Text(String(localized: "onboarding_look_great", defaultValue: "Hi"))
                    .font(.system(size: 64, weight: .semibold, design: .serif))
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Only show the loading view if it persists for more than 300ms
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled {
                shouldShow = true
            }
        }
    }
}
