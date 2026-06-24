//
//  PendingPaymentMetadata.swift
//  Arke
//
//  Created for Phase 0: Send Metadata Enhancement
//

import Foundation
import SwiftData

/// Stores metadata for outgoing payments before the corresponding transaction arrives from the server.
/// This allows users to assign contacts, tags, and notes during the send process,
/// and the metadata will be matched and applied when the server movement syncs.
@Model
final class PendingPaymentMetadata {
    // MARK: - Matching Identifiers
    
    /// Lightning payment hash - primary matching identifier (Priority 1)
    /// This is the most reliable way to match Lightning payments
    var paymentHash: String?
    
    /// Destination address - used for fallback matching (Priority 2)
    /// For all payment types (Lightning, Ark, Onchain)
    var destinationAddress: String?
    
    /// Payment amount in satoshis - used for fallback matching (Priority 2)
    var amountSats: Int?
    
    /// Payment type for debugging and logging
    /// Values: "lightning", "ark", "onchain"
    var paymentType: String?
    
    /// Timestamp when payment was initiated - used for time-window matching (Priority 2)
    var timestamp: Date = Date()
    
    // MARK: - Metadata
    
    /// User-provided notes for this payment (max 1000 characters)
    var notes: String?
    
    // MARK: - Relationships
    
    /// Tag assignments for this pending payment
    @Relationship(deleteRule: .cascade, inverse: \PendingTagAssignment.pendingMetadata)
    var tagAssignments: [PendingTagAssignment]? = []
    
    /// Associated contact (single contact per payment)
    @Relationship(inverse: \PersistentContact.pendingPaymentMetadata)
    var contact: PersistentContact?
    
    // MARK: - Lifecycle
    
    /// When this pending metadata was created
    var createdAt: Date = Date()
    
    /// Whether this metadata has been matched to a transaction
    var isMatched: Bool = false
    
    /// Transaction ID if matched (for debugging)
    var matchedTxid: String?
    
    /// Whether the metadata has been fully applied to the transaction
    /// This prevents redundant re-applications on every transaction update
    /// Reset to false when user modifies metadata after initial application
    var hasBeenApplied: Bool = false
    
    // MARK: - Initialization
    
    init(
        paymentHash: String?,
        destinationAddress: String?,
        amountSats: Int?,
        paymentType: String?,
        timestamp: Date = Date()
    ) {
        self.paymentHash = paymentHash
        self.destinationAddress = destinationAddress
        self.amountSats = amountSats
        self.paymentType = paymentType
        self.timestamp = timestamp
        self.createdAt = Date()
        self.isMatched = false
    }
    
    // MARK: - Computed Properties
    
    /// Get all tags associated with this pending payment
    var associatedTags: [PersistentTag] {
        (tagAssignments ?? []).compactMap { $0.tag }
    }
    
    /// Check if this pending payment has any tags
    var hasTags: Bool {
        !(tagAssignments ?? []).isEmpty
    }
    
    /// Check if this pending payment has a contact
    var hasContact: Bool {
        contact != nil
    }
    
    /// Check if this pending payment has notes
    var hasNotes: Bool {
        guard let notes = notes else { return false }
        return !notes.isEmpty
    }
    
    /// Check if this pending payment has any metadata
    var hasMetadata: Bool {
        hasNotes || hasTags || hasContact
    }
    
    // MARK: - Helper Methods
    
    /// Mark this metadata as modified, requiring re-application
    /// Call this when the user edits notes, adds/removes tags, or changes contact
    func markAsModified() {
        hasBeenApplied = false
    }
}

/// Join table for many-to-many relationship between pending metadata and tags
@Model
final class PendingTagAssignment {
    /// When this tag was assigned
    var assignedDate: Date = Date()
    
    /// The tag being assigned
    @Relationship var tag: PersistentTag?
    
    /// The pending metadata this assignment belongs to
    @Relationship var pendingMetadata: PendingPaymentMetadata?
    
    init(tag: PersistentTag, pendingMetadata: PendingPaymentMetadata, assignedDate: Date = Date()) {
        self.tag = tag
        self.pendingMetadata = pendingMetadata
        self.assignedDate = assignedDate
    }
    
    /// Computed property for easier identification
    var id: String {
        guard let tagId = tag?.id.uuidString,
              let metadataCreated = pendingMetadata?.createdAt else {
            return UUID().uuidString
        }
        return "\(tagId)_\(metadataCreated.timeIntervalSince1970)"
    }
}
