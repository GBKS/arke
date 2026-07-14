//
//  ReceiveView_iOS.swift
//  Arké
//
//  Created by Christoph on 11/27/25.
//

import SwiftUI
import ArkeUI
import SwiftData

struct ReceiveView_iOS: View {
    // MARK: - Initialization Parameters
    let doubleTapTrigger: Int
    
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ReceiveViewModel?

    // Lightning invoice sheet state
    @State private var showingInvoiceSheet = false
    @State private var isDeviceUpsideDown = false
    @State private var motionManager = MotionManager()

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
        .onChange(of: doubleTapTrigger) { _, _ in
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

        // Toggle between Lightning and Payments/Savings balance types
        withAnimation(.easeInOut(duration: 0.3)) {
            let newBalance: ReceiveBalanceType = viewModel.selectedBalance == .lightning ? .paymentsAndSavings : .lightning
            viewModel.selectedBalance = newBalance
        }
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
                    
                    Text("receive_share_your_addresses")
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
                                Text("receive_share_payment_link")
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(Color.Arke.gold4)
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
                                    Text("receive_share_contact_card")
                                        .font(.system(size: 21, weight: .semibold))
                                        .foregroundStyle(.primary)
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
    private func lightningModeView(viewModel: ReceiveViewModel, width: CGFloat) -> some View {
        VStack(spacing: 20) {
            // Add top padding to account for the floating picker
            Spacer()
                .frame(height: 135)
            
            Text("receive_request_a_payment")
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
}

