//
//  ManualSendView.swift
//  Arké
//
//  Created by Christoph on 11/18/25.
//

import SwiftUI
import ArkeUI

struct ManualSendView: View {
    // MARK: - Bindings
    @Binding var manualInput: String
    @Binding var recipientState: RecipientState
    @Binding var amount: String
    @Binding var showAddressFormatsPopover: Bool
    @Binding var selectedDestination: PaymentDestination?
    @Binding var showFeeSelectionSheet: Bool
    @Binding var selectedFeePriority: FeePriority
    
    // MARK: - Properties
    let maxSpendableAmount: Int
    let availableBalanceText: String
    let availableBalanceName: String
    let availableBalanceAmount: String
    let feeText: String
    let feeAmount: Int?
    let isAmountLocked: Bool
    let lockedAmountReason: String?
    let minimumSendAmount: Int
    let paymentContext: PaymentDestinationSelector.PaymentContext
    let contactLookup: ((String) -> ContactModel?)?
    let shouldShowFeeDisclosure: Bool
    let onchainFeeRates: OnchainFeeRates
    
    // MARK: - Callbacks
    let onSend: () -> Void
    let onSwitchToQuickMode: ((PaymentRequest) -> Void)?
    let onCalculateMaxSendable: (() async -> Int?)?
    let onEstimateFee: (() async -> Void)?
    let onEstimateLightningFee: (() async -> Void)?
    let onEstimateArkFee: (() async -> Void)?
    
    // MARK: - State
    @FocusState private var isRecipientFieldFocused: Bool
    @FocusState private var isAmountFieldFocused: Bool
    @State private var resolvedPaymentRequest: PaymentRequest?
    @State private var originalBIP353Address: String?
    @State private var isAlternativesExpanded = false
    @State private var selectedDestinationId: UUID?
    @State private var resolutionTask: Task<Void, Never>?
    
    // MARK: - Computed Properties
    
    /// Determines if we're in confirmed mode (valid address)
    private var isConfirmed: Bool {
        switch recipientState {
        case .valid, .bip353Resolved:
            return true
        default:
            return false
        }
    }
    
    /// Determines if the Send button should be enabled
    private var canSend: Bool {
        guard isConfirmed else { return false }
        // guard let destination = selectedDestination else { return false }
        
        // If amount is locked (e.g., Lightning invoice), we don't need user input
        if isAmountLocked { return true }
        
        // Otherwise, we need a valid amount
        guard !amount.isEmpty, let amountValue = Int(amount) else { return false }
        
        // For Ark addresses, enforce minimum send amount
        if amountValue < minimumSendAmount {
            return false
        }
        
        return true
    }
    
    // MARK: - BIP-353 Resolution Display Properties
    
    /// All destinations as DisplayDestination objects (for BIP-353 resolved addresses)
    private var allDisplayDestinations: [DisplayDestination] {
        guard let paymentRequest = resolvedPaymentRequest else { return [] }
        
        // Note: This is a synchronous computed property, so we can't call async ranking here.
        // The destinations are displayed with static info; fees are calculated when selected
        return paymentRequest.destinations.map { destination in
            let balanceSource = PaymentDestinationSelector.balanceSource(for: destination)
            let availableBalance = PaymentDestinationSelector.availableBalance(for: destination, context: paymentContext)
            
            return DisplayDestination(
                destination: destination,
                estimatedFee: nil,  // Will be calculated async when user selects
                balanceSourceName: balanceSource.displayName,
                matchedContact: contactLookup?(destination.address),
                viable: true,  // Assume viable for display; will validate on selection
                viabilityReason: "Tap to select",
                availableBalance: availableBalance
            )
        }
    }
    
    /// The primary destination to show
    private var primaryDisplayDestination: DisplayDestination? {
        // If user has selected a destination, show that one
        if let selectedId = selectedDestinationId,
           let selected = allDisplayDestinations.first(where: { $0.destination.id == selectedId }) {
            return selected
        }
        
        // Otherwise, show the first ranked destination
        return allDisplayDestinations.first
    }
    
    /// Alternative destinations to show when expanded
    private var alternativeDisplayDestinations: [DisplayDestination] {
        guard let primary = primaryDisplayDestination else { return [] }
        return allDisplayDestinations.filter { $0.destination.id != primary.destination.id }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Recipient input section
            RecipientInputSection(
                input: $manualInput,
                state: $recipientState,
                destination: $selectedDestination,
                onShowAddressFormats: {
                    showAddressFormatsPopover = true
                },
                onPaymentRequestParsed: { paymentRequest in
                    handlePaymentRequestParsed(paymentRequest)
                },
                isRecipientFieldFocused: $isRecipientFieldFocused
            )
            .padding(.top, 15)
            
            // Show original BIP-353 address when resolved
            /*
            if case .bip353Resolved(let originalAddress) = recipientState {
                Text(originalAddress)
                    .font(.title2)
                    .foregroundColor(.arkeSecondary)
            }
            */
            
            // Show resolved destinations for BIP-353
            if case .bip353Resolved = recipientState,
               let primaryDisplay = primaryDisplayDestination {
                SheetDestinationDisplayView(
                    primaryDisplayDestination: primaryDisplay,
                    alternativeDisplayDestinations: alternativeDisplayDestinations,
                    primaryDestinationLabel: L10n.labelAddress,
                    isSimpleAddress: false,
                    showMatchedContact: true,
                    formatNameOverride: originalBIP353Address,
                    selectedDestinationId: $selectedDestinationId
                )
            }
                
            // Amount section (shown in confirmed mode)
            AmountInputSection(
                amount: $amount,
                maxSpendableAmount: maxSpendableAmount,
                availableBalanceText: availableBalanceText,
                availableBalanceName: availableBalanceName,
                availableBalanceAmount: availableBalanceAmount,
                feeText: feeText,
                isAmountLocked: isAmountLocked,
                lockedAmountReason: lockedAmountReason,
                minimumSendAmount: minimumSendAmount,
                onCalculateMaxSendable: onCalculateMaxSendable,
                isAmountFieldFocused: $isAmountFieldFocused
            )
            
            FeeDisplayView(
                fee: feeAmount,
                showDisclosure: shouldShowFeeDisclosure,
                onTap: shouldShowFeeDisclosure ? {
                    showFeeSelectionSheet = true
                } : nil
            )
            
            // Send button
            Button {
                onSend()
            } label: {
                Text(L10n.buttonSend)
                    .font(.title2)
                    .foregroundStyle(Color.Arke.gold4)
                    .padding(.horizontal, 40)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Color.Arke.gold)
            .frame(maxWidth: .infinity)
            .disabled(!canSend)
            .padding(.top, 16)
        }
        .frame(maxWidth: 400)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.buttonDone) {
                    isRecipientFieldFocused = false
                    isAmountFieldFocused = false
                }
            }
        }
        .onChange(of: recipientState) { oldState, newState in
            handleRecipientStateChange(oldState: oldState, newState: newState)
        }
        .onChange(of: selectedDestinationId) { _, newId in
            // Update selectedDestination when user picks from alternatives
            if let newId = newId,
               let destination = allDisplayDestinations.first(where: { $0.destination.id == newId }) {
                selectedDestination = destination.destination
            }
        }
        .onChange(of: amount) { _, newValue in
            // Trigger debounced fee estimation when amount changes
            // Call even when empty to clear the cache
            Task {
                if let estimator = onEstimateFee {
                    await estimator()
                }
                if let lightningEstimator = onEstimateLightningFee {
                    await lightningEstimator()
                }
                if let arkEstimator = onEstimateArkFee {
                    await arkEstimator()
                }
            }
        }
        .onChange(of: selectedFeePriority) { _, _ in
            // Recalculate fee immediately when priority changes (onchain only)
            guard let estimator = onEstimateFee else { return }

            Task {
                await estimator()
            }
        }
        .onChange(of: showFeeSelectionSheet) { _, isShowing in
            // Refresh fee rates when the fee sheet opens so it never shows stale tiers
            guard isShowing, let estimator = onEstimateFee else { return }
            Task {
                await estimator()
            }
        }
        .sheet(isPresented: $showFeeSelectionSheet) {
            FeeSelectionSheet(
                selectedPriority: $selectedFeePriority,
                feeRates: onchainFeeRates,
                onDismiss: {
                    showFeeSelectionSheet = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Payment Request Handling
    
    /// Called when RecipientInputSection parses a payment request from manual input
    /// Decides whether to switch to quick mode for complex requests
    private func handlePaymentRequestParsed(_ paymentRequest: PaymentRequest) {
        // Check if this is a complex payment request that should use quick mode
        // Simple addresses (bare Bitcoin/Ark addresses) stay in manual mode
        let isComplex = paymentRequest.hasAlternatives ||
                       paymentRequest.amount != nil ||
                       paymentRequest.label != nil ||
                       paymentRequest.message != nil
        
        if isComplex {
            print("📋 [ManualSendView] Complex payment request detected, switching to quick mode")
            print("   → Has alternatives: \(paymentRequest.hasAlternatives)")
            print("   → Has amount: \(paymentRequest.amount != nil)")
            print("   → Has label: \(paymentRequest.label != nil)")
            print("   → Has message: \(paymentRequest.message != nil)")
            
            // Switch to quick mode via callback
            onSwitchToQuickMode?(paymentRequest)
        } else {
            print("📋 [ManualSendView] Simple address detected, staying in manual mode")
        }
    }
    
    // MARK: - BIP-353 Resolution Logic
    
    private func handleRecipientStateChange(oldState: RecipientState, newState: RecipientState) {
        // Only cancel resolution if we're moving away from the BIP-353 flow entirely
        let shouldCancelResolution: Bool
        switch (oldState, newState) {
        case (.validBIP353Format, .validBIP353Format),
             (.validBIP353Format, .resolvingBIP353),
             (.resolvingBIP353, .bip353Resolved),
             (.resolvingBIP353, .invalid):
            // These are valid transitions in the BIP-353 resolution flow
            shouldCancelResolution = false
        case (.validBIP353Format, _), (.resolvingBIP353, _):
            // Moving away from BIP-353 flow to another state
            shouldCancelResolution = true
        default:
            shouldCancelResolution = false
        }
        
        if shouldCancelResolution {
            resolutionTask?.cancel()
        }
        
        // Start BIP-353 resolution when format is detected
        if case .validBIP353Format = newState {
            resolutionTask = Task {
                await resolveBIP353Address()
            }
        }
    }
    
    private func resolveBIP353Address() async {
        // Capture the input immediately to avoid race conditions
        let trimmedInput = manualInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Update to resolving state
        recipientState = .resolvingBIP353
        
        do {
            let resolved = try await BIP353Resolver.resolve(trimmedInput)
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            // Parse resolved BIP-21 URI
            guard var paymentRequest = AddressValidator.parsePaymentRequest(resolved.bip21URI) else {
                recipientState = .invalid("Could not parse resolved address")
                return
            }
            
            // Preserve original BIP-353 address
            paymentRequest = PaymentRequest(
                destinations: paymentRequest.destinations,
                amount: paymentRequest.amount,
                label: paymentRequest.label,
                message: paymentRequest.message,
                originalString: resolved.originalAddress
            )
            
            // Store resolved data
            resolvedPaymentRequest = paymentRequest
            originalBIP353Address = resolved.originalAddress
            
            // Rank destinations and select optimal
            let ranked = await paymentRequest.rankedDestinations(context: paymentContext)
            if let optimal = ranked.first(where: { $0.viable }) {
                selectedDestination = optimal.destination
                selectedDestinationId = optimal.destination.id
            } else if let first = ranked.first {
                // No viable destinations, but select the first one anyway
                selectedDestination = first.destination
                selectedDestinationId = first.destination.id
            }
            
            // Pre-fill amount if present
            if let requestAmount = paymentRequest.amount {
                amount = "\(requestAmount)"
            }
            
            // Update state to resolved
            recipientState = .bip353Resolved(resolved.originalAddress)
            
        } catch {
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            // BIP-353 failed, try Lightning Address as fallback
            do {
                _ = try await LightningAddressResolver.resolve(trimmedInput)
                
                guard !Task.isCancelled else { return }
                
                // Lightning Address resolved successfully
                // Create a simple payment request with Lightning destination
                let lightningDestination = PaymentDestination(
                    format: .lightning,
                    network: nil,
                    address: trimmedInput
                )
                
                let paymentRequest = PaymentRequest(
                    destinations: [lightningDestination],
                    amount: nil,
                    label: nil,
                    message: nil,
                    originalString: trimmedInput
                )
                
                // Store resolved data
                resolvedPaymentRequest = paymentRequest
                originalBIP353Address = trimmedInput
                selectedDestination = lightningDestination
                selectedDestinationId = lightningDestination.id
                
                // Update state to resolved (reusing bip353Resolved for now)
                recipientState = .bip353Resolved(trimmedInput)
                
            } catch let lightningError {
                // Both BIP-353 and Lightning Address failed
                guard !Task.isCancelled else { return }
                
                recipientState = .invalid("Address resolution failed. BIP-353: \(error.localizedDescription), Lightning: \(lightningError.localizedDescription)")
                resolvedPaymentRequest = nil
                originalBIP353Address = nil
            }
        }
    }
}
