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
                    walletState: walletState,
                    onWalletReady: {
                        Task {
                            // Activate services now that wallet exists
                            serviceContainer.setActive(true)
                            
                            // Configure services with model context to begin loading data
                            serviceContainer.configureServices(with: modelContext)
                            
                            // Initialize the wallet after creation
                            await walletManager.initialize()
                            hasWallet = true
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
                    print("✅ [MainView] ubiquitousHashKey added - wallet created on another device")
                    print("   → Re-detecting wallet state to show 'Link existing wallet' option")
                    #endif
                } else {
                    #if DEBUG
                    print("🗑️ [MainView] ubiquitousHashKey removed - wallet deleted on another device")
                    print("   → Re-detecting wallet state to hide 'Link existing wallet' option")
                    #endif
                }
                
                // Re-detect wallet state when hash changes
                // This will update walletState and trigger appropriate UI changes
                let newState = await securityService.detectWalletState()
                walletState = newState
                
                #if DEBUG
                print("🔄 [MainView] Wallet state updated to: \(newState)")
                #endif
                
                // If we're currently in onboarding and a wallet was created on another device,
                // the UI will automatically show the "Link existing wallet" option
                // If the hash was deleted, it will show the standard create/import options
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
                
                print("🔍 [MainView] UI transition complete - wallet will initialize in true background")
                
                // Initialize wallet in a detached task so it doesn't block UI
                Task.detached { [weak walletManager] in
                    guard let walletManager = walletManager else { return }
                    print("🔧 [MainView] Initializing wallet in detached background task... at \(Date())")
                    await walletManager.initialize()
                    print("✅ [MainView] Wallet initialization complete at \(Date())")
                }
            }
            
            isCheckingWallet = false
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
                
                // Set UI state FIRST for immediate transition
                hasWallet = true
                isCheckingWallet = false
                
                // Initialize wallet in detached task
                Task.detached { [weak walletManager] in
                    guard let walletManager = walletManager else { return }
                    print("🔧 [MainView] Initializing wallet in detached background task... at \(Date())")
                    await walletManager.initialize()
                    print("✅ [MainView] Wallet initialization complete")
                }
                
            case .walletActiveElsewhere:
                // Wallet exists but device is not primary - initialize in read-only mode
                print("📱 Wallet exists but device is not primary - initializing in read-only mode")
                hasWallet = false
                isCheckingWallet = false
                
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
                isCheckingWallet = false
                
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
        
        print("🔍 [MainView] Wallet check complete at \(Date())")
    }
}

#Preview {
    MainView()
}
