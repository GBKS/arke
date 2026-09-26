# Open Follow-Ups

Cross-feature list of known open items so nothing gets lost between sessions.
Detail lives in the linked docs — this file is just the index. When an item is
finished, check it off with the date (move to a Done section or delete once
stale). Last consolidated: 2026-08-12.

## Localization

- [ ] **Native-speaker review of the de/ja first pass** (all 1,090 × 2 values are
  `needs_review`, translated 2026-08-18): start with the glossary's ⚠️ terms
  (Übertrag, Rechnung, Hauptgerät/Zweitgerät); filter by "Needs Review" in
  Xcode's catalog editor or export `.xcloc`. Required before shipping the
  languages. See `Localization/Translation_Rollout_Plan.md`.
- [ ] **Phase D per-language QA**: run with App Language de (the +30% expansion
  layout pass — badges, fixed-width buttons, alerts) and ja (typography), plus
  guard test + full suite. See the rollout plan. Now also covers zh-Hant
  (CJK/Latin spacing, line breaking).
- [ ] **Native-speaker review of the zh-Hant first pass** (1,088 values,
  `needs_review`, translated 2026-08-23 for the Hong Kong conference demo):
  ⚠️ terms first — 聰 vs "sats", 復原片語 vs community 助記詞, 付款請求,
  轉入/轉出 — plus the app-wide 拷貝/剪貼板 vs 複製/剪貼簿 pair. See the
  zh-Hant section of `Localization/Translation_Rollout_Plan.md`.
- [x] **zh-Hant in `knownRegions` — done 2026-08-23** (user, in Xcode);
  verified: build green, `zh-Hant.lproj` present in ArkeMobile.app, the ArkéUI
  bundle, and the widgets extension.
- [x] **defaultValue migration — on-device smoke pass — verified 2026-08-17**
  (iPhone + macOS, no raw-key sightings). The desktop build's extraction also
  exposed one last hand-assembled plural in
  `TransactionLinkedOnchainView_macOS` — fixed with `^[…](inflect: true)`.
  Migration fully complete; see `Localization/Default_Value_Migration_Plan.md`.

## Multi-Device (guiding doc: `Architecture/Multi_Device_Design.md`)

Status 2026-08-19: S10 DECIDED (read-only + explain). S7 blocking, the S5
assistant sketch, and the security-check matrix are PROPOSALS in the doc
awaiting Christoph's call — the items below assume acceptance:

- [ ] **Security checks first**: switch `authenticateUser` to
  `.deviceOwnerAuthentication` (passcode fallback; biometrics-only hard-fails
  on Macs without Touch ID) and wire the gated-actions table (recovery
  phrase, deletions, promote/demote/unlink; send as opt-in setting). Its only
  call site is currently commented out — nothing is gated today.
- [ ] **S7 build — active devices block full wipe**: blockers list with
  unlink-first paths, informed "delete anyway" override behind the security
  check, "wallet deleted elsewhere" cleanup-offer state on surviving devices.
  (The `getDeletionStrategy()` fallback part landed early and separately on
  2026-09-21 — see Wallet Deletion & Device Registry. The override valve is
  now load-bearing: KVS ghosts block indefinitely, with no staleness cutoff.)
- [ ] **S5 build — migration assistant**: orchestration + copy over existing
  primitives (S2 join → promote → S6 retire), entry points on both devices;
  DELETE `migrateToThisDevice()` (writes `isPrimaryDevice` without
  `becamePrimaryAt`, breaking the reconciliation tiebreak).
- [ ] **S10 build**: read-only reasons for signed-out / account-changed +
  safe-exit copy (sign back in, or local-only delete). Never auto-wipe,
  never pair local files with a foreign account.
- [ ] **Desktop parity for promote/demote UI** (S3; unlink already exists on
  both platforms).
- [ ] **PROPOSED — "new device joined your wallet" notification** (failure
  modes §C): visibility mitigation for iCloud-account compromise; also
  honest-flow feedback for S2/S5.
- [ ] **PROPOSED — phrase-confirmation on full wipe** (failure modes §A):
  final "Delete everything" asks for two recovery-phrase words — consent +
  backup-existence proof before destroying the last seed copies.
- [x] **Device-backup-twin identity problem — DROPPED 2026-09-21**, premise
  was wrong: the device-ID item is `WhenUnlockedThisDeviceOnly`, and Apple
  documents that such items do not migrate to a new device (absent after
  restoring another device's backup). A restored device generates a fresh ID
  and registers as a new device — an ordinary S11 ghost, not a shared
  identity. No liveness nonce needed.
- [x] **Read-only devices never re-read their synced data — FIXED
  2026-09-23**: `ReadOnlyBalanceService` / `ReadOnlyAddressService` read the
  CloudKit-synced rows once at init, which on a fresh install happens *before*
  the first import lands, so the second iPhone showed a 0 balance and an empty
  receive address for the whole session (correct after a relaunch).
  `ReadOnlyBalanceService.refreshBalances()` had no callers at all, and
  `WalletManager.refreshBalances()` forwarded only to the primary
  `balanceService`. Both services now observe `cloudKitDataDidChange` (the
  `DeviceRegistrationService` pattern), `refreshBalances()` is routed by mode,
  and `performRefresh()` short-circuits in read-only mode to re-read synced
  data instead of running server work that can only fail. The balance
  singletons also resolve newest-first, since CloudKit forbids the unique
  constraint that would keep `ark_balance` single. `ReadOnlySyncedDataTests`.
  Still needs the two-device on-device verify (below).
- [ ] **On-device verify on the second iPhone**: with the app already running,
  move funds on the primary and confirm the secondary's balance updates without
  a relaunch; check the receive screen shows an address; pull-to-refresh leaves
  no error banner. Then reinstall on the secondary and confirm it ends up with
  9 tags and 1 faucet contact, not 18 and 3.
  Partial field evidence 2026-09-23: after a reinstall the balance and activity
  appeared later in the same session without a relaunch, which is the observer
  doing its job — confirm in the log that
  `Loaded Ark balance from CloudKit (spendable: …)` follows a
  `[CloudKit] Remote change detected` round.
- [ ] **A payment on the primary does not promptly update the secondary's
  balance**, while tags and activity do. Narrowed 2026-09-23: tags edited *on
  the primary* appeared on the secondary immediately, so
  `cloudKitDataDidChange` fired and `ReadOnlyBalanceService.refreshBalances()`
  ran in that same round — the re-read is not the problem. One hypothesis is
  already disproved: it is not a stale registered object, because a
  cross-context in-place row update *is* visible to the re-fetch
  (`ReadOnlySyncedDataTests/balancePicksUpInPlaceUpdate`). That leaves the
  write/export side — either the primary did not persist a balance update at
  that moment or the record was not in that export. Evidence needed: the
  primary's log around the payment (does `💾 Updated persisted Ark balance`
  appear?) paired with the secondary's
  `📱 Loaded Ark balance from CloudKit (spendable: N)` — N says what the store
  actually held. Check the rapid-fire item below at the same time.
- [x] **`CloudKitObserver` dropped remote-change notifications instead of
  deferring them — FIXED 2026-09-24**: the publisher already spaces emissions
  ≥1.5s apart via `debounce`, and `handleRemoteChange` then returned early for
  anything arriving within `minimumChangeInterval` (2.0s) of the last handled
  one — with no re-schedule. Since debounce only emits after 1.5s of quiet, the
  whole 1.5–2.0s band was live and routinely hit, and those batches were
  discarded until some later, unrelated change. `@Query`-backed UI was
  unaffected (it observes the store directly); anything refreshed *only* by
  `cloudKitDataDidChange` inherited the hole — most of the read-only path.
  Now the decision is the pure `RemoteChangeThrottle.decide(...)`
  (handle now / defer by the remainder / fold into an already-pending
  deferral), pinned by `RemoteChangeThrottleTests` (8 cases, including the
  1.5–2.0s band, the coalesce, and a backwards clock jump). New tells:
  `⏳ [CloudKit] Rapid-fire notification deferred …s` and
  `🔁 … folded into the pending deferred refresh`; the old
  `⏭️ Ignoring rapid-fire notification` line is gone, so its presence in a log
  means an old build.

  This is a **candidate cause of the balance item below** — not a confirmed
  one. It explains the exact shape (tags via `@Query` updated, balance via
  notification didn't), but the write side was never ruled out, so keep
  collecting the paired log lines.
- [x] **A freshly installed secondary showed an empty wallet with no
  explanation — FIXED 2026-09-24** for the activity list: over a minute
  observed 2026-09-23, and it reads as "the wallet is broken".
  `ReadOnlyBalanceService.isWaitingForInitialSync` (neither balance row has
  arrived) now feeds `WalletManager.isWaitingForInitialCloudKitSync`, and
  `TransactionListEmptyState` gained a `.syncingFromCloud` context that takes
  precedence over the tag/contact filter contexts — with nothing synced,
  "no transactions in this tag" isn't a claim we can make either. Two new
  strings (`transaction_list_syncing_title`, `transaction_list_syncing_message`)
  on `defaultValue:`, so they need extraction + de/ja/zh-Hant like the rest.
  Remaining: the **balance card still reads 0** in that window (it renders a
  substituted zero-balance model); decide whether it gets the same treatment
  or stays quiet. Desktop's `TransactionList` takes the same component but was
  not wired — it has no read-only mode yet. Also remaining: the gate is
  balance-based, so a balance batch that lands before the transaction batch
  drops the syncing state early, and a primary that never persisted balance
  rows leaves it up indefinitely (no timeout); the honest upgrade is
  `NSPersistentCloudKitContainer`'s import events.
- [x] **Secondary devices seeded their own default tags and contacts — FIXED
  2026-09-23**: the seeding condition is "none exist", which is briefly true on
  a secondary device too (empty store until the first CloudKit import), so
  `initializeReadOnlyMode()` created its own 9 default tags and the faucet
  contact and then received the primary's — observed 18 tags and 3 contacts on
  the second iPhone. Seeding is now primary-only: guarded in
  `WalletManager.createDefaultTagsIfNeeded()` /
  `createDefaultContactsIfNeeded()` (so the TagsView "add default tags"
  shortcut can't do it either — that button is hidden on secondaries via
  `TagsViewModel.canAddDefaultTags`), and the calls are gone from read-only
  init. The avatar re-encode still runs on either kind of device: it repairs
  already-synced rows rather than creating data. No unit test —
  `WalletManager` has no test harness in this project — so this one rests on
  the on-device check below.
  **Superseded 2026-09-25 — the role-based guard was a half-fix** (review
  finding): the hazard is *store-not-yet-imported*, not device role, so a
  reinstalled PRIMARY (delete app → reinstall → import seed) still seeded
  duplicates before the account's originals imported. Seeding is now
  import-gated (contract rule 26): created wallets seed immediately (provably
  nothing to import), everything else waits for `CloudKitFirstImportGate`
  (first finished successful CloudKit import event; 90 s timeout) — decision
  pinned by `DefaultDataSeedingDecisionTests`, and the faucet contact gained
  insert-time store dedup as the timeout backstop. The role guards stay as
  defense in depth. On-device: the 2026-09-26 two-device session covered the
  deletion flow; the seeding scenarios were not separately reported, so they
  stay listed: (1) reinstalled primary →
  exactly 9 tags + 1 faucet + customs, gate-wait log line; (2) fresh account →
  seeds immediately, no 90 s wait; (3) reinstalled secondary → never seeds;
  (4) iCloud signed out + import → seeds after ~90 s timeout log
  (`log show --info --debug`, or the info lines vanish).
- [ ] **Clean up the duplicate defaults already in the account**: the second
  iPhone's extra 9 tags and 2 contacts are in CloudKit now. Needs a decision:
  hand-delete on a device, or a one-shot dedup by name that re-points tag and
  contact assignments before deleting the loser (`PersistentTag` has no unique
  constraint, so a merge has to move `tagAssignments` first). A post-import
  automatic merge was considered and deferred 2026-09-25: it means deleting
  CloudKit-mirrored rows outside `WalletDataCleanupService` — the exact fault
  class contract rule 23 forbids — and the losing copy may carry assignments;
  if ever built, it keeps the copy with assignments, migrates the rest, runs
  under cleanup-service ownership, behind explicit user action.
- [ ] **An account with no primary can never get default tags/contacts**
  (2026-09-25, consequence of primary-only seeding): if the primary dies
  before its seeds sync, no device seeds and `canAddDefaultTags` hides the
  manual button everywhere. Deliberately NOT patched by showing the button
  when no primary is visible — a registry that merely hasn't imported reads
  as "no primary" and would re-open the duplicate window. Fold the recovery
  into the planned active-no-primary banner/promote flow, which needs the
  same signal.

## Test Infrastructure

- [ ] **The macOS (`Arké`) test suite fails ~68 of 272 tests, and has for an
  unknown length of time** — measured 2026-09-22 on a clean tree, so it is
  pre-existing and unrelated to any current work. It is also **flaky, not
  deterministic**: two consecutive clean-tree runs shared 65 failures but each
  had 2-3 unique ones. The failing set spans nearly every suite
  (`AddressValidator`, `LightningInvoiceParser`, `TaskDeduplicationManager`,
  `ExitStore`, `MetadataImportService`, …) while iOS runs the same Shared
  tests 283/283 green, which points at shared mutable state across parallel
  macOS test hosts (keychain, UserDefaults, KVS) rather than 68 real bugs —
  `TombstonePersistenceTests` and `KeychainAccessibilityMigrationTests` both
  mutate process-wide state. Consequence: **desktop regressions are currently
  undetectable**, because a new failure can't be distinguished from the noise.
  Worth fixing before the desktop parity work (`.serialized` suites, or
  scratch-scoped keychain/defaults) — the current "ignore desktop" workflow
  hides this rather than costing nothing.

## Wallet Deletion & Device Registry

- [x] **Two-device on-device verify of the deletion override — DONE
  2026-09-26** (Christoph, two linked devices, against the 2026-09-25 build
  with the recency gate, pre-wipe recheck and seed-last ordering): the flow
  "works much better". Individual scenarios below were not reported
  one-by-one, so treat the checklist as passed-in-aggregate rather than
  ticked line by line.
- [ ] **Deletion-flow copywriting** (surfaced by the 2026-09-26 two-device
  session, cosmetic, deferred): the strategy intro, the blockers copy, the
  override acknowledgement and the new scope-changed banner
  (`error_delete_scope_changed`) read correctly but need a copy pass — and
  de/ja/zh-Hant for every key in the translation-debt list above once the
  English settles.
- [ ] **Ghost-device incident 2026-09-26 — four hardening follow-ups,
  deliberately deferred to ship first.** With three installs (two iPhones,
  a MacBook) the primary showed an "Unrecognized device" that outlived the
  other installs' deletions and, being younger than the 48h settle window,
  blocked the full wipe with no override (working as designed). The
  primary's log pinned the shape — registry: 1 row (self); mirror: 1 entry
  for another device ID — and it cleared through the intended remedy:
  rejoin on the ghost's device, in-app "Delete from This Device", wait for
  KVS propagation, relaunch the primary. Likeliest causes, in order: an
  install deleted from the home screen without an in-app delete first (its
  mirror entry survives by construction, and a later reinstall re-stamps it
  fresh); an in-app delete whose KVS removal never uploaded because the app
  was uninstalled right after (`synchronize()` only flushes to disk); or the
  mirror clear being skipped — in `unregisterCurrentDevice` it sits behind
  the `modelContext` guard, `getOrCreateDeviceId()` and the registry
  `save()`, and the cleanup service treats an unregister failure as
  non-fatal with a DEBUG-only print. Follow-ups: (1) make the mirror clear
  unconditional and first (or in a `defer`), and surface a failed unregister
  in the deletion summary — typed error + test; (2) re-run the device
  assessment and refresh Linked Devices on
  `NSUbiquitousKeyValueStore.didChangeExternallyNotification` when registry
  keys change — today the primary needs a relaunch to see a cleared ghost
  (the "restart to see the latest data" Christoph hit); (3) log each
  blocker's device-ID prefix and `registeredAt` in the
  "Other-device check" line so a log answers which device and how old;
  (4) a debug-only override of `mirrorSettleWindow`, since a genuine ghost
  created during testing blocks for two days by design. Not a candidate: a
  "forget this device" action without the phrase acknowledgement — same
  door to the same irreversible outcome (S7 reasoning).
- [x] **(superseded checklist, kept for reference)** two-device verify of the
  deletion override (code landed 2026-09-24, contract rule 24). Check, with two
  linked devices: (a) Linked Devices and the delete screen agree on how many
  other devices hold the wallet, and the delete screen *names* them; (b) delete
  on device B, then on A within the KVS propagation window — A still takes the
  local-only path (correct) but now names B as the blocker and offers "Delete
  from the account anyway…"; (c) taking the override with the acknowledgement
  toggle wipes the seed, KVS hash, network config, backups and CloudKit rows,
  and a reinstall lands on **onboarding**, not a read-only activity screen;
  (d) a mirror-only ghost renders as "Unrecognized device" in Linked Devices
  rather than being invisible; (e) the fresh-secondary launch logs
  "🔒 Read-only: this device is registered as a secondary", not "🛑 Blocked …
  indicates demotion".
- [x] **The wallet could not be deleted from the account, and every reinstall
  re-adopted it — FIXED 2026-09-24** (found 2026-09-23 immediately after the
  rule 23 fix; unrelated to it). Deleting the wallet on device B and then on
  device A a minute later took the **local-only** path on *both* — device A's
  delete dialog still said "other devices will keep access" — so
  `clearEverywhere()` never ran and the seed, KVS hash, network config,
  backups and CloudKit rows all survived. Every later reinstall then found the
  seed and the hash, adopted the wallet, and (per the create/import-only claim
  policy) registered non-primary, landing on a read-only activity screen.

  Scope taken: the reduced S7 (blocker disclosure + informed override), not the
  full S7 build. The store ordering was left alone — it is correct, and the only
  safe way out of a block it creates is a user override. Five defects, worst
  first:

  1. **The last-device check loses to KVS lag** — mitigated, not "fixed", and
     deliberately so. `hasOtherActiveDevices(walletHash:)` still consults the
     KVS mirror before SwiftData, because a joining secondary reading the slower
     store would wipe the shared seed. What changed is that the block is now
     escapable: `includesCloudData(strategy:overrideConfirmed:)` makes an
     explicit, acknowledged override the *only* route from `.localOnly` to a
     full wipe, and `DeletePermanentlyConfirmationView` gates it on a
     "I have my recovery phrase written down" toggle. `hasOtherActiveDevices`
     is now a thin wrapper over the new `otherDeviceReport(walletHash:)`.
  2. **The two surfaces disagreed, which made it undiagnosable** — fixed.
     `otherDeviceReport(walletHash:)` merges both stores into one value that
     marks each blocker `.registry` or `.kvsOnly`, and every surface reads it:
     the delete screen names blockers (or says it couldn't check — the
     third state that was derived-work item 12), and Linked Devices renders
     mirror-only entries as `UnsyncedDeviceRow` instead of hiding them. Linked
     Devices also gained the **wallet-hash scoping** the deletion decision
     always had (derived-work item 10's display half).
  3. **A phantom primary was invented** — fixed. `WalletState`'s device name is
     now `String?`; `SecurityService.swift:243` and the second site,
     `lookupPrimaryDeviceName` (which fed the *rejoin* screen, so this was
     user-visible, in hardcoded English inside localized copy), return nil for
     a zero-primary account. `RejoinWalletView` has copy for it.
  4. **Self-inflicted demotion** — fixed, and it was worse than "misleading
     log": **every** write of `device_<id>_isPrimary` in the codebase targets
     the writer's own device, and promote/demote act only on the current device,
     so layer 2's cross-device demotion had *no reachable trigger* — its own
     registration write was the only thing it ever fired on. A local
     `device_<id>_selfWroteIsPrimary` breadcrumb (written at the single new
     choke point `writeOwnPrimaryFlag`) now distinguishes the cases.
     `MirrorPrimaryVerdict` deliberately has no "demoted by another device"
     case, because nothing can currently tell us that.
  5. **`unregisterCurrentDevice` generated permanent ghosts** — fixed; not in
     the original write-up. The mirror cleanup sat inside
     `if let registration = try? fetch(...)`, with no else, so a device whose
     CloudKit row hadn't imported yet (fresh adopt), had been collapsed by
     `dedupeOwnRecords`, or was unreadable deleted its wallet and left its
     mirror entry behind **forever** — and since the mirror is what the deletion
     decision reads, that ghost blocks every *remaining* device's full wipe, and
     each reinstall of that device re-writes it. Now cleared unconditionally and
     across every wallet hash (`mirrorKeys(forDeviceId:in:)`), which also kills
     the row-hash-vs-account-hash mismatch case.

  Note the device ID survives app deletion (local keychain, non-synchronizable
  — Apple documents that such items don't migrate, but they do survive an app
  delete/reinstall on the same device), so a reinstall is the *same* device to
  the registry while its UserDefaults tombstone is gone. The silent
  re-adoption half is left to the explicit device-linking proposal
  (`Multi_Device_Design.md`, cross-cutting section after S13) on purpose:
  strengthening the tombstone here would build that twice.
- [x] **Override offered on a healthy two-device account — FIXED 2026-09-24**,
  same day, found by the two-device verify below. `showsOverrideOption` was
  `deletionStrategy == .localOnly`, and `.localOnly` is the verdict whenever
  *anything* blocks — including one live, correctly-registered primary. So the
  delete screen named the primary correctly and then offered to wipe the account
  anyway, directly beneath. Now `WalletDataCleanupService.shouldOfferOverride(strategy:report:)`
  requires the block to be doubtful: a mirror-only blocker, a stale row the
  mirror keeps alive, or an unreadable registry. `OverrideAvailabilityTests`
  pins it, including that offering the override and *confirming* the wipe stay
  independent decisions. Not reproducible on a re-test, probably because the
  option sits below the fold on that scrolling screen — the condition itself was
  unconditional, so treat the fix as pinned by tests rather than by observation.
- [ ] **Unlink-first for mirror-only ghosts** (deliberately *not* built
  2026-09-24). Now the *only* remedy for a healthy-but-unwanted blocker, since
  the override is no longer offered there: the paths out are "delete it on that
  device" or "unlink it here", and the latter is exactly what this item builds. S7's primary remedy is "I no longer have this device → unlink it
  here", but `unlinkDevice` throws `deviceNotFound` with no registry row to
  delete, so a mirror-only ghost needs a new `forgetUnsyncedDevice(_:)` that
  removes mirror entries directly. Skipped because it is *redundant for
  unblocking* — the override already gets the user out — while adding a second
  route to the same irreversible outcome with gentler copy, and because
  removing a live device's mirror entry (its row merely hasn't imported) tells
  the remaining device it is alone and unlocks the seed-destroying wipe. Build
  it with the full S7 blockers UX, where it is per-device and confirmed, and
  fail it closed when the registry can't be read.
- [ ] **Translate the new deletion strings** for de/ja/zh-Hant after an IDE
  build extracts them: `settings_delete_warning_local_only_named %@`,
  `settings_delete_warning_local_only_unnamed`,
  `settings_delete_warning_check_failed`, `settings_delete_override_blockers %@`,
  `settings_delete_override_blockers_unnamed`,
  `settings_delete_override_acknowledge`,
  `settings_delete_permanent_warning_override`,
  `button_delete_from_account_anyway`, `button_delete_everywhere_anyway`,
  `rejoin_message_no_primary`, `linked_devices_unsynced_device`,
  `linked_devices_unsynced_device_description`,
  `linked_devices_unsynced_device_registered %@`, `settings_unsynced_devices`.
  **Extraction is no longer the gate** (re-checked 2026-09-24): every one of
  these — `settings_unsynced_devices` now included — sits in
  `Shared/Localizable.xcstrings` as `extracted_with_value` with an `en` entry
  only, so `apply_translations.py` + `translation_lint.py` can run today.
  (`settings_other_devices_count` still carries no `extractionState` but
  already has full de/ja/zh-Hant values.)
  `settings_delete_warning_local_only` is now correctly `stale` (not deleted,
  de/ja/zh-Hant values intact) — it is the string that made the false claim.

  Account-wide picture, same check: **80 user-facing keys have no de/ja value**
  (zh-Hant 89 missing, incl. non-translatable symbols), spanning these
  deletion strings, the `metadata_*` export/import set, the ~28 X-Ray
  `data_bg_*` keys, the 5 `ManualRefreshOutcome` keys and `rejoin_*`. All
  render their English `defaultValue` — no raw keys — so this is cosmetic for
  a TestFlight build, but it is the whole remaining Phase 3 translation debt
  in one number.
- [ ] **Collapse `shouldBlockWalletAccess`'s three layers** (surfaced
  2026-09-24 while fixing defect 4). Layer 2 has no unique job: the KVS flag it
  reads is only ever written by the device reading it, and a genuine
  self-demotion already sets layer 1's `wasDemoted`. Left in place because
  layer 3 (`getCurrentDevice()`) returns nil on a fresh install and so does not
  block, which would hand a brand-new secondary spend rights — the same hole as
  derived-work item 13. Fix that first, then reduce the layers.
- [x] **Local-only deletion destroyed every tag and contact assignment in the
  account** — FIXED and **two-device verified 2026-09-23** (contract rule 23):
  after deleting the wallet on the secondary, the primary kept its activity
  list *and* its tag/contact assignments. Found on the same two-device verify:
  deleting on the secondary blanked the primary's activity list. Third instance
  of the rule 19/21 fault class — a device-scoped action destroying account-scoped state,
  one call after the strategy-aware service did the right thing.

  *Cause.* `WalletDataCleanupService` correctly skips all cloud data for
  `.localOnly`, but `DeleteWalletSettingView.swift:215` then calls
  `walletManager.deleteWallet()`, which takes no strategy and ran
  `resetManagerState()` → `clearTransactionModels()` (deleting every
  `PersistentTransaction`) and `resetBalancesAndDeletePersisted()`. Those
  models are CloudKit-mirrored (`SwiftDataHelper.swift:49-51`,
  `cloudKitDatabase: .private`), so the deletes replicated account-wide.
  Transactions returned on the primary's next refresh (re-upserted from bark
  movements — verified on device), but `PersistentTransaction` cascades to
  `TransactionTagAssignment` **and** `TransactionContactAssignment`
  (`PersistentTransaction.swift:49, 53`), and those are unrecoverable: bark
  knows nothing about tags. Balance cache rows went too — invisible on a
  primary (reads bark live), 0 balance on another read-only device.
  `closeWallet()` shared the same reset and would have done the same while
  deleting nothing; it has no callers today.

  *Fix.* `resetManagerState()` is in-memory-only and uses
  `BalanceService.resetBalancesInMemory()`, which had existed unused since the
  service was written. Both row-deleting methods were removed outright rather
  than gated, so no future caller can reintroduce this; the cleanup service
  already deletes both on a full wipe, and it runs first, so nothing is lost.
  `TransactionDeletionBlastRadiusTests` pins the cascade. The wipe-coverage
  test could not have caught this: it asserts the cleanup service's declared
  lists, not strays in other files.

  *Accepted behaviour change:* the rows now stay after a local-only delete, so
  if any transient screen renders the activity list before routing to the
  rejoin screen it shows the account's transactions instead of an empty list.
  Not observed on the verify; the deleting device routed to the rejoin screen
  as rule 20 requires.
- [x] **Shared network config deleted by local-only deletion — FIXED
  2026-08-20**: found by the first two-device verify — deleting the wallet on
  the primary cleared the iCloud KVS network config, stranding the secondary
  on default-mainnet (signet db refused to open; looked like total data
  loss). `NetworkConfigPersistence.clear()` split into `clearLocal()` /
  `clearEverywhere()` (cleanup-service-owned, strategy-scoped); wallet
  initialization now recovers a missing config from iCloud before first open;
  `SharedStateWipeCoverage` inventories shared keys with deletion scopes.
  Contract rule 21.
- [ ] **Optional self-heal on network mismatch**: bark's db knows its own
  network — on a mismatch open failure, derive the config from the db instead
  of the stored setting (last-resort recovery; needs a bindings check for
  reading the db network without a chain source).
- [x] **Tombstone KVS-transient fix — DONE 2026-08-20**: a missing KVS hash
  clears the tombstone only when the keychain corroborates with a definitive
  `.notFound`; seed-still-present or unreadable keychain keep the rejoin
  route. Tested in `TombstoneRoutingTests`.
- [ ] **Two-device on-device verify of deletion + rejoin** (code landed
  2026-08-19, see `Features/Wallet_Deletion_And_Rejoin.md` — Definition of
  done): local-only delete keeps the seed everywhere (recovery phrase still
  displays on the other device), deleted device shows the rejoin screen and
  relaunch does NOT resurrect the wallet; Rejoin restores from the preserved
  iCloud backup; create-wallet is refused while the account has a wallet.
  This is the gate for calling the 2026-08-19 seed-deletion fix done.
- [ ] **Translate the new deletion/rejoin strings** (rejoin_title,
  `rejoin_message %@`, rejoin_button, error_wallet_already_on_account) for
  de/ja via `apply_translations.py` + `translation_lint.py` after extraction.
- [x] **Second mnemonic-deletion site removed — 2026-08-19**:
  `BarkWalletFFI.deleteWallet()` deleted the synchronizable seed on every
  deletion (including local-only), defeating the 2026-08-12 strategy fix
  account-wide. FFI now deletes files only; `SecurityService`'s duplicate
  (and incomplete) wipe implementation deleted. Launch contract rule 19.
- [x] **Pending send metadata missing from the full wipe — fixed 2026-08-19**:
  `PendingPaymentMetadata` / `PendingTagAssignment` were in the schema but not
  the wipe; found by the new wipe-coverage inventory (`WalletWipeCoverage`,
  asserted by `WalletDeletionRejoinTests` against
  `SwiftDataHelper.appSchemaModels`).
- [ ] **On-device verify of the deletion-strategy fix** (fix landed 2026-08-12):
  with two linked devices, delete the wallet on the primary → secondary's
  Settings → Linked Devices should show the "no active wallet" warning and the
  "Make This Device Primary" button once CloudKit syncs → promotion should
  restore the wallet from the (now preserved) iCloud backup.
- [ ] **Active "no primary device" banner** on secondaries' main view
  (deliberately deferred 2026-08-12). Read-only devices would run
  `checkForNoPrimaryDevice()` on launch/foreground and show a callout with a
  deep link to the existing `PromoteDeviceSheet`. Shipped UX for now is the
  passive Linked Devices flow plus the pointer in the delete-confirmation copy.
- [x] **Fail-safe direction of `getDeletionStrategy()`'s error fallback —
  DECIDED + DONE 2026-09-21**: an unreadable registry now resolves to
  `.localOnly`. Extracted as the pure
  `WalletDataCleanupService.deletionStrategy(for:)` over an
  `OtherDeviceEvidence` enum, so `.noneFound` is the *only* input that can
  reach the destructive strategy — pinned by `DeletionStrategyTests`,
  including a test that fails if a newly added evidence case defaults to
  full wipe.
- [x] **Full wipe offered to a non-last device (CloudKit lag) — FIXED
  2026-09-21**: found by a claims audit of `Multi_Device_Design.md`, never
  observed in the field. `hasOtherActiveDevices()` read only the
  CloudKit-backed SwiftData registry, so a secondary that asked before the
  primary's record was imported (seconds to never, when offline) was told it
  was the last device — "Delete Everything" would then have removed the
  synchronizable seed account-wide. Now `hasOtherActiveDevices(walletHash:)`
  consults the fast KVS mirror first (previously written on every
  registration and read by nothing), is scoped to the wallet hash on both
  sides, and answers "others exist" when the hash is unknown.
  `unregisterCurrentDevice()` now clears its KVS entry too, as
  `unlinkDevice()` always did — otherwise a local-only delete would leave a
  ghost that blocks every future full wipe. Tests: `KVSDeviceRegistryTests`.
  282/282 green on iOS. **Not yet on-device verified** — folds into the
  two-device verify below (add: delete on a freshly joined secondary while
  CloudKit is still importing → must say "Delete from This Device").
- [ ] **A KVS-only ghost is invisible and unremovable**: the full-wipe check
  now reads the KVS registry, but Linked Devices lists SwiftData
  registrations. If a device's KVS entry outlives its CloudKit record (record
  lost, or an iOS restore onto new hardware that regenerates the device ID),
  it blocks the full wipe with nothing to unlink in the UI. Remedy: list
  KVS-only entries as blockers (S7 does this naturally) — shipped: the delete
  screen names mirror-only blockers, and aged ones (48h settle window) unlock
  the informed override. The other remedy once listed here — run
  `cleanupKVStoreRegistry()` on launch — is struck, and the method was
  DELETED 2026-09-25: it removed any other device's mirror entry whose
  SwiftData row was locally absent, which is exactly the CloudKit-import-lag
  state a freshly joined live device sits in, so one call could erase the
  evidence that blocks an account-wide seed wipe.
- [ ] **Blocked-strategy copy**: the conservative `.localOnly` fallback shows
  "Other devices have this wallet", which is a guess in the error case. Needs
  a third user-facing state ("couldn't check — try again") = new strings
  across de/ja/zh-Hant, so it was deliberately not bundled with the fix. S7's
  blockers list supersedes this if built first.
- [ ] **`checkReadOnlyMode()` infers primary** (`WalletManager.swift:503-514`):
  a missing or unreadable device registration sets `isReadOnlyMode = false`,
  i.e. full spend rights — contradicting Principle 2 and contract rule 15.
  Registration correctly refuses to infer primary; the spend gate doesn't.
  Reachable via self-unlink (`LinkedDevicesView_iOS.swift:46`), which the
  capability matrix doesn't model. UNVERIFIED — needs a self-unlink →
  relaunch run before deciding the fix.
- [ ] **Dead device-registry code**: `cleanupStaleDevices()` and
  `migrateToThisDevice()` both have zero call sites (verified 2026-09-21);
  `DeleteLocallyConfirmationView` is never instantiated. Delete
  `migrateToThisDevice()` with the S5 work — it bypasses the
  `becamePrimaryAt` bookkeeping reconciliation depends on.
- [ ] **Delete flow has no partial-failure handling**
  (`DeleteWalletSettingView.swift:205-236`): `deleteWalletData()` runs first,
  then `walletManager.deleteWallet()`. If the second throws, shared state is
  already destroyed but the user stays in-app with no navigation, and
  `isDeleting` is never reset on the success path either.
- [ ] **Remove the dead `showNoPrimaryDeviceBanner` NotificationCenter post**
  (`DeviceRegistrationService.demoteThisDevice`): nothing observes it, and as
  an in-process notification it can't reach other devices anyway.
- [ ] **Devices-list display scoping** (open item from the two-primary-devices
  fix): scope the list to the current wallet's registrations.
- [ ] **Server-side arbitration for primary claims** (two-primary hardening):
  CloudKit/KV reconciliation is client-side only today.

## Exits

- [ ] **Exit blocked state**: on-device verify + WalletManager tests.
  See `Features/Exit_Blocked_State.md` (phases 1–3 done).
- [ ] **Exit completion issues**: on-device verify with a wallet that has both
  claimed and cancelled exits. See `Features/Exit_Completion_Issues.md`
  (all 5 phases done).
- [x] **Fresh-import live activity respawn — on-device verified 2026-08-13**:
  importing a wallet whose exit already completed spawned a "Move complete
  5/5" activity because (a) bark replays finished exits through the state
  machine on a fresh DB so they read as in-flight for ~2s, and (b)
  `endLiveActivity` froze the pre-chain 5-step estimate instead of the real
  6-step total. Fix: `recreateMissingActivities` now runs only after the
  launch `checkAndProgressExits` pass (reattach still immediate), and
  `endLiveActivity` recomputes step totals from final statuses. Verified:
  re-import produced zero `[LiveActivity]` log lines; check-in reminders
  were cleared instead of armed-then-cancelled.
- [ ] **Adopt `cancelExit` from bindings v0.18.0** (landed 2026-08-17): the
  cancel-exit API our `ParsedExitState.canceled` comment was waiting for —
  the natural escape hatch for fee-blocked exits. Prerequisites before a
  cancel button ships: Live Activity `ExitState` lacks terminal
  `canceled`/`vtxoAlreadySpent` cases; verify the date-freeze workaround
  covers explicit cancels (feedback §1.4 upstream bug); check whether bark
  purges cancelled exits from `getExitVtxos()` like claimed ones (snapshot
  into `PersistentExitCache` if so). Full notes in
  `Bark_Bindings_Unadopted_API.md` §1.1.
- [ ] **Report upstream to bark devs** (network-verified on the stuck signet
  wallet): (a) exit package transactions don't exist on the network despite
  bark reporting broadcast; (b) round-replacement VTXO fails signature
  validation. The cancelled-exit date bump is already §1.4 in
  `Bark_Bindings_Feedback.md`.
- [ ] **Claimed exit funds invisible after seed import** (network-verified
  2026-08-13, test wallet: 8,839 sats confirmed-unspent at the claim
  address, absent from balance — 143,041 shown vs 151,880 actual). Root
  cause chain: `ExitClaimSequence.run` reveals a fresh address
  (`getOnchainAddress()` = `reveal_next_address`) as its FIRST step on
  every claim attempt — before `drainExits` can fail — and
  `ExitProgressionService` auto-retries failed claims (e.g. fee-blocked)
  each interval, so every failed attempt burns one derivation index. These
  claim addresses bypass `AddressService` history entirely (untracked, not
  gap-limited). Seed import loses the revealed-index state, and both BDK
  gap-10 scans (reader full scan, bark revealed-SPK sync) stop before
  reaching the claim address. Note the receive screen is NOT a contributor
  (`AddressService` reuses the unused address), but its 20-unused cap also
  independently exceeds the gap-10 scan. Mitigation candidates: (a) reveal
  the claim address only after a successful `drainExits` build, or persist
  and reuse one claim address per exit; (b) route claim addresses through
  `AddressService`; (c) scan stop gap ≥ unused cap + margin (e.g. 50) on
  import; (d) upstream — bark onchain wallet has no rescan/full-scan API
  (ties into feedback §2.6 `forceRescan` removal). Also blocks the exit
  movement from ever linking its claim tx (`onchain_… not found` on every
  relink pass).

## VTXO Expiry

Field incident 2026-08-13 (signet): wallet deleted with a 10,000-sat VTXO
(`8958f837…`, expiry height 317579) ~2h from expiry; on re-import 6h later
the recovery mailbox reported it `Spent` — swept by the server at expiry (no
device held keys in between, so no other spender was possible). The app never
surfaced the stake: no warning at deletion, no explanation afterward — Ark
balance just showed 0. Signet's 144-block (~6h) expiry made this unusually
tight, but the gaps are structural:

- [ ] **Warn on wallet deletion about forfeitable offchain balance**: the
  minimum expiry height across spendable VTXOs is known at deletion time —
  the confirmation should say "your offchain balance of X is forfeited
  around \<time\> unless this wallet is re-imported and refreshed before
  then." Deleting the last device also deletes the only agent that can
  refresh.
- [ ] **Surface expiry sweeps instead of silently showing less money**: on
  import (and during recovery scans) VTXOs come back as bare `Spent` with no
  reason, so "spent from another device" and "lost to the expiry deadline"
  are indistinguishable and nothing appears in history. Blocked on upstream
  spent-reason (`sweptAtExpiry` etc.) — filed as §1.9 / ask 17 in
  `Bark_Bindings_Feedback.md`. Once available, write an explicit "expired"
  history entry.
- [ ] **Expiry-critical reminders vs. the notifications toggle**: the
  scheduled free-refresh reminder is silently dropped when notifications are
  disabled in app settings (as they were in the field logs), removing an
  expiry defense without the user knowing the cost. Consider exempting
  expiry-deadline reminders from the toggle, or warning that disabling
  notifications risks missed refresh deadlines.

## VTXO Refresh (guiding doc: `Features/Refresh_Deduplication.md`)

Diagnosed 2026-09-21: three writers (auto service, manual UI, bark daemon)
schedule refreshes from overlapping pools with no "already being refreshed"
exclusion; balance card shows "Refresh now" during an ongoing refresh. Bark
facts verified at the bark-0.7.1 tag (our 0.24 bindings). Approved and
implemented 2026-09-21 (`RefreshExclusion` unit-tested 9/9, mobile build
green):

- [~] **Phase 1 — visibility bugs — partial 2026-09-21**: modal routed
  through the service (refetch included); **status** mapping verified
  statically. The **category** mapping is still unverified and is the half
  that can silently empty the whole signal — `.refresh` requires
  `subsystemName == "bark.round"` *and* `subsystemKind == "refresh"`. Folded
  into the on-device gate below.
- [x] **Phase 2 — Guard C — done 2026-09-21**: `vtxoIdsBeingRefreshed()`,
  `RefreshExclusion` pure filter (+ near-expiry safety valve), exclusion in
  both service paths, `pendingRoundInputVtxos()` adopted; debug
  `VTXOListView` force-refresh deliberately left direct (see doc).
- [x] **Phase 3 — balance card — done 2026-09-21** with one recorded
  deviation: the "Refresh now" side is as specified; "Refreshing" still keys
  on `hasActiveRefresh` (movement-only) because it's a sync property and the
  round-input half needs an await (doc §3.1).
- [x] **Phase 4 — piggybacks — done 2026-09-21**: refresh stats only on
  actual schedules; notification auth prompted only while undetermined.
- [x] **Phase 5 — upstream + doc corrections — done 2026-09-21**: feedback
  doc §2.7 / ask 18; `Exit_Refresh_Coordination.md` facts 7+8 + two
  corrections (cancel path, `hasActiveRefresh` coverage).
- [x] **Manual-refresh outcome — done 2026-09-21**: `ManualRefreshOutcome`
  so the modal stops reporting success for the `isChecking` skip;
  `refreshVTXOsManually()` throws on a missing service.
- [x] **Stale unified-transaction merge — fixed 2026-09-21**:
  `refreshAfterVTXOChange()` refetched the Ark-only service while every
  reader goes through `unifiedTransactionService.allTransactions`, a stored
  merge written only by `performRefresh()`. Guard C's primary signal was
  therefore inert after an auto-schedule, and the card only updated on sheet
  dismissal. Now calls `mergeTransactions()`. Affected all six callers, not
  just refresh.
- [x] **Read-your-own-writes on the post-write refetch — fixed 2026-09-21**:
  `refreshTransactions()` joins an in-flight dedup task, so a fetch started
  before the write could satisfy the call. Added
  `TaskDeduplicationManager.executeFresh` (drains, then fetches fresh — not a
  bypass, because the upsert awaits mid-loop and can't run concurrently with
  itself) and `TransactionService.refreshTransactionsAfterWrite()`.
- [x] **`execute` clobbered `executeFresh`'s registration — fixed
  2026-09-24** (found in review): when `executeFresh` drained an
  `execute`-created task and took over the key, the drained task's creator
  still removed the key unconditionally on completion — so an `execute`
  arriving while the fresh task ran found no key and started a **concurrent
  duplicate**, the exact double-upsert hazard the drain prevents (and the
  stale generation left behind cascaded the clobber onto the next taker).
  Both `execute` variants now remove the key only if it still holds their own
  task (Task identity `==`). Mutation-verified by
  `executeJoinsFreshTaskAfterDrain` (failed before the fix, passes after).
- [x] **Error paths refetch — fixed 2026-09-21**: bark writes the Pending
  movement before server registration (F1), so a throw could leave the app
  blind to it. Both scheduling paths refetch before propagating, scoped to
  the scheduling call so offline checks don't refetch hourly.
- [x] **`unusable_inputs` no longer reads as failure — fixed 2026-09-21**:
  mapped to `ManualRefreshOutcome.alreadyIssuedByServer` → "Already
  refreshing"; auto path stops setting `lastError`.
- [ ] **`TaskDeduplicationManager.cancel`/`cancelAll` have never worked**
  (found 2026-09-21, pre-existing). Both branches cast to `Task<Any, Error>`
  / `Task<Any, Never>`, and `Task` is invariant in both generic parameters —
  verified empirically, those casts can never match a concrete task. So
  `cancel(key:)` is a no-op, and `cancelAll()` cancels nothing while still
  running `tasks.removeAll()`: it clears the registry with operations still
  in flight, which would let the next `execute` start a **concurrent
  duplicate** on any key and defeat the manager's whole purpose.
  Impact today is low — the only caller is `ServiceContainer.cleanup()` on
  the *ServiceContainer* instance (contacts/tags/addresses keys) at app
  teardown via the root view's `onDisappear`, and `"transactions"` lives on
  `WalletManager`'s separate instance, which nothing cancels. Becomes sharp
  if `cancelAll` is ever called mid-session or the two managers are
  consolidated. Fix: store type-erased cancel closures alongside each task
  instead of casting. `generations` is likewise not cleared by either method
  (harmless — bounded by distinct key count).
  Deliberately deferred again 2026-09-24 while fixing the ownership bug
  above: making `cancelAll` real would start genuinely cancelling
  fund-adjacent operations (`createWallet`, `deleteWalletData`,
  `transactions`) that were never written to be cancellation-safe — that
  needs its own per-key review, not a piggyback.
- [ ] **`refreshTransactionsAfterWrite()` costs an extra `getMovements()`
  under contention**: it drains the in-flight fetch *and* runs its own, so a
  contended post-write refetch does two full FFI fetches plus two upsert
  passes over all movements, where before there were zero extra. Event-driven
  only, so accepted for now. A cheaper design: track a write sequence and
  join the in-flight fetch when it already observed our write, instead of
  always refetching.
- [ ] **Surface typed errors across the bark FFI boundary**: every
  `Bark.Error` is collapsed into `BarkWalletFFIError.configurationError(_:)`,
  so callers can only recover by string-matching the message — which is what
  `isAlreadyIssuedRejection` does today. Contradicts the
  "typed errors at the FFI boundary, policy in `WalletManager`" convention.
  Worth a dedicated error case per recoverable bark variant, starting with
  `unusable_inputs`.
- [ ] **Thread the live refresh-expiry threshold into `RefreshExclusion`**:
  the valve hardcodes 144 to mirror bark's `vtxo_refresh_expiry_threshold`,
  which we don't pin (FFI config passes `nil`). A test pins it against
  `ArkConfigModel.vtxoRefreshThresholdBlocks`, but the real fix is reading
  the live value from `getConfig()` with the constant as fallback — needs a
  cached `arkConfig` on `WalletManager` (there isn't one today) to avoid an
  FFI call per check.
- [ ] **On-device signet verification** (doc §6, 4 steps): parsing gate
  first (log `subsystemName`/`subsystemKind`/`category` right after
  scheduling), then card flips to "Refreshing", no duplicate schedule from
  the hourly/foreground check, and "Already refreshing" on a raced tap.
- [ ] **Extract + translate 5 new keys**: `status_refresh_not_needed`,
  `balance_refresh_not_needed`, `status_refresh_already_underway`,
  `balance_refresh_already_underway`, `balance_refresh_already_scheduled`
  (the `ManualRefreshOutcome` screens).
  Absent from `Shared/Localizable.xcstrings` — they render their
  `defaultValue:` English until an **IDE** build extracts them
  (`xcodebuild` doesn't), then need de/ja/zh-Hant. Don't hand-add values;
  re-extraction empties them.
- [ ] **Deferred, recorded in the doc**: near-expiry safety valve is
  auto-path-only (no UI route to it, §3); `findVTXOsForAutoRefresh` (fee
  window + signet cap) still embedded and untested, and
  `vtxoIdsBeingRefreshed()` has no test seam (§5); refresh modal's displayed
  list/amount can diverge from what the service actually refreshes — narrowed
  2026-09-24 (the modal now applies the exit exclusion too, fail-open), the
  remaining divergence is the valve and mid-flight state changes — revisit
  after the device run.

## Startup & Initialization

- [ ] **Startup wallet detection review follow-ups**: 8 items listed in
  `Initialization/REVIEW.md` / `Initialization/STARTUP_WALLET_DETECTION_PLAN.md`
  (phases 1–4 done); optional Phase 5 refactor.
- [x] **Seed-recovery scan never runs on import** — fixed and field-verified:
  single `Wallet.open(createWithoutServer:)` shipped
  (`BarkWalletFFI+WalletCreation.swift`); imports on 2026-08-13 show the scan
  running and completing (`Seed recovery finished … complete=true`).
- [ ] **Keep `Initialization/Launch_Sequence_Contract.md` current** (created
  2026-08-14): the ordering-invariants contract for startup/import/exit/
  multi-device/deletion. Every startup-shaped incident fix adds a rule; PRs
  touching launch ordering check against it.
- [x] **`LaunchSequence` extraction** (done 2026-08-14):
  `ExitProgressionService.start()`'s ordered steps (reattach → first check →
  recreate → reminders) live in `LaunchSequence` (`ExitProgressionLogic.swift`)
  with injected effects and an order-pinning test
  (`LaunchSequenceTests/launchOrderIsPinned`); contract rule 8 now enforced.
- [x] **Import wipe-and-reopen retry decision extracted** (done 2026-08-14):
  `ImportRecoveryLogic` in `BarkWalletFFI+WalletCreation.swift`, decision
  matrix pinned by `ImportRecoveryLogicTests` (contract rule 2).
- [ ] **Next pure-logic extraction**: wallet-detection decisions (contract
  rules 3/4/14 — overlaps the optional Phase 5 refactor above).
- [x] **The wallet can run a whole session on the wrong network** — FIXED
  2026-09-23 (contract rule 22), **both branches verified 2026-09-24**. Step 0-pre is
  now `WalletManager.reconcileNetworkConfigBeforeWalletOpen()`: it syncs from
  iCloud and re-applies the account's network to the wallet object on every
  path that opens the wallet — `performInitialization` and the background wake
  in `WalletManager+Notifications` — and skips entirely when the wallet is
  already open, because create/import save locally and mirror to iCloud
  asynchronously (syncing there would overwrite the newer local value and
  re-point a live wallet). An unresolvable cached id yields `.noUsableConfig`,
  never `load()`'s mainnet fallback. `hasSavedConfig()` is gone — its "no local
  config" framing was the bug. Decision covered by
  `NetworkConfigReconciliationTests` (8 cases); 309/309 mobile, macOS builds.

  **Fresh-install re-apply VERIFIED on device 2026-09-23.** A reinstall joining
  an existing signet account logged, in order: `No saved config found, using
  default: Bitcoin Mainnet` → `Synced network configuration from iCloud: signet
  (was none)` → `🌐 Network config mismatch before wallet open — wallet was
  built on Bitcoin Mainnet, account says Bitcoin Signet; re-applying` →
  `Updating network configuration to: Bitcoin Signet`, and a later pass logged
  `🌐 Network config in sync before wallet open: Bitcoin Signet`. No mainnet
  database was created. A signet import on the primary also completed normally,
  which exercises the skip-when-open guard without proving it by log.

  **Skip-when-open guard VERIFIED on a fresh simulator 2026-09-24** (erased
  iPhone 18 Pro, iOS 27.0, app installed via `simctl`, no debugger attached).
  Creating a signet wallet logged, in order: `Network configuration saved:
  Bitcoin Signet (ID: signet)` → `initialize() CALLED` from
  `MainView_iOS.swift:169` → `Starting initialization...` → `🌐 Network config:
  wallet already open on Bitcoin Signet — leaving it alone` → `Device is
  primary` → `Wallet already open`. Exactly one reconcile-branch line in the
  whole session: no `.reapply`, no `.inSync`, no `.noUsableConfig`. Relaunching
  then logged `Network config loaded: Bitcoin Signet` → `route=wallet` → `🌐
  Network config in sync before wallet open: Bitcoin Signet` → `wallet exists on
  Bitcoin Signet`, so the chosen network survived and the *other* side of the
  guard (wallet not yet open → `.inSync`) is covered too. Both remaining
  sub-checks done; the item is closed.

  Note on the `<private>` worry: network names rendered **in full** on the
  simulator with no debugger attached, read via
  `xcrun simctl spawn booted log show --last 15m --info --debug --predicate
  'subsystem == "GBKS.Arke"'`. Simulator log reads don't redact private data, so
  the concern applies to *physical-device* logs only. The suggestion to mark
  those four interpolations `privacy: .public` (as ~10 other files already do
  for non-sensitive diagnostics) still stands on its own merits — undecided, not
  done. Beware: `log show` omits `info`-level lines unless `--info --debug` is
  passed; without them this check silently shows nothing.

  A stale-but-present local config takes the same `.reapply` branch as the
  2026-09-23 device verify and is covered by the unit tests; it's only
  reproducible by hand on macOS (edit the container plist after
  `killall cfprefsd`).
  Original write-up:
  Two observations on the second iPhone, 2026-09-23:
  1. *Stale local config.* The device had `mainnet` in UserDefaults while iCloud
     said `signet`. `BarkWalletFFI` was built on mainnet at
     `WalletManager.init`; `syncFromiCloud()` later corrected the cache and
     posted `networkConfigDidSyncFromiCloud` — which **nothing observes** — so
     the correction only took effect on the next launch.
  2. *Fresh install (wallet deleted, app deleted, reinstalled).* No local config
     at all, so `performInitialization()`'s step 0-pre recovery
     (`WalletManager.swift`, contract rule 21) should have fired. It didn't:
     its guard is `!hasSavedConfig()`, and MainView's `.task` →
     `syncFromiCloud()` had already written signet into UserDefaults seconds
     earlier, so the guard read false and skipped both the sync *and* the
     `wallet?.updateNetworkConfig(recovered)` that fixes the wallet object. The
     recovery path is disarmed by the very sync that fetched the value. Tell:
     the `⚠️ No local network config` warning never prints, and the session
     fetches `mempool.second.tech/api` (mainnet, height 968278) instead of
     `esplora.signet.2nd.dev`.

  Read-only devices get off lightly — they never open the wallet, so no mainnet
  db is created. **On a primary device the same race opens bark on the wrong
  network**, and the next launch (cache now corrected) hits the network-mismatch
  refusal that looked like total data loss in the 2026-08-20 incident.

  Direction as implemented: reconcile before *every* open and never after,
  rather than "unconditionally" — the create/import-then-`initialize()` flow
  runs with the wallet open and a local config newer than iCloud's, where an
  unconditional sync would have reintroduced the same wrong-network db from the
  other direction. Relates to the network-mismatch self-heal item under Wallet
  Deletion & Device Registry. The explicit device-linking gate below would
  retire this patch rather than inherit it.
- [ ] **Reinstalling after a local wallet deletion silently rejoins**: the
  deletion tombstone is `UserDefaults`
  (`SecurityService.localDeletionTombstoneKey`), which app deletion wipes, while
  the seed (iCloud Keychain) and the wallet hash (KVS) survive — so detection
  says "wallet exists" and routes into the wallet instead of `RejoinWalletView`
  (observed 2026-09-23). Defensible as designed; decide whether a reinstall
  after a local delete should land on the rejoin screen, which means storing the
  tombstone somewhere that survives app deletion — the keychain device-ID slot
  (`WhenUnlockedThisDeviceOnly`, non-synchronizable) has exactly that lifetime.
  **Likely superseded** by the explicit device linking proposal below: a link
  marker whose absence means "ask" needs no survival mechanism at all.
- [ ] **DECIDE — explicit device linking** (PROPOSAL written 2026-09-23 in
  `Architecture/Multi_Device_Design.md`, cross-cutting section after S13, with
  pointers on S2/S6/S9): should an install ever adopt the account's wallet
  silently, or should it disclose what it found and have the user acknowledge
  it once? Single-action disclosure, not a two-button choice — principle 1
  (one wallet per iCloud account) means there is nothing to decline into.
  Four open questions are listed in the proposal; it needs a decision before
  any of it is built, and it would absorb both the tombstone item above and the
  "freshly installed secondary shows an empty wallet" item.
- [ ] **~600 lines of `CoreData: error` on a first launch after reinstall**: the
  App Group's `Library/Application Support` directory doesn't exist yet, so
  adding the persistent store fails and Core Data recovers ("Recovery attempt …
  was successful"). Harmless but it buries real errors, and that launch took
  13.8s just to register the device. Create the directory before building the
  container.

## Background Execution

See `Features/Background_Execution.md` (Phase 1 done, soak running).

### Background runs are being killed for holding a store lock (0xdead10cc)

Found 2026-09-24 in Apple's TestFlight crash data (Xcode Organizer /
`GetTopCrashIssues`), not from the field reports or the journal. **Two of the
three crash signatures on build 23 are the same kill**, one device each:

- `Termination Reason: RUNNINGBOARD 0xdead10cc` — the process was suspended
  while holding a file or SQLite lock, so the system killed it outright.
- **2026-09-17, 1.8s into a background launch** (iPhone16,2, iOS 27.0): main
  thread blocked in `open()` inside `BarkWalletFFI.getWalletDirectory()` — the
  `.test` writability probe — while another thread ran CloudKit's
  `PFCloudKitMetadataModelMigrator` holding a SQLite connection. The probe ran
  on *every* `BarkWalletFFI.init`, which happens inside `App.init()`.
- **2026-09-16** (iPhone18,1): main thread in SwiftData `DefaultStore.save` from
  `DeviceRegistrationService.registerCurrentDevice`.

Why it matters for the release: a killed background run doesn't finish its
pass, so the wake silently achieves nothing — and this release has the relay
sending auth wakes on its own, raising wake frequency. The journal records the
wake but no completion row, which reads as "never granted" rather than "killed".

- [x] **Probe write removed from the launch path — 2026-09-24**:
  `getWalletDirectory()` no longer writes-and-deletes `.test` when the
  directory already exists (it still probes right after creating one, which
  happens once). Strictly less main-thread file I/O in `App.init()`.
- [x] **Task assertion around the exposed writes — 2026-09-24**: new
  `withBackgroundActivityAssertion(_:operation:)`
  (`Shared/Services/BackgroundActivityAssertion.swift`) wraps
  `registerCurrentDevice` (whole pass: save, devices reload, primary
  reconcile) and the headless `openWalletIfNeeded()` in
  `refreshRelayAuthInBackground`. Best-effort by design — a refused assertion
  runs the work unprotected, as before. No-op off iOS.
- [ ] **On-device confirmation**: the kills are only observable after the
  fact. Watch Organizer for build 25+ signatures at
  `getWalletDirectory`/`registerCurrentDevice`, and for the new
  `⏳ Background assertion '…' expired before its work finished` /
  `ℹ️ Background assertion '…' not granted` lines. Absence of new 0xdead10cc
  reports over a week of wakes is the only real confirmation.
- [ ] **Structural: a background launch still builds the whole app**.
  `App.init()` constructs `WalletManager` → `BarkWalletFFI` (file system work)
  and the CloudKit container before anything knows whether this launch is for
  UI or for a wake, and an assertion can't help there — nothing is alive yet
  to take one. Deliberately not restructured for this release (too large, and
  the probe removal takes the measured frame out). The fix direction is a lazy
  wallet/FFI construction so a wake path touches only what it needs; revisit
  with Phase 2.
- [ ] **Audit the other unprotected store writes on background-reachable
  paths**: `unregisterCurrentDevice`, the transaction upsert in
  `refreshTransactionsAfterWrite`, and the balance persist all save on paths a
  mailbox push can reach. Only the two above are crash-proven, so the rest
  were left alone rather than blanket-wrapped.

- [x] **BGTask grant frequency**: ~~evaluate soak results~~ answered from the
  relay side 2026-09-17 (124/151 mailboxes expired — not often enough); the
  `trigger` field on `/v1/register` now measures it server-side per wake path.
- [ ] **Auth wake push: verify from field data** (implemented 2026-09-17,
  stale-mailbox unregister added 2026-09-21, see `SWIFT_AUTH_WAKE_SPEC.md`
  acceptance criteria). Decision 2026-09-21: shipped without manual
  push-simulation tests; verify passively instead. Watch for: (a) X-Ray
  journal rows — "Auth wake push · refreshed" and "Stale mailbox
  unregistered · success · wake_push" with expiry/BGTask rows untouched;
  (b) relay side — `trigger: "wake_push"` registrations under
  `auth_refresh.refreshes_after_wake`, and DELETE /v1/register with
  `removed: 1` shortly after a wake for that mailbox. Caveats: the DELETE
  carries no trigger field (relay can only attribute by wake→DELETE
  correlation), and orphans past their 7-wake budget never get another
  wake — "no signal" ≠ broken. Terminated-not-force-quit cold launch shows
  up as a fresh pid in the journal when it happens.
- [ ] **Background activity journal + X-Ray screen** (plan:
  `Features/Background_Activity_Journal.md`): ALL 3 PHASES DONE 2026-09-18
  (journal + 7 instrumentation points, X-Ray section/screen — device-
  verified via screenshots, relay cross-check row, DebugLogExporter
  journal section); first field findings (double registration, prewarm-
  inflated launch times) found and fixed same day. Remaining:
  simulated-wake journal verify (plan Phase 1 item 4), on-device look at
  the cross-check row, events-list bottom row can sit under the floating
  tab pill, and de/ja/zh-Hant passes for the ~28 new X-Ray strings.
- [ ] **Phase 2**: mailbox push wake → full background pass. Relay stays dumb
  *except* the auth-expiry wake (Decision 2 amendment, 2026-09-17).

## Bindings Adoption

`Bark_Bindings_Unadopted_API.md` (created 2026-08-17) records everything the
bindings offer that we haven't adopted, with feature implications — roadmap
inspiration lives there. Baseline: bindings v0.18.0 / bark v0.6.1 (the
v0.17→v0.18 bump was purely additive; nothing broke).

- [ ] **Keep the unadopted-API record current on every bindings bump**: diff
  the release commits in the package checkout, add new surface, move adopted
  items to its Adopted-since section.

## Bark 0.23 Migration (minimal pass shipped 2026-09-08)

Guiding docs: `Migrations/Bark-0.19.0-to-0.23.0/`. Shipped: recompile,
`vtxoLifetime` migration, `UInt16` config-read widening, `stopDaemonWait()`
in all shutdown paths. Deferred adoption (see plan §2.2-2.4, §Phase 3):

- [ ] **`initialScanOnchain(birthdayHeight:)` on import** — recovers onchain
  history from a previous incarnation of the seed; `sync()` never finds it.
  Needs a distinct "scanning" import UI state + on-device import verify.
- [ ] **`estimateEmergencyExitFee(...)` exit pre-flight** — show broadcast
  vs claim fees separately; block/warn hard on `fundable == false`. Slow
  call (syncs onchain wallet first).
- [ ] **`recoveryStatus()` adoption** — distinguishes recovery-failed from
  never-ran; at minimum log `.failed(message:)` where the import path reads
  `recoveryReport()` (`BarkWalletFFI+WalletCreation.swift:572`).
- [ ] **Phase 3 (optional, ask first)**: `RoundFlowKind`-rich round UI,
  externally funded board (`boardFundingAddress`/`boardPsbt`),
  `OnchainWallet.evictTx`.
- [x] **Update `Bark_Bindings_Unadopted_API.md`** for the 0.23 surface —
  done 2026-09-17 as a catch-up section during the 0.24 bump (baseline now
  v0.24.0).
- [ ] **Daemon auto-start on `Wallet.open()` (new in bark 0.7.0)** — device log
  2026-09-08 shows Rust starting the daemon during open, then our explicit
  `runDaemon()` triggering `Called Wallet::start_daemon while daemon was
  already running.` Per bark docs, calling start again stops the previous
  daemon and starts a new one, so we may be restarting a just-started daemon
  every launch. Either drop the explicit `runDaemon()` call
  (`WalletManager` open path) or confirm the double-start is a true no-op.
- [ ] **18s gap between `initialize()` called and executed** — same device
  log: `initialize() CALLED` 01:29:56, `initialize execute` 01:30:14. A
  *relative* anomaly within one run (not tethering overhead); suspect the
  TaskDeduplicationManager/queueing layer. Check if it reproduces before
  digging (Xcode-tethered timings are otherwise ignorable; untethered
  cold-launch budget is 2.84s).

## Bark 0.24 Migration (shipped 2026-09-17)

Guiding docs: `Migrations/Bark-0.23.0-to-0.24.0/`. Shipped: recompile +
`vtxoKeyGapLimit: nil` (gap limit 50 → 250 by design), widened
`foreign`-ids recovery retry (`ImportRecoveryLogic.retryPasses` +
`retryRecoveries`, `maxVtxoKeyGapLimit()` = 100_000), 4 new
`ImportRecoveryLogicTests`. Deferred:

- [ ] **`importVtxos` batch adoption** — no import loop exists today
  (`WalletManager.importVtxo` has zero callers); adopt when a multi-VTXO
  import feature appears. Notes in `Bark_Bindings_Unadopted_API.md` (v0.24
  section).
- [ ] **Protocol mirroring of `importVtxo(args:)` / `recoverVtxos(gapLimit:)`**
  — mirror onto `BarkWalletProtocol` when the first caller needs a
  non-default; today both stay FFI-internal.
- [x] **On-device import smoke of the widened retry** — done 2026-09-17:
  Christoph ran a seed import on device same day as the bump; import worked.
  (Log-line inspection of the per-pass retry outcomes wasn't part of the
  pass; revisit only if a foreign-VTXO case ever surfaces in the field.)

## Bark 0.16 Migration

- [ ] **On-device verify with a v1-snapshot wallet** (migration merged and
  green in tests; the on-device snapshot upgrade path is unverified).

## BDK Transaction Reader Removal

Plan in `Features/BDK_Transaction_Reader_Removal.md` (planned 2026-08-12,
no code yet). Enabled by `OnchainWalletProtocol.transactions()` in the new
bindings.

- [x] **Phase 0**: A/B diagnostic PASSED 2026-08-12 (imported signet wallet
  with completed exit): 5/5 txid match, all nets/fees/heights identical;
  CPFP-fee-nil risk disproven (bark reports exact fees, even for receives).
  Findings folded into the plan doc (§3.2 net-sign derivation, §5 notes:
  post-import one-sync lag; claim tx outside descriptors unlinked — pre-
  existing; imported CPFP children origin=Block → never movement-linked).
- [x] **Phase 1**: DONE 2026-08-13 — history now comes from
  `onchainWallet.transactions()` via `OnchainTransactionMapper` (net-sign
  classification, raw-tx output-sum parser) with Esplora block-timestamp
  resolution (`BlockTimestampService`; `ConfirmationTime.timestamp` is now
  optional and entities keep a resolved timestamp when a refresh lacks one).
  Phase 0 diagnostic removed. 19 new unit tests green.
- [x] **Phase 1 defect — first render after fresh import shows 0 onchain
  txs**: FIXED 2026-08-13. (a) `WalletManager.refresh` now awaits
  `addressService.loadAddresses()` (which reveals index 0 on a fresh
  import) before the parallel service group, so the first onchain sync has
  something to scan; (b) `getOnchainTransactions()` loops sync+fetch via
  `OnchainHistorySyncer.syncUntilStable` (repeats while the txid set
  changes, cap 5 rounds, seeded with the previous fetch's txids so steady
  state costs one sync; reset on wallet shutdown). 5 new unit tests.
- [x] **On-device verify of Phase 1 + discovery fix**: PASSED 2026-08-13 —
  fresh seed import shows the full history on first Activity render, no
  pull-to-refresh needed.
- [x] **Stale balance overcount after fresh import**: FIXED 2026-08-13 —
  the parallel balance read raced the discovery walk and captured bark's
  transient mid-walk overcount (289,848 vs 143,041; a change output looks
  unspent until its spending tx is discovered). The refresh task group now
  re-reads the onchain balance (`refreshOnchainBalance()`, local state, no
  network) right after the onchain history fetch stabilizes. On-device
  verified 2026-08-13: balance settles without a manual refresh.
- [x] **Phase 2**: DONE 2026-08-13 — no shadow BDK wallet at startup (the
  three background full scans on create/import/open are gone). Renamed to
  `BDKFeeEstimator`, created lazily by `ensureFeeEstimator()` on the first
  send-flow fee estimate (fresh DB → one-time full scan), cleared at wallet
  shutdown. Light verify: open the send screen with an onchain source and
  confirm the fee preview + max-send still work (first use pays the scan).
- [ ] **Phase 3** (blocked upstream): full removal + drop `bdk-swift` once
  bark exposes onchain estimate/drain fee APIs.
- [x] **Feedback doc**: updated 2026-08-13 — §2.5 marked mostly resolved
  (block time on `BlockRef` remains), new §2.5b estimate/drain ask, §2.6
  extended with the seed-import invisible-funds case, pagination noted
  under Priority 3, summary table rows 7/7b/7c.

## Desktop Parity

See `Features/Desktop_Parity.md` (onboarding, settings, launch/registration
done).

- [x] **ArkeDesktop duplicate-doc-basename build break — FIXED 2026-09-21**
  (commit `834a1f4`), re-verified green 2026-09-24:
  `xcodebuild -scheme 'Arké' -destination platform=macOS` builds. ArkeDesktop
  flat-copies `Docs/` into `Contents/Resources`, so duplicate basenames
  collide; `Docs/Migrations/Bark-0.19.0-to-0.23.0/` and
  `Docs/Migrations/Bark-0.23.0-to-0.24.0/` (8 files) plus the review playbook
  were never added to the ArkeDesktop `membershipExceptions` list, unlike the
  other five migration folders. Still open as a process item: add a
  Migrations-folder exclusion step to the bindings-bump checklist so the next
  bump doesn't repeat it (third occurrence of this break).
- [ ] **Exit UI** on desktop.
- [ ] **Notifications** on desktop.

## SwiftData / CloudKit Invalidation

Context: on 2026-09-23 the second iPhone crashed on launch rendering the
activity list — the CloudKit import deleted a `TransactionTagAssignment` row
while `PersistentTransaction.associatedTags` was walking the transaction's
already-materialized `tagAssignments` array, and reading the dead instance
trapped ("This model instance was invalidated because its backing data could no
longer be found the store"). The rule that came out of it: **resolve
relationships with a fetch and read the results in the same synchronous
main-actor pass; never read element properties off a cached relationship array
that may have been materialized in an earlier pass.** Fixed for the transaction
list path (`associatedTags`/`associatedContacts`, `PersistentTag`/
`PersistentContact.associatedTransactions`, `liveAddresses`, plus the bulk
`TransactionMetadataSnapshot` the lists render from), covered by
`TransactionMetadataResolutionTests`.

Extended to the **write paths** 2026-09-25 (review finding: the fix had
covered reads but not writes): new `liveTagAssignments`/`liveContactAssignments`
on `PersistentTransaction`, `liveAssignments` on tag/contact, and a live
accessor on `PendingPaymentMetadata` (whole-table fetch + `persistentModelID`
filter — no domain key, table holds only unmatched sends); the count/bool
accessors (`tagCount`, `hasTags`, `transactionCount`, `addressCount`, …) now
share the same fetches so they can't disagree with the resolved lists; swept
auto-tagging, pending-metadata application, the Send flow's replace-assignment
deletes, `ContactAddressService`'s primary-flag loops, `WalletManager+Contacts`
address learning, `PaymentInfoReceivedSheet`, and import/export. Remaining
cached-array reads are count/isEmpty-only and annotated in place. Dead code
removed: `cacheExistingTagAssignments`, the `TransactionModel+OnchainAdapter`
statics (file emptied — needs an Xcode pass to delete). Pinned by
`TransactionMetadataWritePathTests` (8 tests, second-context deletes).

- [ ] **On-device verify on the second iPhone**: launch during the initial
  CloudKit import (the crash repro), then assign/unassign a tag from the
  transaction detail and confirm the list label updates (the `dataVersion`
  dependency moved from the row to the list), and check a tag-filtered and a
  contact-filtered list.
- [ ] **`TransactionCardStackView_iOS` holds `[PersistentTransaction]`** in
  `@State` for the overlay's lifetime and re-converts on index/`dataVersion`
  changes. Tag and contact resolution is safe now, but if an import deletes the
  movement row itself while the overlay is open, reading the transaction's own
  properties still traps. Fix: have the presenting list pass txids (safe to read
  at tap time) and re-fetch the window; needs the entrance/drag choreography
  re-verified on device, so it was left out of the 2026-09-23 pass.
- [x] **`MetadataExportService` walks cached assignment arrays — FIXED
  2026-09-25**: exports now build from `liveTagAssignments`/
  `liveContactAssignments` (which carry `assignedDate`), so an export can
  neither trap nor emit rows a CloudKit import deleted. Pinned by
  `exportOmitsDeletedAssignments`.
- [x] **`PendingPaymentMetadata.associatedTags` — FIXED 2026-09-25**: the
  "no stable id" blocker dissolved — the live accessor fetches the whole
  `PendingTagAssignment` table (tiny: only unmatched sends) and filters by
  `persistentModelID`, which is instance metadata and can't fire a fault.
  Pinned by `pendingMetadataLiveAssignments`.
- [x] **Fetch-based accessors made the refresh path a fetch storm — FIXED
  2026-09-25** (review finding on eb4f520): the single-arg
  `TransactionModel(from:)` runs a fetch pair per transaction, and
  `ContactModel(from:)` aggregates over every one of the contact's
  transactions — mapping whole lists through them made each refresh
  O(transactions × contact usage) on the main actor. Hot paths
  (`TransactionService.transactions`, `UnifiedTransactionService`'s onchain
  merge, `TransactionListModel`) now bulk-bridge through one
  `TransactionMetadataSnapshot` per pass, and the snapshot uses a new
  row-weight `ContactModel(rowFrom:)` (aggregates nil — no list row reads
  them). Cold single-item sites deliberately stay on the single-arg init (its
  doc comment now warns against loops). Equivalence pinned by
  `TransactionBridgingEquivalenceTests`; a non-asserting `ContinuousClock`
  measurement lives in `bridgingCostMeasurement`. Candidate follow-up if the
  contacts screen ever lags: `ContactService`'s own loads still use the full
  aggregating init per contact — a statistics-service join would batch it.

## UI / Refactors

- [ ] **Previewable models extraction, Phase 3b** (paused; opportunistic,
  per feature area). See `PREVIEWABLE_MODELS_EXTRACTION_PLAN.md`.
- [ ] **Live Activity across device migration**: `closeWallet()` /
  demotion deliberately keeps an in-flight exit's Live Activity alive
  (only wallet *deletion* ends it, since 2026-08-12). Revisit whether
  demotion should end it too, since the demoted device stops progressing
  the exit.
- [ ] **Tap-outside keyboard dismissal for the send flows**: added to
  Boarding/OffboardingModalFormView 2026-08-21 (iOS-only `contentShape` +
  `onTapGesture` clearing focus, as fallback for the flaky keyboard-toolbar
  Done button in sheets). ManualSendView, QuickPaymentView, and
  ContactPaymentView still rely on the toolbar alone — they have multiple
  fields and denser layouts, so apply with a closer look.
- [ ] **ArkeGlassButton adoption sweep**: new ArkéUI component
  (2026-08-24) centralizing the repeated glass-button recipe
  (glassProminent/glass + large control + gold tint + title2 semibold
  gold4/primary label + full width + isLoading spinner swap). Adopted in
  DeviceAssignmentSheets_iOS only; ~45 `.glassProminent` and ~29 `.glass`
  call sites across ~39 files remain hand-styled — migrate opportunistically
  or in one pass. Note some legacy sites use `size: 21` instead of title2
  and `.regular` control size; the component canonicalizes to
  title2/`.large`, so expect slight visual normalization when sweeping.
  The pre-glass custom `ArkeButtonStyle` (5 call sites) is a separate
  later cleanup.
- [ ] **ArkeCircularIcon adoption sweep**: new ArkéUI component
  (2026-08-24) — white SF Symbol on a circular scratch-surface texture
  with drop shadow (default 75pt circle, 30pt icon). Adopted in
  DeviceAssignmentSheets_iOS; other bare large-icon sites to migrate:
  FaucetModalView_iOS, PaymentInfoReceivedSheet, QRScannerView_iOS,
  desktop WalletCreatedView/WalletImportedView. The texture is
  deliberately duplicated in ArkeUI/Sources/Media.xcassets (package
  needs its own bundle copy; Shared copy stays for
  ScratchableMnemonicGrid's main-bundle lookup).

## Themes

Setting + picker shipped 2026-08-20 (`AppTheme`, `ThemeSettingView`, iOS
settings row; both themes still point at the original assets). Remaining:

- [x] **All five surfaces themed — 2026-08-20**: BalanceView_iOS (balance
  background), TiltShareOverlay_iOS, LightningInvoiceFormView_iOS (keypad
  texture), LightningInvoiceSheet_iOS (receive QR) now read
  `theme.images.*` via @AppStorage; only AppTheme.swift still names the
  classic assets. On-device pass of all themes done 2026-08-21.
- [x] **BalanceCard themed — 2026-08-20**: card, card-mask, hidden-card via
  `theme.images.*` (@AppStorage stores the enum directly); cornfield/unicorn
  format easter eggs deliberately still override the theme's hidden image.
  Desktop card themes too (always `classic` there until a picker exists).
- [x] **Real art for the second theme — 2026-08-20**: renamed tuscany →
  ginkgo with dedicated `ginkgo-*` asset sets (Christoph); de/ja for
  `theme_name_ginkgo` applied via scripts.
- [x] **Hidden-card holo + per-theme text color — 2026-08-21**: hidden card
  renders as HoloCard on iOS when `ThemeImages.hiddenCardMask` is set (nil
  = flat; easter eggs and macOS stay flat); `AppTheme.textColor` colors the
  hidden wordmark, hex-overridable per theme, defaults to Arké gold. The
  holo sheen stays hard-coded gold by decision.
- [x] **Ginkgo hidden-card polish — 2026-08-21**: dedicated
  `ginkgo-card-hidden-mask` + `textColorHex` (`F3F4F2`) shipped; art
  finalized and device-verified by Christoph.
- [x] **Desktop settings entry — 2026-08-21**: `SettingsDetailItem.theme`
  case + General-section row in the desktop SettingsView, opening the
  shared `ThemeSettingView`; unblocked by moving the theme art into
  `Shared/Media.xcassets` (see below). Pending: visual pass on macOS.
- [ ] **Reconcile the April theme plan doc**
  (`Features/theme-system-implementation.md`, commit 95c7828): sketches a
  color-first system (ThemeManager, per-theme color asset variants) that
  differs from the shipped image-only `AppTheme`; fold its palette ideas
  into the color-palette item below or archive it.
- [x] **Consolidate app art into one shared asset catalog — 2026-08-21**.
  Phase 1: `Shared/Media.xcassets` owned by both app targets (desktop
  automatic via the synchronized folder, mobile via one opt-in tick), 24
  theme imagesets moved there. Phase 2: all duplicated art deduped —
  51 identical mobile imagesets + the newer `safe` (loose/desktop copies
  were stale Oct 2025 art; desktop's safe image visually updated) moved
  to `Media.xcassets`, 5 desktop-only imagesets (`bodega`, `cover`,
  `kinto`, `second`, `success`) moved too, loose duplicates and desktop
  third copies deleted, dead `arke-qr-background 1` straggler removed.
  Both per-target catalogs now hold only icons + colorsets. Kept loose by
  design: `arke-icon(-100).png` (ArkeWidgets uses them; Media membership
  would drag theme art into the widget bundle), the 8 demo avatars
  (desktop-only, never duplicated), all videos, and
  `arke-recovery-phrase-backup-sheet.pdf` (loaded via
  `Bundle.main.url(forResource:)` — catalogs can't serve it; the dedup
  glob briefly deleted it, restored in a07f3fc). Note: `arke-qr-background`
  in Media is referenced nowhere — delete if no plans for it. Lesson: 
  deleting synchronized-folder files outside Xcode leaves stale
  membership-exception entries in the pbxproj that fail BOTH GUI and CLI
  builds ("Build input file cannot be found"); fixed by scripted removal
  of entries pointing at nonexistent files, verified by both-platform
  builds + bundle inspection (assetutil).
- [ ] **Send-modal (and balance-modal) video sizing** — parked 2026-08-21,
  all code changes reverted; revisit with design intent settled. Key
  finding to keep: the reaction videos display LANDSCAPE ~3:2 — they are
  encoded portrait with a 90° rotation transform, so raw pixel dimensions
  (mdls, AVAsset naturalSize) lie about orientation; only presentationSize
  or a rendered thumbnail shows the truth. A full-width 3:2 window
  (height = width × 2/3, top-pinned, `.clipped()`) showed the entire video
  in the medium detent in simulator screenshots but wasn't accepted
  visually. Balance modals (boarding/offboarding/refresh) use the same
  `aspectFill` pattern and share whatever fix lands.
- [ ] **Per-theme color palettes** (deferred by design).

## Metadata Export / Import (guiding doc: `Features/Metadata_Export_Import.md`)

- [ ] **DECIDED 2026-08-23, ready to build — file-based export/import of user
  metadata** (contacts, tags, transaction notes/assignments, personal profile)
  in the Manual Backup section. Versioned JSON envelope with dedicated DTOs,
  upsert-by-identity merge with newest-wins, annotations keyed by txid,
  plaintext (no warning copy), no auto-export. Phasing in the doc: 1 export,
  2 import + merge, 3 QA/localization. Phases 1+2 shipped 2026-08-23
  (export device-tested; import unit-tested 234/234). Remaining:
  on-device import round-trip (export on one device → import on a fresh
  wallet), then Phase 3 — the 10 new `metadata_*` keys need an IDE build to
  extract into the catalog, then `apply_translations.py` +
  `translation_lint.py` for de/ja/zh-Hant.
- [x] **Shrink avatar data at every write site — FIXED 2026-08-23** (found
  via a 1.2MB export where one avatar was ~900KB). Root cause was the
  default faucet contact storing the bundled `faucetto-signetto` asset as
  full-res PNG (`ContactService+DefaultContacts`), NOT the native-contact
  path (which already prefers the small thumbnail). Fix: new
  `AvatarImageProcessor` in ArkéUI (512px, JPEG 0.8, white-flattened alpha,
  scale-1 rendering so device scale doesn't multiply pixels) now used by the
  contact editor (was 300px PNG), profile picker (private duplicate
  deleted), the native full-image fallback, and default-contact creation;
  plus a one-time launch pass `reencodeOversizedAvatarsIfNeeded()`
  (>150KB → re-encode, UserDefaults-gated, piggybacks on
  `createDefaultContactsIfNeeded`) that shrinks existing stores, CloudKit
  payloads, and exports. Preset avatars are JPGs (no alpha) — safe. Both
  builds green, mobile suite green. Pending: on-device check that the
  faucet avatar re-encodes and the export drops to ~KB size.
