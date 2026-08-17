//
//  QuickPaymentView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/24/25.
//

import SwiftUI
import ArkeUI

/// Represents the source of a payment request for UI display purposes
enum PaymentRequestSource {
    case clipboard
    case qrCode
    case deepLink
    case manual
    case nfc
    
    var displayName: String {
        switch self {
        case .clipboard:
            return "clipboard"
        case .qrCode:
            return "QR code"
        case .deepLink:
            return "link"
        case .manual:
            return "input"
        case .nfc:
            return "NFC tag"
        }
    }
    
    var iconName: String {
        switch self {
        case .clipboard:
            return "doc.on.clipboard"
        case .qrCode:
            return "qrcode"
        case .deepLink:
            return "link"
        case .manual:
            return "text.cursor"
        case .nfc:
            return "wave.3.right"
        }
    }
}

struct QuickPaymentView: View {
    let paymentRequest: PaymentRequest
    let onDismiss: () -> Void
    let onSendImmediately: ((UUID?, String?) -> Void)?
    let currentNetwork: NetworkConfig?
    let paymentContext: PaymentDestinationSelector.PaymentContext?
    let minimumSendAmount: Int
    let contactLookup: ((String) -> ContactModel?)?
    let maxSpendableAmount: Int
    let availableBalanceText: String
    let availableBalanceName: String
    let availableBalanceAmount: String
    let feeText: String
    let feeAmount: Int?
    let shouldShowFeeDisclosure: Bool
    let onchainFeeRates: OnchainFeeRates
    let source: PaymentRequestSource
    let onCalculateMaxSendable: (() async -> Int?)?
    let onEstimateFee: (() async -> Void)?
    let onEstimateLightningFee: (() async -> Void)?
    let onEstimateArkFee: (() async -> Void)?
    
    @Binding var showFeeSelectionSheet: Bool
    @Binding var selectedFeePriority: FeePriority
    @Binding var amount: String
    
    @State private var selectedDestinationId: UUID?
    @State private var isSending = false
    
    /// Cached ranked destinations to avoid recalculating on every render
    @State private var rankedDestinations: [PaymentDestinationSelector.RankedDestination] = []
    
    @FocusState private var isAmountFieldFocused: Bool
    
    init(
        paymentRequest: PaymentRequest,
        onDismiss: @escaping () -> Void,
        onSendImmediately: ((UUID?, String?) -> Void)? = nil,
        currentNetwork: NetworkConfig? = nil,
        paymentContext: PaymentDestinationSelector.PaymentContext? = nil,
        minimumSendAmount: Int = 0,
        contactLookup: ((String) -> ContactModel?)? = nil,
        maxSpendableAmount: Int = 0,
        availableBalanceText: String = "",
        availableBalanceName: String = "",
        availableBalanceAmount: String = "",
        feeText: String = "",
        feeAmount: Int? = nil,
        shouldShowFeeDisclosure: Bool = false,
        onchainFeeRates: OnchainFeeRates = .default,
        showFeeSelectionSheet: Binding<Bool> = .constant(false),
        selectedFeePriority: Binding<FeePriority> = .constant(.medium),
        amount: Binding<String> = .constant(""),
        source: PaymentRequestSource = .clipboard,
        onCalculateMaxSendable: (() async -> Int?)? = nil,
        onEstimateFee: (() async -> Void)? = nil,
        onEstimateLightningFee: (() async -> Void)? = nil,
        onEstimateArkFee: (() async -> Void)? = nil
    ) {
        self.paymentRequest = paymentRequest
        self.onDismiss = onDismiss
        self.onSendImmediately = onSendImmediately
        self.currentNetwork = currentNetwork
        self.paymentContext = paymentContext
        self.minimumSendAmount = minimumSendAmount
        self.contactLookup = contactLookup
        self.maxSpendableAmount = maxSpendableAmount
        self.availableBalanceText = availableBalanceText
        self.availableBalanceName = availableBalanceName
        self.availableBalanceAmount = availableBalanceAmount
        self.feeText = feeText
        self.feeAmount = feeAmount
        self.shouldShowFeeDisclosure = shouldShowFeeDisclosure
        self.onchainFeeRates = onchainFeeRates
        self._showFeeSelectionSheet = showFeeSelectionSheet
        self._selectedFeePriority = selectedFeePriority
        self._amount = amount
        self.source = source
        self.onCalculateMaxSendable = onCalculateMaxSendable
        self.onEstimateFee = onEstimateFee
        self.onEstimateLightningFee = onEstimateLightningFee
        self.onEstimateArkFee = onEstimateArkFee
    }
    
    // MARK: - Computed Properties
    
    /// The optimal (first viable) destination
    private var optimalDestination: PaymentDestinationSelector.RankedDestination? {
        rankedDestinations.first(where: { $0.viable })
    }
    
    /// Other viable destinations (excluding the optimal one)
    private var otherViableDestinations: [PaymentDestinationSelector.RankedDestination] {
        guard let optimal = optimalDestination else { return [] }
        return rankedDestinations.filter { $0.viable && $0.destination.id != optimal.destination.id }
    }
    
    // MARK: - Unified Display Properties
    
    /// All destinations as DisplayDestination objects
    private var allDisplayDestinations: [DisplayDestination] {
        if paymentContext != nil {
            // With context: all ranked destinations with viability info
            return rankedDestinations.map { ranked in
                DisplayDestination(
                    destination: ranked.destination,
                    estimatedFee: ranked.estimatedFee,
                    balanceSourceName: ranked.balanceSource.displayName,
                    matchedContact: contactLookup?(ranked.destination.address),
                    viable: ranked.viable,
                    viabilityReason: ranked.reason,
                    availableBalance: ranked.availableBalance
                )
            }
        } else {
            // Without context: primary + alternatives (assume viable)
            var all: [DisplayDestination] = []
            if let primary = paymentRequest.primaryDestination {
                all.append(DisplayDestination(
                    destination: primary,
                    estimatedFee: nil,
                    balanceSourceName: nil,
                    matchedContact: contactLookup?(primary.address),
                    viable: true,
                    viabilityReason: "No context available",
                    availableBalance: nil
                ))
            }
            all.append(contentsOf: paymentRequest.alternativeDestinations.map { destination in
                DisplayDestination(
                    destination: destination,
                    estimatedFee: nil,
                    balanceSourceName: nil,
                    matchedContact: contactLookup?(destination.address),
                    viable: true,
                    viabilityReason: "No context available",
                    availableBalance: nil
                )
            })
            return all
        }
    }
    
    /// The primary destination to always show (whether expanded or collapsed)
    private var primaryDisplayDestination: DisplayDestination? {
        // If user has selected a destination, show that one
        if let selectedId = selectedDestinationId,
           let selected = allDisplayDestinations.first(where: { $0.destination.id == selectedId }) {
            return selected
        }
        
        // Otherwise, fall back to default logic
        if paymentContext != nil, let firstRanked = rankedDestinations.first {
            // With context: show the first ranked destination (optimal or first non-viable)
            return DisplayDestination(
                destination: firstRanked.destination,
                estimatedFee: firstRanked.estimatedFee,
                balanceSourceName: firstRanked.balanceSource.displayName,
                matchedContact: contactLookup?(firstRanked.destination.address),
                viable: firstRanked.viable,
                viabilityReason: firstRanked.reason,
                availableBalance: firstRanked.availableBalance
            )
        } else if let primary = paymentRequest.primaryDestination {
            // Without context: show the primary destination
            return DisplayDestination(
                destination: primary,
                estimatedFee: nil,
                balanceSourceName: nil,
                matchedContact: contactLookup?(primary.address),
                viable: true,
                viabilityReason: "No context available",
                availableBalance: nil
            )
        }
        return nil
    }
    
    /// Alternative destinations to show when expanded
    private var alternativeDisplayDestinations: [DisplayDestination] {
        guard let primary = primaryDisplayDestination else { return [] }
        
        // Return all destinations except the one currently shown as primary
        return allDisplayDestinations.filter { $0.destination.id != primary.destination.id }
    }
    
    /// Whether there are alternatives to show
    private var hasAlternativeDestinations: Bool {
        !alternativeDisplayDestinations.isEmpty
    }
    
    /// Header label for the primary destination section
    private var primaryDestinationLabel: String {
        if primaryDisplayDestination?.balanceSourceName != nil {
            return L10n.labelAddress
        } else {
            return L10n.labelAddress
        }
    }
    
    private var isCompatibleWithNetwork: Bool {
        guard let network = currentNetwork else { return true }
        return paymentRequest.isCompatible(with: network)
    }
    
    private var networkMismatchMessage: String? {
        guard let network = currentNetwork,
              !isCompatibleWithNetwork,
              let primaryNetwork = paymentRequest.primaryNetwork else {
            return nil
        }
        return "This address is for \(primaryNetwork.displayName), but you're on \(network.name)"
    }
    
    private var isSimpleAddress: Bool {
        // Consider it a simple address if there's only one destination and no metadata
        return !paymentRequest.hasAlternatives && 
               paymentRequest.amount == nil && 
               paymentRequest.label == nil && 
               paymentRequest.message == nil
    }
    
    /// Check if payment request has all information needed for immediate send
    private var canSendImmediately: Bool {
        // Need an amount embedded in the payment request OR a valid entered amount
        let hasValidAmount = paymentRequest.amount != nil || isEnteredAmountValid
        guard hasValidAmount else { return false }
        
        // Need at least one viable destination
        guard optimalDestination != nil else { return false }
        
        // Need to be compatible with current network
        guard isCompatibleWithNetwork else { return false }
        
        // Need the callback to be provided
        guard onSendImmediately != nil else { return false }
        
        return true
    }
    
    /// Check if the entered amount is valid
    private var isEnteredAmountValid: Bool {
        guard let amountValue = Int(amount) else { return false }
        return amountValue >= minimumSendAmount && amountValue <= maxSpendableAmount
    }
    
    /// Whether to show the amount input section
    private var needsAmountInput: Bool {
        // Don't show if network is incompatible
        guard isCompatibleWithNetwork else { return false }
        
        // Don't show for Lightning invoices with fixed amounts
        if let primary = paymentRequest.primaryDestination,
           primary.format == .lightningInvoice,
           paymentRequest.amount != nil {
            return false
        }
        
        // Don't show for LNURL with fixed amounts (point-of-sale scenario)
        if let primary = paymentRequest.primaryDestination,
           primary.format == .lnurl,
           paymentRequest.amount != nil {
            return false
        }
        
        // Don't show for BIP-21 URIs with specific amounts (will add option to enable later)
        // BIP-21 URIs are identified by the original string starting with "bitcoin:"
        if paymentRequest.amount != nil,
           paymentRequest.originalString.lowercased().starts(with: "bitcoin:") {
            return false
        }
        
        return true
    }
    
    /// Whether the amount should be locked
    private var isAmountLocked: Bool {
        paymentRequest.amount != nil
    }
    
    /// Reason for locked amount
    private var lockedAmountReason: String? {
        guard isAmountLocked else { return nil }
        
        // Determine the reason based on the address format
        if let primary = paymentRequest.primaryDestination {
            switch primary.format {
            case .lightningInvoice:
                return "set by Lightning invoice"
            case .bip21:
                return "set by payment request"
            default:
                return "set by payment request"
            }
        }
        
        return "set by payment request"
    }
    
    /// Generate the appropriate title based on source and compatibility
    private var titleText: String {
        let contentType = isSimpleAddress ? "address" : "payment request"
        
        if !isCompatibleWithNetwork {
            // For incompatible addresses, use a consistent format
            return "Incompatible \(contentType)"
        }
        
        // Source-specific phrasing for compatible addresses
        switch source {
        case .clipboard:
            return "\(contentType.capitalized) found" // in clipboard
        case .qrCode:
            return "\(contentType.capitalized) scanned"
        case .deepLink:
            return "\(contentType.capitalized) from link"
        case .manual:
            return "\(contentType.capitalized) entered"
        case .nfc:
            return "\(contentType.capitalized) scanned"
        }
    }
    
    /// Generate the appropriate icon based on compatibility and source
    private var titleIcon: String {
        if !isCompatibleWithNetwork {
            return "exclamationmark.triangle.fill"
        }
        return source.iconName
    }
    
    /// Generate the appropriate icon color based on compatibility
    private var titleIconColor: Color {
        if !isCompatibleWithNetwork {
            return .Arke.orange
        }
        return .primary
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 25) {
                    HStack(spacing: 20) {
                        /*
                        Image(systemName: titleIcon)
                            .foregroundColor(titleIconColor)
                            .font(.title2)
                            .padding(15)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(titleIconColor.opacity(0.2), lineWidth: 1)
                            )
                        */
                        
                        ZStack {
                            Image("card")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            
                            Image(systemName: titleIcon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 48, height: 48)
                        
                        Text(titleText)
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.actionClearContact)
                        
                        /*
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.title)
                        }
                        .buttonStyle(.glass)
                        .help(L10n.actionClearContact)
                        */
                    }
                    
                    if let mismatchMessage = networkMismatchMessage {
                        Text(mismatchMessage)
                            .font(.body)
                            .foregroundColor(.Arke.orange)
                    }
                    
                    /*
                    // Show BIP-353 indicator
                    if BIP353Resolver.isBIP353Format(paymentRequest.originalString) {
                        Text("\(paymentRequest.originalString)")
                            .font(.title2)
                            .foregroundColor(.arkeSecondary)
                    }
                    */
                    
                    // Show payment request metadata (hide if simple address)
                    if (paymentRequest.label != nil && !paymentRequest.label!.isEmpty) || 
                       (paymentRequest.message != nil && !paymentRequest.message!.isEmpty) || 
                       paymentRequest.amount != nil {
                        PaymentRequestMetadataView(
                            label: paymentRequest.label,
                            message: paymentRequest.message,
                            amount: paymentRequest.amount
                        )
                    }
                    
                    // Unified destination display
                    SheetDestinationDisplayView(
                        primaryDisplayDestination: primaryDisplayDestination,
                        alternativeDisplayDestinations: alternativeDisplayDestinations,
                        primaryDestinationLabel: primaryDestinationLabel,
                        isSimpleAddress: isSimpleAddress,
                        showMatchedContact: true,
                        formatNameOverride: BIP353Resolver.isBIP353Format(paymentRequest.originalString) ? paymentRequest.originalString : nil,
                        selectedDestinationId: $selectedDestinationId
                    )
                    .disabled(isSending)
                    
                    // Show amount input section
                    if needsAmountInput {
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
                        .disabled(isSending)
                    }
                    
                    FeeDisplayView(
                        fee: feeAmount,
                        showDisclosure: shouldShowFeeDisclosure,
                        onTap: shouldShowFeeDisclosure ? {
                            showFeeSelectionSheet = true
                        } : nil
                    )
                }
            }
            
            HStack(alignment: .center, spacing: 20) {
                if isCompatibleWithNetwork {
                    Button {
                        guard !isSending else { return }
                        isSending = true
                        
                        // Capture state values before async work
                        let destId = selectedDestinationId
                        let amountToSend = amount.isEmpty ? nil : amount
                        
                        onSendImmediately?(destId, amountToSend)
                        isSending = false
                    } label: {
                        Text(L10n.buttonSend)
                            .font(.title2)
                            .foregroundStyle(Color.Arke.gold4)
                            .padding(.horizontal, 40)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(.Arke.gold)
                    .disabled(!canSendImmediately || isSending)
                } else {
                    Text(String(localized: "error_address_wrong_network", defaultValue: "Cannot use this address on current network"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: 400)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.buttonDone) {
                    isAmountFieldFocused = false
                }
            }
        }
        .onAppear {
            // Calculate ranked destinations once when view appears (if context provided)
            if let context = paymentContext {
                Task {
                    rankedDestinations = await paymentRequest.rankedDestinations(context: context)
                    print("🎯 [QuickPaymentView] Ranked \(rankedDestinations.count) destinations on appear")
                }
            }
            
            // Auto-select the optimal destination when the view appears
            if selectedDestinationId == nil {
                selectedDestinationId = optimalDestination?.destination.id
            }
            
            // Pre-populate amount if payment request has one
            if let requestAmount = paymentRequest.amount, amount.isEmpty {
                amount = "\(requestAmount)"
            }
        }
        .onChange(of: paymentRequest.id) {
            // Recalculate ranked destinations when payment request changes
            if let context = paymentContext {
                Task {
                    rankedDestinations = await paymentRequest.rankedDestinations(context: context)
                    print("🎯 [QuickPaymentView] Recalculated \(rankedDestinations.count) destinations")
                }
            }
            
            // Reset selection when payment request changes
            selectedDestinationId = optimalDestination?.destination.id
            
            // Update amount if payment request has one
            if let requestAmount = paymentRequest.amount {
                amount = "\(requestAmount)"
            } else {
                amount = ""
            }
        }
        .onChange(of: amount) { oldValue, newValue in
            // Avoid triggering if amount hasn't actually changed
            guard oldValue != newValue else { return }
            
            // Re-select optimal destination when amount changes
            // This ensures we always have a viable destination selected
            if let optimal = optimalDestination {
                // Only auto-switch if current selection is not viable
                if let currentId = selectedDestinationId,
                   let current = rankedDestinations.first(where: { $0.destination.id == currentId }),
                   !current.viable {
                    selectedDestinationId = optimal.destination.id
                }
            }
            
            // Trigger debounced fee estimation for all destination types
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
            guard let estimator = onEstimateFee else { return }
            guard !amount.isEmpty, Int(amount) != nil else { return }
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
    
    private func iconForFormat(_ format: AddressFormat) -> String {
        switch format {
        case .bitcoin:
            return "bitcoinsign.circle"
        case .ark:
            return "building.columns.circle"
        case .lightning, .lightningInvoice, .lnurl, .bolt12:
            return "bolt.circle"
        case .silentPayments:
            return "eye.slash.circle"
        case .bip353:
            return "at.circle"
        case .bip21:
            return "link.circle"
        }
    }
}
