//
//  AddressDisplayView.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/21/25.
//

import SwiftUI
import ArkeUI

struct AddressDisplayView: View {
    @Environment(WalletManager.self) private var manager
    let selectedBalance: ReceiveBalanceType
    let amount: String
    let note: String
    @AppStorage(UserDefaults.showAddressIconsKey) private var showAddressIcons = true
    @State private var selectedAddressInfo: AddressInfo?
    
    struct AddressInfo: Identifiable {
        let id = UUID()
        let address: String
        let label: String
    }
    
    var body: some View {
        VStack(spacing: 20) {
            addressContentView
            /*
                .id(selectedBalance)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.9).combined(with: .offset(y: 50))),
                    removal: .opacity.combined(with: .scale(scale: 1.1))
                ))
             */
        }
        .sheet(item: $selectedAddressInfo) { info in
            AddressReviewSheet(
                address: info.address,
                title: info.label,
                showAddressIcons: showAddressIcons
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
            VStack(alignment: .leading, spacing: 8) {
                AddressCard(
                    address: manager.arkAddress,
                    shareContent: BIP21URIHelper.createBIP21URI(
                        arkAddress: manager.arkAddress,
                        amountSats: amount.isEmpty ? nil : amount,
                        label: nil,
                        message: note.isEmpty ? nil : note
                    ),
                    label: "Payments Address",
                    onTap: {
                        selectedAddressInfo = AddressInfo(
                            address: manager.arkAddress,
                            label: "Payments Address"
                        )
                    }
                )
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 20)
        } else {
            ProgressView()
                .scaleEffect(0.75)
                .padding()
        }
    }
    
    @ViewBuilder
    private var savingsAddressView: some View {
        if !manager.onchainAddress.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                AddressCard(
                    address: manager.onchainAddress,
                    shareContent: BIP21URIHelper.createBIP21URI(
                        onchainAddress: manager.onchainAddress,
                        amountSats: amount.isEmpty ? nil : amount,
                        label: nil,
                        message: note.isEmpty ? nil : note
                    ),
                    label: "Savings Address",
                    onTap: {
                        selectedAddressInfo = AddressInfo(
                            address: manager.onchainAddress,
                            label: "Savings Address"
                        )
                    }
                )
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 20)
        } else {
            ProgressView(String(localized: "progress_loading_address", defaultValue: "Loading address..."))
        }
    }
    
    @ViewBuilder
    private var combinedAddressesView: some View {
        VStack(spacing: 20) {
            if !manager.arkAddress.isEmpty {
                HStack(spacing: 12) {
                    /*
                    if showAddressIcons {
                        AddressHallmark(address: manager.arkAddress)
                            .frame(width: 26)
                            .padding(2)
                            .background(Color.systemBackground)
                            //.background(Color(uiColor: .systemBackground))
                            .cornerRadius(8)
                        //AddressIcon(address: manager.arkAddress, size: 24)
                    }
                    */
                    
                    AddressCard(
                        address: manager.arkAddress,
                        shareContent: BIP21URIHelper.createBIP21URI(
                            arkAddress: manager.arkAddress,
                            amountSats: amount.isEmpty ? nil : amount,
                            label: nil,
                            message: note.isEmpty ? nil : note
                        ),
                        label: "Payments Address",
                        onTap: {
                            selectedAddressInfo = AddressInfo(
                                address: manager.arkAddress,
                                label: "Payments Address"
                            )
                        }
                    )
                }
            } else {
                ProgressView(L10n.progressLoadingAddress)
            }
            
            Divider()
            
            if !manager.onchainAddress.isEmpty {
                HStack(spacing: 12) {
                    /*
                    if showAddressIcons {
                        AddressHallmark(address: manager.onchainAddress)
                            .frame(width: 26)
                            .padding(2)
                            .background(Color.systemBackground)
                            .cornerRadius(8)
                        //AddressIcon(address: manager.onchainAddress, size: 24)
                    }
                     */
                    
                    AddressCard(
                        address: manager.onchainAddress,
                        shareContent: BIP21URIHelper.createBIP21URI(
                            onchainAddress: manager.onchainAddress,
                            amountSats: amount.isEmpty ? nil : amount,
                            label: nil,
                            message: note.isEmpty ? nil : note
                        ),
                        label: "Savings Address (fallback)",
                        onTap: {
                            selectedAddressInfo = AddressInfo(
                                address: manager.onchainAddress,
                                label: "Savings Address (fallback)"
                            )
                        }
                    )
                }
            } else {
                ProgressView(L10n.progressLoadingAddress)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }
    
    @ViewBuilder
    private var lightningPlaceholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.circle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            
            Text(String(localized: "label_lightning_network", defaultValue: "Lightning Network"))
                .font(.headline)
            
            Text(String(localized: "message_lightning_coming_soon", defaultValue: "Lightning support coming soon... maybe!?"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 25)
        .padding(.vertical, 20)
    }
}
