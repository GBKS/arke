//
//  ServiceContainer.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/04/25.
//

import Foundation
import SwiftData
import SwiftUI

/// Container that manages all app services and their dependencies
@MainActor
@Observable
class ServiceContainer {
    
    // MARK: - Core Dependencies
    
    /// Task deduplication manager shared across all services
    let taskManager = TaskDeduplicationManager()
    
    // MARK: - Services
    
    /// Service for managing wallet security and authentication
    let securityService: SecurityService
    
    /// Service for managing tags
    let tagService: TagService
    
    /// Service for managing contacts
    let contactService: ContactService
    
    /// Service for managing contact addresses  
    let contactAddressService: ContactAddressService
    
    /// Service for managing device registry
    let deviceRegistrationService: DeviceRegistrationService
    
    /// Service for comprehensive wallet data cleanup and deletion
    let walletDataCleanupService: WalletDataCleanupService
    
    /// Service for requesting signet bitcoin from faucet
    let signetFaucetService: SignetFaucetService

    /// Service for the public exchange-rate file (fiat display only)
    let ratesService: RatesService
    
    // MARK: - CloudKit Sync
    
    /// Observer for CloudKit remote change notifications
    /// Only initialized when wallet exists and CloudKit sync is needed
    private var cloudKitObserver: CloudKitObserver?
    
    // MARK: - State
    
    /// Controls whether services should load and sync data
    /// Set to `false` during onboarding, `true` when wallet exists
    private(set) var isActive: Bool = false
    
    // MARK: - Initialization
    
    /// Shared instance of the service container
    static let shared = ServiceContainer()
    
    private init() {
        // Initialize services with the task manager
        self.securityService = SecurityService(taskManager: taskManager)
        self.tagService = TagService(taskManager: taskManager)
        self.contactService = ContactService(taskManager: taskManager)
        self.contactAddressService = ContactAddressService(taskManager: taskManager)
        self.deviceRegistrationService = DeviceRegistrationService(taskManager: taskManager)
        self.walletDataCleanupService = WalletDataCleanupService(taskManager: taskManager)
        self.signetFaucetService = SignetFaucetService(taskManager: taskManager)
        self.ratesService = RatesService(taskManager: taskManager)
        
        print("🔧 ServiceContainer initialized at \(Date())")
    }
    
    // MARK: - Activation
    
    /// Activates or deactivates the service container
    /// - Parameter active: `true` to enable data loading/syncing, `false` to keep passive
    func setActive(_ active: Bool) {
        self.isActive = active
        
        if active {
            print("✅ ServiceContainer activated - services will load and sync data")
        } else {
            print("⏸️ ServiceContainer passive - services will not load data yet")
        }
    }
    
    // MARK: - SwiftData Integration
    
    /// Configure all services with the SwiftData model context
    /// Only loads data if the container is active (wallet exists)
    func configureServices(with modelContext: ModelContext, caller: String = #function, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        
        guard isActive else {
            print("⏭️ Skipping service configuration - container is passive")
            return
        }
        
        print("🔧 [ServiceContainer] 📞 configureServices() CALLED")
        print("   ├─ From: \(fileName):\(line)")
        print("   └─ Function: \(caller)")
        
        securityService.setModelContext(modelContext)
        tagService.setModelContext(modelContext)
        contactService.setModelContext(modelContext)
        contactAddressService.setModelContext(modelContext)
        deviceRegistrationService.setModelContext(modelContext)
        walletDataCleanupService.setModelContext(modelContext)
    }
    
    // MARK: - CloudKit Sync Management
    
    /// Initialize CloudKit observer for remote change notifications
    /// Should only be called when a wallet exists
    /// - Parameter modelContainer: The ModelContainer to observe for remote changes
    func startCloudKitSync(modelContainer: ModelContainer) {
        guard isActive else {
            print("⏭️ Skipping CloudKit sync - container is passive (no wallet)")
            return
        }
        
        guard cloudKitObserver == nil else {
            print("⏭️ CloudKit observer already initialized")
            return
        }
        
        print("🌥️ Starting CloudKit sync...")
        cloudKitObserver = CloudKitObserver(modelContainer: modelContainer)
    }
    
    /// Stop CloudKit observer (called during wallet deletion)
    func stopCloudKitSync() {
        if cloudKitObserver != nil {
            print("🛑 Stopping CloudKit sync...")
            cloudKitObserver = nil  // Deinit will clean up observer
        }
    }
    
    // MARK: - Lifecycle Management
    
    /// Clean up resources when the app terminates
    func cleanup() {
        print("🧹 Cleaning up ServiceContainer")
        taskManager.cancelAll()
        stopCloudKitSync()
    }
}

// MARK: - SwiftUI Environment Integration

/// Environment key for accessing the service container
private struct ServiceContainerKey: EnvironmentKey {
    static let defaultValue = ServiceContainer.shared
}

extension EnvironmentValues {
    var serviceContainer: ServiceContainer {
        get { self[ServiceContainerKey.self] }
        set { self[ServiceContainerKey.self] = newValue }
    }
}

// MARK: - View Extensions for Service Access

extension View {
    /// Inject the service container into the environment
    func withServiceContainer(_ container: ServiceContainer) -> some View {
        environment(\.serviceContainer, container)
    }
    
    /// Inject the shared service container into the environment
    @MainActor
    func withSharedServiceContainer() -> some View {
        environment(\.serviceContainer, ServiceContainer.shared)
    }
}

// MARK: - Convenience Extensions for Service Access

/// Environment key for device registration service
private struct DeviceRegistrationServiceKey: EnvironmentKey {
    static let defaultValue: DeviceRegistrationService = ServiceContainer.shared.deviceRegistrationService
}

/// Environment key for security service
private struct SecurityServiceKey: EnvironmentKey {
    static let defaultValue: SecurityService = ServiceContainer.shared.securityService
}

/// Environment key for tag service
private struct TagServiceKey: EnvironmentKey {
    static let defaultValue: TagService = ServiceContainer.shared.tagService
}

/// Environment key for contact service
private struct ContactServiceKey: EnvironmentKey {
    static let defaultValue: ContactService = ServiceContainer.shared.contactService
}

/// Environment key for contact address service
private struct ContactAddressServiceKey: EnvironmentKey {
    static let defaultValue: ContactAddressService = ServiceContainer.shared.contactAddressService
}

/// Environment key for wallet data cleanup service
private struct WalletDataCleanupServiceKey: EnvironmentKey {
    static let defaultValue: WalletDataCleanupService = ServiceContainer.shared.walletDataCleanupService
}

/// Environment key for signet faucet service
private struct SignetFaucetServiceKey: EnvironmentKey {
    static let defaultValue: SignetFaucetService = ServiceContainer.shared.signetFaucetService
}

/// Environment key for the exchange-rate service
private struct RatesServiceKey: EnvironmentKey {
    static let defaultValue: RatesService = ServiceContainer.shared.ratesService
}

extension EnvironmentValues {
    /// Convenience accessor for the exchange-rate service
    var ratesService: RatesService {
        get { self[RatesServiceKey.self] }
        set { self[RatesServiceKey.self] = newValue }
    }

    /// Convenience accessor for the security service
    var securityService: SecurityService {
        get { self[SecurityServiceKey.self] }
        set { self[SecurityServiceKey.self] = newValue }
    }
    
    /// Convenience accessor for the tag service
    var tagService: TagService {
        get { self[TagServiceKey.self] }
        set { self[TagServiceKey.self] = newValue }
    }
    
    /// Convenience accessor for the contact service
    var contactService: ContactService {
        get { self[ContactServiceKey.self] }
        set { self[ContactServiceKey.self] = newValue }
    }
    
    /// Convenience accessor for the contact address service
    var contactAddressService: ContactAddressService {
        get { self[ContactAddressServiceKey.self] }
        set { self[ContactAddressServiceKey.self] = newValue }
    }
    
    /// Convenience accessor for the device registration service
    var deviceRegistrationService: DeviceRegistrationService {
        get { self[DeviceRegistrationServiceKey.self] }
        set { self[DeviceRegistrationServiceKey.self] = newValue }
    }
    
    /// Convenience accessor for the wallet data cleanup service
    var walletDataCleanupService: WalletDataCleanupService {
        get { self[WalletDataCleanupServiceKey.self] }
        set { self[WalletDataCleanupServiceKey.self] = newValue }
    }
    
    /// Convenience accessor for the signet faucet service
    var signetFaucetService: SignetFaucetService {
        get { self[SignetFaucetServiceKey.self] }
        set { self[SignetFaucetServiceKey.self] = newValue }
    }
}
