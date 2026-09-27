# Bark FFI Bindings Migration: v0.15.0 → v0.16.0

**Date:** 2026-08-07
**Status:** ✅ Completed 2026-08-07 — iOS build green; full mobile suite 154/154; on-device v1-snapshot verify pending (see [04-completion-report.md](./04-completion-report.md))
**Bark Version:** v0.6.0 → v0.6.0 (unchanged)
**FFI Bindings Version:** v0.15.0 → v0.16.0 (release commit `5c72f6e`, resolved checkout `ad9c21f`, branch `master`)

## Overview

Bark v0.16.0's theme is **typed state**: four fields that used to be
Rust-Debug-formatted `String`s are now real Swift enums, and the server fee
schedule went from a JSON blob to a typed struct tree. `WalletProtocol`
itself is untouched — all 94 methods have identical signatures (verified by
symbol-level diff of the generated `Bark.swift`, 7,436 → 9,081 lines).

What breaks:

1. `ArkInfo.feeScheduleJson: String` → `ArkInfo.feeSchedule: FeeSchedule`
   (typed tree, see [01-api-changes.md](01-api-changes.md) §1).
2. `Vtxo.state: String` → `VtxoState` enum (`Vtxo.kind` stays `String`).
3. `ExitVtxo.state`, `ExitProgressStatus.state`, `ExitTransactionStatus.state`:
   `String` → `ExitState` enum; `ExitTransactionStatus.history`:
   `[String]?` → `[ExitState]?`.

Purely additive: `OnchainWalletProtocol` gains `feeRates()`, `tipHeight()`,
`transactions()`, `utxos()` — **not adopted in this pass** (see
[02-migration-plan.md](02-migration-plan.md) §6).

## The four things this repo must get right

1. **Three type-name collisions.** Bark 0.16 exports `FeeSchedule`, which
   collides with ArkéUI's `FeeSchedule`
   (`ArkeUI/Sources/ArkéUI/Models/FeeSchedule.swift`). Files importing both
   modules (`BarkWalletFFI+Configuration.swift`, `MockBarkWallet.swift`,
   `VTXORefreshService.swift`) get ambiguity errors on the bare name and
   must qualify. Bark also now exports `ExitTxStatus` and `ExitState`,
   which the app already defines (`ParsedExitState.swift:124` and the
   live-activity enum in `ExitProgressActivityAttributes.swift:53`) —
   same-module shadowing means no compile error, but mapper code must
   write `Bark.ExitTxStatus` / `Bark.ExitState` explicitly. Same pattern
   as the known `Bark.Error` collision. ArkeWidgets does not import Bark,
   so the widget side is unaffected.

2. **Persisted exit snapshots are string-format and must stay readable.**
   `PersistentExitCache.exitStatusJson` stores `ExitStatusSnapshot`
   (`state: String`, `history: [String]?`) — the Rust-Debug strings the old
   bindings emitted, including pre-0.11 variants (`NeedsBroadcasting`,
   `BroadcastWithCpfp`). Per the file's own doc comment, this snapshot is
   the **only durable record of a claimed exit** (bark purges completed
   exits). `ExitStatusParser` therefore cannot be deleted: it becomes the
   legacy decoder for on-disk v1 snapshots, while new snapshots persist a
   Codable form of `ParsedExitState` (v2).

3. **The app already has the typed domain model.** `ParsedExitState`
   mirrors `ExitState` case-for-case (plus `.unparsed`). The migration's
   center of gravity is one total mapper `Bark.ExitState → ParsedExitState`
   at the FFI boundary; everything downstream (`ExitProgress`,
   `ExitBlockedInfo`, `ExitProgressionService/Logic`, exit UI) already
   consumes `ParsedExitState` and needs no change. This is much smaller
   than "convert every string comparison site".

4. **`ArkéUI.FeeSchedule` is not a dead mirror — keep it.** It is the
   deliberately Bark-free presentation model (fee math + display strings,
   used by `FeeScheduleView_iOS`, `VTXORefreshService`,
   `BalanceRefreshStatusViewModel`, previews). The mapper changes from
   JSON-decode to direct field mapping (`Bark.FeeSchedule → ArkéUI.FeeSchedule`,
   `UInt64 → Int`, `minFeeSats → minFeeSat`).

## Corrections to the initial (pre-repo) review

The binding-level diff in the initial review was verified against the git
diff between release commits and is **accurate in full** — every claimed
change and non-change confirmed. Its repo-impact guesses needed fixes:

- ❌ "delete now-dead Codable mirrors of the fee schedule" — ArkéUI's
  `FeeSchedule` stays (see above). Only `FeeSchedule.from(jsonString:)`
  becomes a candidate for removal, after checking nothing persists the
  schedule as JSON.
- ❌ It missed both type-name collisions.
- ❌ It missed the persisted-snapshot compatibility problem entirely
  ("replace string comparisons with switches" would silently orphan every
  claimed exit's history on disk).
- ⚠️ "add `ExitState.displayName` helpers" — mostly unnecessary; display
  names already exist on top of `ParsedExitState` / `ExitVtxo` extensions.
- ⚠️ `ExitVtxo+Extensions.swift`'s `extractStateCaseName` (parses
  `String(describing: state)`) happens to keep working — Swift enum case
  names are the lowercased Rust names and the code lowercases before
  matching — but it should be replaced with a real `switch`, not left to
  luck.

## Impact summary

- **Compile errors:** ~15 files — FFI mappers (`BarkWalletFFI+Configuration`,
  `BarkWalletFFI+VTXO`), `VTXOModel+Bark`, `VTXORefreshService`,
  `ExitStatusParser` entry points, `ExitTransactionStatus+Parsing`,
  `ExitVtxo+Extensions` (incl. `formattedHistory`), `ExitProgress`,
  `ExitProgressionService+LiveActivity`, `ExitStatusSnapshot`,
  `WalletManager+Exits`, `MockBarkWallet`, two `== "locked"` filters, three
  test files.
- **Data migration:** `ExitStatusSnapshot` v1 (strings) → v2 (Codable
  `ParsedExitState`), with v1 fallback decode kept indefinitely.
- **User-visible behavior:** none intended.
- **Build result:** not started.

## Documents

1. **[01-api-changes.md](01-api-changes.md)** — Full verified API diff with
   verbatim declarations, semantics from doc comments, collisions, and the
   migration checklist.
2. **[02-migration-plan.md](02-migration-plan.md)** — File-by-file plan,
   the snapshot-persistence design, test strategy, and the deferred
   onchain-methods adoption notes.

## Verification note (important)

Do **not** trust `~/workspace/bark-ffi-bindings` for the real signatures —
read the generated `Bark.swift` from the resolved package in
`DerivedData/.../SourcePackages/checkouts/bark-ffi-bindings/swift/Sources/Bark/`.
The API diff in these docs comes from `git diff 0b63390 5c72f6e`
(v0.15.0 → v0.16.0 release commits) on that checkout's generated
`Bark.swift`.
