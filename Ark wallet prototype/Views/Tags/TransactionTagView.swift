//
//  TransactionTagView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/30/25.
//

import SwiftUI

struct TransactionTagView: View {
    let transaction: TransactionModel
    @Environment(WalletManager.self) private var walletManager
    
    @State private var showingTagSelector = false
    @State private var assignedTags: [TagModel] = []
    @State private var isLoading = false
    @State private var error: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tags")
                    .font(.headline)
                
                Spacer()
                
                Button("Manage Tags") {
                    showingTagSelector = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading)
            }
            
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if assignedTags.isEmpty {
                Text("No tags assigned")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(assignedTags) { tag in
                        TagChip_Removable(tag: tag) {
                            Task {
                                await removeTag(tag.id)
                            }
                        }
                    }
                }
            }
            
            if let error = error {
                Text("Error: \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: transaction.txid) {
            await loadAssignedTags()
        }
        .sheet(isPresented: $showingTagSelector) {
            TagSelectorSheet(
                selectedTagIds: Binding(
                    get: { Set(assignedTags.map { $0.id }) },
                    set: { newTagIds in
                        Task {
                            await updateTagAssignments(newTagIds)
                        }
                    }
                ),
                onCreateNewTag: { tag in
                    await createAndAssignTag(tag)
                }
            )
            .environment(walletManager)
            .frame(width: 600, height: 500)
        }
    }
    
    // MARK: - Private Methods
    
    private func loadAssignedTags() async {
        isLoading = true
        error = nil
        
        do {
            let tags = try await walletManager.getTransactionTags(transaction.txid)
            await MainActor.run {
                self.assignedTags = tags
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func removeTag(_ tagId: UUID) async {
        do {
            try await walletManager.unassignTag(tagId, from: transaction.txid)
            await loadAssignedTags() // Refresh the display
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
    
    private func updateTagAssignments(_ newTagIds: Set<UUID>) async {
        let currentTagIds = Set(assignedTags.map { $0.id })
        
        // Determine which tags to add and remove
        let tagsToAdd = newTagIds.subtracting(currentTagIds)
        let tagsToRemove = currentTagIds.subtracting(newTagIds)
        
        do {
            // Remove tags that are no longer selected
            for tagId in tagsToRemove {
                try await walletManager.unassignTag(tagId, from: transaction.txid)
            }
            
            // Add newly selected tags
            for tagId in tagsToAdd {
                try await walletManager.assignTag(tagId, to: transaction.txid)
            }
            
            await loadAssignedTags() // Refresh the display
            
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
    
    private func createAndAssignTag(_ tag: TagModel) async {
        do {
            let createdTag = try await walletManager.createTag(tag)
            try await walletManager.assignTag(createdTag.id, to: transaction.txid)
            await loadAssignedTags() // Refresh the display
            print("✅ Successfully created and assigned tag: \(createdTag.name)")
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
            print("❌ Failed to create and assign tag: \(error)")
        }
    }
}

#Preview("macOS Transaction Tags") {
    TransactionTagView(
        transaction: TransactionModel(
            txid: "sample-123", 
            movementId: nil, 
            recipientIndex: nil, 
            type: .received, 
            amount: 50000, 
            date: Date(), 
            status: .confirmed, 
            address: nil
        )
    )
    .environment(WalletManager(useMock: true))
    .frame(width: 400, height: 200)
}
