//
//  MainView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import SwiftData
import Combine

struct MainView: View {
    @State private var hasWallet: Bool = false
    @State private var isCheckingWallet: Bool = true
    @State private var walletState: WalletState = .unknown
    @State private var lateServicesActivated: Bool = false
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.securityService) private var securityService
    @Environment(\.serviceContainer) private var serviceContainer
    @Environment(\.initialWalletDetected) private var initialWalletDetected
    
    var body: some View {
        Group {
            if isCheckingWallet {
                // Show loading state while checking for wallet
                LoadingView()
            } else if case .walletActiveElsewhere = walletState {
                // Secondary device: Show wallet in read-only mode instead of blocking screen
                // User can view synced data but cannot perform wallet operations
                if walletManager.isInitialized {
                    WalletView(onWalletDeleted: {
                        // Reset state to show onboarding flow
                        hasWallet = false
                    })
                    .environment(walletManager)
                } else {
                    // Wallet not yet initialized in read-only mode
                    LoadingView()
                }
            } else if hasWallet {
                // Main application UI when wallet exists
                WalletView(onWalletDeleted: {
                    // Reset state to show onboarding flow
                    hasWallet = false
                })
                .environment(walletManager)
            } else {
                // Onboarding sequence when no wallet found
                OnboardingFlow(
                    onWalletReady: {
                        // Transition to the wallet UI immediately - createWallet already
                        // set isInitialized and started services, so WalletView can
                        // render while the remaining setup completes in the background
                        hasWallet = true

                        Task {
                            // 1. Activate services now that wallet exists
                            serviceContainer.setActive(true)

                            // 2. Configure services with model context (CRITICAL: must happen before registration)
                            serviceContainer.configureServices(with: modelContext)

                            // 3. Start the initial wallet sync immediately - it's the longest step
                            //    and drives the transaction list's first-load UI, so it must not
                            //    wait behind device registration below
                            Task {
                                print("🔧 [MainView] Initializing newly created wallet from onWalletReady callback")
                                await walletManager.initialize()
                                print("✅ [MainView] New wallet initialization complete")
                            }

                            // 4. Start CloudKit sync now that wallet exists
                            serviceContainer.startCloudKitSync(modelContainer: modelContext.container)

                            // 5. Register for remote notifications (CloudKit push)
                            NSApplication.shared.registerForRemoteNotifications()

                            // 6. Register device (NOW ModelContext is available)
                            await registerDeviceIfNeeded()
                        }
                    }
                )
            }
        }
        .task {
            print("🔍 [MainView] .task started at \(Date())")
            
            // Subscribe to NSUbiquitousKeyValueStore changes
            subscribeToUbiquitousStoreChanges()

            // Reconcile the network config with iCloud in the background (off the launch path)
            Task.detached(priority: .utility) {
                await NetworkConfigPersistence.syncFromiCloud()
            }

            // Set model context first - fast operation
            print("🔍 [MainView] Setting model context...")
            walletManager.setModelContext(modelContext)
            print("🔍 [MainView] Model context set at \(Date())")
            
            // CRITICAL: Always activate services before wallet detection
            // This ensures device registration works for both primary and secondary devices
            serviceContainer.setActive(true)
            serviceContainer.configureServices(with: modelContext)
            
            // Check for wallet and update UI immediately (fast path uses cached detection)
            await checkForExistingWallet()
            print("🔍 [MainView] checkForExistingWallet completed at \(Date())")
            
            // Update device heartbeat if needed (only if wallet exists)
            if hasWallet {
                await serviceContainer.deviceRegistrationService.updateHeartbeatIfNeeded()
            }
        }
        .onDisappear {
            unsubscribeFromUbiquitousStoreChanges()
        }
    }
    
    // MARK: - Late Wallet Detection

    /// Starts the services that the App body gates on `initialWalletDetected`.
    /// When the early keychain check missed (keychain transiently unreadable) but deeper
    /// detection finds the wallet, CloudKit sync and remote notification registration
    /// would otherwise silently never run for this session.
    private func activateLateDetectedWalletServices() {
        guard !initialWalletDetected, !lateServicesActivated else { return }
        lateServicesActivated = true

        print("🔄 [MainView] Wallet found after negative early check - starting CloudKit sync and notification registration")
        serviceContainer.startCloudKitSync(modelContainer: modelContext.container)
        NSApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - Device Registration Coordination

    /// Registers the current device after wallet detection or creation
    /// Should be called AFTER ServiceContainer has been configured with ModelContext
    private func registerDeviceIfNeeded() async {
        // Get hash from SecurityService (no side effects)
        guard let hash = securityService.getWalletHashForRegistration() else {
            print("ℹ️ [MainView] No wallet hash available for device registration")
            return
        }

        // Determine if this device has the seed
        let hasSeed = securityService.hasMnemonic()

        // Register device (SwiftData operation). Detection never claims primary -
        // only the create/import flows do (registration inside WalletManager)
        print("🔍 [MainView] Device registration starting...")
        do {
            try await serviceContainer.deviceRegistrationService.registerCurrentDevice(
                walletHash: hash,
                hasSeed: hasSeed,
                allowPrimaryClaim: false
            )

            print("✅ [MainView] Device registered with hasSeed=\(hasSeed)")
        } catch {
            // Log but don't fail - device registration is not critical
            print("⚠️ [MainView] Device registration failed: \(error.localizedDescription)")
        }
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
        
        #if DEBUG
        print("🔔 [MainView] Subscribed to NSUbiquitousKeyValueStore changes")
        #endif
    }
    
    private func unsubscribeFromUbiquitousStoreChanges() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        
        #if DEBUG
        print("🔕 [MainView] Unsubscribed from NSUbiquitousKeyValueStore changes")
        #endif
    }
    
    private func handleUbiquitousStoreChange(_ notification: Notification) async {
        guard let userInfo = notification.userInfo else { return }
        
        #if DEBUG
        print("🔕 [MainView] handleUbiquitousStoreChange")
        #endif
        
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
            
            #if DEBUG
            print("📦 [MainView] NSUbiquitousKeyValueStore change detected: \(reason)")
            #endif
        }
        
        // Check if the ubiquitousHashKey was changed
        if let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
            let ubiquitousHashKey = "com.arke.wallet.mnemonicHash"
            
            if changedKeys.contains(ubiquitousHashKey) {
                // Check if the hash value exists or was deleted
                let store = NSUbiquitousKeyValueStore.default
                let hashValue = store.string(forKey: ubiquitousHashKey)
                
                if let _ = hashValue {
                    #if DEBUG
                    print("✅ [MainView] ubiquitousHashKey added - wallet created on another device, re-running wallet detection")
                    #endif
                } else {
                    #if DEBUG
                    print("🗑️ [MainView] ubiquitousHashKey removed - wallet deleted on another device, re-running wallet detection")
                    #endif
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
                    print("⚠️ [MainView] Device has been demoted from primary")

                    // Set local UserDefaults flag
                    UserDefaults.standard.set(true, forKey: "device_\(deviceId)_wasDemoted")

                    // Trigger wallet closure if currently running
                    NotificationCenter.default.post(name: .deviceDemotedFromPrimary, object: nil)
                } else if isPrimary {
                    print("✅ [MainView] Device has been promoted to primary")

                    // Clear demotion flag
                    UserDefaults.standard.removeObject(forKey: "device_\(deviceId)_wasDemoted")

                    // Trigger re-initialization as primary
                    NotificationCenter.default.post(name: .devicePromotedToPrimary, object: nil)
                }
            }
        }
    }
    
    private func checkForExistingWallet() async {
        print("🔍 [MainView] checkForExistingWallet started at \(Date())")
        
        // Use the early detection result from app initialization
        // This avoids redundant keychain checks and SwiftData queries
        if initialWalletDetected {
            print("✅ Using cached wallet detection result: wallet exists")
            
            // CRITICAL: Perform deeper check to determine if device is primary
            // This is necessary because the early detection only checks for mnemonic existence
            let state = await securityService.detectWalletState()
            walletState = state
            print("🔍 [MainView] Deeper detection returned: \(state)")
            
            // Handle both primary and secondary (read-only) devices
            if case .walletActiveElsewhere = state {
                print("📱 Wallet exists but device is not primary - initializing in read-only mode")
                hasWallet = false  // Keep false so we don't trigger normal wallet view yet
                isCheckingWallet = false

                // Register device before initialization - read-only mode reads the
                // device registration record during initialize()
                await registerDeviceIfNeeded()

                // Initialize wallet in read-only mode
                Task.detached { [weak walletManager] in
                    guard let walletManager = walletManager else { return }
                    print("🔒 Initializing wallet in read-only mode (cached detection path)")
                    await walletManager.initialize(forceReadOnly: true)
                    print("✅ Read-only wallet initialization complete")
                }
            } else {
                // Set UI state FIRST so view transitions immediately
                hasWallet = true
                isCheckingWallet = false

                print("🔍 [MainView] UI transition complete - wallet will initialize in true background")

                // Start the wallet sync immediately - primary mode doesn't depend on
                // device registration, which can take a while (CloudKit round trips)
                Task.detached { [weak walletManager] in
                    guard let walletManager = walletManager else { return }
                    print("🔧 [MainView] Initializing wallet in detached background task... at \(Date())")
                    await walletManager.initialize()
                    print("✅ [MainView] Wallet initialization complete at \(Date())")
                }

                // Register device (services are already configured at this point)
                await registerDeviceIfNeeded()
            }
        } else {
            // Perform deeper check only for edge cases (wallet on other device, etc.)
            print("⚠️ No wallet detected in early check, performing deeper detection...")
            let state = await securityService.detectWalletState()
            walletState = state
            print("🔍 [MainView] detectWalletState returned: \(state) at \(Date())")
            
            switch state {
            case .walletWithSeed:
                // Wallet exists with mnemonic in local keychain
                print("✅ Wallet found with seed in keychain")

                // Early check missed this wallet - start the services it gates
                activateLateDetectedWalletServices()

                // Set UI state FIRST for immediate transition
                hasWallet = true
                isCheckingWallet = false
                
                // Start the wallet sync immediately - primary mode doesn't depend on
                // device registration, which can take a while (CloudKit round trips)
                Task.detached { [weak walletManager] in
                    guard let walletManager = walletManager else { return }
                    print("🔧 [MainView] Initializing wallet in detached background task... at \(Date())")
                    await walletManager.initialize()
                    print("✅ [MainView] Wallet initialization complete")
                }

                await registerDeviceIfNeeded()

            case .walletActiveElsewhere:
                // Wallet exists but device is not primary - initialize in read-only mode
                print("📱 Wallet exists but device is not primary - initializing in read-only mode")

                // Early check missed this wallet - start the services it gates
                activateLateDetectedWalletServices()

                hasWallet = false
                isCheckingWallet = false

                // Register device before initialization - read-only mode reads the
                // device registration record during initialize()
                await registerDeviceIfNeeded()

                // Initialize wallet in read-only mode
                Task.detached { [weak walletManager] in
                    guard let walletManager = walletManager else { return }
                    print("🔒 Initializing wallet in read-only mode (deep detection path)")
                    await walletManager.initialize(forceReadOnly: true)
                    print("✅ Read-only wallet initialization complete")
                }
                
            case .noWallet:
                // No wallet found anywhere
                print("ℹ️ No wallet found")
                hasWallet = false
                isCheckingWallet = false
                
            case .unknown:
                // Unable to determine state
                print("❓ Unable to determine wallet state")
                hasWallet = false
                isCheckingWallet = false
            }
        }
        
        // Single structured line summarizing how this launch was routed
        let route: String
        if case .walletActiveElsewhere = walletState {
            route = "read-only"
        } else if hasWallet {
            route = "wallet"
        } else {
            route = "onboarding"
        }
        print("🔍 [MainView] Launch verdict: earlyDetected=\(initialWalletDetected), state=\(walletState), definitive=\(securityService.lastDetectionWasDefinitive), route=\(route)")
    }
}
