# Wallet Deletion & Rejoin

Status: IMPLEMENTED (Phases 1–4) — 2026-08-19; on-device verification pending
(see Definition of done). Implementation notes: the wipe-coverage inventory
immediately caught two more schema/wipe drift victims (`PendingPaymentMetadata`,
`PendingTagAssignment` — now wiped); the app schema is canonicalized in
`SwiftDataHelper.appSchemaModels` and both app targets build their container
from it; rejoin UI lives in `Shared/Views/FirstUse/RejoinWalletView.swift`.
Owner: Christoph
Related: `Initialization/Launch_Sequence_Contract.md`, `Initialization/STARTUP_WALLET_DETECTION_PLAN.md`, `Features/Read_Only_Mode.md`

## Problem statement

The system is designed around **one wallet per iCloud account**, but the deletion and
onboarding flows don't enforce it. Investigation on 2026-08-19 found three problems,
one of them a live seed-destroying bug:

### Bug 1 (live, severity: seed loss): local-only deletion deletes the shared seed anyway

`BarkWalletFFI.deleteWallet()` ("Step 2", `BarkWalletFFI+WalletCreation.swift`) calls
`securityService.deleteWalletData(includeCloudData: false)`, which deletes the
**synchronizable** mnemonic keychain item. `WalletManager` injects the real
`SecurityService` (`WalletManager.swift:306`), and `DeleteWalletSettingView` calls
`walletManager.deleteWallet()` right after the strategy-aware
`WalletDataCleanupService.deleteWalletData(...)`. Result: even when the cleanup
service correctly *keeps* the mnemonic (localOnly strategy, other devices active),
the FFI layer deletes it one call later. Deleting a synchronizable item propagates
through iCloud Keychain **account-wide**: other devices keep running off the seed
copy inside their bark db, but keychain-based promotion, recovery-phrase display,
and reinstall silently break.

This is a second deletion site missed by the 2026-08-12 deletion-strategy fix
(which moved keychain deletion into the full-wipe branch of
`WalletDataCleanupService` only). The planned two-device on-device verify would
have caught it; it hasn't run yet.

### Bug 2: `SecurityService` carries an incomplete duplicate of the full wipe

`SecurityService.deleteWalletData` + `deleteAllWalletDataFromSwiftData` duplicate
`WalletDataCleanupService.deleteCloudKitData` but are missing `PersistentAddress`
(address history), `PersistentExitCache` (exit history), `BackupStatus`, and
`UserProfile`. The cloud branch is currently dead (only caller passes
`includeCloudData: false`), but it's a partial-wipe trap for any future caller.

### Bug 3: post-deletion routing allows creating a second wallet

`onWalletDeleted` in both `MainView_iOS.swift` and desktop `MainView.swift` sets
`hasWallet = false` without re-running detection, dropping straight into the
onboarding flow. The first-use screen offers **Create**, and
`WalletManager.createWallet` → `saveMnemonic` **overwrites** the synchronizable
keychain item and the ubiquitous hash. After a local-only deletion (where the old
seed is deliberately kept for the other devices), creating a new wallet replaces
the old seed on every device via iCloud Keychain. If the user never wrote down
the recovery phrase, the old wallet's funds are unrecoverable.

Additionally, once Bug 1 is fixed, a *fourth* problem appears: after a local-only
deletion the seed is still readable on this device, so the next cold launch
detects `.walletWithSeed` and silently resurrects the wallet — "Delete from this
device" wouldn't stick. The tombstone (Phase 2) exists to prevent exactly this.

Import is already safe: `validateMnemonic` returns `.invalid` when the phrase
doesn't match the reference hash, and `importWallet` rejects it.

## Product decisions (Christoph, 2026-08-19)

- One wallet per iCloud account is a hard invariant, enforced in code.
- After a local-only deletion, the device shows a dedicated **rejoin screen**
  ("your wallet lives on <device>; rejoin?") instead of onboarding. No Create.
- Wallet creation is refused whenever the account already has a wallet
  (defense in depth below the UI).

## Design

### Deletion authority

`WalletDataCleanupService` is the **only** component allowed to touch the
mnemonic keychain item, the ubiquitous hash, and CloudKit data during deletion.
`BarkWalletFFI.deleteWallet()` is demoted to what an FFI wrapper should be:
shutdown + wallet-directory removal. This matches the existing convention that
the FFI layer carries no app policy.

### Tombstone

A device-local UserDefaults marker (NOT iCloud KVS, NOT CloudKit — it describes
*this install's* deliberate choice):

- Key: `com.arke.wallet.deletedLocally`
- Value: the wallet hash the deletion applied to (string), not a bool.
  Storing the hash makes staleness detectable: if the account's current KVS
  hash differs (old wallet fully wiped elsewhere, new one created), the
  tombstone is obsolete and must be cleared.

Lifecycle:

| Event | Tombstone action |
|---|---|
| Local-only deletion completes | Set to current ubiquitous hash |
| Full wipe (last device) completes | Cleared (nothing to rejoin) |
| User taps Rejoin | Cleared, then detection re-runs |
| Create/import succeeds | Cleared |
| Detection sees no KVS hash, or a different hash | Cleared (stale) |

Ordering constraint: the cleanup service's `clearUserDefaults()` step must not
remove the tombstone — set it after that step runs (or keep the key out of the
cleared list; both, for safety).

### Detection & routing

New `WalletState` case: `.walletAvailableToRejoin(deviceName: String)`.

`performWalletStateDetection` checks the tombstone **before** trusting any
wallet signal:

1. If tombstone present and its hash == current KVS hash → return
   `.walletAvailableToRejoin` (primary device name looked up as in the existing
   `.walletActiveElsewhere` branch). This must apply in the `.found` branch AND
   the `.unavailable` (keychain unreadable) fallback — a tombstoned device must
   never low-confidence-route into the wallet.
2. If tombstone present but KVS hash missing/different → clear tombstone,
   continue normal detection.

Both `MainView`s:

- `onWalletDeleted` stops sync/services (as today) and then **re-runs
  `checkForExistingWallet()`** instead of setting `hasWallet = false`.
- New routing branch: `.walletAvailableToRejoin` → `RejoinWalletView` (shared
  view with `#if` islands, per convention). No wallet initialization, no device
  registration in this state (the device deliberately unregistered itself).

The App-level early check (`mnemonicKeychainStatus()` → `initialWalletDetected`)
needs **no change**: it only gates early service start, and both MainView paths
run deep detection afterwards, which is tombstone-aware. Early CloudKit sync
starting on a tombstoned device is desirable — the rejoin screen needs the
device registry to name the primary.

### Rejoin screen (v1 scope)

`RejoinWalletView` (Shared/Views/FirstUse/): explains the wallet is still active
on <primary device name>, one primary action **Rejoin this wallet**:

1. Clear tombstone.
2. Re-run `checkForExistingWallet()` → `.walletWithSeed` → normal init path
   (restore from preserved iCloud backup; registration with
   `allowPrimaryClaim: false`, i.e. rejoins as secondary).

Deliberately out of v1: recovery-phrase entry (seed is guaranteed present — it
was kept), "delete everything from here" (Settings on a rejoined device covers
it). If the keychain is transiently unreadable, Rejoin surfaces the error and
the user retries; the existing protected-data/foreground re-detection hooks
also apply.

### Creation guard

`WalletManager.createWallet` refuses to run when the account already has a
wallet. Guard at the top, before anything is generated or saved:

- `securityService.getUbiquitousHash() != nil`, or
- `SecurityService.mnemonicKeychainStatus() == .found`, or
- tombstone present

→ throw a new typed error (e.g. `BarkErrorArke.walletAlreadyOnAccount`) whose
message points at rejoin/import. Import needs no guard (hash validation covers
it) and must stay available.

Residual risk (accepted): a genuinely fresh install whose KVS initial sync
hasn't landed yet can pass the guard. Mitigation kept cheap: the existing KVS
observers re-route as soon as the hash arrives; a `synchronize()` nudge before
the guard check is optional polish.

## Phases

### Phase 1 — single deletion authority (fixes Bug 1 + Bug 2)

1. `BarkWalletFFI+WalletCreation.swift` `deleteWallet()`: remove Step 2
   (`securityService.deleteWalletData(...)` call). Renumber/redo comments.
2. `SecurityService.swift`: delete `deleteWalletData(includeCloudData:)` and
   `deleteAllWalletDataFromSwiftData` (~200 lines). Keep `removeMnemonic()`
   (import rollback) and the ubiquitous-hash helpers (used elsewhere).
3. Update the `BarkWalletProtocol` doc comment for `deleteWallet()` to state it
   does not touch the keychain.
4. Verify: only production path into `wallet.deleteWallet()` is
   `DeleteWalletSettingView` → `WalletManager.deleteWallet()`, which always runs
   after the cleanup service. (Confirmed 2026-08-19.)

### Phase 2 — tombstone + rejoin

1. `SecurityService`: static tombstone helpers
   (`recordLocalDeletionTombstone(walletHash:)`, `clearLocalDeletionTombstone()`,
   `localDeletionTombstoneHash()`), UserDefaults-backed.
2. `WalletState`: add `.walletAvailableToRejoin(deviceName: String)`.
3. `performWalletStateDetection`: tombstone check per Design; extract the
   routing decision into a pure, testable helper
   (signals + tombstone → state), mirroring `ImportRecoveryLogicTests` style.
4. `WalletDataCleanupService.performDeleteWalletData`: on `!includeCloudData`,
   set the tombstone (capture hash first; set after `clearUserDefaults()`).
   On full wipe, clear it.
5. `RejoinWalletView` (shared, `#if` islands).
6. Both MainViews: `onWalletDeleted` → re-detect; route new state; handle it in
   `checkForExistingWallet()` (no init, no registration).
7. New strings via `defaultValue:`; run translation lint per localization
   workflow.

### Phase 3 — creation guard

1. `BarkErrorArke`: new case `walletAlreadyOnAccount` with localized description.
2. `WalletManager.createWallet`: guard per Design (pure helper for testability).
3. Onboarding UI: no structural change (routing + guard cover it); surface the
   typed error cleanly if it ever fires.

### Phase 4 — docs & bookkeeping

1. `Launch_Sequence_Contract.md`: add rules — "post-deletion routing must re-run
   full detection" and "only WalletDataCleanupService may delete the mnemonic".
2. `Open_Follow_Ups.md`: close the SecurityService-duplicate item; add the
   on-device verification items below.

## Definition of done

Phases 1–3 are not "done" on green unit tests alone. The two-device on-device
matrix below (at minimum scenarios 1 and 3) must run on hardware before this
work is marked complete anywhere (memory, `Open_Follow_Ups.md`, commit
message). Rationale: the 2026-08-12 deletion fix was declared FIXED with its
device verify deferred, and that verify was the only check capable of catching
the second deletion site (Bug 1).

## Test plan

Unit (Testing framework, scoped per lean-verification workflow):

- Detection routing helper: matrix over {mnemonic found/notFound/unavailable} ×
  {KVS hash present/absent/mismatched} × {tombstone present/absent} — asserts
  rejoin state, staleness clearing, and that tombstone beats low-confidence
  `.walletWithSeed`.
- Tombstone helpers: set/clear/read roundtrip; `clearUserDefaults()` does not
  clear it.
- Creation guard helper: refuses on each signal, allows when clean.
- Existing `WalletCleanupKeychainDeletionTests` unchanged (still the only
  keychain-deletion coverage — now the only code path too).
- **Schema-coverage test (anti-regression for Bug 2's class):** iterate every
  entity in the app's SwiftData `Schema` and assert it appears in
  `WalletDataCleanupService`'s deletion coverage (an explicit list the service
  exposes), with an allowlist for types deliberately excluded. Adding a new
  `@Model` without deciding its deletion fate then fails a test instead of
  silently surviving wipes. This is why the duplicate wipe drifted: nothing
  forced new stores into the inventory.
- Full mobile suite batch at task end.

Review sweep (one-time, part of Phase 1 review): enumerate every
`SecItemDelete` in the codebase; after Phase 1 exactly three owners are
legitimate — WalletDataCleanupService (strategy-aware wipe), SecurityService
`removeMnemonic()` (import rollback), and device-ID management. Anything else
is a policy leak.

On-device verification (decisive; two linked devices, signet):

1. Local-only delete on secondary → primary's keychain seed still present
   (Settings → recovery phrase still displays); deleted device shows rejoin
   screen; relaunch deleted device → still rejoin screen (no resurrection).
2. Rejoin → wallet restores from preserved iCloud backup, registers as
   secondary, balances/history correct. Watch for the known created_now
   recovery-scan gate: rejoin relies on the backup restore path, not a bark
   seed-recovery scan — verify restored state matches.
3. Local-only delete on primary → secondary can promote (the original
   2026-08-12 verify, now meaningful because the seed actually survives).
4. Full wipe on last device → onboarding with Create available; tombstone gone.
5. Tombstoned device while other devices full-wipe → device falls through to
   normal onboarding (stale tombstone cleared).
6. Attempt create via any path on an account with a wallet → typed error.

## Edge cases considered

- **Keychain unreadable at launch on a tombstoned device** → rejoin state, never
  low-confidence wallet init (tombstone checked in the `.unavailable` branch).
- **Wallet fully wiped elsewhere, then re-created elsewhere** → KVS hash differs
  from tombstone hash → tombstone cleared → device routes to
  `.walletActiveElsewhere`/read-only for the new wallet, as designed.
- **Read-only (secondary, no-seed) device deleting locally** → same flow;
  strategy resolves localOnly; rejoin works once the seed syncs (existing
  seed-not-synced handling applies after rejoin).
- **iCloud account switch** (`NSUbiquitousKeyValueStoreAccountChange`) → hash
  mismatch clears the tombstone; normal detection for the new account.
- **Import on a tombstoned device** → allowed; same-phrase only (hash
  validation); success clears the tombstone.
