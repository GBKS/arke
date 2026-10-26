# Impact Analysis: the review angles and the backlog match

Companion to [02-migration-plan.md](02-migration-plan.md). Written before
any code, 2026-10-25, so the plan could be checked from several sides
before it is built. Each angle ends with what it changes in the plan.
Labels: **verified** (read at the tag or in the file), **derived**,
**assumed**.

## 1. Money and balance

**What changes.** The Ark total has three new components, one of which
(`needsRefresh`) used to be inside `spendable` (verified, §3.1 of
01-api-changes). `pendingInRound` changes meaning (locked inputs, not
requested outputs); for a delegated refresh awaiting its round it is now
zero until the server issues the round, which matches what
`pendingRoundInputVtxos()` already reported (verified from the changelog
text, derived for the delegated case).

**Where it can go wrong.**

- Two parallel total computations (`ArkBalanceResponse`, `ArkBalanceModel`)
  and twelve explicit constructors (five of them in
  `ReadOnlySyncedDataTests`). The compiler catches the constructors; it
  does not catch a total that forgets a field — and one was already
  forgotten: `claimableLightningReceiveSats` has been in bark's `Balance`
  since 0.7.1 and the app never mapped it, so "matching bark's total"
  needs four fields, not three (review finding 3). → Plan: both totals
  change in the same edit with four fields, `ArkBalanceTotalsTests`
  compares response and model for the same input; the model's init gets
  defaulted parameters so the test constructors compile.
- `BalanceDetailCard` shows spendable, pending and total as three figures
  plus the breakdown rows. Adding needs-refresh to the total but not to
  the figure the rows sum to makes the card's arithmetic visibly wrong
  (review finding 7). → Plan: Phase 2 item 5 shows needs-refresh inside
  the held figure for this release (PROPOSED default), the card's own
  needs-refresh line stays with the Tier 0 item.
- `DeleteWalletSettingView.syncedForfeitSummary` derives "Spendable +
  Locked" from `totalSat - pendingExitSat` on secondaries and will count
  the leaving buckets after the change. Over-warning; accepted. → Plan:
  Phase 2 item 7.
- The read-only secondary device loads `ArkBalanceModel` from CloudKit
  (`ReadOnlyBalanceService.swift:127`). A build-25 secondary reading a
  build-26 record ignores the new fields and shows a total that is smaller
  by `needsRefresh` than the primary's. Accepted: it is the state build 25
  shows anyway, and both devices update together in practice. → Plan:
  noted, no code.
- `WalletManager+Export.swift:54` writes the balance into the debug export.
  If it keeps five fields, the export lies about the total by exactly the
  number that matters for the two users. → Plan: Phase 2 item 3 includes
  the export.
- Send caps and the destination selector read `spendableSat`. After the
  bump that is bark's "what can be sent now", which is the right cap. The
  Tier 0 cluster's complaint that "the balance counts expired VTXOs as
  spendable" is thereby fixed at the data layer. → Plan: no code; chore 3
  notes it on the cluster.

**Verdict.** Phase 2 belongs in the release. Nothing here is design; it is
plumbing with a sibling-sweep hazard.

## 2. Exits and the persisted cache

**What changes.** One new terminal state. `getExitVtxos()` stays "live
only" (verified); `getExitStatus` was always live-or-finished (verified at
both tags, correcting the review); finished exits are now enumerable via
`listFinishedExits` (new); a claim reports which ids it contains (new).

**Where it can go wrong.**

- Track A maps `vtxoSwept` to `vtxoAlreadySpent`. Any swept exit that
  happens while build 26 is current is persisted into `PersistentExitCache`
  as already-spent and stays so after Track B. Probability: an exit must
  be started and then have an input swept on chain mid-exit; the backlog
  has no such case and the state is new. Cost of being wrong: a wrong
  label in the completed-exits list, funds unaffected. → Plan: accepted,
  pinned by a test so the Track B change is deliberate.
- `isCancelled` must include the new case or `isInFlight` keeps the exit
  alive in `ExitProgressionService` polling and the Live Activity
  (`ExitProgressionService+LiveActivity.swift:238` tests `parsed` for
  already-spent, which the lossy mapping satisfies; the `ExitVtxo` helper
  at `ExitVtxo+Extensions.swift:84` tests the Bark enum directly and does
  not). → Plan: Phase 1a item 3, and a question for the adversarial pass.
- `ExitTransactionStatus.transactions` is new and the cache reconstructs
  statuses with `[]`. Nothing reads it today (grep for `.transactions` on
  a status: none; the app reads `transactionCount` and `history`). → Plan:
  `[]`, with the adversarial pass asked to confirm no reader.
- `drainExits` callers: still one production chain
  (`ExitClaimSequence.run`), still `drainAll: false`, still linking the
  requested ids. Same blind spot as after 0.25, now closable. → Plan:
  Track B item 2; not in the release because the claim path is money and
  needs its own tests and device claim.

**Verdict.** Track A touches exits only where the compiler forces it, plus
the one helper that would otherwise regress. Correct for a recovery
release.

## 3. Recovery and the users' procedure

**What changes.** The whole recovery reader (verified, §3.5 of
01-api-changes). Server-side, the xpub endpoint and the mailbox paging fix
exist in `server-0.8.0` (verified); deployment is assumed.

**Where it can go wrong.**

- **The restore trap** (README fact 2), corrected by the review pass: the
  seed import never restores the backup; the restore runs from
  `restoreWalletIfNeeded` during initialization, which is what the
  "Rejoin This Wallet" button after a local-only delete triggers — no
  local file, backup present, restore, non-creating open, no recovery
  scan. The full wipe is offered only when no other device is registered,
  and a second device that still runs Arké re-registers itself on launch,
  so the Devices-screen unlink does not clear the way (its own dialog says
  the device "will reappear here on its own"). → Plan: the procedure has
  the other device delete first and names "Rejoin This Wallet" as the
  button never to tap; no UI (DECIDED). A future "import ignoring the
  backup" option is filed as a Tier 3 question.
- **Tombstone and rejoin.** Full wipe on the last device writes the wallet
  tombstone; importing the same seed afterwards is the rejoin path
  (`Wallet_Deletion_And_Rejoin.md`). Device-checked in August and again in
  the deletion cluster; the import side with the new reader is scenario 2.
  One more guard the review traced: `BarkWalletFFI.importWallet` opens
  without recovery whenever a local `db.sqlite` still exists, which after a
  failed teardown is covered only by `recordStaleWalletDirectory()` +
  `removeStaleWalletDirectoryIfMarked()`. → Plan: scenario 2 is a release
  gate.
- **Second device.** Covered by the procedure's step 3 (delete there
  first). A device that merely stays online as a secondary keeps the wallet
  registered and blocks the complete removal on the main phone; the
  procedure's step 4 tells the user how to recognise that from the delete
  screen's own text.
- **The xpub error path** (README fact 6): any non-`Unimplemented` error
  from `recover_vtxos_by_xpub` makes the whole recovery report an error,
  which the app turns into wipe-and-reopen retries and "Recovery scan
  never completed". → Plan: scenario 2's stop condition, chore 4b to
  Second.
- **The server is still 0.7.1.** Recovery falls back to the mailbox reader
  with the client-side paging fixes; the server-side checkpoint bug
  `dfd425d4a` would then still skip rows, and recovery could miss the
  settling message again. → Plan: scenario 2's log tells which path ran;
  if the fallback line appears, ask Second before sending the procedure.
- **Recovery marks the users' three VTXOs spent and finds the refreshed
  outputs.** Derived from `recover_from_seed` reading plus Second's
  statement that the refresh succeeded server-side; not reproducible on
  our side. → Plan: scenario 3 if Christoph's own wallet is in that state;
  otherwise the users are the test, with a log export requested.

**Verdict.** The procedure is the riskiest artefact of the release and the
one no test covers. It is written, it is short, and scenario 2 rehearses
it on signet.

## 3b. What the user ends up with (second review pass, 2026-10-25)

A fresh-context trace of wipe → import → first sync, per kind of state.
Deciding symbols in `02-migration-plan.md` and the pass's report; this
table is the summary.

| State | After the procedure | Procedure / checklist |
|---|---|---|
| Payments (Ark) balance | Recovered by `recover_from_seed`; history rows rebuilt from server movements, numbering restarts | scenario 2 |
| Savings (onchain) balance | Only address index 0 visible until `initialScan` runs; the app never runs it today | **Phase 4**, scenario 2 |
| Contacts, tag names, profile | Deleted by the wipe; restored by the metadata export/import | procedure steps 3 and 8 |
| Notes and tags on payments | Deleted; cannot be restored (key is `movement_<id>`); an old file imported late misfiles them | procedure text; Tier 1 Data safety entry |
| Exit in progress | State lost with the database; bark re-creates an exit only for already-confirmed exit txs; no warning on the delete screen | procedure step 0; Tier 3 line |
| Open Lightning invoice | Preimage lives only in the deleted database; a paid-in HTLC cannot be claimed, times out to the payer | procedure step 0 |
| Pending board | Not recoverable by the app | procedure step 0 |
| Relay / push registration | Unregistered on delete; exactly one new 30-day registration on the first launch after import (rule 27) | scenario 2 wording |
| Live Activities, local notifications | Cleared on delete; re-armed by `LaunchSequence` after import | — |
| Device registration, primary role | All rows deleted; the importing device registers itself primary. Residual: a stale `wasDemoted` flag could block it read-only on the next launch | scenario 2 relaunch check |
| Network config | Cleared everywhere; chosen again on the first-use screen and saved by the import | procedure step 6 names mainnet |
| Second device | Local-only delete first, "Rejoin This Wallet" later → read-only companion on the new rows; writes no backup of its own in read-only mode | procedure steps 4 and 9, scenario 6 |
| iCloud database backup | Deleted by the full wipe; the import writes a fresh one; the launch-time newest-wins compare cannot pick an older file. Residual: iCloud Drive off for the app leaves the old backup in place, and a later reinstall would restore it | procedure step 0 |
| Cosmetic settings (theme, fiat currency) | Survive | — |

## 4. Startup, daemon, rounds

**What changes.** Nothing in `Wallet.open`, `WalletOpenArgs` or `Config`
(verified). The daemon still starts in `open` (B6, to re-grep during the
build). Round registration no longer locks inputs (#2443, derived).

**Where it can go wrong.**

- `Refresh_Deduplication.md` Guard C reasons from "a pending participation
  locks its inputs". If locks now appear only at attempt start, the
  "being refreshed" signal from `pendingRoundInputVtxos()` is empty for
  longer, and the app's own in-flight set (the pending refresh movement)
  carries more of the load. Nothing breaks; the dedup may admit a second
  submission the server then rejects or merges. → Plan: Track B item 9;
  scenario 1 provides the evidence.
- Christoph's stuck refresh. If #2443 settles it on the first sync, that
  is the first field confirmation of the new behaviour and belongs in the
  Done log of the Tier 1 refresh items. If it does not, the wallet is a
  diverged-wallet rehearsal. Either outcome is useful; neither gates the
  release. → Plan: scenario 1 first.
- Launch ordering (`Launch_Sequence_Contract.md`) is untouched by Track A.
  `walletExists` would touch rule 3 and is Track B.

**Verdict.** No startup risk in Track A.

## 5. Logging and support

**What changes.** Bark's own lines would go private (verified,
`01db51c`). The app's lines follow the project rule (network name public,
ids private).

**Where it can go wrong.**

- Shipping without Phase 3 and then asking the users for a log export:
  every bark line is `<private>`. The recovery lines ("Recovered N
  spendable vtxos", "Recovery incomplete", the xpub fallback) are bark
  lines. → Plan: Phase 3 is a release item, DECIDED.
- Privacy trade-off: bark lines carry VTXO ids and amounts; they did so
  before this bump as well, and the export is user-initiated. → Plan:
  recorded in the code comment; revisit when the export no longer reads
  the unified log.
- `debugInfo()` (network, mailbox id, VTXO xpub) is what Second asks for
  in a support thread. → Plan: Track B item 8; the mailbox id is already
  in X-Ray.

## 6. Tests: decisions versus restatements

- `ExitStateMappingTests` swept→already-spent: a decision test (it exists
  to be deleted on purpose).
- `ArkBalanceTotalsTests`: decision tests (what the total means; response
  and model agree). Not kept: a test that `needsRefreshSat` is mapped from
  `needsRefreshSats` — that restates the implementation.
- No test for the logger flag (one call site, verified on device).
- `ExitClaimSequenceTests`: unchanged in Track A; Track B adds the
  `vtxoIds` link cases.
- Full suite once, after the review, per the lean workflow.

## 7. Backlog match — what this bump does to open entries

| Entry (section) | Effect of this bump | Who acts |
|---|---|---|
| Tier 4 Bindings adoption — **Next bump: post-incident client fixes, front of Train 2** | This is it; all named commits are in `bark-0.8.0`. Closes when Track A ships; Done-log entry links the procedure. | chore 3 |
| Current train — Train 2 pre-emption line | Becomes cluster 0 (Track A) with the three scenarios on the device checklist. | chore 3 |
| Tier 0 — **Wallet state diverged** cluster, balance sub-item | Data half delivered (`needsRefreshSat` kept out of spendable, shown in the breakdown). Card state remains open. | chore 3 note |
| Tier 0 — **Failed boards leave onchain coins stranded** (`f85ca92ac`) | Fix is in the binary; entry becomes a Tier 2 verification (board refused after signing leaves the onchain wallet untouched). | chore 3 |
| Tier 1 Exits — **Replace the hand-rolled estimate with `estimateEmergencyExitFee`** (DECIDED) | Premises changed: no `fundable`, no confirmed-coin walk, no onchain sync, new `feeMargin`. Rewrite before build. | Track B item 4 |
| Tier 1 Activity — **Rows dated by processing time** | Not fixed. Related upstream change: finished exits no longer bump `completed_at` (#2610), which removes one cause of old cancelled exits floating up; the date-freeze workaround in the upsert can go once observed. | Track B note on the entry |
| Tier 3 Exits — **Adopt `cancelExit`** | Open question answered: cancelled rows stay on disk and are listed by `listFinishedExits`. | chore 3 note |
| Tier 4 — **0.25 `ExitClaimTransaction` included-ids gap** | Answered upstream. Closes into Track B item 2. | chore 3 |
| Tier 4 Startup — **Explicit daemon start is redundant** (B6) | Re-verified during this build. | chore 5 |
| Tier 4 Concurrency — **Refresh dedup deferred notes** | Premises touched by #2443. | Track B item 9 |
| Tier 4 Tooling — **Mark network-name log interpolations public** | Same topic as Phase 3, opposite direction; unaffected. | — |
| Train 2 ops item 6 — pin `bark-ffi-bindings` | Do it for this release. | Christoph |
| Feedback doc asks 3, 6, 8, 11, 12, 17, 19 | Shipped or partly shipped at this tag. | chore 2 |
| Tier 0 — **Backup restore is newest-wins** | Unchanged by the bump; it is the mechanism behind the restore trap and the reason the procedure says "full wipe". | procedure |
| Tier 1 Send — items using `spendableSat` as the cap | Correct by construction after the bump. | — |

Entries this bump must **not** touch: the deletion cluster residuals, the
phrase-exposure items, the send-path cluster, the BIP-353 items, the
`checkReadOnlyMode` fix. None of their files are on Track A's list.

## 8. What was not verified

- Any execution: no test run, no device run, no recovery performed.
- Server deployment version (assumed from Christoph's statement).
- That #2443 settles a stuck awaiting participation (derived from the
  changelog; scenario 1 is the observation).
- That `recover_from_seed` on the users' wallets records the three
  pre-refresh VTXOs as spent and recovers the refreshed outputs (derived
  from source reading plus Second's statement).
- Playbook facts B3, B4, B5 at 0.8.0 (B4 and B5 are app-side rules and
  do not depend on the tag; B3 is a timing observation).
- Whether any Swift Testing suite constructs `Balance` directly (grep
  found none; the compiler will say).
- Internals of `sync_pending_rounds` at 0.8.0 — whether it can settle a
  stored participation whose inputs the server already spent (bears on
  scenario 1, not on the users' case).
- What Second's deployed server returns for `recover_vtxos_by_xpub`
  (chore 4b).
- Whether `.canceled` is reachable in this app today (no `cancelExit`
  adoption); the `isCancelled` fix is static either way.
- CloudKit behaviour for a build-25 secondary reading a record with four
  unknown fields (expected: ignored).
- BDK's sync over unrevealed indices (taken from the binding doc and
  `bdk.rs`, not BDK source); "index 0 only" is reasoning.
- Whether the iCloud Drive copy preserves the backup file's modification
  date, which the launch-time newest-wins compare relies on.
- The second device's window of stale rows between its rejoin and the
  CloudKit import of the deletions.
- bark's handling of a VTXO recovered while its exit txs were broadcast
  but unconfirmed.
