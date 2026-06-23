//
//  SendView_iOS.swift
//  Arké
//
//  Created by Assistant on 12/8/25.
//
//  Architecture:
//  - Three distinct modes: Manual, Contact, and Quick
//  - Single SendState object that all child views can modify
//  - Mode selection happens once on initialization based on context
//  - Quick mode can transition to Manual (confirmed) when user accepts a bare address
//  - All modes can reset back to Manual (entering) via clearAll()
//

import SwiftUI
import ArkeUI
import CoreNFC
import os

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "SendView_iOS")

struct SendOperation_iOS: Identifiable {
    let id = UUID()
    let performSend: () async throws -> Void
}

enum SendInputMethod_iOS {
    case camera
    case input
}

/// iOS implementation of the Send view
struct SendView_iOS: View {
    // MARK: - Initialization Parameters
    let prefilledRecipient: String?
    let prefilledContact: ContactModel?
    let onNavigateToContact: ((ContactModel) -> Void)?
    let onNavigateToActivity: ((ContactModel?) -> Void)?
    let doubleTapTrigger: Int
    
    @Environment(WalletManager.self) private var manager
    @Environment(\.dismiss) var dismiss
    
    // MARK: - State
    @State private var viewModel: SendViewModel?
    @State private var inputMethod: SendInputMethod_iOS = .camera
    @State private var showContactPicker: Bool = false
    @State private var sendOperation: SendOperation_iOS?
    @State private var nfcReader: NFCReaderView_iOS?
    @State private var cameraResetTrigger: Int = 0
    
    // MARK: - Initializers
    init(prefilledRecipient: String? = nil, prefilledContact: ContactModel? = nil, onNavigateToContact: ((ContactModel) -> Void)? = nil, onNavigateToActivity: ((ContactModel?) -> Void)? = nil, doubleTapTrigger: Int = 0) {
        self.prefilledRecipient = prefilledRecipient
        self.prefilledContact = prefilledContact
        self.onNavigateToContact = onNavigateToContact
        self.onNavigateToActivity = onNavigateToActivity
        self.doubleTapTrigger = doubleTapTrigger
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
                            clipboardService: ClipboardService_iOS()
                        )
                        viewModel?.onDismiss = { [weak viewModel] in
                            logger.debug("🧹 Clearing form after successful send")
                            viewModel?.clearAll()
                            inputMethod = .camera
                        }
                        await viewModel?.handleInitialSetup(
                            prefilledRecipient: prefilledRecipient,
                            prefilledContact: prefilledContact
                        )
                        logger.debug("✅ Initial setup completed")
                        
                        // If we have prefilled data, switch to input mode (similar to QR scanning)
                        if prefilledRecipient != nil || prefilledContact != nil {
                            logger.debug("🔄 Switching to input mode (prefilled data)")
                            inputMethod = .input
                        }
                    }
            }
        }
    }
    
    @ViewBuilder
    private func contentView(viewModel: SendViewModel) -> some View {
        @Bindable var viewModel = viewModel
        
        mainContentStack(viewModel: viewModel)
            .sheet(item: $sendOperation) { operation in
                sendModalSheet(operation: operation)
            }
            .sheet(isPresented: $viewModel.showDestinationPicker) {
                destinationPickerSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showContactPicker) {
                contactPickerSheet()
            }
            .onAppear {
                handleViewAppearance(viewModel: viewModel)
                logger.debug("👁️ View appeared - inputMethod: \(String(describing: self.inputMethod))")
            }
            .onChange(of: doubleTapTrigger) {
                logger.debug("🔔 doubleTapTrigger changed to: \(self.doubleTapTrigger)")
                handleDoubleTap()
            }
            .onChange(of: inputMethod) { oldValue, newValue in
                logger.debug("🔄 inputMethod changed to: \(String(describing: self.inputMethod))")
                
                // Reset camera scanner when switching back to camera mode
                if oldValue == .input && newValue == .camera {
                    logger.debug("🔄 Switching to camera mode - resetting scanner")
                    cameraResetTrigger += 1
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Check clipboard availability when app becomes active
                // This doesn't trigger permission dialogs, just updates button visibility
                viewModel.checkClipboardAvailability()
            }
    }
    
    @ViewBuilder
    private func mainContentStack(viewModel: SendViewModel) -> some View {
        @Bindable var viewModel = viewModel
        
        ZStack {
            slidingContentView(viewModel: viewModel)
            
            // Floating controls overlay
            VStack {
                // Input method picker (centered) with NFC button (left-aligned)
                ZStack {
                    // Input method picker centered (rendered first so it's behind)
                    inputMethodPicker()
                    
                    // NFC button on the left (rendered on top so it receives taps)
                    HStack {
                        nfcScanButton()
                            .padding(.leading, 30)
                            .opacity(inputMethod == .camera ? 1 : 0)
                            .animation(.easeInOut(duration: 0.2), value: inputMethod)
                        
                        Spacer()
                    }
                    .allowsHitTesting(inputMethod == .camera) // Only allow hits when visible
                }
                .padding(.top, 16)
                
                Spacer()
                
                // Contact picker button positioned above tab bar on the left
                HStack {
                    contactCollageButton()
                        .padding(.leading, 30)
                        .padding(.bottom, 20) // Space above tab bar
                        .opacity(inputMethod == .camera ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: inputMethod)
                    
                    Spacer()
                    
                    // Paste button positioned above tab bar on the right
                    if viewModel.hasClipboardContent {
                        pasteButton()
                            .padding(.trailing, 30)
                            .padding(.bottom, 20) // Space above tab bar
                            .opacity(inputMethod == .camera ? 1 : 0)
                            .animation(.easeInOut(duration: 0.2), value: inputMethod)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func inputMethodPicker() -> some View {
        HStack {
            Spacer()
                .allowsHitTesting(false)
            SendInputMethodPicker_iOS(inputMethod: $inputMethod)
            Spacer()
                .allowsHitTesting(false)
        }
    }
    
    @ViewBuilder
    private func nfcScanButton() -> some View {
        Button {
            handleNFCScan()
        } label: {
            Image(systemName: "wave.3.right")
                .font(.title3)
                .frame(width: 40, height: 40)
                .glassEffect()
                .foregroundStyle(.primary)
        }
        //.buttonStyle(.plain)
        //.shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
    }
    
    @ViewBuilder
    private func pasteButton() -> some View {
        PasteButton_iOS {
            handlePasteFromClipboard()
        }
    }
    
    @ViewBuilder
    private func contactCollageButton() -> some View {
        // Get contacts with addresses from the service
        let contactsWithAddresses = ServiceContainer.shared.contactService.contacts.filter { $0.hasAddresses }
        
        ContactCollageButton_iOS(contacts: contactsWithAddresses) {
            showContactPicker = true
        }
    }
    
    @ViewBuilder
    private func slidingContentView(viewModel: SendViewModel) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                cameraView(viewModel: viewModel, width: geometry.size.width)
                inputFormView(viewModel: viewModel, width: geometry.size.width)
            }
            .frame(height: geometry.size.height)
            .offset(x: inputMethod == .camera ? 0 : -geometry.size.width)
            .animation(.easeInOut(duration: 0.3), value: inputMethod)
        }
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private func cameraView(viewModel: SendViewModel, width: CGFloat) -> some View {
        QRScannerView_iOS(onCodeScanned: { scannedCode in
            logger.debug("📸 QR Code Scanned: '\(scannedCode)'")
            
            // Handle scanned QR code
            Task { @MainActor in
                logger.debug("📸 Parsing scanned code...")
                
                // Extract the actual LNURL if it has a lightning: prefix
                let actualLNURL: String
                if scannedCode.lowercased().hasPrefix("lightning:") {
                    actualLNURL = String(scannedCode.dropFirst(10))
                } else {
                    actualLNURL = scannedCode
                }
                
                // Check if this is an LNURL - needs special handling to resolve and pre-fill fixed amounts
                if LNURLResolver.isLNURL(actualLNURL) {
                    logger.debug("📸 Detected LNURL in QR code (original: \(scannedCode.prefix(20))...)")
                    
                    do {
                        let resolved = try await LNURLResolver.resolve(actualLNURL)
                        logger.debug("✅ LNURL resolved successfully!")
                        logger.debug("   └─ Min: \(resolved.minSendableSats) sats, Max: \(resolved.maxSendableSats) sats")
                        logger.debug("   └─ Callback: \(resolved.callback)")
                        
                        // Check if this is a fixed-amount request (point-of-sale scenario)
                        if resolved.isFixedAmount {
                            logger.debug("   └─ 💰 Fixed amount detected: \(resolved.fixedAmountSats!) sats (POS mode)")
                        }
                        
                        // Store resolved LNURL for later use during payment
                        viewModel.resolvedLNURL = resolved
                        
                        // Parse the LNURL as a payment request (use original scannedCode to preserve lightning: prefix if present)
                        guard var paymentRequest = AddressValidator.parsePaymentRequest(scannedCode) else {
                            viewModel.error = "Failed to parse LNURL payment request"
                            inputMethod = .input
                            return
                        }
                        
                        // If this is a fixed-amount LNURL, pre-fill the amount
                        if let fixedAmount = resolved.fixedAmountSats {
                            logger.debug("   └─ Pre-filling fixed amount into payment request")
                            paymentRequest = PaymentRequest(
                                destinations: paymentRequest.destinations,
                                amount: fixedAmount,
                                label: paymentRequest.label,
                                message: paymentRequest.message,
                                originalString: paymentRequest.originalString
                            )
                        }
                        
                        logger.debug("   └─ Using quick mode (scanned LNURL)")
                        await viewModel.enterQuickMode(paymentRequest: paymentRequest, source: .qrCode)
                        
                        logger.debug("✅ LNURL payment request configured")
                        logger.debug("   └─ Current sendMode: \(viewModel.sendMode.description)")
                    } catch {
                        logger.debug("❌ LNURL resolution failed: \(error.localizedDescription)")
                        viewModel.error = "Failed to resolve LNURL: \(error.localizedDescription)"
                    }
                    
                    inputMethod = .input
                    return
                }
                
                // Parse the scanned code into a payment request
                if let paymentRequest = AddressValidator.parsePaymentRequest(scannedCode) {
                    logger.debug("✅ Valid payment request parsed: \(String(describing: paymentRequest))")
                    logger.debug("   └─ Amount: \(paymentRequest.amount?.description ?? "none")")
                    logger.debug("   └─ Label: \(paymentRequest.label ?? "none")")
                    logger.debug("   └─ Message: \(paymentRequest.message ?? "none")")
                    logger.debug("   └─ Destinations: \(paymentRequest.destinations.count)")
                    
                    // SCAN ROUTING: All scanned payment requests go to quick mode
                    // Rationale: User scanned with intent to pay - unlikely to edit address
                    // To revert to complexity-based routing, uncomment the if/else below:
                    /*
                    if viewModel.isSimplePaymentRequest(paymentRequest) {
                        logger.debug("   └─ Using manual mode (simple address)")
                        viewModel.lockInPaymentRequest(paymentRequest)
                    } else {
                        logger.debug("   └─ Using quick mode (rich payment request)")
                        await viewModel.enterQuickMode(paymentRequest: paymentRequest, source: .qrCode)
                    }
                    */
                    logger.debug("   └─ Using quick mode (scanned payment)")
                    await viewModel.enterQuickMode(paymentRequest: paymentRequest, source: .qrCode)
                    
                    logger.debug("✅ Payment request configured")
                    logger.debug("   └─ Current sendMode: \(viewModel.sendMode.description)")
                } else {
                    logger.debug("❌ Invalid payment request - showing error")
                    
                    // Invalid QR code - show in manual input with error
                    viewModel.manualInput = scannedCode
                    viewModel.error = "Invalid payment address or QR code"
                }
                
                logger.debug("🔄 Switching to input mode...")
                // Switch back to input mode to review the populated data
                inputMethod = .input
                logger.debug("✅ Switched to input mode")
                logger.debug("   └─ Final sendMode: \(viewModel.sendMode.description)")
            }
        }, resetTrigger: cameraResetTrigger)
        .frame(width: width)
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private func inputFormView(viewModel: SendViewModel, width: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Add top padding to account for the floating picker
                Spacer()
                    .frame(height: 80) // Matches picker height
                
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
        .frame(width: width)
        .scrollDismissesKeyboard(.interactively)
    }
    
    @ViewBuilder
    private func sendModalSheet(operation: SendOperation_iOS) -> some View {
        NavigationStack {
            SendModalView(
                onDismissEntireView: {
                    logger.debug("👋 Dismissing entire SendView")
                    viewModel?.onDismiss?()
                },
                performSend: operation.performSend
            )
        }
        .presentationDetents([.medium, .large])
    }
    
    @ViewBuilder
    private func destinationPickerSheet(viewModel: SendViewModel) -> some View {
        @Bindable var viewModel = viewModel
        
        NavigationStack {
            PaymentDestinationPickerView(rankedDestinations: viewModel.rankedDestinations) { destination in
                viewModel.selectedDestination = destination
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    @ViewBuilder
    private func contactPickerSheet() -> some View {
        ContactsView_iOS(
            onSelectContact: { contact, address in
                handleContactSelection(contact: contact, address: address)
            },
            onNavigateToActivity: { contact in
                // Dismiss the contact picker sheet first
                showContactPicker = false
                // Small delay to ensure sheet dismissal completes before navigation
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    onNavigateToActivity?(contact)
                }
            }
        )
        .environment(manager)
    }
    
    private func handleContactSelection(contact: ContactModel, address: ContactAddressModel) {
        logger.debug("👤 Contact selected: \(contact.displayName)")
        logger.debug("📍 Address selected: \(address.address)")
        
        // Populate the send form with the contact
        Task {
            logger.debug("🔄 Calling handleInitialSetup...")
            await viewModel?.handleInitialSetup(
                prefilledRecipient: address.address,
                prefilledContact: contact
            )
            
            logger.debug("✅ handleInitialSetup completed")
            logger.debug("   └─ sendMode: \(self.viewModel?.sendMode.description ?? "nil")")
            logger.debug("   └─ selectedDestination: \(self.viewModel?.selectedDestination?.address ?? "nil")")
            logger.debug("   └─ amount: '\(self.viewModel?.amount ?? "")'")
            
            // Switch to input mode to show the populated form
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    inputMethod = .input
                }
                logger.debug("✅ Switched to input mode with contact data")
            }
        }
    }
    
    private func handleViewAppearance(viewModel: SendViewModel) {
        // Check clipboard availability (doesn't trigger permission dialog)
        viewModel.checkClipboardAvailability()
    }
    
    private func handlePasteFromClipboard() {
        logger.debug("📋 Paste button tapped")
        
        // Read clipboard content (this may trigger permission dialog on first use)
        Task {
            let success = await viewModel?.checkClipboardForAddress() ?? false
            
            await MainActor.run {
                if success {
                    // Only switch to input mode if clipboard parsing succeeded
                    withAnimation(.easeInOut(duration: 0.3)) {
                        inputMethod = .input
                    }
                    logger.debug("✅ Switched to input mode with clipboard data")
                } else {
                    // Show error if clipboard didn't contain valid payment info
                    logger.debug("❌ Clipboard paste failed - no valid payment info found")
                    viewModel?.error = "No valid payment address found in clipboard"
                    // Still switch to input mode so user can see the error
                    withAnimation(.easeInOut(duration: 0.3)) {
                        inputMethod = .input
                    }
                }
            }
        }
    }
    
    private func handleNFCScan() {
        logger.debug("📡 NFC scan button tapped")
        
        // Check if NFC is available
        guard NFCReaderView_iOS.isAvailable else {
            logger.error("❌ NFC is not available on this device")
            viewModel?.error = "NFC is not available on this device"
            withAnimation(.easeInOut(duration: 0.3)) {
                inputMethod = .input
            }
            return
        }
        
        // Start NFC scanning - retain the reader to keep delegate alive
        let reader = NFCReaderView_iOS(
            onScan: { scannedData in
                self.handleNFCResult(scannedData)
            },
            onError: { [weak viewModel] errorMessage in
                logger.error("❌ NFC scan error: \(errorMessage)")
                Task { @MainActor in
                    viewModel?.error = errorMessage
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.inputMethod = .input
                    }
                    self.nfcReader = nil  // Clear reader after error
                }
            }
        )
        
        self.nfcReader = reader  // Retain the reader
        reader.startScanning()
    }
    
    private func handleNFCResult(_ scannedData: String) {
        logger.debug("📡 NFC Tag Scanned: '\(scannedData)'")
        
        // Handle scanned NFC data (same flow as QR code)
        Task { @MainActor in
            logger.debug("📡 Parsing scanned NFC data...")
            
            // Parse the scanned data into a payment request
            if let paymentRequest = AddressValidator.parsePaymentRequest(scannedData) {
                logger.debug("✅ Valid payment request parsed: \(String(describing: paymentRequest))")
                logger.debug("   └─ Amount: \(paymentRequest.amount?.description ?? "none")")
                logger.debug("   └─ Label: \(paymentRequest.label ?? "none")")
                logger.debug("   └─ Message: \(paymentRequest.message ?? "none")")
                logger.debug("   └─ Destinations: \(paymentRequest.destinations.count)")
                
                // SCAN ROUTING: All scanned payment requests go to quick mode
                // Rationale: User scanned with intent to pay - unlikely to edit address
                // To revert to complexity-based routing, uncomment the if/else below:
                /*
                if viewModel?.isSimplePaymentRequest(paymentRequest) == true {
                    logger.debug("   └─ Using manual mode (simple address)")
                    viewModel?.lockInPaymentRequest(paymentRequest)
                } else {
                    logger.debug("   └─ Using quick mode (rich payment request)")
                    await viewModel?.enterQuickMode(paymentRequest: paymentRequest, source: .nfc)
                }
                */
                logger.debug("   └─ Using quick mode (scanned payment)")
                await viewModel?.enterQuickMode(paymentRequest: paymentRequest, source: .nfc)
                
                logger.debug("✅ Payment request configured")
                logger.debug("   └─ Current sendMode: \(viewModel?.sendMode.description ?? "nil")")
            } else {
                logger.debug("❌ Invalid payment request - showing error")
                
                // Invalid NFC data - show in manual input with error
                viewModel?.manualInput = scannedData
                viewModel?.error = "Invalid payment address or NFC tag"
            }
            
            logger.debug("🔄 Switching to input mode...")
            // Switch to input mode to review the populated data
            withAnimation(.easeInOut(duration: 0.3)) {
                inputMethod = .input
            }
            logger.debug("✅ Switched to input mode")
            logger.debug("   └─ Final sendMode: \(viewModel?.sendMode.description ?? "nil")")
            
            // Clear the NFC reader
            nfcReader = nil
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
    
    // MARK: - Double-Tap Handler
    
    private func handleDoubleTap() {
        logger.debug("👆 handleDoubleTap() called")
        logger.debug("   └─ Current inputMethod: \(String(describing: self.inputMethod))")
        
        // Toggle between camera and input modes
        withAnimation(.easeInOut(duration: 0.3)) {
            let newMethod: SendInputMethod_iOS = inputMethod == .camera ? .input : .camera
            logger.debug("   └─ Toggling to: \(String(describing: newMethod))")
            inputMethod = newMethod
        }
        
        logger.debug("   └─ New inputMethod: \(String(describing: self.inputMethod))")
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
                sendOperation = SendOperation_iOS {
                    try await viewModel.executeSend()
                }
            },
            onSwitchToQuickMode: { paymentRequest in
                logger.debug("🔄 Switching to quick mode from manual input")
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
                logger.debug("🔄 Manual destination changed, ranking for fees")
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
        
        let _ = logger.debug("🏗️ Building contactModeView")
        let _ = logger.debug("   └─ contact: \(contact.displayName)")
        let _ = logger.debug("   └─ prefilledRecipient: \(self.prefilledRecipient ?? "nil")")
        let _ = logger.debug("   └─ viewModel.selectedDestination: \(viewModel.selectedDestination?.address ?? "nil")")
        let _ = logger.debug("   └─ viewModel.amount: '\(viewModel.amount)'")
        
        ContactPaymentView(
            contact: contact,
            contactAddress: viewModel.selectedDestination?.address,
            onClear: {
                viewModel.clearAll()
            },
            onNavigateToContact: onNavigateToContact,
            onSend: {
                sendOperation = SendOperation_iOS {
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
                
                sendOperation = SendOperation_iOS {
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
                sendOperation = SendOperation_iOS {
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

// MARK: - Camera Placeholder View

struct CameraPlaceholderView: View {
    var body: some View {
        ZStack {
            Color.Arke.blue.opacity(0.3)
            
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                
                Text("label_camera_view")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                
                Text("send_qr_scanner_placeholder")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Previews

#Preview("Empty State - Manual Entry") {
    NavigationStack {
        SendView_iOS()
            .environment(WalletManager(useMock: true))
    }
}

#Preview("Pre-filled Bitcoin Address") {
    NavigationStack {
        SendView_iOS(
            prefilledRecipient: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
            prefilledContact: nil
        )
        .environment(WalletManager(useMock: true))
    }
}

#Preview("Pre-filled Contact") {
    NavigationStack {
        SendView_iOS(
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
        SendView_iOS(
            prefilledRecipient: "bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh?amount=0.001&label=Coffee%20Shop&message=Order%20%2342"
        )
        .environment(WalletManager(useMock: true))
    }
}

#Preview("BIP-21 with Ark Alternative (Quick Mode)") {
    NavigationStack {
        SendView_iOS(
            prefilledRecipient: "bitcoin:tb1pxks6xl9e05xc3atcewg2tyyzgqm5n6mj6aduss3f0pau27206stsax872h?amount=0.00005&label=Coffee%20Shop&ark=tark1pm6sr0fpzqqpu4k5llkn6wdswx48fwjjujgu4gm679lqwudrzghz7a2rx7wuup9cpqq6ssw20&message=Venti%20White%20Caramel%20Crunch%20Frappuccino%20with%20Almond%20Milk%2C%20Extra%20Hot%2C%20Caramel%20Drizzle%2C%20and%20Extra%20Whip%20Cream"
        )
        .environment(WalletManager(useMock: true))
    }
}

#Preview("Lightning Invoice") {
    NavigationStack {
        SendView_iOS(
            prefilledRecipient: "lnbc1000n1pj9x7zmpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu"
        )
        .environment(WalletManager(useMock: true))
    }
}
