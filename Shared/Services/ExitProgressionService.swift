//
//  ExitProgressionService.swift
//  Ark wallet prototype
//
//  Created by Assistant on 2/5/26.
//

import Foundation
import SwiftUI
import Bark
import ArkeUI

/// Service responsible for automatically progressing unilateral exits in the background
/// 
/// This service runs a timer that periodically checks for active exits and progresses them
/// through their state machine. The Bark SDK handles all the complex exit logic - this
/// service just polls it regularly and triggers progression.
///
/// Exit Flow (Fully Automatic):
/// 1. User starts exit → SDK creates exit transactions (fee pre-approved)
/// 2. Service auto-progresses: Start → Processing → AwaitingDelta → Claimable (automatic)
/// 3. Service auto-claims: Claimable → ClaimInProgress → Claimed (automatic)
/// 4. Exit complete - funds moved to onchain wallet
///
/// Design:
/// - Foreground only: Pauses when app goes to background
/// - Timer-based: Checks every 5 minutes (configurable)
/// - SDK-driven: No complex state tracking, just polls SDK
/// - Silent failures: Logs errors but doesn't interrupt user
@MainActor
@Observable
class ExitProgressionService {
    
    // MARK: - Configuration
    
    /// How often to check for exit progression (in seconds)
    private let checkInterval: TimeInterval = 5 * 60 // 5 minutes
    
    // MARK: - State
    
    /// Whether the service is currently running
    private(set) var isRunning: Bool = false
    
    /// Last time exits were checked/progressed
    private(set) var lastCheckTime: Date?
    
    /// Last error encountered (for debugging)
    private(set) var lastError: String?
    
    // MARK: - Dependencies
    
    internal let wallet: BarkWalletProtocol
    internal weak var walletManager: WalletManager?
    
    // MARK: - Timer
    
    private var timer: Timer?
    
    // MARK: - Initialization
    
    init(wallet: BarkWalletProtocol) {
        self.wallet = wallet
        
        // Listen for exit check-in notifications (iOS only)
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: .exitCheckInReceived,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.userCheckedIn()
            }
        }
        #endif
    }
    
    /// Set the wallet manager reference (needed for cache invalidation)
    func setWalletManager(_ manager: WalletManager) {
        self.walletManager = manager
    }
    
    // MARK: - Lifecycle
    
    /// Start the exit progression service
    func start() {
        guard !isRunning else {
            print("⚠️ [ExitProgression] Service already running")
            return
        }
        
        print("▶️ [ExitProgression] Starting service (check interval: \(Int(checkInterval))s)")
        isRunning = true
        
        // Clean up any stale notifications and reattach to existing Live Activities (iOS only)
        #if os(iOS)
        Task {
            await ExitProgressionNotifications.shared.cancelAllCheckInReminders()
            await reattachToExistingActivities()
        }
        #endif
        
        // Run initial check immediately
        Task {
            await checkAndProgressExits()
        }
        
        // Schedule timer for periodic checks
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAndProgressExits()
            }
        }
    }
    
    /// Stop the exit progression service
    func stop() {
        guard isRunning else { return }
        
        print("⏹️ [ExitProgression] Stopping service")
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    /// Manually trigger an immediate check (in addition to scheduled checks)
    func triggerImmediateCheck() {
        guard isRunning else {
            print("⚠️ [ExitProgression] Cannot trigger check - service not running")
            return
        }
        
        print("🔄 [ExitProgression] Manual check triggered")
        Task {
            await checkAndProgressExits()
        }
    }
    
    // MARK: - Fee Rates

    /// Explicit fee rate override for exit operations.
    ///
    /// On mainnet this is nil: bark resolves rates internally from its chain
    /// source (fast tier for CPFP progression, regular for the claim), and
    /// second-guessing that risks underpaying a real exit. Off mainnet the
    /// same estimator gets poisoned by fee spam (signet estimates in the
    /// six-digit sat/vB range), which makes bark's CPFP funding fail — so
    /// pass the app-side rate, which FeeRateService sanity-caps on
    /// non-mainnet networks. Fast tier for everything: it matches what
    /// progression pays, and only overshoots the claim's regular tier.
    private func exitFeeRateOverride() async -> UInt64? {
        guard let walletManager, !walletManager.isMainnet else { return nil }
        return await walletManager.currentFeeRates().fast
    }

    // MARK: - Exit Progression Logic

    /// Check for active exits and progress them if needed
    internal func checkAndProgressExits() async {
        let startTime = Date()
        print("🔍 [ExitProgression] Starting check at \(startTime)")
        
        do {
            // Step 1: Quick check - do we have any exits that need work?
            // IMPORTANT: Bark's hasPendingExits() only counts exits in the
            // Start/Processing/AwaitingDelta states - an exit sitting at
            // Claimable is NOT "pending". Claimable exits must be checked
            // separately, otherwise they are never auto-claimed (the bark
            // daemon usually performs the final AwaitingDelta -> Claimable
            // transition and never claims). Likewise, an exit whose claim tx
            // has been broadcast (ClaimInProgress) is neither pending nor
            // claimable, but still needs progressExits to be marked Claimed
            // once the claim tx confirms.
            let hasPending = try await wallet.hasPendingExits()
            var claimableExits = try await wallet.listClaimableExits()
            let hasClaimsInProgress = try await wallet.getExitVtxos().contains { $0.isClaimInProgress }

            if !hasPending && claimableExits.isEmpty && !hasClaimsInProgress {
                print("✅ [ExitProgression] No pending, claimable, or claim-in-progress exits - skipping progression")

                // A Claimed exit is none of the above, so this early return
                // is the steady state right after an exit completes - still
                // sweep Live Activities here or finished exits keep their
                // activity on the lock screen forever (iOS only)
                #if os(iOS)
                await updateAllLiveActivities()
                #endif

                lastCheckTime = Date()
                lastError = nil
                return
            }

            let kind = hasPending ? "pending" : (!claimableExits.isEmpty ? "claimable" : "claim-in-progress")
            print("📋 [ExitProgression] Found \(kind) exits - progressing...")

            // Step 2: Progress all exits (broadcasts, fee bumps, state updates)
            let statuses = try await wallet.progressExits(feeRateSatPerVb: await exitFeeRateOverride())

            // Log what happened and track per-VTXO blocked state
            if statuses.isEmpty {
                print("   ℹ️ No exits progressed")
            } else {
                print("   ✅ Progressed \(statuses.count) exit(s):")
                for (index, status) in statuses.enumerated() {
                    if let error = status.error {
                        print("      [\(index)] VTXO \(status.vtxoId): ❌ Error: \(error)")
                        walletManager?.recordExitBlocked(vtxoId: status.vtxoId, phase: .progression, errorMessage: error)
                    } else {
                        print("      [\(index)] VTXO \(status.vtxoId): ✅ Success")
                        walletManager?.clearExitBlocked(vtxoId: status.vtxoId, phase: .progression)
                    }
                }
            }

            // Step 3: Check for claimable exits and auto-claim them
            // Re-fetch after progression, which may have just made exits claimable
            claimableExits = try await wallet.listClaimableExits()

            if !claimableExits.isEmpty {
                print("   💰 Found \(claimableExits.count) claimable exit(s) - auto-claiming...")
                do {
                    try await autoClaimExits(claimableExits)
                    for exit in claimableExits {
                        walletManager?.clearExitBlocked(vtxoId: exit.vtxoId, phase: .claim)
                    }
                } catch {
                    // A failed claim (e.g. fees currently exceeding the exit's
                    // value) must not abort the sync/cache steps below - record
                    // it per VTXO and retry on the next interval
                    print("   ❌ Auto-claim failed: \(error.localizedDescription)")
                    for exit in claimableExits {
                        walletManager?.recordExitBlocked(vtxoId: exit.vtxoId, phase: .claim, errorMessage: error.localizedDescription)
                    }
                }
            }
            
            // Step 4: Sync exit state with blockchain
            try await wallet.syncExits()
            print("   ✅ Synced exit state")
            
            // Step 5: Invalidate cache to trigger UI updates
            walletManager?.invalidateExitCache()
            print("   ✅ Invalidated exit cache")
            
            // Step 6: Update Live Activities (iOS only)
            #if os(iOS)
            await updateAllLiveActivities()
            #endif
            
            // Success
            lastCheckTime = Date()
            lastError = nil
            
            let duration = Date().timeIntervalSince(startTime)
            print("✅ [ExitProgression] Check completed in \(String(format: "%.2f", duration))s")
            
        } catch {
            // Log error but don't stop the service
            let errorMessage = error.localizedDescription
            print("❌ [ExitProgression] Error during check: \(errorMessage)")
            lastError = errorMessage
            lastCheckTime = Date()
            
            // Continue running despite errors - will retry on next interval
        }
    }
    
    /// Automatically claim exits that have become claimable
    private func autoClaimExits(_ claimableExits: [ExitVtxo]) async throws {
        // Get the onchain address to send claimed funds to
        let address = try await wallet.getOnchainAddress()
        let claimableVtxoIds = claimableExits.map { $0.vtxoId }
        
        print("      Creating claim transaction for \(claimableVtxoIds.count) VTXO(s)...")

        let feeRateOverride = await exitFeeRateOverride()

        // Step 1: Create the claim transaction
        let claimTx = try await wallet.drainExits(
            vtxoIds: claimableVtxoIds,
            address: address,
            feeRateSatPerVb: feeRateOverride
        )
        
        let totalAmount = claimableExits.reduce(0) { $0 + $1.amountSats }
        print("      ✅ Claim transaction created (Amount: \(totalAmount) sats, Fee: \(claimTx.feeSats) sats)")
        
        // Step 2: Extract the raw transaction from PSBT
        let txHex = try wallet.extractTxFromPsbt(psbtBase64: claimTx.psbtBase64)
        
        // Step 3: Broadcast the transaction
        let txid = try await wallet.broadcastTx(txHex: txHex)
        print("      ✅ Claim transaction broadcast! TXID: \(txid)")

        // Persist the claim fee now — bark is the only source for it (BDK
        // sees the claim as a pure receive and never computes its fee)
        walletManager?.recordClaimFee(claimTxid: txid, feeSats: claimTx.feeSats)
        
        // Step 4: Progress exits to sync state (updates to ClaimInProgress)
        let _ = try await wallet.progressExits(feeRateSatPerVb: feeRateOverride)
        print("      ✅ Exit states updated to ClaimInProgress")
    }
    
    // MARK: - Manual Operations
    
    /// Manually progress exits (exposed for UI triggers)
    func progressExitsManually() async throws {
        print("🔄 [ExitProgression] Manual progression requested")
        
        // See checkAndProgressExits(): Claimable and ClaimInProgress exits
        // don't count as "pending"
        let hasPending = try await wallet.hasPendingExits()
        let claimableExits = try await wallet.listClaimableExits()
        let hasClaimsInProgress = try await wallet.getExitVtxos().contains { $0.isClaimInProgress }
        guard hasPending || !claimableExits.isEmpty || hasClaimsInProgress else {
            print("   ℹ️ No pending, claimable, or claim-in-progress exits to progress")
            return
        }
        
        let statuses = try await wallet.progressExits(feeRateSatPerVb: await exitFeeRateOverride())
        for status in statuses {
            if let error = status.error {
                walletManager?.recordExitBlocked(vtxoId: status.vtxoId, phase: .progression, errorMessage: error)
            } else {
                walletManager?.clearExitBlocked(vtxoId: status.vtxoId, phase: .progression)
            }
        }
        try await wallet.syncExits()
        walletManager?.invalidateExitCache()

        print("   ✅ Manually progressed \(statuses.count) exit(s)")
    }
}
