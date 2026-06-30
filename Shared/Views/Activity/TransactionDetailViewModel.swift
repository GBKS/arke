//
//  TransactionDetailViewModel.swift
//  Arké
//
//  Created by Assistant on 12/8/25.
//

import SwiftUI
import ArkeUI

/// Shared view model for transaction detail management across macOS and iOS
@Observable
@MainActor
final class TransactionDetailViewModel {
    
    // MARK: - Dependencies
    
    private let walletManager: WalletManager
    let transaction: TransactionModel
    
    // MARK: - State
    
    var isLoading = false
    var errorMessage: String?
    var showCopySuccess = false
    
    // MARK: - Initialization
    
    init(transaction: TransactionModel, walletManager: WalletManager) {
        self.transaction = transaction
        self.walletManager = walletManager
    }
    
    // MARK: - Actions
    
    /// Copies text to clipboard and shows success feedback
    func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        
        // Show success feedback
        withAnimation {
            showCopySuccess = true
        }
        
        // Hide success feedback after 2 seconds
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                showCopySuccess = false
            }
        }
    }
    
    /// Refresh transaction details if needed
    func refresh() async {
        isLoading = true
        errorMessage = nil
        
        // Currently transaction details are already in the model
        // If we need to fetch additional data in the future, add it here
        
        isLoading = false
    }
}
