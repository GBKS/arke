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
  the Done log when closed. Amendment DECIDED 2026-11-10: a trace-shaped
  entry with no history (no ticked sub-items, no superseded premises, no
  chronology) may run to about fifteen lines without a plan doc; anything
  longer, or anything carrying history, moves — and it moves by verbatim
  relocation, never by rewriting, so labels (CONFIRMED / PLAUSIBLE /
  PROPOSED / DECIDED + date), cross-links and "not verified" notes survive.
  Cite symbols (type, function, property) rather than `file:line`; line
  numbers rot within days. Christoph's Reminders app is capture-only; sweep
  it into this file at the end of a session. `python3
  Scripts/backlog_stats.py` prints the counts and flags ticked lines,
  entries over fifteen lines and long entries that carry history markers.
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

**Train 2** — opened 2026-10-25 with the bark 0.26 recovery release.

| Stage | Status |
|---|---|
| Decide | first cut DECIDED 2026-10-25 (recovery release, Track A / Track B); fee-cluster rulings 2026-10-27; the remaining picks are PROPOSED below |
| Build | 0.26 Track A built 2026-10-25; dependency bump (bark v0.26.1, bdk-swift 3.1.1, qrcode 28.1.0, BIP39 pinned) and the send-fee cluster in two batches built 2026-10-27 (`Features/Send_Fee_Quotes.md`) |
| Review | 0.26 Track A adversarial pass 2026-10-25; fee cluster two adversarial passes 2026-10-27, every confirmed finding fixed the same day, rework ledger updated |
| Device | 0.26 recovery scenarios (Christoph, before the upload); fee cluster device look 2026-10-27 (§8.8–8.9), two states unreachable on the phone and waived or left to their entries |
| Release | **build 26 shipped 2026-10-27**, the two diverged-wallet users informed. Next build (custom-server release): `/code-review` pass over `34bba59..HEAD` done 2026-11-04 at high effort, eight findings: four fixed the same day (Lightning Max returned a non-fitting probe, typed-amount precedence, import rollback left the bark handle open, resolver cancellation mapped to a failure; ledger rows), four filed (Tier 3 Send, Tier 3 Activity, Tier 4 Startup ×2). Owed before upload: device re-check of "backup from another server refused", build number bump |
| Soak | from 2026-10-27, Christoph's daily use |

Delivered from Train 1's deferral list: the Tier 1 gate on onchain sends at
the fee ceiling (DECIDED 2026-10-19; built as "Estimate unreliable" in the
fee row, device look waived 2026-10-27) and the Lightning half of the fee
row three-state. Also closed on the way: the blind shadow estimator (root
cause: it never persisted), send-all exceeding bark's balance, the pin-to-
tags Tier 0 item. Since the release: send onchain from the Payments
balance, built, reviewed and device-checked 2026-10-28
(`Features/Send_Onchain_From_Payments.md`), not yet in a build; recovery
phrase exposure (app-switcher and capture cover, hide toggle, QR text not
selectable, 180 s clipboard), device-checked 2026-10-29
(`Features/Recovery_Phrase_Exposure.md`), not yet in a build; Ark server
selection (cover-screen sheet, Default / Development / custom server),
built and reviewed 2026-10-29/30, committed and device-checked 2026-11-02
(`Features/Ark_Server_Selection.md`), not yet in a build; foreign-server
Ark address detection with the nothing-payable send form, built, twice
reviewed and device-checked 2026-11-04
(`Features/Foreign_Server_Ark_Address.md`), not yet in a build. These
four make the custom-server release (DECIDED 2026-11-04, Tier 0 does not
gate it).

**Picks for the rest of Train 2 — PROPOSED 2026-10-27, Christoph to
confirm:** his Lugano UI observations first, one per session; then either
the Tier 0 security pass (relay API token in the repo; the phrase
cover and clipboard landed 2026-10-29) or the exit-cost
estimate replacement via `estimateEmergencyExitFee` (Tier 1 Exits, DECIDED
2026-10-19). Still deferred from Train 1 and not yet picked: the rest of the
deletion cluster (four unprotected store writes, exit Live Activity on
demotion + dead `closeWallet()`, abort-after-unregister), clusters 3, 5 and
6, the remainder of cluster 4, and the exploration-season ruling.

**Past trains:** Train 1 — opened 2026-10-08, build 25 frozen and shipped 2026-10-21 (mainnet fee ceiling, cosmetic pass, loading wave, part of the deletion cluster), soaked at Plan B Forum Lugano from 2026-10-22; Decide took two days, Build ten, Review and Device ran per cluster during Build, Release the day of the freeze. Its full block is archived in the Done log.

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
  `Backups/db.sqlite` slot per iCloud account; `restoreWalletIfNeeded`
  (primary only) replaces the local database whenever the backup is newer,
  with nothing tying it to a wallet hash or sequence number. Fix: bind each
  backup to the wallet hash and a monotonic counter and refuse mismatches.
  Possible field case (2026-10-10, unconfirmed): the divergence incident
  below. Evidence and the closed journal question: `Features/Backup_Restore.md`.
- [ ] **Claimed exit funds invisible after seed import** (network-verified
  2026-08-13: 8,839 sats at the claim address, absent from the balance).
  `ExitClaimSequence.run` reveals a fresh address first on every claim
  attempt and `ExitProgressionService` retries, so failed claims burn
  derivation indexes past both gap-10 import scans; claim addresses bypass
  `AddressService`. Mitigations (a)–(d), the test that pins address-first
  and the related adoption: `Features/Exit_Architecture.md` "Open gap".
- [ ] **Wallet state diverged from the server, and the app can neither see
  it nor say so** (mainnet field incident, build 24; reframed 2026-10-10:
  funds safe server-side, the wallet missed the mailbox message settling a
  refresh). The four app defects are closed (2026-10-11/12, Done log); open
  are the remedy (recovery from seed after the bindings bump), two owed
  answers and the field-log check. Plan: `Features/Wallet_State_Divergence.md`.
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
- [ ] **`checkReadOnlyMode()` infers primary**: a missing or unreadable
  device registration sets `isReadOnlyMode = false` (full spend rights,
  against Principle 2 / contract rule 15); sibling
  `shouldBlockWalletAccess()` answers `false` on an unreadable device ID.
  Reachability re-read 2026-11-12: self-unlink is no longer offered, but
  `unlinkDevice` from another device deletes the row and leaves this
  device's own primary flag, so an unlinked ex-primary lands here (S4).
  Traced 2026-11-12: on that relaunch every layer of `shouldBlockWalletAccess`
  passes and the wallet opens with spend rights for the whole session; the
  secondary row `registerDeviceIfNeeded` then writes makes only the *next*
  launch read-only. Fix shape: unknown = read-only until the registry
  answers. UNVERIFIED on device: unlink from device B, relaunch A once and
  check that first session, since the second launch looks fixed. Trace,
  sibling and the folded `device_<id>_isPrimary` key:
  `Features/Read_Only_Mode.md`; `Development/Contract_Audit_2026_11.md` A.1.
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
  evidence** (found 2026-10-16, pre-existing): `performDeleteWalletData`
  unregisters first, so a CloudKit or keychain throw leaves the wallet
  working with no registration until the next cold launch; another device
  is then offered the full wipe. PROPOSED fix: move Step 1 after the
  CloudKit step, before the keychain step; re-anchor the refresh-gate
  tests' proof. Detail: `Features/Wallet_Deletion_Ghost_Hardening.md` §7.
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
- [ ] **`RelayAPIToken` is checked into the repo**: the 64-hex value sits in
  `ArkeMobile/Info.plist:15-16` (tracked, in history since 9c4a5a2) and is
  read at `WalletManager.swift:430`; no xcconfig exists, tracked or not. The
  relay reads `RELAY_API_TOKEN` from its environment and its guard comment
  acknowledges the token ships in the app. Whatever the injection mechanism
  (untracked xcconfig, build-phase injection, per-device relay auth), the
  token has to be **rotated** on the relay as well, since history keeps it.
- [ ] **Desktop recovery phrase exposure** (parked with desktop): macOS
  `copySecretToClipboard` uses the plain pasteboard with no expiry
  (`org.nspasteboard.ConcealedType` + delayed clear, **assumed** convention,
  unverified with Universal Clipboard); `PhraseExposureCover` is a no-op on
  macOS; desktop Send logs clipboard content on every `didBecomeKey`
  (`SendViewModel+Clipboard`). Detail in the Done log, 2026-10-29.
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
- [ ] **Background runs killed for holding a store lock (0xdead10cc)** — all
  six Arké crash reports found 2026-11-02 (TestFlight builds 21–26 plus
  Christoph's phone) are this kill; the Organizer signature names are noise.
  Crash-proven unwrapped writers: the balance persist in
  `BalanceService.updateArkBalanceFromResponse`, and CloudKit's own mirroring
  export. Still unaudited: `unregisterCurrentDevice`,
  `refreshTransactionsAfterWrite`, `TransactionService.processSingleMovement`.
  Evidence: `Features/Background_Execution.md` §4, 2026-11-02 block.
- [ ] **`Arke_mobile.init` does the full store, CloudKit and bark setup on
  system-initiated launches** — three of the six 0xdead10cc kills came
  0.8–2.2 s after a launch with role "unknown" (prewarm or push), thread 0
  still in `SwiftDataHelper.createModelContainer` or `BarkWalletFFI.init`
  while CoreData's CloudKit migrator held the store. PROPOSED fix direction:
  detect `ActivePrewarm` / a background launch and defer the heavy init, or
  hold a task assertion across it. Evidence: `Features/Background_Execution.md` §4.
- [ ] **Failed boards leave onchain coins stranded on bark 0.7.1** — upstream
  `f85ca92ac` ships in bark 0.8.0 (bindings v0.26.0), so this becomes a
  Tier 2 verification once build 26 is on a phone (**derived** from the
  commit message, not reproduced). Still app-side: pass `ArkInfo.maxVtxoAmount`
  into `BoardingModalFormView` and refuse client-side (the server rejects
  above it since `8fab49706`); disable boarding while the server is
  unreachable (Tier 1 offline list). Evidence: `Features/Board_And_Offboard.md`.

- [ ] **A device-ID keychain read failure makes the delete override appear**
  — `otherDeviceReport` calls `getOrCreateDeviceId()` before reading either
  registry, so the 2026-10-16 throw-on-read-failure guard aborts with no
  evidence; `assessDeletion` maps that to `.undetermined` (nil report) and
  `shouldOfferOverride` answers true. CONFIRMED by trace, code-review
  2026-10-21; low likelihood (device unlocked, override still needs the
  acknowledgement + phrase). Fix: read both stores with an unknown own id.

## Tier 1 — What users hit every day

### Send and fees

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
  `estimateEmergencyExitFee`** (DECIDED 2026-10-19, Train 2 Tier 1,
  Christoph: "do it"; replaces `ExitView_iOS.calculateExitCost`). Premises
  rewritten at bark 0.8.0: compare `exitBroadcastFeeSats` (margin included)
  against the confirmed onchain balance; `fundable` deprecated. Error rule
  DECIDED: a thrown estimate never blocks the exit. Build steps, fee-rate
  rule, sibling sites and the 0.7.1 record: `Features/Exit_Cost_Estimate.md`.

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
  `buildExistingTransactionDictionary`): a repeated txid is deleted and
  saved on both upsert paths; the row is CloudKit-mirrored and cascades to
  tag and contact assignments, against contract rule 23. Sources (a)
  notification/full-list interleave (PLAUSIBLE), (b) two-device merge. Fix
  shape, settling test: `Features/Transaction_Upsert_Duplicates.md`.
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

- [ ] **The regular wallet open relies on the bindings' `createIfNotExists: true`
  default** (`WalletOpenArgs` in `BarkWalletFFI+WalletLifecycle`
  `tryOpenExistingWallet`): with a schema-only or missing `db.sqlite` plus a
  keychain mnemonic, the launch open *creates* a wallet instead of failing,
  the recreate-from-seed contract rule 3 forbids. Moved from Tier 4 on
  2026-11-12: the guard in `tryOpenExistingWallet` tests directory existence
  and `BarkWalletFFI.getWalletDirectory()` creates the directory in every
  init, so a missing database reaches the create on any device that ran
  once (read, not run). Pre-existing, surfaced by the 2026-10-29 adversarial
  pass on `Features/Ark_Server_Selection.md`. Pass `createIfNotExists: false`
  there and decide what the error path shows. `Development/Contract_Audit_2026_11.md` A.4.

### Multi-device (guiding doc: `Architecture/Multi_Device_Design.md`)

- [ ] **CloudKit Production schema was never deployed — no TestFlight build
  has ever synced a SwiftData row** (found 2026-10-26 in the Console:
  Production holds only `Users`, Development every `CD_` type). Remedy:
  Christoph deploys once ("Deploy Schema Changes…"), then watches for
  duplicate default tags / contacts as his TestFlight devices merge; the
  Tier 2 two-device checklist needs one TestFlight run after. Consequences
  and the process fix: `Architecture/CloudKit_Realtime_Sync.md` "Production schema".

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
- [ ] **A device without the seed can be promoted to primary** (tier
  DECIDED 2026-11-12): the promote button in `LinkedDevicesView_iOS` and
  `promoteThisDeviceToPrimary` check only "not primary" and "no other
  primary", never the mnemonic; the device then runs
  `initialize(forceReadOnly: false)` into the seed-missing branch. The
  capability matrix says "needs seed first". Read from code, not run. `Development/Contract_Audit_2026_11.md` A.2.
- [ ] **S3 swap and S4 lost-primary flows differ from the code**: promotion
  is refused while a primary row is visible and no device writes another's
  primary flag, so S3 is really demote-then-promote and S4
  unlink-then-promote. DECIDED 2026-11-12: not ruled on its own; it becomes
  a guided step-by-step swap designed in the explicit device linking scope
  pass (`Architecture/Multi_Device_Design.md`, "Open questions"). Needs the
  Tier 0 `checkReadOnlyMode()` fix and the seed check before promotion
  first. `Development/Contract_Audit_2026_11.md` A.3.

### Connectivity and offline

- [ ] **The activity screen shows "no Ark connection" for the whole launch
  refresh although the server answered in 1 s** (2026-10-12; DECIDED
  2026-10-12 Train 1; built the same day: Step 1 success now calls
  `updateConnectionStatus(connected: true)`, `refreshServer()` returns its
  outcome; adversarial pass found the early write sound, no unit test
  possible without a mid-refresh harness). Device check owed: one launch,
  icon must not appear. Build and review record: `Features/Offline_Experience.md`.
- [ ] **Ark data waits for the onchain sync on every refresh** (DECIDED
  2026-10-14, Tier 1, Train 1; BUILT and REVIEWED the same day: `syncArk()`
  / `syncOnchain()`, Steps 2a/2b/2c, balance published per side). First
  field result 2026-10-14 17:53: Ark data on screen 0.36 s into a
  pull-to-refresh, before the onchain sync. Still owed: one unattached cold
  launch with a mailbox payment waiting (needs the export fix or Console.app).
  Plan, review record and the entry's trace: `Features/Launch_Ark_First_Refresh.md`.
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
  (CONFIRMED by the 2026-10-12 adversarial pass, pre-existing): bark's
  `sync()` returns `()` and the FFI wrapper `Ok(())` unconditionally, so
  `anyServerCallSucceeded` is true for every refresh reaching Step 2 and
  Step 4 always writes connected. Fix shape: only Step 1's handshake counts;
  decide the retry cadence with it. Build this first, the offline feature
  below assumes the signal works. Trace: `Features/Offline_Experience.md`.
- [ ] **Offline / server-down experience** (one feature, merged from eight
  Reminders items): design the states (offline vs server down vs
  connecting), decide what each disables (boarding while unreachable, send
  offline), classify the reason, build. In scope since the 2026-10-10
  operator-dependence ruling: unilateral exit must stay reachable with
  Second's chain source down (fallback Esplora per network, a trust call).
  Item list, what exists today, related dead code: `Features/Offline_Experience.md`.
- [ ] **Invoice request timeout**: unknown how long `getLightningInvoice`
  takes to fail with no connectivity (bark's timeout, unmeasured). If minutes,
  users give up before Try Again / Share Addresses Instead appear. Measure
  under 100% Loss, decide an app timeout, device-verify the failure path.
- [ ] **Invoice creation polish**: "Slow connection, still trying…" after
  ~5 s; say "offline" right away when the wallet knows; VoiceOver
  announcement for "Creating invoice".
- [ ] **A stuck Lightning receive is invisible, and cannot be cancelled or
  exited**: the app has no claim loop (`LightningClaimService` disabled
  since a894888, 2026-04-10); bark's own `sync()` claims receives and only
  warn-logs failures, so the app sees neither state nor error. Decide
  delete-or-revive for the service, then surface pending receives with
  state, show a repeating claim error, offer cancel / exit. Pair with
  "Invoice request timeout" above. Trace: `Features/Lightning_Receive_State.md`.

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
- [ ] **OS `bitcoin:` URI scheme registration**: no `CFBundleURLSchemes` in
  the mobile Info.plist or the generated desktop plist, and no `onOpenURL` /
  `openURLContexts` handler anywhere, so the work is registration plus
  routing into Send. Also test the macOS Shortcuts integration (only the
  widget has App Intents).

## Tier 2 — Verification debt (shipped, never confirmed)

Cheap to clear in a dedicated device session; expensive to carry. Each item
names the fix it verifies; the write-ups are in the Done log.

### Two-device

- [ ] **Backup import rolled back for a server mismatch leaves the FFI handle
  open on an unlinked database** (`WalletManager.importWalletWithBackup`
  → `BarkErrorArke.backupBelongsToAnotherServer`; same shape as the older
  network-mismatch rollback). A retry runs `shutdownWallet()` first, which
  syncs and backs up against the mismatched server. Settle on device: import
  a Second backup with a custom server selected, then retry with Second.
  Found by the second adversarial pass 2026-10-30 (R6),
  `Features/Ark_Server_Selection.md` §7.

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
  (2026-10-14; CONFIRMED by the `OSLogType` docs: info-level entries live
  in a purged memory buffer, the noisy launch is what gets evicted). Fix
  built 2026-10-14 (DECIDED): the twenty launch-skeleton lines log at
  notice; the header lists entries per level. Device check owed: one export
  after a cold launch must show the `Step 1`…`Step 4` markers. Ring-buffer
  mirror stays the follow-up. Evidence: `Features/Debug_Log_Export.md`.
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

- [ ] **The selected row can vanish from the "Pay from" ranking on a typed
  amount** (release review 2026-11-04, PLAUSIBLE): `oneRowPerBalance` runs
  on every re-rank, so when the selected Lightning row turns unviable for
  the amount while its Payments-onchain twin is judged viable, the twin
  takes the Payments slot and `selectedChoice` points at a dropped row; the
  fee row and gate still follow the old selection. PROPOSED rule: the
  selected choice survives the reducer. `PaymentDestinationSelector`.
- [ ] **Four sheets title themselves in the navigation bar (sans-serif)** while
  the app's modals put a serif title in the content (speed sheet, boarding
  and offboarding modals, settings pages): `TagSelectorSheet` ("Choose
  Tags"), `ContactImportSheet`, the assign-contact sheet in
  `SendMetadataSection`, `DeviceAssignmentSheets_iOS`. Found 2026-10-28
  while fixing the "Pay from" sheet; same two-line change each.
- [ ] **PROPOSED: the funding source lives in the amount card, not the
  recipient card.** The "Pay from" control sits inside the recipient card
  (`SheetDestinationDisplayView`); the amount card's balance row already
  names the source. Recipient card = who, amount card = from where. Tier 3:
  "Pay from Savings" caption fixes the misread for now.
  `Features/Send_Onchain_From_Payments.md` §9.2.
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
  resolved address in the send view; actually resolve and test. Unblocked
  2026-10-29: BIP-353 names resolve again (`Features/BIP353_DNSSEC.md`), so
  the `user@domain` race in `tryParallelResolution` is now live (review F6).
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
- [ ] **Onchain receives do not play the received-payment sound** (filed
  2026-11-07): `ReceivePaymentFeedbackModifier` listens to bark's movement
  stream, which carries Ark and Lightning receives only. A payment to the
  onchain address shown on the Receive tab surfaces when a refresh pulls it
  from the BDK wallet, so there is no event to chime on. Needs a
  new-incoming-onchain signal from `OnchainTransactionService`.

- [ ] **QR brightness: `boost()` during a restore ramp saves the mid-ramp
  level** — `ScreenBrightnessBooster.boost` reads `screen.brightness` while a
  `restore()` ramp is still stepping (scene phase inactive → active within the
  ramp), so the final restore lands near full. CONFIRMED by reading,
  code-review 2026-10-21; remember the ramp target as the user level.

### Activity, transaction details, tags

- [ ] **Struck-through failed/cancelled amounts are decided in three views**
  (release review 2026-11-04): `isAmountStruckThrough` and the grey colour
  rule are repeated in `TransactionListItem`, `TransactionSwipeCard` and
  `TransactionDetailView_iOS`, and already diverge (only the card carries
  the dark colour-scheme workaround). One property on `TransactionModel`.
- [ ] **Activity rows are dated by when the wallet processed the movement,
  not when it happened** (Christoph, 2026-10-19). Traced: (c) no re-dating
  on refresh (executed at bark 0.7.1, `settledDateIgnoresUpdatedAt`); (a)
  onchain rows already take the block time; (b) the server-side arrival time
  is on the wire as the mailbox checkpoint and bark drops it. DECIDED
  2026-10-19: upstream ask `Bark_Bindings_Feedback.md` §1.10 / ask 20; stays
  open as the adoption item. Trace: `Features/Activity_Row_Dating.md`.
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
- [ ] **Onboard modal**: add fee info; success message with duration; test
  the error state. **Offboard modal**: add fee info; add data to success
  (claim required?); test the error state. **Boarding**: calculate and
  display the network fee; adjust the amount input to the unit setting;
  offboard takes a long time. (The "minimum only after X-Ray" half closed
  2026-10-19, Done log; its device check is owed with the image line below.)
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
- [ ] **`RefreshModalView` lacks the `isInitialized` reload hook** (contract
  rule 7b): it owns a `BalanceRefreshStatusViewModel` and loads once in
  `.task`, so opened before the wallet handle is set it stays empty. Low
  exposure, user-opened modal. `Development/Contract_Audit_2026_11.md` A.9.

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
- [ ] **Check-in reminders armed on `isActive`, not `isInFlight`**:
  `NotificationsSettingView_iOS` schedules the sequence when any exit
  `isActive` (cancelled ones included), and `userCheckedIn` re-arms without
  an in-flight check; its foreground gate `hasActiveExits()` only tests
  whether a Live Activity exists. Contract rules 9 and 13 require
  `isInFlight`. Cleared by the next launch or backgrounding pass. `Development/Contract_Audit_2026_11.md` A.6.

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
- [ ] **Delete wallet with an exit in flight shows no funds warning** — nor
  for an open Lightning invoice or a pending board (the 0.26 user procedure
  says wait these out, `Migrations/Bark-0.25.0-to-0.26.0/03-impact-analysis.md`
  §3b). PLAUSIBLE from the 2026-10-13 forfeit-warning review, Tier 3
  confirmed by Christoph 2026-10-14. Settle first whether an unclaimed exit
  survives deletion (bark `exit/` claim prerequisites), then a third copy or
  nothing. Trace: `Features/Wallet_Deletion_And_Rejoin.md` "Open: in flight".
- [ ] **Savings deposits don't show up automatically** — note in the
  notifications explainer until Background Execution Phase 2 (Tier 4) lands.
- [ ] **Network mismatch on import**: importing a signet wallet in the
  mainnet flow shows an ugly overlay. Optional self-heal: bark's db knows
  its own network — on a mismatch open failure, derive the config from the
  db instead of the stored setting (needs a bindings check for reading the
  db network without a chain source); the overlay copy is the fallback when
  self-heal is not possible (two lines merged 2026-10-09).
- [ ] **Linked Devices reads the registry itself** (contract rule 24 (a)):
  both platform views take only `mirrorOnly` from `otherDeviceReport` and
  build the row list from `registeredDevices` without the 30-day filter, so
  a stale row is listed but is not a blocker; and `checkForPrimaryDevice`
  calls `getPrimaryDevice()` unscoped while `checkForNoPrimaryDevice` is
  wallet-scoped. `Development/Contract_Audit_2026_11.md` A.10–11.
- [ ] **DECIDE — recovery phrase on a seed-synced secondary**: the matrix
  says ✓, but the Settings entry is hidden whenever `isReadOnlyMode`
  (`SettingsView_iOS`, desktop `SettingsView`). Fix the row or show the
  entry when the seed is present. `Development/Contract_Audit_2026_11.md` C.

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
  down from Tier 0 2026-10-09: `MnemonicChecksumTests` shows bark rejects a
  bad checksum or unknown word before any network I/O). Fix: call the
  binding's `validateMnemonic(mnemonic:)` in `SecurityService.isValidBIP39`
  (word count only today), show "phrase has a typo" before the import UI
  starts, delete the two dead checksum-TODO validators. Also closes the
  seed-written-before-bark-sees-it window. Detail: `Features/BIP39.md` "Open".

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
- [ ] **`unregisterCurrentDevice` can throw before the mirror clear**:
  `getOrCreateDeviceId()` still precedes `removeMirrorEntries`, the one
  fallible step left ahead of it (contract rule 24 (d)); the cleanup
  service records it as `.failed`. `Development/Contract_Audit_2026_11.md` A.7.
- [ ] **Rule 23 sweep: multi-row deletes outside the cleanup service**:
  `TransactionService.cleanupOldPendingMetadata` (age-based, a mirrored
  model), the dedups `dedupeOwnRecords`,
  `buildExistingTransactionDictionary` (duplicate-txid rows, every upsert)
  and `BackupStatus.getSingleton`, the dead
  `OnchainTransactionService.clearPersistedTransactions` and
  `SwiftDataHelper.cleanupDuplicateBackupStatus`, and `TagService.deleteAllTags`
  whose comment claims a deletion-path use it does not have. Rule each as
  exempt or fix. `Development/Contract_Audit_2026_11.md` A.8.
- [ ] **Stale comments repeat "unlink needs a row / iOS menu hidden"**:
  doc comments on `unregisterCurrentDevice`, `otherDeviceReport`,
  `OtherDeviceReport.mirrorOnly`, `shouldOfferOverride`,
  `deviceUnregistrationRecord`, the `rowRetained` case, and the desktop
  `LinkedDevicesView` mirror-only comment. `Development/Contract_Audit_2026_11.md` A.13.

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
- [ ] **PROPOSAL (2026-10-29) — BIP-353 validation through bark-ffi**: the
  reference DNSSEC validator `dnssec-prover` is already linked into the app
  (bark → LDK `lightning` 0.2.2 → `dnssec-prover` 0.6.8, verified in the
  bindings' lock file) but not exposed. One bark-ffi function resolving a
  BIP-353 name with a verified proof would close the documented deviation
  in `Features/BIP353_DNSSEC.md` §4 as a new `DNSTXTSource`. Ask Second.
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

- [ ] **Network config iCloud sync writes before the reconciler decides**
  (release review 2026-11-04): `syncFromiCloud` overwrites the local cache
  with the account's config, then the `.keepCurrent` branch of
  `reconcileNetworkConfigBeforeWalletOpen` writes this device's config
  back, on every launch and wake (error log, cache churn, a sync
  notification each time). Make the sync pure and let the reconciler write
  once. `WalletManager.swift`, `NetworkConfigPersistence`.
- [ ] **Three debounced fee tasks live in static dictionaries keyed by
  `ObjectIdentifier`** (release review 2026-11-04): onchain, Lightning and
  offboard estimation each keep a `static var …TaskStorage`, entries are
  never removed and an identifier can be reused by a later view model.
  Replace with stored properties on `SendViewModel`.
  `SendViewModel+FeeEstimation`, `SendViewModel+FeeCalculation`.
- [ ] **`OnchainTransactionEntity` persistence is dead code**: the model
  (`Shared/Models/OnchainTransactionEntity.swift`) is not in the schema
  (`SwiftDataHelper.swift:49` lists `PersistentTransaction` only), so
  `OnchainTransactionService.persistTransactions` / `loadPersistedTransactions`
  / `clearPersistedTransactions` throw into a `print` on every refresh and
  launch. Found 2026-10-14 while fixing the onchain reset (the reset no longer
  calls the clear). Delete the three methods and the model, or register the
  model if the cache across launches is wanted.

- [ ] **Field cold launches run 10–20 s, one at 74 s** (mainnet user journal
  2026-10-04..09). Long pole answered 2026-10-12 on Christoph's phone: about
  25 of 27.7 s are Esplora/BDK syncs run twice per launch; the call→execute
  gap is a debugger artefact. What stays here: one onchain sync per refresh
  instead of two (DECIDED 2026-10-12 Train 2, needs its own design pass
  because the second sync is the balance-overcount guard) and the
  "Ark-fresh ends the wave" revisit (DECIDED 2026-10-14: wait). `Initialization/Launch_Performance.md`.
- [ ] **Explicit daemon start is redundant and logs a bark error** (B6
  re-verified at bark 0.8.0, 2026-10-25): `Wallet::open` starts the daemon
  when `WalletOpenArgs.runDaemon` is set, and the Swift default is `true`, so
  `initializePrimaryMode`'s `runDaemon()` logs "already running" at error
  level on every launch while the wrapper claims success. Fix: drop or guard
  the launch call, or open with `runDaemon: false`; check create/import and
  post-`stopDaemonWait` paths. Detail: `Initialization/Launch_Performance.md`.
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
- [ ] **Contract rule 25 is narrower in code than its title**:
  `BarkWalletFFI.getWalletDirectory()` still creates the directory and runs
  the `.test` write probe inside init when the directory is missing, and
  `withBackgroundActivityAssertion` wraps two call sites only
  (`updateHeartbeat` and `unregisterCurrentDevice` saves are bare). `Development/Contract_Audit_2026_11.md` A.12.

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
Re-inventoried 2026-11-01 as Track 1 of `Features/MCP_Server.md`; the seven
batches and the porting rules (`Development/Platform_Porting_Rules.md`) are
PROPOSED, not scheduled.

- [ ] Exit UI; notifications; promote/demote UI (S3); read-only mode for
  `TransactionList`; embed `CurrencySettingView` next to `ThemeSettingView`
  (one line, the view is Shared); the never-cleared banner in
  `ActivityView.swift`. Folded into Batches 3–7 of the parity doc.
- [ ] **Desktop quick-mode send misses the view model** (found 2026-11-01):
  `SendView.quickModeView` does not pass `sendViewModel:` as
  `SendView_iOS` does, so `QuickPaymentView` falls back to its load-time
  ranking and has no fiat entry. One argument; Batch 4 in the parity doc.
- [ ] **Desktop `MainView` lifecycle gaps** (confirmed 2026-11-01): no
  foreground re-check, no protected-data re-check, `onWalletDeleted` does
  not stop CloudKit sync or deactivate services, none of the scene-phase
  foreground work. Batch 2 in the parity doc; gates MCP Track 2.

### Agents (`Features/MCP_Server.md`)

- [ ] **MCP server, Track 2** (PARKED 2026-11-01, shape DECIDED): official
  Swift SDK inside the app over loopback HTTP, `.mcpb` shim for Claude
  Desktop, seed-keyed local link first then CloudKit, no hosted connector.
  Prerequisites: `WalletBootstrapper` out of both `MainView.task`s; a
  payment executor pulled out of `SendViewModel`. Starts after desktop
  parity completes; two spikes and a doc review first.
- [ ] **Siri AI and App Intents** (PROPOSED 2026-11-04, behind desktop
  parity): read entities and intents, invoice with `Transferable`, a
  payment draft that ends on the confirmation screen, one `SKILL.md`.
  DECIDED 2026-11-04: history goes into the Spotlight index (to be felt
  out), Mac first on a second APFS volume with the 27.3 beta, no spike
  before parity. Same two prerequisites as MCP Track 2. Plan:
  `Features/Siri_And_App_Intents.md`.

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
  transactions (metadata export covers part of this). macOS Shortcuts folded
  into `Features/Siri_And_App_Intents.md` on 2026-11-04.

Moved from Tier 3 on 2026-10-19 as ideas, not scheduled work:

- [ ] **Parse Cashu NUT-18 `creq` parameter** (idea).
- [ ] **Drain wallet option** (Settings).
- [ ] **Restyle the contact view; invite-friends feature (no fees between
  Arké users)**.
- [ ] **Move relay to DigitalOcean**; **Arke.me domain?** (external).
- [ ] **Switch send button to a slider for larger amounts**.
- [ ] **"Payment sounds" toggle in Settings › General** — deferred
  2026-11-07 until users ask; the ring switch already silences
  `PaymentFeedback`, haptics stay on regardless.
