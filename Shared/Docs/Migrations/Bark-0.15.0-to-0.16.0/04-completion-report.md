# Completion Report: Bark FFI Bindings v0.15.0 → v0.16.0

**Date:** 2026-08-07
**Result:** ✅ iOS build green; scoped exit suites + new mapping/snapshot
suites green; full mobile suite: see verification below.

## What was done

Executed per [02-migration-plan.md](02-migration-plan.md) §5 order. The
architecture landed as planned — map at the FFI boundary, keep everything
downstream on the existing domain models — with one structural deviation
and a handful of deliberate behavior changes, listed below.

### Fee schedule (§1)

- `ArkeUI.FeeSchedule.init(from: Bark.FeeSchedule)` mapper added at the
  bottom of `BarkWalletFFI+Configuration.swift` (its only use site);
  `getArkInfo()` maps directly instead of JSON-decoding, and the
  parse-failure branch is gone (the mapping is total).
- Ambiguous bare `FeeSchedule` references qualified as `ArkeUI.FeeSchedule`
  in `BarkWalletFFI+Configuration`, `MockBarkWallet`, `VTXORefreshService`.
- `ArkéUI.FeeSchedule.from(jsonString:)` deleted (unused after the typed
  mapping). Codable + snake_case CodingKeys stay (wallet export encodes
  `ArkInfoModel`).

### VTXO state (§2)

- `mapFFIStateToVTXOState` and `VTXOModel.init(from:)` switch exhaustively
  over `VtxoState` (no `default:`). Mock/preview `Vtxo` constructions use
  enum cases. The two `== "locked"` filters use `if case .locked`.

### Exit state (§3)

- The forward/reverse mappers live in their own file,
  `Shared/Data/ExitStatus/ParsedExitState+Bark.swift`. Note for future
  file additions: the `Shared` folder is **opt-in per file** for the
  ArkeMobile target (a `membershipExceptions` list in project.pbxproj
  enumerates every included file), so a file created outside Xcode
  silently compiles nowhere for mobile — with misleading downstream
  errors. Creating it via Xcode (or the `XcodeWrite` MCP tool) registers
  the membership correctly; that's how this file was added after an
  initial detour through the bottom of `ExitTransactionStatus+Parsing.swift`.
- **Reverse mapper (not in the original plan's §3.1):** `Bark.ExitState
  (from: ParsedExitState)`. Discovery during implementation:
  `WalletManager+Operations.getExitStatus` returns the persisted snapshot
  through the *same channel* as live statuses. Rather than changing
  `ExitStore`/facade signatures and every consumer, snapshots reconstruct a
  `Bark.ExitTransactionStatus`. Lossless for v2 snapshots and standard v1
  states; app-only legacy cases map to nearest Bark equivalents
  (`needsBroadcasting → awaitingConfirmation`, `needsSignedPackage/unparsed
  → verifyInputs`, unparsed origins → `mempool` so third-party fees are
  never attributed to the user, unparsed states → `start(0)`).
- `ExitStatusSnapshot` v2: Codable `ParsedExitState` + `version` field;
  v1 string snapshots decode forever via `ExitStatusParser` and upgrade
  lazily on next write. `ParsedExitState` (+ nested types, `ArkeBlockRef`)
  gained `Codable`.
- `ExitStatusParser` demoted to legacy v1 decoder (header updated); its
  txid-extraction entry points now go through the typed mapper.
- `parsedState` is **non-optional** now (the mapper is total); the
  `?? .unparsed` / `guard let` dances in `ExitProgress`,
  `ExitProgressionService+LiveActivity` were removed.
- Display helpers (`ExitVtxo`/`ExitTransactionStatus` extensions) rewritten
  as real switches over `Bark.ExitState` via a shared
  `Bark.ExitState.displayName`.
- `ExitStatusDetailView_iOS`: history rows take `Bark.ExitState`; raw
  debug text renders via `String(describing:)`.

### Concurrency wrinkle (not in the plan)

The target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. The
snapshot struct is `nonisolated`, so the whole parsing layer had to be too:
`ParsedExitState` + nested types, `ArkeBlockRef`, `ExitStatusParser`, the
parsing/mapping extensions. All pure value code — `nonisolated` is correct,
not a workaround.

## Behavior changes (not pure type substitution)

1. **Exited VTXOs no longer mislabeled as pending** —
   `VTXOModel.init(from:)` previously defaulted unknown state strings
   (including `"exited"`) to `.pending`; the exhaustive switch maps
   `.exited → .exited`, matching `mapFFIStateToVTXOState`.
2. **Cancelled exits display "Cancelled"** — `stateDisplayName` for
   `.vtxoAlreadySpent`/`.canceled` now uses the localized
   `transaction_cancelled` ("Cancelled") instead of leaking raw case names
   ("VtxoAlreadySpent" / "Canceled"). No new localization keys added.
3. **Dead code deleted** — `ExitVtxo.stateIcon`, `ExitVtxo.stateColor`,
   `ExitTransactionStatus.formattedHistory`, and the
   `extractStateCaseName` reflection helper had zero consumers.
4. **New `ExitTransactionStatus.isClaimInProgress`** — replaces the
   `hasPrefix("ClaimInProgress")` check in `WalletManager+Exits`
   finalization.
5. **`getArkInfo` fee-schedule failure path removed** — the JSON parse
   could return nil (logged a warning); the typed mapping cannot fail.
6. **Debug log/raw-display format drift** — interpolated states print as
   Swift enum descriptions (`claimed(tipHeight:…)`) instead of Rust-Debug
   (`Claimed(ExitClaimedState {…})`). Affects logs and the X-Ray raw rows
   only.

## Tests

- String fixtures in `ExitProgressTests`, `ExitStatusParserTests`,
  `ExitFeeAttributionTests` now build statuses via
  `parse → reverse-map` — deliberately exercising the persisted-v1
  pipeline on every run. `ExitBlockedInfoTests` fixtures construct enum
  states directly.
- New `ExitStateMappingTests` (forward/reverse mapping, legacy fallbacks)
  and `ExitSnapshotFormatTests` (v2 round-trip, v1 fallback decode incl.
  pre-0.11 `BroadcastWithCpfp`, garbage-JSON safety).
- Pre-existing "Exit Status Snapshot" suite in `ExitFeeAttributionTests`
  still covers the rich real-exit fixture round-trip.

## Verification

- ✅ iOS build green (2026-08-07).
- ✅ Scoped suites: ExitStatusParser, ExitProgress, ExitStore,
  ExitBlockedInfo, ExitFeeAttribution (+Parser) — all passing.
- ✅ New suites: ExitStateMapping, ExitSnapshotFormat — all passing.
- ✅ Full mobile suite: 154/154 passed, xcodebuild exit 0 (2026-08-07).
- ⏳ **On-device check pending:** open a wallet whose PersistentExitCache
  holds real v1 snapshots (claimed + cancelled exits) and confirm the
  history renders — pairs with the still-pending exit-completion on-device
  verify.

## Follow-ups

- [x] Delete `ArkéUI.FeeSchedule.from(jsonString:)` (done 2026-08-07).
- [x] Move the mappers to their own file (`ParsedExitState+Bark.swift`,
      added via XcodeWrite with correct target membership, 2026-08-07).
- [ ] On-device v1-snapshot verification (above).
- [ ] Deferred: adopt the four new `OnchainWalletProtocol` methods
      (plan §6) — `getUTXOs()` is still a stub returning `[]`.
