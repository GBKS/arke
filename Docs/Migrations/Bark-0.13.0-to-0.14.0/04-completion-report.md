# Completion Report: Bark FFI v0.13.0 → v0.14.0

**Date:** 2026-08-04
**Result:** ✅ Build green (iOS). Tests not run — no test-covered logic changed
(the touched switches and init sites have no tests). Runtime smoke on device
pending, most importantly a seed import to observe the new recovery scan.

## What was done

Applied directly from the checklist in [01-api-changes.md](01-api-changes.md) §5
(no separate plan doc — the migration was small and additive):

- **Compile fixes** — appended `registered: true` to the four mock/preview
  `Vtxo(...)` sites (`MockBarkWallet` ×3, `BarkWalletFFI+VTXO` preview path)
  and `claimDestination: nil` to the three mock/preview `LightningReceive(...)`
  sites (`BarkWalletFFI+Lightning` ×2, `MockBarkWallet` ×1).
- **`"delivering"` state** — added to the two `receive.state` switches in
  `BarkWalletFFI+Lightning` (invoice status text and the JSON status mapping),
  grouped with `"preimage-revealed"`/`"settled"` → claimed, since it sits after
  preimage reveal. `LightningClaimService` unchanged: it only matches
  `"htlcs-ready"`, and a delivering receive is correctly not claimable.
- **Recovery scan decisions** (`BarkWalletFFI+WalletCreation`):
  - `createWallet` passes `skipRecovery: true` — the seed is freshly generated
    (nothing to recover) and the scan would block onboarding on a network
    round-trip.
  - `importWallet`'s seed-only branch keeps the scan and calls a new private
    `logRecoveryReport(for:)` after open: logs bucket counts + `isComplete`,
    warns with the concrete VTXO ids when `failed` (retryable via
    `recoverVtxos`) or `foreign` (possible gap-limit overflow) are non-empty,
    and warns when the report is `nil` (scan failed or skipped — nil does NOT
    prove no funds are missing).
  - `importWallet`'s restored-backup branch and the regular `WalletLifecycle`
    open don't create wallets, so no scan runs there; untouched.

## Verification

- `XcodeRefreshCodeIssuesInFile` clean on all four edited files.
- `BuildProject` (iOS): success.
- Repo-wide grep confirms no other `Vtxo(`/`LightningReceive(` construction
  sites and no other `state` string comparisons (ArkéUI has no `import Bark`).
- Desktop target not built (out of rotation per current workflow).

## Notes / follow-ups

- **On-device verification (2026-08-05):** upgrade-in-place PASSED — db
  migration 41→42 ran clean on both databases, sync posted 3 recovery VTXO ids
  to the server (`registered: true` confirmed), balances/history intact;
  refresh, send, and receive all worked. Fresh create
  (`skipRecovery: true` path) still to be smoke-tested before release.
- **Deferred post-release (decision 2026-08-05):** seed-only import recovery
  scan test. Rationale: the supported restore path stays iCloud-backup-based
  (which bypasses the scan entirely — backup restore means no creating open);
  a failed scan doesn't block import and is log-only; and seed-only import
  recovered nothing off-chain in v0.13 anyway, so untested-scan risk is
  strictly better than the status quo. Do NOT advertise seed-only recovery
  until this is tested — test it together with building the recovery UI.
  Note for that test: the iCloud backup must be out of the way or it
  short-circuits the scan (`Wallet database detected` = backup path,
  `No wallet database found` + `Recovery scan complete=` = scan path).
- **Recovery UI:** an `isComplete == false` scan is currently log-only. A
  restore flow could surface the `failed`/`foreign` buckets and offer a retry
  via `recoverVtxos(vtxoIds:)`. Related: the import flow has a fixed
  post-create wait; if the scan meaningfully slows `Wallet.open`, that's where
  it will show.
- **`refreshVtxosScheduled`:** scheduling further out never costs more than
  refreshing now, so wherever we use `refreshVtxosDelegated` we could pair
  `getNextRequiredRefreshBlockheight()` with a scheduled refresh and save fees.
- **`bolt11InvoiceForAddress`:** delegated offline receive; no current product
  need, but note the strand-risk semantics in 01-api-changes §1 before using.
- **`Vtxo.registered`:** could be surfaced in the debug Data views to spot
  VTXOs whose recovery state hasn't been asserted with the server; not wired.
