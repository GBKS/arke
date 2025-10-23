//
//  AddressDisplayView.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/21/25.
//

import SwiftUI

struct AddressDisplayView: View {
    @Environment(WalletManager.self) private var manager
    let selectedBalance: ReceiveView.BalanceType
    let amount: String
    let note: String
    
    var body: some View {
        VStack(spacing: 20) {
            addressContentView
                .id(selectedBalance)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.9).combined(with: .offset(y: 50))),
                    removal: .opacity.combined(with: .scale(scale: 1.1))
                ))
        }
    }
    
    @ViewBuilder
    private var addressContentView: some View {
        switch selectedBalance {
        case .payments:
            paymentsAddressView
        case .savings:
            savingsAddressView
        case .paymentsAndSavings:
            combinedAddressesView
        case .lightning:
            lightningPlaceholderView
        }
    }
    
    @ViewBuilder
    private var paymentsAddressView: some View {
        if !manager.arkAddress.isEmpty {
            AddressCard(
                address: manager.arkAddress,
                shareContent: BIP21URIHelper.createBIP21URI(
                    arkAddress: manager.arkAddress,
                    amount: amount.isEmpty ? nil : amount,
                    label: nil,
                    message: note.isEmpty ? nil : note
                )
            )
            .frame(maxWidth: 400)
            .padding()
            .background(.regularMaterial)
            .cornerRadius(8)
        } else {
            ProgressView()
                .scaleEffect(0.75)
                .padding()
                .background(.regularMaterial)
                .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    private var savingsAddressView: some View {
        if !manager.onchainAddress.isEmpty {
            AddressCard(
                address: manager.onchainAddress,
                shareContent: BIP21URIHelper.createBIP21URI(
                    onchainAddress: manager.onchainAddress,
                    amount: amount.isEmpty ? nil : amount,
                    label: nil,
                    message: note.isEmpty ? nil : note
                )
            )
            .frame(maxWidth: 400)
            .padding()
            .background(.regularMaterial)
            .cornerRadius(8)
        } else {
            ProgressView("Loading Bitcoin address...")
        }
    }
    
    @ViewBuilder
    private var combinedAddressesView: some View {
        VStack(spacing: 16) {
            if !manager.arkAddress.isEmpty {
                AddressCard(
                    address: manager.arkAddress,
                    shareContent: BIP21URIHelper.createBIP21URI(
                        arkAddress: manager.arkAddress,
                        amount: amount.isEmpty ? nil : amount,
                        label: nil,
                        message: note.isEmpty ? nil : note
                    )
                )
                .frame(maxWidth: 400)
            } else {
                ProgressView("Loading Ark address...")
            }
            
            if !manager.onchainAddress.isEmpty {
                AddressCard(
                    address: manager.onchainAddress,
                    shareContent: BIP21URIHelper.createBIP21URI(
                        onchainAddress: manager.onchainAddress,
                        amount: amount.isEmpty ? nil : amount,
                        label: nil,
                        message: note.isEmpty ? nil : note
                    )
                )
                .frame(maxWidth: 400)
            } else {
                ProgressView("Loading Bitcoin address...")
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var lightningPlaceholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.circle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            
            Text("Lightning Network")
                .font(.headline)
            
            Text("Lightning support coming soon... maybe!?")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

#Preview {
    @Previewable @State var mockManager = {
        let manager = WalletManager(useMock: true)
        manager.arkAddress = "ark1qyqszqgpqyqszqgpqyqszqgpqyqs2q8tyyq"
        manager.onchainAddress = "bc1qxyxsxqgpqyqszqgpqyqszqgpqyqsz2q8tyy"
        return manager
    }()
    
    AddressDisplayView(
        selectedBalance: .payments,
        amount: "0.001",
        note: "Test payment"
    )
    .environment(mockManager)
    .frame(width: 500, height: 300)
}
