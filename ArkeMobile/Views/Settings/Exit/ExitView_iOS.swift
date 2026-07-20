//
//  ExitView_iOS.swift
//  Arké
//
//  Created by Christoph on 1/7/26.
//

// MARK: - Outstanding Issues & TODOs

// NOTE: Exit Cost Estimation (FINAL CORRECTION 2026-04-24)
// The calculateExitCost() function uses conservative assumptions based on Bark's implementation:
// 
// Critical corrections from detailed Bark developer feedback:
// 1. NO deduplication assumed (0%) - safest without full VTXO chain txid analysis
// 2. Exit tx weight: 1012 WU (RADIX=4: 1 input + 4 P2TR outputs + 1 P2A anchor)
// 3. Tree depth: 3 levels (conservative budget for typical round sizes)
// 4. Claim tx: 214 + N×304 WU (script-path spend, not keyspend)
// 
// Round tree structure (mod.rs, RADIX=4):
// - Round size 1-4 VTXOs → depth 1 → 1 exit tx per VTXO
// - Round size 5-16 VTXOs → depth 2 → 2 exit txs per VTXO
// - Round size 17-64 VTXOs → depth 3 → 3 exit txs per VTXO
// - Round size 65-256 VTXOs → depth 4 → 4 exit txs per VTXO
// 
// Exit transaction weight (RADIX=4):
// - Formula: (64 + 43×R)×4 + 68 where R=4
// - Result: 1012 WU per exit transaction at any tree level
// 
// Claim transaction weight (script-path spend):
// - Witness per input: 140 WU (sig + 39-byte DelayedSignClause + 33-byte control block)
// - Input: 164 WU (non-witness) + 140 WU (witness) = 304 WU
// - Overhead: 214 WU (base tx + marker/flag + outputs)
// - Formula: 214 + N×304 WU
// 
// Example (10 VTXOs, depth 3, 8 sat/vB):
// - Exit phase: (1012×10×3)/4 × 8 × 2 = 121,440 sats
// - Claim phase: (214+10×304)/4 × 8 = 6,508 sats
// - Total with 15% margin: ~147,150 sats

// NOTE: Fee Rates for progressExits()/drainExits() (verified against bark 0.3.0 sources)
// On mainnet, nil is passed and Bark resolves it internally from its chain
// source (the same Esplora backend this app configures, cached 30s):
// - progressExits: uses the FAST tier (1-block target) for CPFP fee bumping
// - drainExits: uses the REGULAR tier (3-block target) for the claim tx
// Do NOT replace nil with a hardcoded rate on mainnet — Bark's RBF guard rejects
// rates below the RBF minimum. Off mainnet, ExitProgressionService passes the
// app-side rate instead (see exitFeeRateOverride), because signet fee spam
// poisons the estimator with six-digit sat/vB values that make CPFP funding fail.
// The cost *estimate* shown to the user comes from FeeRateService (fast tier),
// which queries the same endpoint and is sanity-capped off mainnet, so preview
// and broadcast rates agree.

// TODO: Offline Claim Broadcast Fallback (LOW PRIORITY)
// Currently, drainExits() creates a signed PSBT and progressExits() broadcasts it
// via the Ark server. In the future, we may want a fallback option to manually
// broadcast the PSBT if the Ark server is unavailable.
// Location: ExitProgressionService.autoClaimExits() after wallet.drainExits()
// Enhancement: Add manual broadcast capability using Bitcoin Core/Esplora API

// NOTE: Exit Status State Machine
// The Bark SDK tracks exit status through its own state machine:
// Start → Processing → AwaitingDelta → Claimable → ClaimInProgress → Claimed
// We query this directly and no longer maintain app-level tracking.

import SwiftUI
import Bark
import ArkeUI
import UserNotifications

struct ExitView_iOS: View {
    var onNavigateToBalance: (() -> Void)? = nil
    var onNavigateToActivity: (() -> Void)? = nil

    @Environment(WalletManager.self) var manager

    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showingStartConfirmation = false
    @State private var showingError = false
    @State private var inFlightExits: [ExitVtxo] = []
    @State private var uncoveredVtxos: [VTXOModel] = []
    @State private var hasLoadedExitData = false
    @State private var exitCostEstimate: ExitCostEstimate?
    @State private var isEstimatingCost = false

    @AppStorage(UserDefaults.notificationsEnabledKey)
    private var notificationsEnabled: Bool = false

    private let forceMoveIntroSubtitles: [VideoSubtitle] = [
        VideoSubtitle(startTime: 0.001, endTime: 1.840, text: "Let's talk about the forced move."),
        VideoSubtitle(startTime: 1.840, endTime: 3.440, text: "This is your safety net."),
        VideoSubtitle(startTime: 3.440, endTime: 6.320, text: "Normally, moving bitcoin to savings is quick."),
        VideoSubtitle(startTime: 6.320, endTime: 8.800, text: "The server helps, fees are small."),
        VideoSubtitle(startTime: 8.740, endTime: 10.500, text: "Do that first if you can."),
        VideoSubtitle(startTime: 10.500, endTime: 12.260, text: "But you're not dependent on it."),
        VideoSubtitle(startTime: 12.260, endTime: 15.620, text: "If the server ever stops responding, you don't lose anything."),
        VideoSubtitle(startTime: 15.620, endTime: 18.420, text: "A forced move gets your bitcoin out on your own."),
        VideoSubtitle(startTime: 18.420, endTime: 20.020, text: "No one's permission needed."),
        VideoSubtitle(startTime: 20.060, endTime: 21.340, text: "It's not free."),
        VideoSubtitle(startTime: 21.340, endTime: 23.020, text: "Expect 10 hours or more."),
        VideoSubtitle(startTime: 23.020, endTime: 26.619, text: "Fees can run high, and it can't be undone once it starts."),
        VideoSubtitle(startTime: 26.619, endTime: 30.220, text: "And you'll need to check back about once an hour until it's done."),
        VideoSubtitle(startTime: 30.039, endTime: 34.040, text: "We'll remind you. Keep it for emergencies, but know it's here."),
        VideoSubtitle(startTime: 34.040, endTime: 36.600, text: "This is what makes the bitcoin truly yours.")
    ]
    
    // Computed properties

    /// Sum of spendable VTXOs that are not part of any in-flight exit —
    /// the amount a newly started forced move would actually cover.
    private var uncoveredBalance: UInt64 {
        UInt64(uncoveredVtxos.reduce(0) { $0 + $1.amountSat })
    }

    private var onchainBalance: UInt64 {
        UInt64(manager.onchainBalance?.totalSat ?? 0)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if !hasLoadedExitData {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                } else if uncoveredVtxos.isEmpty && !inFlightExits.isEmpty {
                    // Everything spendable is already part of an in-flight
                    // forced move — nothing new to start. Progress lives in
                    // the activity view, not here.
                    ForcedMoveUnderwayView(onGoToActivity: onNavigateToActivity) {
                        GeometryReader { geometry in
                            LoopingVideoPlayer_iOS.aspectFill(
                                videoName: "force-move-progress-square",
                                videoExtension: "mp4"
                            )
                            .frame(width: geometry.size.width, height: 300)
                        }
                        .frame(height: 300)
                    }
                } else {
                    // Start flow, scoped to the VTXOs no exit covers yet.
                    // With no exits in flight that is simply everything
                    // spendable; NoExitView also renders the zero-balance
                    // empty state.
                    NoExitView(
                        spendableBalance: uncoveredBalance,
                        isProcessing: isProcessing || isEstimatingCost,
                        onStartExit: {
                            Task {
                                await estimateExitCost()
                                showingStartConfirmation = true
                            }
                        },
                        exitCostEstimate: exitCostEstimate,
                        onchainBalance: onchainBalance,
                        isConnectedToServer: manager.connectionStatus.isConnected,
                        hasOngoingRefresh: manager.hasActiveRefresh,
                        onGoToBalance: onNavigateToBalance
                    ) {
                        IntroVideoPlayer_iOS(
                            videoName: "force-move-intro",
                            subtitles: forceMoveIntroSubtitles,
                            autoPlay: false,
                            subtitleBottomPadding: 16
                        )
                        .frame(height: 300)
                    }
                }
            }
            .padding()
        }
        .task {
            await loadExitData()
            if !uncoveredVtxos.isEmpty {
                await estimateExitCost()
            }
        }
        .refreshable {
            await loadExitData()
            if !uncoveredVtxos.isEmpty {
                await estimateExitCost()
            }
        }
        .alert("action_start_forced_move", isPresented: $showingStartConfirmation) {
            Button("button_cancel", role: .cancel) { }
            if let estimate = exitCostEstimate, !estimate.canAfford {
                Button("settings_board_funds") {
                    // TODO: Navigate to board flow
                }
            } else {
                Button("button_start") {
                    Task {
                        await startExit()
                    }
                }
            }
        } message: {
            if let estimate = exitCostEstimate {
                if estimate.canAfford {
                    /*
                    Text("""
                    Recover \(BitcoinFormatter.shared.formatAmount(spendableBalance))?
                    
                    Estimated cost: \(BitcoinFormatter.shared.formatAmount(Int(estimate.totalCost)))
                    Fee rate: \(estimate.feeRate) sat/vB
                    
                    This takes about 24 hours and cannot be cancelled.
                    """)
                    */
                    Text("settings_forced_move_duration_warning")
                } else {
                    Text("""
                    ⚠️ Insufficient onchain balance
                    
                    Required: \(BitcoinFormatter.shared.formatAmount(Int(estimate.totalCost)))
                    Available: \(BitcoinFormatter.shared.formatAmount(Int(estimate.onchainBalance)))
                    Need to board: \(BitcoinFormatter.shared.formatAmount(Int(estimate.shortfall)))
                    
                    Please board more Bitcoin to your savings balance before starting.
                    """)
                }
            } else {
                Text(String(localized: "balance_confirm_recover", defaultValue: "Move \(BitcoinFormatter.shared.formatAmount(Int(uncoveredBalance))) to Savings? It takes 10+ hours and cannot be cancelled."))
            }
        }
        .tint(Color.Arke.gold4)
        .alert("error_title", isPresented: $showingError) {
            Button("button_ok") { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .overlay {
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ProgressView()
                        .controlSize(.large)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    // MARK: - Actions

    private func estimateExitCost() async {
        guard !uncoveredVtxos.isEmpty else { return }

        isEstimatingCost = true
        defer { isEstimatingCost = false }

        print("💰 Estimating exit cost...")

        // Get current fee rate (Esplora-backed, falls back to defaults)
        let feeRate = await estimateCurrentFeeRate()
        print("   Fee rate: \(feeRate) sat/vB")

        // Only the VTXOs a new forced move would actually cover
        let vtxoCount = uncoveredVtxos.count
        print("   VTXOs to exit: \(vtxoCount)")

        // Estimate transaction costs
        let estimate = calculateExitCost(
            vtxoCount: vtxoCount,
            feeRateSatPerVb: feeRate,
            onchainBalance: onchainBalance
        )

        print("   Estimated cost: \(estimate.totalCost) sats")
        print("   Can afford: \(estimate.canAfford)")

        exitCostEstimate = estimate
    }
    
    private func estimateCurrentFeeRate() async -> UInt64 {
        // Fast tier matches what progressExits actually pays for CPFP
        // when it resolves its nil fee rate internally
        return await manager.currentFeeRates().fast
    }
    
    private func calculateExitCost(
        vtxoCount: Int,
        feeRateSatPerVb: UInt64,
        onchainBalance: UInt64
    ) -> ExitCostEstimate {
        // CONSERVATIVE ASSUMPTION: No deduplication
        // Bark deduplicates parent exit transactions by txid (transaction_manager.rs)
        // Dedup rate depends entirely on round tree structure:
        // - VTXOs from different rounds: 0% deduplication (every txid is unique)
        // - VTXOs from same round: 30-60%+ deduplication (shared upper-tree txs)
        // Without access to full VTXO chain txids, safest assumption is NO deduplication
        
        // Exit transaction weight (RADIX=4 from mod.rs)
        // Each exit tx at any tree level has:
        // - 1 taproot keyspend input
        // - 4 P2TR outputs (3 siblings + chain-continuation)
        // - 1 P2A anchor output (13 vbytes = 52 WU)
        // Weight = (64 + 43×R)×4 + 68, where R=4 for round tree
        // Result: (64 + 43×4)×4 + 68 = 1012 WU per exit tx
        let exitTxWeight: UInt64 = 1012
        
        // Helper function to calculate cost for specific parameters
        func calculate(depth: UInt64, cpfpMultiplier: Double, safetyMargin: Double) -> UInt64 {
            // Total weight of all parent transactions in exit chains
            let totalParentWeight = exitTxWeight * UInt64(vtxoCount) * depth
            let totalParentVbytes = totalParentWeight / 4
            
            // CPFP fee with variable multiplier
            let exitPhaseFee = UInt64(Double(totalParentVbytes * feeRateSatPerVb) * cpfpMultiplier)
            
            // Claim transaction fee
            // Claim tx uses script-path spend through DelayedSignClause
            // Formula: 214 + 304×N WU
            let claimTxWeight: UInt64 = UInt64(214 + vtxoCount * 304)
            let claimFee = (claimTxWeight / 4) * feeRateSatPerVb
            
            // Apply safety margin
            let baseCost = exitPhaseFee + claimFee
            return UInt64(Double(baseCost) * safetyMargin)
        }
        
        // Optimistic scenario: depth=1 (boarding VTXOs), CPFP=1.5x, margin=1.10
        // Assumes mostly boarding VTXOs with minimal tree depth
        let lowCost = calculate(depth: 1, cpfpMultiplier: 1.5, safetyMargin: 1.10)
        
        // Mid-point scenario: depth=2, CPFP=1.8x, margin=1.15
        // Reasonable average for mixed VTXO sources
        let midCost = calculate(depth: 2, cpfpMultiplier: 1.8, safetyMargin: 1.15)
        
        // Conservative scenario: depth=3, CPFP=2.0x, margin=1.15
        // Tree depth budget: Round size → Depth: 1-4 VTXOs=1, 5-16=2, 17-64=3, 65-256=4
        // CPFP multiplier 2x is deliberately generous (real is typically 1.3-1.8x)
        let highCost = calculate(depth: 3, cpfpMultiplier: 2.0, safetyMargin: 1.15)
        
        // Calculate transaction counts
        // Formula: (vtxoCount × depth) + 1 claim transaction
        // Each VTXO requires 'depth' exit transactions, then 1 final claim batches all
        let minTransactions = (vtxoCount * 1) + 1  // Optimistic: depth=1 + claim
        let maxTransactions = (vtxoCount * 3) + 1  // Conservative: depth=3 + claim
        
        // Use highCost for affordability check (be safe)
        let canAfford = onchainBalance >= highCost
        
        return ExitCostEstimate(
            lowCost: lowCost,
            totalCost: midCost,
            highCost: highCost,
            minTransactions: minTransactions,
            maxTransactions: maxTransactions,
            feeRate: feeRateSatPerVb,
            canAfford: canAfford,
            onchainBalance: onchainBalance
        )
    }
    
    private func loadExitData() async {
        do {
            // In-flight exits (not claimed, not cancelled) — cancelled exits
            // stay in bark's exit list forever and must not count here, or a
            // wallet with only a cancelled exit could never start a new move
            let allExits = try await manager.getExitVtxos()
            inFlightExits = allExits.filter { $0.isInFlight }

            // Spendable VTXOs no exit covers yet. Exiting VTXOs can still
            // report as spendable during the early exit phase, so membership
            // in the in-flight exit set is what decides coverage, not state.
            let inFlightIds = Set(inFlightExits.map(\.vtxoId))
            let vtxos = try await manager.getVTXOs()
            uncoveredVtxos = vtxos.filter {
                $0.state == .spendable && !inFlightIds.contains($0.id)
            }

            print("📊 Exit data loaded: \(inFlightExits.count) in-flight exit(s), \(uncoveredVtxos.count) uncovered VTXO(s)")

            // Sync exit state
            try await manager.syncExits()

        } catch {
            print("⚠️ Failed to load exit data: \(error)")
            // Don't show error to user for background refresh failures
        }
        hasLoadedExitData = true
    }
    
    private func startExit() async {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            print("🚪 Starting unilateral exit...")

            // Start exit via wallet manager (Bark SDK handles all tracking).
            // With exits already in flight, pass the uncovered VTXO ids
            // explicitly so what the user confirmed is exactly what exits —
            // exiting VTXOs can still read as spendable early on, and an
            // "entire wallet" call must not depend on bark deduplicating them.
            let result: String
            if inFlightExits.isEmpty {
                result = try await manager.startExit()
            } else {
                result = try await manager.startExitForVTXOs(vtxo_ids: uncoveredVtxos.map(\.id))
            }
            print("✅ Exit started: \(result)")

            // Ask for notification permission at the moment of commitment so
            // the hourly check-in reminders can actually fire. Granting a
            // fresh prompt is an opt-in, so it also flips the global setting;
            // an explicit "off" in app settings stays respected.
            let statusBefore = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            let granted = await ExitProgressionNotifications.shared.requestPermissionIfNeeded()
            if granted && statusBefore == .notDetermined {
                notificationsEnabled = true
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }

            // Start Live Activity monitoring for this exit
            if let exitVtxos = try? await manager.getExitVtxos() {
                await manager.exitProgressionService?.startExitMonitoring(for: exitVtxos)
            }
            
            // Refresh wallet state and exit data
            await manager.refresh()
            await loadExitData()
            
        } catch {
            print("❌ Failed to start exit: \(error)")
            errorMessage = "Failed to start exit: \(error.localizedDescription)"
            showingError = true
        }
    }
    
}
