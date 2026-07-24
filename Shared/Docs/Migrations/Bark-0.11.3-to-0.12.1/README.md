# Bark FFI Bindings Migration: v0.11.3 → v0.12.1

**Date:** 2026-07-24
**Status:** ✅ Completed 2026-07-24 — build green, mobile tests green; on-device smoke pending (see [04-completion-report.md](./04-completion-report.md))
**Bark Version:** v0.3.0 → v0.4.0
**FFI Bindings Version:** v0.11.3 → v0.12.1 (rust FFI layer: bark-ffi v0.16.0)

## Overview

Bark v0.4.0 ([changelog, 20 July 2026](https://second.tech/docs/changelog#20-july-2026))
bundles two themes:

1. **Onchain wallet trait consolidation** — a single `OnchainWalletTrait`
   replaces the previous trait set. The onchain wallet is now bound **once** at
   `Wallet.open()` via `WalletOpenArgs.onchain`; board/exit/daemon/sync calls
   drop their per-call `onchainWallet:` argument, the "with onchain" maintenance
   variants disappear, and the custom-callbacks surface switches from a pull
   model (Bark queries your txs by txid/outpoint) to a push model
   (`registerTx` + `isMine`).
2. **Crash-safety across payment operations** — checkpoint-based recovery. This
   is why `LightningReceive` is reshaped around a single `state` string
   (`"awaiting-payment"` → `"htlcs-ready"` → `"preimage-revealed"` → `"settled"`)
   instead of two independent booleans, and why `bolt11Invoice` gains an
   optional `token:` captured at invoice-generation time.

There are **five real API changes** that hit our code, plus one runtime-only
behavioural addition (`ExitState::Canceled`) that never shows up in the Swift
binding diff. Everything else — `Error`, `WalletOpenArgs`, and all other
structs — is unchanged.

The state is good going in: both `Wallet.open` paths already pass
`WalletOpenArgs(onchain:)`, so item 1 is pure argument-label deletion for us.

## The changes that hit this repo

1. **Five methods drop `onchainWallet:`** — `boardAll`, `boardAmount`,
   `progressExits`, `runDaemon`, `syncExits`. Mechanical; `runDaemon` ripples
   through protocol → mock → `WalletManager`. **Breaking.**
2. **`maintenanceWithOnchain` / `maintenanceWithOnchainDelegated` removed** —
   clean delete; the only "caller" is commented-out debug UI. **Breaking.**
3. **Lightning receive reshape** — `lightningReceiveStatus` →
   `lightningReceiveState` (non-optional, throws on unknown hash);
   `tryClaimLightningReceive` now returns `LightningReceive`;
   `LightningReceive` loses `hasHtlcVtxos`/`preimageRevealed`, gains
   `state: String` + `settledAt: Int64?`, `paymentPreimage` becomes optional.
   **Breaking**, contained to protocol + FFI wrapper + mock +
   `LightningClaimService`.
4. **`bolt11Invoice` gains `token: String? = nil`** — additive, no change
   needed (we have no token source).
5. **`CustomOnchainWalletCallbacks` reshaped** — `getWalletTx` /
   `getWalletTxConfirmedBlock` / `getSpendingTx` removed; `isMine` +
   `registerTx` added. **Breaking**, but our only conformer
   (`BDKOnchainWallet`) is dead code — instantiated nowhere; production uses
   `OnchainWallet.default()`. Must still be updated (or deleted) to compile.
6. **Runtime-only: `ExitState::Canceled` added upstream** — currently
   unreachable from this app (no cancel-exit API in the bindings), degrades to
   `.unparsed` → phase `.preparing` if it ever appears. Optional hardening in
   the plan.

No database filename change, no data migration.

## Impact summary

- **User experience:** No visible changes expected. All internal plumbing.
- **Code changes:** ~10 files. Mostly mechanical argument/signature edits; the
  one judgement call is `BDKOnchainWallet` (update vs. delete).
- **Build result:** ✅ iOS build green; full mobile test suite green (2026-07-24).

## Documents

1. **[01-api-changes.md](01-api-changes.md)** — Full API diff old → new, plus
   upstream (rust-side) findings that don't appear in the Swift binding diff.
2. **[02-migration-plan.md](02-migration-plan.md)** — Step-by-step plan with
   concrete file/line targets and the open decisions.
3. **[04-completion-report.md](04-completion-report.md)** — What was done,
   verification results, and follow-ups.

## Verification note (important)

Do **not** trust `~/workspace/bark-ffi-bindings` for the real signatures — read
the generated `Bark.swift` from the resolved package in
`DerivedData/.../SourcePackages/checkouts/bark-ffi-bindings/swift/Sources/Bark/`.
All signatures in these docs were verified against the resolved v0.12.1
checkout (revision `8f9c899`) on 2026-07-24. Upstream enum/error findings were
verified against GitLab tags `bark-0.3.0` / `bark-0.4.0` (ark-bitcoin/bark) and
`v0.16.0+bark-0.4.0.uniffi-0.31.1` (ark-bitcoin/bark-ffi).
