//
//  UnilateralExitListView_iOS.swift
//  Arké
//
//  Created by Christoph on 1/7/26.
//

import SwiftUI
import SwiftData
import ArkeUI
import Bark

struct UnilateralExitListView_iOS: View {
    var reloadTrigger: Int = 0
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.modelContext) private var modelContext
    @State private var selectedExit: ExitVtxo?
    @State private var exits: [ExitVtxo] = []
    @State private var completedExits: [PersistentExitCache] = []
    @State private var selectedCompletedExit: PersistentExitCache?
    @State private var isLoadingExits = false
    @State private var error: String?
    @State private var latestBlockHeight: Int?
    @State private var updateTimer: Timer?
    
    // State
    @State private var isProcessing = false
    @State private var claimableHeight: UInt32?
    @State private var hasPendingExits: Bool?
    @State private var pendingExitsTotal: UInt64?
    
    private var totalExitAmount: UInt64 {
        activeExits.reduce(into: 0) { $0 += $1.amountSats }
    }

    private var formattedTotalAmount: String {
        BitcoinFormatter.shared.formatAmount(Int(totalExitAmount))
    }

    private var activeExits: [ExitVtxo] {
        // Claimed exits get purged from bark's list, but cancelled ones
        // (VtxoAlreadySpent) linger there — don't count those as active
        exits.filter { $0.isInFlight }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("balance_exiting_vtxos")
                        .font(.system(size: 24, design: .serif))
                    
                    if !exits.isEmpty {
                        Text("data_exit_count_summary \(activeExits.count) \(formattedTotalAmount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            Divider()
                .padding(.top, 12)
                .padding(.horizontal)
            
            // Status Indicators Section
            if claimableHeight != nil {
                statusIndicatorsSection
            }
            
            // Exit List
            if isLoadingExits {
                SkeletonLoader(
                    itemCount: 2,
                    itemHeight: 50,
                    spacing: 15,
                    cornerRadius: 15
                )
                .padding(.top, 10)
                .padding(.horizontal)
            } else if let error = error {
                ErrorBox(errorMessage: error)
                    .padding(.horizontal)
            } else if exits.isEmpty && completedExits.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                    Text("balance_no_exits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .padding(.horizontal)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(exits.enumerated()), id: \.element.vtxoId) { index, exit in
                        Button {
                            selectedExit = exit
                        } label: {
                            ExitVtxoRowView_iOS(
                                exit: exit,
                                isSelected: false,
                                latestBlockHeight: latestBlockHeight
                            )
                        }
                        .buttonStyle(.plain)

                        if index < exits.count - 1 {
                            Divider()
                                .padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.horizontal)

                completedExitsSection
            }
        }
        .sheet(item: $selectedExit) { exit in
            ExitStatusSheet(vtxoId: exit.vtxoId, exitVtxo: exit)
        }
        .sheet(item: $selectedCompletedExit) { entry in
            ExitStatusSheet(vtxoId: entry.vtxoId)
        }
        .task(id: reloadTrigger) {
            await loadExits()
            await syncAndProgressExits()
        }
        .onAppear {
            startBlockHeightUpdater()
        }
        .onDisappear {
            stopBlockHeightUpdater()
        }
    }
    
    // MARK: - Status Indicators Section
    
    @ViewBuilder
    private var statusIndicatorsSection: some View {
        if let height = claimableHeight {
            HStack {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundStyle(Color.Arke.green)
                Text(String(localized: "balance_claimable_at_block", defaultValue: "All claimable at block \(height)"))
                if let current = latestBlockHeight {
                    let remaining = Int(height) - current
                    Text("data_blocks_remaining \(remaining)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Completed Exits Section

    /// Exits bark no longer tracks, rendered from the app's persisted
    /// snapshots — the detail sheet works for these because getExitStatus
    /// falls back to the same snapshots
    @ViewBuilder
    private var completedExitsSection: some View {
        if !completedExits.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("data_completed_exits")
                    .font(.headline)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                ForEach(Array(completedExits.enumerated()), id: \.element.vtxoId) { index, entry in
                    Button {
                        selectedCompletedExit = entry
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(entry.vtxoId.prefix(8))...\(entry.vtxoId.suffix(8))")
                                    .font(.system(.body, design: .monospaced))
                                Text(entry.stateDisplayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text(BitcoinFormatter.shared.formatAmount(Int(entry.amountSats)))
                                Text(entry.lastRefreshedAt, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < completedExits.count - 1 {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    /// Load persisted exit records that are no longer in bark's exit list
    /// (bark purges claimed exits; these entries are the surviving history)
    private func loadCompletedExits() {
        let liveVtxoIds = Set(exits.map { $0.vtxoId })
        let descriptor = FetchDescriptor<PersistentExitCache>(
            sortBy: [SortDescriptor(\.lastRefreshedAt, order: .reverse)]
        )
        let allEntries = (try? modelContext.fetch(descriptor)) ?? []
        completedExits = allEntries.filter { !liveVtxoIds.contains($0.vtxoId) }
    }

    // MARK: - Action Methods
    
    private func syncAndProgressExits() async {
        isProcessing = true
        defer { isProcessing = false }
        
        print("🔄 Syncing and progressing all exits...")
        
        do {
            // First, sync with server
            try await walletManager.syncExits()
            print("✅ Exit state fetched from server")
            
            // Then progress all exits
            let statuses = try await walletManager.progressExits(feeRateSatPerVb: nil)

            print("✅ Progressed \(statuses.count) exit(s)")
            for status in statuses {
                print("  - VTXO \(status.vtxoId): \(status.state)")
                if let error = status.error {
                    print("    ❌ Error: \(error)")
                }
            }
            
            // Load debug info
            await loadDebugInfo()
            
            // Refresh UI
            await loadExits()
        } catch {
            self.error = "Failed to sync and progress exits: \(error.localizedDescription)"
            print("❌ Failed to sync and progress exits: \(error)")
        }
    }
    
    private func loadDebugInfo() async {
        print("🔍 Loading debug info...")
        
        do {
            // Load all debug info
            claimableHeight = try await walletManager.allExitsClaimableAtHeight()
            hasPendingExits = try await walletManager.hasPendingExits()
            pendingExitsTotal = try await walletManager.pendingExitsTotalSats()
            
            print("✅ Debug info loaded:")
            print("   Claimable height: \(claimableHeight ?? 0)")
            print("   Has pending: \(hasPendingExits ?? false)")
            print("   Pending total: \(pendingExitsTotal ?? 0) sats")
        } catch {
            print("❌ Failed to load debug info: \(error)")
            // Don't set error state here, as this is supplementary info
        }
    }
    
    private func startBlockHeightUpdater() {
        // Update estimated block height every 30 seconds for real-time status updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task { @MainActor in
                latestBlockHeight = await walletManager.getEstimatedBlockHeight()
            }
        }
    }
    
    private func stopBlockHeightUpdater() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func loadExits() async {
        isLoadingExits = true
        error = nil
        
        print("loadUnilateralExits")
        
        do {
            // Get all VTXOs currently in exit process
            exits = try await walletManager.getExitVtxos()
            latestBlockHeight = await walletManager.getEstimatedBlockHeight()

            print("exits: \(exits)")
            print("latestBlockHeight: \(latestBlockHeight ?? -1)")

            loadCompletedExits()

            // Load debug info
            await loadDebugInfo()
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoadingExits = false
    }
}
