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
// Passing nil is correct and intentional: Bark resolves nil internally from its
// chain source (the same Esplora backend this app configures, cached 30s):
// - progressExits: uses the FAST tier (1-block target) for CPFP fee bumping
// - drainExits: uses the REGULAR tier (3-block target) for the claim tx
// Do NOT replace nil with a hardcoded rate — Bark's RBF guard rejects rates below
// the RBF minimum. Only pass a value if a user-facing urgency picker is added.
// The cost *estimate* shown to the user comes from FeeRateService (fast tier),
// which queries the same endpoint, so preview and broadcast rates agree.

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

    @Environment(WalletManager.self) var manager
    @Environment(\.scenePhase) private var scenePhase

    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showingStartConfirmation = false
    @State private var showingError = false
    @State private var activeExits: [ExitVtxo] = []
    @State private var claimableHeight: UInt32?
    @State private var exitCostEstimate: ExitCostEstimate?
    @State private var isEstimatingCost = false
    @State private var reminderState: ForcedMoveReminderState = .enabled

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
    private var hasActiveExit: Bool {
        !activeExits.isEmpty
    }

    private var currentBlockHeight: Int {
        manager.estimatedBlockHeight ?? 0
    }
    
    private var spendableBalance: Int {
        manager.arkBalance?.spendableSat ?? 0
    }
    
    private var onchainBalance: UInt64 {
        UInt64(manager.onchainBalance?.totalSat ?? 0)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if hasActiveExit {
                    // State B: Forced move underway. Progression and the final
                    // claim are fully automatic (ExitProgressionService), so
                    // this is purely informational.
                    ForcedMoveProgressView(
                        phase: movePhase,
                        reminderState: reminderState,
                        onEnableReminders: enableReminders
                    ) {
                        GeometryReader { geometry in
                            LoopingVideoPlayer_iOS.aspectFill(
                                videoName: "force-move-progress",
                                videoExtension: "mp4"
                            )
                            .frame(width: geometry.size.width, height: 300)
                        }
                        .frame(height: 300)
                    }
                } else {
                    // State A: No active exit
                    NoExitView(
                        spendableBalance: UInt64(spendableBalance),
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
            await refreshReminderState()
            if !hasActiveExit && spendableBalance > 0 {
                await estimateExitCost()
            }
        }
        .refreshable {
            await loadExitData()
            await refreshReminderState()
            if !hasActiveExit && spendableBalance > 0 {
                await estimateExitCost()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Re-check after a round trip to the system notification settings
            if newPhase == .active {
                Task { await refreshReminderState() }
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
                Text(String(localized: "balance_confirm_recover", defaultValue: "Move \(BitcoinFormatter.shared.formatAmount(spendableBalance)) to Savings? It takes 10+ hours and cannot be cancelled."))
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
    
    // MARK: - Forced Move Phase

    private var movePhase: ForcedMovePhase {
        // A forced move exits every spendable VTXO individually, so only report
        // "finishing" once all of them are claimable or being claimed
        if !activeExits.isEmpty, activeExits.allSatisfy({ $0.isClaimable || $0.isClaimInProgress }) {
            return .finishing
        }
        // claimableHeight is allExitsClaimableAtHeight(), so the countdown
        // covers the last VTXO to mature
        if let claimableHeight, claimableHeight > 0 {
            let blocksRemaining = max(0, Int(claimableHeight) - currentBlockHeight)
            return .waiting(hoursRemaining: blocksRemaining * 10 / 60)
        }
        return .starting
    }

    // MARK: - Check-in Reminders

    private func refreshReminderState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            reminderState = .enabled
        case .notDetermined:
            reminderState = .canAsk
        case .denied:
            reminderState = .denied
        @unknown default:
            reminderState = .denied
        }
    }

    private func enableReminders() {
        Task {
            if reminderState == .canAsk {
                let granted = await ExitProgressionNotifications.shared.requestPermissionIfNeeded()
                if granted {
                    // Scheduling was skipped at exit start without permission
                    await ExitProgressionNotifications.shared.scheduleCheckInSequence()
                }
                await refreshReminderState()
            } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                await UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Actions

    private func estimateExitCost() async {
        guard spendableBalance > 0 else { return }
        
        isEstimatingCost = true
        defer { isEstimatingCost = false }
        
        do {
            print("💰 Estimating exit cost...")
            
            // Get current fee rate (Esplora-backed, falls back to defaults)
            let feeRate = await estimateCurrentFeeRate()
            print("   Fee rate: \(feeRate) sat/vB")
            
            // Get spendable VTXOs count (approximate - we'll exit all of them)
            let vtxos = try await manager.getVTXOs()
            // Count only spendable ones (not locked in pending operations)
            let vtxoCount = vtxos.filter { $0.state == .spendable }.count
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
            
        } catch {
            print("⚠️ Failed to estimate exit cost: \(error)")
            // Don't block the user - just skip the estimate
            exitCostEstimate = nil
        }
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
            // Load active exits from Bark SDK (filter out completed/claimed exits)
            let allExits = try await manager.getExitVtxos()
            
            print("📊 All Exit VTXOs from getExitVtxos():")
            print("   Count: \(allExits.count)")
            for (index, exit) in allExits.enumerated() {
                print("\n   [\(index)] Full Object Dump:")
                
                // Use Mirror to inspect all properties
                let mirror = Mirror(reflecting: exit)
                for child in mirror.children {
                    if let label = child.label {
                        print("       \(label): \(child.value)")
                    }
                }
                
                // Print the computed/extension properties we know about
                print("\n       Computed Properties:")
                print("       vtxoId: \(exit.vtxoId)")
                print("       amountSats: \(exit.amountSats)")
                print("       formattedAmount: \(exit.formattedAmount)")
                print("       shortVtxoId: \(exit.shortVtxoId)")
                print("       state: \(exit.state)")
                print("       stateDisplayName: \(exit.stateDisplayName)")
                print("       isActive: \(exit.isActive)")
                print("       isClaimable: \(exit.isClaimable)")
                print("       isClaimed: \(exit.isClaimed)")
                print("       stateIcon: \(exit.stateIcon)")
                print("       stateColor: \(exit.stateColor)")
            }
            
            activeExits = allExits.filter { $0.isActive }
            
            print("\n🔍 Filtered Active Exits:")
            print("   Count: \(activeExits.count)")
            for (index, exit) in activeExits.enumerated() {
                print("   [\(index)] VTXO ID: \(exit.vtxoId)")
                print("       Amount: \(exit.amountSats) sats (\(exit.formattedAmount))")
                print("       State: \(exit.state)")
                print("       State Display: \(exit.stateDisplayName)")
                print("       isClaimable: \(exit.isClaimable)")
            }
            
            // Get claimable height if there are exits
            if !activeExits.isEmpty {
                claimableHeight = try await manager.allExitsClaimableAtHeight()
            }
            
            print("   claimableHeight: \(claimableHeight.map(String.init) ?? "nil")")
            
            // Progress exits (broadcast, fee bump, advance state machine)
            if !activeExits.isEmpty {
                let statuses = try await manager.progressExits(feeRateSatPerVb: nil as UInt64?)
                print("✅ Progressed \(statuses.count) exit(s)")
            }
            
            // Sync exit state
            try await manager.syncExits()
            
        } catch {
            print("⚠️ Failed to load exit data: \(error)")
            // Don't show error to user for background refresh failures
        }
    }
    
    private func startExit() async {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            print("🚪 Starting unilateral exit...")
            
            // Start exit via wallet manager (Bark SDK handles all tracking)
            let result = try await manager.startExit()
            print("✅ Exit started: \(result)")

            // Ask for notification permission at the moment of commitment so
            // the hourly check-in reminders can actually fire
            _ = await ExitProgressionNotifications.shared.requestPermissionIfNeeded()
            await refreshReminderState()

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
