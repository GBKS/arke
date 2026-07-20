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

    /// The single Live Activity tracking all concurrent exit movements.
    private static var activeActivity: Activity<ExitProgressActivityAttributes>?

    // MARK: - Start Exit Monitoring

    /// Start the Live Activity and schedule check-in notifications when an exit begins.
    func startExitMonitoring(for exitVtxos: [ExitVtxo]) async {
        print("🚀 [LiveActivity] Starting exit monitoring for \(exitVtxos.count) VTXO(s)")
        await startLiveActivity(for: exitVtxos)
        await ExitProgressionNotifications.shared.scheduleCheckInSequence()
    }

    // MARK: - Live Activity Lifecycle

    /// Ensure one Live Activity exists for the current exit batch. If an activity
    /// is already running, refreshes it instead of creating a duplicate.
    func startLiveActivity(for exitVtxos: [ExitVtxo]) async {
        guard !exitVtxos.isEmpty else {
            print("⚠️ [LiveActivity] No VTXOs provided, skipping start")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚠️ [LiveActivity] Live Activities not enabled by user")
            return
        }

        if Self.activeActivity != nil {
            print("ℹ️ [LiveActivity] Activity already running — refreshing instead")
            await updateAllLiveActivities()
            return
        }

        let exitCount = exitVtxos.count
        let attributes = ExitProgressActivityAttributes(
            exitId: UUID().uuidString,
            exitCount: exitCount,
            startTime: Date()
        )

        // Initial estimate: each exit starts at step 1 of ~5 steps.
        // Will be updated immediately by the next updateAllLiveActivities call.
        let estimatedTotal = max(1, exitCount * 5)
        let initialState = ExitProgressActivityAttributes.ContentState(
            currentStep: exitCount,
            totalSteps: estimatedTotal,
            stepDescription: exitCount > 1 ? "Moving \(exitCount) outputs to savings" : "Moving to savings",
            transactionsConfirmed: 0,
            totalTransactions: exitCount,
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
            Self.activeActivity = activity
            print("✅ [LiveActivity] Started activity for \(exitCount) VTXO(s)")
        } catch {
            print("❌ [LiveActivity] Failed to start activity: \(error)")
        }
    }

    /// End the Live Activity with a final summary state.
    func endLiveActivity(success: Bool) async {
        guard let activity = Self.activeActivity else {
            print("⚠️ [LiveActivity] No active activity to end")
            return
        }

        let current = activity.content.state
        let finalState = ExitProgressActivityAttributes.ContentState(
            currentStep: success ? current.totalSteps : current.currentStep,
            totalSteps: current.totalSteps,
            stepDescription: success ? "Move complete!" : "Move stopped",
            transactionsConfirmed: current.totalTransactions,
            totalTransactions: current.totalTransactions,
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
            dismissalPolicy: .after(.now + 3600)
        )

        Self.activeActivity = nil
        print("✅ [LiveActivity] Ended activity (success: \(success))")

        await ExitProgressionNotifications.shared.cancelAllCheckInReminders()
    }

    // MARK: - Relaunch Reattachment

    /// Reattach to any surviving Live Activity on app launch and bring it up to date.
    func reattachToExistingActivities() async {
        if let existing = Activity<ExitProgressActivityAttributes>.activities.first {
            Self.activeActivity = existing
            print("✅ [LiveActivity] Reattached to existing activity")
        }
        await recreateMissingActivities()
        await updateAllLiveActivities()
    }

    /// Create a Live Activity if exits are in flight but no activity is running
    /// (e.g. after an app rebuild or a crash mid-exit). Must filter with
    /// `isInFlight`, not `isActive`: claimed and cancelled exits stay in bark's
    /// exit list forever, so an already-finished batch would otherwise respawn
    /// a "complete" activity on every launch.
    private func recreateMissingActivities() async {
        guard Self.activeActivity == nil else { return }
        do {
            let exitVtxos = try await wallet.getExitVtxos().filter { $0.isInFlight }
            guard !exitVtxos.isEmpty else { return }
            print("🆕 [LiveActivity] Recreating missing activity for \(exitVtxos.count) exit(s)")
            await startLiveActivity(for: exitVtxos)
        } catch {
            print("⚠️ [LiveActivity] Failed to recreate missing activity: \(error)")
        }
    }

    // MARK: - Aggregate Update

    /// Fetch all exit statuses, build an aggregate progress, and push one update
    /// to the single Live Activity. Ends the activity when all exits are terminal.
    func updateAllLiveActivities() async {
        guard Self.activeActivity != nil else { return }

        do {
            let exitVtxos = try await wallet.getExitVtxos()

            var statuses: [ExitTransactionStatus] = []
            for vtxo in exitVtxos {
                guard let status = try await wallet.getExitStatus(
                    vtxoId: vtxo.vtxoId,
                    includeHistory: false,
                    includeTransactions: true
                ) else { continue }
                statuses.append(status)
            }

            let aggregate = ExitProgress(statuses: statuses)

            switch aggregate.phase {
            case .complete:
                await endLiveActivity(success: true)
            case .cancelled where exitVtxos.isEmpty:
                // All VTXOs gone from exit list — treat as complete
                await endLiveActivity(success: true)
            case .cancelled:
                // All remaining exits cancelled (vtxoAlreadySpent)
                await endLiveActivity(success: false)
            default:
                let activeCount = statuses.filter { status in
                    guard let parsed = status.parsedState else { return true }
                    if case .vtxoAlreadySpent = parsed { return false }
                    return true
                }.count

                var contentState = buildContentState(
                    from: statuses,
                    exitCount: activeCount,
                    needsCheckIn: false
                )

                // Override description if any movement is fee-blocked
                if let blocked = statuses.compactMap({ walletManager?.getExitBlockedInfo(for: $0.vtxoId) }).first {
                    contentState.stepDescription = Self.pausedDescription(for: blocked.reason)
                }

                await Self.activeActivity?.update(
                    ActivityContent(
                        state: contentState,
                        staleDate: Date().addingTimeInterval(120 * 60)
                    )
                )
                print("✅ [LiveActivity] Updated (step \(aggregate.currentStep)/\(aggregate.totalSteps), phase: \(aggregate.phase))")
            }

            await cleanupDismissedActivities()

        } catch {
            print("❌ [LiveActivity] Failed to update activity: \(error)")
        }
    }

    // MARK: - User Check-In Handler

    /// Called when the user taps a check-in notification or opens the app.
    func userCheckedIn() async {
        print("👤 [LiveActivity] User checked in")
        await checkAndProgressExits()
        await walletManager?.refreshAfterVTXOChange()
        await updateAllLiveActivities()
        await ExitProgressionNotifications.shared.scheduleCheckInSequence()
    }

    // MARK: - Cleanup

    /// Remove the activity reference if the user dismissed it from the lock screen.
    func cleanupDismissedActivities() async {
        guard let current = Self.activeActivity else { return }
        let stillActive = Activity<ExitProgressActivityAttributes>.activities
        if !stillActive.contains(where: { $0.id == current.id }) {
            Self.activeActivity = nil
            print("🗑️ [LiveActivity] Activity dismissed by user")
        }
    }

    /// Whether there is currently a Live Activity running.
    func hasActiveExits() async -> Bool {
        return Self.activeActivity != nil
    }

    // MARK: - Content State Building

    private func buildContentState(
        from statuses: [ExitTransactionStatus],
        exitCount: Int,
        needsCheckIn: Bool
    ) -> ExitProgressActivityAttributes.ContentState {
        let aggregate = ExitProgress(statuses: statuses)

        let totalTransactions = statuses.reduce(0) { $0 + max(1, Int($1.transactionCount)) }
        let transactionsConfirmed = statuses.reduce(0) { $0 + countConfirmedTransactions($1) }

        let currentBlockHeight = statuses.compactMap { extractCurrentBlockHeight($0.parsedState) }.max()
        let targetBlockHeight = aggregate.claimableHeight
        let blocksRemaining: Int? = {
            guard let target = targetBlockHeight, let current = currentBlockHeight else { return nil }
            return max(0, Int(target) - Int(current))
        }()

        return ExitProgressActivityAttributes.ContentState(
            currentStep: aggregate.currentStep,
            totalSteps: max(1, aggregate.totalSteps),
            stepDescription: stepDescription(for: aggregate, exitCount: exitCount),
            transactionsConfirmed: transactionsConfirmed,
            totalTransactions: totalTransactions,
            exitState: Self.exitState(for: aggregate.phase),
            lastUpdated: Date(),
            needsCheckIn: needsCheckIn,
            currentBlockHeight: currentBlockHeight,
            targetBlockHeight: targetBlockHeight,
            blocksRemaining: blocksRemaining,
            isWaitingForBlocks: aggregate.phase == .waiting,
            isClaimable: aggregate.phase == .waiting,
            isClaimed: aggregate.phase == .complete,
            hasError: false
        )
    }

    private func stepDescription(for progress: ExitProgress, exitCount: Int) -> String {
        switch progress.phase {
        case .preparing:
            return exitCount > 1 ? "Moving \(exitCount) outputs to savings" : "Moving to savings"
        case .confirming:
            return "Confirming transactions"
        case .waiting:
            return "Waiting for timelock"
        case .claiming:
            return "Claiming automatically"
        case .complete:
            return exitCount > 1 ? "Moves complete" : "Move complete"
        case .cancelled:
            return "Move stopped"
        }
    }

    private static func exitState(for phase: ExitProgress.Phase) -> ExitState {
        switch phase {
        case .preparing:  return .start
        case .confirming: return .processing
        case .waiting:    return .awaitingDelta
        case .claiming:   return .claimInProgress
        case .complete:   return .claimed
        case .cancelled:  return .start
        }
    }

    private static func pausedDescription(for reason: ExitBlockedReason) -> String {
        switch reason {
        case .insufficientOnchainFunds: return "Paused — add onchain funds to continue"
        case .claimFeeExceedsOutput:    return "Paused — network fees too high"
        case .other:                    return "Paused — will retry automatically"
        }
    }

    private func countConfirmedTransactions(_ status: ExitTransactionStatus) -> Int {
        guard let parsed = ExitStatusParser.parseState(status.state) else { return 0 }
        if case .processing(let state) = parsed {
            return state.transactions.filter {
                if case .confirmed = $0.status { return true }
                return false
            }.count
        }
        return 0
    }

    private func extractCurrentBlockHeight(_ parsed: ParsedExitState?) -> UInt32? {
        guard let parsed else { return nil }
        switch parsed {
        case .start(let s):          return s.tipHeight
        case .processing(let s):     return s.tipHeight
        case .awaitingDelta(let s):  return s.tipHeight
        case .claimable(let s):      return s.tipHeight
        case .claimInProgress(let s): return s.tipHeight
        case .claimed(let s):        return s.tipHeight
        case .vtxoAlreadySpent(let s): return s.tipHeight
        case .unparsed:              return nil
        }
    }
}

#endif
