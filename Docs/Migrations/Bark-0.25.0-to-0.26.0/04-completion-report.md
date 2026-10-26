# Completion Report: Bark FFI v0.25.0 → v0.26.0 — Track A

**Built:** 2026-10-25 (same day as the plan: plan → two review passes →
Phases 1–4 → adversarial pass → fixes → full suite → chores).
**Result:** build green with tests (IDE build, string catalogs untouched);
scoped suites 76/76; full mobile suite **538 passed, 0 failed** via
`xcodebuild test` on the iPhone 17 Pro simulator. **Not done:** anything on
a device, the TestFlight upload, the users' procedure. Track A is not
"done" in the project's sense until device scenarios 2 and 3 pass
(seed-touching definition of done).

## What shipped

### Phase 1 — compile fixes and the terminal exit state

All 21 predicted errors in 11 files, nothing else broke. `vtxoSwept` is
folded into `.vtxoAlreadySpent` in the forward mapper
(`ParsedExitState+Bark.swift`, comment names it lossy and points at Track
B) and into the cancelled display name. `ExitVtxo.isCancelled` now matches
`.vtxoAlreadySpent`, `.vtxoSwept` **and `.canceled`** — the last was a
pre-existing asymmetry the plan review found; without it a swept or
cancelled exit would stay in `isInFlight` forever. Record constructors
filled as planned: `vtxoIds: vtxoIds, skippedVtxoIds: []` in the mock, the
preview and the test double; `paymentHash` placeholders
(`BarkWalletFFI.previewPaymentHash`, `MockBarkWallet.mockPaymentHash`) and
`movementId: nil` on the eight `LightningSend` fixtures; `transactions: []`
on the cache's reconstructed status and six test statuses. `sendToOnchain`
returns `result.txid` and logs the movement id; `send` logs the arkoor
movement id. Stale comments about a 0.11-era method removed.

### Phase 2 — balance totals

`ArkBalanceResponse` and `ArkBalanceModel` gained **four** fields:
`needsRefreshSat`, `claimableLightningReceiveSat` (bark had it since 0.7.1,
never mapped — plan-review finding 3), `pendingArkoorSendSat`,
`pendingOffboardSat`. `totalPendingSat` is bark's `pending()` field for
field; `totalSat` is `spendable + needsRefresh + pending`; new `heldSat =
needsRefresh + pending` is the balance card's Pending figure (DECIDED
2026-10-25) so Available + Pending = Total on screen. The model's init
defaults the four to 0, so the five `ReadOnlySyncedDataTests` constructors
and the zero models compile unchanged; `init(from:)` and `update(from:)`
copy all four. Constructors updated: FFI preview and live mapping, mock,
export (from the model). Views: `BalanceView_iOS` (Payments card, eight
breakdown rows, "Needs refresh" first), the X-Ray `ArkBalanceView`
(Shared) and the desktop card — the last two were missed by the plan and
found by the adversarial pass. Log line "Balance retrieved - Spendable: N
sats, Needs refresh: M sats" plus four debug lines.

### Phase 3 — logger

`barkAttachOSLogger(maxLevel: .debug, redactMessages: false)` with the
reason in the comment.

### Phase 4 — onchain history after import

`BarkWalletFFI.importWallet` runs `builtInWallet.initialScan(birthdayHeight: nil)`
after the open, **on both branches** — seed only and backup file. The
plan scoped it to the seed-only branch on the premise that a backup carries
the BDK store; the adversarial pass showed `WalletBackupService` copies
exactly one file (`db.sqlite`), so the backup-file import had the same
hole. Non-fatal, logged ("Onchain initial scan after import: N sats found
(seed only|backup file)"). The launch-time iCloud restore
(`restoreWalletFromBackup`) is the remaining sibling, filed under Tier 1
Data safety.

### Tests

- `ExitStateMappingTests.testVtxoSweptFoldsIntoAlreadySpent` — the Track A
  pin, separate from `testRoundTrip` (which must not gain the case).
- `ArkBalanceTotalsTests` (new, 6): total counts every bucket (powers of
  ten, so a missing bucket shows); pending excludes needs-refresh; held
  closes the card arithmetic; spendable untouched by an expired VTXO
  (the users' numbers: 5,000 spendable + 19,995 needs-refresh); response
  and model agree through `init(from:)` and `update(from:)`; the legacy
  five-argument model init reports zeros.
- Scoped run 76/76 (eight suites); full suite 538/538.

## Review

Two plan-level passes before code (code-correctness and user-outcome,
findings folded into the plan, see README) and one `fault-class-reviewer`
pass on the diff. Diff-pass findings and what was done:

| # | Finding | Class | Outcome |
|---|---|---|---|
| 1 | Phase 4 premise false: backups never carry the BDK store; backup-file import had the invisible-Savings hole | 5, 2 | CONFIRMED → scan on both branches; ledger row; launch-time restore filed Tier 1 |
| 2 | X-Ray `ArkBalanceView` and desktop card still on the old arithmetic | 1 | CONFIRMED → both on `heldSat`, X-Ray gets the new rows; ledger row |
| 3 | Four new fields on a CloudKit-mirrored model with no Production schema step | 1/2 | **CONFIRMED and wider** (Console, 2026-10-26): Production had no `CD_` record types at all, so no TestFlight build has ever mirrored SwiftData through CloudKit. Filed as a Tier 1 Multi-device entry; Christoph deploys the schema once before build 26; Release stage gains the step |
| 4 | `getExitVtxos()` keeps finished exits until relaunch (filtered at load) | 4/5 | PLAUSIBLE at bark source level → B2 reworded in the playbook; the `isCancelled` widening covers it |
| 5 | A failed post-import scan is permanent and silent | 2 | recorded; scenario 2's Savings check is the detector |
| 6 | `initialScan` versus the daemon's onchain sync | 3 | sound: both take the same `RwLock`; the import task is unstructured, nothing cancels it |
| 7 | `vtxoSwept` and `.canceled` terminal for the exit record | 4 | verified at `bark-0.8.0` (`FINISHED_STATES`, `ProgressStep::Done`) |

Rework ledger: two rows, 2026-10-25.

## Chores done

- `Bark_Bindings_Unadopted_API.md`: baseline v0.26.0 @ `ada76c3`; "New in
  v0.26.0" section (eleven unadopted items, each with its backlog entry);
  five Adopted-since entries.
- `Bark_Bindings_Feedback.md`: asks 3, 6, 11, 12, 19 marked shipped; 8 and
  17 marked partly shipped.
- `Open_Follow_Ups.md`: Current train cluster 0 (Track A built, Christoph's
  next steps, soak closed); pre-emption line resolved; Tier 0 failed-boards
  entry marked fixed upstream → verification; Tier 1 Exits entry carries
  the premise change; two new Tier 1 Data safety entries (metadata key,
  launch-time restore scan); Tier 3 `cancelExit` question answered; Tier 3
  deletion warning widened to invoices and boards; Tier 1 activity-date
  entry notes #2610; Tier 4 section baseline, the release entry, six Track
  B entries, the daemon entry gets B6's answer. Two items ticked and moved
  to the Done log ("0.25 included-ids gap", `initialScanOnchain` on
  import) under a new "Bark 0.26 Migration" block.
- `Change_Review_Playbook.md`: B1, B2, B6 re-verified and reworded; B7
  (balance split) and B8 (onchain sync coverage, backup contents) added.
- `Features/Metadata_Export_Import.md`: status line corrected (was
  "Implementation not started").
- `Docs/README.md`: Migrations line.
- Not done: the Tier 3 `NotificationsSettingView` re-arm note and the Tier 3
  "import ignoring backup" question were folded into existing entries'
  text rather than filed as their own lines (the deletion-warning entry and
  the Data safety restore entry carry them).

## Added after the first device run (2026-10-26)

- **Import screen hardening** (Christoph's observation during the
  re-import): once "Import" is tapped, the back button, the phrase field
  and the backup-file button are disabled for the duration
  (`ImportWalletView_iOS`, `isImporting`). Copy changed, second pass after
  Christoph's review of the first wording: the section description reads
  "Recommended if you have one. It restores your payment history and
  anything still in progress. Without it, your funds are recovered from
  the network and the history starts fresh." — no claim about notes and
  tags, which live in the metadata export. The button's second line was
  removed as a repeat of the description; its key
  (`backup_file_not_selected`) is unreferenced and goes when a build
  re-extracts the catalog. The description's translations are stale (Tier
  3 Localization line). The users' procedure explains why they must still
  leave the backup out.
- **Feedback asks 21–23** (§2.8): already-known check before chain
  validation, skip recovery-stored arkoor messages on the first sync,
  single-flight mailbox sync — from the export of the re-import.
- Procedure step 7 rewritten: first sync takes many minutes on a long
  history, leave the app open.

## Deviations from the plan

1. **Phase 4 covers both import branches**, not the seed-only one (review
   finding 1).
2. **Two more views** updated than planned (finding 2); desktop change
   unbuilt, desktop is parked.
3. **`isCancelled` also includes `.canceled`** (plan-review finding 6).
4. **The pending-items list** on the Payments card has eight rows, not
   seven: "Claimable Lightning receive" was added with the fourth field.
5. **No `ArkBalanceResponse` memberwise defaults**; every constructor names
   all nine fields. The model's init has defaults, as planned.

## Verification record

- Builds: IDE `BuildProject` with tests, green after Phase 1+3 (30 s),
  after Phase 2+4 (21 s), after the review fixes (20 s). String catalogs
  unchanged (no new localized strings; the breakdown labels are plain
  strings like their neighbours).
- Per-file diagnostics clean on every edited Swift file.
- `xcodebuild test`, simulator `7922F8F7…` (iPhone 17 Pro): scoped 76/76,
  full 538/538, zero skipped. The run had to be in the foreground: the
  tool hook timed out on every background launch attempt.
- Not executed: any device scenario, the CloudKit schema deployment, the
  users' procedure, desktop build.

## Christoph's steps (from 02-migration-plan.md, in order)

1. Review the diff; commit per the plan below.
2. Xcode: pin `bark-ffi-bindings` to `v0.26.0+bark-0.8.0` (ops item 6).
3. CloudKit: run a Debug build once (Development schema picks up the four
   fields), then Deploy Schema Changes to Production in the Console before
   any TestFlight build writes a balance.
4. Build 26, then scenarios 1, 2, 4, 5 (and 6 if a second phone is at
   hand); scenario 3 if the stuck wallet turns out diverged. Stop condition
   in scenario 2 for the xpub RPC error path.
5. TestFlight; the written procedure to the two users; ask for a log export
   afterwards.
