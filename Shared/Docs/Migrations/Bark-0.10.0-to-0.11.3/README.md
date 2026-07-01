# Bark FFI Bindings Migration: v0.10.0 → v0.11.3

**Date:** 2026-07-01
**Status:** 📝 Planning
**Bark Version:** v0.2.5 → v0.3.0
**FFI Bindings Version:** v0.10.0 → v0.11.3

## Overview

The v0.11.x bindings restructure wallet creation/opening, drop `Config.network`
in favour of an explicit `network:` argument, collapse the typed `BarkError`
enum into a single-case `Error` type, and remove one maintenance helper. The
diff between the two generated binding files is ~2,300 lines but almost all of
it is noise from UniFFI checksum functions shifting; there are **six real API
changes**, three of which are breaking and hit our FFI wrapper layer directly.

The UniFFI contract version is unchanged (source-level, not ABI, update).

## The six real changes

1. **Wallet creation/opening restructured** — five static factories collapse to
   a free function `initWallet(...)` + `Wallet.open(network:mnemonicOrSeed:config:args:)`
   with a new `WalletOpenArgs` struct. **Breaking, highest impact.**
2. **`Config.network` removed** — `network: Network` is now a separate argument;
   `Config` also gains `userAgent: String?`. **Breaking.**
3. **`OnchainWallet.default(...)` gains a required `network: Network`.** **Breaking.**
4. **`BarkError` → `Error`** — 14 typed cases collapse to a single
   `.Inner(message: String)`; the name now shadows `Swift.Error`. **Breaking, wide sweep.**
5. **`WalletProtocol` method changes:**
   - `maybeScheduleMaintenanceRefresh()` — **removed.**
   - `sendArkoorPayment(arkAddress:amountSats:)` now returns `Void` (was `String`). **Breaking.**
   - New: `payLnurl(...)`, `syncForceExitedVtxos()` (additive, optional to expose).
   - `wait:` params on lightning send/claim now default to `false` (additive).
6. **`CustomOnchainWalletCallbacks` gains a required `sync() throws`.** **Breaking** for our `BDKOnchainWallet`.

The database filename is unchanged (`bark.sqlite` throughout) — no data
migration is required.

Everything else — every other struct, enum, and `WalletProtocol` method — is
byte-for-byte unchanged.

## Impact summary

- **User experience:** No visible changes expected. Wallet create/import/open,
  ark-to-ark send, and maintenance are all internal plumbing.
- **Code changes:** ~20 files. Two categories: (a) a handful of targeted
  structural edits to the wallet-lifecycle and send paths, and (b) a large but
  purely mechanical `catch BarkError` → `catch Bark.Error` sweep across the FFI
  extension files.
- **Build result:** ⬜ Not yet attempted.

## Documents

1. **[01-api-changes.md](01-api-changes.md)** — Full API diff, old → new, with signatures.
2. **[02-migration-plan.md](02-migration-plan.md)** — Step-by-step plan with concrete file/line targets.

## Verification note (important)

Do **not** trust `~/workspace/bark-ffi-bindings` for the real signatures — read
the generated `Bark.swift` from the resolved package in
`DerivedData/.../SourcePackages/checkouts/bark-ffi-bindings`. In particular,
confirm the exact field names/types of `WalletOpenArgs` (especially how the
onchain wallet is now passed) and the `initWallet` argument list before editing.
