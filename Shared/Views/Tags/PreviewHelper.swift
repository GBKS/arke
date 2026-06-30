//
//  PreviewHelper.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/17/25.
//

import Foundation
import SwiftData
import SwiftUI
import ArkeUI

/// Provides isolated preview environments that don't affect production data
@MainActor
struct PreviewHelper {
    
    /// Creates an in-memory ModelContainer for previews
    /// - Returns: A ModelContainer with in-memory storage that disappears when the preview ends
    static func createPreviewContainer() -> ModelContainer {
        return SwiftDataHelper.createModelContainer(
            for: PersistentTransaction.self,
                ArkBalanceModel.self,
                OnchainBalanceModel.self,
                PersistentTag.self,
                TransactionTagAssignment.self,
                PersistentContact.self,
                TransactionContactAssignment.self,
                PersistentContactAddress.self,
            inMemory: true  // Critical: Use in-memory storage for previews
        )
    }
    
    /// Creates a WalletManager configured for preview use with isolated storage
    /// - Parameters:
    ///   - container: Optional ModelContainer. If nil, creates a new in-memory container
    ///   - populateWithDefaultTags: Whether to populate with default tags
    /// - Returns: A fully configured WalletManager safe for preview use
    static func createPreviewWalletManager(
        container: ModelContainer? = nil,
        populateWithDefaultTags: Bool = true
    ) async -> WalletManager {
        let previewContainer = container ?? createPreviewContainer()
        let context = ModelContext(previewContainer)
        
        let walletManager = WalletManager(useMock: true)
        walletManager.setModelContext(context)
        
        if populateWithDefaultTags {
            await walletManager.createDefaultTagsIfNeeded()
        }
        
        return walletManager
    }
    
    /// Creates a WalletManager with an empty tag list for testing empty states
    /// - Returns: A WalletManager with no tags in an isolated environment
    static func createEmptyPreviewWalletManager() async -> WalletManager {
        return await createPreviewWalletManager(populateWithDefaultTags: false)
    }
    
    /// Creates a WalletManager with sample data for comprehensive testing
    /// - Returns: A WalletManager with various test tags
    static func createSampleDataWalletManager() async -> WalletManager {
        let container = createPreviewContainer()
        let context = ModelContext(container)
        
        let walletManager = WalletManager(useMock: true)
        walletManager.setModelContext(context)
        
        // Create sample tags with various configurations
        let sampleTags = [
            TagModel(name: "Groceries", colorHex: "#FF6B6B", emoji: "🛒"),
            TagModel(name: "Rent", colorHex: "#4ECDC4", emoji: "🏠"),
            TagModel(name: "Entertainment", colorHex: "#95E1D3", emoji: "🎮"),
            TagModel(name: "Utilities", colorHex: "#F38181", emoji: "⚡"),
            TagModel(name: "Savings", colorHex: "#FFA07A", emoji: "💰")
        ]
        
        for tag in sampleTags {
            _ = try? await walletManager.createTag(tag)
        }
        
        return walletManager
    }
}

// MARK: - Convenience Extensions for Previews

extension View {
    /// Configures the view with an isolated preview environment
    /// - Parameters:
    ///   - walletManager: The preview WalletManager to use
    ///   - container: The preview ModelContainer to use
    /// - Returns: The view configured for safe preview use
    @MainActor
    func previewEnvironment(
        walletManager: WalletManager,
        container: ModelContainer
    ) -> some View {
        self
            .environment(walletManager)
            .modelContainer(container)
    }
}

#if DEBUG
extension ProcessInfo {
    /// Returns true if the code is running inside a SwiftUI preview
    static var isPreview: Bool {
        processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
#endif
