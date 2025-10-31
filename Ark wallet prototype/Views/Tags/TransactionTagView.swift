//
//  TransactionTagView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/30/25.
//

import SwiftUI
import SwiftData

struct TransactionTagView: View {
    let transaction: TransactionModel
    @Environment(WalletManager.self) private var walletManager
    
    @State private var showingTagSelector = false
    @State private var assignedTags: [TagModel] = []
    @State private var isLoading = false
    @State private var error: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {            
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if assignedTags.isEmpty {
                FlowLayout(alignment: .leading, spacing: 8) {
                    // Edit tags button styled like a TagChip
                    Button("Add tags") {
                        showingTagSelector = true
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .fontWeight(.medium)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isLoading)
                }
            } else {
                FlowLayout(alignment: .leading, spacing: 8) {
                    ForEach(assignedTags) { tag in
                        TagChip(tag: tag)
                    }
                    
                    // Edit tags button styled like a TagChip
                    Button("Edit tags") {
                        showingTagSelector = true
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .fontWeight(.medium)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isLoading)
                }
            }
            
            if let error = error {
                ErrorView(errorMessage: error)
            }
        }
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

struct FlowLayout: Layout {
    var alignment: Alignment
    var spacing: CGFloat
    
    init(alignment: Alignment = .leading, spacing: CGFloat = 8) {
        self.alignment = alignment
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            alignment: alignment,
            spacing: spacing
        )
        return result.bounds
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            alignment: alignment,
            spacing: spacing
        )
        for index in subviews.indices {
            subviews[index].place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var bounds = CGSize.zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, alignment: Alignment, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            var maxX: CGFloat = 0
            
            for subview in subviews {
                let subviewSize = subview.sizeThatFits(.unspecified)
                
                if currentX + subviewSize.width > maxWidth && currentX > 0 {
                    // Move to next line
                    currentY += lineHeight + spacing
                    currentX = 0
                    lineHeight = 0
                }
                
                frames.append(CGRect(origin: CGPoint(x: currentX, y: currentY), size: subviewSize))
                
                currentX += subviewSize.width + spacing
                lineHeight = max(lineHeight, subviewSize.height)
                maxX = max(maxX, currentX - spacing)
            }
            
            bounds = CGSize(width: maxX, height: currentY + lineHeight)
        }
    }
}

#Preview {
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
