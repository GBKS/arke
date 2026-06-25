//
//  TagSelectorSheet.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/30/25.
//

import SwiftUI
import ArkeUI

struct TagSelectorSheet: View {
    @Binding var selectedTagIds: Set<UUID>
    let onCreateNewTag: (TagModel) async -> Void
    
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingTagEditor = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Content
            ScrollView {
                // Existing Tags Section
                if walletManager.hasTags {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(walletManager.tags) { tag in
                            TagChip_Selectable(
                                tag: tag.appearance,
                                isSelected: Binding(
                                    get: { selectedTagIds.contains(tag.id) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedTagIds.insert(tag.id)
                                        } else {
                                            selectedTagIds.remove(tag.id)
                                        }
                                    }
                                )
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
        }
        .navigationTitle("button_assign_tags")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    showingTagEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("tags_new_title")
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel("button_done")
            }
        }
        .sheet(isPresented: $showingTagEditor) {
            TagEditor(
                onSave: { tag in
                    Task {
                        await onCreateNewTag(tag)
                    }
                    showingTagEditor = false
                },
                onCancel: {
                    showingTagEditor = false
                }
            )
            .environment(walletManager)
            .environment(walletManager.tagServiceForEnvironment)
        }
    }
}
