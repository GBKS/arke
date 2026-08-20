# Launch Sequence Contract

Ordering invariants around app startup, wallet open/create/import, first
sync, exit progression, and multi-device detection. Each rule was learned
from an incident — the "or else" column is not hypothetical. This is a
contract, not a narrative: for flow walkthroughs see
`INITIALIZATION_FLOWS.md`.

**Maintenance:** when a startup-shaped bug is fixed, add its rule here (same
reflex as updating `Open_Follow_Ups.md`). Any PR that touches launch
ordering must check itself against this list. A rule whose Test column says
*none* is enforced by comments alone — that column doubles as the extraction
backlog for the pure-logic pattern (`ExitProgressionLogic` /
`ExitClaimSequence` style).

## Opening the wallet

**1. One single-step `Wallet.open` performs creation — never `initWallet()` first.**
A prior `initWallet` writes the properties row, turning the open into a
"subsequent" open and permanently disabling bark's seed-recovery scan (gated
on `created_now`), with no error and no re-scan API. We shipped this shape
for months; imports silently never recovered (2026-08-10, feedback §1.7).
Enforced: `BarkWalletFFI+WalletCreation.swift`. Test: none.

**2. Seed-only import: a nil recovery report means wipe-and-reopen, and `skipRecovery` stays false.**
A failed scan is indistinguishable from a skipped one, and the scan runs only
on the creating open — so on nil report, stop the daemon, wipe the
seconds-old database, redo the creating open (bounded retries). Fresh-seed
*creation* uses `skipRecovery: true`; import must never.
Enforced: `BarkWalletFFI+WalletCreation.swift` (`openImportedWallet`,
decision in `ImportRecoveryLogic`). Test: `ImportRecoveryLogicTests`
(decision matrix; the wipe-before-reopen mechanics remain code-only).

**3. Wallet existence is `db.sqlite` OR `bark.sqlite` — never recreate-from-seed on a "missing" database.**
bark 0.11+ creates `db.sqlite`; a `bark.sqlite`-only probe false-detected "no
wallet" and restored a stale backup over a fresh wallet.
Enforced: `WalletBackupService.swift`. Test: none.

**4. Backup restore runs only when no wallet is open.**
An open wallet is authoritative; restoring over it pairs the keychain
mnemonic with a foreign database (e.g. a stale backup from a previously
deleted wallet, right after creation).
Enforced: `WalletManager.swift` (`restoreWalletIfNeeded`). Test: none.

**5. Network mismatch: seed-only import wipes stale data and retries; backup import surfaces the error and never wipes.**
Leftover data from another network can't be the wallet being seed-imported —
but a user-picked backup file is precious and the mismatch is user error.
Enforced: `WalletManager+Wallet.swift` (`importWallet` vs
`importWalletWithBackup`). Test: none.

**6. The mnemonic keychain item migrates to `afterFirstUnlock` at launch (idempotent).**
Background sync needs the seed after one unlock per boot; `whenUnlocked`
starves background tasks.
Enforced: `SecurityService.swift`. Test: `KeychainAccessibilityMigrationTests`.

## First refresh and sync

**7. Load/reveal addresses before the onchain history and balance reads.**
bark's revealed-SPK sync scans nothing until at least one address is
revealed; on a fresh import the first balance read must come after the
reveal or it reports zero (fixed 2026-08-12, commit `fc9a006`-adjacent).
Enforced: `WalletManager.swift` (`performRefresh`, addresses-first step). Test: none.

## Exit progression and Live Activities (iOS)

**8. Launch order: reattach → first `checkAndProgressExits` → `recreateMissingActivities` → reminder re-arm.**
On a fresh seed import bark replays already-completed exits through the
state machine, so they read as in-flight until the first pass settles them —
recreating earlier spawned a "Move complete 5/5" lock-screen activity for an
exit finished long ago (2026-08-13).
Enforced: `ExitProgressionLogic.swift` (`LaunchSequence.run`, called from
`ExitProgressionService.start`). Test: `ExitProgressTests`
(`LaunchSequenceTests/launchOrderIsPinned`).

**9. Activity recreation filters on `isInFlight`, never `isActive`.**
Claimed and cancelled exits stay in bark's exit list; an `isActive` filter
respawns a "complete" activity on every launch.
Enforced: `ExitProgressionService+LiveActivity.swift`
(`recreateMissingActivities`). Test: none.

**10. `endLiveActivity` recomputes step totals from fresh statuses when the caller has them.**
The last pushed update can predate the transaction chain becoming known
(fresh-import replay), freezing a short step estimate into the final banner
(the 5/5-instead-of-6/6 half of the 2026-08-13 incident).
Enforced: `ExitProgressionService+LiveActivity.swift` (`endLiveActivity`).
Test: none (aggregate math itself: `ExitProgressTests`).

**11. Claim sequence order is load-bearing: `recordClaim` immediately after broadcast; `snapshotStatuses` after `progressExits`.**
bark purges claimed exits from `getExitVtxos()` shortly after the claim —
the drained VTXO ids and the `ClaimInProgress` state carrying the claim txid
exist only in that window; miss it and the fee and claim links are gone
(feedback §1.5).
Enforced: `ExitProgressionLogic.swift` (`ExitClaimSequence.run`).
Test: `ExitProgressTests` (`testSequenceOrder`).

**12. Already-cancelled movements keep their date frozen on upsert.**
bark re-finishes cancelled exits on every sync where the tip advanced,
bumping `completed_at`; only the first transition into cancelled may set the
date (feedback §1.4).
Enforced: `WalletManager+Transactions.swift` (upsert).
Test: `TransactionUpsertDateFreezeTests`.

**13. Check-in reminders re-arm on every launch/backgrounding while exits are in flight, and clear when none are — after the first progression pass.**
Reminders used to be scheduled only at exit start and cancelled on launch,
so any relaunch mid-exit permanently disarmed them; re-arming before the
first pass arms them for replayed already-finished exits.
Enforced: `ExitProgressionService+LiveActivity.swift`
(`rescheduleCheckInRemindersIfNeeded`), `ArkeMobile.swift` (scene phase). Test: none.

## Multi-device

**14. Check demotion before opening the wallet.**
A demoted device must fall back to read-only mode without touching the seed;
the layered check (UserDefaults → iCloud KV → CloudKit cache) runs as step 0
of initialization.
Enforced: `WalletManager.swift` (`performInitialization`,
`shouldBlockWalletAccess`). Test: none (reconciliation half is tested, see 15).

**15. Primary status is claimed only by explicit create/import — never inferred by detection paths.**
"First device" inference under sync lag created two primaries; detection
paths pass `allowPrimaryClaim: false`, and duplicates converge via
deterministic self-demoting reconciliation (earliest `becamePrimaryAt`,
deviceId tiebreak).
Enforced: `DeviceRegistrationService.swift` (`registerCurrentDevice`,
`reconcilePrimaryConflicts`). Test: `PrimaryDeviceReconciliationTests`.

**16. The device ID keychain item is non-synchronizable.**
It distinguishes "this device was wiped" from "the seed arrived on a new
device" — syncing it would collapse that distinction.
Enforced: `DeviceRegistrationService.swift` (`getOrCreateDeviceId`). Test: none.

## Deletion

**17. Deletion order: reset manager state → end Live Activities immediately (sweep all, not just the tracked one) → clear notifications → unregister push → settle → delete files → clear local evidence.**
State reset first prevents operations mid-deletion; the *immediate* activity
end matters because the standard end shows an hour-long summary advertising
an exit of a wallet that no longer exists, and the sweep catches orphans
from failed reattaches.
Enforced: `WalletManager+Wallet.swift` (`deleteWallet`),
`ExitProgressionService+LiveActivity.swift` (`endLiveActivityImmediately`). Test: none.

**18. `includeCloudData` is strategy-derived; the seed is deleted only on a last-device full wipe.**
A fixed value either orphaned secondaries or destroyed the only seed copy
(fixed 2026-08-12).
Enforced: `WalletManager+Wallet.swift` (deletion strategy). Test: none.

**19. Only `WalletDataCleanupService` may delete the mnemonic keychain item.**
A second deletion site inside `BarkWalletFFI.deleteWallet()` deleted the
synchronizable seed on *every* deletion — including local-only — propagating
account-wide via iCloud Keychain and defeating rule 18 one call later
(found 2026-08-19). The FFI layer deletes files only; keychain policy is the
cleanup service's alone. Legitimate `SecItemDelete` owners: the cleanup
service, `removeMnemonic()` (import rollback), and the accessibility
migration's delete-and-re-add fallback.
Enforced: `BarkWalletFFI+WalletCreation.swift` (comment),
`BarkWalletProtocol.swift` (contract). Test: none (sweep: grep `SecItemDelete`).

**20. Post-deletion routing re-runs full detection; a local-only deletion routes to the rejoin screen, never onboarding.**
`onWalletDeleted` used to set `hasWallet = false` blindly, exposing
onboarding's Create path — which overwrites the account's synchronizable
seed. The local-deletion tombstone (UserDefaults, stores the wallet hash)
suppresses seed-based resurrection at relaunch and routes to
`.walletAvailableToRejoin`; `createWallet` independently refuses when any
account-level wallet signal exists (`Wallet_Deletion_And_Rejoin.md`).
Enforced: `SecurityService.swift` (`tombstoneRouting`, detection step 0),
`MainView_iOS.swift` / `MainView.swift` (`onWalletDeleted`),
`WalletManager+Wallet.swift` (`accountHasWalletSignals` guard).
Test: `WalletDeletionRejoinTests`.

**21. Account-shared key-value state (KVS network config, KVS wallet hash, keychain seed) is deleted only by WalletDataCleanupService on a full wipe — never by device-scoped deletion paths.**
`WalletManager.deleteWallet()` used to call `NetworkConfigPersistence.clear()`
unconditionally, removing the shared network config from iCloud KVS on every
deletion: a local-only delete on one device stranded the live secondary on
default-mainnet, whose signet db then failed to open with a network mismatch
that looked like total data loss (2026-08-20). Same fault class as rule 19.
`clearLocal()` vs `clearEverywhere()` make the scope explicit; the inventory
of shared keys and their scopes lives in `SharedStateWipeCoverage`. Related:
initialization recovers a missing local config from iCloud before the first
wallet open (`performInitialization` step 0-pre) instead of silently
defaulting to mainnet.
Enforced: `NetworkConfigPersistence.swift`, `WalletDataCleanupService.swift`
(`SharedStateWipeCoverage`), `WalletManager.swift` (step 0-pre).
Test: `WalletDeletionRejoinTests` (inventory consistency).

## Test gaps

Rules with no pinning test, roughly by risk: 1, 3, 4, 14, 17. Covered since
2026-08-14: rule 8 (`LaunchSequence`, `ExitProgressionLogic.swift`) and
rule 2's decision matrix (`ImportRecoveryLogic`,
`BarkWalletFFI+WalletCreation.swift`) — the pattern to follow for the rest.
Next candidate: wallet-detection decisions (rules 3/4/14, overlaps the
optional startup-detection Phase 5 refactor).
