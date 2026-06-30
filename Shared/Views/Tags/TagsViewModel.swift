//
//  TagsViewModel.swift
//  Ark wallet prototype
//
//  Created by Assistant on 12/2/25.
//

import SwiftUI
import ArkeUI

/// Shared view model for tag management across macOS and iOS
@Observable
@MainActor
final class TagsViewModel {
    
    // MARK: - Dependencies
    
    private let walletManager: WalletManager
    
    // MARK: - State
    
    var tagStatistics: [TagStatistic] = []
    var showingNewTagEditor = false
    var editingTag: TagModel?
    var tagToDelete: TagModel?
    var isLoadingStatistics = false
    var errorMessage: String?
    
    // MARK: - Initialization
    
    init(walletManager: WalletManager) {
        self.walletManager = walletManager
    }
    
    // MARK: - Computed Properties
    
    /// Whether the wallet has any tags
    var hasTags: Bool {
        !walletManager.tags.isEmpty
    }
    
    /// All tags from the wallet manager
    var tags: [TagModel] {
        walletManager.tags
    }
    
    /// The largest positive net amount across all tags (received - sent)
    var largestPositiveAmount: Int {
        tagStatistics.map(\.totalAmount).filter { $0 > 0 }.max() ?? 0
    }
    
    /// The largest negative net amount across all tags (received - sent)
    var largestNegativeAmount: Int {
        tagStatistics.map(\.totalAmount).filter { $0 < 0 }.min() ?? 0
    }
    
    /// Tags paired with their statistics, sorted by net amount (highest to lowest)
    /// Tags with 0 transactions are placed at the bottom
    var sortedTagsWithStatistics: [(tag: TagModel, statistic: TagStatistic)] {
        walletManager.tags
            .compactMap { tag in
                // Find statistic or create a zero-stat placeholder
                let statistic = tagStatistics.first(where: { $0.tagId == tag.id }) ?? 
                    TagStatistic(
                        tagId: tag.id,
                        tagName: tag.name,
                        transactionCount: 0,
                        totalAmount: 0,
                        sentAmount: 0,
                        receivedAmount: 0,
                        offchainFees: 0,
                        onchainFees: 0,
                        totalFees: 0
                    )
                return (tag, statistic)
            }
            .sorted { item1, item2 in
                // System tags go to the end
                if item1.tag.isSystemTag != item2.tag.isSystemTag {
                    return !item1.tag.isSystemTag
                }
                
                // Tags with 0 transactions go to the bottom
                let hasTransactions1 = item1.statistic.transactionCount > 0
                let hasTransactions2 = item2.statistic.transactionCount > 0
                
                if hasTransactions1 != hasTransactions2 {
                    // One has transactions, the other doesn't - prioritize the one with transactions
                    return hasTransactions1
                }
                
                // Both have transactions (or both don't) - sort by net amount
                return item1.statistic.totalAmount > item2.statistic.totalAmount
            }
    }
    
    // MARK: - Actions
    
    func loadTagStatistics() async {
        isLoadingStatistics = true
        errorMessage = nil
        
        do {
            tagStatistics = try await walletManager.getTagStatistics()
            print("📊 Loaded \(tagStatistics.count) tag statistics")
        } catch {
            print("❌ Failed to load tag statistics: \(error)")
            errorMessage = "Failed to load statistics"
            // On error, ensure we still show tags with zero statistics
            tagStatistics = []
        }
        
        isLoadingStatistics = false
    }
    
    func createNewTag(_ tag: TagModel) async {
        do {
            let createdTag = try await walletManager.createTag(tag)
            print("✅ Successfully created tag: \(createdTag.name)")
            // Refresh statistics after creating tag
            await loadTagStatistics()
        } catch {
            print("❌ Failed to create tag: \(error)")
            errorMessage = "Failed to create tag"
        }
    }
    
    func updateTag(_ tag: TagModel) async {
        do {
            try await walletManager.updateTag(tag)
            print("✅ Successfully updated tag: \(tag.name)")
            // Refresh statistics after updating tag
            await loadTagStatistics()
        } catch {
            print("❌ Failed to update tag: \(error)")
            errorMessage = "Failed to update tag"
        }
    }
    
    func deleteTag(_ tag: TagModel) async {
        do {
            try await walletManager.deleteTag(tag.id)
            print("✅ Successfully deleted tag: \(tag.name)")
            // Refresh statistics after deleting tag
            await loadTagStatistics()
        } catch {
            print("❌ Failed to delete tag: \(error)")
            errorMessage = "Failed to delete tag"
        }
    }
    
    func createDefaultTags() async {
        await walletManager.createDefaultTagsIfNeeded()
        await loadTagStatistics()
    }
    
    func getTagUsageCount(for tag: TagModel) -> Int {
        if let statistic = tagStatistics.first(where: { $0.tagId == tag.id }) {
            return statistic.transactionCount
        }
        return 0
    }
    
    // MARK: - Sheet Management
    
    func showNewTagEditor() {
        showingNewTagEditor = true
    }
    
    func hideNewTagEditor() {
        showingNewTagEditor = false
    }
    
    func showEditTagEditor(for tag: TagModel) {
        print("🔧 TagsViewModel: Showing edit editor for tag: \(tag.name) (ID: \(tag.id))")
        editingTag = tag
    }
    
    func hideEditTagEditor() {
        print("🔧 TagsViewModel: Hiding edit editor")
        editingTag = nil
    }
    
    func showDeleteConfirmation(for tag: TagModel) {
        tagToDelete = tag
    }
    
    func hideDeleteConfirmation() {
        tagToDelete = nil
    }
}
