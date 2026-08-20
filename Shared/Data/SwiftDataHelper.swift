//
//  SwiftDataHelper.swift
//  Ark wallet prototype
//
//  Created on 10/29/25.
//

import Foundation
import SwiftData
import CoreData

/// Helper for managing SwiftData ModelContainer with automatic store deletion on migration errors
///
/// ## CloudKit Compatibility
/// When using CloudKit, unique constraints are not supported. This helper provides utilities
/// to enforce uniqueness at the application level.
///
/// ## Usage Examples
///
/// ### Creating a Container
/// ```swift
/// let container = SwiftDataHelper.createModelContainer(
///     for: BackupStatus.self,
///     cloudKitEnabled: true
/// )
/// ```
///
/// ### Working with Singleton (BackupStatus)
/// ```swift
/// let context = container.mainContext
/// let uniqueness = SwiftDataHelper.uniqueness(for: context)
///
/// // Get singleton instance (creates if needed)
/// let backupStatus = try uniqueness.getBackupStatus()
///
/// // Cleanup duplicates on app launch
/// try uniqueness.cleanupDuplicateBackupStatus()
/// ```
struct SwiftDataHelper {

    /// Canonical list of every SwiftData model in the app schema.
    ///
    /// Single source of truth: both app targets build their container from this
    /// list, and the wipe-coverage test asserts that WalletDataCleanupService
    /// accounts for every entry (directly wiped, cascade-wiped, or explicitly
    /// exempt). Add new @Model types HERE and then decide their deletion fate —
    /// the test fails until you do (Wallet_Deletion_And_Rejoin.md).
    static let appSchemaModels: [any PersistentModel.Type] = [
        PersistentTransaction.self,
        ArkBalanceModel.self,
        OnchainBalanceModel.self,
        PersistentTag.self,
        TransactionTagAssignment.self,
        PersistentContact.self,
        TransactionContactAssignment.self,
        PersistentContactAddress.self,
        WalletConfiguration.self,
        DeviceRegistration.self,          // 📱 Device registry for cross-device management
        BackupStatus.self,                // 💾 Backup reminder state
        PersistentAddress.self,           // 📍 Address history for gap limit & internal transfers
        UserProfile.self,                 // 👤 User profile for personalization features
        PersistentExitCache.self,         // 🚪 Exit cache for fast UI rendering
        PendingPaymentMetadata.self,      // 📤 Pending metadata for send flow
        PendingTagAssignment.self         // 🏷️ Pending tag assignments for send flow
    ]

    /// Creates the app's ModelContainer from the canonical schema list
    static func createAppModelContainer(
        inMemory: Bool = false,
        cloudKitEnabled: Bool = false,
        cloudKitContainerIdentifier: String? = nil
    ) -> ModelContainer {
        createModelContainer(
            types: appSchemaModels,
            inMemory: inMemory,
            cloudKitEnabled: cloudKitEnabled,
            cloudKitContainerIdentifier: cloudKitContainerIdentifier
        )
    }

    /// Manually deletes all SwiftData stores (useful for debugging)
    /// - Returns: True if successful, false otherwise
    @discardableResult
    static func resetAllStores() -> Bool {
        deleteExistingStore()
        return true
    }

    /// Creates a ModelContainer with automatic fallback to delete and recreate on migration errors
    /// - Parameters:
    ///   - types: The model types to include in the schema
    ///   - inMemory: Whether to use in-memory storage (default: false)
    ///   - cloudKitEnabled: Whether to enable CloudKit syncing (default: false)
    ///   - cloudKitContainerIdentifier: Optional custom CloudKit container identifier
    /// - Returns: A configured ModelContainer
    static func createModelContainer(
        for types: any PersistentModel.Type...,
        inMemory: Bool = false,
        cloudKitEnabled: Bool = false,
        cloudKitContainerIdentifier: String? = nil
    ) -> ModelContainer {
        createModelContainer(
            types: types,
            inMemory: inMemory,
            cloudKitEnabled: cloudKitEnabled,
            cloudKitContainerIdentifier: cloudKitContainerIdentifier
        )
    }

    /// Array-based core of `createModelContainer(for:...)`
    static func createModelContainer(
        types: [any PersistentModel.Type],
        inMemory: Bool = false,
        cloudKitEnabled: Bool = false,
        cloudKitContainerIdentifier: String? = nil
    ) -> ModelContainer {
        let schema = Schema(types)
        
        // Create configuration with CloudKit support if enabled
        let configuration: ModelConfiguration
        if cloudKitEnabled {
            // Use custom container identifier if provided, otherwise use automatic
            if let containerIdentifier = cloudKitContainerIdentifier {
                configuration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: inMemory,
                    cloudKitDatabase: .private(containerIdentifier)
                )
                print("🌥️ CloudKit enabled with container: \(containerIdentifier)")
            } else {
                configuration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: inMemory,
                    cloudKitDatabase: .automatic
                )
                print("🌥️ CloudKit enabled with automatic container")
            }
        } else {
            // Local storage only
            configuration = ModelConfiguration(
                schema: schema, 
                isStoredInMemoryOnly: inMemory
            )
            print("💾 Local storage only (CloudKit disabled)")
        }
        
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            
            // Enable persistent history tracking for CloudKit sync
            if cloudKitEnabled {
                enablePersistentHistoryTracking(for: container)
            }
            
            print("✅ ModelContainer created successfully")
            return container
        } catch {
            // Check if this is a SwiftData error or migration error
            let shouldDeleteStore: Bool
            
            // Check for SwiftDataError.loadIssueModelContainer
            if let swiftDataError = error as? SwiftDataError {
                print("⚠️ SwiftData error detected: \(swiftDataError)")
                shouldDeleteStore = true
            }
            // Check for NSCocoaError migration issues (common error codes: 134110, 134100, 134060)
            else if let nsError = error as NSError?,
                    nsError.domain == NSCocoaErrorDomain,
                    [134110, 134100, 134060].contains(nsError.code) {
                print("⚠️ Migration error detected: \(nsError.localizedDescription)")
                shouldDeleteStore = true
            } else {
                print("❌ Failed to create ModelContainer: \(error)")
                shouldDeleteStore = false
            }
            
            if shouldDeleteStore {
                print("🗑️ Deleting existing store and creating new one...")
                
                // Delete existing store files
                deleteExistingStore()
                
                // Try creating container again
                do {
                    let container = try ModelContainer(for: schema, configurations: configuration)
                    print("✅ ModelContainer created successfully after store deletion")
                    return container
                } catch {
                    print("❌ Failed to create ModelContainer even after deleting store: \(error)")
                    fatalError("Could not create ModelContainer: \(error)")
                }
            } else {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }
    
    /// Deletes existing SwiftData store files from the app support directory
    private static func deleteExistingStore() {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, 
                                                          in: .userDomainMask).first else {
            print("❌ Could not find application support directory")
            return
        }
        
        print("📂 Searching for stores in: \(appSupportURL.path)")
        
        // Try to find and delete all .store files and related files
        do {
            let fileManager = FileManager.default
            
            // Create app support directory if it doesn't exist
            if !fileManager.fileExists(atPath: appSupportURL.path) {
                try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
                print("📁 Created app support directory")
                return // No stores to delete if directory didn't exist
            }
            
            // Get all files in the directory
            let contents = try fileManager.contentsOfDirectory(at: appSupportURL, 
                                                               includingPropertiesForKeys: nil)
            
            // Delete all .store files and their associated files
            for fileURL in contents {
                let fileName = fileURL.lastPathComponent
                if fileName.hasSuffix(".store") || 
                   fileName.hasSuffix(".store-shm") || 
                   fileName.hasSuffix(".store-wal") {
                    do {
                        try fileManager.removeItem(at: fileURL)
                        print("🗑️ Deleted: \(fileName)")
                    } catch {
                        print("⚠️ Failed to delete \(fileName): \(error)")
                    }
                }
            }
            
            print("✅ Store cleanup complete")
            
        } catch {
            print("⚠️ Error during store cleanup: \(error)")
        }
    }
    
    // MARK: - Persistent History Tracking
    
    /// Enables persistent history tracking on the ModelContainer's underlying Core Data store
    /// This is required for reliable CloudKit remote change notifications
    private static func enablePersistentHistoryTracking(for container: ModelContainer) {
        // Access the underlying persistent store descriptions through reflection
        // This is necessary because SwiftData doesn't expose these directly
        guard let persistentStoreDescriptions = Mirror(reflecting: container)
            .children
            .first(where: { $0.label == "persistentStoreDescriptions" })?
            .value as? [NSPersistentStoreDescription] else {
            print("⚠️ Could not access persistent store descriptions")
            return
        }
        
        for storeDescription in persistentStoreDescriptions {
            // Enable persistent history tracking (required for remote change notifications)
            storeDescription.setOption(true as NSNumber, 
                                       forKey: NSPersistentHistoryTrackingKey)
            
            // Enable remote change notifications
            storeDescription.setOption(true as NSNumber,
                                       forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            
            print("📝 Enabled persistent history tracking and remote notifications")
        }
    }
}

// MARK: - ModelContext Utilities

extension SwiftDataHelper {
    /// Helper to safely perform operations with uniqueness checks
    /// Use this to ensure singleton patterns work correctly without database-level unique constraints
    struct UniquenesHelper {
        let context: ModelContext
        
        /// Get the singleton BackupStatus instance
        func getBackupStatus() throws -> BackupStatus {
            try BackupStatus.getSingleton(context: context)
        }
        
        /// Cleanup duplicate BackupStatus instances (should be called on app launch)
        func cleanupDuplicateBackupStatus() throws {
            let descriptor = FetchDescriptor<BackupStatus>()
            let all = try context.fetch(descriptor)
            
            guard all.count > 1 else {
                print("✅ No duplicate BackupStatus instances found")
                return
            }
            
            // Keep the first one, delete the rest
            for duplicate in all.dropFirst() {
                context.delete(duplicate)
                print("🗑️ Deleted duplicate BackupStatus instance")
            }
            
            try context.save()
            print("✅ Cleaned up \(all.count - 1) duplicate BackupStatus instance(s)")
        }
    }
    
    /// Create a uniqueness helper for the given context
    /// - Parameter context: The ModelContext to use
    /// - Returns: A UniquenesHelper instance
    static func uniqueness(for context: ModelContext) -> UniquenesHelper {
        UniquenesHelper(context: context)
    }
}
