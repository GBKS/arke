# Bark API Migration — Completion Report

**Date:** 2026-07-01
**Migration:** Bark v0.2.5 → v0.3.0, Bark FFI Bindings v0.10.0 → v0.11.3
**Status:** ✅ **COMPLETED — BUILD GREEN** (runtime smoke tests pending)

## Summary

Migrated the app to the Bark 0.11.3 Swift bindings. The bulk of the work was a
restructured wallet create/open path (`initWallet` + `Wallet.open(args:)`),
moving `network` out of `Config` and passing it separately to the FFI, and an
error-type rename (`BarkError` → `Bark.Error`) whose blast radius was much wider
than the initial analysis predicted — the new type is literally named `Error`
and collides with `Swift.Error` in every `import Bark` file.

The project builds with no errors or warnings. Phase 7 (additive APIs) and the
runtime smoke tests remain as follow-ups.

---

## Changes Implemented

### Phase 1: Error type sweep ✅
**Files:** all 13 `Shared/Data/BarkWalletFFI/*.swift` files

- Replaced every `catch let error as BarkError` with `catch let error as Bark.Error`
  (79 sites). `Bark.Error` conforms to `Foundation.LocalizedError`, so
  `.localizedDescription` continued to compile unchanged.

### Phase 2: `Config` construction & network reads ✅
**Files:** `BarkWalletFFI.swift`, `BarkWalletFFI+WalletCreation.swift`,
`BarkWalletFFI+WalletLifecycle.swift`, `BarkWalletFFI+Configuration.swift`

- `Config` no longer carries `network` and gained `userAgent: String?` (last
  field). Dropped `network:` and added `userAgent: nil` to every `Config(...)`.
- Added a stored `let ffiNetwork: Network` on `BarkWalletFFI`, computed once in
  `init`, and rerouted every `config.network` / `finalConfig.network` read to it
  (or to a local `net` in the two functions that accept a network override).

### Phase 3: Wallet creation / opening restructure ✅
**Files:** `BarkWalletFFI+WalletCreation.swift`, `BarkWalletFFI+WalletLifecycle.swift`

- `createWallet`: `Wallet.createWithOnchain(...)` → `initWallet(...)` +
  `Wallet.open(network:mnemonicOrSeed:config:args:)`.
- `importWallet`: existing-DB branch → `Wallet.open(args: WalletOpenArgs(createIfNotExists: false))`;
  fresh branch → `initWallet(...)` + `Wallet.open(args: WalletOpenArgs(createIfNotExists: true))`.
- `openWalletIfNeeded`: `Wallet.openWithOnchain(...)` → `Wallet.open(args:)`.
- `OnchainWallet.default(...)` gained `network:` at all three call sites.
- **`WalletOpenArgs.datadir` is required (no default)** — passed explicitly at
  every construction (the same `datadir` also passed to `initWallet`).
- `forceRescan` was dropped: no equivalent exists on `initWallet` or
  `WalletOpenArgs`.
- Database filename unchanged (`bark.sqlite`); no data migration.

### Phase 4: `sendArkoorPayment` returns Void ✅
**File:** `BarkWalletFFI+Transactions.swift`

- Dropped the `roundId` binding; success string no longer references it.
  Completion is surfaced via Movement events, not the return value. The protocol
  method `send(to:amount:) -> String` is unchanged.

### Phase 5: Removed `maybeScheduleMaintenanceRefresh` ✅
**Files:** `BarkWalletProtocol.swift`, `BarkWalletFFI+Maintenance.swift`,
`MockBarkWallet.swift`, `WalletManager+Operations.swift`, `Shared/Views/Data/VTXOListView.swift`

- Removed the declaration, FFI impl, mock, and manager wrapper.
- `VTXOListView`'s "Get new ones" button was rewired to the existing
  `walletManager.refreshVtxosDelegated(vtxoIds:)` (delegated/non-interactive
  refresh), filtering to spendable VTXOs — mirroring `VTXOListView_iOS`.

### Phase 6: `CustomOnchainWalletCallbacks.sync()` ✅
**File:** `Shared/Data/BDKOnchainWallet.swift`

- Added the new required member `func sync() throws { _ = try syncSync() }`.
  (`BDKOnchainWallet` is not currently wired via `OnchainWallet.custom(callbacks:)`
  — the app uses `OnchainWallet.default` — but the conformance still had to compile.)

### Phase 7: Additive APIs exposed ✅
**Files:** `BarkWalletProtocol.swift`, `BarkWalletFFI+Lightning.swift`,
`BarkWalletFFI+Exit.swift`, `MockBarkWallet.swift`,
`WalletManager+Lightning.swift`, `WalletManager+Operations.swift`

Exposed the two additive 0.11 methods across all four layers (protocol, FFI, mock,
manager), mirroring the existing `payLightningAddress` / `syncExits` patterns:

- `payLnurl(lnurl:amountSats:comment:wait:) -> LightningSendStatus` — manager
  wrapper passes `wait: true`, consistent with the other Lightning send wrappers.
- `syncForceExitedVtxos()` — the underlying FFI call takes no arguments (unlike
  `syncExits`, which takes the onchain wallet).

Not yet called from any UI — these are available for future wiring (e.g. `payLnurl`
may complete/replace part of `LNURL_PAY_IMPLEMENTATION_PLAN.md`).

### Unplanned: wider `Bark.Error` / `Swift.Error` collision ✅
**Files:** `BarkWalletFFI.swift`, `WalletManager.swift`, `BDKCpfpHelper.swift`,
`BDKTransactionReader.swift`, `BDKOnchainWallet.swift`, `BarkWalletFFI+Balance.swift`

The 0.11 error enum is named `Error`, so unqualified `Error` in type position now
resolves to `Bark.Error` in any `import Bark` file. This broke, and was fixed by
qualifying `Swift.Error`:

- Five error-enum declarations: `BarkWalletFFIError`, `BarkErrorArke`,
  `CpfpError`, `BDKTransactionReaderError`, `BDKWalletError`.
- Associated-value types: `BDKWalletError.broadcastFailed(..., underlyingError:)`
  and `BDKTransactionReaderError.syncFailed(_)`.
- `CheckedContinuation<Void, Error>` in `BDKTransactionReader.sync`.
- One granular case match the analysis wrongly assumed absent —
  `if case .ServerConnection(let message) = error` in `newAddress` — rewritten to
  inspect `.Inner(message:)` (diagnostic logging only).

---

## Key Decisions Made

### 1. `userAgent`
**Decision:** Pass `nil` everywhere.
**Rationale:** Preserves prior behaviour (there was no user agent before);
setting a branded agent string is a separate, optional enhancement.

### 2. `forceRescan`
**Decision:** Drop it — no replacement.
**Rationale:** Verified against the generated bindings; neither `initWallet` nor
`WalletOpenArgs` exposes a rescan parameter.

### 3. `VTXOListView` refresh button
**Decision:** Wire to `refreshVtxosDelegated(vtxoIds:)` (spendable VTXOs), not a
plain reload.
**Rationale:** Preserves the button's original "get new ones" intent using the
existing delegated (non-interactive) refresh path already used by the mobile
counterpart. Kept the view free of an `import Bark` dependency by logging round
presence rather than `roundState.id`.

### 4. `Bark.Error.localizedDescription`
**Decision:** Keep using `.localizedDescription`.
**Rationale:** It compiles (type conforms to `LocalizedError`). Note that
`errorDescription` is `String(reflecting: self)`, so messages now render as
`Bark.Error.Inner(message: "…")` rather than the bare message. If a clean
user-facing message is ever needed, extract via `if case .Inner(let m) = error`.

---

## Testing Checklist

### Automated / build
- [x] Build succeeds (active scheme), no errors or warnings
- [x] Protocol conformance verified (`MockBarkWallet`, `BarkWalletFFI`)
- [ ] Build the *other* target scheme (Mobile vs Desktop) — all changes are in
      `Shared/`, so risk is low but unverified from the CLI

### Manual testing required
- [ ] Create a fresh wallet
- [ ] Import an existing mnemonic — "DB exists" branch
- [ ] Import an existing mnemonic — fresh branch
- [ ] Open wallet on relaunch
- [ ] Send an ark-to-ark payment (verify UI success via Movement events)
- [ ] VTXO "Get new ones" delegated refresh (desktop `VTXOListView`)
- [ ] Trigger maintenance; confirm no dangling UI from the removed refresh helper

---

## Files Modified

**FFI layer (18)**
- `Shared/Data/BarkWalletFFI/BarkWalletFFI.swift`
- `Shared/Data/BarkWalletFFI/BarkWalletFFI+WalletCreation.swift`
- `Shared/Data/BarkWalletFFI/BarkWalletFFI+WalletLifecycle.swift`
- `Shared/Data/BarkWalletFFI/BarkWalletFFI+Configuration.swift`
- `Shared/Data/BarkWalletFFI/BarkWalletFFI+Transactions.swift`
- `Shared/Data/BarkWalletFFI/BarkWalletFFI+Maintenance.swift`
- `Shared/Data/BarkWalletFFI/BarkWalletFFI+Balance.swift`
- `Shared/Data/BarkWalletFFI/BarkWalletFFI+VTXO.swift`
- `Shared/Data/BarkWalletFFI/BarkWalletFFI+Lightning.swift`
- `Shared/Data/BarkWalletFFI/BarkWalletFFI+Exit.swift`
- `Shared/Data/BarkWalletFFI/BarkWalletFFI+Rounds.swift`
- `Shared/Data/BarkWalletFFI/BarkWalletFFI+Fees.swift`
- `Shared/Data/BarkWalletFFI/BarkWalletFFI+Server.swift`
- `Shared/Data/BarkWalletFFI/BarkWalletFFI+Mailbox.swift`
- `Shared/Data/BDKOnchainWallet.swift`
- `Shared/Data/BDKTransactionReader.swift`
- `Shared/Data/BDKCpfpHelper.swift`
- `Shared/Data/BarkWalletProtocol.swift`

**Manager / mock / views (4)**
- `Shared/Data/WalletManager/WalletManager.swift`
- `Shared/Data/WalletManager/WalletManager+Operations.swift`
- `Shared/Data/MockBarkWallet.swift`
- `Shared/Views/Data/VTXOListView.swift`

**Docs (2)**
- `Shared/Docs/Migrations/Bark-0.10.0-to-0.11.3/01-api-changes.md`
- `Shared/Docs/Migrations/Bark-0.10.0-to-0.11.3/02-migration-plan.md`

**Total: 24 files (22 code + 2 docs)**

---

## Follow-ups (not required for compile-green)

- ~~**Phase 7 additive APIs**~~ ✅ done — `payLnurl` and `syncForceExitedVtxos`
  exposed across all four layers (see Phase 7 above). Still un-wired to any UI.
- **Runtime smoke tests** (checklist above).
- **Second scheme build.**

---

## Rollback Plan

1. Revert the Bark package pin to 0.10.0 in the project package settings.
2. `git revert` the migration commit(s).
3. Clean build.

**Risk:** Low — all changes are compile-time enforced; transaction display is
driven by Movement events and is isolated from these API changes.
