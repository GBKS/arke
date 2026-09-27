# Process State Service

**Status:** shipped; refreshed against the code 2026-09-27 (exit tracking moved
out — see [Exit_Architecture](../Features/Exit_Architecture.md)).

## Overview

`ProcessStateService` is `WalletManager`'s small side-service for wallet
*health* state: which VTXOs are expired or about to expire, whether the Ark
server answered on the last refresh, whether this device is in read-only mode,
and whether the user should be nudged to back up their seed. It owns one
persisted SwiftData row (`BackupStatus`) and two in-memory values
(`VTXOHealth`, `ConnectionStatus`).

It does **not** track unilateral exits any more. The original
`OngoingUnilateralExit` model and its start/claim/cancel API were removed in
commit `788b51f` (2026-01-09, "rely on what bark provides"). Exit state now
lives in `ExitStore` / `ExitProgressionService` / `PersistentExitCache`; see
[Exit_Architecture](../Features/Exit_Architecture.md). The only remaining
link is that `WalletManager`'s attention summary (below) reads exit counts
from the exit facade alongside the health state from this service.

## Files

| File | Contents |
|---|---|
| `Shared/Data/ProcessState/ProcessStateService.swift` | `ProcessStateService`, `ProcessStateError` |
| `Shared/Data/ProcessState/VTXOHealth.swift` | `VTXOHealth` (struct), `VTXOHealthPriority` |
| `Shared/Data/ProcessState/BackupStatus.swift` | `BackupStatus` (`@Model`), `ReminderPriority`, singleton helpers |
| `ArkeUI/Sources/ArkéUI/Data/ConnectionStatus.swift` | `ConnectionStatus`, `ConnectionQuality`, `ReadOnlyReason` (public, in the ArkéUI package so sheets can render it) |
| `Shared/Data/WalletManager/WalletManager+ProcessState.swift` | `WalletManager` facade + attention aggregation |

## The service

```swift
@MainActor
@Observable
final class ProcessStateService {
    private(set) var vtxoHealth: VTXOHealth            // computed each refresh
    private(set) var connectionStatus: ConnectionStatus // in-memory
    private(set) var backupStatus: BackupStatus?        // SwiftData singleton
    private(set) var currentBlockHeight: Int            // cached from last refresh
    private(set) var error: String?                     // load failure text

    init()
    func setModelContext(_ context: ModelContext)       // loads/creates BackupStatus

    func refreshAll(vtxos: [VTXOModel], blockHeight: Int,
                    isConnected: Bool, connectionError: String? = nil)
    func refreshVTXOHealth(vtxos: [VTXOModel], blockHeight: Int, thresholdBlocks: Int = 144)
    func updateConnectionStatus(connected: Bool, quality: ConnectionQuality? = nil, error: String? = nil)
    func updateReadOnlyMode(isReadOnly: Bool, reason: ReadOnlyReason? = nil)

    var shouldShowBackupReminder: Bool
    func confirmBackup() throws
    func incrementBackupTransactionCount()              // non-throwing, logs on failure
    func snoozeBackupReminder() throws
    func dismissBackupReminder() throws

    var needsAttention: Bool   // vtxoHealth.needsAttention || shouldShowBackupReminder || connectionStatus.showWarning
}

enum ProcessStateError: LocalizedError {
    case noModelContext
    case backupStatusNotFound
}
```

Observation is Swift `@Observable` (not `ObservableObject`); everything is
main-actor. The service is plain `init()` — no dependencies — and is not
registered in `ServiceContainer`.

### Ownership and wiring (all in `WalletManager`)

- **Creation:** `WalletManager.initializeServices()` sets
  `processStateService = ProcessStateService()` next to the other per-wallet
  services (`WalletManager.swift`, stored as `var processStateService: ProcessStateService?`).
- **Model context:** `WalletManager.setModelContext(_:)` forwards to
  `processStateService?.setModelContext(context)`, which fetches the first
  `BackupStatus` row or inserts and saves a fresh one.
- **Refresh:** at the end of the wallet refresh (`performRefresh` Step 4)
  `refreshProcessStates(isConnected: anyServerCallSucceeded)` fetches VTXOs via
  `getVTXOs()` (falls back to `[]` on error), takes
  `balanceService?.estimatedBlockHeight ?? 0`, passes `WalletManager.error`
  (first error among address/transaction/balance/onchain services) as
  `connectionError`, and calls `refreshAll(...)`.
- **Transaction counter:** the `WalletOperationsService` transaction-completed
  callback calls `processStateService?.incrementBackupTransactionCount()`.
- **Read-only mode:** `updateReadOnlyMode(isReadOnly:reason:)` is called from
  `checkReadOnlyMode()`, from the demotion / `forceReadOnly` branches of wallet
  initialization, and from the primary-device migration path. `reason` comes
  from `currentReadOnlyReason()` (`.notPrimary` or `.seedNotSynced`).

## State categories

### 1. VTXO health — `VTXOHealth` (computed, not persisted)

```swift
struct VTXOHealth: Sendable {
    var expiredVTXOs: [VTXOModel]
    var vtxosExpiringSoon: [VTXOModel]
    var thresholdBlocks: Int            // default 144 (~1 day)

    static func calculate(from vtxos: [VTXOModel], currentBlockHeight: Int,
                          expiryThresholdBlocks: Int = 144) -> VTXOHealth
}
```

`calculate` classifies unspent VTXOs only:
- **expired** — `expiryHeight <= currentBlockHeight`
- **expiring soon** — `0 < expiryHeight - currentBlockHeight <= threshold`

Derived members: `hasExpiredVTXOs`, `hasVTXOsExpiringSoon`, `needsAttention`,
`expiredCount`, `expiringSoonCount`, `totalExpiredAmount`,
`totalExpiringSoonAmount`, `formattedExpiredAmount`,
`formattedExpiringSoonAmount` (via `BitcoinFormatter`), `statusMessage`
(localized `balance_vtxos_*` keys, nil when healthy), `actionMessage`
(hard-coded English), `priority: VTXOHealthPriority` (`.critical` if any
expired, `.high` if any expiring soon, else `.normal`), plus per-VTXO helpers
`blocksUntilExpiry(for:currentHeight:)`, `estimatedTimeUntilExpiry` (10 min per
block) and `formattedTimeUntilExpiry` (`format_approx_*` keys).

O(n) over the VTXO list, recomputed on every refresh; a block height of 0
(balance service not ready) makes everything look healthy.

### 2. Server connection — `ConnectionStatus` (in-memory, ArkéUI)

```swift
public struct ConnectionStatus: Sendable {
    public var isConnected: Bool                 // default false
    public var quality: ConnectionQuality        // excellent / good / poor / disconnected
    public var lastSuccessfulSync: Date?
    public var reconnectionAttempts: Int
    public var lastError: String?
    public var isReadOnlyMode: Bool
    public var readOnlyReason: ReadOnlyReason?   // .notPrimary | .seedNotSynced
}
```

Display helpers: `statusMessage` ("Read-only mode" wins over connection
text), `detailedMessage` ("Last synced …"), `showWarning` (false while
read-only; true when disconnected or poor), `shouldShowIndicator` (also true
in read-only), `canPerformCollaborativeOperations`.

How it is actually fed: `updateConnectionStatus(connected:)` calls
`markConnected(quality: .excellent)` on success (the `quality` parameter is
never passed by any caller) and `markDisconnected(error:)` on failure, so in
practice `quality` is only ever `.excellent` or `.disconnected`. The
`good`/`poor` tiers, `ConnectionQuality.from(lastSuccessfulSync:)`,
`from(latencyMs:)`, `incrementReconnectionAttempt()` and `updateQuality(from:)`
exist on the type but are not driven by the service.

The default value (`isConnected: false`) means "nothing attempted yet", not
"offline" — `WalletManager.isArkServerReachable` treats a status with neither
`lastSuccessfulSync` nor `lastError` as reachable so Lightning destinations are
not ruled out at startup.

### 3. Backup reminders — `BackupStatus` (persisted, CloudKit-synced singleton)

```swift
@Model final class BackupStatus {
    var id: UUID                              // no @Attribute(.unique) — CloudKit compatibility
    var hasConfirmedBackup: Bool
    var lastBackupConfirmationDate: Date?
    var transactionsSinceLastReminder: Int
    var lastReminderShownDate: Date?
    var reminderDismissCount: Int
    var snoozedUntilDate: Date?
    var lastUpdated: Date

    static let transactionThreshold = 5
    static let reminderIntervalDays = 7
    static let snoozeHours = 24
}
```

`shouldShowReminder()` returns, in order:
1. `false` if `hasConfirmedBackup`
2. `false` while `snoozedUntilDate` is in the future
3. `true` if `transactionsSinceLastReminder >= 5`
4. `true` if the reminder was shown ≥ 7 days ago
5. `true` if it was never shown and there are ≥ 3 transactions
6. otherwise `false`

Mutations (all set `lastUpdated`): `confirmBackup()` (sets confirmed, clears
counter/dismiss count/snooze), `incrementTransactionCount()`,
`markReminderShown()`, `snoozeReminder()` (dismiss count +1, snooze 24 h, reset
counter), `dismissReminder()` (dismiss count +1, reset counter, mark shown,
clear snooze). The service's `dismissBackupReminder()` calls both
`dismissReminder()` and `markReminderShown()`. Display: `reminderMessage`
(hard-coded English) and `reminderPriority: ReminderPriority`
(`.high` ≥ 10 tx, `.medium` ≥ 5, else `.low`).

Singleton helpers: `BackupStatus.getSingleton(context:)` (returns the first
row and deletes duplicates) and `exists(context:)`; `SwiftDataHelper`
additionally exposes `uniqueness.getBackupStatus()` /
`cleanupDuplicateBackupStatus()`. Note that `ProcessStateService.loadPersistedData()`
uses a plain fetch + `.first` and never calls the de-duplicating helpers; two
devices creating the row before their first CloudKit merge can therefore leave
duplicates that nothing currently cleans up.

## `WalletManager` facade (`WalletManager+ProcessState.swift`)

```swift
var processStateServiceInstance: ProcessStateService?

func confirmBackup() throws            // BarkErrorArke.commandFailed if the service is nil,
func snoozeBackupReminder() throws     // otherwise forwards and rethrows ProcessStateError
func dismissBackupReminder() throws

var vtxoHealth: VTXOHealth             // VTXOHealth() when the service is nil
var connectionStatus: ConnectionStatus // ConnectionStatus() when nil
var isArkServerReachable: Bool         // optimistic until the first sync result
var backupStatus: BackupStatus?
var shouldShowBackupReminder: Bool

// Attention aggregation — combines this service with the exit facade
var attentionItemCount: Int            // expiredCount + exitsRequiringAction.count + (reminder ? 1 : 0)
var needsAttention: Bool               // vtxoHealth || hasExitsRequiringAction || reminder || connection warning
var attentionSummary: String?          // messages joined with " • ", nil when nothing to say
```

`exitsRequiringAction`, `activeUnilateralExits`, `hasExitsRequiringAction`
and `hasActiveUnilateralExits` are `[ExitVtxo]`-based properties of
`WalletManager+Exits.swift`, backed by `ExitStore` — not by this service.

## Who reads it today

- **`connectionStatus`** is the only value with view consumers:
  `ActivityView_iOS` (toolbar indicator, `isReadOnlyMode` gating,
  `ConnectionInfoSheet` from ArkéUI), `ExitView_iOS` (`isConnectedToServer`),
  `MainView_iOS` (`readOnlyReason == .seedNotSynced` to detect seed arrival),
  and `WalletManager.isArkServerReachable` for payment routing.
- **`vtxoHealth`**, **`backupStatus` / `shouldShowBackupReminder`** and the
  attention aggregates (`needsAttention`, `attentionSummary`,
  `attentionItemCount`) have **no view consumers** in ArkeMobile or ArkeDesktop
  as of this refresh. The transaction counter still accrues, so the reminder
  state is real; it just is not surfaced. (The `onBackupReminder` callback in
  the onboarding flows is a separate, one-off post-import prompt.)
- No unit tests target these types directly; `BackupStatus` is covered only
  indirectly by the wipe-coverage test through the schema list.

## Persistence and sync

- `BackupStatus` is listed in `SwiftDataHelper.appSchemaModels`, the single
  schema list both apps build their container from
  (`ArkeMobile.swift` / `ArkeDesktop.swift` →
  `createAppModelContainer(cloudKitEnabled: true,
  cloudKitContainerIdentifier: "iCloud.gbks.sigma")`). It therefore syncs via
  CloudKit like every other model in the list; all properties have defaults
  and there is no unique constraint, as CloudKit requires.
- Deletion fate: `WalletWipeCoverage.directlyWiped` includes `BackupStatus`;
  `WalletDataCleanupService.deleteBackupStatus(modelContext:)` removes all rows
  during a wallet wipe.
- `VTXOHealth` and `ConnectionStatus` are never persisted; they are rebuilt on
  the first refresh after launch.

## Error handling

`confirmBackup()`, `snoozeBackupReminder()` and `dismissBackupReminder()`
throw `ProcessStateError.noModelContext` before `setModelContext` has run and
`.backupStatusNotFound` if the singleton failed to load (the load failure text
is also kept in `error`). `incrementBackupTransactionCount()` swallows save
failures with a log line. `refreshAll` cannot fail. Through the `WalletManager`
facade, a missing service surfaces as `BarkErrorArke.commandFailed(...)`.

## Known gaps

- Connection quality is binary in practice (`.excellent` / `.disconnected`);
  the intermediate tiers and reconnection-attempt counter are unused.
- `actionMessage` and `reminderMessage` are not localized.
- Duplicate `BackupStatus` rows from CloudKit merges are not cleaned up
  (helpers exist, nothing calls them).
- The backup reminder and VTXO health warnings have no UI; whether to surface
  them (or drop the state) is an open product question.
