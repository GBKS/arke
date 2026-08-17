//
//  ContentView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import SwiftData
import ArkeUI

struct ActivityView: View {
    @Environment(WalletManager.self) private var manager
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedTransaction: TransactionModel?
    let filterTag: PersistentTag?
    let filterContact: PersistentContact?
    let onClearFilter: (() -> Void)?
    
    init(selectedTransaction: Binding<TransactionModel?>, filterTag: PersistentTag? = nil, filterContact: PersistentContact? = nil, onClearFilter: (() -> Void)? = nil) {
        self._selectedTransaction = selectedTransaction
        self.filterTag = filterTag
        self.filterContact = filterContact
        self.onClearFilter = onClearFilter
    }
    
    // Computed property to check if any filter is active
    private var hasActiveFilter: Bool {
        filterTag != nil || filterContact != nil
    }
    
    // Computed property for filter display text
    private var filterDisplayText: String? {
        if let tag = filterTag {
            return tag.displayName
        } else if let contact = filterContact {
            return contact.displayName
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter chip (if active)
            if hasActiveFilter, let filterText = filterDisplayText {
                HStack {
                    HStack(spacing: 8) {
                        // Filter icon/indicator
                        if filterTag != nil {
                            // Could add a tag icon here if desired
                        } else if let contact = filterContact {
                            // Show contact avatar
                            ContactAvatarView(avatarData: contact.avatarData, size: 16)
                        }
                        
                        Text(filterText)
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        // Clear button
                        Button {
                            clearFilter()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .help(String(localized: "help_clear_filter", defaultValue: "Clear filter"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(.separator, lineWidth: 0.5)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            
            ScrollView {
                VStack(spacing: 0) {
                    // Transaction List
                    if let transactionService = manager.transactionServiceInstance {
                        TransactionList(
                            selectedTransaction: $selectedTransaction,
                            filterTag: filterTag,
                            filterContact: filterContact
                        )
                            .environment(transactionService)
                            .onAppear {
                                // Double-check ModelContext is set (defensive programming)
                                transactionService.setModelContext(modelContext)
                            }
                        
                        // Error Display - Transaction-specific errors
                        if let error = transactionService.error {
                            ErrorBox(errorMessage: error)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                        }
                    } else {
                        ContentUnavailableView {
                            VStack(spacing: 15) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(String(localized: "progress_loading_transactions", defaultValue: "Loading transactions..."))
                                    .font(.system(size: 19, design: .serif))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "nav_title_activity", defaultValue: "Activity"))
        .refreshable {
            await manager.refresh()
        }
        .task {
            // CRITICAL: Set ModelContext BEFORE calling initialize
            manager.setModelContext(modelContext)
            await manager.initialize()
        }
    }
    
    // Helper function to clear the active filter
    private func clearFilter() {
        onClearFilter?()
    }
}
