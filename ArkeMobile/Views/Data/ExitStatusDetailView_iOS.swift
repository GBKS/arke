//
//  ExitStatusDetailView_iOS.swift
//  Arké
//
//  Created by Christoph on 1/8/26.
//

import SwiftUI
import SwiftData
import UIKit
import Bark
import ArkeUI
import os

fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "ExitStatusDetailView")

/// Full status of a unilateral exit, organized as the same step timeline the
/// exit banner shows as a segmented bar (via the shared ExitProgress model):
/// prepare, one step per exit transaction, unlock wait, claim, complete.
struct ExitStatusDetailView_iOS: View {
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.modelContext) private var modelContext

    /// Keyed by vtxoId so completed exits (no longer in the exit list)
    /// can still show their full status and history.
    let vtxoId: String
    var exitVtxo: ExitVtxo? = nil

    @State private var status: ExitTransactionStatus?
    @State private var isLoading = true
    @State private var error: String?

    /// Onchain wallet records for the exit's transactions, keyed by the exit
    /// txid of each step. The onchain wallet usually knows the CPFP child
    /// (it pays the fee), so lookup tries the child txid first.
    @State private var linkedTransactions: [String: TransactionModel] = [:]

    private var currentBlockHeight: UInt32? {
        walletManager.estimatedBlockHeight.map { UInt32($0) }
    }

    var body: some View {
        List {
            if let status {
                let progress = ExitProgress(status: status)

                Section {
                    ExitProgressHeaderView(
                        progress: progress,
                        exitVtxo: exitVtxo,
                        totalFeesPaid: totalFeesPaid
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            .listRowBackground(Color.clear)

                if progress.isCancelled {
                    Section {
                        Label("exit_cancelled_explanation", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Step \(progress.currentStep) of \(progress.totalSteps)") {
                        ForEach(progress.steps) { step in
                            ExitStepRow(
                                step: step,
                                tint: progress.tint,
                                blocksUntilUnlock: progress.blocksUntilUnlock(currentHeight: currentBlockHeight),
                                blockedInfo: walletManager.getExitBlockedInfo(for: vtxoId),
                                linkedTransaction: linkedTransaction(for: step)
                            )
                        }
                    }
                }

                if let history = status.history, !history.isEmpty {
                    Section(String(localized: "data_state_history")) {
                        ForEach(Array(history.enumerated()), id: \.offset) { index, state in
                            StateHistoryRow(index: index, state: state)
                        }
                    }
                }

                TechnicalDetailsSection(vtxoId: vtxoId, status: status)
            } else if isLoading {
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
            }
        }
        .navigationTitle("balance_exit_status")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Refresh the detailed exit status
                Button {
                    Task {
                        await loadStatus(fullSync: true)
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

    private func loadStatus(fullSync: Bool = false) async {
        isLoading = true
        error = nil

        do {
            // Full sync is expensive, so only do it on explicit refresh;
            // the initial load just reads the current exit status
            if fullSync {
                print("🔄 Syncing wallet state...")
                try await walletManager.sync()
                print("✅ Wallet synced")

                print("🔄 Syncing exit state...")
                try await walletManager.syncExits()
                print("✅ Exit state synced")
            }

            // Now get the detailed exit status
            status = try await walletManager.getExitStatus(
                vtxoId: vtxoId,
                includeHistory: true,
                includeTransactions: true
            )

            if let status = status {
                print("✅ Loaded exit status for \(vtxoId)")
                print("   State: \(status.state)")
                print("   Transaction count: \(status.transactionCount)")
                if let history = status.history {
                    print("   History: \(history.joined(separator: " → "))")
                }
                loadLinkedTransactions(for: status)
            } else {
                error = "No detailed status available"
                print("⚠️ No status returned for \(vtxoId)")
            }
        } catch {
            self.error = "Failed to load status: \(error.localizedDescription)"
            print("❌ Failed to load exit status: \(error)")
        }

        isLoading = false
    }

    /// Sum of the onchain fees the wallet knows about across the exit's
    /// transactions, deduplicated by txid (the claim and complete steps
    /// share the same onchain record).
    private var totalFeesPaid: Int {
        var seenTxids = Set<String>()
        var total = 0
        for model in linkedTransactions.values {
            guard seenTxids.insert(model.txid).inserted else { continue }
            total += model.onchainFeeSat ?? 0
        }
        return total
    }

    private func linkedTransaction(for step: ExitProgress.Step) -> TransactionModel? {
        switch step.kind {
        case .confirmTransaction(_, _, let transaction):
            guard let transaction else { return nil }
            return linkedTransactions[transaction.txid]
        case .claim(let claimTxid):
            guard let claimTxid else { return nil }
            return linkedTransactions[claimTxid]
        case .complete(let txid, _):
            guard let txid else { return nil }
            return linkedTransactions[txid]
        case .prepare, .waitForUnlock:
            return nil
        }
    }

    /// Match the exit's transactions against the onchain wallet's records so
    /// the steps can show confirmations, amount and fee. The CPFP child is
    /// what the onchain wallet actually tracks (it pays the fee), so it takes
    /// precedence over the exit txid itself.
    private func loadLinkedTransactions(for status: ExitTransactionStatus) {
        let progress = ExitProgress(status: status)
        var linked: [String: TransactionModel] = [:]

        for transaction in progress.steps.compactMap(transactionInStep) {
            let candidates = [childTxid(of: transaction.status), transaction.txid].compactMap { $0 }
            for candidate in candidates {
                if let model = fetchTransactionModel(txid: candidate) {
                    linked[transaction.txid] = model
                    break
                }
            }
        }

        // The claim transaction pays back into the onchain wallet, so it
        // usually has a record of its own (also keys the complete step)
        for step in progress.steps {
            if case .claim(let claimTxid?) = step.kind, linked[claimTxid] == nil,
               let model = fetchTransactionModel(txid: claimTxid) {
                linked[claimTxid] = model
            }
        }

        linkedTransactions = linked
        print("🔗 [Exit Status] Matched \(linked.count) onchain transactions for \(vtxoId)")
    }

    private func transactionInStep(_ step: ExitProgress.Step) -> ExitTransaction? {
        guard case .confirmTransaction(_, _, let transaction) = step.kind else { return nil }
        return transaction
    }

    private func fetchTransactionModel(txid: String) -> TransactionModel? {
        // Onchain wallet records are stored with a namespaced txid
        // ("onchain_<txid>") to avoid collisions with ark txids
        let onchainTxid = "onchain_\(txid)"
        let descriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { $0.txid == txid || $0.txid == onchainTxid }
        )
        guard let persistentTx = try? modelContext.fetch(descriptor).first else { return nil }
        return TransactionModel(from: persistentTx)
    }
}

/// Extract the CPFP child txid from a transaction status, if present.
private func childTxid(of status: ExitTxStatus) -> String? {
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

// MARK: - Sheet Wrapper

/// Slide-up presentation of the exit status detail, shared by the
/// transaction detail view (Activity) and the X-Ray exit list.
struct ExitStatusSheet: View {
    let vtxoId: String
    var exitVtxo: ExitVtxo? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExitStatusDetailView_iOS(vtxoId: vtxoId, exitVtxo: exitVtxo)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("button_done") {
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Header

/// Key figures of the exit as label/value rows: the amount being exited and
/// the onchain fees paid so far ("Network Fees" once the exit is complete).
private struct ExitProgressHeaderView: View {
    let progress: ExitProgress
    let exitVtxo: ExitVtxo?
    /// Sum of onchain fees across the exit's linked wallet transactions.
    let totalFeesPaid: Int

    var body: some View {
        Group {
            if let exitVtxo {
                HeaderRow(labelKey: "label_amount", value: BitcoinFormatter.shared.formatAmount(Int(exitVtxo.amountSats)))
            }

            if progress.isCancelled {
                Label("data_vtxo_already_spent", systemImage: "xmark.circle")
                    .foregroundStyle(.secondary)
            } else if totalFeesPaid > 0 {
                if progress.phase == .complete {
                    HeaderRow(labelKey: "exit_fees_total", value: BitcoinFormatter.shared.formatAmount(totalFeesPaid))
                } else {
                    HeaderRow(labelKey: "exit_fees_so_far", value: BitcoinFormatter.shared.formatAmount(totalFeesPaid))
                }
            }
        }
    }
}

private struct HeaderRow: View {
    let labelKey: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(labelKey)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}

// MARK: - Step Rows

/// One step of the exit timeline. Expandable when the step carries details
/// (txids, blocks); the current step starts expanded.
private struct ExitStepRow: View {
    let step: ExitProgress.Step
    let tint: Color
    let blocksUntilUnlock: Int?
    let blockedInfo: ExitBlockedInfo?
    /// Onchain wallet record for this step's transaction, when it has one.
    let linkedTransaction: TransactionModel?

    @State private var isExpanded: Bool

    init(
        step: ExitProgress.Step,
        tint: Color,
        blocksUntilUnlock: Int?,
        blockedInfo: ExitBlockedInfo?,
        linkedTransaction: TransactionModel? = nil
    ) {
        self.step = step
        self.tint = tint
        self.blocksUntilUnlock = blocksUntilUnlock
        self.blockedInfo = blockedInfo
        self.linkedTransaction = linkedTransaction
        _isExpanded = State(initialValue: step.state == .current)
    }

    var body: some View {
        if hasDetails {
            DisclosureGroup(isExpanded: $isExpanded) {
                details
                    .padding(.top, 4)
            } label: {
                label
            }
        } else {
            label
        }
    }

    private var label: some View {
        HStack(alignment: .center, spacing: 10) {
            stepNumberBadge

            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.body)
                    .foregroundStyle(step.state == .upcoming ? .secondary : .primary)

                if step.state == .current {
                    if let blockedInfo {
                        Label {
                            Text(ExitProgress.blockedExplanationKey(for: blockedInfo.reason))
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .font(.caption)
                        .foregroundStyle(Color.Arke.orange)
                    } else if let statusText {
                        statusText
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let doneSubtitle {
                    doneSubtitle
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Step number in a filled circle; the fill carries the state color the
    /// icon used to (green done, tint current, tertiary upcoming).
    private var stepNumberBadge: some View {
        Text("\(step.id)")
            .font(.body.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(step.state == .upcoming ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
            .frame(width: 36, height: 36)
            .background(badgeBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private var badgeBackground: AnyShapeStyle {
        switch step.state {
        case .done:
            AnyShapeStyle(Color.Arke.green)
        case .current:
            AnyShapeStyle(tint)
        case .upcoming:
            AnyShapeStyle(.tertiary)
        }
    }

    private var title: Text {
        switch step.kind {
        case .prepare:
            return Text("exit_step_prepare")
        case .confirmTransaction(let index, let total, _):
            if total > 1 {
                return Text("exit_step_confirm_transaction \(index)")
            } else {
                return Text("exit_step_confirm_transaction_single")
            }
        case .waitForUnlock:
            return Text("exit_step_wait_unlock")
        case .claim:
            return Text("exit_step_claim")
        case .complete:
            return Text("exit_step_complete")
        }
    }

    /// One-line status under a finished step's title. Transaction steps show
    /// their final status ("Confirmed"), so the collapsed list reads as a
    /// timeline; other steps stay quiet once done.
    private var doneSubtitle: Text? {
        guard step.state == .done, case .confirmTransaction = step.kind else { return nil }
        return statusText
    }

    /// One-line status under the current step's title.
    private var statusText: Text? {
        switch step.kind {
        case .prepare:
            return Text("exit_step_prepare_status")
        case .confirmTransaction(_, _, let transaction):
            guard let transaction else { return nil }
            return transactionStatusText(transaction.status)
        case .waitForUnlock:
            if let blocksUntilUnlock, blocksUntilUnlock > 0 {
                return Text("exit_step_wait_blocks \(blocksUntilUnlock)")
            }
            return Text("status_exit_finalizing")
        case .claim:
            return Text("exit_step_claim_status")
        case .complete:
            return nil
        }
    }

    private var hasDetails: Bool {
        switch step.kind {
        case .prepare:
            return false
        case .confirmTransaction(_, _, let transaction):
            return transaction != nil
        case .waitForUnlock(let confirmedBlock, let claimableHeight):
            return confirmedBlock != nil || claimableHeight != nil
        case .claim(let claimTxid):
            return claimTxid != nil
        case .complete(let txid, _):
            return txid != nil
        }
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch step.kind {
            case .prepare:
                EmptyView()

            case .confirmTransaction(_, _, let transaction):
                if let transaction {
                    LabeledTxidRow(labelKey: "activity_transaction_id", txid: transaction.txid)
                    StepDetailTextRow(labelKey: "label_status", value: transactionStatusText(transaction.status))

                    if case .confirmed(let data) = transaction.status {
                        StepDetailRow(labelKey: "data_confirmed_block", value: "\(data.block.height)")
                    }

                    // Onchain wallet view of this transaction: confirmations,
                    // date, amount and the fee actually paid
                    if let linkedTransaction {
                        ExitOnchainInfoRows(transaction: linkedTransaction)
                    }
                }

            case .waitForUnlock(let confirmedBlock, let claimableHeight):
                if let confirmedBlock {
                    StepDetailRow(labelKey: "data_confirmed_block", value: "\(confirmedBlock.height)")
                }
                if let claimableHeight {
                    StepDetailRow(labelKey: "data_claimable_height", value: "\(claimableHeight)")
                }
                if let blocksUntilUnlock, blocksUntilUnlock > 0 {
                    Text("exit_step_wait_blocks \(blocksUntilUnlock)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .claim(let claimTxid):
                if let claimTxid {
                    LabeledTxidRow(labelKey: "data_claim_tx", txid: claimTxid)

                    // While the claim is in flight, its onchain record shows
                    // live confirmations; once done, the complete step owns it
                    if step.state == .current, let linkedTransaction {
                        ExitOnchainInfoRows(transaction: linkedTransaction)
                    } else if let fee = linkedTransaction?.onchainFeeSat, fee > 0 {
                        StepDetailRow(labelKey: "activity_network_fee", value: BitcoinFormatter.shared.formatAmount(fee))
                    }
                }

            case .complete(let txid, let block):
                if let txid {
                    LabeledTxidRow(labelKey: "data_claim_tx", txid: txid)
                }
                if let block {
                    StepDetailRow(labelKey: "data_block", value: "\(block.height)")
                }
                if let linkedTransaction {
                    ExitOnchainInfoRows(transaction: linkedTransaction)
                }
            }
        }
    }

    /// Plain-language version of bark's transaction status; the raw case
    /// names stay visible in Technical Details and the state history.
    private func transactionStatusText(_ status: ExitTxStatus) -> Text {
        switch status {
        case .verifyInputs, .needsSignedPackage, .needsBroadcasting:
            return Text("exit_tx_status_preparing")
        case .broadcastWithCpfp:
            return Text("exit_tx_status_broadcast")
        case .awaitingInputConfirmation:
            return Text("exit_tx_status_awaiting_parent")
        case .confirmed:
            return Text("status_confirmed")
        case .unparsed:
            return Text("data_unknown_status")
        }
    }
}

private struct CopyableTxidRow: View {
    let txid: String

    var body: some View {
        Text(txid.prefix(5) + "..." + txid.suffix(5))
            .font(.system(.subheadline, design: .monospaced))
            .contextMenu {
                Button {
                    UIPasteboard.general.string = txid
                } label: {
                    Label("data_copy_transaction_id", systemImage: "doc.on.doc")
                }
            }
    }
}

private struct LabeledTxidRow: View {
    let labelKey: LocalizedStringKey
    let txid: String

    var body: some View {
        HStack {
            Text(labelKey)
                .foregroundStyle(.secondary)
            Spacer()
            CopyableTxidRow(txid: txid)
        }
        .font(.subheadline)
    }
}

/// Like StepDetailRow, but for localized (non-monospaced) values.
private struct StepDetailTextRow: View {
    let labelKey: LocalizedStringKey
    let value: Text

    var body: some View {
        HStack {
            Text(labelKey)
                .foregroundStyle(.secondary)
            Spacer()
            value
        }
        .font(.subheadline)
    }
}

private struct StepDetailRow: View {
    let labelKey: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(labelKey)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
        }
        .font(.subheadline)
    }
}

// MARK: - Technical Details

/// Raw data kept for debugging (X-Ray): identifiers, raw state string and
/// every txid the parser extracted.
private struct TechnicalDetailsSection: View {
    let vtxoId: String
    let status: ExitTransactionStatus

    var body: some View {
        Section("data_technical_details") {
            LabeledContent("label_vtxo_id") {
                Text(vtxoId)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            LabeledContent("data_current_state") {
                Text(status.state)
                    .font(.system(.caption, design: .monospaced))
            }

            LabeledContent(String(localized: "activity_transaction_count"), value: "\(status.transactionCount)")

            let txids = status.allTransactionIds
            if !txids.isEmpty {
                DisclosureGroup {
                    ForEach(txids, id: \.self) { txid in
                        CopyableTxidRow(txid: txid)
                    }
                } label: {
                    HStack {
                        Text("data_transaction_ids")
                        Spacer()
                        Text("\(txids.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - State History

private struct ParsedStateLabel: View {
    let parsed: ParsedExitState

    var body: some View {
        switch parsed {
        case .start:
            Label("button_start", systemImage: "flag")
        case .processing:
            Label("data_processing", systemImage: "gearshape")
        case .awaitingDelta:
            Label("data_awaiting_delta", systemImage: "clock")
        case .claimable:
            Label("data_claimable", systemImage: "checkmark.circle")
        case .claimInProgress:
            Label("data_claim_in_progress", systemImage: "arrow.down.circle")
        case .claimed:
            Label("data_claimed", systemImage: "checkmark.circle.fill")
        case .vtxoAlreadySpent:
            Label("data_vtxo_already_spent", systemImage: "xmark.circle")
        case .unparsed:
            Label("data_unknown", systemImage: "questionmark.circle")
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
                        Text("data_transaction_ids")
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

            case .vtxoAlreadySpent(let data):
                StateDetailRow(label: "Type", value: "VTXO Already Spent")
                StateDetailRow(label: "Tip Height", value: "\(data.tipHeight)")

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
