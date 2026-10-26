# Open Follow-Ups

Cross-feature index of open work, ordered by priority so the top of the file
is always "what next". Detail lives in the linked guiding docs; this file is
the index. Closed items and their write-ups live in `Open_Follow_Ups_Done.md`
(moved there 2026-10-07 when this file was restructured from workstream
sections into tiers). Last consolidated: 2026-10-07.

How to use it:

- **Tiers, not sections.** Tier 0 is funds or security at risk, Tier 1 is
  what users hit every day, Tier 2 is shipped-but-unverified work, Tier 3 is
  polish grouped by screen, Tier 4 is tech debt, Parked is deliberate.
  Within a tier, items are grouped by area; order inside a group is loose.
- **Closing an item** (DECIDED 2026-10-19, replacing "keep it in place for
  a session or two"): check it off with the date and move it to the Done
  log in the same commit. This file never holds ticked lines; 34 had piled
  up by the time of the 2026-10-19 sweep.
- **New items**: add them to the tier they belong in. An entry is a title
  plus at most about six lines — what, where, why that tier, and a pointer
  to the plan doc that holds the evidence (DECIDED 2026-10-19). Evidence,
  traces and history go in a `Features/*.md` plan while open and travel to
  the Done log when closed. Cite symbols (type, function, property) rather
  than `file:line`; line numbers rot within days. Christoph's Reminders app
  is capture-only; sweep it into this file at the end of a session.
  `python3 Scripts/backlog_stats.py` prints the counts and flags ticked or
  oversize entries.
- **DECIDE / PROPOSAL** markers mean Christoph has not ruled; nothing below
  them is a decision until he says so.

Counts at consolidation: 211 open + 1 partial items from the old layout,
consolidated into 191 entries here (duplicates and same-screen items merged,
nothing dropped); 73 closed items moved to the Done log.

Hygiene pass 2026-10-09: every Decisions, Tier 0 and Tier 1 entry was checked
against the code and the deployed bindings (read, not executed, except the
BIP39 import test); the whole file was swept for duplicates. About two thirds
held apart from line drift. Entries corrected in place carry no marker; the
notable ones are the BIP39 item (bark rejects a bad checksum itself, moved to
Tier 3), the Lightning claim service (disabled since April, not polling), the
expiry reminder (gated by system permission, not the in-app toggle), and the
balance card (no expired state at all). Five items closed, three moved up to
Tier 0, six moved out of Tier 1, twelve merges. 2026-10-10: Second's answer
on the mainnet case reframed the Tier 0 "expired VTXOs" cluster as wallet
state divergence (funds safe server-side) and took the field evidence off
the expiry safety-net decision.

## Current train

Process: `Development/Release_Train.md` — a train is one release that moves
through six stages in order (Decide → Build → Review → Device → Release →
Soak), each closed by a condition, not a date; Build has a soft budget of
about two weeks of working time (DECIDED 2026-10-10, replacing the fixed
two-week calendar). This block names the stage, the picks and the
deferrals; it is rewritten when a train closes and the previous one is
summarised in one line under "Past trains".

**Train 1** — opened 2026-10-08.

| Stage | Status |
|---|---|
| Decide | rulings done 2026-10-10 (15 of 16; exploration season explicitly deferred); picks below PROPOSED, Christoph to confirm |
| Build | started 2026-10-09 with the hygiene pass; **cut DECIDED 2026-10-19** (see below); **closed 2026-10-19** — fee ceiling, cosmetic pass and loading wave all committed (through b270c7d), 531/531 |
| Review | per cluster as built (deletion cluster: four adversarial passes, all filed); `/code-review` over the range since build 23 on 2026-10-21 |
| Device | deletion cluster fully device-checked (10-14, 10-15, 10-16, 10-19); owed cosmetic looks done 10-21; **manual pass on the frozen build done 2026-10-21, everything works** (Christoph); the remaining checklist items are Tier 2 debt and do not gate the upload |
| Release | **2026-10-21**: code frozen at `fd4e2f8`, suite 566/566, `/code-review` ten findings filed (DECIDED 2026-10-21: none fixed before the upload, all ride into Train 2 with their clusters), **build 25** bumped and committed; TestFlight upload + notes next |
| Soak | Plan B Forum, Lugano, from 2026-10-22 — a week of conference use on the new build |

**Cut DECIDED 2026-10-19** (Christoph: TestFlight before Lugano). Build
closes with: the Tier 0 mainnet fee-rate crash (cluster 4's first item,
pulled forward because mainnet payments at a conference are the field
condition) and a cosmetic pass from Tier 3 — QR screen brightening,
"-0 B fees paid" no-fee state, exit-status txid copy, onboard-modal minimum,
move-to-payments image line, rejoin screen styling, plus the two added the
same day: activity rows dated by the movement's own time rather than the
wallet's processing time, and (PROPOSED, not yet picked) the loading wave on
the payments / savings totals of the balance details view. Moved to Train
2: the rest of the deletion cluster (four unprotected store writes, exit
Live Activity on demotion + dead `closeWallet()`, abort-after-unregister),
clusters 3, 5 and 6, the remainder of cluster 4, the new Tier 1 gate on
onchain sends at the fee ceiling (DECIDED 2026-10-19), and the exit cost
estimate replacement via `estimateEmergencyExitFee` (Tier 1 "Exits",
DECIDED 2026-10-19, with the dead ArkéUI fee arithmetic deletion in the
opening hygiene pass).
Cosmetic pass built and committed 2026-10-19 (six items ticked in Tier 3;
the activity-dating item's step (c) came back negative and its (b) became
upstream ask 20; the loading wave was DECIDED the same evening and is
committed). Brightness device-checked. The device looks owed before the
upload (loading wave in motion, boarding modal minimum + image, tags no-fee
row, exit state rows) were done by Christoph, confirmed 2026-10-21. Code
frozen at `fd4e2f8` for his manual pass, mobile suite 566/566 via
`xcodebuild` on that commit. `/code-review` (medium, `06d3cfc..fd4e2f8`)
ran 2026-10-21 before the manual pass: ten findings, all filed (one Tier
0 deletion, two Tier 1, six Tier 3; the CloudKit import-gate claim is
already Tier 2 "Seeding scenarios" (2)), none fixed — fix-before-upload
is Christoph's ruling. Then bump to build 25 and upload.

The exploration-season ruling is parked until the most important items are
worked off (Christoph, 2026-10-09).

Tier 0 ranked on three axes — field evidence (observed loss / latent trap /
hardening), size of loss, cost of the fix including its device step. Twenty
items will not empty in one train; the ranking says which go now and why
the rest wait.

- Decide — done 2026-10-10, one decision per message in chat. Rulings that
  add Train 1 work: Savings default + no auto-switch (send cluster); nearby
  contact card (send-inputs cluster); Live Activity ends on demotion
  (deletion cluster); dead images deleted (build to confirm). Rulings that
  shape later trains: explicit linking accepted (scope pass first), S7
  ghost remedy only, S5 and the join notification after linking, expiry
  safety net (a)+(c) planned later, operator dependence recorded as contract
  rule 13a. Exploration season explicitly deferred.
- Build, Tier 0, in rank order, one cluster per session:
  1. **Divergence (field; funds safe server-side, user stuck):** the
     wallet-state-diverged cluster (classifier back-off ✓ 2026-10-11 and
     FFI log line ✓ 2026-10-11, committed `04e571f..b24fac1`; balance card
     refused state + floor on the manual path ✓ 2026-10-11, committed
     `31e0ad1..5a007ed`; orphan rows ✓ 2026-10-12 — a log artefact of the
     notification path, no rows existed, uncommitted); forfeit warning
     on deletion ✓ 2026-10-13 (amount + time to expiry, strategy-aware copy,
     uncommitted); permission-denied banner for expiry reminders.
  2. **Deletion (traced traps, same function):** skip the backup on the
     delete path ✓ 2026-10-14 (built, reviewed, device-checked the same
     evening, uncommitted; plan `Features/Wallet_Deletion_Backup_Skip.md`;
     the check surfaced the Tier 1 "deleted wallet's onchain row reappears"
     regression from 31e2f10, filed under Data safety); the two-word
     phrase confirmation next (DECIDED 2026-10-10, did not ride along;
     ✓ 2026-10-15 — own pushed screen between the info screen and the
     slider sheet; built, reviewed, committed `b42d536..daabaf8` and
     device-checked on one phone the same day, plan
     `Features/Wallet_Deletion_Phrase_Confirmation.md`; two-device
     override route on the Device checklist);
     partial-failure handling + `isDeleting` ✓ 2026-10-16 (gate on the
     refresh instead of a pause, DECIDED 2026-10-15; built, reviewed,
     device-checked, uncommitted; plan
     `Features/Wallet_Deletion_Partial_Failure.md`); ghost-hardening
     residual (clear-first + surfaced unregister error, same in
     `unlinkDevice`); wrap the four unprotected store writes; end the exit
     Live Activity on demotion + drop dead `closeWallet()` (DECIDED
     2026-10-10, same file).
  3. **Phrase exposure (hardening, cheap):** clipboard 2–3 min + QR-sheet
     selection off; screen-capture / `privacySensitive` on the four phrase
     surfaces. Device check: Handoff paste at 60 s and local paste at 70 s.
  4. **Send inputs (hardening, cheap, one detector):** mainnet fee ceiling +
     test; BIP-353 query skip + softer error; paste fallback + the shared
     `detectFormatOrNil` fix (also header proposal (d)); nearby received
     sheet shows a contact only when every URI destination is theirs
     (DECIDED 2026-10-10).
  5. **Boards (incident-derived, small):** `maxVtxoAmount` into the boarding
     form, refuse client-side, disable while the server is unreachable.
  6. **Ops, Christoph's hands:** rotate `RELAY_API_TOKEN` on the relay and
     move the token out of the tree; pin `bark-ffi-bindings` and BIP39 to
     revisions in Xcode's Package Dependencies.
  Then the Tier 1 cluster: the three send proposals (address header, fee
  three-state incl. the static-20 fallback, onchain from Payments) — the
  last one needs the onchain-default ruling. Added 2026-10-12 (DECIDED):
  the Tier 1 Connectivity icon fix, "no Ark connection" shown for the whole
  launch refresh — built and reviewed the same day, device check in the
  Device stage (one launch, icon must not appear); and the Tier 1 launch
  load indicator (built, reviewed and device-checked 2026-10-13 as a glyph
  wave on the amount; DONE, Device stage has nothing left on it). Added
  2026-10-14 (DECIDED): the Tier 1 Connectivity item "Ark data waits for the
  onchain sync on every refresh" — Step 2 split into Ark sync → early Ark
  publish → onchain sync, plus the balance service publishing the Ark
  balance on arrival; plan in `Features/Launch_Ark_First_Refresh.md`, device
  check one unattached cold launch with a mailbox payment waiting.
- Deferred to Train 2, each with its reason: claimed-exit funds (design pass
  on the claim address + test rewrite); backup binding to wallet hash
  (format change on seed-adjacent state, design first — moves into this
  train if the mainnet user confirms a restore); `checkReadOnlyMode` (fix
  after the Tier 2 self-unlink run in the Device stage settles the shape);
  metadata-import name merge (medium, no field evidence; pull forward if
  cluster 4 finishes early); security gating (design unblocked 2026-10-10,
  explicit linking accepted; build with or after the linking scope pass); the
  offline feature; CI; the bindings bump with bark's recovery fixes (waits
  on a bindings release from Second).
- Review — fresh-context adversarial pass per cluster against the five
  fault classes (`Development/Change_Review_Playbook.md`); findings fixed or
  filed, ledger lines written, then the device checklist
  (`Development/Device_Day_<date>.md`, dated the day Review closes).
- Device — the two-device set: deletion + rejoin, deletion strategy,
  second-iPhone read-only data, seeding scenarios (incl. the Faucetto
  duplicate), SwiftData import crash repro, self-unlink → relaunch; plus
  exit blocked state and exit completion with the stuck-signet wallet; plus
  the phrase-exposure paste checks from cluster 3.
- Release — bump build number, code-review pass, mobile suite via
  `xcodebuild`, TestFlight.
- Soak — 0xdead10cc signatures in Organizer, bark 0.25 day-15 renewal
  (~2026-10-11, observable on the current build already), auth-wake journal
  rows.

**Train 2 — PROPOSED 2026-10-19** (asked by Christoph while Train 1 waits
for its Release; Soak may overlap Decide and Build, not Release). Tier 0 is
not empty at Train 1's Release, so Train 2 takes nothing from Tier 3 or 4
beyond the already-DECIDED ArkéUI fee-arithmetic deletion. Build runs while
Christoph is in Lugano; Device is his first home stretch with both phones
afterwards, and the Lugano soak's findings are read into the picks before
Build closes. Picks, one cluster per session, in order:

0. **Bindings bump v0.26.0 (bark 0.8.0), Track A — the recovery release**
   (pre-empted to the front 2026-10-25 when Second cut the release; two
   mainnet users with diverged wallets re-import on it). Built 2026-10-25:
   compile fixes, balance totals with `needsRefreshSat`, `vtxoSwept` folded
   into cancelled, bark logger kept public, onchain `initialScan` after
   import; adversarial pass done, two findings fixed (ledger). Plan, device
   scenarios 1–6 and the users' procedure:
   `Migrations/Bark-0.25.0-to-0.26.0/`. Christoph next: pin the package to
   the tag, deploy the CloudKit schema (four new `ArkBalanceModel` fields) to
   Production, build 26, scenarios, TestFlight, procedure to the users.
   Track B (nine items) filed under Tier 4 "Bindings adoption" as the
   follow-on cluster. Soak of Train 1 closed 2026-10-25 on Christoph's
   return; its minor findings he records separately.
1. **Train 1 leftovers, Tier 0** — deletion residual (four unprotected store
   writes; exit Live Activity on demotion + dead `closeWallet()`, DECIDED;
   abort-after-Step-1 reorder, PROPOSED fix needs a ruling) and the
   permission-denied banner for expiry reminders. Plans exist, files are warm.
2. **Phrase exposure, Tier 0** — clipboard 2–3 min, QR-sheet selection off,
   `privacySensitive` / capture hiding on the four phrase surfaces.
3. **Send path, Tier 0 + DECIDED Tier 1** — BIP-353 query skip + softer
   error; paste fallback + the shared `detectFormatOrNil` fix; nearby sheet
   contact rule (DECIDED); onchain-send gate at the fee ceiling (DECIDED);
   BDK estimator full-scan-and-retry (option (a), PROPOSED). Lugano's
   send-path findings land here.
4. **Exits, DECIDED Tier 1** — `estimateEmergencyExitFee` replacement; its
   device step shares the stuck-signet session with the Tier 2 exit items.
5. **Boards, Tier 0** — `maxVtxoAmount` into the boarding form, refuse
   client-side. The "disable while unreachable" half waits on the
   connectivity signal (Tier 1 "can never show disconnected"), which is
   PROPOSED as the one Tier 1 connectivity pick if the soak evidences it.
6. **Ops, Christoph's hands** — rotate `RELAY_API_TOKEN` and move it out of
   the tree; pin `bark-ffi-bindings` and BIP39 in Xcode.

Pre-emption: happened 2026-10-25 (cluster 0 above); 5 and 4 move back one
slot each, and 4 is rewritten first (its premises changed at bark 0.8.0,
see the Tier 1 Exits entry). Deferred to Train 3 with
reasons: the three send proposals (design-heavy; the detector fix rides
with 3), claimed-exit funds and backup binding (design first),
`checkReadOnlyMode` (after the self-unlink run on this train's device day),
metadata-import name merge (no field evidence; pull forward if 2 is quick),
security gating (after the linking scope pass), the offline feature beyond
its signal. Device checklist: the Tier 2 two-device set, exit blocked state
+ completion, phrase paste checks, forced-clamp look, cold-launch export
with Step markers. Decide stage: the eight DECIDE lines below are PROPOSED
for bulk deferral except "disable the Settings exit entry while an exit is
active", which cluster 4 touches.

**Past trains:** none yet.

## Decisions needed (Christoph)

Scattered DECIDE and PROPOSAL items pulled together because they block
Tier 0/1 work. Guiding docs hold the full arguments.

Rulings already made (DECIDED 2026-10-10 ×17, 2026-10-19 ×2) moved verbatim
to `Open_Follow_Ups_Done.md` → "Moved from the open list 2026-10-19" on
2026-10-19; the entries they produced carry the DECIDED label in place.

- [ ] **DECIDE — exploration season** (`Development/Exploration_Season.md`,
  PROPOSED 2026-10-07): a four-phase season favouring the ten roadmap
  features over stability. Phase 1 is scope docs only (one per feature plus
  the three abstraction designs, iterated until ruled); then foundations
  under the floor, then flagged features, then consolidation. App labelled
  experimental, flags carry kill-or-ship entries, Tier 0 / seed / schema /
  network-config / money-path work keeps the full process throughout. Eight
  calls at the end of the doc (season, floor, gate G1/G2, Phase 4 in scope,
  abstractions as Phase 1 work, accounting, agents hub, usernames without
  BOLT-12). **Explicitly deferred 2026-10-09 by Christoph** until the most
  important items are worked off; stays on this list as a reminder, not a
  blocker. Re-raise in a Decide stage once Tier 0 has been emptied once.

Question-shaped lines moved here from Tier 3 on 2026-10-19 (sweep): each
needs a ruling or a sentence of reasoning before it can become work.

- [ ] **DECIDE — Settings — combine unit format and show-balance?** (question).
- [ ] **DECIDE — Disable the Settings exit entry while an exit is active?**
- [ ] **DECIDE — When the daemon auto-exits VTXOs, how to detect and tell the user?**
- [ ] **DECIDE — Is there exit grouping, or is each VTXO its own movement entry?**
- [ ] **DECIDE — Options to handle failed Lightning payments (exit?)**.
- [ ] **DECIDE — Hide failed and completed refreshes that were free?** (The growing
  "Failed refresh" list in the Tier 0 divergence cluster is the extreme
  case; this line is the general one.)
- [ ] **DECIDE — Backup — how to explain that not all wallets are compatible?**
- [ ] **DECIDE — Fiat on transaction detail and rows** — skipped 2026-09-29 (decide the
  "today's rate" wording first). `Features/Fiat_Rates.md` Phase 3.

## Tier 0 — Funds or security at risk

- [ ] **Backup restore is newest-wins with no wallet binding**: one
  `Backups/db.sqlite` slot per iCloud account, written by plain file copy;
  on launch `restoreWalletIfNeeded` (`WalletManager.swift:1339-1360`, primary
  only) replaces the local database when the backup's modification date is
  later. Nothing ties a backup to a wallet hash or a sequence number, so a
  device can start from an older or foreign VTXO database (local-only state
  is what unilateral exit depends on). Fix: bind each backup to the wallet
  hash and a monotonic counter and refuse mismatches; binding also
  neutralises the leftover-backup restore above. Possible field case
  (2026-10-10): Second's hypothesis for the mainnet divergence incident
  below is a restore from backup or a reinstall + iCloud restore, which a
  newest-wins restore of an older `db.sqlite` would produce (the wallet
  forgets a round it already took part in). Unconfirmed — our two log
  exports show "Local wallet file is up to date" and earlier sessions are
  unseen; the user has been asked. If confirmed, this becomes the
  field-evidenced root cause and moves into Train 1. Journal question closed
  2026-10-09: bark 0.7.1 sets no `PRAGMA journal_mode` in
  `SqliteClient::open`, so SQLite's default rollback journal applies and
  there are no `-wal`/`-shm` side files; the remaining copy risk is a backup
  taken mid-transaction, which stopping the daemon first mitigates.
- [ ] **Claimed exit funds invisible after seed import** (network-verified
  2026-08-13: 8,839 sats confirmed-unspent at the claim address, absent from
  balance — 143,041 shown vs 151,880 actual). `ExitClaimSequence.run` reveals
  a fresh address (`getOnchainAddress()` = `reveal_next_address`) as its FIRST
  step on every claim attempt, before `drainExits` can fail, and
  `ExitProgressionService` auto-retries failed claims each interval, so every
  failed attempt burns a derivation index. Claim addresses bypass
  `AddressService` history (untracked, not gap-limited); seed import loses the
  revealed-index state and both BDK gap-10 scans stop short. The receive
  screen's 20-unused cap also independently exceeds gap-10. Mitigations:
  (a) reveal the claim address only after a successful `drainExits` build, or
  persist one claim address per exit — `ExitProgressTests.testSequenceOrder`
  currently pins address-first and must change with it; (b) route claim
  addresses through `AddressService`; (c) import scan stop gap ≥ unused cap
  + margin (~50); (d) upstream — no rescan API (feedback §2.6). Also blocks
  the exit movement from linking its claim tx (`onchain_… not found` on
  every relink pass). Related adoption: Tier 4
  `initialScanOnchain(birthdayHeight:)`.
- [ ] **Wallet state diverged from the server, and the app can neither see
  it nor say so** (field incident, mainnet, build 24, logs read 2026-10-07
  and 2026-10-09; wallet id and VTXO ids in the support thread; reframed
  2026-10-10 after Second's answer). Second found a *successful* refresh of
  the user's three VTXOs server-side — no funds lost — but the wallet missed
  the mailbox message that settles the forfeit, so it still holds the
  pre-refresh VTXOs (now spent in that round) and cannot auto-resolve. From
  the app's side: bark's selection logs them `is expired, must be
  refreshed`, every launch's auto-check and every "Refresh now" tap write a
  Pending refresh movement, the server rejects it as `unusable_inputs`, the
  movement flips to Failed, and the balance keeps showing 19,995 sats the
  user cannot spend. Root-cause candidates, both open: Second asks whether
  the user restored from a backup or reinstalled and restored from iCloud
  (see "Backup restore is newest-wins" above — our two log exports show
  "Local wallet file is up to date", earlier sessions unseen); and upstream
  server commit `dfd425d4a` (2026-09-18, after `server-0.7.1`) fixes mailbox
  checkpoint paging where a page boundary inside a batch "skipped the
  remaining rows for good", in both mailboxes — a lost message with no user
  action. Remedy per Second: recovery from seed, once bark's recovery-path
  fixes ship; for Arké that is the bindings bump (Tier 4 "Next bump"),
  since our 0.7.1 bindings predate every one of those fixes, so the user
  should hold the recovery until then. Four app defects, one cluster:
  - [x] **`isAlreadyIssuedRejection` treats every `unusable_inputs` as "already
    issued into a round"** — done 2026-10-11 (`Features/Refresh_Deduplication.md`
    §9): verified at `server-0.7.1` that the tag fires for any unspendable
    input (spent, exited, banned; no expiry check) and the message names the
    ids. Now `isUnusableInputsRejection` + `RefreshRejection.classify`
    (in flight only when the ids are in `vtxoIdsBeingRefreshed()` after the
    refetch) + `RefreshRejectionBackoff` (24 h per id, device-local
    `com.arke.refresh.rejectedInputs`, pruned to the spendable set, batch
    entries yield inside the 144-block valve). Manual path returns
    `.rejectedByServer`; the modal says "Can't refresh from this device" with
    the recovery-phrase + contact-support hint, never "funds lost". 16 unit
    tests (four implementation-restating ones dropped on review, 2026-10-11);
    wipe key added. Adversarial pass 2026-10-11 fixed two CONFIRMED
    findings in-session (a stale Pending movement on an expired VTXO passed
    Guard C's valve and would have read as "in flight" — in-flight now means
    *newly* locked since the pre-call read; the card's list now mirrors the
    back-off so a partial batch cannot report success). Left open from that
    pass, no app fix: **bark's daemon joins every round's first attempt for
    maintenance refresh** (`join_round_for_maintenance_refresh`, bark-0.7.1
    `daemon/mod.rs:155-160`) with the same dead VTXOs, so one Failed refresh
    row per *round* keeps arriving regardless of the app-side back-off —
    confirm in the next field log (bark lines "Joining round … for maintenance
    refresh" / "Maintenance refresh rejected"); it is the bindings bump's to
    fix; defect 4 turned out to be a log artefact, no app-side rows to prune
    (2026-10-12), so the Failed rows that remain are bark's own. Also: a
    `NotFound` ("input vtxo does not exist") rejection is deliberately not
    matched and would still retry as an ordinary error — fold into the Tier 4
    typed-errors item. **Device check owed**: no reliable repro from the app
    (needs the server to refuse); watch the next debug export from the mainnet
    user for the new FFI line carrying the server text with ids (confirms the
    `{:#}` chain reaches the app — plan claim C4, derived), the warning
    "holding them back for 24h", and one app-side Failed row per day.
  - [x] **The balance card has no expired state at all** — done 2026-10-11
    (`Features/Refresh_Deduplication.md` §10). The card now resolves one of
    refreshing / refresh now / refused / too small / countdown / idle via
    `BalanceRefreshCardState`, with the same Guard B → Guard C (valve) →
    back-off order as the service; refused shows "Can't refresh from this
    device" + the held-back amount, no CTA; the 330 floor is one shared
    constant on the auto path, the manual path (`.belowMinimum`) and the
    card; a new `refreshStatusVersion` reloads the card *after* a verdict is
    recorded (the refetch bumped `transactionVersion` too early). Adversarial
    pass fixed two CONFIRMED findings in-session (a dust sibling masked the
    refusal; modal/card contradiction), 8 new tests, 34/34 scoped. Mixed case
    (refreshable + held back) DECIDED 2026-10-11: the compact row shows the
    primary state only; the "Held back" row lives on the full card. New
    keys (5) wait for the next translation batch. Device check owed with defect 1's: the mainnet
    user's next export should show the row, and a tap landing on the refused
    screen. Headline balance untouched (DECIDED 2026-10-11, row only).
    Original entry: The only place the app
    labels a VTXO Expired is the X-Ray row (`VTXORowView.swift:22-48`), and
    even there `VTXOListView_iOS` offers "Refresh all (Free)" with no expiry
    exclusion. Both refresh-status containers hardcode `isExpired: false`
    (`BalanceRefreshStatusContainer.swift:63`, `…Compact.swift:68`), the view
    model has no expiry notion and says "Refresh now" whenever
    `hasVtxosToRefresh`, and the ArkéUI `expiredContent` branch is dead
    outside previews. Hook added 2026-10-11:
    `VTXORefreshService.recentlyRejectedVtxoIds` is the set the service will
    not re-submit, and `BalanceRefreshStatusViewModel` already excludes it
    from `vtxosNeedingRefresh` — so today a rejected VTXO draws **no CTA and
    no explanation** on the card while still counting as spendable; the honest
    copy exists only in the refresh modal's `.refused` state (reachable now
    only via the race). This item supplies the card's own state for that set. The balance counts expired VTXOs as spendable because
    bark 0.7.1's `Balance` has only `spendable`/`pendingExit`; upstream master
    adds `Balance.needs_refresh`, which keeps them out of spendable, so the
    next bindings bump may deliver the balance half. These VTXOs need their
    own state, and the copy must not claim "expired, funds lost" — the app
    cannot tell a sweep from a divergence. Honest version: no refresh CTA,
    "these coins can't be refreshed from this device; recovering the wallet
    from your recovery phrase may restore them — contact support first", the
    amount shown apart from spendable. Same gate, same fix: **don't show
    "Refresh now" below the 330-sat floor** `VTXORefreshService` already
    applies (merged from Tier 3 Refresh 2026-10-09) — the CTA should be
    driven by what the service would actually refresh.
  - [x] **The FFI log line loses the server message** — done 2026-10-11:
    `BarkWalletFFI+VTXO.swift` now logs `localizedDescription` with
    `privacy: .public` for the delegated-refresh call only (the server text
    carries VTXO ids, which bark's own selection logger already prints). The
    other ~160 `\(error)` FFI log lines stay for the Tier 4 typed-errors item.
  - [x] **Every failed refresh attempt leaves an orphaned local row, and the
    orphans are the user's "growing list of Failed refresh rows"** — closed
    2026-10-12, premise wrong: there are no orphan rows. In the 2026-10-09 log
    every full-list pass (41, 42, 43 movements) matched all local rows and
    reported no orphans; all 231 "no longer exists on server" lines came from
    `processSingleMovement`, which wraps one notification movement in an
    array and reused the full upsert, so the orphan check ran against a
    one-element list and named every other Balance-tagged transfer. The
    38 → 39 step is the new Failed refresh row receiving the Balance auto-tag
    (refresh → transfer → `autoTagInternalTransfer`), counted on the next
    notification pass. The growing "Failed refresh" list is bark's own
    movement list (one real Pending → Failed movement per attempt), reduced
    by defect 1's back-off and otherwise the bindings bump's; hiding such
    rows is the separate Tier 3 line (Christoph, 2026-10-12: own focused
    item, not this cluster). Fix: `upsertTransactionsFromServerData(_:
    isCompleteMovementList:)`, the notification path passes `false`; the
    full-list path logs one summary warning per refresh instead of one line
    per row, and only for `sourceType == "ark"` rows (Christoph's 2026-10-12
    device log showed the one remaining "orphan" was his single onchain
    receive, which shares the table and never matches a movement). No rows
    are deleted on either path (unchanged). Ledger line 2026-10-12. Original
    entry: In the 2026-10-09 log each attempt adds one bark
    movement (41 → 42 → 43) *and* one more "tag assignment on orphaned
    transactions" (38 → 39): a `PersistentTransaction` whose `movement_<id>`
    txid matches no movement in the next list, kept because auto-tagging
    gave it a tag (`TransactionService+Upsert.swift:357-369`, "let them
    remain to preserve user tags"). 38 orphans ≈ 38 attempts. Find the id
    mismatch first (the row created from the daemon notification in
    `processSingleMovement` vs. the row from the list — same movement,
    different txid?), then decide pruning (orphans with only auto-tags are
    safe to drop), and log once per refresh at warning level instead of
    231 ERROR lines per session.
  Owed to the user (Christoph, support thread): the two restore questions,
  "funds confirmed safe on the server", "hold the recovery until the next
  Arké build". Owed to Second: was `dfd425d4a` deployed before this user's
  refresh round, and was the successful refresh a delegated one? None of the
  four fixes waits on the expiry safety-net DECIDE, which this incident no
  longer evidences. Related Tier 3 lines, different trigger: "Hide failed
  and completed refreshes that were free?" and "Surface expiry sweeps"
  (upstream-blocked).
- [ ] **Expiry-critical reminders are swallowed by a denied system
  permission**: `scheduleNextRefreshNotification`
  (`VTXORefreshService.swift:640-649`) skips the free-refresh reminder when
  iOS notification authorization is missing and only logs it. Corrected
  2026-10-09: the in-app toggle does **not** gate this reminder — toggle off
  unregisters push and cancels exit check-ins (`NotificationsSettingView_iOS`,
  `ExitProgressionNotifications`), and the "Notifications disabled in
  settings" log line belongs to relay registration. Re-read the field log to
  see which gate the user hit. Fix shape: an in-app banner when the system
  permission is denied while VTXOs approach expiry, naming the amount; a
  toggle exemption cannot help. Precondition for safety-net option (c).
- [ ] **`checkReadOnlyMode()` infers primary** (`WalletManager.swift:530-557`):
  a missing or unreadable device registration sets `isReadOnlyMode = false`,
  i.e. full spend rights — contradicts Principle 2 / contract rule 15.
  Reachable via self-unlink (`LinkedDevicesView_iOS.swift:50`, handler
  `:225-230` → `unlinkDevice` deletes the row and the mirror entries, so
  relaunch sees nil + `.noOpinion`). UNVERIFIED on device — needs the Tier 2
  self-unlink → relaunch run before deciding the fix. Fix this before
  collapsing `shouldBlockWalletAccess`'s layers (Tier 4). Sibling site
  (read 2026-10-08): `shouldBlockWalletAccess()` itself returns `false` when
  the device ID cannot be read (`WalletManager.swift:1247-1250`); the ID is
  stored `WhenUnlockedThisDeviceOnly` (`DeviceRegistrationService.swift:170`)
  while the seed is `AfterFirstUnlock`, and the headless wake path calls
  exactly that gate (`WalletManager+Notifications.swift:127`), so on a locked
  background wake the seed is readable and the gate is not — inferred timing,
  same fix shape: treat "unknown" as read-only until the registry answers.
  No test covers the nil-registration or unreadable-ID branches.
  Folded in 2026-10-19 from Tier 4: the `device_<id>_isPrimary` KVS key
  written by `writeOwnPrimaryFlag` has no clearer — unregister, unlink and
  the full wipe all leave it, although `SharedStateWipeCoverage` lists
  `device_<id>_*` as `fullWipeOnly` (`WalletDataCleanupService.swift:1087`);
  not read by the registry scan, but layer 2 of `shouldBlockWalletAccess`
  reads it on a reinstall whose local breadcrumb is gone. Fix with this
  item or correct the inventory label (found 2026-10-16,
  `Features/Wallet_Deletion_Ghost_Hardening.md` §7).
- [ ] **Security checks first**: switch `authenticateUser`
  (`SecurityService.swift:879-895`) to `.deviceOwnerAuthentication` (passcode
  fallback; biometrics-only hard-fails on Macs without Touch ID) and wire the
  gated-actions table (recovery phrase, deletions, promote/demote/unlink;
  send as opt-in). Its only call site (`WalletManager+Wallet.swift:22-28`)
  is commented out — nothing is gated today. Christoph's view 2026-10-08:
  showing the phrase already sits behind a tap or the scratch-off surface,
  so a show-phrase gate is not a gap on its own; the item stays for the full
  gated-actions table. Design unblocked 2026-10-10: explicit device linking
  is accepted, so the table gates actions *after* a recorded link (phrase,
  deletions, promote/demote/unlink, send as opt-in) and the link screen
  itself is not a gated action. Build with or after the linking scope pass.
- [ ] **Deletion abort after Step 1 strips this device's own blocker
  evidence** (found 2026-10-16 by the ghost-hardening review, pre-existing):
  `performDeleteWalletData` unregisters first — mirror cleared, row delete
  committed — and only then runs the fallible CloudKit deletion and the
  keychain delete. If either throws, the view returns to the info screen
  with the wallet working (`DeleteWalletSettingView.swift`, phase 1 catch)
  and nothing re-registers until the next cold launch. In that window
  another device's `otherDeviceReport` sees no blocker, is offered the full
  wipe, and deletes the shared seed under a device that still spends. The
  next launch then registers a *new* row with `isPrimaryDevice == false`
  (detection paths never claim), so an ex-primary comes back as a secondary.
  PROPOSED fix: move Step 1 to after the CloudKit step and before the
  keychain step — on a full wipe Step 2 deletes every row anyway, on
  local-only nothing fallible follows, so every abort path leaves the
  registration intact; the keychain-failure residual in rule 17 stays.
  Needs the refresh-gate tests' "nothing destructive reached" proof
  re-anchored. Plan `Features/Wallet_Deletion_Ghost_Hardening.md` §7.
- [ ] **Paste button accepts unverified Lightning Addresses**: in
  `SendViewModel+Clipboard`, `tryParallelResolution` (`:154`, fallback
  `:216-219`) and `tryLightningAddressFallback` (`:239`, fallback `:251-253`)
  fall back to `AddressValidator.parsePaymentRequest` when both lookups fail,
  and its `user@domain.tld` regex (`AddressValidator.swift:350-352`) accepts
  anything. Typing the same address rejects it (`ManualSendView.swift:337`,
  `:386`). Seen with `chri@sto.ph`. Remove the fallback or show a "couldn't
  verify" state so both paths match. Shares a root with the Tier 1
  address-header proposal (d): `BIP353Resolver.detectFormatOrNil` accepts
  plain `user@domain` — fix the detector once for both.
- [ ] **BIP-353: stop sending the DNS query while DNSSEC is unimplemented**
  — `performDNSLookup` (`BIP353Resolver.swift:176`) runs before
  `validateDNSSEC` (`:184`), which always returns `false` (`:395-407`), so
  every lookup is refused but the query is still sent and its answer thrown
  away, telling the network's DNS who the user is about to pay. Five callers
  all send it: `SendViewModel+Clipboard.swift:128,160`,
  `SendViewModel+Initialization.swift:36`, `ManualSendView.swift:337`,
  `ContactPaymentView.swift:170`. Skip the query now; soften the error text
  ("address may be compromised" + both raw errors), which lives in
  `BIP353Error.errorDescription` (`:139-140`), not in the views. Full DNSSEC
  implementation is Tier 1.
- [ ] **`RelayAPIToken` is checked into the repo**: the 64-hex value sits in
  `ArkeMobile/Info.plist:15-16` (tracked, in history since 9c4a5a2) and is
  read at `WalletManager.swift:430`; no xcconfig exists, tracked or not. The
  relay reads `RELAY_API_TOKEN` from its environment and its guard comment
  acknowledges the token ships in the app. Whatever the injection mechanism
  (untracked xcconfig, build-phase injection, per-device relay auth), the
  token has to be **rotated** on the relay as well, since history keeps it.
- [ ] **No screen-capture protection on the recovery phrase**: nothing in
  the repo observes `UIScreen.isCaptured` or uses `privacySensitive()`.
  Phrase surfaces: `ManualBackupView_iOS`, `ScratchableMnemonicGrid_iOS`,
  `RecoveryPhraseSettingView` (Shared), desktop `ManualBackupView`. Hide
  while recorded or mirrored; exclude from the app-switcher snapshot. One
  "phrase exposure" cluster with the clipboard item below.
- [ ] **Recovery phrase clipboard** (moved up from Tier 1 2026-10-09; the
  train and the ledger already treated it as Tier 0): expiry of 60 s
  (`copySecretToClipboard` default, `Shared/Helpers/Clipboard.swift:27`, sole
  caller `RecoveryPhraseSettingView.swift:78`) is too short to reach a
  password manager — raise to 2–3 min. macOS still uses the plain general
  pasteboard with no expiry (`Clipboard.swift:17-18`) —
  `org.nspasteboard.ConcealedType` + delayed clear (**assumed**: a
  third-party clipboard-manager convention, not an Apple API; whether
  Universal Clipboard honours it is unverified — label stays until checked
  on a Mac + iPhone).
  - [ ] **QR sheet bypasses the hardened Copy button** (fault-class review of
    `0de06d4`, 2026-10-07, CONFIRMED, class 2): `RecoveryPhraseSettingView`
    (`:208-209`) hands the mnemonic to `ArkeQRCodeView`, which renders it as
    `Text(content).textSelection(.enabled)` (`ArkeQRCodeView.swift:73-76`,
    no selection parameter on the init); long-press → Copy writes the phrase
    to the plain general pasteboard with no `.localOnly` and no expiry, one
    button to the right of the fixed one. Fix: a parameter on `ArkeQRCodeView`
    to disable selection, or a secret-aware variant. Its only other caller is
    the desktop Receive QR (`ArkeDesktop/Views/Receive/ReceiveView.swift:215`);
    the mobile receive QR does not use this view. Same review also noted the
    desktop Send view calls `checkClipboardForAddress()` on every
    `didBecomeKey` (`ArkeDesktop/Views/Send/SendView.swift:93-97`) and the
    shared method (`Shared/Views/Send/SendViewModel/SendViewModel+Clipboard.swift`,
    comment at `:31` claims tap-only — false on macOS) logs the content at
    debug (`:48`); redacted on device, plaintext in the console. Desktop is
    parked, so note only. Device check owed for the iOS fix itself:
    two-device Handoff paste within 60 s (expect nothing) and local paste at
    ~70 s (expect nothing).
- [ ] **Metadata import attaches addresses to existing contacts by name**
  (moved up from Tier 1 2026-10-09: a foreign file can set the default payee
  of a trusted contact, which misdirects funds). `MetadataImportService.swift`
  `matchContact` (`:55-63`): an imported contact merges by UUID, then by any
  shared address, then by normalized name alone; `mergeAddresses`
  (`:356-382`) inserts addresses without `AddressValidator` (no reference in
  the file), maps an unknown `format` string silently to `.bitcoin`, and
  applies an imported primary flag when the local contact has none (`:372`).
  The preview shows counts only (`MetadataBackupSectionView.swift:200-225`).
  Fix: validate imported addresses, drop or disclose name-only merges, list
  added addresses per contact in the preview.
- [ ] **Pin `bark-ffi-bindings` and BIP39 to tags, not branches** (moved up
  from Tier 1 2026-10-09: supply chain into the component that holds keys):
  `project.pbxproj:1164-1170` has `bark-ffi-bindings` on `master` and
  `:1180-1186` `anquii/BIP39` on `main`; `Package.resolved` holds revisions,
  so builds are stable only until "Update to Latest Package Versions" pulls
  whatever is on the branch. Xcode UI change (Package Dependencies → exact
  version / revision); review the diff on each bump.
- [ ] **Background runs killed for holding a store lock (0xdead10cc)** —
  mitigations shipped 2026-09-24 (probe write removed, task assertions around
  `registerCurrentDevice` and the headless open, the only two wrappers that
  exist; see Done log). Still open: **audit the other unprotected store
  writes on background-reachable paths**: `unregisterCurrentDevice`
  (`DeviceRegistrationService.swift:457-491`), the upsert in
  `refreshTransactionsAfterWrite` (`TransactionService.swift:161-181`), the
  balance persist (`BalanceService.swift:318-347`), and — added 2026-10-09 —
  `TransactionService.processSingleMovement` (`:185-200`), which the daemon
  stream drives from `WalletNotificationService.swift:268,285`. Only the two
  crash-proven sites were wrapped.
- [ ] **Failed boards leave onchain coins stranded on bark 0.7.1** — upstream
  fix `f85ca92ac` ships in bark 0.8.0 (bindings v0.26.0, built 2026-10-25),
  so this becomes a Tier 2 verification once build 26 is on a phone: a
  board refused after signing leaves the onchain wallet untouched (surfaced
  by the 2026-10-05 Second server incident: an attacker registered boards
  with only his own signatures via `BoardBuilder::new_from_vtxo`, a lib
  function only the server's register-board handler calls, so our client
  never ran the vulnerable code and user VTXOs stayed on pre-signed exit
  paths; Second lost ~0.75 BTC of its own funds). The client-side fallout is
  upstream `f85ca92ac` (2026-10-07, after our bark 0.7.1): the board flow
  stored the signed funding tx in the onchain wallet *before* the server
  cosigned, so a board refused after signing (cosign refused, below the
  minimum, network error) leaves no movement or checkpoint, the coins read
  as spent, and every sync rebroadcasts a funding tx no VTXO tracks — a
  2-of-2 output with no cosigned exit. **Derived** from the commit message,
  not reproduced. The server now also rejects register-board above
  `max_vtxo_amount` (`8fab49706`), and `BoardingModalView.swift:32` caps the
  form only by `minBoardAmount` although `ArkInfo.maxVtxoAmount` is parsed
  (`BarkWalletFFI+Configuration.swift:192`; `BoardingModalFormView` has no
  maximum parameter while `OffboardingModalFormView` does), so a user can
  trigger exactly that refusal. Now: pass the maximum into the boarding form
  and refuse client-side; disable boarding while the server is unreachable
  (also on the Tier 1 offline feature's disable list). Real fix: the
  bindings bump that carries `f85ca92ac` (Tier 4 "Bindings adoption"). Both
  upstream commits are only on `origin/master`; the local `~/workspace/bark`
  checkout is at `8adc8e7` (2026-09-30), so `git fetch` before quoting more.

- [ ] **A device-ID keychain read failure makes the delete override appear**
  — `otherDeviceReport` calls `getOrCreateDeviceId()` before reading either
  registry, so the 2026-10-16 throw-on-read-failure guard aborts with no
  evidence; `assessDeletion` maps that to `.undetermined` (nil report) and
  `shouldOfferOverride` answers true. CONFIRMED by trace, code-review
  2026-10-21; low likelihood (device unlocked, override still needs the
  acknowledgement + phrase). Fix: read both stores with an unknown own id.

## Tier 1 — What users hit every day

### Send and fees

- [ ] **Gate onchain sends while the mainnet fee estimate sits at the
  ceiling** (DECIDED 2026-10-19 as a Train 2 item; from the mainnet-ceiling
  adversarial pass F2, `Features/Mainnet_Fee_Rate_Ceiling.md` §2 and §10).
  With the 10,000 sat/vB ceiling a poisoned estimator prices a 1.4 M-sat fee
  for a 140 vB send that passes the viability check; the fee line is the
  only guard. Explicit-gate pattern (O5): when the fast tier equals
  `FeeRateService.mainnetMaxRateSatPerVb`, disable onchain sending with a
  reason ("fee estimate unreliable"), Ark and Lightning stay usable; the
  gate lifts on the next fetch below the ceiling. Signal is already there
  (the clamp warning fires on the same condition). Needs its own device
  look because it is new policy on the send path. Definition of done:
  unit test on the gate decision, on-device look with a forced clamp
  (custom network pointing at a poisoned Esplora, or a debug override).
- [ ] **BDK fee estimator is blind to onchain funds that arrived after its
  one full scan, so the exact fee and max-sendable always fall back**
  (found 2026-10-19 in the mainnet-ceiling device check export,
  `Docs/debug_logs.txt`): with 20,000 sats confirmed onchain per bark, the
  estimator threw `CoinSelection … 0 BTC available` on every attempt
  (`estimateOnchainFeeWithBDK` and `calculateOnchainMaxSendable`), and the
  send screen priced the fee from the 140 vB fallback (280 sats) and max
  from `balance - fallback`. Traced: `ensureFeeEstimator`
  (`BarkWalletFFI+Fees.swift:46-49`) full-scans only when
  `createdFreshDatabase` is true; the export has "Creating fee estimator"
  but no "database is fresh" line, so the db pre-existed and only
  `startSyncWithRevealedSpks` ran (`BDKFeeEstimator.swift:131`). The
  estimator is its own BDK wallet on which nothing ever reveals addresses,
  so a UTXO on an address bark revealed after that first scan is invisible
  to it forever — the same revealed-SPK mechanism as the §4 notes in
  `Features/BDK_Transaction_Reader_Removal.md`, now on the estimator. Not
  a funds problem (bark's own wallet sends fine); the shown fee and the
  max amount are guesses. Fix options: (a) when the estimate fails with
  insufficient funds while bark's onchain balance covers the amount, run
  one full scan and retry once; (b) reveal the estimator's external chain
  up to bark's address index before each sync; (c) retire the estimator
  (Tier 4 "BDK fee estimator removal, Phase 3", blocked upstream).
  Recommend (a): one line of policy, self-healing, no new state. Device
  evidence named: `Fee estimator database is fresh - running one-time full
  scan` followed by a `Fee calculated:` line instead of `Failed to estimate fee`.
- [ ] **PROPOSAL (2026-10-07) — Fee row three-state + stale-cache guard**:
  the fee row shows "—" for Lightning addresses and keeps the old value when
  onchain priority changes. (0) **The ranking path falls back silently**:
  when `PaymentDestinationSelector.estimateFee()` (`:388-435`) fails for a
  Lightning destination it logs "Falling back to static estimate of 20 sats"
  and `estimateFeeFallback` returns 20 (`:443`), so the fee shown can differ
  from the fee paid and a too-low estimate can fail the payment (merged from
  its own entry 2026-10-09; carried from
  `Archive/Fixes/LIGHTNING_FEE_ESTIMATION_ISSUES.md` item 3). (1) `feeAmount`
  for Lightning (`SendViewModel+ComputedProperties.swift:181-187`) returns
  only `cachedLightningFee`; when `estimateLightningSendFee` throws,
  `calculateLightningFee` nils the cache → dash, while the ranking path hides
  the same failure behind the static 20 (the "20 ₿" on the 750-sat invoice
  screenshot is that constant). `feeText` (ranked, `:146-155`) and
  `feeAmount` (cached) are two accessors shown in two places
  (`QuickPaymentView.swift:495,506`), which is how one screenshot shows "20"
  in one row and "—" in another. In quick mode with no viable ranked
  destination (`selectedDestination == nil`, balance label falls back to
  "Total balance") no fee path runs although Send is enabled.
  (2) `estimateOnchainFee` keeps the previous cache on any BDK/sync error
  (`SendViewModel+FeeEstimation.swift:73-76`) and `feeAmount` returns
  `cachedOnchainFee` without checking `cachedOnchainFeePriority` /
  `cachedOnchainFeeAmount` match (`+ComputedProperties.swift:164-168`).
  Proposal: value / estimating / unavailable states (never a bare dash, never
  a silent constant); `feeAmount` requires a cache match; log the bark error
  once and confirm on device whether the Lightning estimate really fails;
  when quick mode has no viable destination, say why.
- [ ] **PROPOSAL (2026-10-07) — Human-readable address header**: a plain
  Lightning address shows the address twice in a greyed, disabled destination
  row. `QuickPaymentView.swift:481` passes `formatNameOverride` whenever
  `BIP353Resolver.isBIP353Format` is true, and that test accepts plain
  `user@domain`; `ManualSendView`'s Lightning fallback stores the typed address
  as `originalBIP353Address` and reuses `.bip353Resolved`. The row is a button
  disabled when there are no alternatives. Proposal: (a) make the address the
  title line (replacing "Address found") with a caption like "Lightning
  address, paid from Payments balance" and drop the row; (b) keep the row only
  when there is a choice; (c) manual flow shows a one-line caption since
  "Send to" already shows the address; (d) restrict the override to
  ₿-prefixed or actually-resolved BIP-353 input — same permissive
  `BIP353Resolver.detectFormatOrNil` (`:214-244`) as the Tier 0 paste
  fallback, one detector fix serves both.
- [ ] **PROPOSAL (2026-10-07) — Send onchain from the Payments balance**
  (asked by Neil, Second): bitcoin addresses can only be paid from Savings.
  The round-based path exists — `sendToOnchain` / `estimateSendToOnchainFee`
  on `BarkWalletProtocol` (bark `Wallet.sendOnchain(address:amountSats:)`) —
  the send is used only by the offboarding modal, the fee estimate also by
  `SendViewModel+MaxSendable`. `balanceSource(for:)` maps `.bitcoin` to
  `.bitcoin` only (`PaymentDestinationSelector.swift:357-358`);
  `SendViewModel+PaymentExecution` (`:170-174`) always calls the
  onchain-wallet `sendOnchain`. Also explains "scanned Noah QR, onchain failed
  with error building tx" (empty Savings). Design: ranking emits two entries
  for bitcoin addresses, selection keyed on (destination, source); the round
  path has a server fee, no priority picker, settles at the next round — say
  so in the option row; tell third-party round sends apart from offboards
  via `AddressService` history so Activity doesn't label them "Moved".
  Default source DECIDED 2026-10-10 (Savings; five rules in the Decisions
  section): ranking must be redone with the typed amount so viability stays
  current (today it runs once at parse time and the quick flow's amount
  handler only re-selects within the stale list), the picker rows show
  source + fee + settlement, and nothing auto-switches during input.
- [ ] **Contact assignment mixes up send and receive addresses** (four
  Reminders reports: batch assignment uses the receive-to address; assigning
  a payment adds the Lightning invoice as a contact address; assigning an Ark
  transaction proposes the user's own Ark address; assigning a contact to a
  Noah Lightning-address send did not add the address — which raises the
  question whether a Lightning-address send movement carries the address at
  all, merged from Tier 3 2026-10-09). Likely one root cause in the
  assignment proposal logic — see the address-history findings in Tier 4.
  First step: one assignment on a current build to retire the pre-rework
  Reminders report "transaction address parsing (Strings → Objects) when
  assigning to contacts" (merged from Tier 2 2026-10-09, probably obsolete).
- [ ] **Failed payment errors are ugly** (Reminders). Pair with the
  three-state fee row since both touch the send summary.
- [ ] **Balance shows 0 while refreshing / "Payments balance: 0" while the
  card shows a balance** — label "Available payments balance" or hide during
  refresh (Reminders, two reports). Ask which device: on a secondary,
  `ReadOnlyBalanceService` substitutes zero models (`:52`, `:164`) and this
  is the Multi-device "fresh secondary" item instead.
- [ ] **Send all from savings to spending did not work, needs a better
  message** (Reminders).

### Exits

- [ ] **Replace the hand-rolled exit cost estimate with
  `estimateEmergencyExitFee`** (DECIDED 2026-10-19 as a Train 2 Tier 1
  item, Christoph: "do it"; supersedes the Tier 3 "exit pre-flight" line,
  which was an addition — this is a replacement). **Premises changed at
  bark 0.8.0 (bindings v0.26.0, 2026-10-25): `fundable` is deprecated and
  no longer computed from confirmed coins, the estimate never syncs or reads
  the onchain wallet, `exitBroadcastFeeSats` already includes a `feeMargin`
  (default 1.2). Rewrite the build steps below per
  `Migrations/Bark-0.25.0-to-0.26.0/01-api-changes.md` §1.4 before
  building: compare `exitBroadcastFeeSats` against the confirmed onchain
  balance in the app; the "unconfirmed funds pass our check" argument is
  moot.** The 0.7.1 description follows for the record. Today
  `ExitView_iOS.calculateExitCost` (`:285-358`) prices a forced move
  itself: no tree-tx deduplication, guessed depth 1–3, a 1.5–2.0× CPFP
  multiplier, a 10–15 % margin, three scenarios rendered as a range by
  `ExitCostEstimateCard`, and `canAfford` checked against
  `manager.onchainBalance?.totalSat` (`:115-116`). Bark's estimator at
  `bark-0.7.1` (`bark/src/exit/estimate.rs`, read at the tag 2026-10-19)
  resolves each VTXO's real exit chain, skips confirmed txs, dedupes shared
  txids, prices in-mempool packages as RBF replacements, simulates the
  serial CPFP walk against **confirmed** coins to produce `fundable`, and
  signs a real claim tx for its weight; it returns
  `exitBroadcastFeeSats` / `claimFeeSats` / `txsToBroadcast` separately.
  So this is a correctness fix as well: unconfirmed onchain funds pass our
  check and stall bark's walk. Build: (1) protocol method + `MockBarkWallet`
  stub (`estimateEmergencyExitFee(vtxoIds:feeRateSatPerVb:destination:)`,
  on `WalletProtocol` at v0.25.0, `Bark.swift:2183`); (2) map
  `EmergencyExitFeeEstimate` into the ArkéUI model — show the two legs as
  bark splits them (broadcast paid now from Savings, claim deducted later
  from the recovered amount), `fundable` replaces `canAfford`, the
  low/mid/high scenarios and min/max transaction counts go; (3) same
  fee-rate rule as `ExitProgressionService.exitFeeRateOverride`: nil on
  mainnet, capped fast rate off mainnet (with an explicit rate bark prices
  both legs at it, matching today's approximation); (4) delete the
  weight-formula comment block at the top of `ExitView_iOS.swift`.
  **Error rule DECIDED 2026-10-19:** when the estimate throws (unknown /
  already-exited / spent / non-standard VTXO, or an FFI error) the exit is
  **not** blocked — a forced move is a recovery action; show "cost could
  not be estimated" and keep Start enabled with the warning. Today the
  estimate never fails, so this is new behaviour. Preconditions verified:
  the app passes bark's BDK-backed `OnchainWallet.default` at `Wallet.open`
  (`BarkWalletFFI+WalletLifecycle.swift:262`), which the binding requires
  (callback-backed wallets error). Caveats: slow — the binding doc says it
  syncs the onchain wallet first (doc claim, not traced in the Rust);
  latency on device not measured. Review: adversarial pass (exit money
  path), then a signet forced move on device with one unconfirmed onchain
  input to see `fundable == false` behave. Sibling sites that keep their
  own rate logic and are *not* touched: `ExitProgressionService:170-173`,
  `UnilateralExitListView_iOS:239`.

### Data safety

(The metadata-import name-merge item moved to Tier 0 on 2026-10-09.)

- [ ] **Metadata import keys per-payment notes and tags by `movement_<id>`,
  which restarts from 1 after a seed import** — `MetadataImportService.apply`
  matches `transactionsByTxid` by string equality and Ark rows carry
  `"movement_\(id)"` as their txid. An old export imported after new
  payments misfiles notes onto other rows; nothing in the export survives a
  re-import for Ark payments. Needs a stable key (VTXO ids or funding txid).
  Found by the 0.26 user-outcome trace (`Migrations/Bark-0.25.0-to-0.26.0/03-impact-analysis.md` §3b).
- [ ] **Savings funds invisible after a launch-time iCloud restore** —
  `BarkWalletFFI.restoreWalletFromBackup` (and `importWalletWithBackup`'s
  restore) copy only `db.sqlite`; the BDK store under `bdk/` starts empty
  and bark's `sync` covers revealed addresses only, so onchain history past
  index 0 never appears. The import paths run `OnchainWallet.initialScan`
  since 2026-10-25 (0.26 Track A); the launch-time restore does not yet.
  Same class as feedback ask 7c. Rework ledger 2026-10-25.

- [ ] **The transaction upsert deletes duplicate `PersistentTransaction`
  rows itself** (`TransactionService+Upsert.swift`,
  `buildExistingTransactionDictionary`: `modelContext.delete` + save on a
  repeated txid, on both the full-list and the notification path). The row
  is CloudKit-mirrored and cascades to tag and contact assignments, so the
  dedupe silently drops one side's assignments; contract rule 23 reserves
  mirrored-row deletion for `WalletDataCleanupService`. Where duplicates
  come from: (a) `processSingleMovement` is not routed through
  `taskManager`, so a notification upsert can insert `movement_N` inside one
  of the full-list upsert's suspension points and the full pass, working from
  its pre-suspension snapshot, inserts `movement_N` again (PLAUSIBLE, not
  reproduced; the 2026-10-09 log shows "0 new" on every full pass); (b) two
  devices each creating the same movement row and CloudKit merging both.
  Fix shape: merge assignments onto the survivor before deleting, or route
  the notification path through the same task key and keep the first row.
  Found by the 2026-10-12 adversarial pass on the orphan-log fix; test that
  would settle (a): interleave a single-movement upsert inside a full-list
  upsert at its first `await`.
- [ ] **`SwiftDataHelper` deletes the store on any load error**
  (`SwiftDataHelper.swift:158-194`): any `SwiftDataError` (`:163-166`) or
  Cocoa codes 134110/134100/134060 (`:168-173`) delete every `*.store`,
  `-shm`, `-wal` in Application Support (`:199-235`) and rebuild. Nuance
  2026-10-09: the store is built with `cloudKitDatabase:` when enabled
  (`:120-133`), so tags, contacts and assignments come back from CloudKit;
  what cannot come back is whatever was written but not yet exported, and
  anything in a local-only container. Still a wipe on a transient error.
  Narrow the condition to confirmed migration failures, or back up the store
  files before deleting them.

- [ ] **Tag and contact lookups answer by txid, not by row** —
  `liveTagAssignments` / `liveContactAssignments` fetch
  `transaction?.txid == txid`, so two rows sharing a txid (item above, cause
  (b)) see each other's assignments and `hasTag` / `hasContact` skip
  inserting their own; the dedupe then drops the only copy. PLAUSIBLE,
  code-review 2026-10-21; key the fetch on `persistentModelID`.

### Multi-device (guiding doc: `Architecture/Multi_Device_Design.md`)

- [ ] **CloudKit Production schema was never deployed — no TestFlight build
  has ever synced a SwiftData row** (found 2026-10-26 in the CloudKit
  Console while preparing build 26: Production holds only Apple's `Users`
  type, Development has every `CD_` type; builds run from Xcode use
  Development, where types are created on first use, TestFlight and App
  Store builds use Production, which never auto-creates). Consequences:
  on TestFlight builds, secondary read-only data, tag / contact / note sync,
  `DeviceRegistration` rows, `BackupStatus` and the balance mirror never
  left the device; the iCloud KVS registration mirror, the wallet hash and
  the iCloud Drive backup are unaffected. Remedy: Christoph deploys the
  schema once (Deploy Schema Changes… in the Console) — then existing
  TestFlight installs upload their local stores on the next launch; watch
  for duplicate default tags / contacts where two of Christoph's own
  TestFlight devices merge (singleton rows already read `lastUpdated desc`).
  Process fix: `Development/Release_Train.md` Release stage now requires a
  Debug run + schema deploy after any `@Model` change. (Not the cause of the
  Tier 1 "secondary's balance" entry: there tags and activity did sync, so
  that was an Xcode build.) The Tier 2 two-device checklist needs one run
  on a TestFlight build after the deploy.

Status: S10 DECIDED (read-only + explain). S7 reduced version shipped
2026-09-24; full S7, S5 and the security-check matrix await decisions above.

- [ ] **A payment on the primary does not promptly update the secondary's
  balance**, while tags and activity do. Narrowed 2026-09-23: the re-read
  path is proven (`ReadOnlySyncedDataTests/balancePicksUpInPlaceUpdate`), so
  suspicion is on the write/export side. Candidate cause: the rapid-fire
  notification drop fixed 2026-09-24 (Done log) — not confirmed. Evidence
  needed: primary's `💾 Updated persisted Ark balance` paired with the
  secondary's `📱 Loaded Ark balance from CloudKit (spendable: N)`.
- [ ] **Active "no primary device" banner** on secondaries' main view
  (deferred 2026-08-12): `checkForNoPrimaryDevice()`
  (`DeviceRegistrationService.swift:1123`) runs only from
  `LinkedDevicesView_iOS.reload()`; run it on launch/foreground, callout
  deep-linking to `PromoteDeviceSheet`. The dead `showNoPrimaryDeviceBanner`
  NotificationCenter post (Tier 4) is the hook this would use — decide
  together. Also the recovery path for **an account with no primary can
  never get default tags/contacts** (2026-09-25; deliberately not patched by
  showing the button when no primary is visible — a not-yet-imported
  registry reads as "no primary").
  (The Tier 4 line for the dead post folded in here 2026-10-19; it is at
  `DeviceRegistrationService.swift:1108` today, posted from
  `demoteThisDevice`.)
- [ ] **S10 build**: read-only reasons for signed-out / account-changed +
  safe-exit copy (sign back in, or local-only delete). Never auto-wipe, never
  pair local files with a foreign account.
- [ ] **Fresh secondary: balance card still reads 0 during the initial
  CloudKit import** (activity list got the `.syncingFromCloud` state
  2026-09-24; the card renders a substituted zero model). Decide whether it
  gets the same treatment. Note 2026-10-13: the card's load wave triggers
  on `isRefreshing`, and a secondary's launch load is the CloudKit import,
  which never sets it, so the wave does not show here either; if the card
  gets the syncing treatment, drive the wave from the same gate. Also: the gate is balance-based (a balance batch
  landing first drops the syncing state early; a primary that never persisted
  balance rows leaves it up with no timeout) — honest upgrade is
  `NSPersistentCloudKitContainer` import events. The explicit-device-linking
  DECIDE would absorb the first-launch half; the syncing-state UI is needed
  under either ruling. (Desktop `TransactionList` half is in Parked.)
- [ ] **"Forget this device" for mirror-only ghosts** (full S7's one approved
  piece, DECIDED 2026-10-10). Service half done 2026-10-16 (`unlinkDevice`,
  `UnlinkVerdictTests`). **2026-10-25:** iPhone Linked Devices unlinks
  registry and mirror-only rows via the row's context menu, deliberately
  undiscoverable; the current device is excluded. Remaining: the delete
  screen's blocker-list surface, the discoverability call, the two-device
  ghost verify. History: `Features/Wallet_Deletion_Ghost_Hardening.md` §10.
- [ ] **Deletion-flow copywriting** (2026-09-26 session, cosmetic): strategy
  intro, blockers copy, override acknowledgement, scope-changed banner
  (`error_delete_scope_changed`) — then de/ja/zh-Hant. The amount-warning
  copy merged into the Tier 0 forfeit-warning item.
- [ ] **Devices: plan forced promotion; allow deletion / renaming of
  devices?** (Reminders) → part of the rest of full S7, designed after
  explicit device linking lands (DECIDED 2026-10-10); extend the scenario
  catalog first. (Desktop promote/demote parity is in Parked.)

### Connectivity and offline

- [ ] **The activity screen shows "no Ark connection" for the whole launch
  refresh although the server answered in 1 s** (Christoph's unattached
  log 2026-10-12, icon visible ~19–23 s): `connectionStatus.isConnected`
  is written only in Step 4 of `performRefresh`
  (`refreshProcessStates(isConnected: anyServerCallSucceeded)`), after the
  two onchain syncs above; the Activity view's 4 s grace period expires
  long before that, so the crossed-out antenna is the normal launch state
  on every device. Fix: mark connected right after Step 1 succeeds, leave
  Step 4 unchanged. Small, no device step beyond watching the icon on one
  launch. DECIDED 2026-10-12: pulled into Train 1 (visible on every launch
  for every user). Built 2026-10-12: `refreshServer()` now returns its
  outcome (the old `error != nil` check also misread a stale error from an
  earlier refresh as a Step 1 failure), Step 1 success calls
  `updateConnectionStatus(connected: true)`. Adversarial pass 2026-10-12:
  the early write is sound (single dedup'd `performRefresh`, in-memory
  observable store, all readers live); it refuted the rationale first
  written here for keeping the disconnected side at Step 4 — see the next
  item — and noted that a Step 1 slower than the 4 s grace still shows the
  icon until the server answers, which is the correct reading. No unit
  test: pinning "flag is true before Step 3 ends" needs a mid-refresh
  WalletManager harness that does not exist. Device check owed: one
  launch, icon must not appear.
- [ ] **Ark data waits for the onchain sync on every refresh** (Christoph's
  unattached export 2026-10-14 13:01, anchor-relative: Step 2 onchain BDK
  sync 2.9→5.4 s, Ark sync 5.4→5.6 s, movements saved and the new row shown
  at 6.0 s, Ark balance read at 5.8 s but published at 10.2 s when the
  onchain balance returned; wallet ready 13.3 s. On the 2026-10-12 wallet
  the same onchain sync was 11.6 s.) Two causes, both app-side: (1) the FFI
  `sync()` wrapper runs `onchainWallet.sync()` before `wallet.sync()`, and
  Step 3's movement and balance reads come after both; (2)
  `BalanceService.refreshAllBalances` awaits the Ark and onchain reads as
  one tuple, and the onchain balance call sits behind the BDK lock of the
  Step 3 history sync (4.4 s today, 6.3 s on 10-12). The Activity list is a
  SwiftData query and shows rows at the upsert save, so no list re-publish
  is needed. Verified at source: bark 0.7.1 `Wallet::sync` (local checkout
  `8adc8e7`, `bark/src/lib.rs:1951`) "will not refresh VTXOs or sync the
  onchain wallet" — mailbox, pending rounds/boards/offboards/sends, lightning
  claims, fee rates; the bark-ffi wrapper (`v0.25.0` tag,
  `src/core/wallet.rs:234`) only calls it and logs. So the Ark sync has no
  dependency on our onchain sync and can go first. Fix: split the wrapper
  into Ark and onchain sync methods (two FFI calls, mirrored as two protocol
  methods; the composed `sync()` stays for its four UI callers), Step 2
  becomes Ark sync → early movements + Ark balance read → onchain sync,
  Step 3 unchanged; the balance service publishes the Ark balance when it
  arrives and the onchain figure when that arrives, with separate error
  handling. Expected: row and Ark balance at ≈3.5 s on today's launch.
  Pull-to-refresh gains the same. Plan with labelled claims and the sibling
  sweep: `Features/Launch_Ark_First_Refresh.md`. DECIDED 2026-10-14: Tier 1,
  Train 1; the five UI `sync()` callers stay as they are; the second
  onchain sync round and the Train 2 launch-timing item are untouched.
  Built 2026-10-14 (uncommitted): `syncArk()` / `syncOnchain()` on the FFI,
  protocol, mock and manager; `performRefresh` Steps 2a/2b/2c; balance
  service publishes each side on arrival; `⏱️ Newest inserted row is X s
  old at save` log line; contract rule 7c. Adversarial pass the same day:
  no confirmed defect on the money or startup paths; two plausible items
  fixed (Step 2b uses the read-your-own-writes movements read and
  republishes the unified merge), two accepted with device looks owed
  (Ark-only interim total when the in-memory onchain figure is nil; the
  Ark balance row saved twice per refresh), citation and plan-text errors
  corrected — record in the plan's §9, ledger line written. Device check
  owed: one unattached cold launch with a mailbox payment waiting, export
  after a minute; expect `Step 2b … after launch anchor` within ~0.5 s of
  Step 2a and the row age under 1 s. First field result, export 2026-10-14
  17:53 (pull-to-refresh, 305 movements, no new payment): refresh start
  46.816, Ark sync done 46.931, Step 2b done 47.180 (movements + Ark
  balance published 0.36 s in), onchain sync 1.9 s, Step 3 done 49.47 —
  the Ark data is on screen before the onchain sync starts, as designed;
  Christoph: "pretty quick". The cold launch in the same export is not
  readable: the device store had evicted every info line before 42 s after
  the anchor (see the Tier 2 export item), so the launch-with-waiting-payment
  check is still owed and needs the export fix or Console.app first.
- [ ] **Open-time server connection fails on a cold start** (same export,
  1.4 s after the anchor): bark-ffi's `open` probes `ark_info()` once and
  logs `[OPEN] Server connection FAILED - Lightning and Ark operations will
  not work!` at warn level when it returns nothing (`src/core/wallet.rs:205`,
  `v0.25.0`); Step 1 connected 1.5 s later and everything worked. Likely the
  radio or DNS not being ready that early. Consequence: the daemon's
  open-time mailbox drain presumably fails on such launches, so launch-time
  payments arrive only through our Step 2 sync — one more reason the item
  above does its own early read rather than relying on the daemon. Nothing
  to fix in the app beyond not trusting that line; note it for the
  offline/server-down feature's "is the server reachable" signal, and
  consider telling Second the message overstates a transient failure.
- [ ] **The app can never show "disconnected" once the wallet is open**
  (CONFIRMED by the 2026-10-12 adversarial pass, pre-existing): Step 2's
  `sync()` returns `()` in bark 0.7.1 (`bark/src/lib.rs:1980`, every
  sub-sync is `if let Err … warn!`) and the FFI wrapper returns `Ok(())`
  unconditionally, so the Swift `sync()` can only throw
  `walletNotInitialized`, which `performRefresh` already guards. Hence
  `anyServerCallSucceeded` is true for every refresh that reaches Step 2,
  Step 4 always writes connected / excellent / `lastError = nil`, and with
  the server down the Activity icon hides, the Connection Info sheet says
  "Connected", its red error row is unreachable, `isArkServerReachable`
  stays true so Lightning routing stays enabled, and
  `hasEverSyncedSuccessfully` flips on the same flag. Fix shape: Step 2
  must not count as a server success (only Step 1's handshake does), and
  Step 4 then writes the disconnected verdict with Step 1's error — which
  makes a transient Step 1 failure visible until the next refresh, so
  decide the retry cadence with it. Belongs to the offline / server-down
  feature below; build it first, the rest of that feature assumes the
  signal works.
- [ ] **Offline / server-down experience** (one feature, merged from eight
  Reminders items: "stunningly designed no-connection state", server-down
  and no-internet messages with disabled functionality, server-offline tip to
  withdraw funds, disable send when offline, animate the connection icon
  while connecting, track and surface the disconnect reason, and a Settings
  disconnect button?). Corrected 2026-10-09: the last service error *is*
  shown, as a red row in the Connection Info sheet while disconnected
  (`ConnectionInfoSheet.swift:178-182`, fed via
  `refreshProcessStates(isConnected:)` → `markDisconnected(error:)`), but
  nowhere inline, not in read-only mode, and it is the generic last
  refresh-service error, not a classified reason (offline vs server down).
  Design the states (offline vs server down vs connecting), decide what each
  disables (boarding while the server is unreachable belongs on the list —
  Tier 0 "Failed boards"), classify the reason, build. **In scope since the
  2026-10-10 ruling on operator dependence:** the server-down state must
  leave unilateral exit reachable while Second's chain source is down too —
  pick a fallback Esplora per network (a third-party trust call), decide
  automatic fallback vs. a recipe, and whether an Esplora setting appears in
  Settings; exercise the exit path once against an unreachable server
  before shipping. Related dead code: connection quality is binary in
  practice (Tier 4).
- [ ] **Invoice request timeout**: unknown how long `getLightningInvoice`
  takes to fail with no connectivity (bark's timeout, unmeasured). If minutes,
  users give up before Try Again / Share Addresses Instead appear. Measure
  under 100% Loss, decide an app timeout, device-verify the failure path.
- [ ] **Invoice creation polish**: "Slow connection, still trying…" after
  ~5 s; say "offline" right away when the wallet knows; VoiceOver
  announcement for "Creating invoice".
- [ ] **A stuck Lightning receive is invisible, and cannot be cancelled or
  exited**: Second's 2026-10-06 disclosure says the follow-on denial of
  service "could degrade Lightning receives on Bark-based wallets" (server
  fixes `9111622f9`, `6fd9834ff`). Corrected 2026-10-09: **the app has no
  claim loop at all.** `LightningClaimService` has been disabled since
  commit a894888 (2026-04-10, constructor commented out at
  `WalletManager.swift:390-391`; every `lightningClaimService?.start()` is a
  no-op on nil), so its 30 s poll / `htlcs-ready` / swallowed-error code is
  dead. Receives are claimed inside bark's own `sync()`
  (`try_claim_all_lightning_receives` at tag bark-0.7.1, `lib.rs:1980,2012`),
  which only `warn!`-logs failures — the app sees neither state nor error.
  `cancelLightningReceive`, `attemptLightningReceiveExit`,
  `lightningReceiveState`, `tryClaimLightningReceive`,
  `pendingLightningReceives` exist on `BarkWalletFFI+Lightning.swift` with
  zero live callers. Decide whether to delete the service or revive it as
  the state source for the UI; then surface pending receives with their
  state on the invoice sheet and in Activity, show the last claim error when
  it repeats, and offer cancel / exit for a receive that never settles. Pair
  with "Invoice request timeout" above.

- [ ] **Relay renewal timer wipes the stored registration before the mint**
  — `RelayRegistrationService.scheduleAuthRefresh` sets `registration =
  .empty`, then calls `onNeedsRefresh`; an offline mint failure leaves
  `renewalDate` nil until a later foreground mint succeeds, so the BGTask is
  submitted undated and X-Ray shows no expiry. CONFIRMED by reading, not
  reproduced, code-review 2026-10-21; keep the old record until replaced.

### Release readiness

(2026-10-09: the clipboard pair and the package pins moved to Tier 0; CI,
the macOS suite, the helper test and `SECURITY.md` moved to Tier 4
"Tooling, CI and process"; translation debt moved to Tier 3 Localization.)

- [ ] **Distribution compliance** (Reminders): Terms of Service; Privacy
  Policy with data collection and storage; remove all "prototype" references
  — no user-facing string has one; what remains is file-header comments, the
  test bundle ids `GBKS.Ark-wallet-prototypeTests` and the App Group
  `group.GBKS.Ark-wallet-prototype` (`ArkeMobile.entitlements:22`,
  `ArkeWidgets.entitlements:7`), and renaming the App Group moves the shared
  container, so that one is a migration, not a find/replace; age-rating
  compliance. Website: revise privacy statements (via Max).
- [ ] **Native-speaker review of the de/ja first pass** (counted 2026-10-09:
  de 854 + 202 ArkéUI, ja 884 + 205 values `needs_review`; first pass
  2026-08-18): glossary ⚠️ terms first (Übertrag, Rechnung,
  Hauptgerät/Zweitgerät). Required before shipping the languages.
  `Localization/Translation_Rollout_Plan.md`.
- [ ] **Native-speaker review of the zh-Hant first pass** (900 + 205 values,
  counted 2026-10-09; first pass 2026-08-23): 聰 vs "sats", 復原片語 vs
  助記詞, 付款請求, 轉入/轉出, the 拷貝/剪貼板 vs 複製/剪貼簿 pair.
- [ ] **Phase D per-language QA**: App Language de (+30% expansion layout
  pass — badges, fixed-width buttons, alerts), ja (typography), zh-Hant
  (CJK/Latin spacing, line breaking), plus guard test + full suite.
- [ ] **BIP-353 DNSSEC validation** (full implementation): DNSSEC-validating
  library, RRSIG check, or a validating DoH resolver. Unblocks the BIP-353
  items in Tier 3 (BIP-353 vs Lightning-address logic + resolved-address
  display under Send, and the address-header proposal's override (d)). Two
  resolver defects to fix with it (read 2026-10-08, moot while the query is
  skipped): only the first character-string of the TXT RDATA is read
  (`BIP353Resolver.swift:310-315`), so records over 255 bytes truncate; and
  the lookup does one `select` + one `DNSServiceProcessResult` (`:376-388`)
  with the timeout source cancelled before processing, so a reply with
  `kDNSServiceFlagsMoreComing` set never resumes the continuation and the
  caller hangs. Keep the rule that an unverified BIP-353 answer never
  pre-empts the TLS-authenticated Lightning-address path.
- [ ] **OS `bitcoin:` URI scheme registration**: no `CFBundleURLSchemes` in
  the mobile Info.plist or the generated desktop plist, and no `onOpenURL` /
  `openURLContexts` handler anywhere, so the work is registration plus
  routing into Send. Also test the macOS Shortcuts integration (only the
  widget has App Intents).

## Tier 2 — Verification debt (shipped, never confirmed)

Cheap to clear in a dedicated device session; expensive to carry. Each item
names the fix it verifies; the write-ups are in the Done log.

### Two-device

- [ ] **Deletion + rejoin** (fix 2026-08-19, `Features/Wallet_Deletion_And_Rejoin.md`
  definition of done): local-only delete keeps the seed everywhere (phrase
  still displays on the other device); deleted device shows the rejoin
  screen and relaunch does NOT resurrect the wallet; Rejoin restores from the
  preserved iCloud backup; create-wallet refused while the account has a
  wallet. Gate for calling the seed-deletion fix done. Add: delete on a
  freshly joined secondary while CloudKit is still importing → must say
  "Delete from This Device" (2026-09-21 KVS-mirror fix).
- [ ] **Deletion-strategy fix** (2026-08-12): delete on the primary →
  secondary's Linked Devices shows "no active wallet" + "Make This Device
  Primary" once CloudKit syncs → promotion restores from the iCloud backup.
- [ ] **Second iPhone read-only data** (fix 2026-09-23): with the app running,
  move funds on the primary → secondary's balance updates without relaunch;
  receive screen shows an address; pull-to-refresh leaves no error banner.
  Confirm in the log that `Loaded Ark balance from CloudKit (spendable: …)`
  follows a `[CloudKit] Remote change detected` round.
- [ ] **Seeding scenarios** (import-gated seeding, contract rule 26):
  (1) reinstalled primary → exactly 9 tags + 1 faucet + customs, gate-wait
  log line — this is also the check for the Reminders report "two Faucetto
  Signetto contacts" (merged from Tier 3 2026-10-09; insert-time store dedup
  is the gate's timeout backstop, confirm it covers rejoin too);
  (2) fresh account → seeds immediately, no 90 s wait;
  (3) reinstalled secondary → never seeds; (4) iCloud signed out + import →
  seeds after ~90 s timeout (`log show --info --debug`).
- [ ] **SwiftData invalidation on the second iPhone** (fix 2026-09-23/25):
  launch during the initial CloudKit import (the crash repro), assign/unassign
  a tag from the detail and confirm the list label updates (`dataVersion`
  moved from row to list), check a tag-filtered and a contact-filtered list.
- [ ] **Self-unlink → relaunch** run to settle the `checkReadOnlyMode()`
  finding in Tier 0 before choosing its fix.

### Exits and refresh

- [ ] **Exit blocked state**: on-device verify + WalletManager tests
  (`Features/Exit_Blocked_State.md`, phases 1–3 done). Also closes the
  Reminders report "error when not enough onchain to progress exit".
- [ ] **Exit completion issues**: on-device verify with a wallet that has
  both claimed and cancelled exits (`Features/Exit_Completion_Issues.md`).
  Also closes "exit fee calculation includes pending onchain / fees are off"
  and "completed force move still reads 'Force moving'" (display helpers now
  have `transaction_force_moved_amount`).
- [ ] **Refresh dedup on-device signet verification** (doc §6): parsing gate
  first — log `subsystemName`/`subsystemKind`/`category` right after
  scheduling (the **category mapping** is the unverified half of Phase 1,
  marked `[~]`: `.refresh` requires `subsystemName == "bark.round"` and
  `subsystemKind == "refresh"`, and a miss silently empties the signal);
  then card flips to "Refreshing", no duplicate schedule from hourly or
  foreground check, "Already refreshing" on a raced tap. Also closes the
  Reminders report "active refresh in Activity while card and balance still
  say 'Refresh now'".
- [ ] **Refresh reminder inside the free period** (bcdb0fa): confirm no
  reminder fires inside the fee-free window.
- [ ] **Pre-open refresh skip path** (2026-10-01): soak through normal use —
  grep exported logs for `⏭️ [Refresh] Skipped` (first real exercise; lines
  before it name the trigger, mailbox push suspected) and any
  `walletNotInitialized`. Owed too: `TransactionService.error` is never
  cleared on success (`clearError()` at `:206` has zero callers) — drop or
  clear it. (The desktop banner half is in Parked.)

### Background and relay

- [ ] **0xdead10cc kills**: watch Organizer for build 25+ signatures at
  `getWalletDirectory`/`registerCurrentDevice` and the new `⏳ Background
  assertion '…' expired` / `ℹ️ … not granted` lines. Absence over a week of
  wakes is the only confirmation.
- [ ] **Auth wake push from field data** (2026-09-17/21, acceptance criteria
  in `Features/Background_Execution.md`): X-Ray journal rows "Auth wake push ·
  refreshed" and "Stale mailbox unregistered · success · wake_push"; relay
  side `trigger: "wake_push"` under `auth_refresh.refreshes_after_wake` and
  DELETE `/v1/register` `removed: 1` shortly after a wake. DELETE carries no
  trigger; orphans past their 7-wake budget never wake again — "no signal" ≠
  broken.
- [ ] **Bark 0.25 day-15 renewal**: journal when it happens (~2026-10-11), or
  sooner on the simulator by backdating `com.arke.relay.lastRegisteredAt` /
  `com.arke.relay.authExpiresAt` via `simctl … defaults write`. **Relay-side
  confirmation** after a week: registrations per trigger drop to ~1 per
  device per 15 days; pre-expiry 2h/1h wakes stop for updated devices.
- [ ] **Background activity journal leftovers**: simulated-wake journal
  verify (plan Phase 1 item 4), on-device look at the relay cross-check row,
  events-list bottom row can sit under the floating tab pill.
- [ ] **Verify the rest without the ATS exception** (PR #8): force a relay
  register call (not a still-valid registration) and the signet faucet over
  HTTPS.

### Diagnostics and notification path

- [ ] **Debug export can come back empty or miss the first seconds**
  (2026-10-14, iPhone 17 on iOS 27.0.1, build 24): an export taken 18 s
  after a cold launch had `Entries: 0`; one taken 51 s after the next launch
  had 199 entries, but its first info-level lines start 5.4 s after the
  anchor while error-level lines are present from 1.4 s, so the Step 1 and
  Step 2 markers and `refresh() CALLED` are missing. The exporter itself is
  sound: a Swift Testing probe on the iPhone 17 Pro (26.5) and iPhone 17
  (27.0) simulators saw its own info/notice/error lines (debug is never
  persisted). Third export 17:53 the same day refutes the lag reading: it
  was taken 63 s after the anchor, contains info lines from 42 s after the
  anchor onwards (the pull-to-refresh, 17 s before the export) and none
  from the launch itself, while error and notice lines from 1.4 s on are
  present. PLAUSIBLE, revised: on device, info-level entries live in a
  bounded per-process memory buffer and the oldest are evicted as the
  buffer fills; the launch is the noisiest window (the debug-level dump of
  every movement, one "Establishing links" line per movement, the VTXO
  list), so the launch is exactly what gets evicted. The 12:16 export with
  zero entries fits a buffer that had just turned over. Until fixed:
  launch-step timings cannot be read from exports at all; use Console.app
  with the phone on a cable. Fix shape: mirror the app's own `Logger` lines
  into an in-process ring buffer the export reads first, with OSLogStore
  for bark's bridged lines; and cut the launch log volume (the full
  movements JSON at debug level, per-movement linking lines). The export is
  the support-case path (2026-10-11), so this gates every unattached
  measurement. CONFIRMED by the `OSLogType` docs (read 2026-10-14): "the
  system stores info-level messages in memory buffers and, without a
  configuration change, purges the oldest messages as those buffers fill
  up", while default/notice and above are written to the data store. Fix
  built 2026-10-14 (DECIDED, uncommitted), the documented route rather
  than a mirror: the launch skeleton now logs at notice — `Launch
  verdict`, `Existing wallet opened`, `Wallet opened`, `refresh() CALLED`,
  every `[Refresh] Step` marker incl. `Step 2b … after launch anchor`,
  `Wallet synced`, `Onchain wallet synced`, `Retrieved N movements`,
  `Successfully saved`, `Newest inserted row`, `Balance retrieved`,
  `Onchain balance retrieved`, `Onchain history stabilized`, `DataVersion
  incremented` (20 lines, no private interpolations). The export header
  now lists entries per level and states that info is best-effort. Detail
  lines stay at info and may still be missing from the start of a session;
  the ring-buffer mirror stays here as the follow-up if that proves
  limiting. Device check owed: one export after a cold launch must show the
  `Step 1`…`Step 4` markers.
- [ ] **Notification listener starts after the launch refresh, so
  launch-time movements never arrive through it** (attached run 2026-10-14:
  `Starting notification listener` 9.8 s after `refresh()` was called, after
  Step 4 and the service starts in `initializePrimaryMode`). Movements that
  bark writes during the open-time daemon sync or during Step 2 are only
  ever picked up by Step 3's full read. Starting the listener right after
  the open would need bark's `NotificationHolder` to replay movements
  created before the subscriber attached — not documented in the bindings,
  and the daemon's drain finishes 0.2 s after the open, so even an early
  start races it. Verify replay semantics at the bindings tag before
  building anything; the Tier 1 Ark-first item above makes this
  non-urgent.

### Other on-device looks

- [ ] **Fiat**: X-Ray "Exchange Rates" section on a wallet install (currency
  count, file time, last checked, last result — the simulator has no wallet);
  German separator on the keypad key and in the partial display.
- [ ] **Metadata import round-trip**: export on one device → import on a
  fresh wallet (`Features/Metadata_Export_Import.md`); then the faucet
  avatar re-encode drops the export to ~KB.
- [ ] **Startup routing retests** (Reminders): delete-and-create landing on
  the delete-wallet screen instead of the wallet; importing right after
  delete seeming to freeze the app. Both predate the startup hardening.
- [ ] **Notification permission on first received payment** when never
  asked: `requestAuthorization` runs from the invoice sheet, refresh and exit
  services; confirm the receive-without-invoice path asks too.
- [ ] **Exit local notifications still working?** → needs the X-Ray local
  notification listing (Tier 3, Refresh).

## Tier 3 — Polish by area

One pass per area when that screen is touched. Mostly from the 2026-10-07
Reminders merge; wording kept so the two can be matched.
2026-10-19 sweep: eight question-shaped lines moved to "Decisions needed",
five ideas to Parked → Future ideas, one question answered and closed (Done
log).

### Send

- [ ] **Number pad sometimes has no Done button** (also "amount input
  keyboard done button"). Related: tap-outside keyboard dismissal added to
  the Boarding/Offboarding forms 2026-08-21 as fallback for the flaky toolbar
  Done; `ManualSendView`, `QuickPaymentView`, `ContactPaymentView` still rely
  on the toolbar alone — denser layouts, apply with a closer look.
- [ ] **Fees not correctly calculated in the Zinqq multi-address selector
  sheet**; add a large-address review in the multi-address picker.
- [ ] **Review logic for telling BIP-353 and Lightning addresses apart**,
  in Send and when adding a contact address (merged with the Contacts
  fragment 2026-10-09); a contact with a resolved BIP-353 shows only the
  resolved address in the send view; actually resolve and test — all
  DNSSEC-blocked (Tier 1).
- [ ] **LNURL comment input and metadata** (short/long text, image) —
  `Features/LNURL_Pay.md` "not implemented"; `commentAllowed` is parsed and
  ignored (`comment: nil` passed to `payLnurl`).
- [ ] **Toggle icons blink again; no-contacts icon should be white and more
  distinct; animated highlight when parsing the clipboard** (the cropped
  character videos moved to Parked → Themes video sizing 2026-10-09).
- [ ] **Input field type detection – test thoroughly**.
- [ ] **BOLT-11 network prefix table is wrong**
  (`LightningInvoiceParser.parseNetwork`): `lnbcrt` (regtest) matches the
  `lnbc` check first and reads as mainnet; the parser tests `lnrt` for
  regtest, which no invoice uses; signet's `lntbs` matches `lntb` and reads
  as testnet; unknown prefixes default to mainnet. Check against wherever
  Lightning network compatibility is enforced before changing — signet is
  the daily network.
- [ ] **Send-metadata tidy-ups**: `SendNoteEditorSheet.maxCharacters = 500`
  declared but never enforced while `PersistentTransaction.notes` says 1000 —
  pick one and enforce it; dead `SendMetadataSection.iconView(systemName:isFilled:)`,
  `SendModalContentView.stateMessage` only referenced from a commented block
  and its `.error` video branch still says "Phase 3b will add…";
  `PendingPaymentMetadata.matchedTxid` comment says "for debugging" but it is
  load-bearing (priority-0 matching) — fix the comment.

- [ ] **Bitcoin-field zero keystroke writes "0" and drops Max** —
  `SendViewModel.writeAmount` stores a parsed 0 as `"0"` where the fiat path
  stores nil, and every write clears `isSendingMax`; a leading "0" typed after
  Max flips validation mid-entry. PLAUSIBLE, partly by design, code-review
  2026-10-21: decide whether zero clears the amount like the fiat path.
- [ ] **Empty wallet never shows the over-budget signal** —
  `SendAmountInput.exceedsBalance` is false whenever `maxSpendableAmount ==
  0` and overrides the component's own check, so 5,000 sats typed into a
  zero-balance wallet stays grey. CONFIRMED by reading, code-review
  2026-10-21; distinguish "balance unknown" from "balance zero".

### Receive

- [ ] **Lightning request page: every control reads as "Lightning invoice
  form" to VoiceOver** (simulator hierarchy, 2026-10-19): the container
  `.accessibilityLabel` on `lightningModeView` in `ReceiveView_iOS.swift`
  replaces the children's labels — amount, "Add note" and the keypad all
  announce the same string. Drop the container label, or make the container
  an element with its children still exposed.
- [ ] **Test scanning from a laptop camera; ensure amount and memo input
  interactions work properly**.
- [ ] **QR network indicators not showing?**

- [ ] **QR brightness: `boost()` during a restore ramp saves the mid-ramp
  level** — `ScreenBrightnessBooster.boost` reads `screen.brightness` while a
  `restore()` ramp is still stepping (scene phase inactive → active within the
  ramp), so the final restore lands near full. CONFIRMED by reading,
  code-review 2026-10-21; remember the ramp target as the user level.

### Activity, transaction details, tags

- [ ] **Activity rows are dated by when the wallet processed the movement,
  not when it happened** (Christoph, 2026-10-19; Train 1 cosmetic pass).
  Related, not a fix: bark 0.8.0 (#2610, feedback ask 11) stops finished
  exits from re-stamping `completed_at` on every sync, which removes one
  cause of old cancelled exits floating to the top; the date-freeze
  workaround in the upsert can go once a build-26 export shows no churn.
  Traced: the row date is `parseDate(movement.completedAt ?? movement.createdAt)`
  (`TransactionService+Parsing.swift:320`), and bark's `MovementTimestamp`
  (`bark/src/movement/mod.rs:326-334`) has only `created_at`, `updated_at`,
  `completed_at`, all stamped with the wallet's local clock when *it* acted.
  For a sent payment that is the real time. For anything discovered at a
  sync — a received Ark payment claimed from the mailbox, a board or an
  onchain receive found by the chain scan, a round refresh — it is the
  sync time, which on a phone that was closed for a day is a day late.
  Bark offers no counterparty time, so the fix is per source: (a) onchain
  rows already have the block time (`OnchainTransactionModel.confirmationTime.timestamp`)
  and the movement ↔ onchain link (`Movement_Onchain_Linking.md`) — show
  the block time when linked; (b) received Ark payments that arrive by
  push are processed within seconds (`processSingleMovement`), so they are
  already right; only the catch-up sync case is late, and for it the
  honest display is bark's time — or an "around" prefix / "received by"
  wording, ruling needed; (c) the upsert must not re-date an existing row
  when a later refresh reports a later `completed_at` for the same
  movement (`TransactionUpsertDateFreezeTests` pins the cancelled case
  only; check whether a re-sync bumps dates of settled rows, which would be
  the "when the app loaded it" effect on *every* refresh). Start with (c):
  if settled rows are re-dated on refresh, that is the bug; (a) is the
  improvement; (b) needs a ruling.
  **(c) executed 2026-10-19 — no re-dating.** Read at bark tag 0.7.1 (the
  deployed library): `movement/manager.rs` sets `completed_at` only in
  `new_finished_movement` / `finish_movement*`; `movement/update.rs:217`
  (`MovementUpdate::apply_to`) moves `updated_at` only; `exit/mod.rs:788-797`
  re-finishes an exit movement only on a fresh state change (the §2a bump
  on every tip advance is gone at this tag, the app-side freeze stays as
  belt and braces). The upsert rewrites `date` only when bark's value
  differs, and `updated_at` never feeds it — pinned by
  `settledDateIgnoresUpdatedAt` in `TransactionUpsertDateFreezeTests` (4/4
  green). **(a) is largely moot:** onchain rows already take the block time
  (`UnifiedTransactionService.swift:398-404`), and the movements linked to
  them — boards, offboards, exits — are this wallet's own actions, stamped
  when they happened. **(b) — the real time exists, bark drops it**
  (traced 2026-10-19, Christoph: "is there really no date on when the
  payment actually happened?"). Incoming payments reach the phone through
  the server mailbox (`mailbox_server.proto`: Ark payments, incoming
  Lightning payments, round completions). Every mailbox message carries a
  `checkpoint`, and the server builds it from its clock at deposit time
  (`V21__blinded_mailbox.sql`: upper 44 bits = milliseconds since epoch,
  lower 20 a same-millisecond counter). So the server-side arrival time of
  each received payment is on the wire. The bark client keeps only the
  highest checkpoint as its read cursor (`store_mailbox_checkpoint(u64)`)
  and stamps the movement with the phone's clock when it processes the
  message — that is the "when the app loaded it" date. Nothing in the
  bindings exposes the per-message time, so there is no app-side fix.
  DECIDED 2026-10-19 (Christoph): filed as an upstream ask —
  `Bark_Bindings_Feedback.md` §1.10 / ask 20: stamp mailbox-delivered
  movements with the checkpoint's time (or expose it as a `received_at`
  on the movement). On adoption, the parser uses it as the row date for
  received rows and keeps `completed_at` for everything the wallet did
  itself. Until then the row date is honest about one thing only: when
  this phone learned of the payment. Stays open as the adoption item,
  blocked on upstream.
- [ ] **Tag amounts — do they include fees, should they? Balance tag must
  include onchain child-tx fees**.
- [ ] **Transaction details**: show the invoice description when present
  (Opago order numbers); description for refreshes; onchain send-to /
  received-from addresses; onchain txid with explorer link; general
  clean-up; remove blue from the status colours?
- [ ] **`TransactionCardStackView_iOS` holds `[PersistentTransaction]`** in
  `@State` for the overlay's lifetime; if an import deletes the movement row
  while the overlay is open, reading its own properties still traps. Pass
  txids from the list and re-fetch the window; re-verify the entrance/drag
  choreography on device.

- [ ] **A skipped refresh still ends the loading skeleton** —
  `WalletManager.performRefresh` sets `hasLoadedOnce` in a `defer` placed
  above the "database not open yet" and read-only skips, so a mailbox push
  during launch flips Activity to its empty state before the first real
  sync. CONFIRMED by reading, code-review 2026-10-21; set it after a
  completed pass.

### Balance, board / offboard

- [ ] **VoiceOver hears nothing about the running launch load** (filed
  2026-10-13 from the load-wave item): the activity screen's balance
  element has a label and value but no "updating" state while
  `isRefreshingWithData` is true. One string appended to
  `balanceAccessibilityValue` in `ActivityView_iOS.swift`; read the flag
  directly, the 1 s arming guard is a flash guard and does not apply to a
  value read on focus.
- [ ] **Onboard modal**: ~~minimum value only shows after X-Ray was
  visited~~ (done 2026-10-19 — root cause: `CacheManager.arkInfo` expires
  after five minutes and is not observable, so the modal read an empty
  cache and showed "Loading minimum amount…" until a refresh or an X-Ray
  visit refilled it; `BoardingModalView` now calls
  `WalletManager.cacheArkInfoIfNeeded()` on open and holds the minimum in
  view state. Not screenshotted: the modal is gated on a savings balance
  the simulator wallet lacks — device check owed, together with the image
  line below);
  add fee info; success message with duration; test the error state.
  **Offboard modal**: add fee info; add data to success (claim required?);
  test the error state. **Boarding**: calculate and display the network fee;
  adjust the amount input to the unit setting; offboard takes a long time.
- [ ] **Fee summary — move to savings showed up as a send**.
- [ ] **Full bitcoin format — add satcomma spacing** (nothing in
  `BitcoinFormatter` does it).

### Refresh

- [ ] **X-Ray: list local notifications** (requested 2026-09-27): show
  `pendingNotificationRequests()` (id, title, category, `nextTriggerDate`)
  and `deliveredNotifications()` next to the Background Activity rows, plus
  the scheduler's inputs (current height, target height, blocks remaining,
  seconds/block). A full history needs a `localNotificationScheduled`
  journal kind plus journaling in the `willPresent`/`didReceive` hooks.
- [ ] **Make the overlay better reflect the current state**.
- [ ] **`RefreshModalFormView` — description text is cut off even when the
  modal is fully expanded**.
- [ ] **Surface expiry sweeps instead of silently showing less money** — on
  import VTXOs come back as bare `Spent` with no reason. Blocked on upstream
  spent-reason (`sweptAtExpiry`, feedback §1.9 / ask 17); once available,
  write an explicit "expired" history entry. The pre-sweep half is the
- [ ] **Stale "Time to Refresh" reminder after an unusable-inputs rejection**
  — the auto check in `VTXORefreshService` returns inside the scheduling
  `catch`, skipping `scheduleNextRefreshNotification()`, so a reminder for
  VTXOs now held back still fires. CONFIRMED by reading, code-review
  2026-10-21; reschedule before returning.
- [ ] **Rejection back-off not persisted while the service is stopped** —
  `persistRejectionBackoff` returns on `guard isRunning`, but
  `refreshManually` can record a verdict after demotion's `stop()` with the
  object still alive, so the next launch re-submits the rejected ids.
  PLAUSIBLE, code-review 2026-10-21; gate on "wallet being deleted", not on
  running.

  Tier 0 divergence cluster.

### Exits

(The `estimateEmergencyExitFee` pre-flight line moved to Tier 1 "Exits" on
2026-10-19 as a replacement of the app-side cost estimate, DECIDED.)

- [ ] **Adopt `cancelExit` from bindings v0.18.0**: the escape hatch for
  fee-blocked exits. Prerequisites: Live Activity `ExitState` lacks terminal
  `canceled`/`vtxoAlreadySpent`; verify the date-freeze workaround covers
  explicit cancels (feedback §1.4); purge question answered at bark 0.8.0
  (2026-10-25): `cancel_exit` keeps the cancelled row on disk "for
  auditing", `listFinishedExits` enumerates it, and `getExitVtxos()` drops
  finished exits only at load, so a cancelled exit stays listed until the
  next launch — `ExitVtxo.isCancelled` now treats `.canceled` and
  `.vtxoSwept` as terminal. Notes in `Bark_Bindings_Unadopted_API.md`
  §1.1. Folds in the Reminders question "review exit cancellation — only
  until the first transaction is committed?".
- [ ] **Exit UX pass** (Reminders): completed exit did not show the status
  bar with details (should it?); switch up the notification when done; fix
  progress state in label; remove UI of the manual claim step; review the
  experience from first interaction; more testing.
- [ ] **Report upstream to bark devs** (network-verified on the stuck signet
  wallet): exit package txs don't exist on the network despite bark reporting
  broadcast; round-replacement VTXO fails signature validation. Both are
  written up in `Bark_Bindings_Feedback.md` §1.6 — tick once Christoph
  confirms that doc reached Second.

### Settings, devices, deletion

- [ ] **Mirror-only blocker copy reads as a fact during a sync gap**
  (Christoph, 2026-10-19 device check, PROPOSED): right after B's local
  deletion, A's delete screen said "Another device on this iCloud account
  is still registered to the wallet, though its details haven't reached
  this device yet" (`DeleteWalletSettingView.swift:331`; same shape in
  `UnsyncedDeviceRow.swift:55, 61`) for about ten seconds, because the
  CloudKit row deletion reached A before the KVS mirror removal did. The
  copy asserts a device exists when the honest state is "the two stores
  disagree right now". Proposal: on a mirror-only-only report, show a
  neutral "Syncing devices…" row and re-run the assessment after a few
  seconds; name the unrecognized device only if the entry survives the
  re-check. The same mirror-only state is also the permanent ghost
  (2026-09-23), so the neutral copy must not stay forever — the re-check
  is what separates the two. Needs a ruling on the wording and the delay.
- [ ] **An iOS build run on the Mac registers as "iPad8,6"** (Christoph's
  Devices list, 2026-10-14): Xcode's "My Mac (Designed for iPad)" run of
  2026-10-01 22:07 (the `.XCInstall/ArkeMobile.app/WrappedBundle` wrapper in
  DerivedData) shares the account's iCloud Keychain, found the seed and
  registered through the detection path (`MainView_iOS.swift:62`) as a
  secondary. iOS apps on Apple silicon report `utsname.machine` as
  `iPad8,6`, and `getDeviceModelName`'s map has no entry for it, so the row
  shows the raw identifier with the phone icon. Label it honestly
  (`ProcessInfo.processInfo.isiOSAppOnMac` → "Mac (iPhone app)", Mac icon)
  and add the identifier to the map. Such a row counts as a live device for
  the deletion strategy and the forfeit-warning copy until it is unlinked.
- [ ] **Delete wallet with an exit in flight shows no funds warning** — also
  no warning for an open Lightning invoice (its preimage lives only in the
  deleted database; a paid-in HTLC times out to the payer) or a pending
  board (not recoverable by the app); the 0.26 user procedure tells users
  to wait these out (`Migrations/Bark-0.25.0-to-0.26.0/03-impact-analysis.md`
  §3b, 2026-10-25) (from
  the 2026-10-13 forfeit-warning review, PLAUSIBLE; Tier 3 confirmed by
  Christoph 2026-10-14, no field case): the old generic box
  fired on the grand total, which included `pendingExitSat`; the forfeit box
  reads bark's unspent list (Spendable + Locked) and exits are not in it.
  Whether a started, unclaimed exit is recoverable after deletion is
  unverified — exit progression and the claim need the bark db, and
  `recovery.rs:285` stores recovered VTXOs as `Exited` without the exit
  state. Settle that first (bark `exit/` claim prerequisites), then either a
  third copy ("an exit is in progress; deleting stops it on this device") or
  nothing. The manual-backup reminder on the same screen already names the
  wallet state file.
- [ ] **Savings deposits don't show up automatically** — note in the
  notifications explainer until Background Execution Phase 2 (Tier 4) lands.
- [ ] **Network mismatch on import**: importing a signet wallet in the
  mainnet flow shows an ugly overlay. Optional self-heal: bark's db knows
  its own network — on a mismatch open failure, derive the config from the
  db instead of the stored setting (needs a bindings check for reading the
  db network without a chain source); the overlay copy is the fallback when
  self-heal is not possible (two lines merged 2026-10-09).

### Contacts

- [ ] **Native-contact linking, remaining pieces**: link an existing contact;
  display the link and offer to remove it; test unlinking and deleting a
  linked native contact; explore saving BIP-21s to native contacts. (Import,
  refresh and unlink-on-delete exist in `ContactService+NativeIntegration`.)
- [ ] **Contact permission setting — test**.
- [ ] **Clipboard — offer to add or assign to a contact; copy functionality
  fixes in various places; don't always pop the clipboard modal on first
  view**.
- [ ] **Distinguish testnet and signet addresses; more subtle network display
  when adding an address** (see also the BOLT-11 prefix table under Send;
  the BIP-353 / Lightning-address half merged into the Send line 2026-10-09).
- [ ] **Contact edits don't show up right away**: adding an address doesn't
  update the persistent model (tapping send on it says it cannot be found on
  the contact); after adding a contact it doesn't instantly show in the
  transaction list; refresh-from-native updates the header in the sidebar
  (two lines merged 2026-10-09 — likely the cached-relationship rule: read
  with a fetch in the same main-actor pass).
- [ ] **Assign-contact modal design improvements; "x" should close, not
  unset**.
- [ ] **Move the deletion-logic note into the address-deletion confirmation
  modal**.

### First use

- [ ] **Allow swiping up through the videos; intro video play-button
  flicker?; TL;DR screen when skipping the video?**
- [ ] **Internal flag for "user has backed up the mnemonic" + backup reminder
  once there are funds** (no such flag exists; `BackupStatus.reminderMessage`
  and `shouldShowBackupReminder` exist unwired, see Tier 4 process state).
- [ ] **Import — autocomplete for seed words** (`EnglishWordListProvider`).
- [ ] **Import — validate the phrase before handing it to bark** (moved
  down from Tier 0 2026-10-09 after execution: `MnemonicChecksumTests`
  shows bark's `OnchainWallet.default` throws `invalid mnemonic: the
  mnemonic has an invalid checksum` / `mnemonic contains an unknown word`
  before any network I/O, so a typo never opens a different wallet). The
  live pre-check `SecurityService.isValidBIP39` (`:864-873`) tests word count
  only; the two validators with the checksum TODO
  (`BarkWalletFFI+Mnemonic.swift:47-70`, `BIP39Usage.swift:52-73`) have no
  callers. Fix: call the binding's `validateMnemonic(mnemonic:)` (returns
  `false` for both cases, verified) in the pre-check and show "phrase has a
  typo" before the import UI starts; delete the two dead validators. Note
  `importWalletWithBackup` writes the seed to the keychain before bark sees
  it (`WalletManager+Wallet.swift:102-104`, rollback follows) — the
  pre-check also closes that window. Note (2026-10-10): the import path
  does run bark's recovery scan (single `Wallet.open` with `skipRecovery:
  false`, `openImportedWallet`), but with the 0.7.1 reader — recovery of a
  diverged wallet depends on the Tier 4 bindings bump.

### X-Ray and Tilt

- [ ] **Options view / `VTXODeveloperActionsView` don't refresh when another
  VTXO is selected** — key the view on the VTXO id.
- [ ] **Tilt share — pay is not working; explore Mesh user detection instead
  of NearbyDevices.** Definition of done now includes the deferred half of
  the nearby-payload ruling (DECIDED 2026-10-10): gate receiving on the
  same distance check as sending, accept one payload per exchange, ignore
  invitations outside an active exchange.
- [ ] **X-Ray VTXO bar reads its inflect markup aloud** — `VTXOGraph`
  `accessibilityText` builds the label with `String(localized:)` and a
  `^[… days](inflect: true)` span, which `Text(String)` never inflects; the
  simulator hierarchy showed the raw `^[1 days](inflect: true)` (seen
  2026-10-21, signet import session). Use a plural-variation catalog key.
- [ ] **X-Ray header says "1 VTXOs"** — `VTXOListView_iOS` and the Shared
  `VTXOListView` interpolate `"\(vtxos.count) VTXOs • …"` unlocalized, so
  no plural and no translation (seen 2026-10-21). One catalog key with a
  plural variation, both copies.

### Localization

- [ ] **Import screen: `backup_file_section_description` changed meaning on
  2026-10-26** (the backup file is now "recommended if you have one" and
  restores payment history and in-progress activity, funds either way);
  the de / ja / zh-Hant values still say "optional". The button's second
  line (`backup_file_not_selected`) was removed. Retranslate through
  `Scripts/apply_translations.py` with the next batch.
- [ ] **Translation debt — 128 user-facing keys have no de or ja value,
  112 no zh-Hant** (moved down from Tier 1 and recounted 2026-10-09 over
  `Shared/Localizable.xcstrings`, 1,029 keys, 17 `shouldTranslate=false`
  excluded; plus one ArkéUI key, `accessibility_decimal_separator`, per
  language). Groups: deletion strings (`settings_delete_warning_*`,
  `settings_delete_override*`, `button_delete_*_anyway`,
  `error_delete_scope_changed`), `metadata_*` export/import, ~28 X-Ray
  `data_bg_*` plus `data_background_*` / `action_*_background_events`, the 5
  `ManualRefreshOutcome` keys (now extracted, `en` only), `rejoin_*` and
  `error_wallet_already_on_account`, `linked_devices_unsynced_*` +
  `settings_unsynced_devices`, `transaction_list_syncing_*`,
  `data_fiat_rates*`, `settings_currency*`, `fiat_approx*`, the fiat-entry
  `receive_*` / `send_switch_to_*` strings, and ~13 format-only keys
  (`%@ UTC`, `%llu sat/vB`, `Block %u`, `Round %u`, `Invoice #%lld`, …). All
  render English `defaultValue` (no raw keys) — cosmetic, the whole Phase 3
  debt in one number. `apply_translations.py` then `translation_lint.py`
  (the lint checks empty values and format specifiers, not missing
  languages, so it is not the counter).

## Tier 4 — Tech debt and deferred by design

(2026-10-19 sweep: the daemon auto-start duplicate merged into "Explicit
daemon start is redundant" below; the `_isPrimary` clearer folded into the
Tier 0 `checkReadOnlyMode()` item; the dead banner-post line folded into the
Tier 1 banner item; the dead device-registry entry rewritten to its two
survivors.)

### Concurrency and the FFI boundary

- [ ] **Export noise from the 2026-10-19 mainnet device check** (not
  caused by the ceiling; filed so the next reader does not chase them):
  eleven `client connection error: hyper::Error(IncompleteMessage)` lines
  from bark's Esplora client reusing an idle keep-alive connection to
  `mempool.second.tech` after a pause — the sync that followed succeeded,
  so it is a retry that logs at error level; and one
  `⚠️ [UnifiedTxService] Duplicate txid found: onchain_0bd6f9d9…` for the
  working onchain/bark dedupe of the same receive. Candidates: report the
  hyper line in `Bark_Bindings_Feedback.md` if it recurs in field exports;
  drop the dedupe warning to debug level.
- [ ] **Fee-rate cache survives a network-config switch** (filed
  2026-10-19 from the mainnet-ceiling adversarial pass, F4):
  `feeRateService` is created once in `WalletManager` and never reset, and
  `currentRates(maxAge:)` serves the cache for up to 300 s, so after a
  switch the other network's rates (bounded by *its* cap) can be served
  for up to five minutes — a signet exit override could briefly see up to
  10,000 sat/vB, mainnet can only be tightened (≤ 50). Not a crash. Fix:
  clear `feeRates` / `lastUpdated` in the config-update path (or key the
  cache by Esplora URL). The within-fetch half (URL read before the
  request, cap after) was fixed the same day. Not executed: whether any
  fee fetch can run before the pre-open network reconcile (no caller found).
- [ ] **`TaskDeduplicationManager.cancel`/`cancelAll` have never worked**:
  both cast to `Task<Any, Error>` / `Task<Any, Never>` and `Task` is
  invariant, so `cancel(key:)` is a no-op and `cancelAll()` clears the
  registry with operations in flight (next `execute` → concurrent duplicate).
  Low impact today (only `ServiceContainer.cleanup()` at teardown). Fix:
  type-erased cancel closures per task. Deferred again 2026-09-24: making
  `cancelAll` real starts cancelling fund-adjacent operations never written
  to be cancellation-safe — needs a per-key review. `generations` also never
  cleared (bounded, harmless).
- [ ] **Surface typed errors across the bark FFI boundary**: every
  `Bark.Error` collapses into `BarkWalletFFIError.configurationError(_:)`, so
  callers string-match (`isUnusableInputsRejection`). One case per recoverable
  variant, starting with `unusable_inputs`. The 2026-10-09 field log showed
  the cost: the match fired on an expired-VTXO rejection and the message
  itself never reached the log (Tier 0 cluster). Note the server's
  `unusable_inputs` carries ids only, not reasons — the typed case still
  needs app-side context (pending rounds, expiry) to classify.
- [ ] **`refreshTransactionsAfterWrite()` costs an extra `getMovements()`
  under contention** (drains the in-flight fetch and runs its own). Accepted;
  cheaper design: write sequence + join when the in-flight fetch observed it.
- [ ] **Refresh dedup deferred notes** (doc §3/§5): near-expiry valve is
  auto-path-only and hardcodes 144 to mirror bark's
  `vtxo_refresh_expiry_threshold` (FFI config passes `nil`) — threading the
  live value into `RefreshExclusion` needs a cached `arkConfig` on
  `WalletManager` (merged 2026-10-09); `findVTXOsForAutoRefresh` embedded and
  untested; `vtxoIdsBeingRefreshed()` has no test seam; modal list/amount can
  diverge from what the service refreshes (valve + mid-flight changes) —
  revisit after the device run.

### Device registry cleanup

- [ ] **Deletion clears the fiat currency preference, keeps the rates
  cache** (DECIDED 2026-10-10): add `UserDefaults.fiatCurrencyKey` to the
  preference wipe in `WalletDataCleanupService` and both keys to
  `SharedStateWipeCoverage` with their scope (preference wiped, cache kept);
  the coverage test pins it.

- [ ] **Ghost-device hardening (2)–(4)**: re-run the device assessment and
  refresh Linked Devices on `NSUbiquitousKeyValueStore.didChangeExternallyNotification`
  (today the primary needs a relaunch to see a cleared ghost); log each
  blocker's device-ID prefix and `registeredAt` in the "Other-device check"
  line; debug-only override of `mirrorSettleWindow` (a test ghost blocks for
  two days by design).
- [ ] **"Device has been demoted" logged for a routine secondary**: right
  after "🔒 Read-only: this device is registered as a secondary (iCloud KV
  mirror)" the caller logs "⚠️ [WalletManager] Device has been demoted -
  switching to read-only mode" for a device that was never primary
  (`Docs/debug_logs.txt:131-132`, 2026-10-19). The 2026-09-24 fix corrected
  the layer-2 line but not this follow-up line; same shape. Reword to the
  actual verdict.
- [ ] **SwiftUI warning at deletion teardown**: "`navigationDestination`
  modifier only works inside a `NavigationStack`… presenting
  `DeletePhraseConfirmationView`… It will be ignored" is logged once while
  the wallet view unmounts after a deletion (`Docs/debug_logs.txt:242`). The
  phrase screen itself works (device check 2026-10-15); the modifier is
  evaluated once outside the stack during teardown. Cosmetic; move the
  modifier inside the stack or gate it on presentation.
- [ ] **Collapse `shouldBlockWalletAccess`'s three layers**: layer 2 has no
  unique job (its KVS flag is only ever written by the reading device). Left
  because layer 3 returns nil on a fresh install and would hand a new
  secondary spend rights — fix the Tier 0 `checkReadOnlyMode` item first.
- [ ] **Dead device-registry code, remainder**: `DeleteLocallyConfirmationView`
  is never instantiated and the `DeletionStrategy.title/message` strings have
  no UI caller since the blocker report replaced them (both re-confirmed by
  grep 2026-10-19). `cleanupStaleDevices()` and `migrateToThisDevice()` were
  removed 2026-10-16 with the ghost-hardening change (DECIDED 2026-10-10);
  entry rewritten 2026-10-19 to the two survivors. Rides with the next
  device-registry change.
- [ ] **Server-side arbitration for primary claims** — reconciliation is
  client-side only.
- [ ] **Multi_Device_Design S7 note**: a deleted wallet's 30-day mailbox
  authorization stays valid on the Ark server (cannot be revoked); read-only
  and the mailbox holds nothing new, but worth a sentence.

### Code findings from the 2026-09-27 doc rewrites (unverified beyond a grep)

- [ ] **Onchain "used" marking may rarely fire**: `linkTransactionToAddress`'s
  `type == "received"` branch is the only setter of `PersistentAddress.isUsed`,
  but `PersistentTransaction.address` is documented nil for receives. If so,
  onchain rows stay "unused" forever and the gap counter climbs. Verify what
  bark puts in movement destinations for receives. (Feeds the contact
  assignment mixups in Tier 1.)
- [ ] **Address history dead surface**: `AddressGenerationStrategy.discovered`,
  `AddressError.invalidAddressType`/`.addressNotFound`,
  `PersistentAddress.hasBeenUsed`/`totalReceivedFormatted`,
  `AddressService.getUnusedAddressCount`, `validateGapLimit`.
- [ ] **Address history unlocalized strings**: `AddressHistoryView` section
  titles, gap-limit alert, `effectiveTypeDisplayName`,
  `AddressError.errorDescription`.
- [ ] `generateNewAddress` checks duplicates *after* calling bark (a duplicate
  still consumes a revealed index); `AddressService.loadAddresses()` dumps a
  call-stack trace in DEBUG on every call; no unit tests cover
  `AddressService` or `linkTransactionToAddress`.
- [ ] **Process state**: connection quality is binary in practice
  (`updateConnectionStatus`'s `quality:` never passed; `.good`/`.poor`,
  `from(lastSuccessfulSync:)`, `from(latencyMs:)`,
  `incrementReconnectionAttempt()`, `updateQuality(from:)` unused — the
  offline feature in Tier 1 decides their fate); `vtxoHealth`,
  `shouldShowBackupReminder`, `needsAttention`/`attentionSummary`/
  `attentionItemCount` have no view consumers; `VTXOHealth.actionMessage`,
  `BackupStatus.reminderMessage` hard-coded English. Wire up or delete.
- [ ] **CloudKit-merge duplicates never cleaned**: `loadPersistedData` takes
  `.first` without dedupe while `BackupStatus.getSingleton` and
  `cleanupDuplicateBackupStatus()` exist with zero callers.
- [ ] **Balance persistence**: `loadPersistedArkBalance()` /
  `loadPersistedOnchainBalance()` are private wrappers with zero callers;
  `isValid` only changes a log line; no direct unit coverage of the upsert
  path or `init(from:)`/`update(from:)`.

### Bindings adoption

`Bark_Bindings_Unadopted_API.md` records the unadopted surface (baseline
v0.26.0 / bark 0.8.0 since 2026-10-25). Migration guides in `Migrations/`.

- [ ] **Keep the unadopted-API record current on every bindings bump**.
- [ ] **Bindings v0.26.0 (bark 0.8.0) — ship Track A to the two stuck
  users** (the former "Next bump" entry; the release carries every recovery
  fix it waited for, verified as ancestors of `bark-0.8.0`). Built
  2026-10-25 as Train 2 cluster 0 (`Migrations/Bark-0.25.0-to-0.26.0/`).
  Closes when build 26 has passed device scenarios 2 and 3 and the written
  procedure has gone to the users; the "scanning" import UI state is Tier 3.
- [ ] **0.26 Track B — `vtxoSwept` as its own domain case**: `ParsedExitState`
  gains it (`spentInputs`, label "Swept by server", icon, detail rows,
  legacy-string parse, reverse mapping, Live Activity), delete the Track A
  pin test `testVtxoSweptFoldsIntoAlreadySpent`. Until then swept exits are
  persisted as already-spent (lossy, documented). Plan §Track B 1.
- [ ] **0.26 Track B — claim link from `ExitClaimTransaction.vtxoIds`**,
  `skippedVtxoIds` logged and shown as blocked; `ExitClaimSequenceTests`
  cases; protocol doc comment (binding: "Link the claim transaction to
  these, not to the ids you asked for"). Replaces the 0.25 included-ids gap
  entry (answered upstream, ask 19). Plan §Track B 2.
- [ ] **0.26 Track B — movement ids from sends into `PendingPaymentMetadata`**
  (`sendArkoorPayment` → `UInt32`, `OffboardResult.movementId`,
  `LightningSend.movementId`): feedback ask 3's "deletes the heuristic
  matching subsystem". Own plan in `Features/Send_Metadata.md` first. Plan
  §Track B 3.
- [ ] **0.26 Track B — protocol mirroring and startup adoptions**:
  `retryForSecs` on the four `pay*` methods (nil until a policy exists);
  `walletExists(datadir:)` / `readDatadirInfo` for the existence probes
  (throws on a corrupt db — design the error path; Launch_Sequence_Contract
  rule 3 successor); `listFinishedExits` / `listAllExits` as the completed
  exits source with `PersistentExitCache` demoted to a display cache. Plan
  §Track B 5–7.
- [ ] **0.26 Track B — one-paragraph proposals in the unadopted doc** for
  `balanceSummary()`, `debugInfo()` (support screen), `bip321Uri` (one
  receive QR), `parsePaymentRequest` / `sendPayment` against the send
  flow's branching, `decodeBolt11Invoice` (invoice preview). Plan §Track B 8.
- [ ] **0.26 Track B — `Refresh_Deduplication.md` premises re-read against
  bark 0.8.0 #2443** (inputs lock at attempt start, not registration;
  participations shrink or re-delegate on sync) with device scenario 1's
  evidence attached. Plan §Track B 9.
- [ ] **`recoveryStatus()` adoption** — distinguishes recovery-failed from
  never-ran; at minimum log `.failed(message:)` where the import path reads
  `recoveryReport()` (`BarkWalletFFI+WalletCreation.swift:572`).
- [ ] **0.23 Phase 3 (optional, ask first)**: `RoundFlowKind`-rich round UI,
  externally funded board (`boardFundingAddress`/`boardPsbt`),
  `OnchainWallet.evictTx`.
- [ ] **0.24: `importVtxos` batch adoption** (no import loop exists;
  `WalletManager.importVtxo` has zero callers) and **protocol mirroring of
  `importVtxo(args:)` / `recoverVtxos(gapLimit:)`** when a caller needs a
  non-default.
- [ ] **BDK fee estimator removal, Phase 3** — blocked until bark exposes
  onchain estimate/drain fee APIs; then drop `bdk-swift`.
- [ ] **`refreshVtxosScheduled(vtxoIds:scheduledHeight:)`** — DECIDED
  2026-10-10 as the primary mechanism of the VTXO expiry safety net; adopt
  when that plan is written (later train, full process).
  `RoundState.scheduledHeight` is already in the binding.

### Startup and background structure

- [ ] **`OnchainTransactionEntity` persistence is dead code**: the model
  (`Shared/Models/OnchainTransactionEntity.swift`) is not in the schema
  (`SwiftDataHelper.swift:49` lists `PersistentTransaction` only), so
  `OnchainTransactionService.persistTransactions` / `loadPersistedTransactions`
  / `clearPersistedTransactions` throw into a `print` on every refresh and
  launch. Found 2026-10-14 while fixing the onchain reset (the reset no longer
  calls the clear). Delete the three methods and the model, or register the
  model if the cache across launches is wanted.

- [ ] **Field cold launches run 10–20s, one at 74s** (background event
  journal of the mainnet user, 2026-10-04..09; the 2026-10-07 export caught
  the launch refresh still inside Step 3 at 11s, no "Step 3.1" yet). Which
  Step 3 task is the long pole — `refreshAllBalances`, the onchain sync, or
  the block-height fetch? Add per-task timings to the Step 3 task group
  before guessing. Same timings answer the older **18s gap between
  `initialize()` called and executed** (device log 2026-09-08, suspect the
  dedup/queueing layer; merged 2026-10-09). Related: the CoreData error
  flood and the whole-app background launch below.
  Measured 2026-10-12 on Christoph's phone (mainnet, 26 VTXOs, 250
  movements, 1 onchain tx), two launches of the same build: attached to
  Xcode, wallet ready at 48 s with a 20 s call→execute gap; unattached,
  27.7 s with a 61 ms gap — so the call→execute gap is a debugger artefact,
  not the dedup layer. Unattached breakdown: open 0.3 s, server connect
  1.0 s, Step 2 11.9 s of which the BDK onchain sync inside `sync()`
  (`BarkWalletFFI+Server.swift`, runs before the Ark sync) is 11.6 s and
  the Ark sync 0.1 s; Step 3 13.5 s, movements done after 0.4 s, the rest
  is the onchain balance read (6.3 s) and "Onchain history stabilized after
  2 sync round(s)" (6.7 s). About 25 of 27.7 s are esplora/BDK syncs, run
  twice per launch. Long pole answered; the lever is one onchain sync per
  refresh instead of two, or the Step 2 onchain sync off the launch path.
  DECIDED 2026-10-12: Train 2 candidate, not Train 1 — the second sync is
  the 2026-08-13 balance-overcount guard ("history stabilised"), so the
  restructuring needs its own design pass. DECIDED 2026-10-13: once this
  has landed, revisit whether the balance card's load wave should end when
  the Ark data is fresh instead of at the end of the full refresh (today
  that would only halve the window, because Step 2's onchain sync precedes
  the Ark sync); until then the wave stays honest to the full refresh.
  Data points 2026-10-14 evening (journal, unattached, same build as the
  Ark-first change): cold launches of 26.5 s and 32.6 s four seconds apart,
  no step breakdown because the export had evicted the launch's info lines;
  the pull-to-refresh a minute later took 2.65 s with a 1.9 s onchain sync,
  so esplora was not slow at that moment. Christoph saw the balance and
  list refresh quickly and the load wave run about 12 s — if the wave
  ended at 12 s, `refresh()` returned then and the remaining ~20 s to
  "Wallet ready" sat in the post-refresh part of `initializePrimaryMode`
  (exit cache, default-data seeding, arkInfo, service starts), which took
  80 ms in the 13:01 export. Unexplained; needs a Console.app launch.
  DECIDED 2026-10-14 (evening): the wave stays honest to the full refresh
  for now, even though the Ark-first change made "end it at Step 2b"
  possible; Christoph wants to watch the new launch behaviour for a few
  days first. Revisit after that.
  2026-10-14: the Step 2 reorder (Ark sync first, early Ark publish) was
  split out as the Tier 1 Connectivity item "Ark data waits for the onchain
  sync on every refresh" (DECIDED, Train 1); what stays here is the
  one-onchain-sync-per-refresh restructuring and the "Ark-fresh ends the
  wave" revisit.
- [ ] **Explicit daemon start is redundant and logs a bark error** (B6
  re-verified at bark 0.8.0, 2026-10-25: `Wallet::open` calls
  `start_daemon()` when `WalletOpenArgs.run_daemon` is set, and the Swift
  `WalletOpenArgs` has had `runDaemon: Bool = true` all along — so the fix is
  either dropping the launch `runDaemon()` call or opening with
  `runDaemon: false` where the app wants to own the start): bark
  0.7.1's `Wallet::open` starts the daemon itself (`Starting daemon for
  wallet …` is logged before `Existing wallet opened successfully` on every
  launch, 2026-10-14), so `initializePrimaryMode`'s `runDaemon()` call
  produces `Called Wallet::start_daemon while daemon was already running` at
  error level on every launch, and the FFI wrapper still logs "Wallet daemon
  started successfully". Check the bindings for whether `runDaemon` is
  still needed on any path (create/import, after `stopDaemonWait`), then
  drop or guard the launch call and fix the misleading success line. Also
  counts toward the "four BDK syncs per launch" observation: the daemon's
  own esplora sync at open, Step 2's, and the two Step 3 history rounds.
  (The Tier 4 concurrency line "Daemon auto-start on `Wallet.open()` (bark
  0.7.0)" said the same thing and was merged here 2026-10-19.)
- [ ] **Startup wallet detection review follow-ups**: 8 items in
  `Initialization/Startup_Wallet_Detection_Plan.md`; optional Phase 5
  refactor. **Next pure-logic extraction**: wallet-detection decisions
  (contract rules 3/4/14).
- [ ] **Keep `Initialization/Launch_Sequence_Contract.md` current**: every
  startup-shaped fix adds a rule.
- [ ] **~600 lines of `CoreData: error` on first launch after reinstall**: the
  App Group `Library/Application Support` directory doesn't exist yet; create
  it before building the container (that launch took 13.8s).
- [ ] **A background launch still builds the whole app**: `App.init()`
  constructs `WalletManager` → `BarkWalletFFI` and the CloudKit container
  before anything knows whether the launch is UI or a wake. Direction: lazy
  wallet/FFI construction; revisit with Background Execution Phase 2.
- [ ] **Background Execution Phase 2**: mailbox push wake → full background
  pass. Relay stays dumb except the auth-expiry wake. Also carries
  "payment notification → navigate to that payment" and "notifications on
  onchain deposits" from Reminders.

### UI components, refactors, tooling

- [ ] **SwiftUI previews of Shared files fail on the barkFFI archive**
  (observed 2026-10-11 via the preview tool, same error Christoph saw in the
  canvas): the preview JIT reports `CouldNotLoadInputStaticArchiveFile …
  Debug-iphonesimulator/barkFFI.framework/barkFFI` when the host is the app,
  so any view in `Shared/` (e.g. `BalanceRefreshStatusCompact`) cannot be
  previewed; ArkéUI package views preview fine under the `ArkeUI` scheme.
  Options: make the preview host link the bindings dynamically, mark Bark as
  excluded from preview builds, or keep moving previewable views into ArkéUI
  (the paused extraction plan). Until then, verify Shared layouts on device.
- [ ] **Mark every network-name log interpolation `privacy: .public`**
  (DECIDED 2026-10-10): ~30 sites, found with `rg` for `networkConfig.name`
  / `network.name` / `networkName` inside `logger.` calls; mechanical, no
  other interpolation on those lines changes. Verify on a device export that
  "Network config loaded" reads the name instead of `<private>`.

- [ ] **Delete the dead fee-schedule arithmetic in ArkéUI** (DECIDED
  2026-10-19 for Train 2's opening hygiene pass, not Train 1 — the package
  compiles into every target and nothing here ships a behaviour).
  `ArkeUI/Sources/ArkéUI/Models/FeeSchedule.swift`: `calculateFee` on all
  five structures, the three `getPpm` copies on offboard / lightning-send
  (the refresh one stays, `isFreeRefresh` calls it), `isFreeBoard`,
  `isFreeLightningReceive`, `feeDescription(for:)`. Grep 2026-10-19: no
  caller outside the file, no test in ArkeMobileTests or ArkeUI/Tests;
  every live fee display already uses bark's `estimate*` FFI calls. Two of
  the formulas are wrong against `lib/src/fees.rs` at `bark-0.7.1`: offboard
  omits the destination script length and uses the chain fee rate where
  bark uses the server's `offboard_feerate` (so it cannot be computed
  client-side at all); board floors the ppm where bark rounds up. Keep the
  data structs (`FeeScheduleView`, `ArkInfoModel`), `isFreeRefresh` and
  `freeRefreshBlocks` (`VTXORefreshService`, `VTXOGraph`). No behaviour
  change; `BuildProject` on Mobile is the whole check.
- [ ] **`TransactionListModel` has no callers** (`Shared/Views/Activity/
  TransactionListModel.swift`, 2026-10-14 grep: no `TransactionListModel(`
  anywhere in Shared, ArkeMobile or ArkeDesktop). It is the old
  unified-service-backed list model; the iOS list is a SwiftData `@Query`
  and the desktop list has its own path. Delete it, or if the desktop list
  turns out to want it, say so in the file header.
- [ ] **ArkeGlassButton adoption sweep** (~45 `.glassProminent` + ~29
  `.glass` hand-styled sites across ~39 files; adopted in
  DeviceAssignmentSheets_iOS only; expect slight normalization to
  title2/`.large`). `ArkeButtonStyle` (5 sites) is a separate later cleanup.
- [ ] **ArkeCircularIcon adoption sweep**: FaucetModalView_iOS,
  PaymentInfoReceivedSheet, QRScannerView_iOS, desktop WalletCreatedView /
  WalletImportedView.
- [ ] **Previewable models extraction, Phase 3b** (paused; opportunistic).
  `Previewable_Models_Extraction_Plan.md`.
- [ ] **`arke-qr-background` in `Shared/Media.xcassets` is referenced
  nowhere** — delete the imageset. (The emptied `TransactionModel+OnchainAdapter`
  file was deleted in 34b938a; that half closed 2026-10-09.)
- [ ] **Revise use of Int / UInt32 etc. through the app, starting with the
  Bark bindings** (0.23 widened a few to UInt16).
- [ ] **`PaymentInfoReceivedSheet` keeps its own BIP-21 parser**
  (`BIP21URIHelper.parseBIP21URI` extension in the sheet file): strips
  every `bitcoin:` occurrence and splits on the last `?`, while
  `AddressValidator` uses the first. The amount trap is gone (shared
  helper); replace the rest with `AddressValidator.parsePaymentRequest`.
- [ ] **Memory profiler pass** to see if memory piles up over time.
- [ ] **`Data samples/` → `Data_Samples/`** (folder names were out of scope
  for the 2026-09-27 filename standardization).

### Tooling, CI and process

Moved out of Tier 1 "Release readiness" 2026-10-09: no user hits these;
they are the infrastructure `Development/Release_Train.md` assumes.

- [ ] **`Scripts/apply_translations.py` rewrites the whole catalog**
  (2026-10-25): it serializes with Python's default separators and
  `sort_keys`, so one new key produced a 35k-line diff in
  `Shared/Localizable.xcstrings`, and a rebuild does not normalize it back
  (Xcode re-serializes only when extraction changes). Fix: emit Xcode's
  `" : "` separators and ordering, or re-save through Xcode after running.
  Until then, small batches go through `StringCatalogEdit` after a build.
- [ ] **Canvas previews for app-target files cannot launch** (2026-10-13,
  `RenderPreview` on `GlyphWaveTextRenderer.swift`): the preview host
  fails with `CouldNotLoadInputStaticArchiveFile … Debug-iphonesimulator/
  barkFFI.framework/barkFFI`; the folder exists but the binary inside is
  `BarkFFI` (capital B), so the JIT path is looking for a differently
  cased product name. ArkéUI package previews are unaffected. Until
  fixed, visual checks on Shared views go through the device or a render
  test on the simulator (`GlyphWaveRenderTests` is the pattern).
- [ ] **Set up CI via GitHub**: no `.github/` exists. Pair with the nightly
  AI security review via scheduled Claude tasks, which needs CI first. Until
  then the release-candidate step runs the mobile suite by hand.
- [ ] **macOS test suite fails ~68 of 272, flaky, for an unknown length of
  time** (measured 2026-09-22 on a clean tree; the suite has grown since):
  failures span nearly every suite while iOS runs the same Shared tests
  green, pointing at shared mutable state across parallel macOS test hosts
  (keychain, UserDefaults, KVS). `TombstonePersistenceTests` is already
  `.serialized`, `KeychainAccessibilityMigrationTests` is not, so
  `.serialized` alone is not the fix — scratch-scoped keychain/defaults.
  Consequence: desktop regressions are undetectable. Fix before desktop
  parity work.
- [ ] **`BIP21URIHelper.satoshis(fromBTCAmount:)` has no direct unit test**:
  the helper carries the amount parsing for the BIP-21 parsers (fix
  `7338733`). Indirect coverage exists — `AddressValidatorTests.swift:155-181`
  runs `nan`, `inf`, `1e11`, `0x1p-3`, negative, nine fraction digits,
  21M + 1 sat and `0.57` → 57,000,000 through `parsePaymentRequest`. The
  nearby-payment sheet's own BIP-21 parser also calls the shared helper
  (verified 2026-10-09, it is an `extension BIP21URIHelper`), so there is no
  second trap site. Add the direct test when the helper is next touched.
- [ ] **`SECURITY.md` and GitHub private vulnerability reporting**: the repo
  has mainnet users and no stated channel for a security report
  (`README.md:199-201` lists sync facts only); the next reviewer should not
  need a DM. Enabling private reporting is a repo setting (Christoph). Pair
  with a disclosure rule: unfixed items that are exploitable against running
  infrastructure stay out of this doc until fixed.

## Parked (deliberate)

### Desktop parity (`Features/Desktop_Parity.md`)

Onboarding, settings, launch/registration done. Desktop is ignored in the
day-to-day workflow until the macOS test suite is trustworthy (Tier 1).

- [ ] Exit UI; notifications; promote/demote UI (S3); read-only mode for
  `TransactionList`; embed `CurrencySettingView` next to `ThemeSettingView`
  (one line, the view is Shared); the never-cleared banner in
  `ActivityView.swift`.

### Themes (`Features/Theme_System.md`)

- [ ] **Send-modal and balance-modal video sizing** — parked 2026-08-21, code
  reverted. Keep: the reaction videos display LANDSCAPE ~3:2 (encoded portrait
  with a 90° rotation; `mdls`/`naturalSize` lie, only `presentationSize` or a
  thumbnail shows the truth). A full-width 3:2 window showed the whole video
  in the medium detent but wasn't accepted visually. The Reminders report
  "some character videos are awkwardly cropped in the send modal" is this
  item (moved here from Tier 3 Send 2026-10-09).
- [ ] **Per-theme color palettes** (deferred by design).

### Website and marketing

- [ ] "Discuss with AI" buttons; video explainers per test page;
  content-marketing article series on Ark and Lightning topics.

### Future ideas (not scheduled)

- [ ] Fave-friends quick send from Activity; propaganda videos; throw/swipe
  sats at people; replace address parsing with Matt's Rust crate; Ark server
  picker V2 with auto-pick default (plus the cover-screen server selection
  mockup); console; Passkey (may be moot given the server requirement); export
  transactions (metadata export covers part of this); macOS Shortcuts.

Moved from Tier 3 on 2026-10-19 as ideas, not scheduled work:

- [ ] **Parse Cashu NUT-18 `creq` parameter** (idea).
- [ ] **Drain wallet option** (Settings).
- [ ] **Restyle the contact view; invite-friends feature (no fees between
  Arké users)**.
- [ ] **Move relay to DigitalOcean**; **Arke.me domain?** (external).
- [ ] **Switch send button to a slider for larger amounts**.
