//
//  BoardingModalView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/17/25.
//

import SwiftUI

struct OffboardingModalView: View {
    let manager: WalletManager
    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingVTXOs: Bool = false
    @State private var isConfirming: Bool = false
    @State private var errorMessage: String?
    @State private var vtxos: [VTXOModel] = []
    @State private var selectedVTXOs: Set<String> = []
    @State private var viewState: ViewState = .form
    
    enum ViewState {
        case form
        case success
    }
    
    // Add initializer to optionally set initial success state
    init(manager: WalletManager, showSuccessState: Bool = false) {
        self.manager = manager
        self._viewState = State(initialValue: showSuccessState ? .success : .form)
    }
    
    var body: some View {
        switch viewState {
        case .success:
            OffboardingModalSuccessView {
                dismiss()
            }
        case .form:
            OffboardingModalFormView(
                vtxos: vtxos,
                selectedVTXOs: $selectedVTXOs,
                errorMessage: errorMessage,
                isLoading: isConfirming,
                onConfirm: {
                    Task {
                        await performBoarding()
                    }
                },
                onCancel: {
                    dismiss()
                }
            )
            .onAppear {
                if vtxos.isEmpty && !isLoadingVTXOs {
                    Task {
                        await loadVTXOs()
                    }
                }
            }
        }
    }
    
    @MainActor
    private func loadVTXOs() async {
        // Prevent multiple simultaneous loads
        guard !isLoadingVTXOs else { return }
        
        isLoadingVTXOs = true
        errorMessage = nil
        
        do {
            let loadedVTXOs = try await manager.getVTXOs()
            vtxos = loadedVTXOs
            print("DEBUG: Loaded \(vtxos.count) VTXOs: \(vtxos)")
        } catch {
            errorMessage = "Failed to load VTXOs: \(error.localizedDescription)"
            vtxos = []
            print("DEBUG: Failed to load VTXOs - vtxos array is now empty")
        }
        
        isLoadingVTXOs = false
    }
    
    @MainActor
    private func performBoarding() async {
        guard !selectedVTXOs.isEmpty else { return }
        
        isConfirming = true
        errorMessage = nil
        
        do {
            // Exit each selected VTXO
            for vtxoId in selectedVTXOs {
                _ = try await manager.exitVTXO(vtxoId: vtxoId)
            }
            
            // Start the exit process
            _ = try await manager.startExit()
            
            // Show success state - don't reset isConfirming when successful
            viewState = .success
        } catch {
            errorMessage = "Failed to transfer coins: \(error.localizedDescription)"
            isConfirming = false  // Only reset isConfirming on error
        }
    }
}



#Preview {
    OffboardingModalView(manager: WalletManager(useMock: true))
}

#Preview("Success") {
    OffboardingModalView(manager: WalletManager(useMock: true), showSuccessState: true)
}


