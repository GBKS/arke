//
//  TagEditorMacOSExample.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/30/25.
//

import SwiftUI

// MARK: - macOS Tag Management Example

struct TagsView: View {
    @Environment(WalletManager.self) private var walletManager
    
    @State private var showingNewTagEditor = false
    @State private var editingTag: TagModel?
    @State private var showingEditTagEditor = false
    @State private var tagStatistics: [TagStatistic] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Content
                if walletManager.hasTags {
                    TagsGraph()
                    tagsSection
                } else {
                    emptyStateView
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 30)
            .navigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Tag") {
                        showingNewTagEditor = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        // Sheet presentation for new tag
        .sheet(isPresented: $showingNewTagEditor) {
            TagEditor(
                onSave: { tag in
                    Task {
                        await createNewTag(tag)
                    }
                    showingNewTagEditor = false
                },
                onCancel: {
                    showingNewTagEditor = false
                }
            )
            .environment(walletManager)
            .environment(walletManager.tagServiceForEnvironment)
            .frame(width: 500, height: 600)
        }
        // Sheet presentation for editing tag
        .sheet(isPresented: $showingEditTagEditor) {
            TagEditor(
                editingTag: editingTag,
                onSave: { tag in
                    Task {
                        await updateTag(tag)
                    }
                    showingEditTagEditor = false
                },
                onCancel: {
                    showingEditTagEditor = false
                }
            )
            .environment(walletManager)
            .environment(walletManager.tagServiceForEnvironment)
            .frame(width: 500, height: 600)
        }
        .task {
            // Create default tags if needed and load statistics
            if walletManager.hasTags == false {
                await walletManager.createDefaultTagsIfNeeded()
            }
            await loadTagStatistics()
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var tagsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 16) {
            ForEach(walletManager.activeTags) { tag in
                if let statistic = tagStatistics.first(where: { $0.tagId == tag.id }) {
                    TagCard(
                        tag: tag,
                        tagStatistic: statistic,
                        onEdit: {
                            editingTag = tag
                            showingEditTagEditor = true
                        },
                        onDelete: {
                            Task {
                                await deleteTag(tag)
                            }
                        }
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tag.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
                .symbolRenderingMode(.hierarchical)
            
            VStack(spacing: 8) {
                Text("No Tags Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Create tags to organize and categorize your transactions")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Button("Create Your First Tag") {
                showingNewTagEditor = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: 400)
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func createNewTag(_ tag: TagModel) async {
        do {
            let createdTag = try await walletManager.createTag(tag)
            print("✅ Successfully created tag: \(createdTag.name)")
            // Refresh statistics after creating tag
            await loadTagStatistics()
        } catch {
            print("❌ Failed to create tag: \(error)")
        }
    }
    
    private func updateTag(_ tag: TagModel) async {
        do {
            try await walletManager.updateTag(tag)
            print("✅ Successfully updated tag: \(tag.name)")
            // Refresh statistics after updating tag
            await loadTagStatistics()
        } catch {
            print("❌ Failed to update tag: \(error)")
        }
    }
    
    private func deleteTag(_ tag: TagModel) async {
        do {
            try await walletManager.deleteTag(tag.id)
            print("✅ Successfully deleted tag: \(tag.name)")
            // Refresh statistics after deleting tag
            await loadTagStatistics()
        } catch {
            print("❌ Failed to delete tag: \(error)")
        }
    }
    
    private func getTagUsageCount(for tag: TagModel) -> Int {
        // Find the statistic for this tag
        if let statistic = tagStatistics.first(where: { $0.tagId == tag.id }) {
            return statistic.transactionCount
        }
        return 0
    }
    
    private func loadTagStatistics() async {
        do {
            tagStatistics = try await walletManager.getTagStatistics()
        } catch {
            print("❌ Failed to load tag statistics: \(error)")
        }
    }
}

// MARK: - Preview

#Preview("macOS Tag Management") {
    TagsView()
        .environment(WalletManager(useMock: true))
        .frame(width: 800, height: 600)
}
