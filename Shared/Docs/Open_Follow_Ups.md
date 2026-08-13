# Open Follow-Ups

Cross-feature list of known open items so nothing gets lost between sessions.
Detail lives in the linked docs — this file is just the index. When an item is
finished, check it off with the date (move to a Done section or delete once
stale). Last consolidated: 2026-08-12.

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

## Startup & Initialization

- [ ] **Startup wallet detection review follow-ups**: 8 items listed in
  `Initialization/REVIEW.md` / `Initialization/STARTUP_WALLET_DETECTION_PLAN.md`
  (phases 1–4 done); optional Phase 5 refactor.
- [ ] **Seed-recovery scan never runs on import**: our initWallet+open
  two-step bypasses bark's recovery scan (gated on `created_now`). Fix is a
  single `Wallet.open(createWithoutServer:)` call. Until then, restoring from
  seed alone silently shows an empty wallet.

## Background Execution

See `Features/Background_Execution.md` (Phase 1 done, soak running).

- [ ] **BGTask grant frequency**: evaluate soak results (how often iOS actually
  grants the refresh task).
- [ ] **Phase 2**: mailbox push wake → full background pass. Relay stays dumb.

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
