# Migration Plan: Bark FFI v0.25.0 → v0.26.0

Companion to [01-api-changes.md](01-api-changes.md). **Track A** below is
the release (DECIDED 2026-10-25); **Track B** is a PROPOSED Train 2 cluster
and is only listed here so nothing is lost. The definition of done for
Track A is a TestFlight build the two stuck users can recover on, plus the
written procedure they follow.

Every claim in the phases is **verified** by reading the files named
unless marked otherwise.

## Phase 0 — Package sanity (mostly done)

`Package.resolved` points at `bark-ffi-bindings` revision `ada76c3`
(branch `master`), uncommitted; the binary target resolves from the tag's
release asset (checksum in the package's `Package.swift`). Two things to
do by hand:

1. **Christoph, Xcode UI:** pin `bark-ffi-bindings` to the tag or revision
   instead of `master` (already the ops item 6 of the Train 2 picks). A
   `master` pin can silently move the binary under a release whose purpose
   is this exact binary.
2. **Stale module cache.** The first build after the bump fails on
   `barkFFI.h has been modified since the module file … was built`. Clean
   Build Folder, or delete `barkFFI-*.pcm` under the DerivedData
   `SwiftExplicitPrecompiledModules` directory (done once already on
   2026-10-25 for the `Arke-gknak…` DerivedData).

## Phase 1 — Compile fixes (Track A)

Mechanical. Build once at the end of the phase.

### 1a. `vtxoSwept` folded into today's cancelled handling

1. `Shared/Data/ExitStatus/ParsedExitState+Bark.swift:27` forward mapper:
   add `case .vtxoSwept(let tipHeight, _): self = .vtxoAlreadySpent(.init(tipHeight: tipHeight))`
   with a comment naming this as the Track A lossy mapping and pointing at
   the Track B entry. `spentInputs` is dropped.
2. `Shared/Views/Activity/ExitVtxo+Extensions.swift:20` `stateDisplayName`:
   `.vtxoAlreadySpent, .vtxoSwept, .canceled` → `L10n.transactionCancelled`.
3. `Shared/Views/Activity/ExitVtxo+Extensions.swift` `ExitVtxo.isCancelled`:
   true for `.vtxoSwept` **and `.canceled`** — the helper matches only
   `.vtxoAlreadySpent` today, while every `ParsedExitState` site treats
   `.canceled` as terminal (review finding 6, a pre-existing asymmetry;
   `.canceled` is not produced by this app yet, so the fix is static).
   Readers of `isInFlight` that this corrects: `WalletManager+Exits`
   (`activeExits`, stale-blocked pruning in `performRefresh`),
   `ExitProgressionService+LiveActivity` (`rescheduleCheckInRemindersIfNeeded`,
   `recreateMissingActivities`), `ExitView_iOS.inFlightExits`,
   `UnilateralExitListView_iOS`. Not touched: `ExitVtxo.isActive`
   (`!isClaimed`), whose one reader `NotificationsSettingView_iOS` re-arms
   exit check-in reminders for cancelled exits — pre-existing, filed as a
   Tier 3 line in chore 3.
4. No `ParsedExitState` case, no string, no icon in Track A.

### 1b. Record constructors

| Site | Fill |
|---|---|
| `BarkWalletFFI+Exit.swift:352` (preview `drainExits`) | `vtxoIds: vtxoIds, skippedVtxoIds: []` |
| `MockBarkWallet.swift:527` `drainExits` | `vtxoIds: vtxoIds, skippedVtxoIds: []` — the mock does not model unclaimable ids; say so in a comment |
| `Tests/Shared/ExitProgressTests.swift:496` `RecordingClaimWallet.drainExits` | `vtxoIds: vtxoIds, skippedVtxoIds: []`; no new assertion (Track B tests the link) |
| `BarkWalletFFI+Lightning.swift:24/280/325/375` (preview `LightningSend`s) | `paymentHash: "preview_payment_hash"`-style placeholder, `movementId: nil`; insert after `invoice:` to follow the memberwise order |
| `MockBarkWallet.swift:325/643/660/677` | same, a 64-hex placeholder hash and `movementId: nil` |
| `Shared/Models/PersistentExitCache.swift:95` reconstructed status | `transactions: []` — the snapshot never stored packages; the app reads `transactionCount` |
| `Tests/Shared/ExitProgressTests.swift:50`, `ExitStateMappingTests.swift:136`, `ExitBlockedInfoTests.swift:196/266`, `ExitFeeAttributionTests.swift:76`, `ExitStatusParserTests.swift:289` | `transactions: []` |

### 1c. Offboard and arkoor results

1. `BarkWalletFFI+Transactions.swift:270-279` `sendToOnchain`: bind
   `let result = try await wallet.sendOnchain(…)`, log
   `result.txid` and `result.movementId`, `return result.txid`. The
   variable is called `roundState` today and the comment block around it
   is stale (two TODOs about a method that no longer exists); replace the
   block with one sentence.
2. `BarkWalletFFI+Transactions.swift:226` `send`: bind the movement id, log
   it at info with the amount, keep the returned String unchanged (its only
   use is a success message). Track B feeds it to `PendingPaymentMetadata`.

### 1d. Build

`XcodeRefreshCodeIssuesInFile` per edited file as the edits land, then one
`BuildProject` (active scheme "Arke mobile", `buildForTesting`) at the end
of the phase. Expect zero errors; the only expected warning change is the
unused-result warning disappearing.

## Phase 2 — Balance fields and totals (Track A)

Why in the release: without this, every wallet with an expired VTXO or an
arkoor send / offboard in flight shows a smaller Ark total after the
update, and the two users' wallets are exactly the expired case.

1. `Shared/Models/ArkBalanceResponse.swift`: add **four** fields —
   `needsRefreshSat`, `claimableLightningReceiveSat` (bark has had it since
   0.7.1; it was never mapped, review finding 3), `pendingArkoorSendSat`,
   `pendingOffboardSat` (`Int`, coding keys in bark-json's spelling:
   `needs_refresh_sat`, `claimable_lightning_receive_sat`,
   `pending_arkoor_send_sat`, `pending_offboard_sat`). `totalPendingSat`
   adds the three pending buckets (bark's `pending()` is then matched
   field for field: in-round, board, arkoor send, lightning send,
   claimable lightning receive, offboard, exit); `totalSat = spendableSat +
   needsRefreshSat + totalPendingSat` = bark's `Balance::total`. One more
   computed property, `heldSat = needsRefreshSat + totalPendingSat`, for
   the card (item 5). Add `…BTC` mirrors only if a caller appears.
2. `Shared/Models/ArkBalanceModel.swift`: the same four stored properties
   **with `= 0` defaults** (CloudKit-mirrored SwiftData model; additive
   properties with defaults are a lightweight migration; a build-25
   secondary ignores the extra fields, build 26 reading an old record gets
   zeros). The memberwise `init` gains the four as **defaulted
   parameters** (`= 0`), so the five constructors in
   `Tests/Shared/ReadOnlySyncedDataTests.swift` and the two that build a
   zero model (`BalanceService`, `ReadOnlyBalanceService`) compile
   unchanged; `init(from:)` and `update(from:)` copy all four;
   `totalPendingSat`, `totalSat`, `heldSat` mirror the response.
3. Constructors of the response: `BarkWalletFFI+Balance` preview (zeros)
   and live (map `ffiBalance.needsRefreshSats`,
   `claimableLightningReceiveSats`, `pendingArkoorSendSats`,
   `pendingOffboardSats`), `MockBarkWallet`, `WalletManager+Export` (built
   from the model — copy the four so the export's total matches the
   screen). Constructors of the model: `BalanceService` (API path passes
   through `init(from:)`), `TotalBalanceModel`. **Sibling sweep rule:**
   grep `ArkBalanceResponse(` and `ArkBalanceModel(` again after editing;
   the compiler finds explicit inits, but the two `totalSat` copies and
   the two `totalPendingSat` copies are the kind of second site the ledger
   is full of — all four change or none.
4. `BarkWalletFFI+Balance` log lines: add "Needs refresh", "Claimable
   Lightning receive", "Pending arkoor send", "Pending offboard". The
   needs-refresh line is what the users' and Christoph's exports will be
   read for.
5. The card. `BalanceDetailCard` (`Shared/Views/Balance/BalanceDetailCard.swift`)
   renders `spendable`, `pending` and `total` as three figures plus the
   `pendingItems` rows, so the rows must sum to `pending` and `spendable +
   pending` must equal `total` (review finding 7). Needs-refresh is not
   pending in bark's model, but for this release it is shown **inside the
   held figure**: `BalanceView_iOS` passes `pending: heldSat` and the rows
   become "Needs refresh" (first), "Pending Lightning send", "Pending in
   round", "Pending board", "Claimable Lightning receive", "Pending arkoor
   send", "Pending offboard", "Pending exit" — same unlocalized style as
   the four existing rows (localizing the list is Tier 3). **DECIDED
   2026-10-25** (Christoph: "I agree with option 1" — needs-refresh inside
   the card's Pending figure for this release, so Available + Pending still
   equals Total and the card component is untouched). The card's own
   needs-refresh state (its own line, copy, no CTA) stays with the Tier 0
   cluster item and Track B.
6. `TotalBalanceModel` uses `spendableSat` for "available" — correct,
   unchanged — and `totalSat` for the grand total and the Ark share, which
   pick up the new total through the model.
7. `DeleteWalletSettingView.syncedForfeitSummary` (read-only secondaries
   only) computes `totalSat - pendingExitSat` as "Spendable + Locked".
   After this phase it also counts needs-refresh, claimable receives and
   the two leaving buckets. Over-warning is the safe direction for a
   forfeit box; accepted and noted here, revisit with the Tier 3 "delete
   with exit in flight" item.

Not in Track A: `balanceSummary()` on the protocol (Track B; the app
already computes the same four numbers).

## Phase 3 — Logger (Track A, DECIDED 2026-10-25)

`Shared/Data/BarkWalletFFI/BarkWalletFFI.swift:67`:
`try barkAttachOSLogger(maxLevel: .debug, redactMessages: false)` with a
two-line comment: the default went private in bindings `01db51c`; our
exports and sysdiagnose rely on these lines, and the app's own log lines
already follow the project's privacy rules (network name public, ids
private). Revisit when the debug export stops depending on the unified
log. Verified on device by scenario 1's export containing a bark line in
clear.

## Phase 4 — Onchain history after a seed import (DECIDED 2026-10-25: in Track A)

Found by the second review pass (user-outcome trace, 2026-10-25). The app
never calls `OnchainWalletProtocol.initialScan(birthdayHeight:)` (grep:
zero hits), and neither `Wallet.open` nor `OnchainWallet.default` runs it
in bark 0.8.0 (only `bark-cli` does). bark's `OnchainWallet::sync` covers
only the addresses this BDK instance has revealed; a fresh import reveals
index 0 on the first refresh and nothing else. So after the procedure a
user's **Savings balance shows only coins on address index 0** — every
later receive and every exit-claim address is invisible to `balance()` and
`transactions()`. The funds are at seed-derived addresses and not lost,
but the app cannot show or spend them. This is the network-verified
8,839-sat case in `Bark_Bindings_Feedback.md` §2.6 and the Tier 4
"`initialScanOnchain(birthdayHeight:)` on import" line, now on the
critical path of this release.

**Smallest change:** in `BarkWalletFFI.importWallet`, seed-only branch,
after `openImportedWallet` returns and before `backupWallet()`:
`_ = try await builtInWallet.initialScan(birthdayHeight: nil)` in its own
do/catch, logged, non-fatal. No protocol change (inside the FFI type), no
UI: the import already blocks on the recovery scan and the view shows
"Importing…" for the whole await; the esplora gap-50 full scan is the only
added latency (birthday is ignored on esplora). Not applied to the
backup-file branch, whose BDK database arrives with the backup. Verified
by scenario 2 (the signet wallet's Savings balance before the wipe equals
the balance after import) and by an added log line "Onchain initial scan:
N sats".

**DECIDED 2026-10-25** (Christoph: "yes"): in Track A. Without it the
procedure would need a sentence telling users with Savings funds that
those will not appear.

## Tests (Track A)

- `Tests/Shared/ExitStateMappingTests.swift`: one **separate** case —
  `ParsedExitState(from: .vtxoSwept(tipHeight: 9, spentInputs: []))` equals
  `.vtxoAlreadySpent(.init(tipHeight: 9))`, named so the Track B change
  deletes it deliberately. The existing `testRoundTrip` list asserts
  forward-then-reverse identity; it must **not** gain `.vtxoSwept`, which
  fails by construction under the lossy mapping (review finding 5).
- New `Tests/Shared/ArkBalanceTotalsTests.swift` (decision tests, not
  restatements): `totalSat` includes `needsRefreshSat`; `totalPendingSat`
  includes the three pending buckets and `heldSat` adds needs-refresh;
  `spendableSat` is untouched by `needsRefreshSat`; the response and the
  SwiftData model agree for the same input (`ArkBalanceModel(from:)` →
  `totalSat`, `heldSat`); a model built with the defaulted init reports
  zeros for the four. Pure logic — fine for the MCP runner, but run via
  `xcodebuild` like everything else.
- `ExitClaimSequenceTests` compile unchanged; no new assertion.
- Scoped: `ExitStateMappingTests`, `ArkBalanceTotalsTests`,
  `ExitClaimSequenceTests`, `PersistentExitCache`-touching suites
  (`ExitBlockedInfoTests`, `ExitFeeAttributionTests`). Full mobile suite
  **once**, after the adversarial pass has returned (DECIDED 2026-10-11).

## Review (Track A)

`fault-class-reviewer` on the commit range, area "bark FFI boundary +
balance + exits". Specific questions to hand it:

- Class 2 (path asymmetry): both `totalSat` copies, both
  `ArkBalanceModel` inits, the export's balance mapping, the read-only
  secondary's reload.
- Class 4 (boundary assumptions): that `.vtxoSwept` folding into
  cancelled never hides a claimable exit (bark: swept is terminal, "a
  refresh may still be possible" is about the VTXO, not the exit); that
  `transactions: []` on reconstructed statuses reaches no reader that now
  expects packages.
- Class 5 (trusted claims): the two "not a change" findings in
  `01-api-changes.md` §3.2 and the server-deployment assumption.

## Device checklist (Track A)

Scenarios in the order that costs least if one fails. Build fingerprint:
the new balance log line "Needs refresh: N sats" plus `git log -S
redactMessages`.

**1. In-place upgrade on Christoph's phone with the four-day stuck refresh.**
Install build 26 over 25, no wallet action. Watch: X-Ray pending rounds,
the Activity "Failed refresh" rows, the balance breakdown ("Pending in
round" now means locked inputs), and the log export. Expected (**derived**
from changelog #2443, not traced): on the first sync `sync_pending_rounds`
shrinks, cancels or re-delegates the stored participation
(`try_shrink_participation` / `adopt_participation` /
`recover_delegated_participation` in `bark/src/round/mod.rs`) and the
refresh either completes or settles as one terminal row. Grep the export
for those functions' log lines (collect the exact strings during the build
and list them here before the device day). Whatever happens here is
evidence for the Tier 1 refresh items, not a gate for the release — the
release gates are 2 and 3. If the refresh still does not finish and the
wallet is diverged in the users' sense, this phone becomes the dress
rehearsal for scenario 3.

**2. Signet: full wipe, then seed import on build 26** (the throwaway
signet wallet; its phrase stays off every tracked file). Expected: the
import completes; the log shows either the xpub lookup ("Server scanned N
xpub children") or the fallback line "Server doesn't support VTXO recovery
by xpub" followed by both mailbox scans; `recoveryReport()` logs
`recovered` ≥ the wallet's live VTXOs, `failed` empty, no "Recovery
incomplete"; Payments total equals the pre-wipe total; **Savings total
equals the pre-wipe total** (Phase 4 — without it, only index-0 coins
show); exactly one relay registration on the first launch after import,
then "not yet due for renewal" skips (rule 27); the relaunch logs "Local
wallet file is up to date" and the wipe logged "Skipping final backup
(full wipe)"; the launch verdict after a relaunch is the wallet, not
read-only (a stale `wasDemoted` flag would make a once-demoted phone
import as primary and then be blocked). Not expected: completed exits in
the exit list — the full wipe deletes `PersistentExitCache`, and only
exits bark replays from confirmed exit txs reappear. Also run the
metadata round trip here: export "Contacts & Metadata" before the wipe,
import after — contacts, tags and profile come back; per-payment notes
and tag assignments are reported unmatched (see the procedure for why).
**Stop condition:** if the export shows the
`ImportRecoveryLogic` wipe-and-reopen retries and "Recovery scan never
completed", the server answered the xpub RPC with something other than
`Unimplemented` (README fact 6) — do not send the procedure; ask Second
what their server returns for `recover_vtxos_by_xpub`. This is the users'
procedure end to end minus mainnet.

**3. The users' procedure, written** (see below), and — if Christoph's own
diverged wallet exists after scenario 1 — executed once on mainnet by him
before it is sent to anyone. Seed-touching: not recorded as done without
this. **Run 2026-10-25 (Christoph, mainnet, Debug build from Xcode):**
full wipe + seed import worked end to end. Export read the same evening:
xpub recovery path taken (so the server is on 0.8.0 — the README's
assumption is now **verified**), 631 VTXOs returned, 77 recovered
(70,802 sats), 666 skipped as spent, 0 failed/foreign; onchain initial
scan found 20,000 sats ("seed only"); import completed; the first sync
then replayed the full mailbox history with duplicated passes (feedback
§2.8) and finished after a long wait. "All looks good" (Christoph,
2026-10-26). Still to read from a later export: the "Balance retrieved …
Needs refresh: N" line and what happened to the three VTXOs that expired
at height 971843.

**4. Balance sanity on a healthy wallet:** total unchanged across the
update; the needs-refresh log line reads 0.

**5. Log export after the update** contains at least one bark line in clear
(for example the daemon start or a sync line) — proves Phase 3.

**6. Two devices, the procedure's own shape** (seed-touching, so both
phones): second phone linked as secondary; on it Settings → Delete Wallet
→ Continue (local-only) → "Rejoin This Wallet" screen appears, not tapped;
on the main phone the delete screen now offers the complete removal (its
text names iCloud and the recovery phrase); full wipe; import; balance
shows; then relaunch the second phone and tap Rejoin → it comes back
read-only, showing the new rows (a short window of stale old rows until
the CloudKit deletions land is expected). Proves procedure steps 3, 4 and
the rejoin instruction.

## User procedure (the written instructions, DECIDED: no UI)

Written for a user whose wallet shows a refresh that never completes and
whom Second has told that their funds are safe server-side. Screen names
below are the real ones (checked against the strings and views by the
review pass, 2026-10-25); re-check once on build 26 before sending. Steps,
sent together with the build 26 TestFlight link:

0. **Before you start, make sure nothing is in flight:** no "Move to
   Savings" (exit) in progress, no open Lightning invoice waiting to be
   paid, no Savings → Payments move pending. None of these survive the
   delete (the exit state, the invoice preimage and the pending board live
   only in the deleted database). Check that iCloud Drive is on for Arké
   (Settings app → your name → iCloud → Drive), or the old backup cannot
   be deleted and would survive invisibly.
1. Update to build 26 on every device that has this wallet, and open the
   app once on each.
2. Have the recovery phrase written down. The delete asks for two words of
   it before it proceeds; it does not check that you have a backup, so
   check yourself.
3. **Save your contacts and tags:** Settings → Manual Backup → "Contacts &
   Metadata" → Download, and keep the file (Files, AirDrop to a Mac). It
   contains your contacts, tag names and profile. It does **not** bring
   back the notes and tags on individual payments — those are tied to
   numbers the wallet assigns fresh after the import, and the payment
   history itself is rebuilt from the server without them. Expect the
   Activity list to start over with the recovered balance.
4. **If a second device (iPad, other iPhone) has this wallet:** on that
   device, Settings → Delete Wallet → Continue. That device deletes only
   its own copy and shows a "Rejoin This Wallet" screen afterwards — **do
   not tap it yet** (step 9). Unlinking the device from the Devices screen
   is not enough: a device that still runs the app re-registers itself,
   and the delete on your main phone will then not offer the complete
   removal.
5. On the main phone: Settings → Delete Wallet. The screen must say that
   it deletes the wallet **from this device and from iCloud, including the
   recovery phrase**. If it does not say that, another device is still
   registered — go back to step 4. Continue → enter the two words → slide
   to delete.
6. On the first-use screen pick the **same network as before (mainnet)**,
   then Import Wallet and enter the recovery phrase. The screen now calls
   the backup file "recommended" — **for this recovery it is not**: your
   backup holds the stuck state and would bring it straight back. Leave
   the "Wallet Backup File" section empty and do **not** tap "Select Backup
   File". If you see a "Rejoin This Wallet" screen instead of the import,
   stop and send a log export; do not tap Rejoin.
7. Tap Import and **leave the app open in the foreground**. The import
   runs the recovery scan and the onchain scan, then the first sync
   replays your whole payment history from the server. On a wallet with a
   long history this takes **many minutes** (Christoph's own re-import on
   2026-10-25: recovery in seconds, the first sync well over ten minutes
   while attached to Xcode); the Activity list shows a loading state the
   whole time and the balance appears only at the end. Do not force-quit.
   Both balances should then match what you had.
8. Import the file from step 3: Settings → Manual Backup → "Contacts &
   Metadata" → Import. Then send a log export (Settings → Data → the
   export button) either way, so we can confirm the recovery ran.
9. Second device, if any: relaunch the app and tap "Rejoin This Wallet"
   now. It comes back as a read-only companion showing the new data.

Why the detours: the app keeps one database backup per iCloud account;
"Rejoin This Wallet" and a reinstall restore that backup, which would
bring the stuck state back without a recovery scan. Only the complete
removal on the last device deletes the backup. And the contacts file goes
first because the complete removal deletes every synced row — contacts,
tags, notes — on purpose, so that a deleted wallet leaves nothing behind.

**Caveat for the metadata import (filed, see chores):** the import matches
notes to payments by an id that restarts from 1 in the new wallet, so a
file from the *old* wallet imported *after* new payments exist would
attach old notes to the wrong rows. Importing right after the re-import,
before any new payment, is safe: nothing matches, nothing is misfiled.

## Chores (Track A)

1. `Bark_Bindings_Unadopted_API.md`: baseline → v0.26.0 @ `ada76c3`; a
   "New in v0.26.0 (bark v0.8.0)" section listing the unadopted surface
   from `01-api-changes.md` §5 with the backlog entry each serves;
   Adopted-since entries for the balance fields (data only) and
   `redactMessages: false`.
2. `Bark_Bindings_Feedback.md`: asks 3 (movement ids), 6 (`walletExists`),
   8 (`paymentHash` on `LightningSend` — the `failed` case half stays
   open), 11 (`completed_at` churn), 12 (`listFinishedExits`), 17 (partly:
   `vtxoSwept` is a reason, the recovery-mailbox spent-reason is not
   answered), 19 (claim ids) → mark shipped in the table with the tag; §1.5
   gets the `getExitVtxos` doc quote.
3. `Open_Follow_Ups.md`:
   - Current train block: Train 2 cluster 0 = this bump, Track A, with the
     three device scenarios on the checklist; pre-emption line replaced by
     the fact.
   - Tier 4 "Next bump": ticked and moved to the Done log when Track A
     ships, with the tag and the users' procedure link.
   - Tier 0 divergence cluster: note that the balance half is delivered by
     the bump; the card state stays.
   - Tier 0 "failed boards stranded": upstream fix is in; becomes a Tier 2
     verification line.
   - Tier 1 Exits `estimateEmergencyExitFee`: one line "premises changed at
     0.8.0 — rewrite before build (01-api-changes §1.4)".
   - Tier 4 "0.25 included-ids gap": closes into the Track B claim-link
     entry.
   - New Track B entries (one per item in §Track B below), each ≤ 6 lines,
     pointing here.
   - Tier 3 Settings: `NotificationsSettingView_iOS` re-arms exit check-in
     reminders off `ExitVtxo.isActive`, which is true for cancelled and
     swept exits (review finding 6).
   - Tier 3 Settings, question-shaped: an import option that ignores the
     iCloud backup, so a stuck wallet can be recovered without the
     procedure's detours (DECIDED 2026-10-25: not in this release).
   - Tier 1 Data safety, new: **metadata import attaches per-payment
     annotations by `movement_<id>`**, an id that restarts from 1 after a
     seed import, so an old export imported after new payments misfiles
     notes and tags onto other rows (`MetadataImportService.apply`,
     `transactionsByTxid`); and nothing in the export survives a
     re-import for Ark payments at all. Needs a stable key (VTXO ids or
     the movement's funding txid) before the feature is offered for
     restores. From the 2026-10-25 user-outcome trace.
   - Tier 4 Bindings adoption `initialScanOnchain(birthdayHeight:)`: moves
     into this release if Phase 4 is ruled in; otherwise it stays with a
     note that the procedure's users are affected.
   - Tier 3 Deletion: the delete screen gives no warning for an exit in
     progress, an open Lightning invoice or a pending board, none of which
     survive the wipe (the existing "delete with an exit in flight" line
     widens to the three).
   - `Features/Metadata_Export_Import.md` `**Status:**` line still reads
     "Implementation not started"; Phase 2 is shipped, on-device import
     verify pending — scenario 2 now covers it.
4. `Docs/README.md` Migrations line: "… through 0.26.0".
4a. **Train rule — resolved 2026-10-25:** Christoph is back from Lugano, so
   Train 1's soak is over before build 26 ships and the "soak may not
   overlap the next Release" rule holds without an exception. He records
   the soak's minor findings separately; the Current train block gets
   "Soak closed 2026-10-25" when chore 3 is done.
4b. **Answered from source 2026-10-25, no question to Second needed.**
   Either deployed version gives bark the answer it tolerates: `server-0.8.0`
   implements `recover_vtxos_by_xpub` (`server/src/recovery.rs`, no config
   gate beyond `recovery_xpub_nb_keys`, **verified**); `server-0.7.1` has
   no such method (zero hits), and a tonic gRPC server answers an unknown
   method with `Status::unimplemented` (`tonic/src/service/router.rs`
   fallback, **verified** at tonic 0.14.5 in the cargo registry, **derived**
   for the 0.13.1 bark pins — same design, no local copy). A plain HTTP
   proxy in front that 404s an unknown path is mapped to `Unimplemented`
   as well (`tonic/src/status.rs`, gRPC's HTTP-status mapping,
   **verified**); only a proxy answering 5xx would surface as
   `Unavailable` and trip README fact 6, which scenario 2's stop
   condition still covers. bark's client is plain tonic over HTTP/2 (no
   grpc-web in `bark/src`). `ArkInfo` carries no server version, so
   scenario 2's log line is the only way to see which path ran.
5. `Development/Change_Review_Playbook.md` Bark facts: B1 re-verified at
   0.8.0 (`lib.rs:1392`); B2 re-verified (doc quote); B3, B4, B5, B6
   re-check during the build (B6: grep `start_daemon` in 0.8.0
   `Wallet::open`; the "explicit daemon start is redundant" Tier 4 item
   gets its answer).
6. `04-completion-report.md`.

## Execution order (Track A)

1. Phase 0 item 2 (cache), Phase 1, build green.
2. Phase 2, Phase 3, build green; scoped suites.
3. Adversarial pass; fix or file; `Rework_Ledger.md` lines for anything
   confirmed.
4. Full mobile suite once.
5. Chores 1–5; completion report draft; commit plan proposed (Christoph
   commits; `Package.resolved` goes in the first commit).
6. Christoph: Phase 0 item 1 (pin), **CloudKit schema deploy** (the
   adversarial pass's finding 3 turned out worse than plausible: Production
   had no schema at all on 2026-10-26 — Tier 1 Multi-device entry; deploy
   from Development once, which also makes the four new balance fields
   exist in Production), build 26 bump, scenarios 1, 2, 4, 5; scenario 3 if
   applicable; TestFlight; the procedure to the two users.

## Track B — PROPOSED Train 2 cluster (not in this release)

Each becomes a backlog entry in chore 3. Order is a suggestion.

1. **`ParsedExitState.vtxoSwept`** with `spentInputs`, its own label
   ("Swept by server"), icon, detail rows, legacy-string parse, reverse
   mapping; delete the Track A pin test; Live Activity terminal handling.
   Serves: exit correctness, the `cancelExit` prerequisites.
2. **Claim link from `ExitClaimTransaction.vtxoIds`**, `skippedVtxoIds`
   logged and shown as blocked; `ExitClaimSequenceTests` cases; protocol
   doc comment. Closes the Tier 4 "0.25 included-ids gap".
3. **Movement ids from sends** (`sendArkoorPayment`, `OffboardResult`,
   `LightningSend.movementId`) into `PendingPaymentMetadata` matching —
   feedback ask 3's "deletes the heuristic matching subsystem". Needs its
   own plan (`Send_Metadata.md`).
4. **Tier 1 Exits rewrite**: `estimateEmergencyExitFee(… feeMargin: nil)`,
   compare `exitBroadcastFeeSats` with the confirmed onchain balance, no
   sync caveat, error rule as DECIDED 2026-10-19.
5. **`retryForSecs` mirrored on the four `pay*` protocol methods** (protocol
   mirrors the FFI); `nil` everywhere until a policy exists.
6. **`walletExists(datadir:)` / `readDatadirInfo`** in `openWalletIfNeeded`
   and the existence probes (Launch_Sequence_Contract rule 3 gets a
   successor; throws on a corrupt db — design the error path first).
7. **`listFinishedExits` / `listAllExits`** as the source for the completed
   exits section, `PersistentExitCache` demoted to a display cache (B2
   stays true for `getExitVtxos`).
8. **`balanceSummary()`**, `debugInfo()` for the support screen,
   `bip321Uri` for one receive QR, `parsePaymentRequest` / `sendPayment`
   against the send flow's branching, `decodeBolt11Invoice` for invoice
   preview — each a one-paragraph proposal in the unadopted-API doc first.
9. **Refresh_Deduplication premises** re-read against #2443 (locks at
   attempt start, re-delegation, participations shrinking) — a doc pass
   with scenario 1's evidence attached.
