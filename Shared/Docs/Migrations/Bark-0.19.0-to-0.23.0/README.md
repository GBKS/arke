# Bark FFI Bindings Migration: v0.19.0 → v0.23.0

**Date:** 2026-09-08
**Status:** ✅ Minimal pass completed 2026-09-08 — build green; Phase 1 +
`stopDaemonWait()` adoption shipped (see
[04-completion-report.md](./04-completion-report.md)). Remaining Phase 2 items
(`initialScanOnchain`, `estimateEmergencyExitFee`, `recoveryStatus`) deferred to
`Open_Follow_Ups.md`.
**Bark Version:** v0.6.1 → v0.7.0
**FFI Bindings Version:** v0.19.0 → v0.23.0 (resolved checkout
`4c86dccb81618b4fa3ef5f4375110e9b05328a9a`, branch `master`; UniFFI contract
version **30, unchanged** — no scaffolding-wide changes)

## Overview

Bark v0.23.0's theme is **additive**: new lifecycle/recovery/exit-fee methods on
`Wallet` and `OnchainWallet`, plus three record-layout changes and one new callback
method. **Nothing was removed or renamed** — every symbol `BarkWalletProtocol`
declares still exists with the same signature (verified against the generated
`Bark.swift` in the resolved checkout).

The headline for *this* repo, which the pre-repo review got wrong: **the three
record-layout changes break zero call sites here**, because the app never
constructs the affected FFI structs. It reads them at the FFI boundary and maps to
its own presentation models. So the migration is a clean recompile plus optional
new-API adoption — not a compile-error cleanup.

What changed at the binding level:

1. `RoundState` gained `state: RoundFlowKind` and `scheduledHeight: UInt32?`;
   `ongoing: Bool` kept as a compatibility alias
   ([01-api-changes.md](01-api-changes.md) §1.1).
2. `Config.vtxoRefreshExpiryThreshold`: `UInt32?` → `UInt16?` (§1.2).
3. `ArkInfo` gained `vtxoLifetime: UInt32` between `vtxoExitDelta` and
   `vtxoExpiryDelta`; `vtxoExpiryDelta` kept but deprecated upstream (§1.3).
4. `CustomOnchainWalletCallbacks` gained a required `func evictTx(txid:) throws`
   (§1.4).

Purely additive new API worth adopting (§2): `Wallet.stopDaemonWait()`,
`OnchainWallet.initialScan(birthdayHeight:)`,
`Wallet.estimateEmergencyExitFee(...)`, `Wallet.recoveryStatus()`. Lower priority:
`OnchainWallet.evictTx`, externally-funded board (`boardFundingAddress` /
`boardPsbt`).

## The three things this repo must get right

1. **Phase 1 is nearly empty — do not go hunting for compile breaks.** Verified by
   repo-wide grep:
   - **No `Bark.RoundState(...)` construction** exists anywhere (app, tests,
     previews). The two new fields break nothing. `MockBarkWallet` returns
     `ArkInfoModel`/app types, not FFI structs.
   - **No `Bark.ArkInfo(...)` construction** exists. Every `getArkInfo()` hit
     returns the app's `ArkInfoModel`. The FFI `ArkInfo` is only *read*, at two
     sites in `BarkWalletFFI+Configuration.swift` (lines 173, 183).
   - **One `Bark.Config(...)` site** — `makeConfig` at
     `BarkWalletFFI+Configuration.swift:228`, passing
     `vtxoRefreshExpiryThreshold: nil` (a literal). The `UInt16?` change is
     transparent.
   - **No `CustomOnchainWalletCallbacks` conformer** — the app uses the built-in
     BDK onchain wallet (`OnchainWallet.default(...)`). The `evictTx` callback
     break is benign; skip §1.4 entirely.

   The single mechanical must-do is deprecation hygiene: migrate the two *reads* of
   `ffiArkInfo.vtxoExpiryDelta` to `ffiArkInfo.vtxoLifetime` (same value).

2. **`vtxoExpiryDelta` is two different things — only the FFI read migrates.**
   `ArkInfoModel.vtxoExpiryDelta: Int` (the app's presentation model) stays, and so
   does its Codable key `vtxo_expiry_delta` — `ArkInfoModel` is `Codable` and its
   JSON is part of the metadata export format. Renaming the *model* field would
   change the export schema. Change only the *source* of the value
   (`ffiArkInfo.vtxoExpiryDelta` → `ffiArkInfo.vtxoLifetime`), keep the model field
   name. Same caution as the 0.16 migration's `CodingKeys` note.

3. **The new API is the actual value of this bump.** Two of the additions fix real
   correctness gaps the protocol has today:
   - `stopDaemonWait()` — `deleteWallet()` currently calls `stopDaemon()` (via
     `shutdownWallet()`), which returns before the daemon's tasks drain, racing
     datadir deletion and file locks. Swap the delete path to `stopDaemonWait()`.
   - `initialScan(birthdayHeight:)` — the import-from-mnemonic path
     (`openImportedWallet`) relies on `recoveryReport()` to recover VTXOs but has no
     way to recover pre-existing *onchain* history from a previous incarnation of
     the seed. `sync()` alone never finds it.

   These belong on `BarkWalletProtocol`; the rest (`estimateEmergencyExitFee`,
   `recoveryStatus`) are strong improvements to surface but not blocking.

## Corrections to the pre-repo review

The binding-level diff in the review is **accurate in full** — all four
source-breaking changes and all new-API signatures were verified verbatim against
the resolved checkout's `Bark.swift` (see [01-api-changes.md](01-api-changes.md)).
Its repo-impact guesses were wrong in the ways that matter:

- ❌ "Any call to the memberwise `RoundState(...)` initializer breaks. Most likely
  sites: the mock wallet, previews, tests." — **There are none.** Zero breaks.
- ❌ "Memberwise `ArkInfo(...)` init calls break (mock/test fixtures again)." —
  **There are none.** The mock builds `ArkInfoModel`, not `Bark.ArkInfo`.
- ❌ "`CustomOnchainWalletCallbacks` gained a required method … only breaking if the
  app conforms." — The app does **not** conform. Benign; skip.
- ⚠️ `Config.vtxoRefreshExpiryThreshold` change is real but the one construction
  site passes a `nil` literal, so it compiles unchanged. **However** (found during
  implementation, missed by both the review and this doc's construction-only grep):
  the *read* at `getConfig()`'s `ArkConfigModel` mapping
  (`BarkWalletFFI+Configuration.swift:70`) passed the now-`UInt16?` field into the
  app model's `UInt32?` — one real compile error. Fixed by widening losslessly at
  the boundary (`.map { UInt32($0) }`), keeping the app model unchanged.
- ❌ (Ours, not the review's.) An earlier repo scan reported `stopDaemon()` on
  `BarkWalletProtocol` at line 227 — **it is not**; the protocol has no daemon
  methods. `stopDaemon`/`shutdownWallet` are internal to `BarkWalletFFI`, so
  adopting `stopDaemonWait()` needed no protocol or mock changes at all.
- ✅ The `estimateEmergencyExitFee` "errors on callback-backed onchain wallets"
  caveat is moot here for the same reason — the app is BDK-backed, so the call
  always works.

Net: the review's Phase 1 ("fix compile breaks") collapses to a single one-line
deprecation-hygiene edit. The weight of the work is Phase 2 (adopt the new API).

## Impact summary

- **Compile errors:** expected **none** after swapping the binary + `Bark.swift` as
  a matched pair and clean-building. (If any appear, they are unlisted construction
  sites — report, don't guess.)
- **Mechanical must-do:** migrate 2 reads of `vtxoExpiryDelta` → `vtxoLifetime` in
  `BarkWalletFFI+Configuration.swift` (lines 173, 183).
- **New-API adoption (recommended):** `stopDaemonWait()` in the delete path,
  `initialScan()` in the import path, `estimateEmergencyExitFee()` as an exit
  pre-flight, `recoveryStatus()` replacing the ambiguous `recoveryReport()`.
- **User-visible behavior:** none from the recompile; the adopted APIs add a
  "scanning" import state, a fee pre-flight before exit, and a distinguishable
  recovery-failed state.
- **Build result:** not started.

## Documents

1. **[01-api-changes.md](01-api-changes.md)** — verified API diff with verbatim
   declarations, the new-API surface ranked by relevance, verified non-changes, and
   the migration checklist.
2. **[02-migration-plan.md](02-migration-plan.md)** — Phase 0 matched-pair sanity,
   the one Phase 1 edit, the Phase 2 protocol + mock + real-wallet adoption plan,
   deferred items, and test strategy.
3. **04-completion-report.md** — to be written when the work lands.

## Verification note (important)

Signatures were read from the generated `Bark.swift` in the resolved package
checkout at
`DerivedData/Arke-…/SourcePackages/checkouts/bark-ffi-bindings/swift/Sources/Bark/Bark.swift`
(revision `4c86dcc`), **not** from `~/workspace/bark-ffi-bindings`. The *new* (0.23)
declarations were confirmed present exactly as documented; the claim that each is
new/changed *relative to 0.19* is taken from the pre-repo diff review (the 0.19
`Bark.swift` was not available to re-diff here). The repo-impact facts —
construction-site counts, `CustomOnchainWalletCallbacks` non-conformance, the
`deleteWallet()`→`stopDaemon()` path, the `vtxoExpiryDelta` read sites — were
verified directly by grep against the working tree.

The `.xcframework`/dylib and `Bark.swift` must be replaced **as a matched pair**:
several FFI checksums moved on unchanged Swift signatures
(`customonchainwalletcallbacks_{make_signed_p2a_cpfp,store_signed_p2a_cpfp,sync}`,
`wallet_recovery_report`, `wallet_validate_arkoor_address` — UniFFI hashes
docstrings into the metadata). A mismatch fails at runtime in
`uniffiEnsureInitialized()` with `apiChecksumMismatch`, not at compile time — so a
clean build + DerivedData wipe after swapping is part of Phase 0.
