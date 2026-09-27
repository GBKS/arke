# Live Activity for Exit Progression - Implementation Plan

> **📦 Archived 2026-07-09.** Implementation shipped 2026-05-12/13 ("Add Live Activity and local notifications for exits"). All planned files exist: `ExitProgressActivityAttributes.swift`, `ExitProgressionService+LiveActivity.swift`, `ExitProgressionNotifications.swift` (Shared), plus the lock-screen and Dynamic Island UI in the `ArkeWidgets` widget target. The checklist at the bottom was never ticked off — it's all done.

**Date:** 2026-05-11  
**Status:** ✅ Shipped 2026-05-12 (header previously said Planning)  
**Platform:** iOS 16.1+

---

## Executive Summary

This document outlines the implementation plan for adding Live Activity support to the exit progression system in Arke. Live Activities will provide persistent, always-visible status updates on the lock screen and Dynamic Island during the multi-hour Force Move to Savings process.

**Core Strategy:** Live Activities provide status display, while local notifications provide reliable check-in reminders. The user opening the app progresses exits and updates the Live Activity.

### Implementation Scope

**Existing Infrastructure (Already in Place):**
- ✅ **Notification handling** (`AppDelegate_iOS.swift` with `UNUserNotificationCenterDelegate`)
  - Foreground presentation, tap handling, remote notification processing
  - Currently handles CloudKit and mailbox notifications
- ✅ **Scene lifecycle monitoring** (`ArkeMobile.swift` with `scenePhase` tracking)
  - Already monitors background/foreground transitions
  - Currently triggers wallet backup on background
- ✅ **Notification permissions** (`SettingsView_iOS.swift`)
  - Full permission request flow with error handling
  - Settings toggle for notification enable/disable
- ✅ **Exit progression service** (`ExitProgressionService.swift`)
  - Timer-based checks every 5 minutes
  - Auto-progression and auto-claiming
  - Manual trigger support
- ✅ **Exit state parsing** (`ExitStatusParser.swift`)
  - Parses complex SDK states into readable format
  - Transaction chain analysis
- ✅ **WalletManager integration** (`WalletManager.swift`)
  - Exit progression service already instantiated (line 108)
  - Cache management for exit VTXOs (lines 125-131)

**Minimal Changes Required:**
- **4 existing files** to modify (~45 lines total)
  - AppDelegate_iOS.swift: +15 lines (add exit notification handling)
  - ArkeMobile.swift: +10 lines (add foreground activation)
  - Info.plist: +1 key (enable Live Activities)
  - ExitProgressionService.swift: +20 lines (integrate updates)
- **6 new files** to create (all Live Activity-specific code)
- **1 Widget Extension target** to add in Xcode

**Why This is Simple:**
The existing notification and lifecycle infrastructure is excellent. We're just adding exit-specific handlers alongside the existing mailbox notification handlers. Most code is net-new (Live Activity UI and logic), not modifications to existing code.

### Key Integration Points

**Where to Start Live Activity:**
- `ExitView_iOS.swift` line 428 in `startExit()` method
- After `manager.startExit()` succeeds, call `startLiveActivity(for: exitVtxos)`
- Check notification permission first if not already granted

**Where to Handle Notification Taps:**
- `AppDelegate_iOS.swift` line 164 in `userNotificationCenter(_:didReceive:)`
- Add case for `action == "check_exit_progress"` alongside existing mailbox handling

**Where to Handle Foreground Activation:**
- `ArkeMobile.swift` line 125 in `.onChange(of: scenePhase)`
- Add `else if newPhase == .active` case alongside existing background handler

**Where Exit Progression Happens:**
- `ExitProgressionService.swift` line 120 in `checkAndProgressExits()`
- Already runs every 5 minutes when app is in foreground
- Add Live Activity update calls here

### Why Live Activity + Local Notifications is the Right Approach

1. **Long-running process**: Exits involve 4-8 onchain transactions over many hours (2-8 hours total)
2. **Critical timing**: Users need to check in every ~1.5 hours to progress exits
3. **iOS background limitations**: Live Activities cannot wake the app or execute code
4. **Reliable reminders**: Local notifications have 99%+ delivery reliability
5. **Beautiful status display**: Live Activity shows current state when fresh
6. **No server required**: Local notifications work without backend infrastructure
7. **Battery friendly**: No background processing, just passive display + notification delivery

---

## Current System Analysis

### ExitProgressionService (Arke/Shared/Services/ExitProgressionService.swift:31)

**Current Design:**
- Timer-based: Checks every 5 minutes (configurable)
- Foreground only: Pauses when app backgrounds
- Automatic: Handles full lifecycle from Start → Claimed
- SDK-driven: Polls Bark SDK, which manages complex exit state machine

**Exit Flow (Fully Automatic):**
1. User starts exit → SDK creates exit transactions (fee pre-approved)
2. Service auto-progresses: Start → Processing → AwaitingDelta → Claimable
3. Service auto-claims: Claimable → ClaimInProgress → Claimed
4. Exit complete - funds moved to onchain wallet

**Key Operations:**
- `checkAndProgressExits()`: Main progression loop (runs every 5 min)
- `progressExitsManually()`: Manual trigger for UI buttons
- `autoClaimExits()`: Automatically claims when VTXOs become claimable

### Exit States (Parsed from Bark SDK)

**Primary States:**
- `Start`: Exit initiated, waiting for first broadcast
- `Processing`: Transactions being broadcast/confirmed (has transaction chain)
- `AwaitingDelta`: Waiting for block height delta before claimable
- `Claimable`: Ready to claim funds
- `ClaimInProgress`: Claim transaction broadcast
- `Claimed`: Exit complete, funds claimed

**Transaction States:**
- `VerifyInputs`: Verifying transaction inputs
- `NeedsSignedPackage`: Needs transaction signing
- `NeedsBroadcasting`: Ready to broadcast
- `BroadcastWithCpfp`: Broadcast with CPFP (Child Pays For Parent)
- `AwaitingInputConfirmation`: Waiting for parent tx confirmation
- `Confirmed`: Transaction confirmed onchain

### Current UI Components

1. **ExitStatusDetailView_iOS**: Full detailed view of exit status
   - Shows parsed state, transaction chain, confirmation status
   - VTXO information and amounts
   
2. **TransactionExitDetailsView**: Expandable section in transaction detail
   - Summary of VTXOs exiting
   - Individual VTXO details
   - Linked onchain transactions

3. **Data Views**: Various exit-related data views
   - `UnilateralExitListView_iOS`: List all active exits
   - `ExitVtxoRowView_iOS`: Individual VTXO row
   - `ActiveExitAlertView_iOS`: Alert for active exits

---

## Proposed Architecture

### 1. Live Activity Structure

```swift
// New file: Arke/ArkeMobile/LiveActivity/ExitProgressActivityAttributes.swift

import ActivityKit
import Foundation

struct ExitProgressActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Current exit state
        var currentStep: ExitStep
        var totalSteps: Int
        var stepDescription: String
        
        // Transaction progress
        var transactionsConfirmed: Int
        var totalTransactions: Int
        
        // Timing information
        var lastUpdated: Date
        var needsCheckIn: Bool  // Indicates staleness, user should check in
        
        // Block information (optional, for advanced users)
        var currentBlockHeight: UInt32?
        var targetBlockHeight: UInt32?
        var blocksRemaining: Int?
        
        // Status indicators
        var isWaitingForBlocks: Bool
        var isClaimable: Bool
        var hasError: Bool
        var errorMessage: String?
    }
    
    // Static data (doesn't change during the activity)
    var exitId: String  // Primary VTXO ID or exit batch identifier
    var exitCount: Int  // Number of VTXOs being exited (for multiple exits)
    var startTime: Date
}

enum ExitStep: Int, Codable {
    case start = 1
    case broadcasting = 2
    case confirming = 3
    case awaitingDelta = 4
    case claiming = 5
    case completed = 6
    
    var displayName: String {
        switch self {
        case .start: return "Starting"
        case .broadcasting: return "Broadcasting"
        case .confirming: return "Confirming"
        case .awaitingDelta: return "Waiting"
        case .claiming: return "Claiming"
        case .completed: return "Complete"
        }
    }
}
```

### 2. Live Activity Widget

```swift
// New file: Arke/ArkeMobile/LiveActivity/ExitProgressLiveActivity.swift

import ActivityKit
import WidgetKit
import SwiftUI

struct ExitProgressLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExitProgressActivityAttributes.self) { context in
            // Lock screen / banner UI
            ExitProgressLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded region
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.needsCheckIn ? 
                        "exclamationmark.circle.fill" : "arrow.down.circle")
                        .foregroundColor(context.state.needsCheckIn ? .orange : .blue)
                        .symbolEffect(.bounce, value: context.state.needsCheckIn)
                }
                
                DynamicIslandExpandedRegion(.center) {
                    VStack {
                        Text(context.state.stepDescription)
                            .font(.headline)
                        if context.state.needsCheckIn {
                            Text("Check app to continue")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text("\(context.state.transactionsConfirmed)/\(context.state.totalTransactions)")
                            .font(.caption)
                        Text("confirmed")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        ProgressView(value: Double(context.state.currentStep.rawValue), 
                                    total: Double(context.state.totalSteps))
                        Text("\(context.state.currentStep.rawValue)/\(context.state.totalSteps)")
                            .font(.caption)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.needsCheckIn ? 
                    "exclamationmark.triangle.fill" : "arrow.down.circle")
                    .foregroundColor(context.state.needsCheckIn ? .orange : .blue)
            } compactTrailing: {
                Text("\(context.state.currentStep.rawValue)/\(context.state.totalSteps)")
                    .font(.caption2)
            } minimal: {
                Image(systemName: context.state.needsCheckIn ? 
                    "exclamationmark.circle.fill" : "arrow.down.circle.fill")
                    .foregroundColor(context.state.needsCheckIn ? .orange : .blue)
            }
        }
    }
}
```

### 3. Integration with ExitProgressionService

**Enhanced Service Methods:**

```swift
// Add to ExitProgressionService

/// Active Live Activity for exit progression
private var currentActivity: Activity<ExitProgressActivityAttributes>?

/// Start Live Activity when exit begins
func startLiveActivity(for exitVtxos: [ExitVtxo]) async {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        print("⚠️ Live Activities not enabled")
        return
    }
    
    let attributes = ExitProgressActivityAttributes(
        exitId: exitVtxos.first?.vtxoId ?? "unknown",
        exitCount: exitVtxos.count,
        startTime: Date()
    )
    
    let initialState = ExitProgressActivityAttributes.ContentState(
        currentStep: .start,
        totalSteps: 6,
        stepDescription: exitVtxos.count > 1 ? "Starting move (\(exitVtxos.count) outputs)" : "Starting move to savings",
        transactionsConfirmed: 0,
        totalTransactions: 0,
        lastUpdated: Date(),
        needsCheckIn: false,
        isWaitingForBlocks: false,
        isClaimable: false,
        hasError: false
    )
    
    do {
        currentActivity = try Activity.request(
            attributes: attributes,
            content: .init(state: initialState, staleDate: nil)
        )
        print("✅ Live Activity started: \(currentActivity?.id ?? "unknown")")
    } catch {
        print("❌ Failed to start Live Activity: \(error)")
    }
}

/// Update Live Activity with current exit state
func updateLiveActivity(with status: ExitTransactionStatus) async {
    guard let activity = currentActivity else { return }
    
    let contentState = buildContentState(from: status)
    
    await activity.update(
        ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(10 * 60) // Stale after 10 min
        )
    )
}

/// End Live Activity when exit completes
func endLiveActivity(success: Bool) async {
    guard let activity = currentActivity else { return }
    
    let finalState = ExitProgressActivityAttributes.ContentState(
        currentStep: success ? .completed : .start,
        totalSteps: 6,
        stepDescription: success ? "Move completed!" : "Move stopped",
        transactionsConfirmed: 0,
        totalTransactions: 0,
        lastCheckTime: Date(),
        isWaitingForBlocks: false,
        isClaimable: false,
        hasError: !success
    )
    
    await activity.end(
        ActivityContent(state: finalState, staleDate: nil),
        dismissalPolicy: .after(.now + 3600) // Dismiss after 1 hour
    )
    
    currentActivity = nil
}

/// Build ContentState from ExitTransactionStatus
private func buildContentState(from status: ExitTransactionStatus, needsCheckIn: Bool = false) -> ExitProgressActivityAttributes.ContentState {
    // Parse status to determine current step, progress, etc.
    let parsed = ExitStatusParser.parseState(status.state)
    
    let (step, description, isWaiting, isClaimable) = parseExitState(parsed)
    
    return ExitProgressActivityAttributes.ContentState(
        currentStep: step,
        totalSteps: 6,
        stepDescription: description,
        transactionsConfirmed: countConfirmedTransactions(status),
        totalTransactions: status.transactionCount,
        lastUpdated: Date(),
        needsCheckIn: needsCheckIn,
        currentBlockHeight: extractCurrentBlockHeight(parsed),
        targetBlockHeight: extractTargetBlockHeight(parsed),
        blocksRemaining: extractBlocksRemaining(parsed),
        isWaitingForBlocks: isWaiting,
        isClaimable: isClaimable,
        hasError: false
    )
}

private func parseExitState(_ parsed: ParsedExitState?) -> (ExitStep, String, Bool, Bool) {
    guard let parsed = parsed else {
        return (.start, "Processing...", false, false)
    }
    
    switch parsed {
    case .start:
        return (.start, "Starting move to savings", false, false)
    case .processing:
        return (.broadcasting, "Broadcasting transactions", false, false)
    case .awaitingDelta(let data):
        let blocksLeft = data.claimableHeight > data.tipHeight ? 
            data.claimableHeight - data.tipHeight : 0
        return (.awaitingDelta, "Waiting for \(blocksLeft) blocks", true, false)
    case .claimable:
        return (.claiming, "Claiming funds", false, true)
    case .claimInProgress:
        return (.claiming, "Claim transaction confirming", false, false)
    case .claimed:
        return (.completed, "Move complete", false, false)
    case .unparsed:
        return (.start, "Processing...", false, false)
    }
}
```

**Modified checkAndProgressExits():**

```swift
private func checkAndProgressExits() async {
    // ... existing code ...
    
    // Update Live Activity if active
    if let currentActivity = currentActivity {
        let exitVtxos = try? await wallet.getExitVtxos()
        if let firstVtxo = exitVtxos?.first {
            if let status = try? await wallet.getExitStatus(
                vtxoId: firstVtxo.vtxoId,
                includeHistory: false,
                includeTransactions: true
            ) {
                await updateLiveActivity(with: status)
            }
        }
    }
    
    // Check if all exits completed
    let hasPending = try? await wallet.hasPendingExits()
    if hasPending == false && currentActivity != nil {
        await endLiveActivity(success: true)
    }
}
```

### 4. Lock Screen View with Check-In State

```swift
// New file: Arke/ArkeMobile/LiveActivity/ExitProgressLockScreenView.swift

import ActivityKit
import SwiftUI

struct ExitProgressLockScreenView: View {
    let context: ActivityViewContext<ExitProgressActivityAttributes>
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: context.state.needsCheckIn ? 
                    "exclamationmark.circle.fill" : "arrow.down.circle")
                    .foregroundColor(context.state.needsCheckIn ? .orange : .blue)
                
                Text(context.state.stepDescription)
                    .font(.headline)
                
                Spacer()
            }
            
            // Progress bar
            ProgressView(value: Double(context.state.currentStep.rawValue), 
                        total: Double(context.state.totalSteps))
                .tint(context.state.needsCheckIn ? .orange : .blue)
            
            HStack {
                Text("Step \(context.state.currentStep.rawValue) of \(context.state.totalSteps)")
                    .font(.caption)
                Spacer()
                if context.state.needsCheckIn {
                    Text("⚠️ Check-in needed")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("\(context.state.transactionsConfirmed)/\(context.state.totalTransactions) confirmed")
                        .font(.caption)
                }
            }
            
            // Time since last update
            HStack {
                Image(systemName: "clock")
                    .font(.caption2)
                Text("Updated \(context.state.lastUpdated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if context.state.needsCheckIn {
                    Text("Tap notification to update")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
}
```

### 5. Coordinated Service Implementation

**Primary Strategy:** Live Activity + Local Notifications working together.

```swift
// Add to ExitProgressionService

class ExitProgressionService {
    
    private var currentActivity: Activity<ExitProgressActivityAttributes>?
    private var scheduledNotificationIds: [String] = []
    private var lastCheckTime: Date?
    
    // MARK: - Start Exit Monitoring
    
    func startExitMonitoring(for exitVtxos: [ExitVtxo]) async {
        print("🚀 Starting exit monitoring for \(exitVtxos.count) VTXO(s)")
        
        // Start Live Activity
        await startLiveActivity(for: exitVtxos)
        
        // Schedule check-in reminder sequence
        await scheduleCheckInSequence()
    }
    
    // MARK: - Check-In Notification Sequence
    
    private func scheduleCheckInSequence() async {
        // Clear any existing notifications
        cancelAllCheckInReminders()
        
        // Schedule reminders at 90-minute intervals
        let intervals: [TimeInterval] = [
            90 * 60,      // 1.5 hours
            90 * 60,      // 3.0 hours
            90 * 60,      // 4.5 hours
            90 * 60,      // 6.0 hours
            90 * 60       // 7.5 hours
        ]
        
        var cumulativeTime: TimeInterval = 0
        for (index, interval) in intervals.enumerated() {
            cumulativeTime += interval
            let notificationDate = Date().addingTimeInterval(cumulativeTime)
            
            let id = await scheduleCheckInNotification(
                at: notificationDate,
                checkNumber: index + 1
            )
            scheduledNotificationIds.append(id)
        }
        
        print("✅ Scheduled \(intervals.count) check-in reminders")
    }
    
    private func scheduleCheckInNotification(at date: Date, checkNumber: Int) async -> String {
        let id = "exit-check-\(UUID().uuidString)"
        
        let content = UNMutableNotificationContent()
        content.title = "Force Move Progress Check-In"
        content.body = "Tap to check on your force move and keep it moving"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1.0
        
        // Action category for future interactive notifications
        content.categoryIdentifier = "EXIT_PROGRESS"
        
        // Deep link data
        content.userInfo = [
            "action": "check_exit_progress",
            "checkNumber": checkNumber,
            "scheduledFor": date.timeIntervalSince1970
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: date.timeIntervalSinceNow,
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("📅 Scheduled check-in #\(checkNumber) for \(date)")
        } catch {
            print("❌ Failed to schedule notification: \(error)")
        }
        
        return id
    }
    
    // MARK: - User Check-In Handler
    
    func userCheckedIn() async {
        print("👤 User checked in")
        lastCheckTime = Date()
        
        // Progress exits
        await checkAndProgressExits()
        
        // Update Live Activity to "fresh" state
        await updateLiveActivityAfterCheckIn()
        
        // Reschedule notifications (reset the clock)
        await scheduleCheckInSequence()
    }
    
    private func updateLiveActivityAfterCheckIn() async {
        guard let activity = currentActivity else { return }
        
        // Get latest exit status
        guard let status = try? await getLatestExitStatus() else {
            print("⚠️ Could not get exit status for Live Activity update")
            return
        }
        
        let contentState = buildContentState(
            from: status,
            needsCheckIn: false  // User just checked in!
        )
        
        await activity.update(
            ActivityContent(
                state: contentState,
                staleDate: Date().addingTimeInterval(120 * 60) // Stale in 2 hours
            )
        )
        
        print("✅ Live Activity updated (fresh)")
    }
    
    // MARK: - Staleness Detection
    
    func markLiveActivityAsNeedingCheckIn() async {
        guard let activity = currentActivity else { return }
        
        let currentState = await activity.contentState
        
        // Only update if not already marked
        guard !currentState.needsCheckIn else { return }
        
        var updatedState = currentState
        updatedState.needsCheckIn = true
        
        await activity.update(
            ActivityContent(state: updatedState, staleDate: nil)
        )
        
        print("⚠️ Marked Live Activity as needing check-in")
    }
    
    // MARK: - Cleanup
    
    private func cancelAllCheckInReminders() {
        guard !scheduledNotificationIds.isEmpty else { return }
        
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: scheduledNotificationIds)
        
        print("🗑️ Cancelled \(scheduledNotificationIds.count) pending notifications")
        scheduledNotificationIds.removeAll()
    }
    
    func stopExitMonitoring(success: Bool) async {
        print("🛑 Stopping exit monitoring (success: \(success))")
        
        await endLiveActivity(success: success)
        cancelAllCheckInReminders()
    }
    
    // MARK: - Helper Methods
    
    private func buildContentState(from status: ExitTransactionStatus, needsCheckIn: Bool) -> ExitProgressActivityAttributes.ContentState {
        let parsed = ExitStatusParser.parseState(status.state)
        let (step, description, isWaiting, isClaimable) = parseExitState(parsed)
        
        return ExitProgressActivityAttributes.ContentState(
            currentStep: step,
            totalSteps: 6,
            stepDescription: description,
            transactionsConfirmed: countConfirmedTransactions(status),
            totalTransactions: status.transactionCount,
            lastUpdated: Date(),
            needsCheckIn: needsCheckIn,
            currentBlockHeight: extractCurrentBlockHeight(parsed),
            targetBlockHeight: extractTargetBlockHeight(parsed),
            blocksRemaining: extractBlocksRemaining(parsed),
            isWaitingForBlocks: isWaiting,
            isClaimable: isClaimable,
            hasError: false
        )
    }
}
```

### 6. Multiple Concurrent Exits Strategy

**Design Decision:** Support **multiple Live Activities** simultaneously, one per exit batch.

**Why Multiple Activities:**
- Users may initiate separate exits at different times
- Each exit has its own timeline and state
- Better visibility into individual exit progress
- iOS supports multiple Live Activities per app

**Implementation:**

```swift
// Track multiple activities by exit ID
private var activeActivities: [String: Activity<ExitProgressActivityAttributes>] = [:]

/// Start Live Activity for a specific exit batch
func startLiveActivity(for exitVtxos: [ExitVtxo]) async {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        print("⚠️ Live Activities not enabled")
        return
    }
    
    // Use first VTXO ID as the batch identifier
    let exitId = exitVtxos.first?.vtxoId ?? UUID().uuidString
    
    // Check if we already have an activity for this exit
    if activeActivities[exitId] != nil {
        print("⚠️ Live Activity already exists for exit \(exitId)")
        return
    }
    
    let attributes = ExitProgressActivityAttributes(
        exitId: exitId,
        exitCount: exitVtxos.count,
        startTime: Date()
    )
    
    let initialState = ExitProgressActivityAttributes.ContentState(
        currentStep: .start,
        totalSteps: 6,
        stepDescription: exitVtxos.count > 1 ? "Moving \(exitVtxos.count) outputs" : "Moving to savings",
        transactionsConfirmed: 0,
        totalTransactions: 0,
        lastUpdated: Date(),
        needsCheckIn: false,
        isWaitingForBlocks: false,
        isClaimable: false,
        hasError: false
    )
    
    do {
        let activity = try Activity.request(
            attributes: attributes,
            content: .init(state: initialState, staleDate: nil)
        )
        activeActivities[exitId] = activity
        print("✅ Live Activity started for exit \(exitId)")
    } catch {
        print("❌ Failed to start Live Activity: \(error)")
    }
}

/// Update Live Activity for a specific exit
func updateLiveActivity(exitId: String, with status: ExitTransactionStatus) async {
    guard let activity = activeActivities[exitId] else {
        print("⚠️ No active Live Activity found for exit \(exitId)")
        return
    }
    
    let contentState = buildContentState(from: status, needsCheckIn: false)
    
    await activity.update(
        ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(120 * 60) // Stale in 2 hours
        )
    )
}

/// End Live Activity for a specific exit
func endLiveActivity(exitId: String, success: Bool) async {
    guard let activity = activeActivities[exitId] else {
        print("⚠️ No active Live Activity found for exit \(exitId)")
        return
    }
    
    let finalState = ExitProgressActivityAttributes.ContentState(
        currentStep: success ? .completed : .start,
        totalSteps: 6,
        stepDescription: success ? "Move completed!" : "Move stopped",
        transactionsConfirmed: 0,
        totalTransactions: 0,
        lastUpdated: Date(),
        needsCheckIn: false,
        isWaitingForBlocks: false,
        isClaimable: false,
        hasError: !success
    )
    
    await activity.end(
        ActivityContent(state: finalState, staleDate: nil),
        dismissalPolicy: .after(.now + 3600) // Dismiss after 1 hour
    )
    
    activeActivities.removeValue(forKey: exitId)
    print("✅ Live Activity ended for exit \(exitId)")
}

/// Reattach to existing activities on app launch
func reattachToExistingActivities() async {
    for activity in Activity<ExitProgressActivityAttributes>.activities {
        let exitId = activity.attributes.exitId
        activeActivities[exitId] = activity
        print("✅ Reattached to existing Live Activity for exit \(exitId)")
    }
}

/// Clean up dismissed activities
func cleanupDismissedActivities() async {
    let currentActivityIds = Set(Activity<ExitProgressActivityAttributes>.activities.map { $0.attributes.exitId })
    
    for (exitId, _) in activeActivities {
        if !currentActivityIds.contains(exitId) {
            activeActivities.removeValue(forKey: exitId)
            print("🗑️ Removed dismissed activity for exit \(exitId)")
        }
    }
}
```

**Modified checkAndProgressExits():**

```swift
private func checkAndProgressExits() async {
    // ... existing code ...
    
    // Update all active Live Activities
    if !activeActivities.isEmpty {
        let exitVtxos = try? await wallet.getExitVtxos()
        
        // Group VTXOs by their exit batch (for now, treat each VTXO as separate)
        for vtxo in exitVtxos ?? [] {
            let exitId = vtxo.vtxoId
            
            if activeActivities[exitId] != nil {
                if let status = try? await wallet.getExitStatus(
                    vtxoId: exitId,
                    includeHistory: false,
                    includeTransactions: true
                ) {
                    await updateLiveActivity(exitId: exitId, with: status)
                }
            }
        }
    }
    
    // Check for completed exits and end their activities
    for (exitId, _) in activeActivities {
        let vtxo = try? await wallet.getExitVtxos().first { $0.vtxoId == exitId }
        if vtxo == nil {
            // Exit is complete (VTXO no longer in exit list)
            await endLiveActivity(exitId: exitId, success: true)
        }
    }
    
    // Clean up any dismissed activities
    await cleanupDismissedActivities()
}
```

**Notification Strategy for Multiple Exits:**
- Each exit gets its own notification schedule
- Notifications include exit identifier in userInfo
- User tapping notification progresses all exits (simpler UX)
- Live Activities update individually

**iOS Limitations:**
- iOS supports up to 8 concurrent Live Activities per app
- If user starts more than 8 exits, older activities will be dismissed
- This is acceptable for Arke's use case (unlikely to have >8 concurrent exits)

### 7. Integration with Existing Infrastructure

**Good News:** Arke already has excellent notification and scene lifecycle infrastructure in place!

#### Existing Infrastructure (No Changes Needed)

**AppDelegate_iOS.swift:**
- ✅ `UNUserNotificationCenterDelegate` already set up
- ✅ `userNotificationCenter(_:willPresent:)` handles foreground notifications
- ✅ `userNotificationCenter(_:didReceive:)` handles notification taps
- ✅ Currently handles CloudKit and mailbox notifications

**ArkeMobile.swift:**
- ✅ `@UIApplicationDelegateAdaptor` connects AppDelegate
- ✅ `@Environment(\.scenePhase)` tracks scene transitions
- ✅ `.onChange(of: scenePhase)` already monitors background/foreground

#### Required Changes (Minimal)

**1. AppDelegate_iOS.swift - Add Exit Notification Handling**

Add to existing `userNotificationCenter(_:didReceive:)` method (after line 185):

```swift
// EXISTING CODE (lines 164-185):
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
) {
    let userInfo = response.notification.request.content.userInfo
    
    Self.logger.info("User tapped notification")
    Self.logger.debug("Notification tap payload: \(String(describing: userInfo))")
    
    // Check if this is a mailbox notification
    if let notificationType = userInfo["type"] as? String,
       notificationType.contains("mailbox") {
        Self.logger.info("User tapped mailbox notification - posting NotificationCenter event")
        
        NotificationCenter.default.post(
            name: .mailboxUpdateReceived,
            object: nil
        )
        Self.logger.debug("NotificationCenter.post completed")
    }
    
    // ADD THIS: Check for exit progress check-in notification
    if let action = userInfo["action"] as? String,
       action == "check_exit_progress" {
        Self.logger.info("User tapped exit check-in notification")
        
        // Post notification for exit progression service
        NotificationCenter.default.post(
            name: .exitCheckInReceived,
            object: nil
        )
    }
    
    completionHandler()
}
```

Add to Notification.Name extension (after line 198):

```swift
extension Notification.Name {
    /// Posted when APNs token is received
    static let apnsTokenReceived = Notification.Name("apnsTokenReceived")
    
    /// Posted when mailbox update notification is received
    static let mailboxUpdateReceived = Notification.Name("mailboxUpdateReceived")
    
    /// Posted when user taps exit check-in notification (NEW)
    static let exitCheckInReceived = Notification.Name("exitCheckInReceived")
}
```

**2. ArkeMobile.swift - Add Foreground Activation Handler**

Modify existing `.onChange(of: scenePhase)` (lines 125-131):

```swift
// EXISTING CODE:
.onChange(of: scenePhase) { oldPhase, newPhase in
    if newPhase == .background {
        Task {
            await (walletManager.wallet as? BarkWalletFFI)?.backupWallet()
        }
    }
    // ADD THIS: Handle foreground activation with active exits
    else if newPhase == .active && oldPhase == .background {
        Task {
            // Check if we have active exits and progress them
            if let service = walletManager.exitProgressionService,
               await service.hasActiveExits() {
                await service.userCheckedIn()
            }
        }
    }
}
```

**3. Info.plist - Enable Live Activities**

Add one key-value pair:

```xml
<!-- Add to Arke/ArkeMobile/Info.plist -->
<key>NSSupportsLiveActivities</key>
<true/>
```

**4. ExitProgressionService - Add Observer**

Add observer setup in `init()` or `start()`:

```swift
// Listen for notification taps
NotificationCenter.default.addObserver(
    forName: .exitCheckInReceived,
    object: nil,
    queue: .main
) { [weak self] _ in
    Task { @MainActor in
        await self?.userCheckedIn()
    }
}
```

---

## Implementation Phases

### Phase 1: Core Live Activity Infrastructure (Week 1)
**Goal:** Basic Live Activity that shows exit status

**Tasks:**
1. Create Widget Extension target in Xcode
2. Create `ExitProgressActivityAttributes` with ContentState
3. Create `ExitProgressLiveActivity` widget with basic UI
   - Lock screen view
   - Dynamic Island minimal UI
4. Add `NSSupportsLiveActivities` to Info.plist (1 line change)
5. Test basic Live Activity start/update/end lifecycle

**Files Created:** 2 new files
**Files Modified:** 1 (Info.plist)

**Deliverable:** Live Activity appears on lock screen showing "Moving to savings" with basic step count.

### Phase 2: ExitProgressionService Integration (Week 2)
**Goal:** Automatically manage Live Activity during exit progression

**Tasks:**
1. Create `ExitProgressionService+LiveActivity.swift` extension with methods:
   - `startLiveActivity(for:)` - Start activity for exit batch
   - `updateLiveActivity(exitId:with:)` - Update specific exit activity
   - `endLiveActivity(exitId:success:)` - End specific exit activity
   - `reattachToExistingActivities()` - Reattach on app launch
2. Modify `ExitProgressionService.checkAndProgressExits()` to update activities
3. Add helper methods to parse `ExitTransactionStatus` into `ContentState`
4. Test with real exit progression (single and multiple exits)

**Files Created:** 1 new file (extension)
**Files Modified:** 1 (ExitProgressionService.swift - ~20 lines added to checkAndProgressExits)

**Deliverable:** Live Activity automatically updates as exit progresses through states.

### Phase 3: Rich Dynamic Island UI (Week 2-3)
**Goal:** Beautiful, informative Dynamic Island experience

**Tasks:**
1. Design and implement expanded Dynamic Island regions
   - Leading: Progress indicator / icon
   - Trailing: Transaction count / block info
   - Center: Step description
   - Bottom: Detailed status / time until next check
2. Add compact and minimal states
3. Implement animations for state transitions
4. Add color coding (orange for in-progress, green for claimable/complete)
5. Test on iPhone 14 Pro+ with Dynamic Island

**Deliverable:** Rich, animated Dynamic Island that shows detailed exit progress.

### Phase 4: Local Notification Integration (Week 3)
**Goal:** Reliable check-in reminders via local notifications

**Tasks:**
1. Create `ExitProgressionNotifications.swift` with scheduling methods:
   - `scheduleCheckInSequence()` for 90-minute intervals
   - `scheduleCheckInNotification()` with deep link data
   - `cancelAllCheckInReminders()`
2. Add notification handling to existing AppDelegate_iOS.swift (~10 lines)
   - Add exit check-in case to `userNotificationCenter(_:didReceive:)`
   - Post `.exitCheckInReceived` notification
3. Add foreground activation to existing ArkeMobile.swift (~8 lines)
   - Modify `.onChange(of: scenePhase)` to handle `.active` phase
   - Call `userCheckedIn()` when app enters foreground with active exits
4. Add notification permission request flow (reuse existing pattern)
5. Add NotificationCenter observer in ExitProgressionService
6. Test notification delivery, app activation, and exit progression

**Files Created:** 1 new file
**Files Modified:** 2 (AppDelegate_iOS.swift ~10 lines, ArkeMobile.swift ~8 lines)

**Deliverable:** Reliable check-in reminders that open app and progress exits.

### Phase 5: Polish & Edge Cases (Week 4)
**Goal:** Handle all edge cases and error scenarios

**Tasks:**
1. Handle multiple exits (show aggregate status)
2. Handle exit errors (display error in Live Activity)
3. Handle app termination (restore Live Activity on restart)
4. Add user preference to disable Live Activity
5. Handle system dismissal of Live Activity
6. Add analytics/logging for Live Activity lifecycle
7. Test on various iOS versions (16.1+)
8. Test on devices without Dynamic Island

**Deliverable:** Robust Live Activity system that handles all scenarios.

### Phase 6: Testing & Refinement (Week 5)
**Goal:** Comprehensive testing and user feedback

**Tasks:**
1. End-to-end testing on real Bitcoin (signet/testnet)
2. Test background execution over extended periods
3. Test with poor network conditions
4. Verify battery impact (should be minimal - just status updates)
5. User feedback and iteration
6. Documentation for users

**Deliverable:** Production-ready Live Activity for exit progression.

---

## Technical Considerations

### Live Activity Limitations

1. **Size Limits**: Activities have memory and update frequency limits
   - Keep ContentState small (<4KB recommended)
   - Limit updates to every 30-60 seconds minimum
   
2. **Duration**: Live Activities can last up to 8 hours before iOS dismisses them
   - For longer exits, may need to restart the activity
   
3. **Background Updates**: Can only update from background during specific circumstances
   - Background App Refresh
   - Silent push notifications (requires server)
   - Location updates (not applicable)

### Primary Strategy: Live Activity + Local Notifications

**Core Principle:** Don't fight iOS limitations - work with them.

**How It Works:**
1. **Live Activity** displays last known status (passive, no execution)
2. **Local Notifications** reliably remind user to check in (99%+ delivery)
3. **User opens app** → exits progress → Live Activity updates (reliable)
4. **Repeat** every 90 minutes until exit complete

**Why This Works:**
- ✅ No unreliable background tasks (BGProcessingTask has 10-30% success rate)
- ✅ No server infrastructure needed (no silent push notifications)
- ✅ Battery friendly (no background processing)
- ✅ Simple architecture (easy to maintain)
- ✅ Reliable (local notifications work, user controls progression)

**User Experience:**
```
0:00 - Start force move
       └─ Live Activity: "Starting move to savings..."
       └─ Notifications scheduled: 1.5h, 3h, 4.5h, 6h, 7.5h

1:30 - 🔔 Notification: "Tap to check on your force move"
       └─ User taps → App opens → Exits progress → Live Activity updates
       └─ Notifications rescheduled from now

3:00 - 🔔 Next reminder
       └─ Repeat...

4:15 - Move complete!
       └─ Live Activity: "✅ Complete!"
       └─ All notifications cancelled
```

### Exit Process Considerations

**From Analysis:**
- Exits are unilateral (don't depend on ASP server)
- Require broadcasting onchain transactions to Bitcoin network
- Transaction confirmations take ~10 minutes per block
- Total exit time: 4-8 transactions × ~10 min/tx = 40-80 minutes minimum
- Plus timelock waits (AwaitingDelta phase) which can be hours
- **Total duration: 2-8 hours typical**

**Why Local Notifications Work:**
- 90-minute check-in interval is reasonable for 2-8 hour process
- 4-5 notifications max per exit (not spammy)
- Delays if user misses notification don't break the exit
- Live Activity shows staleness ("Last updated: 2 hours ago")

**User Behavior:**
- Most users will respond to 1st or 2nd notification
- Some will ignore and check manually later
- Either way, exit progresses when they open app
- No funds lost if user is slow to respond

### Privacy & Security

**Design Decision: No amounts shown in Live Activities**

Live Activities are visible on the lock screen without authentication, so we prioritize privacy:

**What We Show:**
- ✅ Generic status: "Moving to savings", "Confirming transactions"
- ✅ Progress indicators: "Step 3 of 6", "2 of 5 confirmed"
- ✅ Count of outputs: "Moving 3 outputs" (if multiple VTXOs)
- ✅ Time since last update: "Updated 5 minutes ago"

**What We DON'T Show:**
- ❌ Bitcoin amounts (no sats, no BTC values)
- ❌ Full VTXO IDs or transaction IDs
- ❌ Addresses
- ❌ Fee amounts

**Why This Approach:**
1. Lock screen is visible to anyone near the device
2. Amounts could reveal financial status to onlookers
3. Generic progress is still useful for the user
4. Detailed information available in-app where it's protected

**ContentState Security:**
- ContentState is logged by iOS system
- Never include: seed phrases, private keys, full transaction data
- Use truncated IDs for debugging only
- Keep all sensitive data in the app, not in Live Activity

---

## User Permissions Required

### Overview

This feature requires **one** user permission:

| Permission | Required? | When to Request | What Happens if Denied |
|------------|-----------|-----------------|------------------------|
| **Notifications** | Yes | Before starting first exit | No check-in reminders, Live Activity still works but goes stale |
| **Live Activities** | No (automatic) | N/A | User can disable in iOS Settings if desired |

### 1. Notification Permission (REQUIRED)

**Good News:** Arke already has notification permission handling in `SettingsView_iOS.swift`!

**Existing Implementation:**
- ✅ `registerForNotifications()` method already exists (line 440)
- ✅ Handles `requestAuthorization` with proper error handling
- ✅ Shows error messages when permission denied
- ✅ Registers with remote notifications after grant

**When to Request for Exits:**
- When user starts their **first exit**
- Show explanation dialog first (see below)
- Reuse existing `registerForNotifications()` pattern

**Permission Request Flow:**

```swift
// Step 1: Show explanation sheet BEFORE requesting permission
struct ExitNotificationPermissionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Stay Updated on Your Force Move")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Moving funds to savings takes 2-8 hours and requires periodic check-ins. We'll send you reminders every 90 minutes so you don't have to keep the app open.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                PermissionBenefitRow(
                    icon: "clock",
                    title: "Timely Reminders",
                    description: "Get notified every 90 minutes to check on your force move"
                )
                
                PermissionBenefitRow(
                    icon: "lock.shield",
                    title: "Keep Your Funds Safe",
                    description: "Don't miss check-ins and risk delays"
                )
                
                PermissionBenefitRow(
                    icon: "iphone",
                    title: "Close the App",
                    description: "No need to keep Arke open for hours"
                )
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            
            Button("Enable Notifications") {
                dismiss()
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Button("Continue Without Notifications") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding()
    }
}

// Step 2: Reuse existing permission request method
// EXISTING CODE in SettingsView_iOS.swift (lines 440-474)
private func registerForNotifications() async {
    do {
        // Request notification permission
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        
        if granted {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            
            // Wait a moment for token to be received
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Register with relay
            await manager.registerForPushNotifications()
            
            print("✅ Successfully registered for notifications")
        } else {
            // User denied permission
            await MainActor.run {
                notificationsEnabled = false
                notificationErrorMessage = "Notification permission denied. Please enable in Settings."
                showNotificationError = true
            }
        }
    } catch {
        // Error requesting permission
        await MainActor.run {
            notificationsEnabled = false
            notificationErrorMessage = "Failed to register: \(error.localizedDescription)"
            showNotificationError = true
        }
    }
}

// NEW: Helper to check permission status before requesting
func checkNotificationPermission() async -> UNAuthorizationStatus {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    return settings.authorizationStatus
}

// Step 3: Handle "Denied" state - direct to Settings
func showNotificationsDeniedAlert() async {
    let alert = UIAlertController(
        title: "Notifications Disabled",
        message: "Enable notifications in Settings to receive check-in reminders. Without reminders, you'll need to manually check the app every 90 minutes.",
        preferredStyle: .alert
    )
    
    alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    })
    
    alert.addAction(UIAlertAction(title: "Continue Anyway", style: .cancel))
    
    // Present alert
    await MainActor.run {
        // Get top view controller and present
    }
}

// Step 4: Handle "Declined" state - explain implications
func showNotificationsDeclinedAlert() async {
    let alert = UIAlertController(
        title: "Check-In Reminders Disabled",
        message: "Without notifications, you'll need to manually check the app every 90 minutes during your force move. You can enable notifications later in iOS Settings.",
        preferredStyle: .alert
    )
    
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    
    // Present alert
}
```

**Integration into Existing Exit Flow:**

The exit is started in `ExitView_iOS.swift` (line 428). Hook in there:

```swift
// EXISTING CODE in ExitView_iOS.swift (lines 428-448)
private func startExit() async {
    isProcessing = true
    defer { isProcessing = false }
    
    do {
        print("🚪 Starting unilateral exit...")
        
        // Start exit via wallet manager (Bark SDK handles all tracking)
        let result = try await manager.startExit()
        print("✅ Exit started: \(result)")
        
        // ADD: Check notification permission and start Live Activity
        let notificationStatus = await UNUserNotificationCenter.current().notificationSettings()
        if notificationStatus.authorizationStatus == .notDetermined {
            // First exit - request permission
            await requestExitNotificationPermission()
        }
        
        // ADD: Start Live Activity for the exit
        if let exitVtxos = try? await manager.getExitVtxos() {
            await manager.exitProgressionService?.startLiveActivity(for: exitVtxos)
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
```

**Note:** Arke already has a full notification toggle in `SettingsView_iOS.swift` (lines 144-173) with permission handling (lines 440-474). The exit notification flow should integrate with this existing system.

**What Happens if Permission Denied:**
- ✅ Live Activity still works (shows status when fresh)
- ❌ No check-in reminders sent
- ⚠️ Show in-app banner with settings link: "Enable notifications for check-in reminders"
- ⚠️ Live Activity will go stale unless user manually checks app
- 💡 Suggest: "Set a timer to check back every 90 minutes"

**Recommended UI Enhancements:**

1. **Exit Status View Banner** (when notifications disabled):
```swift
// Show banner at top of exit status view
if notificationStatus == .denied {
    Banner(
        icon: "bell.slash.fill",
        title: "Notifications Disabled",
        message: "Enable notifications in Settings to receive check-in reminders",
        action: {
            // Deep link to Settings or show sheet explaining how to enable
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        },
        actionLabel: "Open Settings"
    )
    .padding()
}
```

2. **Quick Settings Toggle** (in exit detail view):
```swift
// In UnilateralExitListView_iOS or ExitStatusDetailView_iOS
Section {
    Toggle("Check-in Reminders", isOn: $notificationsEnabled)
        .onChange(of: notificationsEnabled) { _, newValue in
            if newValue {
                Task {
                    await checkAndRequestNotificationPermission()
                }
            }
        }
} footer: {
    Text("Get notified every 90 minutes to check on your move progress")
}
```

3. **Settings Deep Link** (from exit views):
```swift
// Add to navigation bar or as button
Button("Notification Settings") {
    // Navigate to settings or show notification permission sheet
}
```

### 2. Live Activity Permission (Automatic)

**Good News:** Live Activities don't require explicit permission!

**How it Works:**
- iOS automatically allows Live Activities
- User can disable in Settings → [App Name] → Live Activities
- Your code should check: `ActivityAuthorizationInfo().areActivitiesEnabled`
- If disabled, skip starting Live Activity (no error, just silently skip)

```swift
func startLiveActivity(for exitVtxos: [ExitVtxo]) async {
    // Check if Live Activities are enabled
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        print("⚠️ Live Activities disabled by user")
        // This is OK - continue without Live Activity
        // Notifications will still work
        return
    }
    
    // Proceed to start Live Activity
    // ...
}
```

**User Can Disable:**
- Settings → Arke → Live Activities → Toggle Off
- No permission dialog needed
- No re-prompting possible (user's choice)

### 3. Background App Refresh (Optional)

**Not required for this implementation** (we're not using background tasks), but mentioned for completeness:

**If you add background tasks later:**
- Settings → Arke → Background App Refresh
- User can disable per-app
- No explicit permission request
- Check with: `UIApplication.shared.backgroundRefreshStatus`

### Permission Summary

**User Will See:**
1. ✅ **One permission dialog**: Notifications (first exit)
2. ❌ **No permission dialog**: Live Activities (automatic)
3. ✅ **Can disable later**: Both in iOS Settings

**Best Practices:**
- Request notifications **in context** (when starting first exit)
- Show **clear explanation** before requesting
- Handle **all denial scenarios** gracefully
- Provide **fallback experience** (manual checking)
- Show **helpful in-app guidance** if permissions denied
- **Never repeatedly prompt** (respect user's decision)

### Testing Permission States

```swift
// Test helper to check all permission states
func checkAllPermissions() async -> PermissionStatus {
    let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
    let liveActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
    
    return PermissionStatus(
        notifications: notificationSettings.authorizationStatus,
        liveActivities: liveActivitiesEnabled
    )
}

struct PermissionStatus {
    let notifications: UNAuthorizationStatus
    let liveActivities: Bool
    
    var isOptimal: Bool {
        notifications == .authorized && liveActivities
    }
    
    var canSendReminders: Bool {
        notifications == .authorized
    }
    
    var canShowLiveActivity: Bool {
        liveActivities
    }
    
    var userFacingMessage: String {
        switch (notifications, liveActivities) {
        case (.authorized, true):
            return "✅ All features enabled"
        case (.authorized, false):
            return "⚠️ Live Activity disabled (check-ins still work)"
        case (.denied, true):
            return "⚠️ Notifications disabled (Live Activity works but will go stale)"
        case (.denied, false):
            return "❌ Both disabled (manual checking required)"
        default:
            return "⚠️ Notifications not configured"
        }
    }
}
```

---

## Critical Reminders & Gotchas

### Live Activities

#### 1. **Entitlements & Info.plist (REQUIRED)**
```xml
<!-- Info.plist -->
<key>NSSupportsLiveActivities</key>
<true/>
```

Without this, `Activity.request()` will fail silently or throw an error.

#### 2. **Widget Extension Target**
Live Activities require a **Widget Extension** target:
- Create new target: File → New → Target → Widget Extension
- Name it something like `ArkeWidgets`
- Include Live Activity in the extension
- The widget extension runs in a separate process

#### 3. **Shared Code Between App and Widget**
Widget extension needs access to:
- `ExitProgressActivityAttributes` (must be in shared framework)
- Any models used in ContentState
- Asset catalog (SF Symbols work, custom assets need to be in widget target)

**Solution:** Put Live Activity code in `Shared` target or create shared framework.

#### 4. **ContentState Size Limits**
- Keep ContentState **under 4KB** (system limit)
- Avoid large strings, arrays, or nested objects
- Use primitive types where possible
- Don't include: full transaction hex, large arrays of data

#### 5. **Update Frequency Limits**
- iOS throttles updates if you update too frequently
- Minimum recommended interval: **30-60 seconds**
- Our case: Update only when user checks in (every 90 min) - perfect!

#### 6. **Live Activity Lifetime**
- Maximum duration: **8 hours** (iOS dismisses after this)
- Can be dismissed by user at any time (swipe away)
- Can be dismissed by system if too many activities active
- **Handle dismissal gracefully** - check if activity is still active before updating

#### 7. **Testing Live Activities**
- Simulator support is limited (no Dynamic Island preview)
- **Must test on real device** for accurate behavior
- iPhone 14 Pro+ for Dynamic Island testing
- Live Activities don't appear in notification center

#### 8. **Activity State Persistence**
- Activities persist across app termination
- Must handle case where app restarts but activity is still live
- Store activity ID in UserDefaults to reattach
- Use `Activity<T>.activities` to enumerate existing activities

```swift
// Reattach to existing activity on app launch
func reattachToExistingActivity() async {
    for activity in Activity<ExitProgressActivityAttributes>.activities {
        if activity.attributes.exitId == currentExitId {
            self.currentActivity = activity
            print("✅ Reattached to existing Live Activity")
            return
        }
    }
}
```

### Local Notifications

#### 1. **Permission Request (REQUIRED)**
Local notifications require explicit user permission:

```swift
func requestNotificationPermission() async -> Bool {
    let center = UNUserNotificationCenter.current()
    
    do {
        let granted = try await center.requestAuthorization(
            options: [.alert, .sound, .badge]
        )
        print(granted ? "✅ Notification permission granted" : "❌ Notification permission denied")
        return granted
    } catch {
        print("❌ Failed to request notification permission: \(error)")
        return false
    }
}
```

**When to request:**
- When user starts their first exit
- Show explanation dialog first ("We'll remind you to check in")
- Don't request on app launch (feels spammy)

#### 2. **Do Not Disturb / Focus Modes**
- Notifications are suppressed during Do Not Disturb
- Use `.timeSensitive` interruption level to break through DND
- Requires "Time Sensitive Notifications" capability
- Still respects user's "Always Allow" vs "Deliver Quietly" settings

```swift
content.interruptionLevel = .timeSensitive  // Break through DND
content.relevanceScore = 1.0  // High priority
```

#### 3. **Notification Scheduling Limits**
- iOS limits to **64 pending notifications** per app
- Scheduling more causes oldest to be dropped
- Our case: Max 5 notifications per exit - well within limit

#### 4. **Time Zones & Date Handling**
- `UNTimeIntervalNotificationTrigger` uses relative time (seconds from now)
- Handles time zone changes automatically
- Don't use `UNCalendarNotificationTrigger` for our use case (too complex)

#### 5. **Notification Identifiers**
- Must be unique for each notification
- Use UUID to avoid collisions: `"exit-check-\(UUID().uuidString)"`
- Store IDs to cancel later: `scheduledNotificationIds.append(id)`
- Cancel old notifications before rescheduling

#### 6. **App State When Notification Taps**
Three scenarios:
```swift
// 1. App not running → App launches
// 2. App in background → App comes to foreground
// 3. App in foreground → Notification banner appears, tap does nothing special

// Handle all three in:
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
) {
    // Your handling code
    completionHandler()  // MUST call this!
}
```

#### 7. **Notification Categories (Optional but Useful)**
Register categories for interactive notifications (v2 feature):

```swift
let viewAction = UNNotificationAction(
    identifier: "VIEW_EXIT",
    title: "View Progress",
    options: [.foreground]
)

let category = UNNotificationCategory(
    identifier: "EXIT_PROGRESS",
    actions: [viewAction],
    intentIdentifiers: [],
    options: []
)

UNUserNotificationCenter.current().setNotificationCategories([category])
```

### Development & Debugging

#### 1. **Simulator Limitations**
- ✅ Local notifications work in simulator
- ❌ Live Activities have limited simulator support (no Dynamic Island)
- ❌ Background execution doesn't work realistically in simulator
- **Solution:** Use real device for accurate testing

#### 2. **Xcode Debugging Live Activities**
- Widget extension runs in separate process
- Attach debugger: Debug → Attach to Process → ArkeWidgets
- Or set breakpoint and it will pause when hit
- Use `print()` statements (show up in Console)

#### 3. **Live Activity Not Appearing?**
Check these:
- [ ] `NSSupportsLiveActivities` in Info.plist
- [ ] Widget extension target created and included in scheme
- [ ] `ActivityAttributes` is `Codable` and `Hashable`
- [ ] ContentState is under 4KB
- [ ] Not on iOS < 16.1
- [ ] Activity authorization: `ActivityAuthorizationInfo().areActivitiesEnabled`

#### 4. **Notification Not Firing?**
Check these:
- [ ] Permission granted (`requestAuthorization`)
- [ ] Notification identifier is unique
- [ ] Trigger time is in the future
- [ ] App has network connectivity (for time sync)
- [ ] Device not in Low Power Mode (delays non-critical notifications)
- [ ] Not in Do Not Disturb (unless `.timeSensitive`)

#### 5. **Testing Notification Scheduling**
Override trigger time for testing:

```swift
#if DEBUG
let trigger = UNTimeIntervalNotificationTrigger(
    timeInterval: 10,  // 10 seconds instead of 90 minutes
    repeats: false
)
#else
let trigger = UNTimeIntervalNotificationTrigger(
    timeInterval: 90 * 60,
    repeats: false
)
#endif
```

### Production Considerations

#### 1. **Analytics & Monitoring**
Track these metrics:
- Live Activity start success rate
- Live Activity update success rate
- Notification delivery rate (check pending vs delivered)
- User response time to notifications
- Exit completion rate with vs without Live Activity

#### 2. **Error Handling**
Always handle failures gracefully:

```swift
do {
    currentActivity = try Activity.request(...)
} catch {
    print("❌ Failed to start Live Activity: \(error)")
    // Continue without Live Activity - notifications still work
}
```

#### 3. **User Settings**
Allow users to disable:
- Live Activity (some users find it distracting)
- Notification reminders (some users want manual checking)
- At least one should be enabled (warn if both disabled)

#### 4. **Battery Testing**
- Live Activities are passive (minimal battery impact)
- Local notifications are lightweight
- Test on real device over 8+ hour period
- Monitor battery usage in Settings → Battery

#### 5. **Accessibility**
- Live Activity text should work with Dynamic Type
- Use `.minimumScaleFactor()` for text that must fit
- Provide VoiceOver labels for icons
- Test with VoiceOver enabled

### Common Pitfalls

❌ **Don't:**
- Store large objects in ContentState
- Update Live Activity more than once per minute
- Assume background tasks will run (they won't reliably)
- Force unwrap `currentActivity` (can be nil if dismissed)
- Forget to call notification completion handler

✅ **Do:**
- Keep ContentState minimal and primitive
- Check if activity exists before updating
- Handle all three notification app states
- Test on real device, not just simulator
- Provide fallback if Live Activity fails
- Request notification permission at right time
- Cancel old notifications before rescheduling

---

## UI/UX Design Guidelines

### Lock Screen View States

**Fresh State (< 30 minutes old):**
```
┌─────────────────────────────────────┐
│ 🔵 Confirming Transactions          │
│ ■■■□□□ Step 3 of 6                  │
│ 2 of 5 transactions confirmed       │
│ Updated 5 minutes ago               │
└─────────────────────────────────────┘
```

**Needs Check-In State (> 90 minutes old):**
```
┌─────────────────────────────────────┐
│ ⚠️ Confirming Transactions          │
│ ■■■□□□ Step 3 of 6                  │
│ ⚠️ Check-in needed                  │
│ Updated 2 hours ago                 │
│ Tap notification to update          │
└─────────────────────────────────────┘
```

**Complete State:**
```
┌─────────────────────────────────────┐
│ ✅ Move Complete                    │
│ ■■■■■■ Step 6 of 6                  │
│ All transactions confirmed          │
│ Funds available in wallet           │
└─────────────────────────────────────┘
```

### Dynamic Island

**Minimal State:**
- Single icon: Arrow down circle (exit symbol)
- Shows when island is collapsed to smallest size

**Compact State:**
- Leading: Exit icon
- Trailing: "3/6" (step progress)

**Expanded State:**
- **Top Leading**: Large exit icon with animation
- **Top Trailing**: Transaction count (2/5 confirmed)
- **Center**: Current step description ("Confirming transactions")
- **Bottom**: Progress bar + "Next check in 3 minutes"

**Colors:**
- Orange: In progress
- Blue: Waiting for blocks
- Green: Claimable/Complete
- Red: Error

### Error Handling

**If exit encounters error:**
- Show red icon in Live Activity
- Description: "Exit needs attention"
- Tapping opens app to error details
- Don't auto-dismiss - keep visible until user resolves

### Completion

**When exit completes:**
- Show green checkmark
- Description: "Move complete! Funds claimed."
- Keep visible for 1 hour
- Add haptic feedback when completed

---

## Testing Plan

### Unit Tests
- ContentState serialization/deserialization
- Exit state parsing logic
- Progress calculation methods

### Integration Tests
- Live Activity start/update/end lifecycle
- Background task scheduling
- Notification scheduling

### Manual Testing Scenarios

1. **Happy Path**
   - Start exit
   - Verify Live Activity appears
   - Watch it update through each state
   - Verify completion and dismissal

2. **Background Progression**
   - Start exit
   - Background app
   - Wait 1+ hours
   - Check if Live Activity updated
   - Check if notifications sent

3. **App Termination**
   - Start exit with Live Activity
   - Force quit app
   - Relaunch app
   - Verify Live Activity still active and syncs

4. **Multiple Exits**
   - Start exit with multiple VTXOs
   - Verify aggregate status shown correctly

5. **Error Scenarios**
   - Trigger exit error
   - Verify Live Activity shows error state
   - Resolve error, verify recovery

6. **Network Issues**
   - Start exit
   - Disable network
   - Verify graceful handling
   - Re-enable network, verify recovery

7. **Long-Running Exit**
   - Monitor exit over full 4-8 hour duration
   - Verify Live Activity doesn't get dismissed
   - Check battery impact

---

## Success Metrics

### Technical Metrics
- Live Activity successfully starts: >95% of exits
- Notification delivery: >99% (local notifications are reliable)
- User responds to notification within 2 hours: >80% (target)
- Completion detection: 100% of exits
- Battery impact: <1% per hour (minimal - just notifications)

### User Experience Metrics
- User satisfaction with check-in reminders: Measured via feedback
- Users enable notifications: >85% (critical for functionality)
- Exit completion time: Same as current (no improvement expected, but no regression)
- User complaints about "missed check-ins": <5%

---

## Future Enhancements

### V2 Features (Post-MVP)
1. **Silent Push Notifications**: Add server infrastructure for guaranteed background updates (70-90% reliability)
2. **Interactive Notifications**: Action buttons to view details or claim immediately
3. **Multiple Exit Support**: Show aggregate status for multiple concurrent exits
4. **Block Explorer Links**: Tap Live Activity to view transactions in block explorer
5. **Estimated Completion Time**: Show "~2 hours remaining" based on current state
6. **Smart Notification Timing**: Adjust reminder frequency based on exit phase

### Advanced Features
1. **Watch App Integration**: Show exit status on Apple Watch, notifications appear on wrist
2. **Widget**: Home screen widget showing current exit status (static, updates when app opens)
3. **StandBy Mode**: Full-screen exit progress view optimized for StandBy mode
4. **Settings**: Customizable notification frequency (60/90/120 minutes)
5. **Background App Refresh**: Opportunistic updates when system allows (best effort, don't rely on it)

---

## Open Questions

1. **Notification Frequency**: 90 minutes is the baseline - should this be user-configurable?
   - **Recommendation**: Start with fixed 90 min, add setting in v2 if users request it
   
2. **Exit Restart**: If iOS dismisses activity after 8 hours, restart it?
   - **Recommendation**: Yes, restart with notification to user
   
3. **Error Recovery**: Should we retry failed progression automatically or require user intervention?
   - **Recommendation**: Auto-retry up to 3 times with exponential backoff, then show error state

---

## Dependencies

### System Requirements
- iOS 16.1+ (Live Activities)
- iPhone 14 Pro+ for Dynamic Island (fallback to lock screen on other devices)
- User permission for notifications (for fallback)

### Framework Dependencies
- ActivityKit (iOS 16.1+)
- WidgetKit (for widget configuration)
- BackgroundTasks (for background execution)
- UserNotifications (for notification fallback)

### Arke Dependencies
- `ExitProgressionService` (existing)
- `BarkWalletFFI` exit methods (existing)
- `ExitStatusParser` (existing)
- `WalletManager` (existing)

### Files Modified (Existing)
1. **`AppDelegate_iOS.swift`** - Add exit check-in notification handling (~15 lines)
   - Add case to existing `userNotificationCenter(_:didReceive:)` method
   - Add `.exitCheckInReceived` to Notification.Name extension
2. **`ArkeMobile.swift`** - Add foreground activation with exit check (~10 lines)
   - Modify existing `.onChange(of: scenePhase)` handler
   - Add `.active` phase handling for exit progression
3. **`Info.plist`** - Enable Live Activities (1 key-value pair)
   - Add `NSSupportsLiveActivities` = `true`
4. **`ExitProgressionService.swift`** - Integrate Live Activity updates (~20 lines)
   - Modify `checkAndProgressExits()` to update activities
   - Add NotificationCenter observer setup

**Total Existing File Modifications:** ~45 lines across 4 files

### New Files Required
1. **Widget Extension Target** (created via Xcode, not a file)
2. `ExitProgressActivityAttributes.swift` - Activity attributes definition
3. `ExitProgressLiveActivity.swift` - Widget configuration and UI
4. `ExitProgressLockScreenView.swift` - Lock screen UI components
5. `ExitProgressDynamicIslandViews.swift` - Dynamic Island UI components
6. `ExitProgressionNotifications.swift` - Notification scheduling manager
7. `ExitProgressionService+LiveActivity.swift` - Live Activity management extension

**Total New Files:** 6 Swift files + 1 Widget Extension target

---

## Conclusion

Live Activities + Local Notifications are an **excellent solution** for exit progression in Arke. This approach:

✅ **Works reliably** - Local notifications have 99%+ delivery rate  
✅ **No server required** - Everything runs on-device  
✅ **Battery friendly** - No background processing  
✅ **Simple architecture** - Easy to implement and maintain  
✅ **Great UX** - Beautiful status display + reliable reminders  
✅ **iOS-friendly** - Works with platform limitations, not against them  

**The Reality:**
- Live Activities **cannot** execute code or wake the app
- Background tasks (BGProcessingTask) are **unreliable** (10-30% success rate)
- Local notifications **are reliable** and work perfectly for this use case
- User opening the app is what progresses exits (this is fine!)
**Why This is Better Than Current State:**
- Current: User must keep app open for hours (bad UX)
- With this: User gets lock screen status + reminders, checks in every 90 min (good UX)

**Implementation Strategy:**
1. **Phase 1-2**: Core Live Activity with basic UI (1-2 weeks)
2. **Phase 3**: Rich Dynamic Island UI (1 week)
3. **Phase 4**: Local notification integration (1 week)
4. **Phase 5**: Polish and edge cases (1 week)
5. **Phase 6**: Testing and refinement (1 week)

**Total Timeline:** ~6 weeks to production-ready

**Recommendation: Proceed with implementation.** This is the right balance of features, reliability, and complexity. Future v2 can add server-based silent push if deeper background integration is needed, but start with this solid foundation.

---
## Implementation Checklist Summary

### Existing Infrastructure (No Changes)
- [x] Notification delegate setup (`AppDelegate_iOS.swift`)
- [x] Scene lifecycle monitoring (`ArkeMobile.swift`)
- [x] Notification permission handling (`SettingsView_iOS.swift`)
- [x] Exit progression service (`ExitProgressionService.swift`)
- [x] Exit state parsing (`ExitStatusParser.swift`)
- [x] WalletManager with exit service instantiated

### Minimal Changes Required (~45 lines total)
- [ ] `AppDelegate_iOS.swift` - Add exit notification case (+15 lines)
- [ ] `ArkeMobile.swift` - Add foreground activation handler (+10 lines)
- [ ] `Info.plist` - Add NSSupportsLiveActivities key (+1 line)
- [ ] `ExitProgressionService.swift` - Add activity updates to checkAndProgressExits (+20 lines)

### New Files to Create (6 files)
- [ ] `ExitProgressActivityAttributes.swift` - Attributes and ContentState
- [ ] `ExitProgressLiveActivity.swift` - Widget configuration
- [ ] `ExitProgressLockScreenView.swift` - Lock screen UI
- [ ] `ExitProgressDynamicIslandViews.swift` - Dynamic Island UI
- [ ] `ExitProgressionNotifications.swift` - Notification scheduling
- [ ] `ExitProgressionService+LiveActivity.swift` - Live Activity management

### New Target to Create
- [ ] Widget Extension target in Xcode (for Live Activity)

### Integration Points
- [ ] Hook `startLiveActivity()` into `ExitView_iOS.startExit()` (line 428)
- [ ] Test notification flow from scheduling → tap → progression
- [ ] Test foreground activation triggering exit progression
- [ ] Test multiple concurrent exits with separate activities
- [ ] Verify Live Activity dismissal and cleanup


