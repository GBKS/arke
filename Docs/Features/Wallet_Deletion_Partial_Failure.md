# Wallet Deletion: Gate on Refresh, Then Handle Partial Failure

**Status: DECIDED 2026-10-15 (Tier 0, Train 1, deletion cluster) — gate
approach and route-anyway both ruled by Christoph the same day. BUILT and
REVIEWED 2026-10-15 (uncommitted): adversarial pass in §10, four findings,
three fixed in-session and one claim corrected; scoped deletion suites
green on the iPhone 17 Pro simulator; full mobile suite `** TEST SUCCEEDED **`
after the review fixes (the pass count was not captured — the shell hook
timed out before the result bundle could be read). Device check DONE,
reported by Christoph 2026-10-16: "works great" — passed in aggregate, no
log lines read; the §9 markers remain unverified individually. Item
closed in the backlog; nothing left on device for it.**

Backlog entry: `Open_Follow_Ups.md`, Tier 0, "Delete flow has no
partial-failure handling" (includes the refresh-vs-deletion race added
2026-10-14; trigger (2) of the Tier 1 "deleted wallet's onchain row
reappears" item). Area doc: `Wallet_Deletion_And_Rejoin.md`; contract rules
17–24 in `../Initialization/Launch_Sequence_Contract.md`; sibling plans
`Wallet_Deletion_Backup_Skip.md`, `Wallet_Deletion_Phrase_Confirmation.md`.

## 1. Problem

Two faults in one function (`DeleteWalletSettingView.deleteWallet`,
`DeleteWalletSettingView.swift:416-479`):

1. **The deletion races the refresh.** The cleanup service deletes the
   CloudKit-mirrored rows while the launch refresh may still be running;
   the refresh's later steps insert the rows again. The 2026-10-14 device
   log showed Step 3.1 re-creating a deleted onchain row 0.9 s after the
   wipe.
2. **No failure path is handled.** A throw from the cleanup service leaves
   the user on a disabled slider sheet with the error hidden behind it; a
   throw from the manager after the cleanup succeeded leaves the user in
   the wallet UI of a wallet that no longer exists on the account. The
   screen's `isDeleting` is never reset.

## 2. Principle (Christoph, 2026-10-15)

A destructive action does not start while background work could fight it.
The user waits **before** committing, visibly and with a reason, instead of
the app pausing mid-wipe. Same move as explicit device linking: slightly
more friction, clearer understanding, fewer error paths, less code.

## 3. Trace: why wait-before and not cancel or wait-inside

All **verified** 2026-10-15 unless marked.

| # | Where | Fact |
|---|---|---|
| 1 | `WalletManager.swift:869-903` | `refresh()` runs `performRefresh()` under the dedup key `"refresh"`; `isRefreshing` is set while any call is active (`:876-896`). |
| 2 | `TaskDeduplicationManager.swift:57-80` | The work is an **unstructured** `Task<Void, Never>`; callers only await its value, so cancelling a caller does nothing. |
| 3 | `WalletManager.swift:523-539`, `:684-778` | The launch refresh is nested in the `"initialize"` key, which also runs `refreshExitCache()` (`:737`) and seeding (`:743`) after it. Those writes outlive `isRefreshing`. |
| 4 | `WalletManager.swift:905-1126` | `performRefresh` never checks cancellation; its FFI syncs cannot be interrupted. |
| 5 | `TaskDeduplicationManager.swift:143-163` | `cancel`/`cancelAll` are no-ops (cast never matches; executed as a script 2026-10-15; playbook O4, Tier 4 item). |
| 6 | `WalletManager.swift:1082`, `UnifiedTransactionService.swift:299-355`; `TransactionService+Upsert.swift:120, 185` | Steps 2b, 3 and 3.1 insert every row missing locally; the orphan check only warns (`:399`), so rows re-created after the wipe stay for the next wallet. |

**Conclusion (derived):** cancelling is impossible and waiting inside the
wipe needs a pause, a resume and a timeout. Gating the button on the same
flag costs none of that.

## 4. Design

### 4.1 The gate (fault 1)

1. **A "busy loading" signal on the manager.** New computed property
   `isLoadingWalletData`: `isRefreshing || taskManager.isRunning(key: "initialize")`.
   The second half covers the launch's exit-cache write and seeding, which
   `isRefreshing` does not (§3 row 3).
2. **The delete screen waits on it.** While the signal is true, Continue
   (and the override link) are replaced by a spinner row "Finishing the
   current refresh…", the same shape as the existing "Checking for other
   devices..." row (`DeleteWalletSettingView.swift:127-135`). Localized via
   `defaultValue:`. The user can leave the screen at any time.
3. **Re-check at the first destructive step.** A refresh can start between
   the button lighting up and the slide (mailbox push). The cleanup service
   already re-derives the scope immediately before its first step and
   aborts with `fullWipeScopeInvalidated`, nothing deleted
   (`WalletDataCleanupService.swift:265-269`). The refresh check slots in
   beside it: the view passes `walletManager.isLoadingWalletData` as a
   closure (the service does not know `WalletManager`); if it is true at
   that moment, throw the new `WalletCleanupError.refreshInProgress`,
   handled in the view exactly like the scope-invalidated abort (sheet and
   phrase screen dismissed, error on the info screen: "A refresh started
   while you were confirming. Nothing was deleted — try again in a
   moment."). The check runs before `unregisterCurrentDevice`, so it is
   literally pre-destructive.
4. **No new refresh during the wipe.** `WalletManager` gets
   `isDeletionInProgress`, set by the view where it sets the backup
   suspension today (`:423-424`) and cleared in the same `defer`;
   `setWalletDeletionInProgress(_:)` sets both flags. `performRefresh`
   gains one guard next to the not-open skip (`:940`):
   `⏭️ [Refresh] Skipped — wallet deletion in progress` at notice level
   (rule O3 shape). Covers the mailbox-push refresh, the only `refresh()`
   caller reachable while the delete screen is up (pull-to-refresh and the
   wallet-view reappearance refresh need another screen).
5. **Seeding checks the flag too.** The `.waitForFirstImport` branch spawns
   a free task that waits up to 90 s and then seeds, guarded only on
   read-only mode (`WalletManager.swift:800-806`); a full wipe inside that
   window would seed 9 tags and the faucet contact into the wiped account.
   `runSeedingFunnels()` returns early when `isDeletionInProgress || !isInitialized`.

### 4.2 Partial failure (fault 2)

Failure points, the state they leave, and the response:

| Failure | State | Response |
|---|---|---|
| `fullWipeScopeInvalidated`, `refreshInProgress` | nothing deleted | dismiss sheet + phrase screen, error on the info screen, Continue retries (existing path, extended by one case) |
| `noModelContext` | today thrown after four account-level writes (`:343`); moved to the top of `performDeleteWalletData` → nothing deleted | same as above |
| `saveFailed` from `deleteCloudKitData` | fetch or save threw; today after KVS hash, mirror, network config and backups are gone, with partially queued deletes left in the context | **reorder**: run `deleteCloudKitData` before the KVS/backup block, and `modelContext.rollback()` on throw (**verified** in the SwiftData docs: discards pending inserts and deletes). Result: account untouched except Step 1's unregister, which the retry repeats harmlessly. Dismiss sheet, error on the info screen. |
| `keychainDeletionFailed` | seed intact; CloudKit rows, hash, mirror, network config (iCloud **and** local, `clearEverywhere()`), backups gone | unchanged order (seed last, 2026-09-25). Dismiss sheet, error on the info screen. Retry traced: the hash is gone, so `otherDeviceReport(walletHash: nil)` takes the unscoped registry fallback (`DeviceRegistrationService.swift:676-687`), whose rows the first attempt deleted → `.noneFound` → `.promptForCloudData` → the retry reaches the full wipe (**derived**, pinned by a test). **If the user does not retry** (review finding 4): the wallet keeps working in-process, the next refresh re-creates its history rows from bark, and the next cold launch reconciles to `.noUsableConfig` with a seed present and opens on the default network — a signet wallet then hits the 2026-08-20 mismatch shape. Rare (SecItemDelete failing in the foreground) and recovered by a second deletion; recorded, not built for. |
| `walletManager.deleteWallet(scope:)` throws after the cleanup returned | account-side deletion complete (seed gone on `.everywhere`, tombstone written on `.localOnly`); bark files may remain; manager state reset | the deletion is **committed** (§8 ruling): log at error level, `clearLocalWalletEvidence()` anyway, **mark the directory stale** (`SecurityService.recordStaleWalletDirectory`), still call `onWalletDeleted` so routing re-runs detection (rule 20). Inside `deleteWallet(scope:)`, retry `wallet.deleteWallet()` once after 500 ms (**assumed** cause: a still-held SQLite handle; the import path sleeps 500 ms before its `removeItem` for that stated reason, `WalletManager+Wallet.swift:279`). The stale marker exists because the ruling's premise was half wrong (review finding 1): the FFI create removes an existing directory, but **import does not** — bark refuses to open a database whose fingerprint does not match the phrase ("incorrect mnemonic", `bark/src/lib.rs:1336`), so importing a *different* phrase would fail on every attempt. `createWallet`, `importWallet` and `importWalletWithBackup` now remove a marked directory first and clear the marker; `hasLocalWalletEvidence()` ignores a marked directory so the keychain-unreadable detection branch cannot route a wiped install back into the wallet UI (finding 1b). An unmarked directory is never touched: a database with no readable seed can also be a transiently unreadable keychain. |

Every failure before the keychain step leaves a wallet that keeps working,
with no services to restart, because nothing was paused; the keychain step
itself is the one exception, see its row.

The view's `isDeleting` is reset in the `defer` with the flags. The slider
sheet's own `isDeleting` is never reset and its `deleteError` is never set
(`DeletePermanentlyConfirmationView.swift:28, 310`); with the parent
dismissing the sheet on every failure both become harmless, and the dead
`deleteError` state goes.

### 4.3 Contract

Rule 17 gains: "Deletion does not start while wallet data is loading
(`isLoadingWalletData`): the delete screen waits visibly, the cleanup
service re-checks at its first step and aborts with nothing deleted, and
`refresh()` skips while a deletion is in progress. A failure before the
seed step leaves a working wallet; a failure after the cleanup returned
never blocks routing." The "known gap" sentence at the end of rule 17 goes.
Playbook stub O3 gets the deletion skip as a second enforcement site.

Rejected: cancelling the refresh (§3); pausing inside the cleanup service
with a resume and a timeout (first draft of this plan, 2026-10-15 — more
machinery for the same user-visible wait, and it hid the wait inside the
destructive flow); continuing past a keychain failure (the seed left in
iCloud Keychain resurrects the wallet via seed recovery); moving the KVS
hash deletion after the seed step (retry already works, see §4.2).

## 5. Sweep: writers that can land after the row deletion

| Writer | Where | Verdict |
|---|---|---|
| Refresh Steps 2b/3/3.1, balance rows, address rows, Step 4 exit cache | `"refresh"` key | covered — gate + re-check + skip |
| `refreshExitCache()` and `.seedNow` seeding after the launch refresh | `"initialize"` key | covered — `isRunning("initialize")` half of the gate |
| Seeding `.waitForFirstImport` waiter | `WalletManager.swift:800-806` | covered — §4.1.5 |
| Mailbox-push `refresh()` | `WalletManager+Notifications.swift:345` | covered — skip during the wipe; before the wipe it flips the gate and the re-check catches the slide |
| `WalletNotificationService` → `processSingleMovement` upsert | `TransactionService.swift:185-203` | **residual** — one row if a payment lands inside the 5–15 s wipe; services are stopped only in `resetManagerState()` after the cleanup. Field evidence is refresh-only; recorded in rule 17, not built for. |
| Exit / round / Lightning-claim timers | `*Service` | **residual**, same reasoning; exit cache is merge-saved |
| `refreshExitCache()` from `WalletManager+Exits.swift:465` | exit progression path | residual, same as above |
| `registerForPushNotifications` fire-and-forget | `WalletManager.swift:770` | exempt-because: one relay round trip right after launch; a late write leaves stale relay bookkeeping for the next wallet (rule 27). Filed §7. |
| `registerDeviceIfNeeded` (launch) and the `onWalletReady` registration | `MainView_iOS.swift:47-73, 169` | exempt-because: outside every key and outside the manager; a late registration after `unregisterCurrentDevice` re-creates the 2026-09-23 ghost. Filed on the ghost-hardening item (§7). |

## 6. Tests

- `WalletDeletionRejoinTests` (seam `otherDeviceReportProvider`, plus the
  new loading closure): `refreshInProgress` is thrown before Step 1 and
  the summary is never produced; the scope-invalidated abort still wins
  when both conditions hold (order documented, not important); a full-wipe
  retry with a nil hash and an empty registry reaches
  `.promptForCloudData`; `refreshInProgress` and `noModelContext` are
  distinct cases (no string matching in the view).
- `isLoadingWalletData` truth table: not tested — constructing
  `WalletManager` builds the FFI wallet; the property is two reads and was
  reviewed (and its ownership checked by the adversarial pass).
- `StaleWalletDirectoryTests` (added after review finding 1b): a marked
  directory is not local wallet evidence; the breadcrumb still counts; the
  marker roundtrips.
- No test on the `deleteCloudKitData` reorder; it needs a failing context
  injected. Reviewed by hand; the rollback is one line.

## 7. Residuals filed (not fixed here)

- Launch device registration racing `unregisterCurrentDevice` → added to
  the Tier 0 ghost-hardening residual item (refuse while
  `isDeletionInProgress`, or re-clear the mirror after the cleanup).
- Relay bookkeeping written after `clearUserDefaults` by the launch's
  push registration → Tier 4 note under rule 27.
- Notification listener and progression timers writing inside the wipe
  window → recorded as a residual in rule 17.
- `updateProgress` messages are unlocalized English in two views → Tier 3
  strings item. The new row in §4.1.2 uses `defaultValue:`.
- A crash between the KVS hash deletion and the keychain deletion leaves
  seed-without-hash; both orders have a crash residual, both recover
  through a second deletion.

## 8. Rulings (Christoph, 2026-10-15)

- **Gate, not pause** — DECIDED. The delete screen waits visibly while
  wallet data is loading; nothing pauses inside the wipe (§2, §4.1).
- **Route anyway on a late failure** — DECIDED. After the cleanup service
  has returned, a failure to remove the bark directory logs at error level
  and still navigates to onboarding or rejoin. The alternative (stay with
  an error and a retry of only the manager phase) was rejected: the stale
  directory is replaced by the next create or import, and staying would
  show a wallet UI with no wallet behind it.

## 10. Review record (2026-10-15, `fault-class-reviewer`, same session)

Handed the working-tree diff and the area name. Findings and what was done:

1. **CONFIRMED, class 5 → 2** — the route-anyway ruling rested on "the
   stale directory is replaced by the next create or import"; true for
   create (`BarkWalletFFI+WalletCreation.swift:99-102`), false for import
   (`:494-507` opens with `createIfNotExists: false`; bark bails with
   "incorrect mnemonic" on a fingerprint mismatch; only the network
   mismatch is caught). A full wipe whose teardown failed would make every
   import of a different phrase fail until a create or reinstall. **Fixed
   in-session**: stale-directory marker, consumed by all three wallet-arrival
   paths (§4.2 last row); inventory entry; ledger line.
   1b. **PLAUSIBLE, class 2** — `clearLocalWalletEvidence()` clears the
   breadcrumb only; `hasLocalWalletEvidence()` falls through to the
   directory check, so the keychain-unreadable detection branch would route
   a wiped install to `.walletWithSeed`. **Fixed**: a marked directory is not
   evidence.
2. **CONFIRMED, class 3, cosmetic** — the view set `isDeletionInProgress`
   before the service's `assessDeletion()` await, and a mailbox-push
   `refresh()` arriving in that window flipped `isRefreshing` before it
   reached the skip inside `performRefresh`, so the service's re-check could
   abort with "a refresh started" for a refresh that never ran, and the
   button row flickered. **Fixed**: the skip moved to the top of
   `refresh()`, before the counter.
3. **PLAUSIBLE, class 1/3** — `rollback()` runs on the container's shared
   main context and discards every unsaved change, not only the queued
   deletes; one autosave-reliant writer found (`BackupStatus.getSingleton`).
   **Fixed**: the service saves pending changes before it starts deleting,
   so a rollback can only undo its own work.
4. **PLAUSIBLE, class 5** — "every pre-seed failure leaves a working wallet"
   overstated for the keychain step (local network config gone, rows
   re-created by the next refresh). **Claim corrected** in §4.2 and rule 17;
   no code change.

Sound per the reviewer: `isInitializing` ownership under joined callers,
the unconditional `defer`, route-anyway not recreating the 2026-10-14 shape
(manager state is reset before the file step), the FFI handle being nil in
both scopes before the backup suspension lifts, rollback leaving nothing
half-committed, `DeletionStep` monotonic along the new order. Scoped tests
8/8 on the simulator. Not verified by the reviewer: any device run; whether
`wallet.deleteWallet()` can fail at all on device; `autosaveEnabled` on the
main context; the two-device local-only route-anyway → rejoin path; the
fingerprint check at the deployed bark tag (read at a checkout 130 commits
past it); SwiftUI `@State` reset of the slider sheet on re-presentation.

## 9. Device check (owed after Review)

One phone, full wipe, cold launch on mainnet with history. Open Settings →
Delete wallet within ~10 s of launch: the screen shows "Finishing the
current refresh…" instead of Continue, then Continue appears after
`DataVersion incremented`. Delete. Expected log: no `saved N new` and no
`Step 3.1` after the first `[WalletDataCleanupService] Progress:` line.
Then create a new wallet: Activity empty, Step 2b `saved 0 new`. Second
run: open the delete screen, trigger a mailbox push (pay the wallet from the
other phone) while the slider sheet is up, slide — expected either the
`refreshInProgress` abort text or, if the push lands after the slide, the
`Skipped — wallet deletion in progress` line. The failure paths cannot be
provoked on device; tests and the hand trace cover them.
