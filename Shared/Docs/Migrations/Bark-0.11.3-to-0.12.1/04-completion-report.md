# Completion Report: Bark FFI v0.11.3 → v0.12.1

**Date:** 2026-07-24
**Result:** ✅ Build green (iOS), ✅ full mobile test suite green (`** TEST SUCCEEDED **`),
including 3 new `Canceled` tests. Runtime smoke tests on device pending.

## What was done

All phases of [02-migration-plan.md](02-migration-plan.md) executed as planned:

- **Phase 1** — Dropped `onchainWallet:` from the five FFI call sites
  (`boardAmount`, `boardAll`, `progressExits`, `syncExits`, `runDaemon`).
  Preflight guards kept as `guard onchainWallet != nil` for their diagnostic
  error messages. `runDaemon()` signature rippled through
  `BarkWalletProtocol`, `MockBarkWallet`, and `WalletManager`.
- **Phase 2** — Deleted `maintenanceWithOnchain` /
  `maintenanceWithOnchainDelegated` from the FFI wrapper, protocol, mock, and
  the `WalletManager+Operations` passthrough. The commented-out debug button in
  `DataView_iOS` now references `maintenanceDelegated()`.
- **Phase 3** — `lightningReceiveStatus` → `lightningReceiveState`
  (non-optional, throws on unknown hash; preview returns an
  `"awaiting-payment"` stub). `tryClaimLightningReceive` returns
  `LightningReceive` (`@discardableResult`). Boolean checks replaced with
  `state` string comparisons in `LightningClaimService` (claimable ==
  `"htlcs-ready"`) and the two console formatters in
  `BarkWalletFFI+Lightning` (which now also expose `state`/`settled_at`).
- **Phase 4b** — Deleted `BDKOnchainWallet.swift` and `BDKCpfpHelper.swift`
  via XcodeRM (project references cleaned). Context: a CPFP experiment that
  didn't pan out; `BDKTransactionReader` covers history reading.
- **Phase 5** — No change; `token:` left defaulted (no token source; see
  01-api-changes §4 for when that changes).
- **Phase 6** — `Canceled` hardening: new `ParsedExitState.canceled(CanceledState)`
  case, parsed from `"Canceled(ExitCanceledState { tip_height: N })"`. Mapped
  to phase `.cancelled` and excluded from aggregates (like
  `vtxoAlreadySpent`) in `ExitProgress` and
  `ExitProgressionService+LiveActivity`; tip-height plumbed in
  `ExitTransactionStatus+Parsing`; labeled in `ExitStatusDetailView_iOS`
  (reuses existing `transaction_cancelled` key — no new localization entries).

## Verification

- `BuildProject` (iOS): success, no warnings surfaced in the log summary.
- `xcodebuild test`, scheme "Arke mobile", iPhone 17 Pro simulator:
  **TEST SUCCEEDED**. New tests: `testParseCanceledState`, `testCanceled`,
  `testAggregateCanceledExcluded`.
- Repo-wide grep confirms zero remaining references to removed/renamed
  symbols.

## Notes / follow-ups

- `Localizable.xcstrings`: the build marked `button_yes` / `button_no` as
  `extractionState: stale` — their only code usages were the deleted
  `hasHtlcVtxos`/`preimageRevealed` status lines. Values retained; left as-is
  (generic keys, may be reused).
- **Pending:** on-device runtime smoke on signet — board, lightning receive +
  auto-claim (verify `"htlcs-ready"` filter fires), exit progression.
- Desktop target not built (out of rotation per current workflow).
- Empty-wallet lightning receive has no anti-DoS token path — but this only
  matters on servers that report `ArkInfo.lnReceiveAntiDosRequired = true`
  (the app already surfaces this flag in the debug Ark Info view). Tokens are
  operator-issued integration tokens; the wallet-facing protocol has no RPC to
  request one. Details in 01-api-changes §4; revisit if Lightning-first
  onboarding becomes a goal.
