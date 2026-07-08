//
//  ContactPaymentView.swift
//  Arké
//
//  Created by Christoph on 11/18/25.
//

import SwiftUI
import ArkeUI

struct ContactPaymentView: View {
    let contact: ContactModel
    let contactAddress: String?
    let onClear: () -> Void
    let onNavigateToContact: ((ContactModel) -> Void)?
    let onSend: () -> Void
    let onCalculateMaxSendable: (() async -> Int?)?
    let onEstimateFee: (() async -> Void)?
    let onEstimateLightningFee: (() async -> Void)?
    let onEstimateArkFee: (() async -> Void)?
    
    // Amount input properties
    @Binding var amount: String
    @Binding var selectedDestination: PaymentDestination?
    @Binding var showFeeSelectionSheet: Bool
    @Binding var selectedFeePriority: FeePriority
    let maxSpendableAmount: Int
    let availableBalanceText: String
    let availableBalanceName: String
    let availableBalanceAmount: String
    let feeText: String
    let feeAmount: Int?
    let isAmountLocked: Bool
    let lockedAmountReason: String?
    let minimumSendAmount: Int
    let paymentContext: PaymentDestinationSelector.PaymentContext?
    let shouldShowFeeDisclosure: Bool
    let onchainFeeRates: OnchainFeeRates
    
    // State for destination card
    @State private var showFullAddress: Bool = false
    
    // BIP-353 resolution state
    @State private var isResolvingBIP353: Bool = false
    @State private var resolvedPaymentRequest: PaymentRequest? = nil
    @State private var resolutionError: String? = nil
    @State private var rankedDestinations: [PaymentDestinationSelector.RankedDestination] = []
    
    @FocusState private var isAmountFieldFocused: Bool
    
    // MARK: - Computed Properties
    
    /// Find the contact address that matches the provided contactAddress string
    private var matchedContactAddress: ContactAddressModel? {
        // If no specific address provided, use primary or first address
        guard let contactAddress = contactAddress else {
            return contact.primaryAddress ?? contact.addresses.first
        }
        
        let normalized = contactAddress.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // First try to find exact match on normalized address
        if let match = contact.addresses.first(where: { $0.normalizedAddress == normalized }) {
            return match
        }
        
        // Fallback to case-insensitive match on original address
        if let match = contact.addresses.first(where: { $0.address.lowercased() == normalized }) {
            return match
        }
        
        // If still no match and contact has a BIP-353 address, use that
        // This handles the case where SendViewModel resolved the BIP-353 but passed the resolved address
        if contact.bip353Addresses.count > 0 {
            return contact.primaryAddress ?? contact.bip353Addresses.first
        }
        
        return nil
    }
    
    /// Convert the matched ContactAddressModel to a PaymentDestination
    private var paymentDestination: PaymentDestination? {
        guard let matched = matchedContactAddress else { return nil }
        
        return PaymentDestination(
            format: matched.format,
            network: matched.network,
            address: matched.address,
            scanPublicKey: nil,
            spendPublicKey: nil
        )
    }
    
    /// Create a PaymentRequest from the matched address
    private var paymentRequest: PaymentRequest? {
        guard let destination = paymentDestination else { return nil }
        
        return PaymentRequest(
            destination: destination,
            amount: nil,
            label: matchedContactAddress?.label ?? contact.displayName,
            message: matchedContactAddress?.label != nil ? "Payment to \(contact.displayName)" : nil
        )
    }
    
    /// Check if there's a valid matched address
    private var hasMatchedAddress: Bool {
        matchedContactAddress != nil
    }
    
    /// Check if contactAddress was provided but no match was found
    private var hasUnmatchedAddress: Bool {
        contactAddress != nil && !contactAddress!.isEmpty && matchedContactAddress == nil
    }
    
    /// Check if the matched address is BIP-353 format
    private var isBIP353Address: Bool {
        matchedContactAddress?.format == .bip353
    }
    
    /// Convert ranked destinations to DisplayDestination for the destination display
    private var displayDestinations: [DisplayDestination] {
        rankedDestinations.map { ranked in
            DisplayDestination(
                destination: ranked.destination,
                estimatedFee: ranked.estimatedFee,
                balanceSourceName: ranked.balanceSource.displayName,
                matchedContact: contact,
                viable: ranked.viable,
                viabilityReason: ranked.reason,
                availableBalance: ranked.availableBalance
            )
        }
    }
    
    /// Primary destination to display (selected or first ranked)
    private var primaryDisplayDestination: DisplayDestination? {
        // If user has selected a destination, show that one
        if let selectedId = selectedDestination?.id,
           let selected = displayDestinations.first(where: { $0.destination.id == selectedId }) {
            return selected
        }
        // Otherwise show first ranked destination
        return displayDestinations.first
    }
    
    /// Alternative destinations (all except primary)
    private var alternativeDisplayDestinations: [DisplayDestination] {
        guard let primary = primaryDisplayDestination else { return [] }
        return displayDestinations.filter { $0.destination.id != primary.destination.id
        }
    }
    
    // MARK: - BIP-353 Resolution
    
    /// Resolves a BIP-353 address to get payment destinations
    private func resolveBIP353Address() async {
        guard let contactAddr = matchedContactAddress,
              contactAddr.format == .bip353 else {
            return
        }
        
        isResolvingBIP353 = true
        resolutionError = nil
        
        do {
            let resolved = try await BIP353Resolver.resolve(contactAddr.address)
            
            guard let paymentRequest = AddressValidator.parsePaymentRequest(resolved.bip21URI) else {
                resolutionError = "Could not parse resolved address"
                isResolvingBIP353 = false
                return
            }
            
            // Preserve original BIP-353 address in a new PaymentRequest
            let modifiedRequest = PaymentRequest(
                destinations: paymentRequest.destinations,
                amount: paymentRequest.amount,
                label: paymentRequest.label,
                message: paymentRequest.message,
                originalString: contactAddr.address
            )
            
            resolvedPaymentRequest = modifiedRequest
            
            // Rank destinations using payment context
            if let context = paymentContext {
                rankedDestinations = await modifiedRequest.rankedDestinations(context: context)
                
                // Auto-select optimal destination
                if selectedDestination == nil,
                   let optimal = rankedDestinations.first(where: { $0.viable }) {
                    selectedDestination = optimal.destination
                }
            }
            
            isResolvingBIP353 = false
        } catch {
            // BIP-353 failed, try Lightning Address as fallback
            do {
                _ = try await LightningAddressResolver.resolve(contactAddr.address)
                
                // Lightning Address resolved successfully
                let lightningDestination = PaymentDestination(
                    format: .lightning,
                    network: nil,
                    address: contactAddr.address
                )
                
                let paymentRequest = PaymentRequest(
                    destinations: [lightningDestination],
                    amount: nil,
                    label: nil,
                    message: nil,
                    originalString: contactAddr.address
                )
                
                resolvedPaymentRequest = paymentRequest
                
                if let context = paymentContext {
                    rankedDestinations = await paymentRequest.rankedDestinations(context: context)
                    
                    if selectedDestination == nil,
                       let optimal = rankedDestinations.first(where: { $0.viable }) {
                        selectedDestination = optimal.destination
                    }
                }
                
                isResolvingBIP353 = false
                
            } catch let lightningError {
                // Both BIP-353 and Lightning Address failed
                resolutionError = "Failed to resolve. BIP-353: \(error.localizedDescription), Lightning: \(lightningError.localizedDescription)"
                isResolvingBIP353 = false
            }
        }
    }
    
    // MARK: - Validation
    
    /// Determines if the Send button should be enabled
    private var canSend: Bool {
        print("🔍 [ContactPaymentView] canSend evaluation:")
        print("   └─ hasMatchedAddress: \(hasMatchedAddress)")
        print("   └─ selectedDestination: \(selectedDestination?.address ?? "nil")")
        print("   └─ isAmountLocked: \(isAmountLocked)")
        print("   └─ amount: '\(amount)'")
        print("   └─ amount.isEmpty: \(amount.isEmpty)")
        print("   └─ Int(amount): \(Int(amount) ?? -999)")
        
        // Must have a valid matched address
        guard hasMatchedAddress else {
            print("   └─ ❌ FAILED: No matched address")
            return false
        }
        guard selectedDestination != nil else {
            print("   └─ ❌ FAILED: selectedDestination is nil")
            return false
        }
        
        // If BIP-353, must be resolved successfully
        if isBIP353Address {
            guard !isResolvingBIP353 else {
                print("   └─ ❌ FAILED: Still resolving BIP-353")
                return false
            }
            guard resolutionError == nil else {
                print("   └─ ❌ FAILED: BIP-353 resolution error")
                return false
            }
            guard resolvedPaymentRequest != nil else {
                print("   └─ ❌ FAILED: No resolved payment request")
                return false
            }
        }
        
        // If amount is locked (e.g., Lightning invoice), we don't need user input
        if isAmountLocked {
            print("   └─ ✅ PASSED: Amount is locked")
            return true
        }
        
        // Otherwise, we need a valid amount
        let hasValidAmount = !amount.isEmpty && Int(amount) != nil
        print("   └─ \(hasValidAmount ? "✅ PASSED" : "❌ FAILED"): Valid amount check")
        return hasValidAmount
    }
    
    var body: some View {
        VStack(spacing: 24) {
            ContactInfoBanner(
                contact: contact,
                onClear: onClear,
                onViewContact: { onNavigateToContact?(contact) }
            )
            .onAppear {
                print("👁️ [ContactPaymentView] View appeared")
                print("   └─ contactAddress: \(contactAddress ?? "nil")")
                print("   └─ matchedContactAddress: \(matchedContactAddress?.address ?? "nil")")
                print("   └─ paymentDestination: \(paymentDestination?.address ?? "nil")")
                print("   └─ selectedDestination (before): \(selectedDestination?.address ?? "nil")")
                
                // Set the selected destination when the view appears
                if selectedDestination == nil {
                    selectedDestination = paymentDestination
                    print("   └─ Set selectedDestination to: \(selectedDestination?.address ?? "nil")")
                } else {
                    print("   └─ selectedDestination already set, not overriding")
                }
                
                // Trigger BIP-353 resolution if needed
                if isBIP353Address {
                    Task {
                        await resolveBIP353Address()
                    }
                }
            }
            
            // Destination Card - show matched address or error
            if hasMatchedAddress {
                VStack(alignment: .leading, spacing: 10) {
                    // Show BIP-353 original address if applicable
                    /*
                    if isBIP353Address, let original = matchedContactAddress?.address {
                        Text(original)
                            .font(.title2)
                            .foregroundColor(.arkeSecondary)
                    }
                    */
                    
                    // Resolution status
                    if isResolvingBIP353 {
                        HStack {
                            ProgressView()
                            Text(String(localized: "status_resolving_address"))
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    } else if let error = resolutionError {
                        Text(error)
                            .foregroundColor(.Arke.red)
                            .padding()
                    } else if isBIP353Address {
                        // Show resolved destinations using SheetDestinationDisplayView
                        SheetDestinationDisplayView(
                            primaryDisplayDestination: primaryDisplayDestination,
                            alternativeDisplayDestinations: alternativeDisplayDestinations,
                            primaryDestinationLabel: "Addresses",
                            isSimpleAddress: false,
                            showMatchedContact: false,
                            formatNameOverride: matchedContactAddress?.address,
                            selectedDestinationId: Binding(
                                get: { selectedDestination?.id },
                                set: { id in
                                    if let id = id,
                                       let ranked = rankedDestinations.first(where: { $0.destination.id == id }) {
                                        selectedDestination = ranked.destination
                                    }
                                }
                            )
                        )
                    } else {
                        // Non-BIP-353: show simple card
                        /*
                        Text("contacts_address")
                            .font(.title2)
                        */
                        
                        // Address card
                        if let destination = selectedDestination {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showFullAddress.toggle()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(matchedContactAddress?.label ?? destination.format.displayName)
                                            .font(.body)
                                            .fontWeight(.medium)
                                        
                                        Text(showFullAddress ? destination.address : destination.shortAddress)
                                            .font(.body.monospaced())
                                            .foregroundColor(showFullAddress ? .primary : .secondary)
                                            .lineSpacing(4)
                                            .lineLimit(showFullAddress ? nil : 1)
                                            .animation(.easeInOut(duration: 0.2), value: showFullAddress)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(15)
                                .background(.primary.opacity(0.05))
                                .cornerRadius(15)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.primary.opacity(0.1), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if hasUnmatchedAddress {
                // Error state: address provided but not found in contact
                AddressNotFoundErrorCard(
                    providedAddress: contactAddress ?? "",
                    contactName: contact.displayName,
                    contactAddressCount: contact.addresses.count
                )
            }
            
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
                Text("button_send")
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
                Button("button_done") {
                    isAmountFieldFocused = false
                }
            }
        }
        .onChange(of: amount) { oldValue, newValue in
            print("💰 [ContactPaymentView] amount changed: '\(oldValue)' → '\(newValue)'")
            print("   └─ canSend is now: \(canSend)")
            
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
        .onChange(of: selectedDestination) { oldValue, newValue in
            print("🎯 [ContactPaymentView] selectedDestination changed:")
            print("   └─ from: \(oldValue?.address ?? "nil")")
            print("   └─ to: \(newValue?.address ?? "nil")")
            print("   └─ canSend is now: \(canSend)")
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
}
