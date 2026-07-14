//
//  ExitProgressionService+LiveActivity.swift
//  Arké
//
//  Live Activity management extension for ExitProgressionService
//  Created by Claude on 5/12/26.
//

#if canImport(ActivityKit) && os(iOS)
import Foundation
import ActivityKit
import Bark

extension ExitProgressionService {
    
    // MARK: - Live Activity Management
    
    /// Active Live Activities tracked by exit ID
    private static var activeActivities: [String: Activity<ExitProgressActivityAttributes>] = [:]
    
    /// Scheduled notification IDs for cleanup
    private static var scheduledNotificationIds: [String] = []
    
    // MARK: - Start Exit Monitoring
    
    /// Start Live Activity and notification schedule when exit begins
    func startExitMonitoring(for exitVtxos: [ExitVtxo]) async {
        print("🚀 [LiveActivity] Starting exit monitoring for \(exitVtxos.count) VTXO(s)")
        
        // Start Live Activity
        await startLiveActivity(for: exitVtxos)
        
        // Schedule check-in notifications
        await ExitProgressionNotifications.shared.scheduleCheckInSequence()
    }
    
    // MARK: - Live Activity Lifecycle
    
    /// Start a new Live Activity for an exit batch
    func startLiveActivity(for exitVtxos: [ExitVtxo]) async {
        guard !exitVtxos.isEmpty else {
            print("⚠️ [LiveActivity] No VTXOs provided, cannot start activity")
            return
        }
        
        // Check if Live Activities are enabled
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚠️ [LiveActivity] Live Activities not enabled by user")
            return
        }
        
        // Use first VTXO ID as the exit identifier
        let exitId = exitVtxos.first?.vtxoId ?? UUID().uuidString
        
        // Check if we already have an activity for this exit
        if Self.activeActivities[exitId] != nil {
            print("⚠️ [LiveActivity] Activity already exists for exit \(exitId)")
            return
        }
        
        let attributes = ExitProgressActivityAttributes(
            exitId: exitId,
            exitCount: exitVtxos.count,
            startTime: Date()
        )
        
        let initialState = ExitProgressActivityAttributes.ContentState(
            currentStep: 1,
            totalSteps: 5, // Will be updated when we get transaction count (1 tx + 4 steps)
            stepDescription: exitVtxos.count > 1 ? "Moving \(exitVtxos.count) outputs" : "Moving to savings",
            transactionsConfirmed: 0,
            totalTransactions: 0,
            exitState: .start,
            lastUpdated: Date(),
            needsCheckIn: false,
            isWaitingForBlocks: false,
            isClaimable: false,
            isClaimed: false,
            hasError: false
        )
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil)
            )
            Self.activeActivities[exitId] = activity
            print("✅ [LiveActivity] Started activity for exit \(exitId)")
        } catch {
            print("❌ [LiveActivity] Failed to start activity: \(error)")
        }
    }
    
    /// Update Live Activity with current exit status
    func updateLiveActivity(exitId: String, with status: Bark.ExitTransactionStatus) async {
        guard let activity = Self.activeActivities[exitId] else {
            print("⚠️ [LiveActivity] No active activity found for exit \(exitId)")
            return
        }
        
        var contentState = buildContentState(from: status, needsCheckIn: false)

        // Surface a blocked exit (fees can't be covered right now) instead of
        // the regular step description
        if let blocked = walletManager?.getExitBlockedInfo(for: exitId) {
            contentState.stepDescription = Self.pausedDescription(for: blocked.reason)
        }

        await activity.update(
            ActivityContent(
                state: contentState,
                staleDate: Date().addingTimeInterval(120 * 60) // Stale in 2 hours
            )
        )
        
        print("✅ [LiveActivity] Updated activity for exit \(exitId)")
    }
    
    /// End Live Activity when exit completes or fails
    func endLiveActivity(exitId: String, success: Bool) async {
        guard let activity = Self.activeActivities[exitId] else {
            print("⚠️ [LiveActivity] No active activity found for exit \(exitId)")
            return
        }
        
        let finalState = ExitProgressActivityAttributes.ContentState(
            currentStep: success ? 5 : 1, // Assuming minimal 1 tx (5 total steps)
            totalSteps: 5,
            stepDescription: success ? "Move completed!" : "Move stopped",
            transactionsConfirmed: 0,
            totalTransactions: 1,
            exitState: success ? .claimed : .start,
            lastUpdated: Date(),
            needsCheckIn: false,
            isWaitingForBlocks: false,
            isClaimable: false,
            isClaimed: success,
            hasError: !success
        )
        
        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .after(.now + 3600) // Dismiss after 1 hour
        )
        
        Self.activeActivities.removeValue(forKey: exitId)
        print("✅ [LiveActivity] Ended activity for exit \(exitId)")
        
        // Cancel notifications if this was the last active exit
        if Self.activeActivities.isEmpty {
            await ExitProgressionNotifications.shared.cancelAllCheckInReminders()
        }
    }
    
    /// Reattach to existing activities on app launch
    func reattachToExistingActivities() async {
        // First, reattach to any existing Live Activities that survived
        for activity in Activity<ExitProgressActivityAttributes>.activities {
            let exitId = activity.attributes.exitId
            Self.activeActivities[exitId] = activity
            print("✅ [LiveActivity] Reattached to existing activity for exit \(exitId)")
        }
        
        // Then, check if we have active exits without Live Activities (e.g., after rebuild)
        await recreateMissingActivities()
    }
    
    /// Recreate Live Activities for active exits that don't have them
    private func recreateMissingActivities() async {
        do {
            // Check if we have any pending exits
            let hasPending = try await wallet.hasPendingExits()
            guard hasPending else {
                print("ℹ️ [LiveActivity] No pending exits found")
                return
            }
            
            // Get all exit VTXOs
            let exitVtxos = try await wallet.getExitVtxos()
            guard !exitVtxos.isEmpty else {
                print("ℹ️ [LiveActivity] No exit VTXOs found")
                return
            }
            
            print("🔄 [LiveActivity] Found \(exitVtxos.count) active exit(s) without Live Activities")
            
            // For each exit, create a Live Activity if it doesn't have one
            for vtxo in exitVtxos {
                let exitId = vtxo.vtxoId
                
                // Skip if we already have an activity for this exit
                if Self.activeActivities[exitId] != nil {
                    continue
                }
                
                // Create a new Live Activity for this exit
                print("🆕 [LiveActivity] Recreating Live Activity for exit \(exitId)")
                await startLiveActivity(for: [vtxo])
            }
            
        } catch {
            print("⚠️ [LiveActivity] Failed to recreate activities: \(error)")
        }
    }
    
    /// Clean up dismissed activities
    func cleanupDismissedActivities() async {
        let currentActivityIds = Set(Activity<ExitProgressActivityAttributes>.activities.map { $0.attributes.exitId })
        
        for (exitId, _) in Self.activeActivities {
            if !currentActivityIds.contains(exitId) {
                Self.activeActivities.removeValue(forKey: exitId)
                print("🗑️ [LiveActivity] Removed dismissed activity for exit \(exitId)")
            }
        }
    }
    
    /// Check if there are any active exits being monitored
    func hasActiveExits() async -> Bool {
        return !Self.activeActivities.isEmpty
    }
    
    // MARK: - User Check-In Handler
    
    /// Called when user checks in (taps notification or opens app)
    func userCheckedIn() async {
        print("👤 [LiveActivity] User checked in")
        
        // Progress exits
        await checkAndProgressExits()
        
        // Refresh balances and transactions to show latest exit state
        await walletManager?.refreshAfterVTXOChange()
        
        // Update all Live Activities to "fresh" state
        await updateAllLiveActivitiesAfterCheckIn()
        
        // Reschedule notifications (reset the clock)
        await ExitProgressionNotifications.shared.scheduleCheckInSequence()
    }
    
    private func updateAllLiveActivitiesAfterCheckIn() async {
        for (exitId, activity) in Self.activeActivities {
            // Get latest exit status
            do {
                let exitVtxos = try await wallet.getExitVtxos()
                guard let vtxo = exitVtxos.first(where: { $0.vtxoId == exitId }) else {
                    continue
                }
                
                guard let status = try await wallet.getExitStatus(
                    vtxoId: vtxo.vtxoId,
                    includeHistory: false,
                    includeTransactions: true
                ) else {
                    print("⚠️ [LiveActivity] No status available for exit \(exitId)")
                    continue
                }
                
                let contentState = buildContentState(from: status, needsCheckIn: false)
                
                await activity.update(
                    ActivityContent(
                        state: contentState,
                        staleDate: Date().addingTimeInterval(120 * 60) // Stale in 2 hours
                    )
                )
                
                print("✅ [LiveActivity] Updated activity \(exitId) after check-in")
                
            } catch {
                print("❌ [LiveActivity] Failed to update activity \(exitId): \(error)")
            }
        }
    }
    
    // MARK: - Content State Building

    /// Step description override for blocked exits. Plain English like the
    /// other step descriptions in this file (Live Activity content isn't
    /// routed through the localization catalogs yet).
    private static func pausedDescription(for reason: ExitBlockedReason) -> String {
        switch reason {
        case .insufficientOnchainFunds:
            return "Paused — add onchain funds to continue"
        case .claimFeeExceedsOutput:
            return "Paused — network fees too high"
        case .other:
            return "Paused — will retry automatically"
        }
    }

    /// Build ContentState from ExitTransactionStatus
    private func buildContentState(from status: Bark.ExitTransactionStatus, needsCheckIn: Bool) -> ExitProgressActivityAttributes.ContentState {
        let parsed = ExitStatusParser.parseState(status.state)
        let transactionCount = max(1, Int(status.transactionCount))
        let totalSteps = transactionCount + 4
        let (currentStep, exitState, description, isWaiting, isClaimable, isClaimed) = parseExitState(parsed, transactionCount: transactionCount)
        
        return ExitProgressActivityAttributes.ContentState(
            currentStep: currentStep,
            totalSteps: totalSteps,
            stepDescription: description,
            transactionsConfirmed: countConfirmedTransactions(status),
            totalTransactions: transactionCount,
            exitState: exitState,
            lastUpdated: Date(),
            needsCheckIn: needsCheckIn,
            currentBlockHeight: extractCurrentBlockHeight(parsed),
            targetBlockHeight: extractTargetBlockHeight(parsed),
            blocksRemaining: extractBlocksRemaining(parsed),
            isWaitingForBlocks: isWaiting,
            isClaimable: isClaimable,
            isClaimed: isClaimed,
            hasError: false
        )
    }
    
    /// Parse exit state into step number, state, description, and flags
    /// Steps: 1=Prepare, 2..k+1=Process transactions, k+2=Wait unlock, k+3=Claim, k+4=Complete
    private func parseExitState(_ parsed: ParsedExitState?, transactionCount: Int) -> (Int, ExitState, String, Bool, Bool, Bool) {
        guard let parsed = parsed else {
            return (1, .unparsed, "Processing...", false, false, false)
        }
        
        switch parsed {
        case .start:
            return (1, .start, "Starting move to savings", false, false, false)
            
        case .processing(let state):
            let confirmedCount = state.transactions.filter { tx in
                if case .confirmed = tx.status {
                    return true
                }
                return false
            }.count
            let currentStep = 2 + confirmedCount
            
            if state.transactions.isEmpty {
                return (currentStep, .processing, "Broadcasting transactions", false, false, false)
            } else {
                return (currentStep, .processing, "Confirming transactions", false, false, false)
            }
            
        case .awaitingDelta(let data):
            let blocksLeft = data.claimableHeight > data.tipHeight ? 
                data.claimableHeight - data.tipHeight : 0
            let currentStep = transactionCount + 2
            return (currentStep, .awaitingDelta, "Waiting for \(blocksLeft) blocks", true, false, false)
            
        case .claimable:
            let currentStep = transactionCount + 2
            return (currentStep, .claimable, "Ready to claim", false, true, false)
            
        case .claimInProgress:
            let currentStep = transactionCount + 3
            return (currentStep, .claimInProgress, "Claim transaction confirming", false, false, false)
            
        case .claimed:
            let currentStep = transactionCount + 4
            return (currentStep, .claimed, "Move complete", false, false, true)

        case .vtxoAlreadySpent:
            // Terminal: exit cancelled because the VTXO was spent elsewhere.
            // No dedicated Live Activity state yet — surface as a terminal message.
            return (transactionCount + 4, .unparsed, "Exit cancelled — funds already spent", false, false, true)

        case .unparsed:
            return (1, .unparsed, "Processing...", false, false, false)
        }
    }
    
    /// Count confirmed transactions from status
    private func countConfirmedTransactions(_ status: Bark.ExitTransactionStatus) -> Int {
        guard let parsed = ExitStatusParser.parseState(status.state) else {
            return 0
        }
        
        if case .processing(let state) = parsed {
            return state.transactions.filter { tx in
                if case .confirmed = tx.status {
                    return true
                }
                return false
            }.count
        }
        
        return 0
    }
    
    /// Extract current block height from parsed state
    private func extractCurrentBlockHeight(_ parsed: ParsedExitState?) -> UInt32? {
        guard let parsed = parsed else { return nil }
        
        switch parsed {
        case .start(let state):
            return state.tipHeight
        case .processing(let state):
            return state.tipHeight
        case .awaitingDelta(let state):
            return state.tipHeight
        case .claimable(let state):
            return state.tipHeight
        case .claimInProgress(let state):
            return state.tipHeight
        case .claimed(let state):
            return state.tipHeight
        case .vtxoAlreadySpent(let state):
            return state.tipHeight
        case .unparsed:
            return nil
        }
    }
    
    /// Extract target block height from parsed state
    private func extractTargetBlockHeight(_ parsed: ParsedExitState?) -> UInt32? {
        guard let parsed = parsed else { return nil }
        
        if case .awaitingDelta(let state) = parsed {
            return state.claimableHeight
        }
        
        return nil
    }
    
    /// Extract blocks remaining from parsed state
    private func extractBlocksRemaining(_ parsed: ParsedExitState?) -> Int? {
        guard let parsed = parsed else { return nil }
        
        if case .awaitingDelta(let state) = parsed {
            if state.claimableHeight > state.tipHeight {
                return Int(state.claimableHeight - state.tipHeight)
            } else {
                return 0
            }
        }
        
        return nil
    }
    
    // MARK: - Integration with Existing checkAndProgressExits
    
    /// Update all active Live Activities (called from checkAndProgressExits)
    func updateAllLiveActivities() async {
        guard !Self.activeActivities.isEmpty else { return }
        
        do {
            let exitVtxos = try await wallet.getExitVtxos()
            
            // Update each active Live Activity
            for (exitId, _) in Self.activeActivities {
                guard let vtxo = exitVtxos.first(where: { $0.vtxoId == exitId }) else {
                    // Exit is complete (VTXO no longer in exit list)
                    await endLiveActivity(exitId: exitId, success: true)
                    continue
                }
                
                // Get status and update activity
                guard let status = try await wallet.getExitStatus(
                    vtxoId: vtxo.vtxoId,
                    includeHistory: false,
                    includeTransactions: true
                ) else {
                    continue
                }
                
                await updateLiveActivity(exitId: exitId, with: status)
            }
            
            // Clean up any dismissed activities
            await cleanupDismissedActivities()
            
        } catch {
            print("❌ [LiveActivity] Failed to update activities: \(error)")
        }
    }
}

#endif
