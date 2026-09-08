# Completion Report: Bark FFI v0.19.0 → v0.23.0 (minimal pass)

**Date:** 2026-09-08
**Scope decision:** deliberately minimal — a vacation-window release. Shipped the
recompile, the deprecation migration, and the one behavioral fix with the best
risk/value ratio (`stopDaemonWait`). Everything else deferred (see below).

## What shipped

### Phase 0 — matched pair
No manual step needed: `bark-ffi-bindings` is consumed as an SPM package (resolved
revision `4c86dcc`), whose `Package.swift` pins the `BarkFFI.xcframework` binary to
the v0.23.0 release zip by checksum. Binary and `Bark.swift` cannot mismatch. The
docs' `apiChecksumMismatch` warning applies only to manual-swap workflows.

### Phase 1 — deprecation + one real compile fix
`Shared/Data/BarkWalletFFI/BarkWalletFFI+Configuration.swift`:

- `getArkInfo()` mapping and debug log now read `ffiArkInfo.vtxoLifetime` instead of
  the deprecated `vtxoExpiryDelta` (same value; upstream rename). The app model
  field `ArkInfoModel.vtxoExpiryDelta` and its `vtxo_expiry_delta` Codable key are
  **unchanged** — metadata-export schema preserved.
- **Unplanned fix:** `getConfig()`'s `ArkConfigModel` mapping broke on the
  `vtxoRefreshExpiryThreshold` `UInt32? → UInt16?` narrowing (a *read*, which the
  construction-only impact analysis missed). Widened losslessly at the boundary:
  `.map { UInt32($0) }`. App model unchanged.

### `stopDaemonWait()` adoption — the delete/overwrite race fix
`stopDaemon()` returns before the daemon's background tasks drain; every
`shutdownWallet()` caller then mutates or deletes wallet files. Changes:

- `BarkWalletFFI+WalletLifecycle.swift`: new internal `stopDaemonWait()` wrapper
  (mirrors `stopDaemon()`, calls `wallet.stopDaemonWait()`; nil-wallet → no-op).
  `shutdownWallet()` now calls it instead of `stopDaemon()` — covering all six
  callers: `createWallet`, `importWallet`, `deleteWallet`
  (`BarkWalletFFI+WalletCreation.swift:64,355,656`), `restoreWalletFromBackup`
  (`BarkWalletFFI+Backup.swift:95`), and both WalletManager teardown paths
  (`WalletManager+Wallet.swift:498`, `WalletManager.swift:1001`).
- `BarkWalletFFI+WalletCreation.swift:590`: the import `wipeAndRetry` path (stop
  daemon → delete database → reopen) had the identical race; swapped to
  `wallet.stopDaemonWait()`.
- The pre-existing 500ms sleeps in `shutdownWallet()` were **kept** — now redundant
  belt-and-braces, deliberately not removed in a minimal release.
- **No `BarkWalletProtocol` / `MockBarkWallet` changes** — daemon control was never
  on the protocol (correcting an earlier repo-scan misreport).

## Corrections discovered during implementation

1. The impact analysis grepped only for *constructions* of `Config`; the
   `vtxoRefreshExpiryThreshold` narrowing bit at a *read* site
   (`Configuration.swift:70`). Recorded in README's corrections section.
2. `stopDaemon()` is not on `BarkWalletProtocol` (earlier subagent report of
   "line 227" was wrong — the protocol has no daemon methods). The
   `stopDaemonWait` adoption is therefore FFI-internal only.

## Verification

- iOS build: ✅ green (27.7s, via Xcode BuildProject).
- Live diagnostics on all edited files: ✅ clean.
- Full mobile test suite (`xcodebuild test`, scheme "Arke mobile"): ✅ green
  (exit 0, no failures).
- On-device (mainnet, 2026-09-08): ✅ open/sync of existing wallet (log-reviewed:
  `vtxoLifetime: 4032` mapped, recovery "not run" as expected, balances/VTXOs
  reconcile), plus delete/create, import, arkoor and lightning send/receive.
  Two log observations filed to Open_Follow_Ups: bark 0.7.0 auto-starts the
  daemon on open (our `runDaemon()` now redundant), and an 18s
  initialize-call-to-execute gap.
- No xcstrings churn (checked; no new strings added).
- Behavior change surface: daemon shutdown now drains tasks before returning —
  strictly stronger guarantee; shutdown paths may take marginally longer, which is
  the point.

## Deferred (tracked in Shared/Docs/Open_Follow_Ups.md)

- `initialScanOnchain(birthdayHeight:)` on import — needs a new "scanning" UI state
  + on-device import verification (plan §2.2).
- `estimateEmergencyExitFee(...)` exit pre-flight — new UX, slow-call handling
  (plan §2.3).
- `recoveryStatus()` adoption (incl. the logging-only slim variant) — plan §2.4.
- Phase 3 (all optional): `RoundFlowKind`-rich round UI, externally funded board,
  `OnchainWallet.evictTx`.
- Update `Bark_Bindings_Unadopted_API.md` for the 0.23 surface (baseline is
  v0.18.0; the new-in-0.23 methods above belong there until adopted).
