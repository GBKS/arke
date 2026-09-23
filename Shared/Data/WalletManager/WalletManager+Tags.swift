//
//  WalletManager+Tags.swift
//  Arké
//
//  Tag management operations
//  All operations delegate to TagService for persistence and relationship management
//

import Foundation
import OSLog
import ArkeUI

extension WalletManager {
    
    // MARK: - Tag Properties
    
    var tags: [TagModel] {
        tagService.tags
    }
    
    var hasTags: Bool {
        tagService.hasTags
    }
    
    var tagServiceError: String? {
        tagService.error
    }
    
    /// Access to TagService for SwiftUI environment injection
    var tagServiceForEnvironment: TagService {
        tagService
    }
    
    // MARK: - Tag Operations
    
    /// Create a new tag
    func createTag(_ tagModel: TagModel) async throws -> TagModel {
        return try await tagService.createTag(tagModel)
    }
    
    /// Update an existing tag
    func updateTag(_ tagModel: TagModel) async throws {
        try await tagService.updateTag(tagModel)
    }
    
    /// Delete a tag using soft delete (preserves historical data)
    func deleteTag(_ tagId: UUID) async throws {
        try await tagService.deleteTag(tagId)
    }
    
    /// Assign a tag to a transaction
    func assignTag(_ tagId: UUID, to transactionTxid: String) async throws {
        try await tagService.assignTag(tagId, to: transactionTxid)
        dataVersion += 1
        Self.logger.debug("DataVersion incremented to \(self.dataVersion) after tag assignment")
    }
    
    /// Remove a tag assignment from a transaction
    func unassignTag(_ tagId: UUID, from transactionTxid: String) async throws {
        try await tagService.unassignTag(tagId, from: transactionTxid)
        dataVersion += 1
        Self.logger.debug("DataVersion incremented to \(self.dataVersion) after tag unassignment")
    }
    
    /// Get all transactions with a specific tag
    func getTransactionsWithTag(_ tagId: UUID) async throws -> [TransactionModel] {
        return try await tagService.getTransactionsWithTag(tagId)
    }
    
    /// Create default tags if needed
    ///
    /// Primary devices only. The seeding condition is "no tags exist", which is
    /// briefly true on a secondary device too — the store is empty until the
    /// first CloudKit import lands — so a secondary would create its own nine
    /// defaults and then receive the primary's, leaving 18 (2026-09-23, second
    /// iPhone). Default data belongs to the wallet, not to the device, so only
    /// the device that owns the wallet seeds it.
    func createDefaultTagsIfNeeded() async {
        guard !isReadOnlyMode else {
            Self.logger.info("⏭️ [WalletManager] Read-only device — not seeding default tags")
            return
        }

        await tagService.createDefaultTagsIfNeeded()
    }
    
    /// Get tag usage statistics
    func getTagStatistics() async throws -> [TagStatistic] {
        return try await tagService.getTagStatistics()
    }
    
    /// Get all tags assigned to a specific transaction
    func getTransactionTags(_ transactionId: String) async throws -> [TagModel] {
        return try await tagService.getTagsForTransaction(transactionId)
    }
    
    /// Check if a transaction has any tags
    func transactionHasTags(_ transactionId: String) async throws -> Bool {
        let tags = try await getTransactionTags(transactionId)
        return !tags.isEmpty
    }
    
    /// Clear tag service errors
    func clearTagError() {
        tagService.clearError()
    }
}
