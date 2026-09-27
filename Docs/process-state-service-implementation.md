# Process State Service Implementation

## Overview

This implementation provides centralized tracking of ongoing wallet processes and health states. The system tracks unilateral exits, VTXO expiry, ASP connection status, and backup reminders.

## Architecture

### Core Components

1. **ProcessStateService** (`ProcessStateService.swift`)
   - Main service class that coordinates all process state tracking
   - Observable, integrates with SwiftUI
   - Manages both persistent and computed states

2. **Persistent Models** (SwiftData)
   - `OngoingUnilateralExit` - Tracks unilateral exit processes
   - `BackupStatus` - Tracks backup confirmation and reminder state

3. **Computed State Structures**
   - `VTXOHealth` - Health status of VTXOs (expired, expiring soon)
   - `ConnectionStatus` - ASP connection quality and status

## State Categories

### 1. Unilateral Exit Tracking

**Model:** `OngoingUnilateralExit`

**States:**
- `broadcasted` - Exit transaction has been broadcast
- `inChallengePeriod` - Exit is in challenge period (waiting for maturity)
- `matured` - Challenge period has ended
- `claimable` - Exit funds are ready to be claimed
- `claimed` - Exit has been claimed (completed)
- `failed` - Exit process failed

**Key Features:**
- Tracks challenge period countdown
- Calculates blocks remaining and estimated time
- Automatically updates status based on block height
- Persists across app restarts
- Links to VTXOs being exited

**Usage Example:**
```swift
// Start tracking an exit
try manager.startUnilateralExit(
    exitTxid: "abc123...",
    challengePeriodEndHeight: 850000,
    vtxoOutpoints: ["txid:0", "txid:1"],
    totalAmountSat: 100000,
    notes: "Emergency exit"
)

// Check active exits
if manager.hasActiveUnilateralExits {
    for exit in manager.activeUnilateralExits {
        print("Exit \(exit.shortTxid): \(exit.formattedTimeRemaining(currentHeight: height))")
    }
}

// Mark as claimed when user completes the process
try manager.markExitClaimed(exitTxid: "abc123...")
```

### 2. VTXO Health Monitoring

**Model:** `VTXOHealth` (computed, not persisted)

**Tracks:**
- Expired VTXOs (past expiry height)
- VTXOs expiring soon (within threshold, default 144 blocks ~1 day)
- Total amounts at risk
- Priority level (normal, high, critical)

**Key Features:**
- Computed on each wallet refresh
- Configurable expiry threshold
- Provides formatted amounts and time estimates
- Action recommendations (refresh vs exit)

**Usage Example:**
```swift
let health = manager.vtxoHealth

if health.hasExpiredVTXOs {
    print("⚠️ \(health.expiredCount) VTXOs expired (\(health.formattedExpiredAmount))")
    print("Action: \(health.actionMessage ?? "No action needed")")
}

if health.hasVTXOsExpiringSoon {
    for vtxo in health.vtxosExpiringSoon {
        let timeLeft = health.formattedTimeUntilExpiry(for: vtxo, currentHeight: currentHeight)
        print("VTXO \(vtxo.shortId) expires in \(timeLeft)")
    }
}
```

### 3. ASP Connection Status

**Model:** `ConnectionStatus` (in-memory, not persisted)

**Quality Levels:**
- `excellent` - Recent successful sync (< 1 minute)
- `good` - Sync within 5 minutes
- `poor` - Sync within 15 minutes
- `disconnected` - No recent sync or connection failed

**Key Features:**
- Updated on each refresh attempt
- Tracks reconnection attempts
- Stores last successful sync timestamp
- Can determine if collaborative operations are possible

**Usage Example:**
```swift
let status = manager.connectionStatus

if status.showWarning {
    print("⚠️ \(status.statusMessage)")
    if let detail = status.detailedMessage {
        print(detail)
    }
}

if !status.canPerformCollaborativeOperations {
    // Disable send/receive UI
    print("Cannot perform collaborative operations - ASP disconnected")
}
```

### 4. Backup Reminders

**Model:** `BackupStatus` (persisted)

**Configuration:**
- Shows after 3 transactions (first time)
- Shows after 5 transactions (subsequent)
- Can be snoozed for 24 hours
- Can be dismissed (resets transaction counter)
- Confirms backup to disable permanently

**Key Features:**
- Persists across app restarts
- Tracks transaction count since last reminder
- Configurable snooze duration
- Priority levels based on transaction count

**Usage Example:**
```swift
if manager.shouldShowBackupReminder {
    let status = manager.backupStatus
    print("💾 \(status?.reminderMessage ?? "Back up your wallet")")
    
    // User actions:
    // 1. Snooze for 24 hours
    try manager.snoozeBackupReminder()
    
    // 2. Dismiss until more transactions
    try manager.dismissBackupReminder()
    
    // 3. Confirm backup (permanently disables)
    try manager.confirmBackup()
}
```

## Integration with WalletManager

### Service Initialization

The service is automatically initialized when `WalletManager` is created:

```swift
private func initializeServices() {
    // ... other services
    processStateService = ProcessStateService()
    
    // Configure post-transaction callback
    walletOperationsService?.setTransactionCompletedCallback { [weak self] in
        await self?.balanceService?.refreshAfterTransaction()
        // Increment backup transaction count after each transaction
        self?.processStateService?.incrementBackupTransactionCount()
    }
}
```

### ModelContext Setup

The service receives the SwiftData `ModelContext` automatically:

```swift
func setModelContext(_ context: ModelContext) {
    // ... other services
    processStateService?.setModelContext(context)
}
```

### Automatic Refresh

Process states are refreshed after each wallet data refresh:

```swift
private func performRefresh() async {
    // ... refresh balance, transactions, etc.
    
    // After successful refresh, update process state service
    await refreshProcessStates()
}

private func refreshProcessStates() async {
    let vtxos = try await getVTXOs()
    let blockHeight = balanceService?.estimatedBlockHeight ?? 0
    let isConnected = error == nil
    
    processStateService.refreshAll(
        vtxos: vtxos,
        blockHeight: blockHeight,
        isConnected: isConnected,
        connectionError: error
    )
}
```

## Exposed Properties

WalletManager exposes all process state data through computed properties:

```swift
// Service access
var processStateServiceInstance: ProcessStateService?

// Unilateral exits
var activeUnilateralExits: [OngoingUnilateralExit]
var hasActiveUnilateralExits: Bool
var exitsRequiringAction: [OngoingUnilateralExit]
var hasExitsRequiringAction: Bool

// VTXO health
var vtxoHealth: VTXOHealth

// Connection
var connectionStatus: ConnectionStatus

// Backup
var backupStatus: BackupStatus?
var shouldShowBackupReminder: Bool

// Attention summary
var attentionItemCount: Int
var needsAttention: Bool
var attentionSummary: String?
```

## Public Methods

### Unilateral Exit Management

```swift
func startUnilateralExit(
    exitTxid: String,
    challengePeriodEndHeight: Int,
    vtxoOutpoints: [String],
    totalAmountSat: Int,
    notes: String? = nil
) throws

func markExitClaimed(exitTxid: String) throws
func markExitFailed(exitTxid: String, error: String) throws
func cancelExit(exitTxid: String) throws
func getExit(txid: String) -> OngoingUnilateralExit?
func cleanupOldExits() throws
```

### Backup Management

```swift
func confirmBackup() throws
func snoozeBackupReminder() throws
func dismissBackupReminder() throws
```

## UI Integration Points

### Activity List Banner

Show warnings/alerts in the activity list:

```swift
if manager.needsAttention {
    BannerView(message: manager.attentionSummary ?? "Attention needed")
}
```

### Exit Status Indicators

Show exit progress for transactions:

```swift
if let exit = manager.getExit(txid: transaction.txid) {
    HStack {
        Image(systemName: "arrow.up.forward")
        Text("Exiting: \(exit.formattedTimeRemaining(currentHeight: blockHeight))")
    }
}
```

### VTXO Health Warnings

```swift
if manager.vtxoHealth.hasExpiredVTXOs {
    WarningView(
        title: "Expired VTXOs",
        message: manager.vtxoHealth.statusMessage ?? "",
        action: manager.vtxoHealth.actionMessage ?? ""
    )
}
```

### Backup Reminder

```swift
if manager.shouldShowBackupReminder {
    BackupReminderView(
        message: manager.backupStatus?.reminderMessage ?? "",
        priority: manager.backupStatus?.reminderPriority ?? .low,
        onConfirm: { try? manager.confirmBackup() },
        onSnooze: { try? manager.snoozeBackupReminder() },
        onDismiss: { try? manager.dismissBackupReminder() }
    )
}
```

### Connection Status Indicator

```swift
HStack {
    Image(systemName: manager.connectionStatus.quality.iconName)
    Text(manager.connectionStatus.statusMessage)
}
.foregroundStyle(manager.connectionStatus.showWarning ? .orange : .secondary)
```

## Data Persistence

### SwiftData Models Added to Schema

In `Ark.swift`, the following models were added to the `ModelContainer`:

```swift
let modelContainer: ModelContainer = {
    SwiftDataHelper.createModelContainer(
        for: // ... existing models
             OngoingUnilateralExit.self,  // 🚪 Unilateral exit process tracking
             BackupStatus.self,  // 💾 Backup reminder state
        cloudKitEnabled: true,
        cloudKitContainerIdentifier: "iCloud.gbks.sigma"
    )
}()
```

### CloudKit Sync

Both persistent models sync via CloudKit:
- **OngoingUnilateralExit** - Exit processes sync across devices
- **BackupStatus** - Backup confirmation syncs across devices (singleton pattern)

## Error Handling

All methods that can fail throw `ProcessStateError`:

```swift
enum ProcessStateError: LocalizedError {
    case noModelContext
    case exitNotFound(txid: String)
    case backupStatusNotFound
}
```

Handle errors appropriately:

```swift
do {
    try manager.startUnilateralExit(...)
} catch ProcessStateError.noModelContext {
    // Model context not available
} catch {
    // Other error
}
```

## Performance Considerations

1. **VTXO Health** - Computed on each refresh, O(n) where n is number of VTXOs
2. **Exit Updates** - Only updates status for active exits, not completed
3. **Backup Counter** - Increments after each transaction (lightweight)
4. **Connection Status** - In-memory only, no persistence overhead

## Testing

Mock data is available for testing UI components:

```swift
// Mock exit
let mockExit = OngoingUnilateralExit(
    exitTxid: "abc123",
    challengePeriodEndHeight: 850000,
    vtxoOutpoints: ["txid:0"],
    totalAmountSat: 100000
)

// Mock VTXO health
let mockHealth = VTXOHealth.calculate(
    from: mockVTXOs,
    currentBlockHeight: 849900,
    expiryThresholdBlocks: 144
)
```

## Future Enhancements

Potential additions (not implemented):
1. Push notifications for exits becoming claimable
2. Auto-refresh for expiring VTXOs
3. Connection quality metrics (latency tracking)
4. Historical exit tracking/analytics
5. Batch exit operations
6. VTXO consolidation recommendations

## Migration Notes

If migrating an existing wallet:
- Old exits will not be tracked (only new exits started after implementation)
- Backup status will be created on first launch
- No data migration required for existing transactions
