//
//  ReceiveView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import AppKit
import ArkeUI
import SwiftData

struct ReceiveView: View {
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ReceiveViewModel?
    
    var body: some View {
        Group {
            if let viewModel {
                contentView(viewModel: viewModel)
            } else {
                ProgressView()
                    .task {
                        viewModel = ReceiveViewModel(walletManager: walletManager, modelContext: modelContext)
                    }
            }
        }
        .navigationTitle(String(localized: "nav_title_receive", defaultValue: "Receive bitcoin"))
    }
    
    @ViewBuilder
    private func contentView(viewModel: ReceiveViewModel) -> some View {
        ScrollView {
            VStack(spacing: 30) {
                headerSection
                VStack(spacing: 0) {
                    addressContentSection(viewModel: viewModel)
                    Divider()
                        .padding(.leading, 25)
                        .padding(.trailing, 25)
                    amountAndNoteSection(viewModel: viewModel)
                }
                .background(.ultraThinMaterial)
                .cornerRadius(25)
                .frame(maxWidth: 400)
                actionButtonsSection(viewModel: viewModel)
            }
            .padding(.top, 30)
        }
        .toolbar {
            // Hide Lightning toggle in read-only mode (Lightning requires ASP connection)
            if !walletManager.isReadOnlyMode {
                ToolbarItem(placement: .primaryAction) {
                    balanceTypeMenu(viewModel: viewModel)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showingQRCode },
            set: { if !$0 { viewModel.hideQRCode() } }
        )) {
            qrCodeSheet(viewModel: viewModel)
        }
        .onChange(of: viewModel.selectedBalance) { oldValue, newValue in
            viewModel.changeBalanceType(to: newValue)
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(String(localized: "receive_share_info", defaultValue: "Share your payment info"))
                .font(.system(size: 24, design: .serif))
                .multilineTextAlignment(.center)
        }
    }
    
    @ViewBuilder
    private func balanceTypeMenu(viewModel: ReceiveViewModel) -> some View {
        Menu {
            ForEach(ReceiveBalanceType.allCases, id: \.self) { balanceType in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.changeBalanceType(to: balanceType)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(balanceType.rawValue)
                                .font(.body)
                            if viewModel.selectedBalance == balanceType {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .font(.body)
                                    .foregroundStyle(Color.Arke.blue)
                            }
                        }
                        Text(balanceType.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.balanceTypeLabel)
                    .font(.body)
                    .padding(.horizontal, 14)
            }
            .background(Color.clear)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .help(String(localized: "receive_switch_balance_type", defaultValue: "Switch balance type"))
    }
    
    @ViewBuilder
    private func addressContentSection(viewModel vm: ReceiveViewModel) -> some View {
        if vm.selectedBalance != .lightning {
            AddressDisplayView(
                selectedBalance: vm.selectedBalance,
                amount: vm.amount,
                note: vm.note
            )
        } else {
            if vm.lightningInvoice == nil {
                VStack(spacing: 8) {
                    Text(String(localized: "receive_lightning_invoice", defaultValue: "Lightning Invoice"))
                        .font(.title2)
                        .multilineTextAlignment(.center)
                    Text(String(localized: "receive_enter_amount", defaultValue: "Enter an amount to generate a Lightning invoice"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 30)
            }
        }
    }
    
    @ViewBuilder
    private func amountAndNoteSection(viewModel vm: ReceiveViewModel) -> some View {
        if vm.selectedBalance == .lightning {
            LightningAmountInputSection(
                amount: Binding(
                    get: { vm.amount },
                    set: { vm.amount = $0 }
                ),
                note: Binding(
                    get: { vm.note },
                    set: { vm.note = $0 }
                ),
                lightningInvoice: vm.lightningInvoice,
                invoiceError: vm.invoiceError,
                onAmountChange: { vm.clearLightningInvoice() },
                onNoteChange: { vm.clearLightningInvoice() },
                onInvoiceTap: {
                    if let invoice = vm.lightningInvoice {
                        vm.copyToClipboard(vm.extractInvoiceFromJSON(invoice))
                    }
                },
                showCopySuccess: vm.showCopySuccess
            )
        } else {
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
    }
    
    @ViewBuilder
    private func actionButtonsSection(viewModel: ReceiveViewModel) -> some View {
        if viewModel.selectedBalance == .lightning {
            LightningActionSection(
                amount: viewModel.amount,
                lightningInvoice: viewModel.lightningInvoice,
                isGeneratingInvoice: viewModel.isGeneratingInvoice,
                onCreateInvoice: {
                    Task {
                        await viewModel.generateLightningInvoice()
                    }
                },
                onShowQRCode: { viewModel.showQRCode() },
                extractInvoiceFromJSON: viewModel.extractInvoiceFromJSON
            )
        } else {
            ActionButtonsView(
                selectedBalance: viewModel.selectedBalance,
                shareContent: viewModel.getShareContent(),
                hasQRContent: viewModel.hasQRContent,
                onShowQRCode: { viewModel.showQRCode() }
            )
        }
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
}
