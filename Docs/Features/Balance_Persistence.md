# Balance Persistence

**Status:** Shipped; refreshed against the code 2026-09-27.

## Overview
Both balances are stored in SwiftData so the app can show the last known figures immediately on launch and keep working offline. The Ark and onchain balances follow the same pattern: one singleton `@Model` row per balance type, upserted after every successful wallet fetch and read back synchronously when the service receives its `ModelContext`. The rows are CloudKit-mirrored, which is also how secondary (read-only) devices get a balance at all.

## Files

### Models (`Shared/Models/`)
- **ArkBalanceModel.swift**: `@Model` for the Ark balance. The former separate `PersistedArkBalance` type was unified into this class (10/29/25).
- **OnchainBalanceModel.swift**: `@Model` for the onchain balance, unified from `PersistedOnchainBalance` the same way.

### Schema
- **Shared/Data/SwiftDataHelper.swift**: `appSchemaModels` is the canonical schema list; both balance models are entries. `ArkeMobile/ArkeMobile.swift` and `ArkeDesktop/ArkeDesktop.swift` build their `ModelContainer` from it.

### Services
- **Shared/Services/BalanceService.swift**: primary-device service; fetches from the wallet, upserts the rows.
- **Shared/Services/ReadOnlyBalanceService.swift**: secondary-device service; reads the rows only (see below).
- **Shared/Data/WalletManager/WalletManager.swift**: `setModelContext(_:)` hands the context to whichever balance service is active.
- **Shared/Views/Settings/WalletDataCleanupService.swift**: `deleteBalanceCache()` is the only code that deletes the rows.

## Implementation Details

### 1. Persistence Models

#### ArkBalanceModel
```swift
@Model
class ArkBalanceModel {
    var id: String = "ark_balance"  // Singleton approach
    var spendableSat: Int = 0
    var pendingLightningSendSat: Int = 0
    var pendingInRoundSat: Int = 0
    var pendingExitSat: Int = 0
    var pendingBoardSat: Int = 0
    var lastUpdated: Date = Date()
}
```

#### OnchainBalanceModel
```swift
@Model
class OnchainBalanceModel {
    var id: String = "onchain_balance"  // Singleton approach
    var totalSat: Int = 0
    var confirmedSat: Int = 0
    var pendingSat: Int = 0
    var lastUpdated: Date = Date()
}
```
`spendableSat` on the onchain model is computed (`confirmedSat`). The model was simplified to match the FFI's `OnchainBalance` (total / confirmed / pending); the older trusted/untrusted/immature split no longer exists.

**Key Features:**
- Singleton by convention, using fixed IDs ("ark_balance" and "onchain_balance"). CloudKit forbids unique constraints, so duplicates can exist; every fetch sorts by `lastUpdated` descending and takes the newest.
- Every stored property has a default value, as CloudKit requires.
- `init(from:)` and `update(from:)` convert from the `ArkBalanceResponse` / `OnchainBalanceResponse` API structs; `isValid` reports whether the row is younger than 5 minutes.

### 2. BalanceService Persistence Integration

**Methods:**
- `setModelContext(_:)`: stores the context, then runs both loads synchronously and calls `updateTotalBalance()`. Synchronous on purpose, so the first render already has a balance card.
- `loadPersistedArkBalanceSync()` / `loadPersistedOnchainBalanceSync()` (private): newest-first fetch of the singleton row; assigns it to `arkBalance` / `onchainBalance` whether or not it is stale.
- `updateArkBalanceFromResponse(_:)` / `updateOnchainBalanceFromResponse(_:)` (private): upsert. Updates the existing row in place via `update(from:)`, or inserts a new one via `init(from:)`, then `modelContext.save()`.
- `resetBalancesInMemory()`: clears `arkBalance`, `onchainBalance`, `totalBalance`, and `error` without touching the rows. This is the only reset the service offers, including for wallet close and deletion (`WalletManager+Wallet.swift`).

**Refresh paths:** `refreshArkBalance()`, `refreshOnchainBalance()`, and `refreshAllBalances()` all go through the `updateXFromResponse` upsert after a successful fetch, so the persisted row is always the latest fetched value.

**Deletion:** because the rows sync through CloudKit, deleting them from `BalanceService` would replicate account-wide and zero a read-only device's displayed balance. Deletion therefore lives only in `WalletDataCleanupService.deleteBalanceCache()`, which runs on a full wipe (Launch Sequence Contract rule 23).

### 3. Cache Strategy

- **Always show the persisted row.** On load, the persisted balance is assigned regardless of age; `isValid` only changes the log line ("valid" vs "stale, will refresh in background").
- **Always refresh from the wallet.** The 5-minute window does not gate fetching; the normal refresh cycle runs and the upsert replaces the persisted values when it completes.
- **No data:** the UI gets zero-balance models from `updateTotalBalance()` until the first fetch (or, on a secondary device, the first CloudKit import) lands.
- **Graceful degradation:** every persistence failure is logged and swallowed; the in-memory state still updates from the API response path where it can.

## Read-Only Devices: ReadOnlyBalanceService

Secondary devices never run the wallet (see [Read-Only Mode](../Features/Read_Only_Mode.md)), so their only balance source is the pair of rows the primary device wrote and CloudKit synced. `ReadOnlyBalanceService` has no wallet dependency: `setModelContext(_:)` performs the same newest-first synchronous loads as `BalanceService`, calls `updateTotalBalance()`, and installs a `.cloudKitDataDidChange` observer (once). Each notification re-runs `refreshBalances()`, which re-reads both rows and recomputes the total; `WalletManager.refreshBalances()` and pull-to-refresh reach the same method in read-only mode. Without the observer, a fresh secondary install showed 0 sats all session because its one load ran before the first import arrived. `isWaitingForInitialSync` (both rows still `nil`) lets the UI say "syncing from iCloud" rather than presenting the zero-filled placeholders as fact. The notification pipeline (debounce, throttle) is described in [CloudKit Realtime Sync](../Architecture/CloudKit_Realtime_Sync.md).

## Benefits

### User Experience
- **Instant Balance Display**: last known balances render on the first frame, before any network round trip.
- **Offline Capability**: both balance types are available when the network is unavailable.
- **Multi-device**: the same rows are what a read-only device displays.

### Reliability
- **Graceful Degradation**: the app functions normally even if persistence fails for either balance type.
- **Independent Failures**: one balance type can fail without affecting the other.
- **Duplicate-safe reads**: newest-first ordering means a stale duplicate row from another device cannot shadow the current one.

## Testing
- `Tests/Shared/ReadOnlySyncedDataTests.swift`: `ReadOnlyBalanceService` picks up rows that arrive after init, re-reads a row updated in place by another context, re-reads on explicit `refreshBalances()`, and resolves duplicate singletons newest-first.
- `Tests/Shared/WalletDeletionRejoinTests.swift`: asserts every entry of `appSchemaModels` (including both balance models) has a declared wipe fate.
- There is no direct unit test of `BalanceService`'s upsert path or of the models' `isValid` / `init(from:)` / `update(from:)` conversions; those are covered only indirectly.

## Usage
The persistence layer is transparent to the UI. Views read `arkBalance`, `onchainBalance`, and `totalBalance` off `WalletManager`, which forwards to `BalanceService` or `ReadOnlyBalanceService` depending on `isReadOnlyMode`. No caller needs to know whether a value came from the wallet or from the store.
