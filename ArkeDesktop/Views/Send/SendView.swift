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
import SwiftData

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
    @Environment(\.modelContext) private var modelContext
    
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
                            clipboardService: ClipboardService_macOS(),
                            modelContext: modelContext
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
        .navigationTitle(String(localized: "nav_title_send", defaultValue: "Send bitcoin"))
        .sheet(item: $sendOperation) { operation in
            sendModalSheet(operation: operation)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task {
                await viewModel.checkClipboardForAddress()
            }
        }
    }
    
    @ViewBuilder
    private func sendModalSheet(operation: SendOperation_macOS) -> some View {
        if let viewModel = viewModel {
            @Bindable var viewModel = viewModel
            
            SendModalView(
                onDismissEntireView: {
                    viewModel.onDismiss?()
                },
                performSend: operation.performSend,
                pendingMetadata: $viewModel.pendingMetadata
            )
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
