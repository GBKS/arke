//
//  SendView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//
//  Architecture:
//  - Three distinct modes: Manual, Contact, and Quick
//  - Single SendState object that all child views can modify
//  - Mode selection happens once on initialization based on context
//  - Quick mode can transition to Manual (confirmed) when user accepts a bare address
//  - All modes can reset back to Manual (entering) via clearAll()
//

import SwiftUI
import AppKit
import ArkeUI

struct SendOperation_macOS: Identifiable {
    let id = UUID()
    let performSend: () async throws -> Void
}

/// macOS implementation of the Send view
struct SendView: View {
    // MARK: - Initialization Parameters
    let prefilledRecipient: String?
    let prefilledContact: ContactModel?
    let onNavigateToContact: ((ContactModel) -> Void)?
    
    @Environment(WalletManager.self) private var manager
    @Environment(\.dismiss) var dismiss
    
    // MARK: - State
    @State private var viewModel: SendViewModel?
    @State private var sendOperation: SendOperation_macOS?
    
    // MARK: - Initializers
    init(prefilledRecipient: String? = nil, prefilledContact: ContactModel? = nil, onNavigateToContact: ((ContactModel) -> Void)? = nil) {
        self.prefilledRecipient = prefilledRecipient
        self.prefilledContact = prefilledContact
        self.onNavigateToContact = onNavigateToContact
    }
    
    var body: some View {
        Group {
            if let viewModel {
                contentView(viewModel: viewModel)
            } else {
                ProgressView()
                    .task {
                        viewModel = SendViewModel(
                            walletManager: manager,
                            clipboardService: ClipboardService_macOS()
                        )
                        viewModel?.onDismiss = { dismiss() }
                        await viewModel?.handleInitialSetup(
                            prefilledRecipient: prefilledRecipient,
                            prefilledContact: prefilledContact
                        )
                    }
            }
        }
    }
    
    @ViewBuilder
    private func contentView(viewModel: SendViewModel) -> some View {
        @Bindable var viewModel = viewModel
        
        ScrollView {
            VStack(spacing: 24) {
                // Three distinct modes
                modeSpecificContent(viewModel: viewModel)
                
                // Error display
                if let error = viewModel.error {
                    errorView(viewModel: viewModel, error: error)
                }
                
                Spacer()
            }
            .frame(maxWidth: 600)
            .padding(.top, 20)
            .padding()
        }
        .navigationTitle("nav_title_send")
        .sheet(item: $sendOperation) { operation in
            sendModalSheet(operation: operation)
        }
        .sheet(isPresented: $viewModel.showDestinationPicker) {
            destinationPickerSheet(viewModel: viewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task {
                await viewModel.checkClipboardForAddress()
            }
        }
    }
    
    @ViewBuilder
    private func sendModalSheet(operation: SendOperation_macOS) -> some View {
        SendModalView(
            onDismissEntireView: {
                viewModel?.onDismiss?()
            },
            performSend: operation.performSend
        )
    }
    
    @ViewBuilder
    private func destinationPickerSheet(viewModel: SendViewModel) -> some View {
        PaymentDestinationPickerView(rankedDestinations: viewModel.rankedDestinations) { destination in
            viewModel.selectedDestination = destination
        }
    }
    
    @ViewBuilder
    private func modeSpecificContent(viewModel: SendViewModel) -> some View {
        switch viewModel.sendMode {
        case .manual:
            manualModeView(viewModel: viewModel)
            
        case .contact(let contact):
            contactModeView(viewModel: viewModel, contact: contact)
            
        case .quick(let paymentRequest, let source):
            quickModeView(viewModel: viewModel, paymentRequest: paymentRequest, source: source)
        }
    }
    
    @ViewBuilder
    private func manualModeView(viewModel: SendViewModel) -> some View {
        @Bindable var viewModel = viewModel
        
        ManualSendView(
            manualInput: $viewModel.manualInput,
            recipientState: $viewModel.recipientState,
            amount: $viewModel.amount,
            showAddressFormatsPopover: $viewModel.showAddressFormatsPopover,
            selectedDestination: $viewModel.selectedDestination,
            showFeeSelectionSheet: $viewModel.showFeeSelectionSheet,
            selectedFeePriority: $viewModel.selectedFeePriority,
            maxSpendableAmount: viewModel.maxSpendableAmount,
            availableBalanceText: viewModel.availableBalanceText,
            availableBalanceName: viewModel.availableBalanceName,
            availableBalanceAmount: viewModel.availableBalanceAmount,
            feeText: viewModel.feeText ?? "",
            feeAmount: viewModel.feeAmount,
            isAmountLocked: viewModel.isAmountLocked,
            lockedAmountReason: viewModel.lockedAmountReason,
            minimumSendAmount: viewModel.minimumSendAmount,
            paymentContext: viewModel.paymentContext,
            contactLookup: { address in
                let normalizedAddress = address.lowercased()
                let contacts = ServiceContainer.shared.contactService.contacts
                return contacts.first { contact in
                    contact.addresses.contains { $0.normalizedAddress == normalizedAddress }
                }
            },
            shouldShowFeeDisclosure: viewModel.shouldShowFeeDisclosure,
            onchainFeeRates: viewModel.onchainFeeRates,
            onSend: {
                sendOperation = SendOperation_macOS {
                    try await viewModel.executeSend()
                }
            },
            onSwitchToQuickMode: { paymentRequest in
                print("🔄 [SendView] Switching to quick mode from manual input")
                viewModel.sendMode = .quick(paymentRequest, source: .manual)
            },
            onCalculateMaxSendable: {
                await viewModel.calculateMaxSendable()
            },
            onEstimateFee: {
                viewModel.updateOnchainFeeEstimate()
            },
            onEstimateLightningFee: {
                viewModel.updateLightningFeeEstimate()
            },
            onEstimateArkFee: {
                viewModel.updateArkFeeEstimate()
            }
        )
        .onChange(of: viewModel.selectedDestination) { oldDestination, newDestination in
            // When destination changes in manual mode, rank it for fee calculation
            if case .manual = viewModel.sendMode,
               let destination = newDestination,
               oldDestination?.id != newDestination?.id {
                print("🔄 [SendView] Manual destination changed, ranking for fees")
                Task {
                    await viewModel.rankManualDestination(destination)
                }
            }
        }
        .popover(isPresented: $viewModel.showAddressFormatsPopover) {
            AddressFormatsInfoView()
        }
    }
    
    @ViewBuilder
    private func contactModeView(viewModel: SendViewModel, contact: ContactModel) -> some View {
        @Bindable var viewModel = viewModel
        
        ContactPaymentView(
            contact: contact,
            contactAddress: viewModel.selectedDestination?.address,
            onClear: {
                viewModel.clearAll()
            },
            onNavigateToContact: onNavigateToContact,
            onSend: {
                sendOperation = SendOperation_macOS {
                    try await viewModel.executeSend()
                }
            },
            onCalculateMaxSendable: {
                await viewModel.calculateMaxSendable()
            },
            onEstimateFee: {
                viewModel.updateOnchainFeeEstimate()
            },
            onEstimateLightningFee: {
                viewModel.updateLightningFeeEstimate()
            },
            onEstimateArkFee: {
                viewModel.updateArkFeeEstimate()
            },
            amount: $viewModel.amount,
            selectedDestination: $viewModel.selectedDestination,
            showFeeSelectionSheet: $viewModel.showFeeSelectionSheet,
            selectedFeePriority: $viewModel.selectedFeePriority,
            maxSpendableAmount: viewModel.maxSpendableAmount,
            availableBalanceText: viewModel.availableBalanceText,
            availableBalanceName: viewModel.availableBalanceName,
            availableBalanceAmount: viewModel.availableBalanceAmount,
            feeText: viewModel.feeText ?? "",
            feeAmount: viewModel.feeAmount,
            isAmountLocked: viewModel.isAmountLocked,
            lockedAmountReason: viewModel.lockedAmountReason,
            minimumSendAmount: viewModel.minimumSendAmount,
            paymentContext: viewModel.paymentContext,
            shouldShowFeeDisclosure: viewModel.shouldShowFeeDisclosure,
            onchainFeeRates: viewModel.onchainFeeRates
        )
    }
    
    @ViewBuilder
    private func quickModeView(viewModel: SendViewModel, paymentRequest: PaymentRequest, source: PaymentRequestSource) -> some View {
        @Bindable var viewModel = viewModel
        
        QuickPaymentView(
            paymentRequest: paymentRequest,
            onDismiss: {
                viewModel.clearAll()
            },
            onSendImmediately: { destinationId, enteredAmount in
                // Capture values immediately to avoid state race conditions
                let capturedDestinationId = destinationId
                let capturedAmount = enteredAmount
                
                // Determine the amount to send
                let amountToSend: String?
                if let entered = capturedAmount, !entered.isEmpty {
                    amountToSend = entered
                } else if let amount = paymentRequest.amount {
                    amountToSend = "\(amount)"
                } else {
                    amountToSend = nil
                }
                
                sendOperation = SendOperation_macOS {
                    try await viewModel.executeSend(paymentRequest: paymentRequest, destinationId: capturedDestinationId, amount: amountToSend)
                }
            },
            currentNetwork: viewModel.currentNetworkConfig,
            paymentContext: viewModel.paymentContext,
            minimumSendAmount: viewModel.minimumSendAmount,
            contactLookup: { address in
                let normalizedAddress = address.lowercased()
                let contacts = ServiceContainer.shared.contactService.contacts
                return contacts.first { contact in
                    contact.addresses.contains { $0.normalizedAddress == normalizedAddress }
                }
            },
            maxSpendableAmount: viewModel.maxSpendableAmount,
            availableBalanceText: viewModel.availableBalanceText,
            availableBalanceName: viewModel.availableBalanceName,
            availableBalanceAmount: viewModel.availableBalanceAmount,
            feeText: viewModel.feeText ?? "",
            feeAmount: viewModel.feeAmount,
            shouldShowFeeDisclosure: viewModel.shouldShowFeeDisclosure,
            onchainFeeRates: viewModel.onchainFeeRates,
            showFeeSelectionSheet: $viewModel.showFeeSelectionSheet,
            selectedFeePriority: $viewModel.selectedFeePriority,
            amount: $viewModel.amount,
            source: source,
            onCalculateMaxSendable: {
                await viewModel.calculateMaxSendable()
            },
            onEstimateFee: {
                viewModel.updateOnchainFeeEstimate()
            },
            onEstimateLightningFee: {
                viewModel.updateLightningFeeEstimate()
            },
            onEstimateArkFee: {
                viewModel.updateArkFeeEstimate()
            }
        )
    }
    
    @ViewBuilder
    private func errorView(viewModel: SendViewModel, error: String) -> some View {
        ErrorBox(
            errorMessage: error,
            onRetry: {
                sendOperation = SendOperation_macOS {
                    try await viewModel.executeSend()
                }
            },
            onDismiss: {
                viewModel.error = nil
            }
        )
        .frame(maxWidth: 400)
    }
}

#Preview("Empty State - Manual Entry") {
    NavigationStack {
        SendView()
            .environment(WalletManager(useMock: true))
    }
}

#Preview("Pre-filled Bitcoin Address") {
    NavigationStack {
        SendView(
            prefilledRecipient: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
            prefilledContact: nil
        )
        .environment(WalletManager(useMock: true))
    }
}

#Preview("Pre-filled Contact") {
    NavigationStack {
        SendView(
            prefilledRecipient: "ark1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
            prefilledContact: ContactModel(
                cachedName: "Alice Johnson",
                notes: "Friend from work"
            )
        )
        .environment(WalletManager(useMock: true))
    }
}

#Preview("BIP-21 with Label and Message") {
    NavigationStack {
        SendView(
            prefilledRecipient: "bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh?amount=0.001&label=Coffee%20Shop&message=Order%20%2342"
        )
        .environment(WalletManager(useMock: true))
    }
}

#Preview("BIP-21 with Label Only") {
    NavigationStack {
        SendView(
            prefilledRecipient: "bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh?label=Alice"
        )
        .environment(WalletManager(useMock: true))
    }
}

#Preview("BIP-21 Multi-Destination") {
    NavigationStack {
        SendView(
            prefilledRecipient: "bitcoin:tb1pxks6xl9e05xc3atcewg2tyyzgqm5n6mj6aduss3f0pau27206stsax872h?amount=0.001&label=Multi-Payment&ark=tark1pm6sr0fpzqqpu4k5llkn6wdswx48fwjjujgu4gm679lqwudrzghz7a2rx7wuup9cpqq6ssw20"
        )
        .environment(WalletManager(useMock: true))
    }
}

#Preview("Ark Address (No Label)") {
    NavigationStack {
        SendView(
            prefilledRecipient: "tark1pm6sr0fpzqqpu4k5llkn6wdswx48fwjjujgu4gm679lqwudrzghz7a2rx7wuup9cpqq6ssw20"
        )
        .environment(WalletManager(useMock: true))
    }
}

#Preview("Lightning Invoice") {
    NavigationStack {
        SendView(
            prefilledRecipient: "lnbc1000n1pj9x7zmpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu"
        )
        .environment(WalletManager(useMock: true))
    }
}

#Preview("BOLT12 Lightning Offer") {
    NavigationStack {
        SendView(
            prefilledRecipient: "lno1zrxq8pjw7qjlm68mtp7e3yvxee4y5xrgjhhyf2fxhlphpckrvevh50u0q2uumyll60x70znjle4vhrg496pmj4csnrnnxk7tkmf8fjx44zy4sqsrqtk7wvd7uqdv6yfrkpfgqplwggwfh8hnzsc8wzs8e79vphc6kugqqvuu3nm57har2dc73p40jz4xczrvjxdxyksueekymnzlvyytgy5fn8v4hjfxwrszhzkrgvd4hd"
        )
        .environment(WalletManager(useMock: true))
    }
}

#Preview("BIP-21 with BOLT12 Offer") {
    NavigationStack {
        SendView(
            prefilledRecipient: "bitcoin:?lno=lno1zrxq8pjw7qjlm68mtp7e3yvxee4y5xrgjhhyf2fxhlphpckrvevh50u0q2uumyll60x70znjle4vhrg496pmj4csnrnnxk7tkmf8fjx44zy4sqsrqtk7wvd7uqdv6yfrkpfgqplwggwfh8hnzsc8wzs8e79vphc6kugqqvuu3nm57har2dc73p40jz4xczrvjxdxyksueekymnzlvyytgy5fn8v4hjfxwrszhzkrgvd4hd"
        )
        .environment(WalletManager(useMock: true))
    }
}

#Preview("Silent Payment Address") {
    NavigationStack {
        SendView(
            prefilledRecipient: "sp1qqgste7k9hx0qftg6qmwlkqtwuy6cycyavzmzj85c6qdfhjdpdjtdgqjuexzk6murw56suy3e0rd2cgqvycxttddwsvgxe2usfpxumr70xc9pkqwv"
        )
        .environment(WalletManager(useMock: true))
    }
}

#Preview("BIP-353") {
    NavigationStack {
        // Note: This will attempt DNS resolution for ₿alice@example.com
        // In preview mode, it will likely fail and show nothing
        // Real testing requires actual DNS records
        SendView(
            prefilledRecipient: "₿chri@sto.ph"
        )
        .environment(WalletManager(useMock: true))
    }
}

#Preview("BIP-353 2") {
    NavigationStack {
        // Note: This will attempt DNS resolution first
        // If DNS fails, falls back to Lightning Address parsing
        SendView(
            prefilledRecipient: "chri@sto.ph"
        )
        .environment(WalletManager(useMock: true))
    }
}
