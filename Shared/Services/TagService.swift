//
//  TagService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/30/25.
//

import Foundation
import SwiftUI
import SwiftData
import Combine
import ArkeUI

/// Service responsible for managing all tag-related operations
@MainActor
@Observable
class TagService {
    
    // MARK: - Published Properties
    
    /// All available tags
    var tags: [TagModel] = []
    
    /// Error message for tag operations
    var error: String?
    
    /// Loading state for tag operations
    var isLoading: Bool = false
    
    // MARK: - Dependencies
    
    private let taskManager: TaskDeduplicationManager
    private var modelContext: ModelContext?
    
    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties for UI
    
    /// True if any tags exist
    var hasTags: Bool {
        !tags.isEmpty
    }
    
    /// True if default tags haven't been created yet
    var needsDefaultTags: Bool {
        tags.isEmpty
    }
    
    // MARK: - Initialization
    
    init(taskManager: TaskDeduplicationManager) {
        self.taskManager = taskManager
        // Don't start observing CloudKit changes yet - wait until setModelContext() is called
        // This ensures we only observe when a wallet exists
    }
    
    // MARK: - CloudKit Change Observation
    
    /// Start observing CloudKit remote change notifications
    /// Called automatically when setModelContext() is invoked (only when wallet exists)
    private func startObservingCloudKitChanges() {
        // Prevent duplicate subscriptions
        guard cancellables.isEmpty else {
            print("⏭️ [TagService] Already observing CloudKit changes")
            return
        }
        
        NotificationCenter.default
            .publisher(for: .cloudKitDataDidChange)
            .debounce(for: .seconds(1), scheduler: RunLoop.main) // Debounce rapid notifications
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.handleCloudKitChange()
                }
            }
            .store(in: &cancellables)
        
        print("📋 [TagService] Started observing CloudKit changes (debounced)")
    }
    
    /// Handle CloudKit remote changes by reloading tags
    private func handleCloudKitChange() async {
        print("📋 [TagService] CloudKit change detected - reloading tags")
        await loadTags()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - SwiftData Integration
    
    /// Set the model context for persistence operations
    /// This is only called when a wallet exists (ServiceContainer.isActive == true)
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        
        // Start observing CloudKit changes now that we have a context (and wallet)
        startObservingCloudKitChanges()
        
        // Load existing tags on startup
        Task {
            await loadTags()
        }
    }
    
    // MARK: - Tag CRUD Operations
    
    /// Load all tags from SwiftData
    func loadTags() async {
        guard let modelContext = modelContext else {
            print("⚠️ No model context available for loading tags")
            return
        }
        
        do {
            let descriptor = FetchDescriptor<PersistentTag>(sortBy: [
                SortDescriptor(\.createdDate, order: .forward)
            ])
            let persistentTags = try modelContext.fetch(descriptor)
            
            // Convert to UI models
            self.tags = persistentTags.map { TagModel(from: $0) }
            
            print("📋 Loaded \(tags.count) tags from SwiftData")
            
        } catch {
            print("❌ Failed to load tags: \(error)")
            self.error = "Failed to load tags: \(error)"
        }
    }
    
    /// Create a new tag
    func createTag(_ tagModel: TagModel) async throws -> TagModel {
        return try await taskManager.execute(key: "createTag_\(tagModel.name)") {
            try await self.performCreateTag(tagModel)
        }
    }
    
    private func performCreateTag(_ tagModel: TagModel) async throws -> TagModel {
        guard let modelContext = modelContext else {
            throw TagServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Check if tag with same name already exists
            let existingDescriptor = FetchDescriptor<PersistentTag>(
                predicate: #Predicate<PersistentTag> { $0.name == tagModel.name }
            )
            let existingTags = try modelContext.fetch(existingDescriptor)
            
            if !existingTags.isEmpty {
                throw TagServiceError.tagAlreadyExists(tagModel.name)
            }
            
            // Create persistent tag
            let persistentTag = tagModel.toPersistentTag()
            modelContext.insert(persistentTag)
            
            // Save changes
            try modelContext.save()
            
            // Add to local array
            let newTag = TagModel(from: persistentTag)
            self.tags.append(newTag)
            
            print("✅ Created tag: \(newTag.name)")
            return newTag
            
        } catch {
            print("❌ Failed to create tag: \(error)")
            self.error = "Failed to create tag: \(error)"
            throw error
        }
    }
    
    /// Update an existing tag
    func updateTag(_ updatedTag: TagModel) async throws {
        return try await taskManager.execute(key: "updateTag_\(updatedTag.id)") {
            try await self.performUpdateTag(updatedTag)
        }
    }
    
    private func performUpdateTag(_ updatedTag: TagModel) async throws {
        guard let modelContext = modelContext else {
            throw TagServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Find existing persistent tag
            let descriptor = FetchDescriptor<PersistentTag>(
                predicate: #Predicate<PersistentTag> { $0.id == updatedTag.id }
            )
            let existingTags = try modelContext.fetch(descriptor)
            
            guard let persistentTag = existingTags.first else {
                throw TagServiceError.tagNotFound(updatedTag.id)
            }
            
            // Update properties
            persistentTag.name = updatedTag.name
            persistentTag.colorHex = updatedTag.colorHex
            persistentTag.emoji = updatedTag.emoji
            
            // Save changes
            try modelContext.save()
            
            // Update local array
            if let index = tags.firstIndex(where: { $0.id == updatedTag.id }) {
                tags[index] = updatedTag
            }
            
            print("✅ Updated tag: \(updatedTag.name)")
            
        } catch {
            print("❌ Failed to update tag: \(error)")
            self.error = "Failed to update tag: \(error)"
            throw error
        }
    }
    
    /// Delete a tag permanently (removes tag and all its assignments via cascade)
    func deleteTag(_ tagId: UUID) async throws {
        return try await taskManager.execute(key: "deleteTag_\(tagId)") {
            try await self.performDeleteTag(tagId)
        }
    }
    
    private func performDeleteTag(_ tagId: UUID) async throws {
        guard let modelContext = modelContext else {
            throw TagServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Find the tag
            let descriptor = FetchDescriptor<PersistentTag>(
                predicate: #Predicate<PersistentTag> { $0.id == tagId }
            )
            let existingTags = try modelContext.fetch(descriptor)
            
            guard let persistentTag = existingTags.first else {
                throw TagServiceError.tagNotFound(tagId)
            }
            
            let tagName = persistentTag.name
            
            // Delete the tag (cascade will delete all assignments)
            modelContext.delete(persistentTag)
            
            // Save changes
            try modelContext.save()
            
            // Remove from local array
            tags.removeAll { $0.id == tagId }
            
            print("✅ Permanently deleted tag: \(tagName)")
            
        } catch {
            print("❌ Failed to delete tag: \(error)")
            self.error = "Failed to delete tag: \(error)"
            throw error
        }
    }
    
    // MARK: - Tag Assignment Operations
    
    /// Assign a tag to a transaction
    func assignTag(_ tagId: UUID, to transactionTxid: String) async throws {
        return try await taskManager.execute(key: "assignTag_\(tagId)_\(transactionTxid)") {
            try await self.performAssignTag(tagId, to: transactionTxid)
        }
    }
    
    private func performAssignTag(_ tagId: UUID, to transactionTxid: String) async throws {
        guard let modelContext = modelContext else {
            throw TagServiceError.noModelContext
        }
        
        do {
            // Find the tag
            let tagDescriptor = FetchDescriptor<PersistentTag>(
                predicate: #Predicate<PersistentTag> { $0.id == tagId }
            )
            let tags = try modelContext.fetch(tagDescriptor)
            guard let tag = tags.first else {
                throw TagServiceError.tagNotFound(tagId)
            }
            
            // Find the transaction
            let transactionDescriptor = FetchDescriptor<PersistentTransaction>(
                predicate: #Predicate<PersistentTransaction> { $0.txid == transactionTxid }
            )
            let transactions = try modelContext.fetch(transactionDescriptor)
            guard let transaction = transactions.first else {
                throw TagServiceError.transactionNotFound(transactionTxid)
            }
            
            // Check if assignment already exists
            let assignmentDescriptor = FetchDescriptor<TransactionTagAssignment>(
                predicate: #Predicate<TransactionTagAssignment> { 
                    assignment in
                    assignment.tag?.id == tagId && assignment.transaction?.txid == transactionTxid
                }
            )
            let existingAssignments = try modelContext.fetch(assignmentDescriptor)
            
            if !existingAssignments.isEmpty {
                throw TagServiceError.tagAlreadyAssigned
            }
            
            // Create new assignment
            let assignment = TransactionTagAssignment(tag: tag, transaction: transaction)
            modelContext.insert(assignment)
            
            // Save changes
            try modelContext.save()
            
            print("✅ Assigned tag '\(tag.name)' to transaction \(transactionTxid)")
            
        } catch {
            print("❌ Failed to assign tag: \(error)")
            self.error = "Failed to assign tag: \(error)"
            throw error
        }
    }
    
    /// Remove a tag assignment from a transaction
    func unassignTag(_ tagId: UUID, from transactionTxid: String) async throws {
        return try await taskManager.execute(key: "unassignTag_\(tagId)_\(transactionTxid)") {
            try await self.performUnassignTag(tagId, from: transactionTxid)
        }
    }
    
    private func performUnassignTag(_ tagId: UUID, from transactionTxid: String) async throws {
        guard let modelContext = modelContext else {
            throw TagServiceError.noModelContext
        }
        
        do {
            // Find the assignment
            let assignmentDescriptor = FetchDescriptor<TransactionTagAssignment>(
                predicate: #Predicate<TransactionTagAssignment> { 
                    assignment in
                    assignment.tag?.id == tagId && assignment.transaction?.txid == transactionTxid
                }
            )
            let assignments = try modelContext.fetch(assignmentDescriptor)
            
            guard let assignment = assignments.first else {
                throw TagServiceError.assignmentNotFound
            }
            
            let tagName = assignment.tag?.name ?? "Unknown"
            
            // Delete the assignment
            modelContext.delete(assignment)
            
            // Save changes
            try modelContext.save()
            
            print("✅ Unassigned tag '\(tagName)' from transaction \(transactionTxid)")
            
        } catch {
            print("❌ Failed to unassign tag: \(error)")
            self.error = "Failed to unassign tag: \(error)"
            throw error
        }
    }
    
    // MARK: - Default Tags Operations
    
    /// Create default tags if none exist
    func createDefaultTagsIfNeeded() async {
        guard needsDefaultTags else { return }
        
        await taskManager.execute(key: "createDefaultTags") {
            await self.performCreateDefaultTags()
        }
    }
    
    private func performCreateDefaultTags() async {
        guard let modelContext = modelContext else {
            print("❌ Cannot create default tags: no model context")
            return
        }
        
        let defaultTagModels = TagModel.createDefaultTags()
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Batch create all default tags in a single transaction
            var createdTags: [PersistentTag] = []
            
            for tagModel in defaultTagModels {
                // Check if tag with same name already exists
                let existingDescriptor = FetchDescriptor<PersistentTag>(
                    predicate: #Predicate<PersistentTag> { tag in tag.name == tagModel.name }
                )
                let existingTags = try modelContext.fetch(existingDescriptor)
                
                if existingTags.isEmpty {
                    // Create persistent tag (but don't save yet)
                    let persistentTag = tagModel.toPersistentTag()
                    modelContext.insert(persistentTag)
                    createdTags.append(persistentTag)
                    print("✅ Created tag: \(tagModel.name)")
                } else {
                    print("⏭️ Tag '\(tagModel.name)' already exists, skipping")
                }
            }
            
            // Save all tags in a single transaction
            // This triggers only ONE CloudKit sync instead of one per tag
            if !createdTags.isEmpty {
                try modelContext.save()
                print("✅ Created \(createdTags.count) default tags in batch")
                
                // Reload tags to update the in-memory cache
                await loadTags()
            } else {
                print("ℹ️ All default tags already exist")
            }
            
        } catch {
            print("❌ Failed to create default tags: \(error)")
            self.error = "Failed to create default tags: \(error)"
        }
    }
    
    // MARK: - Query Operations
    
    /// Get all transactions that have a specific tag
    func getTransactionsWithTag(_ tagId: UUID) async throws -> [TransactionModel] {
        guard let modelContext = modelContext else {
            throw TagServiceError.noModelContext
        }
        
        do {
            // Find tag assignments for this tag
            let assignmentDescriptor = FetchDescriptor<TransactionTagAssignment>(
                predicate: #Predicate<TransactionTagAssignment> { $0.tag?.id == tagId }
            )
            let assignments = try modelContext.fetch(assignmentDescriptor)
            
            // Extract persistent transactions and convert to UI models
            let persistentTransactions = assignments.compactMap { $0.transaction }
            return persistentTransactions.map { TransactionModel(from: $0) }
            
        } catch {
            print("❌ Failed to get transactions for tag: \(error)")
            throw error
        }
    }
    
    /// Get all tags assigned to a specific transaction
    func getTagsForTransaction(_ transactionId: String) async throws -> [TagModel] {
        guard let modelContext = modelContext else {
            throw TagServiceError.noModelContext
        }
        
        do {
            // Find tag assignments for this transaction
            let assignmentDescriptor = FetchDescriptor<TransactionTagAssignment>(
                predicate: #Predicate<TransactionTagAssignment> { $0.transaction?.txid == transactionId }
            )
            let assignments = try modelContext.fetch(assignmentDescriptor)
            
            // Extract tags and convert to UI models
            let persistentTags = assignments.compactMap { $0.tag }
            return persistentTags.map { TagModel(from: $0) }
            
        } catch {
            print("❌ Failed to get tags for transaction: \(error)")
            throw error
        }
    }
    
    /// Get tag usage statistics
    func getTagStatistics() async throws -> [TagStatistic] {
        guard let modelContext = modelContext else {
            throw TagServiceError.noModelContext
        }
        
        do {
            let tagDescriptor = FetchDescriptor<PersistentTag>()
            let persistentTags = try modelContext.fetch(tagDescriptor)
            
            // Resolve each tag's transactions once — the aggregates each run
            // their own fetch now that they no longer walk cached relationships
            let statistics = persistentTags.map { tag in
                let transactions = tag.associatedTransactions
                let sent = transactions.filter { $0.type == "sent" }.reduce(0) { $0 + $1.amount }
                let received = transactions.filter { $0.type == "received" }.reduce(0) { $0 + $1.amount }
                let offchainFees = transactions.reduce(0) { $0 + ($1.fees ?? 0) }
                let onchainFees = transactions.reduce(0) { $0 + ($1.onchainFeeSat ?? 0) }

                return TagStatistic(
                    tagId: tag.id,
                    tagName: tag.displayName,
                    transactionCount: transactions.count,
                    totalAmount: received - sent,
                    sentAmount: sent,
                    receivedAmount: received,
                    offchainFees: offchainFees,
                    onchainFees: onchainFees,
                    totalFees: offchainFees + onchainFees
                )
            }
            
            return statistics.sorted { $0.transactionCount > $1.transactionCount }
            
        } catch {
            print("❌ Failed to get tag statistics: \(error)")
            throw error
        }
    }
    
    // MARK: - Bulk Operations
    
    /// Delete all tags and their assignments from SwiftData
    /// This is used during wallet deletion when user chooses to delete all cloud data
    func deleteAllTags() async throws {
        return try await taskManager.execute(key: "deleteAllTags") {
            try await self.performDeleteAllTags()
        }
    }
    
    private func performDeleteAllTags() async throws {
        guard let modelContext = modelContext else {
            throw TagServiceError.noModelContext
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Fetch all tags
            let descriptor = FetchDescriptor<PersistentTag>()
            let allTags = try modelContext.fetch(descriptor)
            
            guard !allTags.isEmpty else {
                print("ℹ️ No tags to delete")
                return
            }
            
            let tagCount = allTags.count
            let assignmentCount = allTags.reduce(0) { $0 + ($1.tagAssignments?.count ?? 0) }
            
            // Delete all tags (cascade will handle assignments)
            for tag in allTags {
                modelContext.delete(tag)
            }
            
            // Save changes
            try modelContext.save()
            
            // Clear local array
            tags.removeAll()
            
            print("🗑️ [TagService] Deleted \(tagCount) tags and \(assignmentCount) tag assignments from SwiftData")
            
        } catch {
            print("❌ [TagService] Failed to delete all tags: \(error)")
            self.error = "Failed to delete all tags: \(error)"
            throw error
        }
    }
    
    // MARK: - State Management
    
    /// Clear error state
    func clearError() {
        error = nil
    }
    
    /// Refresh tags from storage
    func refreshTags() async {
        await loadTags()
    }
}

// MARK: - Error Types

enum TagServiceError: LocalizedError {
    case noModelContext
    case tagNotFound(UUID)
    case transactionNotFound(String)
    case tagAlreadyExists(String)
    case tagAlreadyAssigned
    case assignmentNotFound
    
    var errorDescription: String? {
        switch self {
        case .noModelContext:
            return "Database context not available"
        case .tagNotFound(let id):
            return "Tag with ID \(id) not found"
        case .transactionNotFound(let txid):
            return "Transaction with ID \(txid) not found"
        case .tagAlreadyExists(let name):
            return "Tag '\(name)' already exists"
        case .tagAlreadyAssigned:
            return "Tag is already assigned to this transaction"
        case .assignmentNotFound:
            return "Tag assignment not found"
        }
    }
}

// MARK: - Supporting Models

struct TagStatistic {
    let tagId: UUID
    let tagName: String
    let transactionCount: Int
    let totalAmount: Int        // Net total (received - sent)
    let sentAmount: Int         // Sum of sent transactions
    let receivedAmount: Int     // Sum of received transactions
    let offchainFees: Int       // Sum of offchain fees
    let onchainFees: Int        // Sum of onchain fees
    let totalFees: Int          // Sum of all fees (offchain + onchain)
    
    // Computed properties
    
    /// Net amount including fees (totalAmount - totalFees)
    /// This represents the actual impact on the wallet after accounting for fees
    var totalAmountIncludingFees: Int {
        totalAmount - totalFees
    }
    
    // Computed properties for display
    var formattedTotalAmount: String {
        BitcoinFormatter.shared.formatAccountingAmount(totalAmount, transactionType: totalAmount >= 0 ? .received : .sent)
    }
    
    var formattedTotalAmountIncludingFees: String {
        BitcoinFormatter.shared.formatAccountingAmount(totalAmountIncludingFees, transactionType: totalAmountIncludingFees >= 0 ? .received : .sent)
    }
    
    var formattedSentAmount: String {
        BitcoinFormatter.shared.formatAccountingAmount(sentAmount, transactionType: .sent)
    }
    
    var formattedReceivedAmount: String {
        BitcoinFormatter.shared.formatAccountingAmount(receivedAmount, transactionType: .received)
    }
    
    var formattedOffchainFees: String {
        BitcoinFormatter.shared.formatAccountingAmount(offchainFees, transactionType: .sent)
    }
    
    var formattedOnchainFees: String {
        BitcoinFormatter.shared.formatAccountingAmount(onchainFees, transactionType: .sent)
    }
    
    var formattedTotalFees: String {
        BitcoinFormatter.shared.formatAccountingAmount(totalFees, transactionType: .sent)
    }
}
