//
//  ExitStatusDetailView_iOS.swift
//  Arké
//
//  Created by Christoph on 1/8/26.
//

import SwiftUI
import Bark
import ArkeUI
import os

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "ExitStatusDetailView")

struct ExitStatusDetailView_iOS: View {
    @Environment(WalletManager.self) private var walletManager
    
    let exitVtxo: ExitVtxo
    
    @State private var status: ExitTransactionStatus?
    @State private var isLoading = true
    @State private var error: String?
    
    var body: some View {
        List {
                Section(String(localized: "label_basic_info")) {
                    LabeledContent("VTXO ID") {
                        Text(exitVtxo.vtxoId)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    
                    LabeledContent("Amount", value: "\(exitVtxo.amountSats) sats")
                    
                    /*
                    LabeledContent("State") {
                        HStack {
                            Circle()
                                .fill(exitVtxo.isClaimable ? Color.Arke.green : Color.Arke.orange)
                                .frame(width: 8, height: 8)
                            Text(exitVtxo.state)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    */
                    
                    LabeledContent(String(localized: "balance_is_claimable")) {
                        HStack {
                            Image(systemName: exitVtxo.isClaimable ? "checkmark.circle.fill" : "clock")
                                .foregroundStyle(exitVtxo.isClaimable ? Color.Arke.green : Color.Arke.orange)
                            Text(exitVtxo.isClaimable ? String(localized: "button_yes") : String(localized: "button_no"))
                        }
                    }
                }
                
                if isLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text(String(localized: "status_loading_status"))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let error = error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.Arke.red)
                    }
                } else if let status = status {
                    // Parsed state information
                    if let parsed = status.parsedState {
                        ParsedStateSection(parsed: parsed)
                    }
                    
                    // Transaction chain
                    if !status.transactionChain.isEmpty {
                        TransactionChainSection(transactions: status.transactionChain)
                    }
                    
                    // All extracted transaction IDs
                    if !status.allTransactionIds.isEmpty {
                        TransactionIdsSection(txids: status.allTransactionIds)
                    }
                    
                    // Confirmed transactions
                    if !status.confirmedTransactions.isEmpty {
                        ConfirmedTransactionsSection(confirmed: status.confirmedTransactions)
                    }
                    
                    // Raw state (for debugging)
                    Section("Raw State") {
                        LabeledContent("Current State") {
                            Text(status.state)
                                .font(.system(.caption, design: .monospaced))
                        }
                        
                        LabeledContent(String(localized: "activity_transaction_count"), value: "\(status.transactionCount)")
                    }
                    
                    // State history
                    if let history = status.history, !history.isEmpty {
                        Section(String(localized: "data_state_history")) {
                            ForEach(Array(history.enumerated()), id: \.offset) { index, state in
                                StateHistoryRow(index: index, state: state)
                            }
                        }
                    }
                }
            }
            .navigationTitle("balance_exit_status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Refresh the detailed exit status
                    Button {
                        Task {
                            await loadStatus()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadStatus()
            }
    }
    
    private func loadStatus() async {
        isLoading = true
        error = nil
        
        do {
            // Sync wallet and exit state before checking status
            print("🔄 Syncing wallet state...")
            try await walletManager.sync()
            print("✅ Wallet synced")
            
            print("🔄 Syncing exit state...")
            try await walletManager.syncExits()
            print("✅ Exit state synced")
            
            // Now get the detailed exit status
            status = try await walletManager.getExitStatus(
                vtxoId: exitVtxo.vtxoId,
                includeHistory: true,
                includeTransactions: true
            )
            
            if let status = status {
                print("✅ Loaded exit status for \(exitVtxo.vtxoId)")
                print("🔍 DEBUG: Full status object: \(status)")
                print("   State: \(status.state)")
                print("   Transaction count: \(status.transactionCount)")
                if let history = status.history {
                    print("   History: \(history.joined(separator: " → "))")
                }
            } else {
                error = "No detailed status available"
                print("⚠️ No status returned for \(exitVtxo.vtxoId)")
            }
        } catch {
            self.error = "Failed to load status: \(error.localizedDescription)"
            print("❌ Failed to load exit status: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - Supporting Views

private struct ParsedStateSection: View {
    let parsed: ParsedExitState
    
    var body: some View {
        Section("Parsed State") {
            switch parsed {
            case .start(let data):
                LabeledContent("Type", value: "Start")
                LabeledContent("Tip Height", value: "\(data.tipHeight)")
                
            case .processing(let data):
                LabeledContent("Type", value: "Processing")
                LabeledContent("Tip Height", value: "\(data.tipHeight)")
                LabeledContent("Transactions", value: "\(data.transactions.count)")
                
            case .awaitingDelta(let data):
                LabeledContent("Type", value: "Awaiting Delta")
                LabeledContent("Tip Height", value: "\(data.tipHeight)")
                LabeledContent("Confirmed Block", value: "\(data.confirmedBlock.height)")
                LabeledContent("Claimable Height", value: "\(data.claimableHeight)")
                
            case .claimable(let data):
                LabeledContent("Type", value: "Claimable")
                LabeledContent("Tip Height", value: "\(data.tipHeight)")
                LabeledContent("Claimable Since", value: "\(data.claimableSince.height)")
                
            case .claimInProgress(let data):
                LabeledContent("Type", value: "Claim In Progress")
                LabeledContent("Tip Height", value: "\(data.tipHeight)")
                LabeledContent("Claim TX") {
                    Text(data.claimTxid.prefix(8) + "..." + data.claimTxid.suffix(8))
                        .font(.system(.caption, design: .monospaced))
                }
                
            case .claimed(let data):
                LabeledContent("Type", value: "Claimed")
                LabeledContent("Tip Height", value: "\(data.tipHeight)")
                LabeledContent("Claim TX") {
                    Text(data.txid.prefix(8) + "..." + data.txid.suffix(8))
                        .font(.system(.caption, design: .monospaced))
                }
                LabeledContent("Block", value: "\(data.block.height)")
                
            case .unparsed(let str):
                LabeledContent("Type", value: "Unparsed")
                Text(str)
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }
}

private struct TransactionChainSection: View {
    let transactions: [ExitTransaction]
    
    var body: some View {
        let _ = logger.info("🎨 Rendering TransactionChainSection with \(transactions.count) transactions")
        
        Section("Transaction Chain") {
            ForEach(Array(transactions.enumerated()), id: \.offset) { index, tx in
                let _ = logger.debug("   Transaction #\(index + 1): \(tx.txid.prefix(16))... status: \(String(describing: tx.status))")
                let childTxid = extractChildTxid(from: tx.status)
                let _ = childTxid.map { logger.info("      ✅ Has child_txid: \($0.prefix(16))...") }
                    ?? logger.debug("      ℹ️ No child_txid for this transaction")
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("#\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tx.txid.prefix(8) + "..." + tx.txid.suffix(8))
                                .font(.system(.caption, design: .monospaced))
                            
                            TransactionStatusLabel(status: tx.status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            // Display child_txid if present in status
                            if let childTxid = childTxid {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text("Child: " + childTxid.prefix(8) + "..." + childTxid.suffix(8))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Extract child_txid from status if present
    private func extractChildTxid(from status: ExitTxStatus) -> String? {
        switch status {
        case .needsBroadcasting(let data):
            return data.childTxid
        case .broadcastWithCpfp(let data):
            return data.childTxid
        case .confirmed(let data):
            return data.childTxid
        default:
            return nil
        }
    }
}

private struct TransactionIdsSection: View {
    let txids: [String]
    
    var body: some View {
        Section("All Transaction IDs (\(txids.count))") {
            ForEach(txids, id: \.self) { txid in
                Text(txid.prefix(8) + "..." + txid.suffix(8))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }
}

private struct ConfirmedTransactionsSection: View {
    let confirmed: [(txid: String, block: ArkeBlockRef)]
    
    var body: some View {
        Section("Confirmed Transactions") {
            ForEach(confirmed, id: \.txid) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.Arke.green)
                            .font(.caption)
                        
                        Text(item.txid.prefix(8) + "..." + item.txid.suffix(8))
                            .font(.system(.caption, design: .monospaced))
                    }
                    
                    Text("Block \(item.block.height)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ParsedStateLabel: View {
    let parsed: ParsedExitState
    
    var body: some View {
        switch parsed {
        case .start:
            Label("Start", systemImage: "flag")
        case .processing:
            Label("Processing", systemImage: "gearshape")
        case .awaitingDelta:
            Label("Awaiting Delta", systemImage: "clock")
        case .claimable:
            Label("Claimable", systemImage: "checkmark.circle")
        case .claimInProgress:
            Label("Claim In Progress", systemImage: "arrow.down.circle")
        case .claimed:
            Label("Claimed", systemImage: "checkmark.circle.fill")
        case .unparsed:
            Label("Unknown", systemImage: "questionmark.circle")
        }
    }
}

private struct TransactionStatusLabel: View {
    let status: ExitTxStatus
    
    var body: some View {
        switch status {
        case .verifyInputs:
            Text("Verify Inputs")
        case .needsSignedPackage:
            Text("Needs Signed Package")
        case .needsBroadcasting:
            Text("Needs Broadcasting")
        case .broadcastWithCpfp:
            Text("Broadcast with CPFP")
        case .awaitingInputConfirmation:
            Text("Awaiting Input Confirmation")
        case .confirmed:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.Arke.green)
                Text("Confirmed")
            }
        case .unparsed:
            Text("Unknown Status")
        }
    }
}

private struct StateHistoryRow: View {
    let index: Int
    let state: String
    
    @State private var isExpanded = false
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                // Full raw state
                Text(state)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
                
                // Detailed parsed state info if available
                if let parsed = ExitStatusParser.parseState(state) {
                    Divider()
                    ParsedStateDetails(parsed: parsed)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Text("#\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .leading)
                
                if let parsed = ExitStatusParser.parseState(state) {
                    ParsedStateLabel(parsed: parsed)
                } else {
                    Text(state)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct ParsedStateDetails: View {
    let parsed: ParsedExitState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch parsed {
            case .start(let data):
                StateDetailRow(label: "Type", value: "Start")
                StateDetailRow(label: "Tip Height", value: "\(data.tipHeight)")
                
            case .processing(let data):
                StateDetailRow(label: "Type", value: "Processing")
                StateDetailRow(label: "Tip Height", value: "\(data.tipHeight)")
                StateDetailRow(label: "Transactions", value: "\(data.transactions.count)")
                
                if !data.transactions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transaction IDs:")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        
                        ForEach(Array(data.transactions.enumerated()), id: \.offset) { _, tx in
                            Text(tx.txid.prefix(8) + "..." + tx.txid.suffix(8))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                
            case .awaitingDelta(let data):
                StateDetailRow(label: "Type", value: "Awaiting Delta")
                StateDetailRow(label: "Tip Height", value: "\(data.tipHeight)")
                StateDetailRow(label: "Confirmed Block", value: "\(data.confirmedBlock.height)")
                StateDetailRow(label: "Claimable Height", value: "\(data.claimableHeight)")
                
            case .claimable(let data):
                StateDetailRow(label: "Type", value: "Claimable")
                StateDetailRow(label: "Tip Height", value: "\(data.tipHeight)")
                StateDetailRow(label: "Claimable Since", value: "\(data.claimableSince.height)")
                
            case .claimInProgress(let data):
                StateDetailRow(label: "Type", value: "Claim In Progress")
                StateDetailRow(label: "Tip Height", value: "\(data.tipHeight)")
                StateDetailRow(label: "Claim TX", value: data.claimTxid.prefix(8) + "..." + data.claimTxid.suffix(8))
                
            case .claimed(let data):
                StateDetailRow(label: "Type", value: "Claimed")
                StateDetailRow(label: "Tip Height", value: "\(data.tipHeight)")
                StateDetailRow(label: "Claim TX", value: data.txid.prefix(8) + "..." + data.txid.suffix(8))
                StateDetailRow(label: "Block", value: "\(data.block.height)")
                
            case .unparsed(let str):
                StateDetailRow(label: "Type", value: "Unparsed")
                Text(str)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
    }
}

private struct StateDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption2, design: .monospaced))
        }
    }
}
