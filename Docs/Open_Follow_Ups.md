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
- **Closing an item**: check it off with the date, keep it in place for a
  session or two as a reminder, then move it to the Done log.
- **New items**: add them to the tier they belong in, with a pointer and
  one line of context. Christoph's Reminders app is capture-only; sweep it
  into this file at the end of a session.
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
| Build | started 2026-10-09 with the hygiene pass; soft target ≈ 2026-10-23 |
| Review | not started |
| Device | not started — next time both phones are at hand after Review closes |
| Release | not started |
| Soak | not started |

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

**Past trains:** none yet.

## Decisions needed (Christoph)

Scattered DECIDE and PROPOSAL items pulled together because they block
Tier 0/1 work. Guiding docs hold the full arguments.

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
- [x] **DECIDED 2026-10-10 — explicit device linking: direction accepted,
  build later.** No install adopts the account's wallet silently; it
  discloses what it found and asks for one acknowledgement (Christoph:
  "let's make it explicit"). Proposal: `Architecture/Multi_Device_Design.md`,
  cross-cutting section after S13. Sequencing: a **scope pass** answers the
  four open questions there (primary reinstall sees the same screen; no
  decline button; a late seed is not a second acknowledgement; background
  and push wakes on an unlinked install) before any build; the build is
  Train 2 or later and brings a new detection route
  (`accountWalletAwaitingLink`), one screen plus strings and translations, a
  Launch_Sequence_Contract rule ("never adopt an account wallet without a
  recorded local link"), rewrites of S2/S6/S9, and retires the pre-open
  network reconcile patch (`WalletManager.swift:586-617`) rather than
  inheriting it. Unblocks the design of the Tier 0 "Security checks first"
  gated-actions table (joining is explicit, so gating is about actions after
  the link). Shapes the Tier 1 "fresh secondary reads 0" item's first-launch
  half.
  - [x] **Reinstall after a local wallet deletion silently rejoins — closed
    as superseded 2026-10-10.** The `UserDefaults` tombstone dies with the
    app while the synchronizable seed + KVS hash survive, so a reinstall
    routed straight into the wallet (observed 2026-09-23). Under explicit
    linking the reinstall lands on the link screen instead; no tombstone
    lifetime change needed.
- [x] **DECIDED 2026-10-10 — S7: build only the ghost remedy now; the rest
  of full S7 stays a scoped proposal until explicit linking lands.** The
  reduced S7 shipped 2026-09-24 (blocker disclosure + informed override
  after the settle window). Of the four full-S7 pieces — unlink-first
  paths, per-device confirmed "forget this device" for mirror-only ghosts,
  forced promotion / device deletion and renaming, the "wallet deleted
  elsewhere" cleanup state — only the ghost remedy has an incident behind it
  (2026-09-26 blocked wipe), so it becomes its own Tier 1 item. The other
  three are designed after explicit device linking, which changes who can
  become a ghost; designing them first means designing twice. Tier 0
  "Ghost-device hardening (1)" never waited on this.
- [x] **DECIDED 2026-10-10 — S5 migration assistant: delete the dead
  function now, design the assistant after explicit linking.** The guided
  flow over S2 join → promote → S6 retire is deferred: the link screen is
  where a new phone first learns the account has a wallet, so "this is my
  new phone, move everything here" belongs on it, and designing the
  assistant before that screen exists means designing it twice. Until then
  the three steps stay manual with Linked Devices as the guide.
  `migrateToThisDevice()` (zero callers; writes `isPrimaryDevice` without
  `becamePrimaryAt`, which reconciliation relies on) is deleted now via the
  Tier 4 dead-code line, not held for S5.
- [x] **DECIDED 2026-10-10 — default source for onchain sends: Savings.**
  Rules: (1) Savings is the default for a bitcoin address when both sources
  are viable; the picker offers Payments with its fee and "settles at the
  next round". (2) The smart pick happens once, on load, with whatever the
  request carries (amount, balances, fees). (3) Viability is re-evaluated
  as the user types (ranking redone with the typed amount, debounced like
  fee estimation) so the exceeds-balance state and the picker rows are
  current, but **the selected source never switches automatically during
  amount input** — Christoph: auto-switching under the user's thumb leads
  to unexpected results. (4) If neither source covers amount + fee, the
  exceeds-balance state names both balances. (5) No fee-based auto-pick;
  both fees are shown, the choice is speed/liquidity vs. keeping onchain
  coins untouched. Build item: the Payments-balance onchain proposal in
  Tier 1.
- [x] **DECIDED 2026-10-10 — nearby-exchange payloads: fix the contact
  card now, defer the peer gating to the tilt-share pass.** Background (PR
  #8 description): payloads are accepted whatever the distance check says,
  parsed on arrival, from any connected peer, any number of times; the
  session is encrypted but unauthenticated and every invitation is accepted
  (`ProximityExchangeManager.swift:429-448`, `:567-573`, `:633-644`; the NI
  distance check gates sending only, `:777-796`). The received sheet shows
  a saved contact's card when only the URI's primary onchain address
  matches (`PaymentInfoReceivedSheet.swift:34-40`), while an `ark=`
  destination may outrank it at send time (not traced) — a confirmed Pay
  could go to a payee the card did not name. Ruling: (1) **now, small**:
  show a contact on the received sheet only when every destination in the
  URI belongs to that contact; rides with the Tier 0 send-inputs cluster.
  (2) **deferred** to the Tier 3 "Tilt share" item as its definition of
  done: gate receiving on the same distance check as sending, accept one
  payload per exchange, ignore invitations outside an active exchange.
  Reason: opt-in under Experimental, needs a tilt from the Activity tab and
  a confirmed Pay, no field evidence.
- [x] **DECIDED 2026-10-10 — duplicate default tags/contacts: hand-delete,
  no tool.** The second iPhone's extra 9 tags + 2 contacts in CloudKit are
  removed by Christoph through the normal Tags and Contacts delete paths
  (`TagService.deleteTag` / `ContactService`, user-initiated single-row
  deletes, allowed for mirrored rows). Check before deleting a tag that its
  assignments, if any, sit on the survivor. No dedup tool: one account,
  eleven rows, and prevention (import-gated seeding, 2026-09-25) is on the
  Device checklist as "Seeding scenarios" (1). Revisit a cleanup-service-
  owned merge only if a second account shows the same. Closes when the rows
  are gone — Christoph ticks it.
- [x] **DECIDED 2026-10-10 — wallet deletion and the rates cache: clear the
  currency preference with the other preferences, leave the cache.** The
  rates file (`Application Support/Rates/rates-cache.json`) is public market
  data, not wallet data; the fiat currency preference
  (`UserDefaults.fiatCurrencyKey`) is a user choice like unit format and
  resets with deletion. Both keys get an entry in `SharedStateWipeCoverage`
  with their scope recorded (preference: wiped; cache: kept) so the test
  documents the choice. Build line in Tier 4 "Device registry cleanup".
- [x] **DECIDED 2026-10-10 — dead Shared images: deleted.**
  `Shared/Images/avatar-{female,male}-{1..4}.jpg` (8) and
  `Shared/Images/cover-animation.mp4` shipped in both app bundles since
  Shared attached to both targets; referenced by no code (the avatar names
  in `ContactAvatarEditor` load from the ArkéUI package bundle, `Image(_:
  bundle: .module)` and `UIImage(named:in: .module)`, whose asset catalog
  holds its own imagesets). Removed from the tree 2026-10-10; the
  File-Inspector exclusion route was rejected because Xcode rewrites
  per-file exception sets wholesale. Build to confirm rides with the next
  Build-stage session.
- [x] **DECIDED 2026-10-10 — demotion ends the exit Live Activity.**
  Demotion runs `closeWalletForMigration()` → `resetManagerStateForMigration()`
  (`WalletManager+Wallet.swift:654-668`), which stops services and cancels
  the refresh notification but leaves an in-flight exit's Live Activity up,
  frozen on a state this device no longer advances; only `deleteWallet()`
  or exit completion ends it. Ruling: call the existing
  `endLiveActivityImmediately()` from the migration reset, next to the
  notification cancel, plus a test on the reset path. A "continued on
  another device" terminal state is not built; it would come with the exit
  terminal cases in the Tier 3 `cancelExit` item if ever. Also delete the
  caller-less `closeWallet()`. Rides with the Tier 0 deletion cluster, same
  file.
- [x] **DECIDED 2026-10-10 — "new device joined your wallet" notification:
  accepted, built with explicit device linking** (failure modes §C in
  `Multi_Device_Design.md`): the only visibility a user gets of an
  iCloud-account compromise, and the confirmation for honest S2/S5 joins.
  It is the receiving end of the link event, so it lands in the same
  cluster as the link screen with matching copy; the registry observer that
  detects a new registration row already exists, delivery is a local
  notification (permission handling shared with the expiry-reminder item).
  Part of the linking scope pass.
- [x] **DECIDED 2026-10-10 — phrase confirmation on full wipe: accepted,
  unconditional on the last-device full-wipe path** (failure modes §A in
  `Multi_Device_Design.md`): the final "Delete everything" asks for two
  recovery-phrase words (e.g. 4 and 9), a consent check and backup-existence
  proof in one. Not gated on balance — the spendable number can be wrong
  (divergence incident) and an empty seed can receive later. Local-only
  deletion keeps the seed on the account and is untouched. Word entry can
  borrow the import screen's field; new strings + de/ja/zh-Hant. Rides with
  whichever Tier 0 item touches `DeleteWalletSettingView` first (deletion
  cluster or forfeit warning); two-device verify with the deletion set.
  **DONE 2026-10-15 — flow decided, built, reviewed, committed
  (`b42d536..daabaf8`) and device-checked on one phone the same day**
  (plan `Features/Wallet_Deletion_Phrase_Confirmation.md`; the two-device
  override route stays on the Device checklist; the review's one
  CONFIRMED finding was a pre-existing erased abort error, fixed, ledger
  2026-10-15). Flow rulings: (1) the
  check is its own screen, pushed in the settings stack between the info
  screen and the unchanged slider sheet, not inside the sheet; (2) the
  info screen's manual-backup box gets a full-wipe copy naming the phrase
  deletion and the two-word step, local-only copy unchanged; (3) an
  unreadable keychain fails closed with retry, a definitive `.notFound`
  skips the check; (4) the override keeps its consent toggle next to the
  words; (5) positions are random per presentation. Entry points covered:
  the last-device "Delete wallet" and the "Delete from the account anyway…"
  override; local-only never sees the screen.
- [x] **DECIDED 2026-10-10 — deletion is never blocked on remaining VTXOs;
  warn, don't block.** (From Reminders; `DeletionStrategy` keeps
  distinguishing only last-device vs other-devices.) Christoph: warnings
  exist, the wallet is recoverable from the phrase and its history from the
  backup file, so a hard block has no justification; and two real cases in
  this backlog (dust under the fee floor, the divergence incident) have
  VTXOs that cannot be moved, where a block would strand the user. The
  informed path is the Tier 0 forfeit warning (amount + deadline) plus the
  two-word phrase confirmation decided above.
- [x] **DECIDED 2026-10-10 — network names in log lines are public.** The
  network name is not sensitive (the debug export header already prints
  it), so every network-name interpolation gets `privacy: .public`: the six
  in the pre-open reconcile block (`WalletManager.swift:586-617`) and the
  ~25 elsewhere (FFI wrapper, `NetworkConfigPersistence`, wallet manager,
  refresh service, create-wallet view). Only the name becomes public,
  nothing else on those lines. Build line in Tier 4 "UI components,
  refactors, tooling".
- [x] **DECIDED 2026-10-10 — VTXO expiry safety net: direction (a)
  pre-commit + (c) escalating reminders; plan deferred to a later train.**
  Design gap, no field loss behind it — the mainnet case that first
  motivated it turned out to be a missed mailbox message with the funds
  safe server-side (Tier 0 "Wallet state diverged from the server"); the
  2026-08-13 case was a deleted wallet and backs the forfeit warning. The
  plan, when written, must include how the app learns a server-run
  scheduled round completed (the divergence incident is exactly a round the
  wallet never heard about) and the height maths against the server's
  at-or-past-expiry rejection; full process, funds path. Background: today
  the only thing standing between a closed app and expiry is
  one local notification when the free-refresh zone opens; the hourly
  `VTXORefreshService` check runs in the foreground only and refreshes only
  what is already free. A user who does not open the app during that last
  stretch loses the VTXO to the server's expiry sweep. Options, not
  exclusive: (a) **pre-commit with the server** —
  `refreshVtxosScheduled(vtxoIds:scheduledHeight:)` is in the bindings and
  unadopted (`Bark_Bindings_Unadopted_API.md`, "Maintenance & scheduling");
  whenever the app is open, register a delegated refresh for a height inside
  the free zone and let the server run it later, no app wake needed, and the
  binding's own doc says scheduling further out never costs more than
  refreshing now; the server rejects a scheduled height at or past expiry
  (`server/src/round/mod.rs:1930-1940`, read at master `8adc8e7`, not
  confirmed at the deployed 0.7.1 tag), so the height maths must be right.
  (b) refresh earlier and pay ppm while in the foreground when expiry is
  within N days. (c) escalating reminders (zone opens / 3 days / 1 day) that
  name the amount at stake; its precondition is the Tier 0 "Expiry-critical
  reminders" item, since a reminder a denied permission swallows is no
  backstop. (d) Background Execution Phase 2 (push wake → refresh), already
  planned but slow and uncertain after Phase 1's grant numbers. PROPOSED
  2026-10-09: (a) as the primary mechanism plus (c) as the backstop for
  wallets never reopened after the VTXO was created. Changes the refresh
  model from "wait for free, in the foreground" to "pre-commit", touches
  funds — plan in a later train, full process. The four app defects in the
  Tier 0 divergence cluster do not wait on this.
- [x] **DECIDED 2026-10-10 — exits depend on the same operator as the
  server: accepted and recorded; the fallback is designed inside the
  offline feature.** The pre-signed exit path is only real if a user can
  exit while Second is down, and today both the chain source and the Ark
  server are Second's on both networks (`NetworkConfig.swift:43-59`), with
  no second chain source, no Settings entry, and nothing telling a user a
  custom config could point elsewhere. Ruling: (c) now — the dependency is
  recorded as rule 13a in `Initialization/Launch_Sequence_Contract.md` so
  nobody mistakes the exit path for operator-independent; (a) and (b) are
  folded into the Tier 1 offline / server-down feature's scope: when that
  feature designs the server-down state it also decides the fallback chain
  source per network (a trust decision about a third party such as
  `mempool.space`), whether it is automatic or a recipe, and whether an
  Esplora setting appears in Settings (the former Tier 3 line). Reason: the
  exit path has never been exercised against a server outage, so a
  standalone fallback patch would be untested policy; the outage feature is
  where the whole path gets designed. Verified 2026-10-08: both servers and
  both chain sources answered.

## Tier 0 — Funds or security at risk

- [ ] **Mainnet fee rate can still crash the app**: mainnet rates are
  uncapped and `FeeRateService.parse` only drops values past `UInt64`. A rate
  above ~6.6e16 sat/vB passes and crashes at
  `PaymentDestinationSelector.swift:482` (`Int(feeRate * estimatedVBytes)`,
  the only such arithmetic site) whenever an onchain destination is ranked.
  Sanity ceiling on mainnet (e.g. 10,000 sat/vB) or checked arithmetic, plus
  a test; note `FeeRateServiceTests.testNilCapPassesHighRatesThrough` pins
  the current uncapped behaviour and changes with the fix. Executed
  2026-10-08 (external parser harness against the working tree):
  `{"1": 250000.0}` yields 250,000 sat/vB for all three tiers. Also check
  what the confirmation screen shows for the fee at such a rate — not traced.
- [x] **"Delete everything" re-creates the iCloud backup it just deleted**
  — done 2026-10-14, device check passed the same evening (two full wipes
  logged the skip, the import between them found no backup; plan §8.1).
  Original entry: (traced 2026-10-08, not executed): `DeleteWalletSettingView.deleteWallet`
  runs `cleanupService.deleteWalletData` (which calls
  `WalletBackupService.deleteAllBackups()`), then `walletManager.deleteWallet()`
  → `BarkWalletFFI.deleteWallet()` → `shutdownWallet()` → `backupWallet()`,
  whose only guard is `wallet != nil` — true, the handle is still open
  (nothing in `WalletManager.deleteWallet` steps 1–4 touches the FFI handle).
  A fresh `Backups/db.sqlite` plus a timestamped copy land in iCloud Drive
  before the directory is removed, after a final `wallet.sync()` the
  delete-path shutdown also runs, and the cleanup service's own comment says
  such a leftover is restored over the next wallet created. Fix: skip the
  backup on the delete path (a flag on shutdown, or delete backups after
  shutdown). Same function as "Delete flow has no partial-failure handling"
  below: one build cluster. **BUILT, REVIEWED and DEVICE-CHECKED 2026-10-14**
  (uncommitted; 504/504 mobile; app-switch variant passed in the 21:50
  export, nothing left on device), plan in
  `Features/Wallet_Deletion_Backup_Skip.md`: `WalletManager.deleteWallet(scope:)`
  reads `DeletionSummary.scope` and on `.everywhere` runs the FFI shutdown
  with `backingUp: false` before the file delete; the backup slot joins
  `SharedStateWipeCoverage` as full-wipe-only. Consequence corrected there:
  the leftover is restored only on the no-local-file launch branch, not
  over a freshly created wallet (newest-wins keeps the newer local file).
  Test choice DECIDED 2026-10-14: no backup-directory injection, the device
  check is the proof. Adversarial pass 2026-10-14 (plan §10): one CONFIRMED
  finding fixed in-session — the app's background backup hook could refill
  the slot during the 5–15 s wipe window, so opportunistic backups are now
  suspended for the whole deletion; the local-only final backup still
  runs. Side findings filed in the plan's §9 for other items:
  `deleteAllBackups` skips hidden `.icloud` placeholders of a never-
  downloaded backup (goes with the newest-wins item below), and
  `restoreWalletFromBackup` would overwrite the slot with the local file if
  ever called with an open handle (Tier 4, guarded by the caller today).
  Done means: delete-everywhere then create on one device, backup slot
  stays empty (relaunch log says no backup available; the ordering test was
  dropped 2026-10-14, see the plan). Local-only
  deletion keeps the backup on purpose (rejoin) — do not touch that branch.
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
- [x] **Warn on wallet deletion about forfeitable offchain balance** — done
  2026-10-13 (uncommitted). The orange box on the Delete wallet screen now
  shows only for a Payments balance bark can still forfeit (its unspent
  list, Spendable + Locked) and names the amount in the user's unit plus
  the time to the earliest expiry ("in about 26d 5h", shared
  `BlockTimeFormatter`); last-device copy says forfeited unless recovered
  from the phrase and refreshed, other-devices copy says open another device
  so it refreshes in time; no time clause when the height is unknown or the
  expiry is already past (the app cannot tell whether the sweep ran).
  Onchain-only wallets get no box (DECIDED 2026-10-13: they come back with
  the phrase). Decision in `DeletionForfeitWarning` (pure, 10 tests);
  read-only secondaries fall back to the synced `totalSat - pendingExitSat`
  with no deadline. Sweep timing verified at bark `watchman/policy.rs`
  (`chain_tip >= expiry_height`, same at `bark-0.7.1` and HEAD). Adversarial
  pass fixed two CONFIRMED findings in-session (override and
  unreadable-registry cases now get the last-device copy; the amount no
  longer waits on the network block-height fetch, ledger line). Not carried
  over from the old generic box: a wallet whose only Ark funds are an exit in
  flight shows nothing now — filed in Tier 3 deletion. "About" still
  overstates by up to one round: the server refuses inputs with
  `expiry_height <= scheduled_height`, fine at days, loose at hours. Four new
  keys wait for the next translation batch; the old
  `settings_delete_balance_warning` sits stale in the catalog with its
  de/ja/zh-Hant values. Device check done 2026-10-14 (Christoph: Delete
  wallet on the primary with VTXOs, amount + time read fine; the
  other-devices copy still unseen, needs a second registered device). The
  two-word phrase confirmation
  (DECIDED 2026-10-10) did not ride along, next deletion-cluster item takes
  it. Original entry: (field
  incident 2026-08-13: 10,000-sat VTXO swept at expiry 6h after deletion, app
  showed 0 with no explanation). Minimum expiry height across spendable VTXOs
  is known at deletion time (`BalanceRefreshStatusViewModel.swift:55` already
  computes it) — say "your offchain balance of X is forfeited around <time>
  unless this wallet is re-imported and refreshed before then." Deleting the
  last device deletes the only agent that can refresh. The existing
  `settings_delete_balance_warning` string (`DeleteWalletSettingView.swift:57`)
  is what this replaces; the Reminders report "delete wallet amount-warning
  copy is not right" (merged here 2026-10-09) is the same string. The
  stronger alternative is the PROPOSED "delete only when the user has no
  VTXOs?" above.
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
- [x] **Delete flow has no partial-failure handling** — done 2026-10-16:
  built and reviewed 2026-10-15, device check passed (Christoph, "works
  great", in aggregate), uncommitted; plan
  `Features/Wallet_Deletion_Partial_Failure.md`. Original entry:
  (`DeleteWalletSettingView.swift:276-328`). Added 2026-10-14 from the
  deletion device log: the flow also does not wait for or cancel an
  in-flight refresh — wipe 1 ran while the launch refresh was in Step 3, the
  cleanup deleted the rows at 19:22:11.5 and Step 3.1 merged at 19:22:12.4,
  re-creating the deleted wallet's onchain row into the no-wallet state
  (rule 17 orders services, not the refresh task). Await or cancel the
  refresh before the cleanup's first destructive step. Original entry:
  `deleteWalletData()` runs first,
  then `walletManager.deleteWallet()`; if the second throws, shared state is
  already destroyed and the user stays in-app with no navigation
  (`onWalletDeleted` is wired, the generic catch never calls it). The view's
  `isDeleting` is never reset on success either (the service resets its own
  in a `defer`). User-visible face: Tier 2 "Startup routing retests".
  **Plan DECIDED 2026-10-15**, `Features/Wallet_Deletion_Partial_Failure.md`:
  the refresh is owned by an unstructured task in the dedup manager with no
  cancellation point (cancel is a known no-op, O4), so deletion is **gated**
  instead — the delete screen waits visibly while wallet data is loading
  (`isRefreshing` or the `initialize` key), the cleanup service re-checks at
  its first step and aborts with nothing deleted, and `refresh()` skips
  during the wipe (Christoph's principle: wait before committing, like
  explicit device linking; the first draft's pause-inside-the-wipe with
  resume + timeout was dropped). Fallible CloudKit deletes move ahead of
  the KVS/backup block with a `rollback()`; every pre-seed failure shows
  its error on the info screen with the wallet still working. Route-anyway
  on a late file-removal failure DECIDED 2026-10-15. **BUILT and REVIEWED
  2026-10-15** (uncommitted): adversarial pass found the route-anyway
  premise half wrong (import does not replace a leftover directory, bark
  refuses the fingerprint mismatch) → stale-directory marker consumed by
  create/import; plus the refresh skip moved ahead of the `isRefreshing`
  flip and a pre-deletion save so the rollback only undoes the cleanup's
  own work (plan §10). Device check in plan §9 owed. Sweep found
  two more late writers: the 90 s seeding waiter (fixed in the plan) and
  the launch device registration (filed on the ghost item below).
- [ ] **Ghost-device hardening (1), residual**: the mirror clear in
  `unregisterCurrentDevice` is already unconditional and across hashes
  (`DeviceRegistrationService.swift:475-486`, commit 3dc292c) but still
  skipped when `modelContext` is nil, `getOrCreateDeviceId` throws or
  `save()` throws (`:458`, `:462`, `:472`), and `WalletDataCleanupService`
  swallows the unregister error as non-fatal (`:293-304`) so
  `summary.deviceUnregistered` stays false with no typed error. Same
  ordering fault in `unlinkDevice` (`:942-943` throws `deviceNotFound`
  before the mirror clear at `:955`). Fix: clear first or in a `defer`,
  surface the failure in the deletion summary — typed error + test. From the
  2026-09-26 incident (full write-up in the Done log): an uncleared mirror
  entry blocks every remaining device's full wipe for 48h with no override.
  Items (2)–(4) of that incident are in Tier 4. Added 2026-10-15 from the
  partial-failure sweep: `MainView_iOS.registerDeviceIfNeeded` (launch
  `.task`, CloudKit round trip) and the `onWalletReady` registration run in
  parallel with the wallet and can land *after* `unregisterCurrentDevice`,
  re-creating the same ghost mirror entry; `registerCurrentDevice` should
  refuse while `isDeletionInProgress`, or the cleanup re-clears the mirror
  after its quiesce (`Features/Wallet_Deletion_Partial_Failure.md` §8).
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
- [ ] **Failed boards leave onchain coins stranded on bark 0.7.1** (surfaced
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

## Tier 1 — What users hit every day

### Send and fees

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
- [x] **Nothing on screen says the launch load is still running** — DONE
  2026-10-13: device look passed on the themes, pull-to-refresh and Reduce
  Motion on and off (Christoph: "looks great"); shipped shape is the glyph
  wave on the amount, 3 s continuous passes, ten glyph-widths at 60 %,
  label plain white, static 75 % amount only under Reduce Motion. Follow-ups
  filed on their own: VoiceOver value (Tier 3 Balance), secondary-device
  CloudKit import window (Multi-device fresh secondary), "Ark-fresh ends
  the wave" revisit (Tier 4 launch timing item, after Train 2), canvas
  preview host (Tier 4 tooling). Not observed on device: the numeric
  content transition at settle with the renderer installed — needs a
  balance that changes during a refresh. Move to the Done log with the
  write-up below. DECIDED
  2026-10-12: into Train 1, design below approved for a first build
  ("affects every user every time they open the app"); the on-device look
  across the four themes decides between the full version and the
  amount-state-only fallback.
  (Christoph's unattached log 2026-10-12: wallet ready at 27.7 s, the
  balance card showed a 3 h old persisted balance as current the whole
  time, no marker; the connection icon fixed the same day was the only
  accidental hint). Today: the list skeleton needs an empty cache plus a
  fresh import, "Loading transactions…" needs a missing service,
  pull-to-refresh spins only when pulled; `WalletManager.isRefreshingWithData`
  ("refresh running, data already shown") exists for exactly this and has
  no reader. Earlier attempts (pre-git): a pulsating dot, and an opacity
  pulse on "Your Balance" — still in `BalanceCard.swift` commented out,
  0.5↔1.0 autoreversing every 0.8 s on `isRefreshing`: continuous motion
  with no rest, hence distracting. Proposed design (Christoph's sweep idea
  + two additions, 2026-10-12):
  - **Highlight sweep across "Your Balance"**: one pass ≈ 1 s, then ≈ 2 s
    rest, repeat; the rest period is the difference from the pulse. Band
    tinted from the theme accent, not pure white — on light art a white
    band on white text vanishes and a darkening band reads as a glitch.
  - **Amount in a quiet state**, ≈ 75 % opacity while refreshing with
    data; no motion on the number.
  - **Visible ending**: sweep finishes its pass, amount settles to full,
    the existing number transition shows any change. The settle is what
    makes the wait feel finite.
  - Guardrails: start only after a refresh has run ≈ 1 s (a 2 s
    pull-to-refresh must not flash); stop at the end of a pass, never
    mid-sweep; trigger on `isRefreshingWithData`; Reduce Motion → static
    75 % state, no sweep.
  Caveat: shimmer is read as "placeholder", so on real text it may read as
  "this label is loading"; the rest period and tint are the bet against
  that. Fallback if it reads wrong: amount state + settle alone, no sweep —
  a subset of the full version, worth seeing first. Done means: on-device
  look on all four themes, cold launch and pull-to-refresh, Reduce Motion
  on and off. Independent of the Train 2 onchain-sync item above, which
  shortens the window but does not remove it.
  **BUILT 2026-10-13, awaiting the device look.** Full version as designed:
  `BalanceLoadIndicatorModel` (Shared/UI, pure state machine holding the
  four guardrails, 9 tests in `BalanceLoadIndicatorModelTests`),
  `GlyphWaveTextRenderer` (see below), `BalanceCard` drives
  the clocks (1 s arm, 1 s pass, 2 s rest, amount at 75 %, settle over
  0.3 s) and the old commented-out pulse is gone.
  First device look 2026-10-13 (Christoph): the tinted band, a gradient
  overlay masked to the text, was only visible when staring — a few glyphs
  got a white glow for a split second. Cause: white glyphs have no
  brighter to go, and the tint (`AppTheme.textColor`) is near-white on
  three themes. DECIDED 2026-10-13 (Christoph's idea): per-glyph opacity
  instead — `GlyphWaveTextRenderer`, a `TextRenderer` that dips each glyph
  to 35 % as a trough travels across the label,
  no tint, no motion, one `Text` so kerning, localisation and VoiceOver are
  untouched; `#Preview` in the file loops the cadence on dark, light and
  gradient swatches. Second device look 2026-10-13: better, not smooth —
  DECIDED (Christoph): trough six glyph-widths instead of three, pass
  0.5 s instead of 1 s, rest unchanged at 2 s. Third look: still stepped —
  DECIDED (Christoph): ten glyph-widths and a shallower dip, set to 60 %
  trough opacity. Fourth look: the label is the wrong carrier and short
  passes feel hectic — DECIDED 2026-10-13 (Christoph): the wave moves to
  the amount (the stale thing), label back to plain white, 3 s pass, no
  rest, ten glyph-widths at 60 %; the flat 75 % baseline dim on the amount
  is dropped outside Reduce Motion (two dimming signals on one number
  muddled both; under Reduce Motion the static 75 % stays as the only
  signal). Open risk for the device look: whether a custom `TextRenderer`
  keeps the numeric content transition that shows the changed value at
  settle. If the wave still reads as stepped, the next lever is per-pixel
  dimming (a moving opacity gradient as a soft clip layer in the renderer)
  instead of per-glyph opacity — PROPOSED, not built.
  Fifth look: Christoph likes it. One defect fixed: a quick wave running
  backwards at settle — the loop's reset of the progress from 1 to 0 landed
  in the same update as the settle, and the amount's
  `.animation(value: isQuiet)` interpolated it; the reset now runs in a
  transaction with `disablesAnimations`. Open question raised at this
  look: the wave runs for the whole launch refresh, ~25 of 27.7 s of which
  are the two esplora/BDK onchain syncs. Ending it when the Ark data is
  fresh would only halve the window today, because Step 2 runs its onchain
  sync *before* the Ark sync; the real lever is the Train 2 onchain-sync
  item. PROPOSED: keep the indicator honest to the full refresh now, and
  revisit "Ark-fresh ends the wave" once Train 2 has moved the Step 2
  onchain sync off the launch path. Seen before shipping this time: `GlyphWaveRenderTests`
  rasterises the label on the simulator and checks rest = untouched,
  mid-pass = a visible share of glyph pixels dimmed but legible (canvas
  previews could not be used, see the Tier 4 preview-host item). The band
  tint paragraph below is history. Planning finding
  (trusted claim, caught before code): `isRefreshingWithData` was
  `isRefreshing && hasLoadedOnce`, and `hasLoadedOnce` flips only when the
  first `performRefresh` returns, so it was false for the entire 27 s
  launch window this entry is about; redefined as
  `isRefreshing && totalBalance != nil` (no other reader; the review
  showed `totalBalance` is non-nil from `setModelContext` on because zero
  models are synthesised, so this is `isRefreshing` in practice, and a
  freshly created wallet's first refresh shows a quiet 0 — accepted).
  Adversarial pass 2026-10-13: two fixes landed (band start frame never
  rendered, so nothing would have swept; the flag's rationale was wrong —
  both in the Rework Ledger). Accepted as low: a Reduce-Motion
  double-toggle mid-pass can leave "quiet, no sweep" until the refresh
  ends; the cancelled loop's `defer` writes `@State` after a wallet
  delete unmounts the card (no-op in practice, unverified). Gap, not this
  item's: on a secondary device the launch load is the CloudKit import,
  which has no `isRefreshing` signal, so the indicator never shows there —
  belongs to the Multi-device "fresh secondary" item.
  Band tint: there is no per-theme accent property, so the band
  uses `AppTheme.textColor` (gold on Classic, the wordmark tints on the
  others) — swap for a dedicated colour if the device look says so. Hidden
  (privacy) card shows no indicator by design: no label, no amount.
  Not done: VoiceOver still hears nothing about the running load (the
  activity screen's balance element has no "updating" value) — a one-string
  follow-up if wanted.
- [ ] **Send all from savings to spending did not work, needs a better
  message** (Reminders).

### Data safety

(The metadata-import name-merge item moved to Tier 0 on 2026-10-09.)

- [x] **A deleted wallet's onchain row reappears in the next wallet created
  in the same process** — trigger (1) fixed 2026-10-14 (uncommitted):
  `resetManagerState()` now calls `OnchainTransactionService.resetTransactions()`
  (list + 30 s cache, dead entity-clear dropped) and the new
  `UnifiedTransactionService.resetMergedTransactions()`. Device check passed
  the same evening (21:50 export: delete → create in one session, Step 2b
  saved 0 rows, Activity empty). Trigger
  (2), deletion racing an in-flight refresh, closed 2026-10-16 with the
  Tier 0 partial-failure item (deletion gated on the refresh; plan
  `Features/Wallet_Deletion_Partial_Failure.md`). Original entry: (field, Christoph 2026-10-14 21:24
  export + four
  screenshots: new mainnet wallet, balance 0, one "Received +20,000 sats, 2
  wk. ago" row, category `onchain_transaction`, 2125 confirmations — the
  previous wallet's onchain receive; bark reported `Retrieved 0 onchain
  transactions` for the new wallet). Traced: nothing resets
  `OnchainTransactionService` on deletion — `resetTransactions()` has zero
  callers and `resetManagerState()` (`WalletManager+Wallet.swift`) skips the
  service — so its in-memory `onchainTransactions` still holds the deleted
  wallet's list. Every `UnifiedTransactionService.mergeTransactions()` turns
  that array into `PersistentTransaction` rows via
  `findOrCreatePersistentOnchainTransaction` (`:292-359`, insert + save,
  never a delete), and the list shows them through the ark service's
  all-rows fetch (`TransactionService.swift:100`). Two triggers in the log:
  (1) **regression from `31e2f10` (2026-10-13)** — Step 2b now merges at
  19:24:13.7, six seconds *before* Step 3's fresh onchain fetch replaced
  the array at 19:24:19.67, so the first refresh of every freshly created
  wallet re-creates the old rows; before Step 2b the only merge ran after
  the fetch and the fault was latent. (2) **deletion does not wait for the
  in-flight refresh**: wipe 1 ran while the launch refresh was still in
  Step 3; the cleanup deleted the rows at ~19:22:11.5 and Step 3.1 merged
  at 19:22:12.4, re-creating the row into the no-wallet state (contract
  rule 17 orders services, not the refresh task). Fix: reset the onchain
  service (array + 30 s cache) in `resetManagerState()`; note
  `resetTransactions()` also tries to clear `OnchainTransactionEntity`, a
  model that is **not in the schema** (`SwiftDataHelper.swift:49` lists
  `PersistentTransaction` only), so that persistence branch is dead and
  should go. For (2), the refresh should be awaited or cancelled before the
  cleanup's first destructive step — same family as the Tier 0
  partial-failure item. Ark rows are unaffected (their upsert diffs against
  bark's list, which is empty for a new wallet). Display only, no funds;
  Tier 1 because every delete → create in one session now shows a foreign
  transaction in a brand-new wallet.

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

### Multi-device (guiding doc: `Architecture/Multi_Device_Design.md`)

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
- [ ] **"Forget this device" for mirror-only ghosts** (the one piece of
  full S7 approved to build, DECIDED 2026-10-10; deliberately not built
  2026-09-24; now the only remedy for a healthy-but-unwanted blocker since
  the override is no longer offered there): `unlinkDevice` throws
  `deviceNotFound` with no registry row (`DeviceRegistrationService.swift:
  933-944`), so needs `forgetUnsyncedDevice(_:)` (does not exist) that
  clears the mirror entry for one named device, per-device and confirmed,
  owned by the cleanup service's rules for shared state; fail closed when
  the registry can't be read. Surface it from the delete screen's blocker
  list (which already names mirror-only blockers; aged ones unlock the
  override) and from Linked Devices. The "KVS-only ghost is invisible" item
  folds in here. Two-device verify: create a ghost (install, link, wipe the
  device without unregistering), forget it from the other phone, confirm
  the full wipe is no longer blocked.
- [x] **Blocked-strategy copy** — already built (2026-10-09 hygiene pass):
  `DeleteWalletSettingView.swift:238-243` shows
  `settings_delete_warning_check_failed` when the blocker report is nil
  (landed in ed9d8fe). The old `DeletionStrategy.title/message` strings have
  no UI caller — Tier 4 dead-code line.
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
- [ ] **Switch send button to a slider for larger amounts**.
- [ ] **Toggle icons blink again; no-contacts icon should be white and more
  distinct; animated highlight when parsing the clipboard** (the cropped
  character videos moved to Parked → Themes video sizing 2026-10-09).
- [ ] **How to detect if an address is from a different Ark server?**
- [ ] **Parse Cashu NUT-18 `creq` parameter** (idea).
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

### Receive

- [ ] **Temporarily brighten the screen when showing a QR**
  (`UIScreen.main.brightness`, restore on dismiss).
- [ ] **Test scanning from a laptop camera; ensure amount and memo input
  interactions work properly**.
- [ ] **QR network indicators not showing?**

### Activity, transaction details, tags

- [ ] **Hide failed and completed refreshes that were free?** (The growing
  "Failed refresh" list in the Tier 0 divergence cluster is the extreme
  case; this line is the general one.)
- [ ] **Balance tag shows "-0 B fees paid"; needs a no-fee state**.
- [ ] **Tag amounts — do they include fees, should they? Balance tag must
  include onchain child-tx fees**.
- [ ] **Transaction details**: show the invoice description when present
  (Opago order numbers); description for refreshes; onchain send-to /
  received-from addresses; onchain txid with explorer link; general
  clean-up; remove blue from the status colours?
- [ ] **Exit status — long-press copy copies the truncated txid**.
- [ ] **`TransactionCardStackView_iOS` holds `[PersistentTransaction]`** in
  `@State` for the overlay's lifetime; if an import deletes the movement row
  while the overlay is open, reading its own properties still traps. Pass
  txids from the list and re-fetch the window; re-verify the entrance/drag
  choreography on device.
- [ ] **Fiat on transaction detail and rows** — skipped 2026-09-29 (decide the
  "today's rate" wording first). `Features/Fiat_Rates.md` Phase 3.

### Balance, board / offboard

- [ ] **VoiceOver hears nothing about the running launch load** (filed
  2026-10-13 from the load-wave item): the activity screen's balance
  element has a label and value but no "updating" state while
  `isRefreshingWithData` is true. One string appended to
  `balanceAccessibilityValue` in `ActivityView_iOS.swift`; read the flag
  directly, the 1 s arming guard is a flash guard and does not apply to a
  value read on focus.
- [ ] **Onboard modal**: minimum value only shows after X-Ray was visited;
  add fee info; success message with duration; test the error state.
  **Offboard modal**: add fee info; add data to success (claim required?);
  test the error state. **Boarding**: calculate and display the network fee;
  adjust the amount input to the unit setting; offboard takes a long time.
- [ ] **Fee summary — move to savings showed up as a send**.
- [ ] **Full bitcoin format — add satcomma spacing** (nothing in
  `BitcoinFormatter` does it).
- [ ] **Settings — combine unit format and show-balance?** (question).

### Refresh

- [ ] **X-Ray: list local notifications** (requested 2026-09-27): show
  `pendingNotificationRequests()` (id, title, category, `nextTriggerDate`)
  and `deliveredNotifications()` next to the Background Activity rows, plus
  the scheduler's inputs (current height, target height, blocks remaining,
  seconds/block). A full history needs a `localNotificationScheduled`
  journal kind plus journaling in the `willPresent`/`didReceive` hooks.
- [ ] **Make the overlay better reflect the current state**.
- [x] **Warn when total VTXOs are under 330 sats** — done 2026-10-11 with the
  balance-card state: the row says "Too small to refresh" with the floor,
  the modal disables Start and names the amounts, the manual path returns
  `.belowMinimum` (`Features/Refresh_Deduplication.md` §10).
- [ ] **`RefreshModalFormView` — description text is cut off even when the
  modal is fully expanded**.
- [ ] **Surface expiry sweeps instead of silently showing less money** — on
  import VTXOs come back as bare `Spent` with no reason. Blocked on upstream
  spent-reason (`sweptAtExpiry`, feedback §1.9 / ask 17); once available,
  write an explicit "expired" history entry. The pre-sweep half is the
  Tier 0 divergence cluster.

### Exits

- [ ] **Adopt `cancelExit` from bindings v0.18.0**: the escape hatch for
  fee-blocked exits. Prerequisites: Live Activity `ExitState` lacks terminal
  `canceled`/`vtxoAlreadySpent`; verify the date-freeze workaround covers
  explicit cancels (feedback §1.4); check whether bark purges cancelled exits
  from `getExitVtxos()` like claimed ones (snapshot into
  `PersistentExitCache` if so). Notes in `Bark_Bindings_Unadopted_API.md`
  §1.1. Folds in the Reminders question "review exit cancellation — only
  until the first transaction is committed?".
- [ ] **`estimateEmergencyExitFee(...)` exit pre-flight** — broadcast vs
  claim fees separately; block/warn hard on `fundable == false`. Slow call
  (syncs the onchain wallet first).
- [ ] **Exit UX pass** (Reminders): completed exit did not show the status
  bar with details (should it?); switch up the notification when done; fix
  progress state in label; remove UI of the manual claim step; review the
  experience from first interaction; more testing.
- [ ] **Disable the Settings exit entry while an exit is active?**
- [ ] **When the daemon auto-exits VTXOs, how to detect and tell the user?**
- [ ] **Is there exit grouping, or is each VTXO its own movement entry?**
- [ ] **Options to handle failed Lightning payments (exit?)**.
- [ ] **Drain wallet option** (Settings).
- [ ] **Report upstream to bark devs** (network-verified on the stuck signet
  wallet): exit package txs don't exist on the network despite bark reporting
  broadcast; round-replacement VTXO fails signature validation. Both are
  written up in `Bark_Bindings_Feedback.md` §1.6 — tick once Christoph
  confirms that doc reached Second.

### Settings, devices, deletion

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
- [ ] **Delete wallet with an exit in flight shows no funds warning** (from
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
- [ ] **Backup — how to explain that not all wallets are compatible?**
- [ ] **Rejoin wallet screen is unstyled**.
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
- [ ] **Restyle the contact view; invite-friends feature (no fees between
  Arké users)**.

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
- [ ] **Image in move-to-payments has a slight white line on the left**.

### X-Ray and Tilt

- [ ] **Options view / `VTXODeveloperActionsView` don't refresh when another
  VTXO is selected** — key the view on the VTXO id.
- [ ] **Tilt share — pay is not working; explore Mesh user detection instead
  of NearbyDevices.** Definition of done now includes the deferred half of
  the nearby-payload ruling (DECIDED 2026-10-10): gate receiving on the
  same distance check as sending, accept one payload per exchange, ignore
  invitations outside an active exchange.

### Localization

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

### Concurrency and the FFI boundary

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
- [ ] **Daemon auto-start on `Wallet.open()` (bark 0.7.0)**: our explicit
  `runDaemon()` logs `Called Wallet::start_daemon while daemon was already
  running` — may restart a just-started daemon every launch. Drop the call or
  confirm the double-start is a no-op.

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
- [ ] **Collapse `shouldBlockWalletAccess`'s three layers**: layer 2 has no
  unique job (its KVS flag is only ever written by the reading device). Left
  because layer 3 returns nil on a fresh install and would hand a new
  secondary spend rights — fix the Tier 0 `checkReadOnlyMode` item first.
- [ ] **Dead device-registry code**: `cleanupStaleDevices()` and
  `migrateToThisDevice()` have zero call sites; `DeleteLocallyConfirmationView`
  is never instantiated; `DeletionStrategy.title/message` strings have no UI
  caller since the blocker report replaced them (`WalletDataCleanupService.swift:
  1062`). `migrateToThisDevice()` goes now (DECIDED 2026-10-10, no longer
  held for S5); rides with the next device-registry change, e.g. the
  deletion cluster's ghost-hardening residual.
- [ ] **The `showNoPrimaryDeviceBanner` NotificationCenter post has no
  observer** (`DeviceRegistrationService.swift:1069`, from `demoteThisDevice`).
  It is the hook the Tier 1 "no primary device" banner would use — wire it
  there or remove it, decided together.
- [x] **Devices-list display scoping** — already done 2026-09-24 (Done log,
  Linked Devices wallet-hash scoping; both list views filter on
  `device.walletHash == accountWalletHash`). Closed 2026-10-09.
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
v0.25.0 / bark 0.7.1). Migration guides in `Migrations/`.

- [ ] **Keep the unadopted-API record current on every bindings bump**.
- [ ] **Next bump: take the post-incident bark client fixes — now a funds
  path, front of Train 2** (upstream master as of 2026-10-08, no tag past
  `bark-0.7.1` / `server-0.7.1` yet; depends on Second cutting a bindings
  release). A mainnet user is waiting on it: Second's remedy for the Tier 0
  divergence incident is recovery from seed, and every client-side recovery
  fix is newer than the bark 0.7.1 our bindings carry — `f83de1901`
  (2026-09-14, recovery reader stopped paging on pages without vtxo ids),
  `d9e305d0e` (09-17, recover from both mailboxes and ask the server per
  vtxo), the `fix-recovery-bug` merge `1ea9116ae` (09-21), `e9e78ad33`
  (10-08, read the mailboxes to the end). Also: `f85ca92ac` failed boards
  kept out of the onchain wallet (Tier 0 item), `48b005f10` lib board
  funding-output check (server-only path, harmless for us), `244e3981f`
  `GetVtxosByIds` rpc, and upstream master's `Balance.needs_refresh` split.
  Watch for a `bindings` release that pins a bark with these; re-run the
  migration checklist, update `Bark_Bindings_Unadopted_API.md`, then tell
  the user to recover.
- [ ] **`initialScanOnchain(birthdayHeight:)` on import** — recovers onchain
  history from a previous incarnation of the seed; `sync()` never finds it.
  Needs a "scanning" import UI state + on-device verify. (Relates to the
  Tier 0 claimed-exit-funds item.)
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
- [ ] **0.25: `ExitClaimTransaction` included-ids gap** — skips unclaimable
  ids silently, so `recordClaim` links every *requested* id. Asked upstream
  (feedback §1.3 addendum); no app workaround planned.
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
- [ ] **Explicit daemon start is redundant and logs a bark error**: bark
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
- [ ] **Move relay to DigitalOcean**; **Arke.me domain?** (external).
- [ ] **`Data samples/` → `Data_Samples/`** (folder names were out of scope
  for the 2026-09-27 filename standardization).

### Tooling, CI and process

Moved out of Tier 1 "Release readiness" 2026-10-09: no user hits these;
they are the infrastructure `Development/Release_Train.md` assumes.

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
