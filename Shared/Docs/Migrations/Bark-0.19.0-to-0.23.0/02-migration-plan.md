# Migration Plan: Bark FFI Bindings v0.19.0 → v0.23.0

Principle: **the recompile is free; the value is in the new API.** Unlike the 0.16
bump, there are no boundary types to re-map — the app never constructs the changed
FFI structs (verified, see [README.md](README.md)). So this plan is short on
compile-fixing and long on deciding which additive methods to adopt now.

Keep `BarkWalletProtocol` and `MockBarkWallet` in lockstep: every protocol addition
needs a mock counterpart, and the mock must stay usable as an `ExitClaimWallet` for
`ExitClaimSequence`. Do not change `deleteWallet()`'s documented contract (it shuts
down the wallet and deletes the on-disk directory only; keychain and cloud data stay
owned by the cleanup service).

---

## Phase 0 — matched-pair sanity

Confirm the binary (`.xcframework`/dylib) and `Bark.swift` came from the same release
(resolved checkout `4c86dcc`). Wipe DerivedData, clean-build. Several FFI checksums
moved on unchanged Swift signatures (§1.5 in the API doc), so a stale binary fails at
runtime in `uniffiEnsureInitialized()` with `apiChecksumMismatch`, not at compile
time.

## Phase 1 — the one mechanical edit

**File:** `Shared/Data/BarkWalletFFI/BarkWalletFFI+Configuration.swift`.

- Line 183: `vtxoExpiryDelta: Int(ffiArkInfo.vtxoExpiryDelta)` →
  `Int(ffiArkInfo.vtxoLifetime)`. Same value; `vtxoExpiryDelta` is deprecated
  upstream and will be removed.
- Line 173: the debug log interpolating `ffiArkInfo.vtxoExpiryDelta` →
  `ffiArkInfo.vtxoLifetime`.

**Do not** rename `ArkInfoModel.vtxoExpiryDelta` or its Codable key
`vtxo_expiry_delta` — the app model keeps its name (metadata-export JSON schema
depends on it). We are only changing the *source* of the value.

Build. Expect green with no further edits. If any construction-site compile error
appears, it is an unlisted site — report it rather than guessing at intent.

## Phase 2 — adopt the new API

Each item touches three places: `BarkWalletProtocol.swift` (declaration),
`MockBarkWallet.swift` (stub/no-op), and the FFI implementation
(`BarkWalletFFI+*.swift`).

### 2.1 `stopDaemonWait()` — fix the delete-path race ✅ SHIPPED (2026-09-08)

> **Correction (implementation):** daemon control was never on
> `BarkWalletProtocol` — the "line 227" report was wrong; the protocol has no
> daemon methods. `stopDaemon`/`shutdownWallet` are internal to `BarkWalletFFI`, so
> this item needed **no protocol or mock changes**. What actually shipped:
>
> - Internal `stopDaemonWait()` wrapper in `BarkWalletFFI+WalletLifecycle.swift`,
>   mirroring `stopDaemon()`.
> - `shutdownWallet()` calls it — covering all six callers (create, import, delete,
>   backup-restore, both WalletManager teardowns), each of which mutates or releases
>   wallet files afterward.
> - The import `wipeAndRetry` path (`BarkWalletFFI+WalletCreation.swift:590`) had
>   the same race before `removeBarkDatabase()` — also swapped.
> - `stopDaemon()` kept for any caller that genuinely doesn't need the drain.
> - Pre-existing 500ms sleeps kept (redundant belt-and-braces).

### 2.2 `initialScanOnchain(birthdayHeight:)` — recover onchain history on import

- **Protocol** (`MARK: - Wallet Lifecycle`):
  ```swift
  /// Runs a gap-limited scan for onchain history from a previous incarnation of this
  /// seed. Call once after importWallet; sync() alone will not find it. Returns total sats.
  func initialScanOnchain(birthdayHeight: UInt32?) async throws -> UInt64
  ```
  (Named `initialScanOnchain` to disambiguate from any wallet-level scan; the FFI
  method is `OnchainWallet.initialScan`.)
- **FFI impl:** call `onchainWallet.initialScan(birthdayHeight:)`. Esplora ignores
  `birthdayHeight`; pass a real height only if a bitcoind backend is configured (it is
  not today — `makeConfig` sets `bitcoindAddress: nil`).
- **Import flow:** in `openImportedWallet` (`BarkWalletFFI+WalletCreation.swift:547`),
  after the wallet opens and before the first balance read, run the scan. It is slower
  than a normal sync — surface a distinct "scanning" state in the import UI rather
  than reusing the generic sync spinner.
- **Mock:** return a fixed sats value (or 0).

### 2.3 `estimateEmergencyExitFee(...)` — exit pre-flight

- **Protocol** (`MARK: - Fee Estimation`, next to the other `estimate*` methods):
  ```swift
  func estimateEmergencyExitFee(vtxoIds: [String],
                                feeRateSatPerVb: UInt64?,
                                destination: String?) async throws -> EmergencyExitFeeEstimate
  ```
  Decide whether to expose `Bark.EmergencyExitFeeEstimate` directly or map it to an
  app model — prefer a small app struct for consistency with the rest of the protocol
  (which returns `*Model` types), but a direct passthrough is acceptable for a
  first pass since the fields are already presentation-ready.
- **Usage:** pre-flight before `startExit()` / `startExitForVTXOs()`. Empty `vtxoIds`
  = whole-wallet exit. Show `exitBroadcastFeeSats` (paid now, from confirmed onchain
  funds) and `claimFeeSats` (deducted later from recovered value) separately — they
  come from different pockets — and **block or hard-warn when `fundable == false`**.
  It syncs the onchain wallet first; treat as a slow call. It throws on
  callback-backed onchain wallets (not our case), but still handle the error rather
  than surfacing it generically.
- **Mock:** return a plausible fixed estimate with `fundable: true`.

### 2.4 `recoveryStatus()` — disambiguate recovery outcome

- **Protocol** (`MARK: - Sync & Maintenance`, recovery area; synchronous,
  non-throwing to match `mailboxIdentifier()`/`notifications()` style):
  ```swift
  /// Distinguishes a recovery scan that never ran from one that failed.
  func recoveryStatus() -> RecoveryStatus
  ```
- **Adoption:** the import path currently reads `recoveryReport()` at
  `BarkWalletFFI+WalletCreation.swift:572` (with retries at 610, logging at 621).
  Switch the *decision* logic to `recoveryStatus()`: `.notRun` → nothing to do;
  `.failed(message:)` → distinct, retryable presentation (the old `nil` from
  `recoveryReport()` could not tell this apart from "nothing to recover");
  `.completed(report:)` → existing report handling (`report.isComplete == false` still
  means retry the report's `failed` ids via `recoverVtxos`).
- **Mock:** return `.notRun` (or a `.completed` with an empty report).

### Constraints recap

- Keep `stopDaemon()` on the protocol for the non-deleting shutdown path.
- Keep `recoveryReport()` — `recoveryStatus()` is additive, not a replacement at the
  binding level.
- Mock parity is a hard requirement; verify the mock still satisfies
  `ExitClaimWallet` after the additions.

## Phase 3 — optional, ask before implementing

- **`RoundFlowKind`-rich round UI.** `RoundState.state` now distinguishes
  `.delegatedPending` (with `scheduledHeight`) from `.pending`, `.ongoing`,
  `.awaitingConfirmations`, `.failed`, `.canceled` — richer than the boolean
  `ongoing`. Relevant to `pendingRoundStates()`, `progressPendingRounds()`,
  `cancelPendingRound(roundId:)`, `refreshVtxosDelegated(vtxoIds:)`. Do not remove
  `ongoing` reads when adopting.
- **Externally funded board** (`boardFundingAddress` → `boardPsbt`). Persist and
  replay `keypairIndex`/`expiryHeight` unchanged. Only if the feature is planned.
- **`OnchainWallet.evictTx(txid:)`.** Only for definitively-superseded txs.

## Tests

- Per the lean-verification workflow: scoped tests only where logic changed; batch the
  full mobile suite at the end; desktop ignored.
- Phase 1 is type-substitution — no new tests, just confirm the suite stays green.
- Phase 2 new tests:
  - `deleteWallet()` uses `stopDaemonWait()` (assert the mock records the wait call).
  - Import path invokes `initialScanOnchain` and surfaces the scanning state.
  - `estimateEmergencyExitFee` pre-flight blocks on `fundable == false`.
  - `recoveryStatus()` mapping: `.notRun` / `.failed` / `.completed` each drive the
    intended import outcome; `.failed` gets the retryable path.
- Watch the mock: every protocol addition needs a mock stub or the whole test target
  fails to build.

## Suggested order of work

1. Phase 0 matched-pair + clean build.
2. Phase 1 one-line `vtxoLifetime` migration; confirm green.
3. Phase 2.1 (`stopDaemonWait`) and 2.4 (`recoveryStatus`) — small, high-value.
4. Phase 2.2 (`initialScanOnchain`) with the import "scanning" state.
5. Phase 2.3 (`estimateEmergencyExitFee`) exit pre-flight.
6. Scoped tests as you go; full mobile suite at the end.
7. Update README status + write `04-completion-report.md`.
