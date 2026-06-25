//
//  ReceiveView_iOS.swift
//  Arké
//
//  Created by Christoph on 11/27/25.
//

import SwiftUI
import ArkeUI
import CoreImage.CIFilterBuiltins
import SwiftData

struct ReceiveView_iOS: View {
    // MARK: - Initialization Parameters
    let doubleTapTrigger: Int
    
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ReceiveViewModel?
    @State private var showingBalanceTypeSheet = false
    
    // Lightning invoice sheet state
    @State private var showingInvoiceSheet = false
    @State private var isDeviceUpsideDown = false
    @State private var motionManager = MotionManager()
    
    // Address expansion state
    @State private var isAddressesExpanded = false
    
    // MARK: - Initializers
    init(doubleTapTrigger: Int = 0) {
        self.doubleTapTrigger = doubleTapTrigger
    }
    
    var body: some View {
        if let viewModel {
            contentView(viewModel: viewModel)
        } else {
            ProgressView()
                .task {
                    viewModel = ReceiveViewModel(walletManager: walletManager, modelContext: modelContext)
                }
        }
    }
    
    @ViewBuilder
    private func contentView(viewModel: ReceiveViewModel) -> some View {
        ZStack(alignment: .top) {
            slidingContentView(viewModel: viewModel)
                .zIndex(0)
             
            // Centered picker - controls balance type and sliding behavior
            ReceiveModePicker_iOS(
                selectedBalance: Binding(
                    get: { viewModel.selectedBalance },
                    set: { viewModel.selectedBalance = $0 }
                ),
                isReadOnlyMode: walletManager.isReadOnlyMode
            )
            .offset(y: 75)
        }
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: Binding(
            get: { viewModel.showingQRCode },
            set: { if !$0 { viewModel.hideQRCode() } }
        )) {
            qrCodeSheet(viewModel: viewModel)
        }
        .onChange(of: doubleTapTrigger) { oldValue, newValue in
            print("🔔 [ReceiveView_iOS] doubleTapTrigger changed: \(oldValue) → \(newValue)")
            handleDoubleTap()
        }
        .onChange(of: viewModel.lightningInvoice) { oldValue, newValue in
            // Show invoice sheet when invoice is generated
            if viewModel.selectedBalance == .lightning && newValue != nil && oldValue == nil {
                showingInvoiceSheet = true
            }
        }
        .onChange(of: viewModel.showAddressesOnly) { oldValue, newValue in
            // Show sheet when user wants to share addresses without invoice
            if viewModel.selectedBalance == .lightning && newValue && !oldValue {
                showingInvoiceSheet = true
            }
        }
        .sheet(isPresented: $showingBalanceTypeSheet) {
            BalanceTypeSelectionSheet_iOS(
                viewModel: viewModel,
                isPresented: $showingBalanceTypeSheet
            )
        }
        .fullScreenCover(isPresented: $showingInvoiceSheet) {
            LightningInvoiceSheet_iOS(
                invoice: viewModel.lightningInvoice,
                amount: viewModel.amount,
                note: viewModel.note,
                arkAddress: walletManager.arkAddress,
                onchainAddress: walletManager.onchainAddress,
                isDeviceUpsideDown: isDeviceUpsideDown,
                onClose: {
                    showingInvoiceSheet = false
                    viewModel.resetLightningForm()
                },
                walletManager: walletManager
            )
        }
        .onAppear {
            motionManager.startMonitoring()
        }
        .onDisappear {
            motionManager.stopMonitoring()
        }
        .onChange(of: motionManager.isForwardTilted) { _, newValue in
            isDeviceUpsideDown = newValue
        }
    }
    
    // MARK: - Double-Tap Handler
    
    private func handleDoubleTap() {
        guard let viewModel = viewModel else { return }
        
        // Skip in read-only mode (Lightning requires ASP connection)
        guard !walletManager.isReadOnlyMode else { return }
        
        print("👆 [ReceiveView_iOS] handleDoubleTap() called")
        print("   └─ Current selectedBalance: \(viewModel.selectedBalance)")
        
        // Toggle between Lightning and Payments/Savings balance types
        withAnimation(.easeInOut(duration: 0.3)) {
            let newBalance: ReceiveBalanceType = viewModel.selectedBalance == .lightning ? .paymentsAndSavings : .lightning
            print("   └─ Toggling to: \(newBalance)")
            viewModel.selectedBalance = newBalance
        }
        
        print("   └─ New selectedBalance: \(viewModel.selectedBalance)")
    }
    
    @ViewBuilder
    private func slidingContentView(viewModel: ReceiveViewModel) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                lightningModeView(viewModel: viewModel, width: geometry.size.width)
                addressesModeView(viewModel: viewModel, width: geometry.size.width)
            }
            .frame(height: geometry.size.height)
            .offset(x: viewModel.selectedBalance == .lightning ? 0 : -geometry.size.width)
            .animation(.easeInOut(duration: 0.3), value: viewModel.selectedBalance)
        }
    }
    
    
    // MARK: - Mode Views
    
    @ViewBuilder
    private func addressesModeView(viewModel: ReceiveViewModel, width: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    // Add top padding to account for the floating picker
                    Spacer()
                        .frame(height: 135)
                    
                    Text("Share your Addresses")
                        .font(.system(size: 24, design: .serif))
                        .multilineTextAlignment(.center)
                    
                    VStack(spacing: 0) {
                        AddressDisplayView(
                            selectedBalance: viewModel.selectedBalance,
                            amount: viewModel.amount,
                            note: viewModel.note
                        )
                    }
                    .background(.ultraThinMaterial)
                    .cornerRadius(25)
                    .padding(.horizontal)
                    
                    // Share buttons (non-Lightning only)
                    if viewModel.hasQRContent, let shareContent = viewModel.getShareContent() {
                        VStack(spacing: 30) {
                            // Main share button - shares BIP-21 URI as text
                            ShareLink(item: shareContent) {
                                Text("Share Payment Link")
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(Color.Arke.gold3)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 20)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(.Arke.gold)
                            .controlSize(.large)
                            .accessibilityLabel(String(localized: "accessibility_share_payment_request"))
                            .accessibilityHint(String(localized: "accessibility_share_payment_hint"))
                            
                            // vCard share button - only show if user has profile
                            if viewModel.hasUserProfile, let vcardURL = viewModel.getVCardData() {
                                ShareButton(items: [vcardURL]) {
                                    Text("Share Contact Card")
                                        .font(.system(size: 21, weight: .semibold))
                                        .foregroundStyle(Color.Arke.gold3)
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 20)
                                }
                                .buttonStyle(.plain)
                                .tint(.Arke.gold)
                                .controlSize(.small)
                                .accessibilityLabel(String(localized: "accessibility_share_contact_card"))
                                .accessibilityHint(String(localized: "accessibility_share_contact_hint"))
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
            }
        }
        .frame(width: width)
        .accessibilityLabel(String(localized: "accessibility_payment_qr"))
    }
    
    @ViewBuilder
    private func bitcoinModeView(viewModel: ReceiveViewModel, width: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    // Add top padding to account for the floating picker
                    Spacer()
                        .frame(height: 135)
                    
                    // Non-Lightning balance types (Bitcoin/Ark)
                    // Large QR Code Display
                    VStack(spacing: 20) {
                        if let qrContent = viewModel.getCurrentQRContent() {
                            ReceiveQRCodeDisplaySection_iOS(
                                content: qrContent.content,
                                title: qrContent.title
                            )
                        } else {
                            // Placeholder when no content available
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.large)
                                Text("Loading...")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(height: 300)
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(String(localized: "accessibility_loading_payment_address"))
                        }
                    }
                    .padding(.horizontal)
                    
                    // Amount and Note inputs (non-Lightning only)
                    if viewModel.getCurrentQRContent() != nil {
                        VStack(spacing: 0) {
                            amountAndNoteSection(viewModel: viewModel)
                        }
                        .background(.ultraThinMaterial)
                        .cornerRadius(25)
                        .padding(.horizontal)
                    }
                    
                    // Share buttons (non-Lightning only)
                    if viewModel.hasQRContent, let shareContent = viewModel.getShareContent() {
                        HStack(spacing: 12) {
                            // Main share button - shares BIP-21 URI as text
                            ShareLink(item: shareContent) {
                                Text("button_share")
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(Color.Arke.gold3)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 20)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(.Arke.gold)
                            .controlSize(.large)
                            .accessibilityLabel(String(localized: "accessibility_share_payment_request"))
                            .accessibilityHint(String(localized: "accessibility_share_payment_hint"))
                            
                            // vCard share button - only show if user has profile
                            if viewModel.hasUserProfile, let vcardURL = viewModel.getVCardData() {
                                ShareButton(items: [vcardURL]) {
                                    Image(systemName: "person.text.rectangle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.Arke.gold3)
                                        .frame(width: 30, height: 30)
                                }
                                .buttonStyle(.glassProminent)
                                .tint(.Arke.gold)
                                .controlSize(.large)
                                .accessibilityLabel(String(localized: "accessibility_share_contact_card"))
                                .accessibilityHint(String(localized: "accessibility_share_contact_hint"))
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Expandable address list section at the bottom
                    expandableAddressSection(viewModel: viewModel)
                        .padding(.horizontal)
                        .id("expandableSection")
                    
                    Spacer()
                }
            }
            .onChange(of: isAddressesExpanded) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        proxy.scrollTo("expandableSection", anchor: .bottom)
                    }
                }
            }
        }
        .frame(width: width)
        .accessibilityLabel(String(localized: "accessibility_payment_qr"))
    }
    
    @ViewBuilder
    private func lightningModeView(viewModel: ReceiveViewModel, width: CGFloat) -> some View {
        VStack(spacing: 20) {
            // Add top padding to account for the floating picker
            Spacer()
                .frame(height: 135)
            
            Text("Request a Payment")
                .font(.system(size: 24, design: .serif))
                .multilineTextAlignment(.center)
            
            LightningInvoiceFormView_iOS(
                amount: Binding(
                    get: { viewModel.amount },
                    set: { viewModel.amount = $0 }
                ),
                note: Binding(
                    get: { viewModel.note },
                    set: { viewModel.note = $0 }
                ),
                onGenerateInvoice: {
                    Task {
                        await viewModel.proceedWithOrWithoutInvoice()
                    }
                }
            )
        }
        .padding(.horizontal)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .accessibilityLabel(String(localized: "accessibility_lightning_invoice_form"))
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private func expandableAddressSection(viewModel: ReceiveViewModel) -> some View {
        VStack(spacing: 0) {
            // Header button
            Button(action: {
                withAnimation {
                    isAddressesExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Text("receive_your_addresses")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Image(systemName: "chevron.down")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .rotationEffect(.degrees(isAddressesExpanded ? 180 : 0))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            
            // Expanded content
            if isAddressesExpanded {
                VStack(spacing: 0) {
                    AddressDisplayView(
                        selectedBalance: viewModel.selectedBalance,
                        amount: viewModel.amount,
                        note: viewModel.note
                    )
                }
                .background(.ultraThinMaterial)
                .cornerRadius(25)
                .padding(.top, 8)
            }
        }
        .padding(.top, 20)
    }
    
    @ViewBuilder
    private func addressContentSection(viewModel: ReceiveViewModel) -> some View {
        // Only used for non-Lightning balance types now
        AddressDisplayView(
            selectedBalance: viewModel.selectedBalance,
            amount: viewModel.amount,
            note: viewModel.note
        )
    }
    
    @ViewBuilder
    private func amountAndNoteSection(viewModel vm: ReceiveViewModel) -> some View {
        // Only used for non-Lightning balance types now
        AmountAndNoteInputView(
            amount: Binding(
                get: { vm.amount },
                set: { vm.amount = $0 }
            ),
            note: Binding(
                get: { vm.note },
                set: { vm.note = $0 }
            ),
            showingAmountAndNote: Binding(
                get: { vm.showingAmountAndNote },
                set: { vm.showingAmountAndNote = $0 }
            )
        )
    }
    
    @ViewBuilder
    private func qrCodeSheet(viewModel: ReceiveViewModel) -> some View {
        if let qrContent = viewModel.getCurrentQRContent() {
            ArkeQRCodeView(
                content: qrContent.content,
                title: qrContent.title,
                onClose: { viewModel.hideQRCode() }
            )
            .frame(minWidth: 300, minHeight: 300)
        }
    }
    
    // MARK: - Toolbar Components
    
    @ViewBuilder
    private func balanceTypeMenu(viewModel: ReceiveViewModel) -> some View {
        Button {
            showingBalanceTypeSheet = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3)
                .frame(width: 40, height: 40)
                .glassEffect()
                .foregroundStyle(.primary)
        }
        .accessibilityLabel(String(localized: "accessibility_balance_type_options"))
        .accessibilityHint(String(localized: "accessibility_balance_type_selection_hint"))
    }
}

