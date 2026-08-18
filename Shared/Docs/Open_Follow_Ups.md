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
  guard test + full suite. See the rollout plan.
- [x] **defaultValue migration — on-device smoke pass — verified 2026-08-17**
  (iPhone + macOS, no raw-key sightings). The desktop build's extraction also
  exposed one last hand-assembled plural in
  `TransactionLinkedOnchainView_macOS` — fixed with `^[…](inflect: true)`.
  Migration fully complete; see `Localization/Default_Value_Migration_Plan.md`.

## Wallet Deletion & Device Registry

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
- [ ] **Decide the fail-safe direction of `getDeletionStrategy()`'s error
  fallback**: when the other-devices check fails, it falls back to
  `.promptForCloudData` — i.e. a full wipe — even if other devices actually
  exist. The shown copy is accurate, but the conservative fallback would be
  `.localOnly` (keeps cloud data at the cost of possible leftovers).
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

## Background Execution

See `Features/Background_Execution.md` (Phase 1 done, soak running).

- [ ] **BGTask grant frequency**: evaluate soak results (how often iOS actually
  grants the refresh task).
- [ ] **Phase 2**: mailbox push wake → full background pass. Relay stays dumb.

## Bindings Adoption

`Bark_Bindings_Unadopted_API.md` (created 2026-08-17) records everything the
bindings offer that we haven't adopted, with feature implications — roadmap
inspiration lives there. Baseline: bindings v0.18.0 / bark v0.6.1 (the
v0.17→v0.18 bump was purely additive; nothing broke).

- [ ] **Keep the unadopted-API record current on every bindings bump**: diff
  the release commits in the package checkout, add new surface, move adopted
  items to its Adopted-since section.

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

- [ ] **Exit UI** on desktop.
- [ ] **Notifications** on desktop.

## UI / Refactors

- [ ] **Previewable models extraction, Phase 3b** (paused; opportunistic,
  per feature area). See `PREVIEWABLE_MODELS_EXTRACTION_PLAN.md`.
- [ ] **Live Activity across device migration**: `closeWallet()` /
  demotion deliberately keeps an in-flight exit's Live Activity alive
  (only wallet *deletion* ends it, since 2026-08-12). Revisit whether
  demotion should end it too, since the demoted device stops progressing
  the exit.
