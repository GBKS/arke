# Delete Everywhere: Skip the Final Backup

**Status: DECIDED 2026-10-14 (Tier 0, Train 1, deletion cluster) — BUILT
and REVIEWED 2026-10-14 (uncommitted; adversarial pass in §10, one
CONFIRMED finding fixed in-session; full mobile suite 504/504 on the
iPhone 17 Pro simulator). Test choice DECIDED 2026-10-14: no
backup-directory injection; proof is the device check plus the
wipe-inventory entry. Device check DONE 2026-10-14 21:24 export (§8): two
full wipes logged the skip line, the import between them found no backup,
the new wallet's first backup is its own. App-switch variant DONE in the
21:50 export: the background hook was refused ("Backup skipped - wallet
deletion in progress") 1.3 s before the shutdown's skip. Side finding from
the first run, fixed and device-checked in the second: a stale onchain row
reappeared in the new wallet (§11). Nothing left on device for this item.**

Backlog entry: `Open_Follow_Ups.md`, Tier 0, "'Delete everything' re-creates
the iCloud backup it just deleted". Area doc:
`Wallet_Deletion_And_Rejoin.md`; contract rules 17–21 in
`../Initialization/Launch_Sequence_Contract.md`.

## 1. Problem

The last-device full wipe empties the iCloud Drive backup folder, then the
FFI shutdown that follows writes a fresh backup of the wallet it is about to
delete. After "Delete everything" the account still holds a copy of the
deleted wallet's offchain database.

## 2. Trace (all **verified**, read 2026-10-14)

| Step | Where | What |
|---|---|---|
| 1 | `DeleteWalletSettingView.swift:369-375` | cleanup service runs first, `walletManager.deleteWallet()` second |
| 2 | `WalletDataCleanupService.swift:336` | full wipe only: `WalletBackupService.deleteAllBackups()` removes current, legacy and timestamped copies |
| 3 | `WalletManager+Wallet.swift:512-563` | steps 1–4 (reset state, clear notifications, unregister push, settle) never touch the FFI handle; step 5 calls `wallet.deleteWallet()` |
| 4 | `BarkWalletFFI+WalletCreation.swift:697` | FFI `deleteWallet()` calls `shutdownWallet()` before removing the directory; it has no guard on the handle itself |
| 5 | `BarkWalletFFI+WalletLifecycle.swift:406-453` | `shutdownWallet()` stops the daemon, runs a final `sync()`, then **unconditionally** calls `backupWallet()` at `:437` |
| 6 | `BarkWalletFFI+Backup.swift:26` | `backupWallet()`'s only guard is `wallet != nil`, still true here |
| 7 | `WalletBackupService.swift:147-218` | `performBackup()` writes `Backups/db.sqlite` and a timestamped copy into the ubiquity container |

## 3. Consequence, corrected

The cleanup service's comment ("a leftover backup would resurface via the
restore-on-launch path after a new wallet is created") overstates the
common case. **Derived** from `WalletManager.swift:1381-1450`:

- Right after creation the wallet is open, and `restoreWalletIfNeeded`
  returns at the `wallet == nil` guard (`:1391`).
- On later launches a local file exists, and the newest-wins compare
  (`:1425`) keeps the local file because the leftover backup predates it.
- The import path only logs that a backup exists
  (`BarkWalletFFI+WalletCreation.swift:408-414`), it does not restore.

The branch that does restore is the **no-local-file** branch (`:1399-1416`):
a primary launch with no bark directory (reinstall before creating,
restored app sandbox, a secondary promoted on an account that was wiped and
re-created) pairs the dead wallet's database with whatever seed the
keychain holds. The second harm needs no branch at all: the offchain state
of a wallet the user asked to delete everywhere stays in iCloud Drive.

## 4. Design

The scope decision stays in the policy layer. The FFI keeps deleting files
only (rule 19) and `BarkWalletProtocol` is unchanged.

1. `BarkWalletFFI.shutdownWallet(backingUp: Bool = true)` — FFI-internal
   (not on the protocol, like `stopDaemonWait`). `false` skips the final
   backup and logs "Skipping final backup (full wipe)" at notice level.
   Every existing caller keeps the default.
2. `nonisolated enum DeletionScope { case localOnly, everywhere }` next to
   `DeletionStrategy`; `DeletionSummary` gains `scope`, set by
   `performDeleteWalletData` from the `includeCloudData` it actually ran
   with. The view hands `summary.scope` on, so the manager learns the scope
   from the deletion that happened, not from a recomputation.
3. `WalletManager.deleteWallet(scope:)`: on `.everywhere`, after step 4 and
   before step 5, call `shutdownWallet(backingUp: false)` on the FFI. The
   FFI's own `deleteWallet()` then enters `shutdownWallet()` with a nil
   handle and returns at its first guard (`:407`), so the delay and sync
   run once. On `.localOnly` nothing changes: the final backup is the
   newest copy of the primary's database, and a promoted secondary with no
   local file restores exactly that slot (`:1399`) — load-bearing, keep it.
4. `SharedStateWipeCoverage` gets an entry for the iCloud Drive backup
   (`Backups/db.sqlite` + timestamped copies, scope `.fullWipeOnly`), and
   `criticalSharedStateIsFullWipeOnly` pins it. That is the decision test;
   the ordering itself is proven on device (§8).
5. Launch contract: rule 17 gains the clause that on a full wipe the FFI
   shutdown writes no backup, since the cleanup service emptied the slot
   one step earlier and nothing after it may refill it.
6. **Added after the adversarial pass (§10, finding 1):** the opportunistic
   backups are suspended for the whole deletion. `BarkWalletFFI.backupWallet()`
   (the entry point of the app background hook and the manual button)
   refuses while `opportunisticBackupsSuspended` is set; the shutdown's own
   final backup goes through `runBackupNow()` and bypasses the suspension,
   so the local-only path still writes its copy. The delete view sets the
   flag through `WalletManager.setWalletDeletionInProgress(_:)` before the
   cleanup service starts and clears it in a `defer`, on every outcome: the
   FFI object outlives the handle and serves the next wallet created in the
   same process, so a sticky flag would silence that wallet's backups.

Rejected: deleting the backups after the manager's delete (a second cloud
deletion site outside the cleanup service, and it would move a cloud
deletion after the seed deletion, breaking the seed-last ordering at
`WalletDataCleanupService.swift:358`); a flag on the protocol's
`deleteWallet()` (app policy on the FFI surface).

## 5. Claims the design rests on

- **verified** `shutdownWallet` is not on `BarkWalletProtocol`
  (`BarkWalletProtocol.swift` has `deleteWallet` only, grep 2026-10-14).
- **verified** FFI `deleteWallet()` does not guard on the handle, so a
  pre-shutdown does not change its file deletion
  (`BarkWalletFFI+WalletCreation.swift:681-724`).
- **verified** `WalletManager.deleteWallet()` has one caller, the delete
  view (grep 2026-10-14).
- **derived** the view-side scope equals the service's: the service throws
  `fullWipeScopeInvalidated` rather than downgrading
  (`WalletDataCleanupService.swift:265-270`), so a returned summary carries
  the scope that ran.
- **verified** `deleteAllBackups()` returns `false` when the ubiquity
  container is nil; the summary then says `iCloudBackupDeleted == false`.
  With no container, `performBackup()` also skips, so the fix changes
  nothing in the offline case.

## 6. Sweep — `shutdownWallet()` callers

| Site | Verdict |
|---|---|
| `BarkWalletFFI+WalletCreation.swift:697` (FFI delete) | covered — no-op after the pre-shutdown on `.everywhere`; backs up on `.localOnly`, intended |
| `WalletManager+Wallet.swift:498` (`closeWallet`) | exempt — caller-less, slated for deletion with the Live Activity demotion item (DECIDED 2026-10-10) |
| `WalletManager.swift:1221` (demotion, `closeWalletForMigration`) | exempt — files stay, the backup is what the new primary may restore |
| `BarkWalletFFI+Backup.swift:95` (`restoreWalletFromBackup`) | exempt — both callers (`WalletManager.swift:1405`, `:1432`) run under the `wallet == nil` guard at `:1391`, so the shutdown is a no-op; latent trap filed in §9 |
| `BarkWalletFFI+WalletCreation.swift:93`, `:384` (create/import with a live instance) | exempt — replacing an open wallet; a backup of the outgoing one is harmless and matches today |

`backupWallet()` callers (`ArkeMobile.swift:150` background,
`BackupStatusSectionView_iOS.swift:121`, desktop `ManualBackupView.swift:142`,
`ArkeDesktop.swift:105`): all go through `backupWallet()`, which now
refuses during a deletion (design item 6) and returns on a nil handle after
it — covered. The plan's first draft called the background-hook window "a
few seconds" and filed it as a residual; the adversarial pass measured it
at two network calls plus 1.5 s of sleeps and rated it CONFIRMED, see §10.

## 7. Tests

- `WalletDeletionRejoinTests.criticalSharedStateIsFullWipeOnly` pins the
  new inventory key. Scoped run of `WalletDeletionRejoinTests`.
- No test on the shutdown ordering (DECIDED 2026-10-14, option 1): it would
  need an injectable backup directory and a stand-in for the FFI shutdown,
  and would still not exercise the bark call that writes the file.

## 8. Device check (owed)

One device, the last registered one, with iCloud Drive on. Before: Settings
→ Backup status shows a backup. Delete wallet → Delete everything, and stay
in the app until onboarding appears (the first run of the check); on a
second run, switch to another app while the spinner shows, to exercise the
suspension. Expected device log lines during the delete: "Skipping final
backup (full wipe)" and, on the second run, "Backup skipped - wallet
deletion in progress". Then create a new wallet and relaunch: the log says
"Local wallet file exists, no backup available", never "Restoring". The
Files app cannot show the folder — `Backups/` sits at the container root,
not under `Documents/` (`WalletBackupService.swift:35-37`), so the log and
the Backup status section are the evidence. The local-only path still
backing up is covered by the two-device deletion set on the Device
checklist, not here.

### 8.1 Result (Christoph's export `arke-debug-20261014-212434.log`, mainnet, build 24)

| Time (UTC) | Line | Meaning |
|---|---|---|
| 19:22:13 | `Skipping final backup (full wipe) — the backup slot stays empty` | wipe 1, the skip ran |
| 19:23:10 | import of the same phrase; no `iCloud backup detected` line | `hasBackupAvailable()` at import found the slot empty |
| 19:24:03 | `Skipping final backup (full wipe) …` | wipe 2, the skip ran |
| 19:24:07 | `Wallet backup completed` right after `Created wallet with fingerprint` | the new wallet's own first backup, expected |
| 19:24:13 | `Wallet is open - skipping backup restore check` | post-create initialize, guard at `WalletManager.swift:1391` |

Second run, export `arke-debug-20261014-215001.log` (import of the old
wallet, full wipe with an app switch during the spinner, new wallet):

| Time (UTC) | Line | Meaning |
|---|---|---|
| 19:49:21 | `Retrieved 1 onchain transactions`, onchain balance 20,000 | the imported wallet's onchain receive is in memory |
| 19:49:34.5 | `Backup skipped - wallet deletion in progress` | the `.background` hook fired inside the wipe window and was refused |
| 19:49:35.8 | `Skipping final backup (full wipe) …` | the shutdown's own skip |
| 19:49:43 | `Created wallet with fingerprint`, then `Wallet backup completed` | the new wallet and its own first backup |
| 19:49:48 | Step 2b, `saved 0 new, 0 updated` | the merge that re-created the stale row the first time now has nothing to merge (§11 fix) |
| 19:49:55 | `Retrieved 0 onchain transactions` | bark agrees |

Christoph confirmed the Activity tab was empty. No cold relaunch after the
create in either run, so the "no backup available" launch line is unseen;
the import-time check in run 1 is the equivalent evidence for the slot.

## 9. Side findings (filed, not fixed here)

- `restoreWalletFromBackup` shuts the wallet down *with* a backup before
  restoring: if ever called with an open handle it would overwrite the
  backup slot with the local database and then "restore" that same file.
  Guarded today only by the caller's nil check. Tier 4.
- `deleteAllBackups()` lists the folder with `.skipsHiddenFiles` and
  treats an unreadable directory as success (`WalletBackupService.swift:452-457`).
  A backup that this device never downloaded shows as a hidden `.icloud`
  placeholder and would be skipped while the summary reports the slot
  emptied — the case is a promoted former secondary doing the full wipe.
  iCloud Drive semantics unverified (does `removeItem` on a placeholder
  delete the ubiquitous item? can the writing device evict its own file?).
  Belongs to the Tier 0 "Backup restore is newest-wins with no wallet
  binding" design pass, which already owns the backup file format; the
  two-device run is: A backs up, B (never restored) wipes, a fresh install
  checks `hasBackupAvailable()`.

## 10. Review record (2026-10-14, fault-class-reviewer, same session)

Handed the working-tree diff and the area name. Findings and what was done:

1. **CONFIRMED, class 3** — the app's `.background` hook
   (`ArkeMobile.swift:150`) calls `backupWallet()` with only the nil-handle
   guard; on a full wipe the handle stays non-nil from `deleteAllBackups()`
   through CloudKit deletes, keychain delete, push unregister (network),
   daemon stop, the final `sync()` (network) and 1.5 s of sleeps. An app
   switch during the spinner refills the slot before the skip runs. The
   first draft had filed this as a Tier 4 residual with a wrong size.
   **Fixed in-session**: design item 6 (suspension), ledger line.
2. **PLAUSIBLE, class 4** — `.skipsHiddenFiles` vs `.icloud` placeholders.
   Pre-existing; filed in §9 under the backup-binding item.
3. **PLAUSIBLE, class 5** — §8's Files-app check could never show the
   folder. §8 rewritten around the log lines and the Backup status section.
4. **PLAUSIBLE, class 5** — the summary-scope test re-asserted
   `includesCloudData` and rule 17's Test column overclaimed. Test reduced
   to the merge-cannot-narrow case; rule 17 now says the writer → reader
   link is traced by hand and proven on device.
5. Doc drift — the backlog's "done means" still named the dropped ordering
   test; §4.1 said info level where the code logs notice. Both corrected.

## 11. Side finding from the device check (filed Tier 1, Data safety)

The run's new wallet showed the deleted wallet's 20,000-sat onchain receive
with a 0 balance. Not this change: `OnchainTransactionService` is never
reset on deletion and Step 2b (`31e2f10`) now merges before Step 3's fresh
onchain fetch, so the stale in-memory list is re-persisted into the new
wallet. Full trace, both triggers and the fix shape are in the backlog entry
"A deleted wallet's onchain row reappears in the next wallet created in the
same process"; ledger line 2026-10-14.

Sound per the reviewer, with what was checked: class 1 (the only new store
decision is not writing, and only on the scope the owning service set),
class 2 (one caller; FFI delete unchanged; slot readers enumerated; §3's
corrected consequence accurate), re-entry through the dedup key, the
cleanup-throws error path, cold start. Not verified by the reviewer: any
device behaviour, two-device scenarios, iCloud Drive delete semantics, the
relay unregister timeout, the full mobile suite.
