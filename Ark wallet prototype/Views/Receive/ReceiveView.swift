//
//  ReceiveView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

struct ReceiveView: View {
    @Environment(WalletManager.self) private var manager
    @State private var selectedBalance: BalanceType = .payments
    @State private var showingQRCode = false
    @State private var showingAmountAndNote = false
    @State private var amount = ""
    @State private var note = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                addressContentSection
                amountAndNoteSection
                actionButtonsSection
            }
            .padding()
        }
        .navigationTitle("Receive bitcoin")
        .sheet(isPresented: $showingQRCode) {
            qrCodeSheet
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Choose balance to receive to")
                .font(.title2)
                .multilineTextAlignment(.center)
            
            BalanceTypePicker(selectedBalance: $selectedBalance)
                .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    private var addressContentSection: some View {
        AddressDisplayView(
            selectedBalance: selectedBalance,
            amount: amount,
            note: note
        )
    }
    
    @ViewBuilder
    private var amountAndNoteSection: some View {
        if selectedBalance != .lightning {
            AmountAndNoteInputView(
                amount: $amount,
                note: $note,
                showingAmountAndNote: $showingAmountAndNote
            )
        }
    }
    
    @ViewBuilder
    private var actionButtonsSection: some View {
        if selectedBalance != .lightning {
            ActionButtonsView(
                selectedBalance: selectedBalance,
                shareContent: getShareContent(),
                hasQRContent: getCurrentQRContent() != nil,
                onShowQRCode: { showingQRCode = true }
            )
        }
    }
    
    @ViewBuilder
    private var qrCodeSheet: some View {
        if let qrContent = getCurrentQRContent() {
            QRCodeView(
                content: qrContent.content,
                title: qrContent.title,
                onClose: { showingQRCode = false }
            )
            .frame(minWidth: 300, minHeight: 300)
        }
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentQRContent() -> (content: String, title: String)? {
        return ReceiveQRContentHelper.getCurrentQRContent(
            selectedBalance: selectedBalance,
            amount: amount,
            note: note,
            arkAddress: manager.arkAddress,
            onchainAddress: manager.onchainAddress
        )
    }
    
    private func getShareContent() -> String? {
        return ReceiveQRContentHelper.getShareContent(
            selectedBalance: selectedBalance,
            amount: amount,
            note: note,
            arkAddress: manager.arkAddress,
            onchainAddress: manager.onchainAddress
        )
    }
}

#Preview("Loading State") {
    ReceiveView()
        .environment(WalletManager(useMock: true))
        .frame(width: 600, height: 600)
}

#Preview("Loaded State") {
    @Previewable @State var mockManager = WalletManager(useMock: true)
    
    ReceiveView()
        .environment(mockManager)
        .frame(width: 600, height: 600)
        .task {
            // Initialize the mock manager to load mock addresses
            await mockManager.initialize()
        }
}
