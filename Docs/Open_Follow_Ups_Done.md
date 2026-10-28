# Open Follow-Ups — Done Log

Closed items moved out of `Open_Follow_Ups.md` on 2026-10-07 when that file
was restructured into priority tiers. Everything here is verbatim from the
index as it stood that day, grouped under the original section headers, with
the section intros kept for context. Nothing in this file is open work; the
value is the write-ups (root causes, decisions, verification evidence) that
later debugging keeps reaching for. New closures (DECIDED 2026-10-19): check
the item off in `Open_Follow_Ups.md` with the date and move it here in the
same commit, under a matching header or a dated "Moved from the open list"
section; the open file never holds ticked lines.

## Localization
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

## Wallet Deletion & Device Registry
- [x] **Two-device on-device verify of the deletion override — DONE
  2026-09-26** (Christoph, two linked devices, against the 2026-09-25 build
  with the recency gate, pre-wipe recheck and seed-last ordering): the flow
  "works much better". Individual scenarios below were not reported
  one-by-one, so treat the checklist as passed-in-aggregate rather than
  ticked line by line.
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
- [x] **Tombstone KVS-transient fix — DONE 2026-08-20**: a missing KVS hash
  clears the tombstone only when the keychain corroborates with a definitive
  `.notFound`; seed-still-present or unreadable keychain keep the rejoin
  route. Tested in `TombstoneRoutingTests`.
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

## Exits
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

## VTXO Refresh (guiding doc: `Features/Refresh_Deduplication.md`)
Diagnosed 2026-09-21: three writers (auto service, manual UI, bark daemon)
schedule refreshes from overlapping pools with no "already being refreshed"
exclusion; balance card shows "Refresh now" during an ongoing refresh. Bark
facts verified at the bark-0.7.1 tag (our 0.24 bindings). Approved and
implemented 2026-09-21 (`RefreshExclusion` unit-tested 9/9, mobile build
green):

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
- [x] **"Time to Refresh" reminder fired ~4x early on signet — fixed
  2026-09-27, device-verified same day**. `scheduleNextRefreshNotification`
  converted blocks to seconds at 150 s/block for any non-mainnet network;
  bitcoin signet runs ~10 min/block like mainnet (measured 10.8 min/block
  against mempool.space for 2026-09-26/27; the 2026-09-26 field log scheduled
  for block 323884 at "4.8 h out" and the chain hadn't reached it 18 h later).
  Because the app reschedules on every launch, the premature reminder
  repeated. Now uses `BlockTimeFormatter.secondsPerBlock` (600, same as the
  expiry UI) and recomputes on every foreground return
  (`checkAndRescheduleAfterForeground`, wired in `ArkeMobile.swift`). Not
  related to uninstall/reinstall churn — iOS drops pending local
  notifications on uninstall and in-app deletion cancels them.
- [x] **Hourly auto-refresh check silently skipped after 60 s — fixed
  2026-09-27** (found alongside the above; code-level, not seen in a log).
  `WalletCacheManager.getEstimatedBlockHeight()` read `blockHeight.value`,
  which is nil once the 1-minute cache expires, so the synchronous
  `estimatedBlockHeight` the hourly check and the reminder scheduler used
  was nil unless something had fetched the height in the last minute →
  "Missing required data … skipping". It also extrapolated by the Ark round
  interval instead of block time. Now extrapolates from the last *known*
  height at 600 s/block, and both service paths use the async
  `getEstimatedBlockHeight()` which refetches on expiry.
- [x] **Demotion left the refresh reminder pending — fixed 2026-09-27**:
  `resetManagerStateForMigration()` now calls `cancelScheduledNotification()`
  like the deletion path.
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

## Startup & Initialization
- [x] **Seed-recovery scan never runs on import** — fixed and field-verified:
  single `Wallet.open(createWithoutServer:)` shipped
  (`BarkWalletFFI+WalletCreation.swift`); imports on 2026-08-13 show the scan
  running and completing (`Seed recovery finished … complete=true`).
- [x] **`LaunchSequence` extraction** (done 2026-08-14):
  `ExitProgressionService.start()`'s ordered steps (reattach → first check →
  recreate → reminders) live in `LaunchSequence` (`ExitProgressionLogic.swift`)
  with injected effects and an order-pinning test
  (`LaunchSequenceTests/launchOrderIsPinned`); contract rule 8 now enforced.
- [x] **Import wipe-and-reopen retry decision extracted** (done 2026-08-14):
  `ImportRecoveryLogic` in `BarkWalletFFI+WalletCreation.swift`, decision
  matrix pinned by `ImportRecoveryLogicTests` (contract rule 2).
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
- [x] **BGTask grant frequency**: ~~evaluate soak results~~ answered from the
  relay side 2026-09-17 (124/151 mailboxes expired — not often enough); the
  `trigger` field on `/v1/register` now measures it server-side per wake path.

## Bark 0.23 Migration (minimal pass shipped 2026-09-08)
Guiding docs: `Migrations/Bark-0.19.0-to-0.23.0/`. Shipped: recompile,
`vtxoLifetime` migration, `UInt16` config-read widening, `stopDaemonWait()`
in all shutdown paths. Deferred adoption (see plan §2.2-2.4, §Phase 3):

- [x] **Update `Bark_Bindings_Unadopted_API.md`** for the 0.23 surface —
  done 2026-09-17 as a catch-up section during the 0.24 bump (baseline now
  v0.24.0).

## Bark 0.26 Migration (Track A built 2026-10-25; device + TestFlight pending)
Guiding docs: `Migrations/Bark-0.25.0-to-0.26.0/`. Built: 21 compile fixes,
`vtxoSwept` folded into cancelled (`isCancelled` now covers `.canceled` and
`.vtxoSwept`), four new balance fields with bark's total and the card's
`heldSat`, bark logger `redactMessages: false`, `OnchainWallet.initialScan`
after both import branches; `ArkBalanceTotalsTests` (6) and the swept pin
test; adversarial pass with two confirmed findings fixed (ledger
2026-10-25). The open release entry stays under Tier 4 "Bindings adoption"
until the device scenarios and the users' procedure are done. Closed here:

- [x] **0.25: `ExitClaimTransaction` included-ids gap** — answered upstream
  in v0.26.0 (`vtxoIds` / `skippedVtxoIds`, feedback ask 19) on 2026-10-25;
  the app-side adoption is the Tier 4 "0.26 Track B — claim link" entry.
- [x] **`initialScanOnchain(birthdayHeight:)` on import** — adopted
  2026-10-25 in `BarkWalletFFI.importWallet` for the seed-only and the
  backup-file branch (no UI state; the import view already blocks on the
  scan). Remaining halves filed separately: the launch-time iCloud restore
  path (Tier 1 Data safety) and a "scanning" import state (Tier 3).


## Bark 0.25 Migration (shipped 2026-09-26)
Guiding docs: `Migrations/Bark-0.24.0-to-0.25.0/`. Shipped: `drainAll`
plumbing (always `false`; empty-ids guard in `ExitClaimSequence`),
`mailboxAuthorization(expirySecs:)` with 30-day tokens
(`RelayRegistrationService.mailboxAuthorizationExpirySecs`), persisted relay
registration state + mid-life renewal rule (`needsRenewal` / `renewalDate`)
+ foreground trigger, `LightningReceive.amountSats` optional handling.
Open:

- [x] **On-device: first registration after the update — verified 2026-09-26**
  (Christoph, iPhone, signet): first run registered; second run's post-init
  path logged "Skipping relay registration (trigger: foreground) -
  authorization not yet due for renewal" and made no relay call; X-Ray shows
  "Relay auth expires" 30 days out and "Next auth renewal" 15 days out
  (log: `Docs/debug_logs.txt`, line 1120).
- [x] **Xcode Docs exclusion for the new Migrations folder — done 2026-09-26**
  (Christoph, Xcode UI): the four 0.25 doc files are excluded from
  ArkeDesktop's flat Docs copy (`project.pbxproj`).


## Bark 0.24 Migration (shipped 2026-09-17)
Guiding docs: `Migrations/Bark-0.23.0-to-0.24.0/`. Shipped: recompile +
`vtxoKeyGapLimit: nil` (gap limit 50 → 250 by design), widened
`foreign`-ids recovery retry (`ImportRecoveryLogic.retryPasses` +
`retryRecoveries`, `maxVtxoKeyGapLimit()` = 100_000), 4 new
`ImportRecoveryLogicTests`. Deferred:

- [x] **On-device import smoke of the widened retry** — done 2026-09-17:
  Christoph ran a seed import on device same day as the bump; import worked.
  (Log-line inspection of the per-pass retry outcomes wasn't part of the
  pass; revisit only if a foreign-VTXO case ever surfaces in the field.)


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
- [x] **Feedback doc**: updated 2026-08-13 — §2.5 marked mostly resolved
  (block time on `BlockRef` remains), new §2.5b estimate/drain ask, §2.6
  extended with the seed-import invisible-funds case, pagination noted
  under Priority 3, summary table rows 7/7b/7c.


## Payments / Send
- [x] **`PaymentRequestInfoBanner` removed 2026-09-27** as dead code (defined,
  never referenced); its only string key `action_clear_payment_request`
  becomes an orphan the next catalog re-extraction prunes. Git history:
  `Shared/Views/Send/PaymentRequestInfoBanner.swift`.


## Payments / Receive
- [x] **Invoice creation feedback on slow networks — COMMITTED 81900a9,
  device-verified 2026-10-01** with Network Link Conditioner (the slow path).
  The failure path was not reached because the test didn't wait for bark's
  timeout; see the timeout item below. On a bad connection the iOS receive form gave
  no response to the checkmark for several seconds. `isGeneratingInvoice`
  and `invoiceError` were never read on iOS, so failures were silent too.
  Now the QR sheet opens right when the checkmark is tapped and shows "Creating
  Invoice..." in the QR's place. On failure it offers Try Again or Share
  Addresses Instead. Share stays disabled until the invoice exists. Repeat
  taps are ignored, and a late answer to a closed request is discarded
  (`invoiceRequestID`). The post-invoice `sync()` (added 976e488 with
  `LightningClaimService`) now runs in the background and can no longer throw
  away a valid invoice.

## Fiat Rates (guiding doc: `Features/Fiat_Rates.md`)
Phase 1 (client + cache + triggers + X-Ray section) shipped 2026-09-28,
19/19 unit tests, live-server check passed. Nothing user-facing shows fiat
yet, by design.

- [x] **Phase 2 — currency setting — built 2026-09-28**: `CurrencySettingView`
  (Shared, modelled on `ThemeSettingView`), `FiatCurrencyPreference`
  (stored → locale currency if cached → USD; 5 tests), `fiatCurrencyKey`,
  General-section row "Currency — Currently: USD". Owed: on-device look.
- [x] **Credit placement — decided 2026-09-28**: the "Rates by Exchange Rate
  API" link lives in the picker's footer; no About screen.
- [x] **`LightningInvoiceSheet_iOS` / BIP-21 read the unit-format amount as
  a sats string — FIXED 2026-09-29** in the fiat-input groundwork: the
  whole receive chain now passes `amountSats: Int?` from
  `ReceiveViewModel`. Under a decimal unit format the amount used to be
  dropped from every payment link and shown raw on the sheet.
- [x] **On-device look at X-Ray section and currency picker — done by
  Christoph 2026-09-28**, looked good.
- [x] **Lightning invoice limit mismatch — FIXED 2026-09-29**: both the
  keypad cap (was 1 BTC) and the view model cap (was 0.1 BTC) now derive
  from the server's advertised `maxVtxoAmount`; neither number had a
  technical basis (see `Features/Fiat_Rates.md` §7 step 2). Refused keys
  now give a warning haptic.

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
  bump doesn't repeat it (third occurrence of this break). **Superseded by
  the item below** — a folder-level exclusion makes the per-bump step and
  the unique-basename rule unnecessary.
- [x] **Docs out of every target — DONE 2026-09-27** (decided by Christoph:
  "it's just documentation, there is no code there"). What actually
  happened, in order: (1) Christoph ticked ArkeMobile on the `Shared`
  synchronized folder; Xcode deleted the 313-entry Mobile inclusion list and
  attached Shared to the target — Mobile now gets every Shared file
  automatically, same as Desktop (ArkeWidgets stays opt-in with its 3-file
  list). (2) `git mv Shared/Docs Docs` moved all 229 docs to the repo root,
  outside any synchronized folder, so they belong to no target; Xcode pruned
  all 213 stale `Docs/...` entries from the Desktop exception list by
  itself. (3) Mobile build green via Xcode; Desktop build NOT run at the time — it
  turned out broken, see the ActivityKit item below. (4) All `Shared/Docs` path references rewritten to
  `Docs` (11 Swift comments, 19 docs, assistant memory). The unique-basename
  rule and the per-bump Migrations-exclusion step are retired
  (`Documentation_Inventory.md` updated). Pre-check: nothing in Docs is
  bundle-loaded at runtime.
- [x] **Desktop build broken by e744bb6, FIXED same day (2026-09-27) — `'ActivityAttributes' is
  unavailable in macOS`** at `Shared/Models/ExitProgressActivityAttributes.swift:15`.
  Cause: when Xcode rewrote the project after the Docs move it dropped the
  ArkeDesktop "Exceptions for Shared" set *entirely* — not just the 213 Docs
  entries but also its two other entries, `Models/ExitProgressActivityAttributes.swift`
  and `Images/cover-animation.mp4` (the working copy still showed them
  right after the move; Xcode's later save removed them before the commit).
  So macOS now compiles the attributes file, which imports ActivityKit
  unguarded, while its sibling `ExitProgressionService+LiveActivity.swift`
  is already wrapped in `#if canImport(ActivityKit) && os(iOS)`.
  **Fix applied (approved):** wrapped the attributes file in the same
  `#if canImport(ActivityKit) && os(iOS)` guard — one island, no
  project-file exclusion to lose again (exception sets were rewritten
  twice today). Safe because the only consumers are the guarded extension
  and the iOS-only ArkeWidgets target, and the app-level `ExitState` enum
  in that file is never used on macOS (all other code uses `Bark.ExitState`).
  Alternative: re-tick the exclusion in Xcode's File Inspector — fragile.
  Verified: `xcodebuild -scheme 'Arké' -destination platform=macOS` and
  `-scheme 'Arke mobile' -destination 'generic/platform=iOS Simulator'`
  (widgets included) both green. Side effect of the same loss:
  `cover-animation.mp4` (unreferenced) now ships in the macOS bundle too —
  covered by the dead-images item above.

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
statics (file emptied; deleted in 34b938a). Pinned by
`TransactionMetadataWritePathTests` (8 tests, second-context deletes).

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
- [x] **Standardize `Docs/` filenames — DONE 2026-09-27** (assessed 2026-09-27, Christoph:
  "makes sense"). **Batch 1 DONE 2026-09-27:** inventory Steps 25–26 closed
  and 47 finished/superseded docs moved to `Archive/` after code
  verification (living 152 → 105; details + per-file evidence in
  `Documentation_Inventory.md` → "2026-09-27 archive pass"). 24 links
  auto-repointed, plain-text mentions and 2 Swift comments by hand; README
  rewritten. **Held items resolved 2026-09-27** (approved): auth-wake spec merged into
  `Features/Background_Execution.md` + archived; lightning fee-estimation
  issues archived (open item → Payments / Send above); quick-payment source
  guide merged into `SendView_Architecture.md` + archived; APNS spec →
  `API/Relay_Registration_API.md`; `Features/Theme_System.md` written.
  **Batch 2 DONE 2026-09-27** (inventory Step 27): all 27 living
  off-convention files renamed to `Title_Case_With_Underscores` with plain
  `git mv`; four `intro.md` indexes → `README.md` (rewritten to list every
  doc); `Address_History`, `Send_Metadata` rewritten plan → reference,
  `Process_State_Service`, `Balance_Persistence` refreshed against the
  code; `CloudKit/`, `Address history/`, `Payment destination selection/`
  folders dissolved; exceptions recorded in the inventory's naming section.
  Zero off-convention living docs remain. Follow-ups: `Features/Theme_System.md`
  written; consider `Data samples/` → `Data_Samples/` (folder names were
  out of scope).

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
- [x] **Reconcile the April theme plan doc — 2026-09-27**: plan archived (never built); `Features/Theme_System.md` now documents the shipped image-based system; the palette idea lives on in the item below. Original note:
  (`Archive/Implementations/theme-system-implementation.md`, commit 95c7828): sketches a
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

## Metadata Export / Import (guiding doc: `Features/Metadata_Export_Import.md`)
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


## Reminders Backlog Merge (2026-10-07) — closed for the record

Shipped: exit live activity not cleared / fresh-import live widget (Exit
Completion Issues); BIP-353 unauthenticated DNS, ATS disabled, recovery
phrase on general pasteboard (PR #8, iOS; macOS half still open); receive
"share address instead" on slow networks (81900a9); delete on one or all
devices + all-data wipe coverage; Esplora/Ark config sync via iCloud; refresh
dates on foreground (bcdb0fa); background-process expiry tracking (answered:
relay wakes); ₿ prefix detection; onchain fee priority picker
(`FeeSelectionSheet`); identicons (Hallmarks); native-contact import, refresh
and unlink-on-delete.

Dropped: move bark-data-ffi into iCloud (contradicts the per-device wallet
database; only the seed is in iCloud); "does reinstall delete contacts, tags,
assignments" (CloudKit restores them); remove UTXOs if bindings don't expose
them (they do); review Kumulynjas custom onchain wallet (BDK reader removed).

Duplicates of items already in the index: `EmergencyExitFeeEstimate` and
`RoundFlowKind` (Bindings doc); "delete wallet – block if devices still
syncing, with override" (Multi-Device S7); payment-notification navigate,
onchain-deposit notifications (Background Execution Phase 2).


## Backlog Hygiene Pass (2026-10-09)

Every Decisions, Tier 0 and Tier 1 entry checked against the code and the
deployed bindings (v0.25.0+bark-0.7.1) by six parallel read-only agents, plus
a whole-file duplicate sweep; one claim settled by execution. About two
thirds of the entries held apart from line drift; corrections were applied
in place in the open file. Closed here:

- [x] **Get Patrick's private write-up** (2026-10-08): received with a
  parser repro harness; every claim spot-checked against `main` held. The
  new findings were filed in their tiers (the two backup items, the
  `shouldBlockWalletAccess` sibling, metadata import and store deletion,
  resolver and prefix notes, branch pins, `SECURITY.md`). Relay server-side
  observations are handled with the relay, outside the backlog. The harness
  runs on a Mac with a `swiftc` wrapper that adds `-sdk`; the eight parser
  traps it documented are confirmed fixed by execution.
- [x] **Blocked-strategy copy** — the third state ("couldn't check") already
  existed: `DeleteWalletSettingView.swift:238-243` shows
  `settings_delete_warning_check_failed` when the blocker report is nil,
  landed in ed9d8fe with the reduced S7. The item had outlived its fix; the
  old `DeletionStrategy.title/message` strings are now a Tier 4 dead-code
  line.
- [x] **Devices-list display scoping** — done 2026-09-24 with the Linked
  Devices wallet-hash scoping (both list views filter on
  `device.walletHash == accountWalletHash`); the Tier 4 line was a leftover.
- [x] **Delete the emptied `TransactionModel+OnchainAdapter` file** — deleted
  in 34b938a (2026-09-26). The `arke-qr-background` half stays open.
- [x] **Bark 0.16 v1-snapshot wallet upgrade path** — retired unverified:
  three bindings bumps later no field device can still hold a v1 snapshot.
- [x] **BIP39 checksum is not validated on import — demoted from Tier 0**:
  `MnemonicChecksumTests` (new, 6 tests, green on the iPhone 17 Pro
  simulator) shows `OnchainWallet.default` throws `invalid mnemonic: the
  mnemonic has an invalid checksum` / `mnemonic contains an unknown word`
  before any network I/O, and the binding's `validateMnemonic(mnemonic:)`
  returns `false` for both. A typo never opens a different wallet; the
  remaining gap is UX (the live pre-check tests word count only) and lives
  in Tier 3 First use.

Also recorded for the method: the entries that were wrong in kind, not just
in line numbers, were all "mechanism" claims — which gate drops a reminder,
which service polls, which view shows an error — rather than "what" claims.
Grep confirms a symbol exists; only a trace confirms it runs.

## Moved from the open list 2026-10-19

Sweep of `Open_Follow_Ups.md` on 2026-10-19: every ticked item still in the
open file, verbatim, grouped by the section it sat in, plus one question
answered and closed the same day. The seventeen 2026-10-10 rulings and two
2026-10-19 rulings are kept here because the entries they produced carry the
DECIDED label in place.

### Decisions needed (Christoph)

- [x] **DECIDED 2026-10-19 — ceiling alone for Lugano, the gate as a Train 2
  Tier 1 item; ceiling value 10,000 confirmed** (Christoph: "I'll follow
  your recommendation"). The gate is filed under Tier 1 "Send and fees".
- [x] **DECIDED 2026-10-19 — exit cost estimate: adopt
  `estimateEmergencyExitFee` as a replacement, Train 2 Tier 1; a thrown
  estimate does not block the exit; dead ArkéUI fee arithmetic deleted in
  Train 2's opening hygiene pass; bark's `OnchainWallet.feeRates()` recorded
  in the unadopted doc, not filed** (Christoph: "do it", on the
  recommendation from the unadopted-fee-bindings review). Filed under Tier 1
  "Exits" and Tier 4 "UI components, refactors, tooling".
  Original question: what an onchain send does when the mainnet fee estimate
  sits at the ceiling (`Features/Mainnet_Fee_Rate_Ceiling.md` §10,
  PROPOSED 2026-10-19, from the ceiling's adversarial pass F2). The
  10,000 sat/vB ceiling removes the crash but turns a poisoned estimate
  that used to fail the viability check into a 1.4 M-sat fee that passes
  it for any wallet holding that much onchain; the fee line is the only
  guard. Options: (a) ship the ceiling alone, the fee line is visible and
  the hazard class existed below the old refusal point anyway; (b) the
  explicit-gate pattern (O5): fast tier at the ceiling disables onchain
  sending with "fee estimate unreliable", Ark and Lightning stay usable.
  **Recommendation: (a) for the Lugano build, (b) as a Train 2 Tier 1 item**
  — (b) is small but is new policy on the send path and needs its own
  device look. Also to confirm: the ceiling value itself (10,000; anything
  from ~5,000 up keeps the arithmetic safe). Blocks nothing in Train 1.
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
  Tier 1. Rule (1)'s "settles at the next round" superseded 2026-10-27:
  bark's path is a collaborative offboard, not a round, and the row
  carries no settlement caption (`Features/Send_Onchain_From_Payments.md` §7).
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

### Tier 0 — Funds or security at risk

- [x] **Mainnet fee rate can still crash the app** — **DONE 2026-10-19**:
  built, reviewed and device-checked the same day (uncommitted; plan
  `Features/Mainnet_Fee_Rate_Ceiling.md`):
  10,000 sat/vB sanity ceiling on mainnet, no uncapped mode left (the
  parser's cap defaults to the ceiling, the closure is non-optional), one
  warning line when a fetch is clamped, four tests replace
  `testNilCapPassesHighRatesThrough`. Adversarial pass (plan §8): no code
  defect, four findings, all acted on the same session. Corrections to the
  entry below: the ranker is the only `Int(...)` conversion, but the Exit
  screen's cost estimate (`ExitView_iOS.swift:313-323`) is a second
  overflow site that traps earlier; BDK and the FFI send fail soft (throw
  / error, verified at the tags). Confirmation screen at 250,000 sat/vB,
  traced not executed: a 0.35 BTC fee line, send enabled, the app's own
  viability check refuses the tap. Trade-off that needs a ruling (Decisions
  block): at the ceiling the same poisoning now prices a 1.4 M-sat fee that
  *passes* viability, so a visibly overpriced send becomes possible where
  it was refused before (ruled the same day: ceiling alone for Lugano, gate
  in Train 2). Device check PASSED 2026-10-19 (Christoph, mainnet phone,
  debug build; export `Docs/debug_logs.txt`): `Fee rates updated: fast 2,
  medium 2, slow 1 sat/vB` from `mempool.second.tech`, no clamp line; exit
  cost estimate rendered (33 VTXOs at 2 sat/vB → 75,019 sats, "can afford:
  false" against 20,000 sats onchain); the onchain destination ranked and
  the fee came from the ceiling-bounded fallback arithmetic (280 sats =
  2 × 140 vB) because BDK's estimator reported "0 BTC available" — a
  pre-existing gap filed as its own Tier 1 line under "Send and fees". Full
  mobile suite 565/565 after the adversarial pass (plan §9).
  Original entry: mainnet rates are
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
- [x] **Ghost-device hardening (1), residual — DONE 2026-10-19** (device
  check passed on both phones, plan §6.1; full-wipe step skipped on the
  mainnet pair; commits pending). Original entry: the mirror clear in
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
  **Plan DECIDED, BUILT and REVIEWED 2026-10-16** (uncommitted),
  `Features/Wallet_Deletion_Ghost_Hardening.md`: full writer/clearer/reader
  trace (one writer, two clearers), mirror clear moved ahead of every
  fallible step in both functions with a typed `UnregistrationOutcome` →
  `DeletionSummary.deviceUnregistration` (deletion continues, error-level
  line for the export), registration skip inside the dedup closure via the
  existing `setWalletDeletionInProgress` switch, `unlinkDevice` succeeds on
  a mirror-only ID (the Tier 1 "forget this device" item is UI-only now),
  `getOrCreateDeviceId` mints only on `errSecItemNotFound`, dead
  `cleanupStaleDevices` / `migrateToThisDevice` removed. Adversarial pass
  in plan §9: two claim fixes, one false-alarm fix, one plan correction,
  one pre-existing hazard filed below. Device check 2026-10-19 (plan §6.1):
  B-side local deletion, no ghost line, and re-registration after rejoin
  PASS from the console log; on A the device row vanished within seconds
  and the delete screen offered the full wipe after ~10 s of KVS lag (the
  CloudKit row deletion arrived before the mirror removal — a short
  mirror-only window, then clean). Full-wipe step skipped on mainnet.

### Tier 1 — What users hit every day › Send and fees

- [x] **Send onchain from the Payments balance** — DONE 2026-10-28 (asked
  by Neil, Second, 2026-10-07): a bitcoin address ranks as two rows,
  Savings and Payments (`BalanceSource.arkToOnchain`, a collaborative
  offboard), selection keyed on `PaymentDestinationSelector.Choice`; the
  "Pay from" sheet keeps one row per balance; the collapsed row reads "Pay
  from Savings"; Activity calls an onchain send "Moved" only when it went to
  an own address. Fault-class pass fixed, 617/617, signet device check
  passed. Not run: the forced parked error. `Features/Send_Onchain_From_Payments.md`.
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

### Tier 1 — What users hit every day › Data safety

- [x] **The wallet-created log line carries the mnemonic** — found and
  fixed 2026-10-19 (seen in the simulator log during the cosmetic-pass
  screenshots). `CreateWalletView_iOS.swift:247` and the desktop
  `CreateWalletView.swift:232` logged `createWallet`'s `String` result,
  which is the phrase, at info level; both now log the network and the
  word count. Interpolated values are redacted on device by default, so
  device logs and X-Ray exports never carried it; simulator logs are not
  redacted, and one `privacy: .public` edit would have exposed it. Sweep:
  the two import sites log the FFI's status string ("Wallet imported
  successfully…"), not the phrase — exempt; `BarkWalletFFI+Mnemonic.swift:41`
  logs entropy and word count only — exempt; `BIP39Usage.runExamples()`
  prints a demo mnemonic it generates itself and has no callers — dead
  example code, left as is; the old `[DEBUG] Loaded mnemonic` line in
  `BarkWalletFFI+WalletLifecycle.swift:73` is commented out. Rule for the
  playbook: a value that is or contains a seed is never interpolated into
  a log message, redaction or not.
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

### Tier 1 — What users hit every day › Multi-device (guiding doc: `Architecture/Multi_Device_Design.md`)

- [x] **Blocked-strategy copy** — already built (2026-10-09 hygiene pass):
  `DeleteWalletSettingView.swift:238-243` shows
  `settings_delete_warning_check_failed` when the blocker report is nil
  (landed in ed9d8fe). The old `DeletionStrategy.title/message` strings have
  no UI caller — Tier 4 dead-code line.

### Tier 3 — Polish by area › Receive

- [x] **Temporarily brighten the screen when showing a QR** — done
  2026-10-19: `ScreenBrightnessBooster` + `brightScreenWhileVisible()`
  (`ArkeMobile/Helpers/ScreenBrightnessBooster.swift`; the window scene's
  screen, not the deprecated `UIScreen.main`) on the two surfaces that
  render a QR: the invoice / addresses sheet (`LightningInvoiceSheet_iOS`)
  and the Tilt share overlay pages. User level saved on first boost,
  restored on dismiss and on leaving the foreground; iOS resets brightness
  on lock anyway. Simulator log 2026-10-19 (`category ==
  "ScreenBrightness"`, iOS 27.0 iPhone 17 sim): boost on sheet open,
  restore on Done, restore on Home with the sheet up, boost again on
  foreground, restore on Done, nothing on a tab round-trip — 6 lines, all
  as predicted. The first cut routed dismissal through an `onChange` on
  the sheet's own view and never restored (dismissed view tree, no body
  pass); caught by the same simulator run, fixed before build. The change
  ramps over 0.5 s (eased) after the instant jump read as a flash.
  Device-checked by Christoph 2026-10-19 ("works well"). Known limit: a
  Control Center change made while the sheet is up is overwritten by the
  restore. Finding on the way: the Receive tab's addresses page shows no
  QR at all — addresses with copy buttons and a share button only — so the
  QR lives in the sheet; the item's wording assumed otherwise.

### Tier 3 — Polish by area › Activity, transaction details, tags

- [x] **Balance tag shows "-0 B fees paid"; needs a no-fee state** — done
  2026-10-19: `TagRow` (`TagsView_iOS.swift`) shows "No fees paid"
  (`tags_no_fees_paid`) when `totalFees == 0`; the "—" for a tag with no
  transactions is unchanged. Not screenshotted in that state: it needs a
  wallet with fee-free internal transfers, which the simulator wallet
  lacks (list with "—" rows captured); device check with the real wallet.
- [x] **Exit status — long-press copy copies the truncated txid** —
  2026-10-19: not reproducible in the current code. The only long-press
  copy in the exit detail, `CopyableTxidRow` (since 152f0e3, 2026-07-15),
  copies the full id. Three txids in the state history
  (`ParsedStateDetails`: the processing-state transaction list and the
  "Claim TX" of claim-in-progress / claimed) were shown truncated with no
  copy at all; they now go through `CopyableTxidRow` too, so every exit
  txid on screen copies in full. If the report meant another screen,
  reopen with its name. Not screenshotted (needs an exit in progress).

### Tier 3 — Polish by area › Balance, board / offboard

- [x] **Loading wave on the balance details totals** (Christoph, 2026-10-19,
  PROPOSED — "not 100% sold"; built 2026-10-19, see the end of this
  entry): the balance card's glyph wave
  (`BalanceLoadIndicatorModel`) could also run on the separate payments and
  savings totals in the balance details view, each driven by whether *its*
  data is still loading (the Ark balance arrives before the onchain sync
  since the Ark-first refresh, so the two would settle at different
  moments). Purpose: someone wondering what is still loading gets the
  answer without a spinner or copy. **DECIDED 2026-10-19** (Christoph:
  "tackle the loading wave next") — rides in the Train 1 cosmetic pass.
  Premise check: no per-source loading signal existed; `isRefreshing`
  covers the whole refresh. Built as two flags written by `performRefresh`
  (Ark settles after Step 2b's early publish, onchain after Step 3's
  onchain balance read, both cleared when the refresh ends) and the card's
  wave machinery extracted into a `loadingWave(isLoading:)` modifier
  (`Shared/UI/LoadingWaveModifier.swift`) the two totals and the balance
  card share. Verified 2026-10-19 by the modifier's info-level log lines
  (`category == "LoadingWave"`) on the iOS 27.0 iPhone 17 simulator, two
  pull-to-refreshes on the details view: both totals arm at the pull; the
  Payments total returns to idle 0.2 s later when Step 2b publishes, so it
  never shows (the 1 s arming guard); the Savings total arms at 1 s, starts
  its pass, and finishes the pass when Step 3 ends; the Activity card still
  waves on the launch refresh. On the zero-balance simulator wallet the
  onchain sync lasts ~2 s, so the Savings wave is one pass; on the phone it
  runs for the ~25 s sync. Not seen in motion — device look owed. Tooling
  note: a first "no wave" verdict came from a stale simulator build (the
  run destination had been switched back to the phone, so Xcode built the
  device slice); always rebuild after switching destinations.

### Tier 3 — Polish by area › Refresh

- [x] **Warn when total VTXOs are under 330 sats** — done 2026-10-11 with the
  balance-card state: the row says "Too small to refresh" with the floor,
  the modal disables Start and names the amounts, the manual path returns
  `.belowMinimum` (`Features/Refresh_Deduplication.md` §10).

### Tier 3 — Polish by area › Settings, devices, deletion

- [x] **Rejoin wallet screen is unstyled** — already done by Christoph
  before 2026-10-19 (the committed `RejoinWalletView` has the circular icon
  and glass button); the line was stale from the Reminders merge. A second
  restyle generated on 2026-10-19 was reverted the same day. Note for
  Tier 3 evidence: Xcode previews cannot JIT-load the static `BarkFFI`
  framework in this setup (`CouldNotLoadInputStaticArchiveFile`, same for
  a view that imports nothing bark-related), so screens without a
  reachable simulator state need the device.

### Tier 3 — Polish by area › First use

- [x] **Image in move-to-payments has a slight white line on the left** —
  done 2026-10-19: it was in the asset. `board.jpg` column 0 averaged RGB
  (255, 253, 240) and column 1 (127, 112, 96) against ≈(90, 62, 33) for the
  picture; the two leftmost columns are cropped off (1001 → 999 px wide),
  re-measured clean. `offboard.jpg` has no such edge. The view's
  `.fill` + `.cornerRadius` + `.clipped()` chain is unchanged. Device check
  owed with the boarding minimum above (same modal, same gate).

### Tier 4 — Tech debt and deferred by design › Device registry cleanup

- [x] **Devices-list display scoping** — already done 2026-09-24 (Done log,
  Linked Devices wallet-hash scoping; both list views filter on
  `device.walletHash == accountWalletHash`). Closed 2026-10-09.

### Tier 3 — Polish by area › Send

- [x] **How to detect if an address is from a different Ark server?** —
  answered 2026-10-19, no app work filed: bark rejects an Ark address it
  cannot deliver to up front in `sendArkoorPayment` ("rejected up front,
  leaving the VTXOs spendable rather than cosigned", binding doc at
  v0.25.0), and `validateArkoorAddress(address:)` is the unadopted
  pre-check (`Bark_Bindings_Unadopted_API.md` §2) should the send flow want
  to tell the user before the attempt.

## Moved from the open list 2026-10-27

### Tier 0 — Funds or security at risk

- [x] **Pin `bark-ffi-bindings` and BIP39 to tags, not branches** — closed
  2026-10-27 (moved up from Tier 1 2026-10-09: supply chain into the
  component that holds keys). bark went to an exact revision on 2026-10-26
  (a68c69b, v0.26.0) and to `4670c1a` (v0.26.1+bark-0.8.0) on 2026-10-27;
  BIP39 went from branch `main` to exact 3.0.0 the same day (Christoph, in
  Xcode's Package Dependencies UI). Both were already resolving to those
  commits, so the resolved pins did not move. In the same pass bdk-swift
  went 2.3.1 → 3.1.1 (one call-site change in `BDKFeeEstimator`, the
  `NetworkKind` constructors) and qrcode 27.13.0 → 28.1.0 (no call-site
  change). Rules, the update recipe and the stale-`.pcm` trap are in
  `Development/Setup.md`.

### Tier 1 — Send and fees

- [x] **Fee row three-state, Lightning half** — closed 2026-10-27
  (PROPOSAL 2026-10-07; onchain half built the same morning). The ranker
  no longer hides a failed Lightning estimate behind a static 20 sats
  (`PaymentDestinationSelector.estimateFee` returns nil, viability judges
  the amount alone); the row says "Estimating…" while the request is open
  and "unavailable" when it failed; the unrendered `feeText` accessor chain
  is gone, so one screen can no longer show two fees. In quick mode with no
  viable destination Send is disabled by `canSendImmediately`. Write-up:
  `Features/Send_Fee_Quotes.md` §8.
- [x] **PROPOSED — gate Send while the fee row says "Estimating…"** —
  closed 2026-10-27, DECIDED and built as `SendBlocker.estimatingFee`: the
  row says "estimating" from the first keystroke (not from the end of the
  debounce, review F3) and Send is disabled with "Estimating the fee…"
  under it until the quote lands. The follow-on question, gating the
  approximate placeholder after a failed quote, is its own PROPOSED entry.
- [x] **Send-all can exceed bark's Savings balance** — closed 2026-10-27.
  `OnchainSendAll.cappedAmount` caps the drain at bark's `spendableSat`
  minus the drain fee; review F1 of the second pass found the capped
  amount re-quotes with a change output and a larger fee, so
  `OnchainSendAll.refit` shrinks it until amount plus fee fits, keeping the
  largest amount that fitted across BDK's non-deterministic coin
  selection. Simulator: 130,972 + 7,713 within 141,572, no orange flag,
  Send enabled. Write-up: `Features/Send_Fee_Quotes.md` §8.
- [x] **BDK fee estimator is blind to onchain funds after a relaunch** —
  closed 2026-10-27 (found 2026-10-19 as "blind to funds that arrived after
  its one full scan"). Root cause found the same day the fix shipped: the
  shadow wallet never called `Wallet.persist`, so in bdk 1.0+ nothing it
  learned reached SQLite and every launch started from an empty chain state;
  the revealed-address theory in the original entry was the symptom's
  shape, not its cause. Fixed by persisting after every applied update plus
  a 30 s sync window; the full-scan retry stays as the safety net. Device
  evidence (Christoph, mainnet, 2026-10-27): consecutive relaunches, no
  `finds no funds … running one full scan` line, first quote in about a
  second. Write-up: `Features/Send_Fee_Quotes.md` §8.7.
- [x] **Send-all waits ~5 s before the amount appears** — closed 2026-10-27
  (Christoph, mainnet device, same evening). The balance button filled the
  field only after the shadow wallet's incremental sync and drain build; it
  now fills at once with bark's spendable minus the rough placeholder fee
  while the fee row says "estimating" and the gate keeps Send disabled, then
  takes the exact drain amount. Same commit: the quick flow's destination
  row is a button only when there are alternatives, so a single destination
  is no longer dimmed as a disabled button. Device-checked "works great".
  Write-up: `Features/Send_Fee_Quotes.md` §8.9.

- [x] **Gate onchain sends while the mainnet fee estimate sits at the
  ceiling** — closed 2026-10-27 (DECIDED 2026-10-19 as a Train 2 item from
  the mainnet-ceiling adversarial pass). Built as `SendBlocker.feeEstimateUnreliable`
  and `FeeDisplayState.unreliable`: when the mainnet fast tier equals
  `FeeRateService.mainnetMaxRateSatPerVb` the fee row reads "Estimate
  unreliable" in orange and Send is disabled for onchain destinations; Ark
  and Lightning stay usable; the gate lifts on the next fetch below the
  ceiling. Unit-tested (`SendGateTests`). The definition of done asked for a
  device look with a forced clamp; **waived, DECIDED 2026-10-27** (no debug
  override; the condition cannot be produced on a real network, the state
  is rendered by the same path as the other fee-row states that were
  device-checked). `Features/Send_Fee_Quotes.md` §8.3.
- [x] **PROPOSED — gate Send on the approximate placeholder too** — DECIDED
  2026-10-27 **not to gate**. After a failed onchain quote the row shows the
  grey "~₿ …" placeholder and Send stays enabled. Reasons: the placeholder is
  marked approximate and sized not to undershoot the simplest Taproot send;
  the common failure (the never-persisted shadow wallet) is fixed; when
  Esplora is down bark's own send fails too, so a gate would add little while
  blocking all onchain sending. Revisit when bark exposes its own onchain
  estimate and the shadow wallet goes away.

## Train 1 (opened 2026-10-08, closed 2026-10-27) — archived Current train block

Moved verbatim from `Open_Follow_Ups.md` when Train 2 took over the block.

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

