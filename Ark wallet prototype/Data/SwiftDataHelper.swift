//
//  SwiftDataHelper.swift
//  Ark wallet prototype
//
//  Created on 10/29/25.
//

import Foundation
import SwiftData

/// Helper for managing SwiftData ModelContainer with automatic store deletion on migration errors
struct SwiftDataHelper {
    
    /// Creates a ModelContainer with automatic fallback to delete and recreate on migration errors
    static func createModelContainer(for types: any PersistentModel.Type..., inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(types)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            print("✅ ModelContainer created successfully")
            return container
        } catch {
            // Check if this is a migration error (common error codes: 134110, 134100)
            if let nsError = error as NSError?,
               nsError.domain == NSCocoaErrorDomain,
               [134110, 134100, 134060].contains(nsError.code) {
                
                print("⚠️ Migration error detected: \(nsError.localizedDescription)")
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
                print("❌ Failed to create ModelContainer: \(error)")
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
        
        let storeNames = ["default.store", "default.store-shm", "default.store-wal"]
        
        for storeName in storeNames {
            let storeURL = appSupportURL.appendingPathComponent(storeName)
            if FileManager.default.fileExists(atPath: storeURL.path) {
                do {
                    try FileManager.default.removeItem(at: storeURL)
                    print("🗑️ Deleted store file: \(storeName)")
                } catch {
                    print("⚠️ Failed to delete store file \(storeName): \(error)")
                }
            }
        }
    }
}