//
//  BoardingModalView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI

struct BoardingModalView: View {
    let manager: WalletManager
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showSuccessState: Bool = false
    
    // Add initializer to optionally set initial success state
    init(manager: WalletManager, showSuccessState: Bool = false) {
        self.manager = manager
        self.showSuccessState = showSuccessState
    }
    
    var body: some View {
        if showSuccessState {
            BoardingModalSuccessView {
                dismiss()
            }
        } else {
            BoardingModalFormView(
                errorMessage: errorMessage,
                isLoading: isLoading,
                onConfirm: { amount in
                    Task {
                        await performBoarding(amount: amount)
                    }
                },
                onCancel: {
                    dismiss()
                }
            )
        }
    }
    
    @MainActor
    private func performBoarding(amount: Int) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await manager.board(amount: amount)
            showSuccessState = true
        } catch {
            errorMessage = "Failed to board sats: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

#Preview {
    BoardingModalView(manager: WalletManager(useMock: true))
}

#Preview("Success") {
    BoardingModalView(manager: WalletManager(useMock: true), showSuccessState: true)
}
