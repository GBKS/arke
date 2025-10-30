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
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                HStack {
                    Text("Tags")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button("New Tag") {
                        showingNewTagEditor = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if walletManager.hasTags {
                    HStack {
                        Text("\(walletManager.activeTagCount) active tags")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
            }
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                if walletManager.hasTags {
                    tagsSection
                        .padding()
                } else {
                    emptyStateView
                        .padding()
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
            // Create default tags if needed
            if walletManager.hasTags == false {
                await walletManager.createDefaultTagsIfNeeded()
            }
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
                tagCard(for: tag)
            }
        }
    }
    
    @ViewBuilder
    private func tagCard(for tag: TagModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TagChip(tag: tag)
                
                Spacer()
                
                Menu {
                    Button("Edit") {
                        editingTag = tag
                        showingEditTagEditor = true
                    }
                    
                    Divider()
                    
                    Button("Delete", role: .destructive) {
                        Task {
                            await deleteTag(tag)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20, height: 20)
            }
            
            // Tag statistics
            VStack(alignment: .leading, spacing: 4) {
                Text("Usage Statistics")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text("\(getTagUsageCount(for: tag)) transactions")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tag.color.opacity(0.3), lineWidth: 1)
        )
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
        } catch {
            print("❌ Failed to create tag: \(error)")
        }
    }
    
    private func updateTag(_ tag: TagModel) async {
        do {
            try await walletManager.updateTag(tag)
            print("✅ Successfully updated tag: \(tag.name)")
        } catch {
            print("❌ Failed to update tag: \(error)")
        }
    }
    
    private func deleteTag(_ tag: TagModel) async {
        do {
            try await walletManager.deleteTag(tag.id)
            print("✅ Successfully deleted tag: \(tag.name)")
        } catch {
            print("❌ Failed to delete tag: \(error)")
        }
    }
    
    private func getTagUsageCount(for tag: TagModel) -> Int {
        // This would normally come from the TagService
        // For now, return a placeholder
        return Int.random(in: 0...15)
    }
}

// MARK: - Preview

#Preview("macOS Tag Management") {
    TagsView()
        .environment(WalletManager(useMock: true))
        .frame(width: 800, height: 600)
}
