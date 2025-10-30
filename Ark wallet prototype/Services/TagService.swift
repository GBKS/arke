//
//  TagService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/30/25.
//

import Foundation
import SwiftUI
import SwiftData

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
    
    // MARK: - Computed Properties for UI
    
    /// Active tags only
    var activeTags: [TagModel] {
        tags.filter { $0.isActive }
    }
    
    /// Count of active tags
    var activeTagCount: Int {
        activeTags.count
    }
    
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
    }
    
    // MARK: - SwiftData Integration
    
    /// Set the model context for persistence operations
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        
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
                predicate: #Predicate<PersistentTag> { $0.name == tagModel.name && $0.isActive }
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
            persistentTag.isActive = updatedTag.isActive
            
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
    
    /// Delete a tag (soft delete by setting isActive = false)
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
            
            // Soft delete (set inactive)
            persistentTag.isActive = false
            
            // Save changes
            try modelContext.save()
            
            // Update local array
            if let index = tags.firstIndex(where: { $0.id == tagId }) {
                tags[index] = TagModel(from: persistentTag)
            }
            
            print("✅ Deleted (deactivated) tag: \(persistentTag.name)")
            
        } catch {
            print("❌ Failed to delete tag: \(error)")
            self.error = "Failed to delete tag: \(error)"
            throw error
        }
    }
    
    /// Permanently delete a tag and all its assignments
    func permanentlyDeleteTag(_ tagId: UUID) async throws {
        return try await taskManager.execute(key: "hardDeleteTag_\(tagId)") {
            try await self.performPermanentDeleteTag(tagId)
        }
    }
    
    private func performPermanentDeleteTag(_ tagId: UUID) async throws {
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
            
            // Delete the tag (cascade will delete assignments)
            modelContext.delete(persistentTag)
            
            // Save changes
            try modelContext.save()
            
            // Remove from local array
            tags.removeAll { $0.id == tagId }
            
            print("✅ Permanently deleted tag: \(tagName)")
            
        } catch {
            print("❌ Failed to permanently delete tag: \(error)")
            self.error = "Failed to permanently delete tag: \(error)"
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
            let transactionDescriptor = FetchDescriptor<TransactionModel>(
                predicate: #Predicate<TransactionModel> { $0.txid == transactionTxid }
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
        let defaultTagModels = TagModel.createDefaultTags()
        
        for tagModel in defaultTagModels {
            do {
                _ = try await performCreateTag(tagModel)
            } catch {
                print("⚠️ Failed to create default tag '\(tagModel.name)': \(error)")
            }
        }
        
        print("✅ Created default tags")
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
            
            // Extract transactions
            let transactions = assignments.compactMap { $0.transaction }
            
            return transactions
            
        } catch {
            print("❌ Failed to get transactions for tag: \(error)")
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
            
            let statistics = persistentTags.map { tag in
                TagStatistic(
                    tagId: tag.id,
                    tagName: tag.displayName,
                    transactionCount: tag.transactionCount,
                    isActive: tag.isActive
                )
            }
            
            return statistics.sorted { $0.transactionCount > $1.transactionCount }
            
        } catch {
            print("❌ Failed to get tag statistics: \(error)")
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
    let isActive: Bool
}