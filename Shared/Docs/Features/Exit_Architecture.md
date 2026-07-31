# Unilateral Exit — Architecture

One-page map of the exit subsystem: who owns what, how data flows, and the
constraints that shaped it. Incident history and design rationale live in
the companion docs ([Exit_Blocked_State](Exit_Blocked_State.md),
[Exit_Completion_Issues](Exit_Completion_Issues.md),
[Exit_Refresh_Coordination](Exit_Refresh_Coordination.md),
[Movement_Onchain_Linking](../Movements/Movement_Onchain_Linking.md)).

Last updated: 2026-07-30 (bark 0.11).

## Lifecycle

```
Start → Processing → AwaitingDelta → Claimable → ClaimInProgress → Claimed
                                                                 ↘ VtxoAlreadySpent (cancelled)
```

- bark owns the state machine; the app polls and nudges it.
- The bark daemon usually performs Processing → Claimable transitions but
  **never claims**. Claiming is the app's job.
- bark's `hasPendingExits()` counts only Start/Processing/AwaitingDelta.
  Claimable and ClaimInProgress exits need their own probes or they strand
  (see `ExitProgressionLogic.requiredWork`).

## Ownership

| Concern | Owner | Where |
|---|---|---|
| All exit state (live exits, statuses, blocked records, disk cache) | `ExitStore` | `Shared/Data/WalletManager/WalletManager+Exits.swift` |
| Facade for call sites (`activeUnilateralExits`, `refreshExitCache`, …) | `WalletManager` extension | same file, delegates to the store |
| When to progress/claim (pure decisions) | `ExitProgressionLogic` | `Shared/Services/ExitProgressionLogic.swift` |
| The fund-moving claim order (drain → broadcast → record → progress → snapshot) | `ExitClaimSequence` | same file |
| Polling loop, effects, Live Activities | `ExitProgressionService` | `Shared/Services/ExitProgressionService.swift` (+LiveActivity) |
| Claim/exit tx ↔ movement linking | `TransactionLinkingService` | `Shared/Services/TransactionService/` |
| Durable exit history | `PersistentExitCache` (SwiftData) | `Shared/Models/PersistentExitCache.swift` |
| bark-string → typed state parsing | `ExitStatusParser` → `ParsedExitState` | `Shared/Data/ExitStatus/` |
| UI step model (banner, timeline, Live Activity all share it) | `ExitProgress` | `Shared/Data/ExitStatus/ExitProgress.swift` |

`ExitStore` gets wallet access injected via `WalletHooks` (it outlives
wallet sessions — the disk cache loads before the wallet opens) and reports
user-visible changes through `onStateChange` (bumps `dataVersion`).

## The load-bearing constraint: bark purges claimed exits

Once an exit completes, bark removes it from `getExitVtxos()` — fast enough
that polling can miss ClaimInProgress/Claimed entirely (observed on device
2026-07-30; feedback doc §1.5). Per-id `getExitStatus(vtxoId:)` appears to
keep answering, so the loss is enumeration — but the in-memory status cache
is scoped to the list, so anything reading only that cache goes blind after
the purge. Everything below follows from this:

- **Capture at drain time.** The moment `drainExits` returns,
  `ExitClaimSequence` records the claim fee, links the claim tx to its exit
  movement(s) (`recordClaimFee` → `linkClaimTransaction`), and snapshots
  each exit's status to disk. Waiting for the next poll would lose the data.
- **`PersistentExitCache` is merge-saved, never wiped.** Entries that
  vanish from bark's list are the only surviving record; a vanished
  ClaimInProgress entry is finalized as claimed.
- **`getExitStatus` falls back to the persisted snapshot**, which keeps
  completed exits inspectable (X-Ray completed section, exit detail sheet).
- **The movement relink resolves statuses with the same fallback** (cache →
  per-id lookup/snapshot), so an onchain record that appears only after the
  purge — e.g. a late CPFP re-bump synced by BDK — still gets linked on the
  next relink instead of stranding in the activity list (field case
  2026-07-30, txid 0dc9ffa0…).

Cancelled exits (`VtxoAlreadySpent`) are the opposite: they linger in
bark's list forever, so "active" filtering must use `isInFlight`.

## Data flow (one refresh)

```
ExitProgressionService (5-min timer / manual)
  → probes bark (pending? claimable? claim-in-progress?)   [gate: ExitProgressionLogic]
  → wallet.progressExits()                                 [blocked bookkeeping per VTXO]
  → auto-claim if claimable                                 [ExitClaimSequence]
  → wallet.syncExits()
  → walletManager.invalidateExitCache()
      → ExitStore.refresh():  fetch exits → prune stale blocked records
        → fetch statuses → merge-save to disk → relink movements (once)
  → update Live Activities
```

Concurrent `refresh()` calls join the in-flight one. Linked onchain txs get
`parentTxid` set and disappear from the activity list (the movement shows
instead); fee attribution divides shared children (batch claims, shared
CPFPs) across their movements.

## UI surfaces

- **Activity**: swipe card + detail view show `TransactionClaimExitBanner`
  (step bar via `ExitProgress`), loading through
  `WalletManager.exitData(forInputVtxoIds:)`; tapping opens
  `ExitStatusSheet` → `ExitStatusDetailView_iOS` (full timeline, works for
  completed exits via the snapshot fallback).
- **X-Ray** (`UnilateralExitListView_iOS`): live exits from bark plus the
  persisted completed-exits section.
- **Settings → Exit** (`ExitView_iOS`): start flow + cost estimate.
- **Live Activity** (`ExitProgressLockScreenView`): lock-screen step bar.

## Tests

`Tests/Shared/`: `ExitStatusParserTests` (string parsing),
`ExitProgressTests` (step model + progression gate + claim sequence order),
`ExitBlockedInfoTests` (classification, debounce, + `ExitStoreTests`:
refresh joining, single relink, purge-survival, blocked pruning),
`ExitFeeAttributionTests` (fee shares, third-party CPFP exclusion,
claim linking), `TransactionUpsertDateFreezeTests` (cancelled-exit dates).

Untested by design choice: `ExitProgressionService`'s shell (timer/Live
Activity wiring) — its decisions and sequences are the extracted, tested
parts.

## Fragility to keep in mind

`ExitStatusParser` reverse-engineers Rust `Debug` strings; every bark
release can silently change the format (it did in 0.11). The parser
defaults to `.unparsed` rather than failing. The real fix is typed exit
states over the FFI — feedback doc §1.1.
