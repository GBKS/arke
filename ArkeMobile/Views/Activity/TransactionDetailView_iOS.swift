//
//  TransactionDetailView_iOS.swift
//  Arké
//
//  Created by Assistant on 12/8/25.
//

import SwiftUI
import ArkeUI
import Bark
import SwiftData

struct TransactionDetailView_iOS: View {
    let transaction: TransactionModel
    let onNavigateToContact: ((ContactModel) -> Void)?
    let onNavigateToTag: ((TagModel) -> Void)?
    
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TransactionDetailViewModel?
    @State private var showAbsoluteDate = false
    
    // Exit state
    @State private var exitVtxos: [ExitVtxo] = []
    @State private var exitStatus: ExitTransactionStatus?
    
    var body: some View {
        Group {
            if let viewModel {
                contentView(viewModel: viewModel)
            } else {
                ProgressView()
                    .task {
                        viewModel = TransactionDetailViewModel(
                            transaction: transaction,
                            walletManager: walletManager
                        )
                    }
            }
        }
        .onAppear {
            print("=== Transaction Detail View Appeared ===")
            print("Transaction Data:")
            print("  txid: \(transaction.txid)")
            print("  movementId: \(transaction.movementId?.description ?? "nil")")
            print("  recipientIndex: \(transaction.recipientIndex?.description ?? "nil")")
            print("  type: \(transaction.transactionType)")
            print("  amount: \(transaction.amount)")
            print("  date: \(transaction.date)")
            print("  status: \(transaction.transactionStatus)")
            print("  address: \(transaction.address ?? "nil")")
            print("  fees: \(transaction.fees?.description ?? "nil")")
            print("  onchainFeeSat: \(transaction.onchainFeeSat?.description ?? "nil")")
            print("  category: \(transaction.category?.rawValue ?? "nil")")
            print("  subsystemCategory: \(transaction.subsystemCategory ?? "nil")")
            print("  subsystemKind: \(transaction.subsystemKind ?? "nil")")
            print("  subsystemName: \(transaction.subsystemName ?? "nil")")
            print("  notes: \(transaction.notes ?? "nil")")
            print("  associatedContacts: \(transaction.associatedContacts.map { $0.displayName }.joined(separator: ", "))")
            print("  associatedTags: \(transaction.associatedTags.map { $0.name }.joined(separator: ", "))")
            print("=====================================")
            
            // Load exit data for claimable exit banner
            loadExitData()
        }
        //.navigationTitle("Transaction")
        //.navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private func contentView(viewModel: TransactionDetailViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // Header Section
                headerView
                
                // Claimable Exit Banner
                claimableExitBanner
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 20) {
                    // Contact
                    TransactionContactView(
                        transaction: transaction,
                        onNavigateToContact: onNavigateToContact
                    )
                    
                    // Tags
                    TransactionTagView(
                        transaction: transaction,
                        onNavigateToTag: onNavigateToTag
                    )
                    
                    // Note
                    TransactionNotesSection(transaction: transaction)
                }
                .padding(.horizontal)
                
                detailsView
                    .padding(.horizontal)
                
                // Exit details (for unilateral exit transactions)
                // Now includes linked onchain transactions
                TransactionExitDetailsView(transaction: transaction)
                    .padding(.horizontal)
                
                // Technical details (for testing/debugging)
                TransactionTechnicalDetailsView(transaction: transaction)
                    .padding(.horizontal)
            }
            .padding(.bottom)
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .bottom) {
            if viewModel.showCopySuccess {
                Text("status_copied_clipboard")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                    .cornerRadius(8)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var headerView: some View {
        VStack(spacing: 25) {
            // Transaction Icon and Type (or Contact Avatar if contact exists)
            Group {
                if let contact = transaction.associatedContacts.first {
                    // Show contact avatar
                    ContactAvatarView(
                        avatarData: contact.avatarData,
                        size: 75,
                        fallbackText: contact.displayName
                    )
                    .padding(.top, 120)
                } else {
                    // Show transaction icon
                    transactionIcon
                        .font(.system(size: 32))
                        //.foregroundColor(transaction.transactionType.iconColor)
                        .foregroundColor(.white)
                        .frame(width: 75, height: 75)
                        .background(transactionIconColor)
                        .cornerRadius(15)
                        .padding(.top, 120)
                }
            }
            
            VStack(alignment: .center, spacing: 0) {
                Text(transaction.shortDisplayText(includeStatusPrefix: true))
                    .font(.system(.title, design: .serif))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                // Amount (transferred amount for internal transfers, net amount for others)
                // Refreshes have no meaningful amount to display, so hide it.
                if transaction.category != .refresh {
                    Text(transaction.formattedDisplayAmount)
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundColor(amountTextColor == .black || amountTextColor == .primary ? .white : amountTextColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            
            VStack(alignment: .center, spacing: 5) {
                if transaction.isInternalTransfer {
                    Text(transaction.detailedDisplayText(includeStatusPrefix: true))
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                
                HStack(alignment: .center, spacing: 4) {
                    // Fee information (only show for sent/transfer)
                    if transaction.transactionType == .sent || transaction.transactionType == .transfer {
                        // For exits, use fees including linked onchain transactions
                        let feeText = transaction.formattedTotalFeesIncludingLinked(modelContext: modelContext) ?? BitcoinFormatter.shared.formatAmount(0)
                        let hasFees = transaction.totalFeesIncludingLinked(modelContext: modelContext) > 0
                        Text(hasFees ? "\(feeText) fee" : String(localized: "label_no_fee"))
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.75))
                        
                        Text("symbol_middot")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.75))
                    }
                    
                    Text(showAbsoluteDate ? transaction.formattedDateAbsolute : transaction.formattedDate)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.75))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showAbsoluteDate.toggle()
                        }
                }
                .frame(maxWidth: .infinity)
            }
            
            // Status Badge (only show if not confirmed)
            /*
            if transaction.transactionStatus != .confirmed {
                HStack {
                    Text(transaction.transactionStatus.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(transaction.transactionStatus.textColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(transaction.transactionStatus.backgroundColor)
                        .clipShape(Capsule())
                    
                    Spacer()
                }
                .padding(.vertical, 16)
            }
            */
        }
        .colorScheme(.dark)
        .padding(.horizontal)
        .padding(.bottom, 30)
        .background(alignment: .bottom) {
            Color(hex: "#1C1C1C")
            
            Image(backgroundPatternImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
                .opacity(0.15)
        }
    }
    
    // MARK: - Icon and Color Helpers
    
    /// Returns the appropriate icon Image view based on transaction category or type
    @ViewBuilder
    private var transactionIcon: some View {
        let iconName = transactionIconName
        
        // Check if it's a system symbol (contains dots or common SF Symbol patterns)
        // Asset names we use are: "wallet", "safe"
        // System symbols are: "arrow.up", "arrow.down", "repeat", "clock"
        if iconName.contains(".") || ["repeat", "clock"].contains(iconName) {
            Image(systemName: iconName)
        } else {
            Image(iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
    
    /// Returns the appropriate icon name based on transaction category or type
    private var transactionIconName: String {
        // For internal transfers, use category-specific icons
        if transaction.isInternalTransfer, let _ = transaction.category {
            /*
            // Special case: onchain_send with bark.offboard subsystem should use offboarding icon
            // TODO: This needs a more elegant solution
            if category == .onchainSend, transaction.subsystemName == "bark.offboard" {
                return MovementCategory.offboarding.icon
            }
            
            return category.icon
             */
            
            let imageName: String = {
                if let category = transaction.category {
                    // Special case: onchain_send with bark.offboard subsystem should use offboarding logic
                    if category == .onchainSend, transaction.subsystemName == "bark.offboard" {
                        return "safe"
                    }
                    
                    switch category {
                    case .boarding, .refresh:
                        return "wallet"
                    case .offboarding:
                        return "safe"
                    case .onchainTransaction:
                        // Onchain self-transfers use safe image
                        if transaction.subsystemKind == "self_transfer" {
                            return "safe"
                        }
                        return "wallet"
                    default:
                        return "wallet" // fallback
                    }
                }
                
                // Check for exit subsystem
                if transaction.subsystemName == "bark.exit" {
                    return "safe"
                }
                
                return "wallet" // fallback
            }()
            return imageName
        }
        
        // For other transactions, use type-based icons
        return transaction.transactionType.iconName
    }
    
    /// Returns the appropriate icon color based on transaction status
    private var transactionIconColor: Color {
        // Cancelled is terminal and wins over the exit-progress check below,
        // which would otherwise show a never-completing pending state.
        if transaction.transactionStatus == .cancelled {
            return .gray
        }

        // Special case for unilateral exits: only complete when claimed
        if transaction.subsystemName == "bark.exit" {
            if transaction.subsystemKind == "claimed" {
                // Exit is complete
                if transaction.isInternalTransfer {
                    return .gray
                }
                return transaction.transactionType.iconColor
            } else {
                // Exit is still pending (not yet claimed)
                return .Arke.blue
            }
        }
        
        switch transaction.transactionStatus {
        case .confirmed:
            // For confirmed transactions, use semantic colors
            if transaction.isInternalTransfer {
                return .gray
            }
            return transaction.transactionType.iconColor
            
        case .pending:
            return .Arke.blue

        case .failed:
            return .Arke.red

        case .cancelled:
            return .gray
        }
    }

    /// Returns the appropriate amount text color based on transaction status
    private var amountTextColor: Color {
        // Cancelled is terminal and wins over the exit-progress check below,
        // which would otherwise show a never-completing pending state.
        if transaction.transactionStatus == .cancelled {
            return .gray
        }

        // Special case for unilateral exits: only complete when claimed
        if transaction.subsystemName == "bark.exit" {
            if transaction.subsystemKind == "claimed" {
                // Exit is complete
                if transaction.isInternalTransfer {
                    return .primary
                }
                return transaction.transactionType.amountColor
            } else {
                // Exit is still pending (not yet claimed)
                return .Arke.blue
            }
        }
        
        switch transaction.transactionStatus {
        case .confirmed:
            // For confirmed transactions, use semantic colors
            if transaction.isInternalTransfer {
                return .primary
            }
            return transaction.transactionType.amountColor
            
        case .pending:
            return .Arke.blue

        case .failed:
            return .Arke.red

        case .cancelled:
            return .gray
        }
    }

    // MARK: - Helper Properties
    
    /// Determines the appropriate background pattern image based on transaction category
    private var backgroundPatternImageName: String {
        guard let category = transaction.category else {
            // Fallback to block pattern if no category
            return "block-pattern-gold"
        }
        
        switch category {
        case .boarding, .exit, .offboarding, .refresh:
            // Internal/Ark transactions
            return "circle-pattern-gold"
            
        case .onchainSend, .onchainTransaction:
            // Onchain transactions - use different patterns based on confirmation count
            if let confirmations = transaction.liveConfirmations {
                switch confirmations {
                case 0:
                    return "block-pattern-gold-0"
                case 1:
                    return "block-pattern-gold-1"
                case 2:
                    return "block-pattern-gold-2"
                case 3:
                    return "block-pattern-gold-3"
                case 4:
                    return "block-pattern-gold-4"
                case 5:
                    return "block-pattern-gold-5"
                default:
                    return "block-pattern-gold"
                }
            } else {
                return "block-pattern-gold"
            }
            
        case .lightningSend, .lightningReceive:
            // Lightning transactions
            return "lightning-pattern-gold"
            
        case .offchainTransfer, .unknown:
            // Fallback for unknown categories
            return "wave-pattern-gold"
        }
    }
    
    // MARK: - Exit Claim Helpers
    
    /// Load exit VTXOs data and exit status
    private func loadExitData() {
        guard transaction.subsystemName == "bark.exit" else {
            return
        }
        
        let inputIds = Set(transaction.inputVtxoIds)
        exitVtxos = walletManager.allUnilateralExits.filter { exit in
            inputIds.contains(exit.vtxoId)
        }
        
        // Fetch exit status for the first VTXO (they should all be part of the same exit)
        if let firstVtxo = exitVtxos.first {
            Task {
                do {
                    exitStatus = try await walletManager.getExitStatus(
                        vtxoId: firstVtxo.vtxoId,
                        includeHistory: true,
                        includeTransactions: true
                    )
                } catch {
                    print("Failed to fetch exit status: \(error)")
                }
            }
        }
    }
    
    // MARK: - Claimable Exit Banner
    
    @ViewBuilder
    private var claimableExitBanner: some View {
        if let exitStatus = exitStatus {
            TransactionClaimExitBanner(
                exitStatus: exitStatus,
                currentBlockHeight: walletManager.estimatedBlockHeight.map { UInt32($0) }
            )
        }
    }
    
    @ViewBuilder
    private var detailsView: some View {
        VStack(spacing: 16) {
            /*
            // Fee (show for sent and transfer transactions)
            if (transaction.transactionType == .sent || transaction.transactionType == .transfer) {
                // If both fee types exist, show them separately
                if transaction.hasBothFeeTypes {
                    /*
                    if let offchainFee = transaction.formattedFee {
                        DetailRow(
                            title: "Offchain Fee",
                            value: offchainFee
                        )
                    }
                    if let onchainFee = transaction.formattedOnchainFee {
                        Divider()
                        DetailRow(
                            title: "Onchain Fee",
                            value: onchainFee
                        )
                    }
                    */
                    // Show total
                    if let totalFee = transaction.formattedTotalFees {
                        Divider()
                        DetailRow(
                            title: "Fee",
                            value: totalFee
                        )
                    }
                } else {
                    // Show single fee line
                    DetailRow(
                        title: "Fee",
                        value: transaction.formattedTotalFees ?? BitcoinFormatter.shared.formatAmount(0)
                    )
                }
            }
            */
            
            // Address (hide for lightning payments and received offchain transfers)
            if let address = transaction.address {
                // Don't show address for lightning payments (invoices aren't useful to users)
                let isLightning = transaction.category?.isLightning ?? false
                
                // Don't show address for received offchain transfers (users would just see their own address)
                let isReceivedOffchainTransfer = transaction.category == .offchainTransfer && transaction.transactionType == .received
                
                if !isLightning && !isReceivedOffchainTransfer {
                    // Extract the actual address value if it's a PaymentMethod JSON object
                    let addressValue: String = {
                        if let data = address.data(using: .utf8),
                           let paymentMethod = try? JSONDecoder().decode(PaymentMethod.self, from: data) {
                            return paymentMethod.value
                        } else {
                            // Fallback to the raw string if it's not a PaymentMethod object
                            return address
                        }
                    }()
                    
                    /*
                    DetailRow(
                        title: transaction.transactionType == .received ? "From Address" : "To Address",
                        value: addressValue,
                        isCopyable: true,
                        onCopy: { viewModel?.copyToClipboard($0) }
                    )
                    
                    Divider()
                    */
                    
                    VStack(alignment: .leading, spacing: 4) {
                        /*
                        Text(transaction.transactionType == .received ? LocalizedStringKey("activity_from_address") : LocalizedStringKey("activity_to_address"))
                            .font(.body)
                            .foregroundColor(.secondary)
                        */
                        
                        AddressCardExpandable(
                            address: addressValue,
                            shareContent: addressValue,
                            label: transaction.transactionType == .received ? String(localized: "activity_from_address") : String(localized: "activity_to_address")
                        )
                    }
                }
            }
            
            /*
            // Explainer text for non-intuitive transaction types
            if let explainerText = transaction.explainerText {
                Text(explainerText)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
             */
            
            /*
            // Transaction ID
            Divider()
            DetailRow(
                title: "Transaction ID",
                value: transaction.txid,
                isCopyable: true,
                onCopy: { viewModel?.copyToClipboard($0) }
            )
            */
        }
        .padding(.vertical, 4)
    }
}
