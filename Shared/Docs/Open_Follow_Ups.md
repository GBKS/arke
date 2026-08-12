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
