# Rework Ledger

One line per time generated code had to be revisited: when, what, which of
the five fault classes it belongs to (`Change_Review_Playbook.md`), how it
was found, and which contract rule or test it produced. Reviewed every third
release train (`Release_Train.md`). The point is not blame; it is to see
which class dominates so the next contract rule or test goes where the
faults actually are, and to check whether the day-7 review is catching them
before the device day and the field do.

Classes: **1 Scope** · **2 Path asymmetry** · **3 Ownership** ·
**4 Boundary assumption** · **5 Trusted claim**.
Found by: **review** (a review pass) · **device** (on-device verify) ·
**field** (TestFlight / real use) · **audit** (claims audit) · **tests**.

## Seed entries (reconstructed 2026-10-07 from the Done log)

| Date | Change revisited | Class | Found by | Produced |
|------|------------------|-------|----------|----------|
| 2026-08-10 | `initWallet()` + `open` shipped for months; seed-recovery scan never ran on import | 4 | audit (bark source) | Launch rule 1; single-step `Wallet.open` |
| 2026-08-13 | Fresh-import Live Activity respawned "Move complete" — bark replays finished exits ~2 s | 4 | device | B3; `recreateMissingActivities` after first check |
| 2026-08-13 | Balance overcount after import — parallel read captured bark's mid-walk state | 2 | device | `refreshOnchainBalance()` after history stabilises |
| 2026-08-19 | 2026-08-12 deletion-strategy fix defeated: FFI `deleteWallet` still deleted the synchronizable seed on every deletion | 1 | review | Launch rule 19; S1 |
| 2026-08-19 | `PendingPaymentMetadata` / `PendingTagAssignment` missing from the full wipe | 1 | tests (`WalletWipeCoverage`) | wipe-coverage inventory |
| 2026-08-20 | Local-only delete cleared the shared KVS network config; secondary stranded on mainnet | 1 | device (two-device) | Launch rule 21; `clearLocal()` / `clearEverywhere()` |
| 2026-09-21 | `refreshAfterVTXOChange` refetched the Ark-only service while every reader used the stored merge — new guard inert | 2 | review (pass 3) | P1; `mergeTransactions()` |
| 2026-09-21 | Post-write refetch joined a fetch that predated the write | 2 | review | P2; `executeFresh` |
| 2026-09-21 | Refresh doc claims "three writers", "we pin 144", "status mapping verified" all false | 5 | audit | claims-audit method; feedback §2.7 |
| 2026-09-21 | `TaskDeduplicationManager.cancel`/`cancelAll` never worked (invariant generics) | 3 | review | O4; Tier 4 item |
| 2026-09-21 | Full wipe offered to a non-last device under CloudKit lag | 1 | audit (Multi_Device_Design) | KVS mirror consulted first; `KVSDeviceRegistryTests` |
| 2026-09-23 | Local-only delete destroyed every tag/contact assignment account-wide (`deleteWallet()` after the strategy-aware service) | 1 | device (two-device) | Launch rule 23; `TransactionDeletionBlastRadiusTests`; S1 |
| 2026-09-23 | Wallet ran a whole session on the wrong network — `hasSavedConfig()` guard disarmed by the very sync that fetched the value | 2 | device | Launch rule 22; `reconcileNetworkConfigBeforeWalletOpen` |
| 2026-09-23 | Secondary seeded its own default tags/contacts (18 tags, 3 contacts) — role-based guard | 5 | device (two-device) | first fix |
| 2026-09-23 | Activity list crashed on launch reading a cached relationship array during CloudKit import | 2 | field (crash) | P3; `TransactionMetadataResolutionTests` |
| 2026-09-24 | `execute` removed `executeFresh`'s key → concurrent duplicate | 3 | review | O1; `executeJoinsFreshTaskAfterDrain` |
| 2026-09-24 | Override offered on a healthy two-device account (`.localOnly` ⇒ override) | 5 | device (two-device) | `shouldOfferOverride`; `OverrideAvailabilityTests` |
| 2026-09-24 | `unregisterCurrentDevice` mirror cleanup inside `if let` with no else → permanent ghosts | 2 | review | P4 (partial); Tier 0 item (1) |
| 2026-09-24 | `CloudKitObserver` dropped remote changes in the 1.5–2.0 s band instead of deferring | 3 | review | O2; `RemoteChangeThrottleTests` |
| 2026-09-24 | Background launch killed holding a store lock (`.test` probe on every `BarkWalletFFI.init`) | 3 | field (Organizer) | probe removed; task assertions |
| 2026-09-25 | Seeding guard was a half-fix: hazard is store-not-imported, not device role; reinstalled primary still duplicated | 5 | review | Launch rule 26; S3; `DefaultDataSeedingDecisionTests` |
| 2026-09-25 | Invalidation fix covered reads, not writes | 2 | review | P3 extended; `TransactionMetadataWritePathTests` |
| 2026-09-25 | The write-path fix made refresh a fetch storm (O(transactions × contact usage)) | 2 | review | `TransactionMetadataSnapshot` bulk bridge |
| 2026-09-27 | Refresh reminder fired ~4× early on signet — 150 s/block assumed for non-mainnet | 4 | field (log) | B4; `BlockTimeFormatter.secondsPerBlock` |
| 2026-09-27 | Hourly auto-refresh silently skipped after 60 s — read an expired cache value | 2 | review | async `getEstimatedBlockHeight()` |
| 2026-09-27 | `matchedTxid` documented "for debugging" but load-bearing | 5 | audit | Tier 3 item |
| 2026-09-27 | Desktop build broken: Xcode dropped the Shared exception set during the Docs move | 4 (tooling) | tests (build) | `#if canImport(ActivityKit)` island |
| 2026-10-01 | Pre-open refresh → sticky `walletNotInitialized` banner | 3 | field (log) | Launch rule 7b; O3 |
| 2026-10-07 | Backlog audit: first keyword sweep used `\|` in rg (literal pipe) → false "not implemented" verdicts for native contacts, identicons, fee picker | 5 | review (self) | memory rule: `a|b` alternation |

## Running entries

Add below as they happen, newest last. One line each; link the backlog item
or Done-log entry if the write-up is long.

| Date | Change revisited | Class | Found by | Produced |
|------|------------------|-------|----------|----------|
| 2026-10-07 | `0de06d4` hardened the recovery-phrase Copy button (`.localOnly` + expiry) but the QR sheet next to it still exposes the phrase as selectable text → plain pasteboard copy | 2 | review (first `fault-class-reviewer` run) | backlog item under the clipboard entry; Train 1 Tier 0 pick |
| 2026-10-07 | `Documentation_Inventory.md` rated `Setup.md`, `Common_Tasks.md`, `Testing_Patterns.md` "valuable, current, keep as-is"; all three still described the bark-CLI macOS app with a non-existent test module — the September doc cleanup trusted the rating | 5 | review (self, while writing CLAUDE.md) | archived to `Archive/Development/`; Setup + Testing_Patterns rewritten from source |
| 2026-10-11 | 2026-09-21 `isAlreadyIssuedRejection` mapped every `unusable_inputs` to "already issued into a round"; at `server-0.7.1` the tag fires for any unspendable input (spent, exited, banned), so a wallet that missed a round retried its three dead VTXOs on every launch and tap (mainnet field log 10-09) | 4 | field (log) | `Refresh_Deduplication.md` §9: classify against pending-round inputs after the refetch + 24 h per-id back-off; FFI line logs the server text |
| 2026-10-11 | Same-session `BalanceRefreshCardState.resolve` put "too small" ahead of "refused", so any dust sibling (which bark lists alongside must-refresh VTXOs) masked 19,995 refused sats as "Too small to refresh"; the modal's refused auto-switch ignored an in-flight refresh and could contradict the card | 2 | review (`fault-class-reviewer`, same session) | precedence fixed, modal decides via the shared resolver, test `dustSiblingDoesNotMaskRefused`; `Refresh_Deduplication.md` §10 review notes |
| 2026-10-12 | `processSingleMovement` reused `upsertTransactionsFromServerData` for one notification movement; the orphan check inside it assumed the complete list and reported every other tagged row as "no longer exists on server" (231 lines in the 2026-10-09 mainnet log) — the Tier 0 backlog entry then chased orphan rows that did not exist | 2 | review (log read against the code) | `isCompleteMovementList:` flag, notification path skips the check; one summary warning per full refresh |
| 2026-10-12 | Same-session connection-icon fix justified leaving the disconnected verdict at Step 4 with "Step 2 can still succeed after a failed Step 1"; bark 0.7.1 `sync()` cannot fail at all, so Step 4 has never written disconnected and the comment codified a false model | 5 | review (`fault-class-reviewer`, same session) | comment corrected; Tier 1 Connectivity item "can never show disconnected" filed ahead of the offline feature |
| 2026-10-13 | Same-session balance-card load indicator wrote the sweep band's start (0) and animated end (1) in one main-actor turn, so SwiftUI would only ever render the band at 1, off the trailing edge — the amount dimmed, nothing swept; the redefined `isRefreshingWithData` was justified with "the persisted balance from the first render" although `updateTotalBalance()` synthesises zero models, so `totalBalance != nil` holds from `setModelContext` on and the `hasLoadedOnce` half was dead | 4, 5 | review (`fault-class-reviewer`, same session) | a committed frame at 0 before the animated write; flag simplified to `isRefreshing && totalBalance != nil` with an honest comment |
| 2026-10-13 | Same-session balance-card load wave drew a quick wave running backwards at settle: the loop's 1 → 0 progress reset landed in the same update as the quiet-state change, and the amount's `.animation(value: isQuiet)` interpolated every animatable change in that update, the renderer's progress included | 4 | field (device look, same day) | reset runs in a `SwiftUI.Transaction` with `disablesAnimations`; comment names the hazard |
| 2026-10-13 | Same-session deletion forfeit warning derived its copy from `DeletionStrategy` alone, so the "Delete from the account anyway…" path (which wipes the seed account-wide) and the unreadable-registry case told the user to "open the wallet on another device"; and it awaited the network block-height fetch before publishing the amount, so on a slow network the delete button appeared with no warning — the field condition the item exists for; the read-only fallback also counted `spendableSat` while the VTXO path counted Spendable + Locked | 1, 2 | review (`fault-class-reviewer`, same session) | `overrideOffered` picks the last-device copy; amount published after the local VTXO read with the cached height, fresh height only refines; fallback is `totalSat - pendingExitSat`; tests `overrideOfferedUsesLastDeviceCopy`, `readOnlyFallback` |
| 2026-10-14 | Same-session Ark-first refresh read Step 2b's movements with the joining `refreshTransactions()` right after Step 2a had written, so on a pull-to-refresh with a notification-path read in flight the "early publish" could be the pre-sync list; it also left the unified stored merge to Step 3.1, widening the rows-vs-merge window by the whole onchain sync; and its bark cite named the HEAD line of a checkout 130 commits past the tag | 3 | review (`fault-class-reviewer`, same session) | `refreshTransactionsAfterWrite()` + `mergeTransactions()` in Step 2b; cites name tag `bark-0.7.1` `lib.rs:1980`; `Launch_Ark_First_Refresh.md` §9 review record |
| 2026-10-14 | Same-session full-wipe backup skip gated only the FFI shutdown's own backup; the app's `.background` hook calls the same `backupWallet()` with just a nil-handle guard, and on a full wipe the handle stays live from `deleteAllBackups()` through CloudKit deletes, keychain delete, push unregister, daemon stop and the final sync — two network calls, which the plan had sized as "a few seconds" and filed as a Tier 4 residual | 3 | review (`fault-class-reviewer`, same session) | opportunistic backups suspended for the whole deletion (`opportunisticBackupsSuspended`, set by the delete view, cleared in a `defer`); shutdown's final backup bypasses it via `runBackupNow()`; `Wallet_Deletion_Backup_Skip.md` §10 |
| 2026-10-14 | `31e2f10` (Ark-first refresh, 10-13) added a merge in Step 2b that runs before Step 3's onchain fetch; after a delete → create in one process the never-reset `OnchainTransactionService.onchainTransactions` still held the deleted wallet's list, so the new wallet's first refresh re-created the old onchain row as a `PersistentTransaction` (20,000-sat "Received" in a 0-balance mainnet wallet). The fault was latent before: the only merge ran after the fetch. Deletion also never waited for the in-flight refresh, which re-created the same row 1 s after wipe 1's delete | 3 | field (Christoph's 21:24 export + screenshots, same day as the deletion device check) | `resetManagerState()` resets the onchain service (list + cache) and the merged list; the refresh-vs-deletion race stays with the Tier 0 partial-failure item |
| 2026-10-15 | The delete screen's `checkDevices()` cleared `deleteError` on every run, and the slider sheet's `onDismiss` re-runs it — so the scope-invalidated abort (which sets the error and dismisses the sheet in one transaction) had its message erased before the user could read it. Latent since the abort landed (2026-09-25); the same-session phrase-confirmation screen added a second trigger (the info screen's `.task` restarts on pop) and its plan claimed "pops to the info screen with the error" without tracing the dismissal path | 2, 5 | review (`fault-class-reviewer`, same session) | `checkDevices()` no longer touches `deleteError`; it is cleared in `startDeletion(override:)` when the user begins a new attempt; `Wallet_Deletion_Phrase_Confirmation.md` §11 |
