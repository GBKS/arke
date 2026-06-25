//
//  TagsView_iOS.swift
//  Arké
//
//  Created by Christoph on 11/27/25.
//

import SwiftUI
import SwiftData
import ArkeUI

// MARK: - iOS Tag Management

struct TagsView_iOS: View {
    @Environment(WalletManager.self) private var walletManager
    
    let onNavigateToActivity: (TagModel) -> Void
    
    @State private var viewModel: TagsViewModel?
    
    var body: some View {
        Group {
            if let viewModel {
                contentView(viewModel: viewModel)
            } else {
                ProgressView()
                    .task {
                        viewModel = TagsViewModel(walletManager: walletManager)
                        await viewModel?.loadTagStatistics()
                    }
            }
        }
    }
    
    @ViewBuilder
    private func contentView(viewModel: TagsViewModel) -> some View {
        List {
            if viewModel.hasTags {
                tagsSection(viewModel: viewModel)
            } else {
                emptyStateSection(viewModel: viewModel)
            }
        }
        .navigationTitle("tags_title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showNewTagEditor()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable {
            await viewModel.loadTagStatistics()
        }
        // Sheet presentation for new tag
        .sheet(isPresented: Binding(
            get: { viewModel.showingNewTagEditor },
            set: { if !$0 { viewModel.hideNewTagEditor() } }
        )) {
            NavigationStack {
                TagEditor(
                    onSave: { tag in
                        Task {
                            await viewModel.createNewTag(tag)
                        }
                        viewModel.hideNewTagEditor()
                    },
                    onCancel: {
                        viewModel.hideNewTagEditor()
                    }
                )
                .environment(walletManager)
                .environment(walletManager.tagServiceForEnvironment)
            }
            .presentationDetents([.medium, .large])
        }
        // Sheet presentation for editing tag
        .sheet(item: Binding(
            get: { viewModel.editingTag },
            set: { viewModel.editingTag = $0 }
        )) { tag in
            NavigationStack {
                TagEditor(
                    editingTag: tag,
                    onSave: { updatedTag in
                        Task {
                            await viewModel.updateTag(updatedTag)
                        }
                        viewModel.hideEditTagEditor()
                    },
                    onCancel: {
                        viewModel.hideEditTagEditor()
                    }
                )
                .environment(walletManager)
                .environment(walletManager.tagServiceForEnvironment)
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("button_delete_tag",
            isPresented: Binding(
                get: { viewModel.tagToDelete != nil },
                set: { if !$0 { viewModel.hideDeleteConfirmation() } }
            ),
            presenting: viewModel.tagToDelete
        ) { tag in
            Button(String(localized: "button_delete_item", defaultValue: "Delete \"\(tag.name)\""), role: .destructive) {
                Task {
                    await viewModel.deleteTag(tag)
                    viewModel.hideDeleteConfirmation()
                }
            }
            Button(String(localized: "button_cancel"), role: .cancel) {
                viewModel.hideDeleteConfirmation()
            }
        } message: { tag in
            Text(String(localized: "tags_confirm_delete"))
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private func tagsSection(viewModel: TagsViewModel) -> some View {
        let items = viewModel.sortedTagsWithStatistics
        
        if items.isEmpty {
            ContentUnavailableView {
                Label("status_loading_tags", systemImage: "tag.circle")
            } description: {
                Text(String(localized: "status_please_wait"))
            }
        } else {
            ForEach(items, id: \.tag.id) { item in
                Button {
                    onNavigateToActivity(item.tag)
                } label: {
                    TagRow(
                        tag: item.tag,
                        statistic: item.statistic
                    )
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowSpacing(0)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !item.tag.isSystemTag {
                        Button(role: .destructive) {
                            viewModel.showDeleteConfirmation(for: item.tag)
                        } label: {
                            Label("button_delete", systemImage: "trash")
                        }
                        
                        Button {
                            viewModel.showEditTagEditor(for: item.tag)
                        } label: {
                            Label("button_edit", systemImage: "pencil")
                        }
                        .tint(.Arke.blue)
                    }
                }
                .contextMenu {
                    if !item.tag.isSystemTag {
                        Button {
                            viewModel.showEditTagEditor(for: item.tag)
                        } label: {
                            Label("button_edit", systemImage: "pencil")
                        }
                    }
                    
                    if item.statistic.transactionCount > 0 {
                        Button {
                            onNavigateToActivity(item.tag)
                        } label: {
                            Label("button_view_transactions", systemImage: "list.bullet")
                        }
                    }
                    
                    if !item.tag.isSystemTag {
                        Divider()
                        
                        Button(role: .destructive) {
                            viewModel.showDeleteConfirmation(for: item.tag)
                        } label: {
                            Label("button_delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func emptyStateSection(viewModel: TagsViewModel) -> some View {
        Section {
            ContentUnavailableView {
                Label("tags_empty_title", systemImage: "tag.circle")
            } description: {
                Text("tags_empty_help")
            } actions: {
                Button("tags_create_first") {
                    viewModel.showNewTagEditor()
                }
                .buttonStyle(.borderedProminent)
                
                Button("button_add_default_tags") {
                    Task {
                        await viewModel.createDefaultTags()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .listRowBackground(Color.clear)
    }
}

// MARK: - Tag Row Component

/// iOS-specific row component for displaying tag information
private struct TagRow: View {
    let tag: TagModel
    let statistic: TagStatistic
    
    var body: some View {
        HStack(spacing: 12) {
            // Tag chip
            TagChip(tag: tag.appearance, size: .large)
            
            Spacer()
            
            // Statistics
            VStack(alignment: .trailing, spacing: 4) {
                if statistic.transactionCount > 0 {
                    // For system tags (Balance tag for internal transfers), only show fees
                    if tag.isSystemTag {
                        Text(statistic.formattedTotalFees)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.Arke.red)
                        
                        Text("activity_fees_paid")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(statistic.formattedTotalAmountIncludingFees)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(statistic.totalAmountIncludingFees >= 0 ? .Arke.green : .Arke.red)
                        
                        Text(String(localized: "tags_transaction_count", defaultValue: "^[\(statistic.transactionCount) transaction](inflect: true)"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("activity_no_transactions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
