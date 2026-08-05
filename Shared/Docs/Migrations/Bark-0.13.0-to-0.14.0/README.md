# Bark FFI Bindings Migration: v0.13.0 → v0.14.0

**Date:** 2026-08-04
**Status:** ✅ Completed 2026-08-04 — build green; upgrade-in-place verified on device 2026-08-05 (db migration + recovery registration + send/receive/refresh); fresh-create smoke pending, seed-recovery test deferred post-release (see [04-completion-report.md](./04-completion-report.md))
**Bark Version:** v0.4.0 → v0.5.0
**FFI Bindings Version:** v0.13.0 → v0.14.0 (resolved revision `316e38b`, branch `master`)

## Overview

Bark v0.5.0's theme is **seed recovery**: a recovery mailbox scan that runs
during the `Wallet.open()` that creates a wallet locally, plus the machinery
around it (`RecoveryReport`, `recoverVtxos`, `Vtxo.registered`,
`WalletOpenArgs.skipRecovery`). Secondary additions: delegated offline
Lightning receive (`bolt11InvoiceForAddress`, `LightningReceive.claimDestination`,
new `"delivering"` state) and scheduled delegated refresh
(`refreshVtxosScheduled`).

The Swift binding diff is **purely additive** — no method removed, no
signature changed, no type renamed. The only compile breaks are memberwise
initializers that gained parameters (`Vtxo`, `LightningReceive`), which in
this repo only hit mock/preview construction sites.

Because the migration was this small, there is no separate `02-migration-plan.md`;
changes were applied directly from the checklist in [01-api-changes.md](01-api-changes.md) §5.

## The changes that hit this repo

1. **`Vtxo` gains `registered: Bool`** — appended memberwise init parameter.
   Four mock/preview construction sites (`MockBarkWallet`,
   `BarkWalletFFI+VTXO` preview path). **Breaking**, mechanical.
2. **`LightningReceive` gains `claimDestination: String?`** — appended
   memberwise init parameter. Three mock/preview construction sites.
   **Breaking**, mechanical.
3. **`LightningReceive.state` gains `"delivering"`** — a `String`, so no
   compile break; unhandled switches would treat an almost-settled receive as
   "waiting". Two console formatters in `BarkWalletFFI+Lightning` updated
   (mapped alongside `"preimage-revealed"`/`"settled"` → claimed).
   `LightningClaimService` needed no change — it only matches `"htlcs-ready"`,
   and a delivering receive is correctly not claimable.
4. **Creating `Wallet.open()` now runs a network-backed recovery scan** —
   behavioral, no compile break. Decision made per open site:
   - `createWallet` (fresh seed): pass `skipRecovery: true` — nothing to
     recover, and the scan would block onboarding on a network round-trip.
   - `importWallet`, seed-only branch: keep the scan (it's what restores
     existing VTXOs) and log `recoveryReport()` after open via a new
     `logRecoveryReport(for:)` helper.
   - `importWallet`, restored-backup branch and the regular
     `WalletLifecycle` open: not creating opens, no scan runs, untouched.

Not adopted (yet): `bolt11InvoiceForAddress`, `recoverVtxos` retry,
`refreshVtxosScheduled`, surfacing `Vtxo.registered`. See the follow-ups in
[04-completion-report.md](04-completion-report.md) and the product framing in
[05-what-this-enables.md](05-what-this-enables.md).

No database filename change, no data migration.

## Impact summary

- **User experience:** Seed import now performs a recovery mailbox scan during
  wallet open (slower, needs network to be fully effective; result currently
  log-only). Fresh wallet creation explicitly skips it — no onboarding change.
- **Code changes:** 4 files (`MockBarkWallet`, `BarkWalletFFI+VTXO`,
  `BarkWalletFFI+Lightning`, `BarkWalletFFI+WalletCreation`).
- **Build result:** ✅ iOS build green (2026-08-04).

## Documents

1. **[01-api-changes.md](01-api-changes.md)** — Full API diff old → new,
   including recovery-bucket semantics and the migration checklist.
2. **[04-completion-report.md](04-completion-report.md)** — What was done,
   verification results, and follow-ups.
3. **[05-what-this-enables.md](05-what-this-enables.md)** — Forward-looking:
   the product capabilities this release unlocks (offline receive, restore
   from seed alone, scheduled expiry protection, recoverability indicator)
   and the liveness/trust assumptions they carry.

## Verification note (important)

Do **not** trust `~/workspace/bark-ffi-bindings` for the real signatures — read
the generated `Bark.swift` from the resolved package in
`DerivedData/.../SourcePackages/checkouts/bark-ffi-bindings/swift/Sources/Bark/`.
The API diff in these docs comes from a symbol-level comparison of the
generated `Bark.swift` v0.13.0 vs v0.14.0 (resolved revision `316e38b`).
