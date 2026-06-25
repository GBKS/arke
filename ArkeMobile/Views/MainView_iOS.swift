//
//  ContentView.swift
//  Arké mobile
//
//  Created by Christoph on 11/27/25.
//

import SwiftUI
import SwiftData
import Combine
import OSLog

struct MainView_iOS: View {
    /// Logger for main view operations
    nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "MainView")
    
    @State private var hasWallet: Bool = false
    @State private var isCheckingWallet: Bool = true
    @State private var walletState: WalletState = .unknown
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.securityService) private var securityService
    @Environment(\.serviceContainer) private var serviceContainer
    @Environment(\.initialWalletDetected) private var initialWalletDetected
    
    // MARK: - Device Registration Coordination
    
    /// Registers the current device after wallet detection or creation
    /// Should be called AFTER ServiceContainer has been configured with ModelContext
    private func registerDeviceIfNeeded() async {
        // Get hash from SecurityService (no side effects)
        guard let hash = securityService.getWalletHashForRegistration() else {
            Self.logger.debug("No wallet hash available for device registration")
            return
        }
        
        // Determine if this device has the seed
        let hasSeed = securityService.hasMnemonic()
        
        // Register device (SwiftData operation)
        do {
            try await serviceContainer.deviceRegistrationService.registerCurrentDevice(
                walletHash: hash,
                hasSeed: hasSeed
            )
            
            Self.logger.info("Device registered with hasSeed=\(hasSeed)")
        } catch {
            // Log but don't fail - device registration is not critical
            Self.logger.error("Device registration failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - View Body
    
    var body: some View {
        ZStack {
            if isCheckingWallet {
                // Show loading state while checking for wallet
                LoadingView_iOS()
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
                        
                        // Reset state to show onboarding flow with animation
                        withAnimation(.smooth(duration: 0.6)) {
                            hasWallet = false
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
                    
                    // Reset state to show onboarding flow with animation
                    withAnimation(.smooth(duration: 0.6)) {
                        hasWallet = false
                    }
                })
                .environment(walletManager)
                .transition(.move(edge: .bottom))
            } else {
                // Onboarding sequence when no wallet found
                OnboardingFlow_iOS(
                    walletState: walletState,
                    onWalletReady: {
                        Task {
                            // 1. Activate services now that wallet exists
                            serviceContainer.setActive(true)
                            
                            // 2. Configure services with model context (CRITICAL: must happen before registration)
                            Self.logger.debug("Calling serviceContainer.configureServices()...")
                            serviceContainer.configureServices(with: modelContext)
                            
                            // 3. Start CloudKit sync now that wallet exists
                            serviceContainer.startCloudKitSync(modelContainer: modelContext.container)
                            
                            // 4. Register for remote notifications
                            await MainActor.run {
                                #if os(iOS)
                                UIApplication.shared.registerForRemoteNotifications()
                                Self.logger.info("Registered for remote notifications")
                                #endif
                            }
                            
                            // 5. Register device (NOW ModelContext is available)
                            await registerDeviceIfNeeded()
                            
                            // 6. Initialize the wallet FIRST (before UI transition)
                            Self.logger.debug("CALL #3: Initializing newly created wallet from onWalletReady callback")
                            await walletManager.initialize()
                            Self.logger.info("CALL #3: New wallet initialization complete")
                            
                            // 7. THEN update UI with smooth animation (all heavy work is done)
                            await MainActor.run {
                                withAnimation(.smooth(duration: 0.6)) {
                                    hasWallet = true
                                }
                            }
                        }
                    },
                    onWalletDeleted: {
                        // Re-detect wallet state after deletion
                        let newState = await securityService.detectWalletState()
                        await MainActor.run {
                            walletState = newState
                            Self.logger.info("Wallet state updated after deletion: \(String(describing: newState))")
                        }
                    }
                )
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.smooth(duration: 0.4), value: hasWallet)
        .task {
            Self.logger.debug(".task started")
            
            // Subscribe to NSUbiquitousKeyValueStore changes
            subscribeToUbiquitousStoreChanges()

            // Reconcile the network config with iCloud in the background (off the launch path)
            Task.detached(priority: .utility) {
                await NetworkConfigPersistence.syncFromiCloud()
            }

            // Subscribe to foreground notifications for heartbeat updates
            subscribeToForegroundNotifications()
            
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
        }
    }
    
    // MARK: - Foreground Notification Handling
    
    private func subscribeToForegroundNotifications() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
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
        }
        
        // Check if the ubiquitousHashKey was changed
        if let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
            let ubiquitousHashKey = "com.arke.wallet.mnemonicHash"
            
            if changedKeys.contains(ubiquitousHashKey) {
                // Check if the hash value exists or was deleted
                let store = NSUbiquitousKeyValueStore.default
                let hashValue = store.string(forKey: ubiquitousHashKey)
                
                if let _ = hashValue {
                    Self.logger.info("ubiquitousHashKey added - wallet created on another device, re-detecting wallet state")
                } else {
                    Self.logger.info("ubiquitousHashKey removed - wallet deleted on another device, re-detecting wallet state")
                }
                
                // Re-detect wallet state when hash changes
                // This will update walletState and trigger appropriate UI changes
                let newState = await securityService.detectWalletState()
                walletState = newState
                
                Self.logger.info("Wallet state updated to: \(String(describing: newState))")
                
                // If we're currently in onboarding and a wallet was created on another device,
                // the UI will automatically show the "Link existing wallet" option
                // If the hash was deleted, it will show the standard create/import options
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
            }
        }
    }
    
    private func checkForExistingWallet() async {
        Self.logger.debug("checkForExistingWallet started")
        
        // Use the early detection result from app initialization
        // This avoids redundant keychain checks and SwiftData queries
        if initialWalletDetected {
            Self.logger.info("Using cached wallet detection result: wallet exists")
            
            // CRITICAL: Perform deeper check to determine if device is primary
            // This is necessary because the early detection only checks for mnemonic existence
            let state = await securityService.detectWalletState()
            walletState = state
            Self.logger.info("Deeper detection returned: \(String(describing: state))")
            
            // Handle both primary and secondary (read-only) devices
            if case .walletActiveElsewhere = state {
                Self.logger.info("📱 Wallet exists but device is not primary - initializing in read-only mode")
                hasWallet = false  // Keep false so we don't trigger normal wallet view yet
                
                // Register device before initialization
                await registerDeviceIfNeeded()
                
                // Initialize wallet in read-only mode
                Task.detached { [weak walletManager] in
                    guard let walletManager = walletManager else { return }
                    Self.logger.debug("🔒 Initializing wallet in read-only mode (cached detection path)")
                    await walletManager.initialize()
                    Self.logger.info("✅ Read-only wallet initialization complete")
                }
            } else {
                // Set UI state FIRST so view transitions immediately (without animation)
                hasWallet = true
                
                Self.logger.debug("UI transition complete - wallet will initialize in background")
                
                // Register device (services are already configured at this point)
                await registerDeviceIfNeeded()
                
                // Initialize wallet in a detached task so it doesn't block UI
                Task.detached { [weak walletManager] in
                    guard let walletManager = walletManager else { return }
                    Self.logger.debug("CALL #1: Initializing wallet in detached background task (cached detection path)")
                    await walletManager.initialize()
                    Self.logger.info("CALL #1: Wallet initialization complete")
                }
            }
            
            // Disable animation for initial loading transition
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isCheckingWallet = false
            }
        } else {
            // Perform deeper check only for edge cases (wallet on other device, etc.)
            Self.logger.info("No wallet detected in early check, performing deeper detection...")
            let state = await securityService.detectWalletState()
            walletState = state
            Self.logger.info("detectWalletState returned: \(String(describing: state))")
            
            // Register device after detection (if not .noWallet)
            if state != .noWallet && state != .unknown {
                await registerDeviceIfNeeded()
            }
            
            switch state {
            case .walletWithSeed:
                // Wallet exists with mnemonic in local keychain
                print("✅ Wallet found with seed in keychain")
                
                // Set UI state FIRST for immediate transition (without animation)
                hasWallet = true
                
                // Disable animation for initial loading -> wallet transition
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isCheckingWallet = false
                }
                
                // Initialize wallet in detached task
                Task.detached { [weak walletManager] in
                    guard let walletManager = walletManager else { return }
                    print("🔧 [MainView_iOS] 📍 CALL #2: Initializing wallet in detached background task... at \(Date())")
                    print("   └─ Location: MainView_iOS deep detection path (walletWithSeed)")
                    await walletManager.initialize()
                    print("✅ [MainView_iOS] 📍 CALL #2: Wallet initialization complete")
                }
                
            case .walletActiveElsewhere:
                // Wallet exists but device is not primary - initialize in read-only mode
                print("📱 Wallet exists but device is not primary - initializing in read-only mode")
                hasWallet = false
                
                // Disable animation for initial loading transition
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isCheckingWallet = false
                }
                
                // Initialize wallet in read-only mode
                Task.detached { [weak walletManager] in
                    guard let walletManager = walletManager else { return }
                    print("🔒 Initializing wallet in read-only mode (deep detection path)")
                    await walletManager.initialize(forceReadOnly: true)
                    print("✅ Read-only wallet initialization complete")
                }
                
            case .walletWithoutSeed:
                // Wallet found on another device (via iCloud), but no local seed
                print("⚠️ Wallet found on another device, but no seed locally")
                // User needs to recover by entering their mnemonic
                hasWallet = false
                
                // Disable animation for initial loading -> onboarding transition
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isCheckingWallet = false
                }
                
            case .noWallet:
                // No wallet found anywhere
                print("ℹ️ No wallet found")
                hasWallet = false
                
                // Disable animation for initial loading -> onboarding transition
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isCheckingWallet = false
                }
                
            case .unknown:
                // Unable to determine state
                print("❓ Unable to determine wallet state")
                hasWallet = false
                
                // Disable animation for initial loading -> onboarding transition
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isCheckingWallet = false
                }
            }
        }
        
        print("🔍 [MainView_iOS] Wallet check complete at \(Date())")
    }
}

#Preview {
    MainView_iOS()
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
                
                Text("onboarding_look_great")
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
