# Migration Plan: Bark FFI v0.10.0 → v0.11.3

**Migration:** Bark v0.2.5 → v0.3.0, FFI Bindings v0.10.0 → v0.11.3

Concrete, ordered plan. Line numbers are from the working tree at planning time
(2026-07-01) and will drift as edits are applied — treat them as anchors, not
guarantees. Verify all new signatures against the resolved package's generated
`Bark.swift` in `DerivedData/.../SourcePackages/checkouts/bark-ffi-bindings`
before editing (do **not** use `~/workspace/bark-ffi-bindings`).

---

## Phase 0 — Verify real signatures ✅ DONE (2026-07-01)

Verified against `Bark.swift` in DerivedData SourcePackages:

- `initWallet(network:mnemonicOrSeed:config:datadir:allowUnreachableServer:)` —
  free func, `async throws -> Void`. No onchain wallet, no rescan param.
- `Wallet.open(network:mnemonicOrSeed:config:args:)` — `async throws -> Wallet`.
- `WalletOpenArgs(runDaemon:datadir:onchain:createIfNotExists:createWithoutServer:)`
  — **`datadir: String` is REQUIRED (no default)**; `onchain: OnchainWallet? = nil`;
  `createIfNotExists = true`; `createWithoutServer = false`; `runDaemon = true`.
- `OnchainWallet.default(network:mnemonic:config:datadir:)` — param order confirmed.
- `Config`: `network` removed; `userAgent: String?` added as the **last** field;
  memberwise init is fully positional with no defaults.
- `Bark.Error: Foundation.LocalizedError`, single `case Inner(message: String)`.
  `.localizedDescription` compiles but reflects the enum
  (`Bark.Error.Inner(message: "…")`), not the bare message.
- `forceRescan` has no replacement anywhere → dropped.

---

## Phase 1 — Error type sweep (mechanical, do early to unblock compile)

Replace every `catch let error as BarkError` with `catch let error as Bark.Error`.
`BarkError` no longer exists, so nothing compiles until this is done.

Do **not** touch the app's own `BarkErrorArke` enum (`WalletManager.swift:1048`)
or `BarkWalletFFIError` — those are ours and unaffected.

Affected files (≈ every FFI extension):

- `Shared/Data/BarkWalletFFI/BarkWalletFFI.swift` (170, 195)
- `BarkWalletFFI+Balance.swift` (62, 113, 195) — also the `type(of: error)`
  debug log at 115 still works.
- `BarkWalletFFI+VTXO.swift` (67, 114, 149, 188, 235, 271, 297, 321, 345, 369, 391, 413, 435, 461)
- `BarkWalletFFI+Lightning.swift` (many; see grep — 79 … 659)
- `BarkWalletFFI+Exit.swift` (41, 84, 116, 283, 314, 343, 369, 393, 417, 439, 461, 483)
- `BarkWalletFFI+Maintenance.swift` (42, 64, 93, 120, 149)
- `BarkWalletFFI+Rounds.swift` (35, 60, 84, 115, 140, 165)
- `BarkWalletFFI+Fees.swift` (32, 54, 76, 98, 120, 142, 164)
- `BarkWalletFFI+Server.swift` (152, 179)
- `BarkWalletFFI+Mailbox.swift` (32, 54)
- `BarkWalletFFI+Transactions.swift` (203, 249, 295)
- `BarkWalletFFI+WalletCreation.swift` (300, 546)
- `BarkWalletFFI+WalletLifecycle.swift` (337, 382, 411)

Where the catch body only uses `error.localizedDescription`, no further change is
needed if `Bark.Error` conforms to `LocalizedError` (confirm in Phase 0);
otherwise substitute `if case .Inner(let message) = error`.

Suggested approach: a single find/replace of the exact string
`catch let error as BarkError` → `catch let error as Bark.Error` across
`Shared/Data/BarkWalletFFI/`, then compile.

---

## Phase 2 — `Config` construction & `network` reads

**`BarkWalletFFI+WalletCreation.swift`**
- `Config(...)` at lines 69 and 353: drop `network: ffiNetwork`, add
  `userAgent: <value or nil>`. Keep `ffiNetwork` in a local — it's now needed for
  `initWallet` / `OnchainWallet.default`.
- `finalConfig.network` reads at 93, 183 (and the equivalent in import at 377,
  467): replace with the separate network value.

**`BarkWalletFFI+WalletLifecycle.swift`**
- `config.network` reads at 194, 209 (and debug helper `printWalletState` at
  `BarkWalletFFI+WalletCreation.swift:622`): replace with the stored network.

**Elsewhere:** any other `Config(...)` construction (check `BarkWalletFFI.swift`,
config plumbing in `NetworkConfig.swift` / `BarkWalletFFI+Configuration.swift`).
Confirm where the wallet's `Network` value is sourced (there is already
`convertToFFINetwork(_:)` at `BarkWalletFFI+WalletCreation.swift:653`).

---

## Phase 3 — Wallet creation / opening restructure (highest-impact)

### `BarkWalletFFI+WalletCreation.swift` — `createWallet`

- `OnchainWallet.default(mnemonic:config:datadir:)` at **171** → add `network:`.
- `Wallet.createWithOnchain(mnemonic:config:datadir:onchainWallet:forceRescan:)`
  at **189** → replace with:
  ```swift
  try await initWallet(network: net, mnemonicOrSeed: mnemonic, config: finalConfig,
                       datadir: datadir, allowUnreachableServer: true)
  let newWallet = try await Wallet.open(
      network: net, mnemonicOrSeed: mnemonic, config: finalConfig,
      args: WalletOpenArgs(datadir: datadir, onchain: builtInWallet, createIfNotExists: true))
  ```
  `WalletOpenArgs.datadir` is required — pass it explicitly (same `datadir` as
  `initWallet`). `forceRescan` is gone with no replacement; drop it.

### `BarkWalletFFI+WalletCreation.swift` — `importWallet`

- `OnchainWallet.default(...)` at **456** → add `network:`.
- The `walletExists` branch (478–500):
  - existing: `Wallet.openWithOnchain(...)` at **483** →
    `Wallet.open(..., args: WalletOpenArgs(datadir: datadir, onchain: builtInWallet, createIfNotExists: false))`.
  - new: `Wallet.createWithOnchain(...)` at **492** → `initWallet(...)` +
    `Wallet.open(..., args: WalletOpenArgs(datadir: datadir, onchain: builtInWallet, createIfNotExists: true))`.
  - Consider collapsing both branches into a single `Wallet.open` with
    `createIfNotExists: true` now that open can create — but keep the explicit
    branch if the restore-from-backup logging/behaviour matters.

### `BarkWalletFFI+WalletLifecycle.swift` — `openWalletIfNeeded`

- `OnchainWallet.default(...)` at **197** → add `network:`.
- `Wallet.openWithOnchain(...)` at **291** →
  `Wallet.open(network:, ..., args: WalletOpenArgs(datadir: datadir, onchain: builtInWallet))`.

> Database filename is unchanged: `bark.sqlite` was and remains the on-disk name
> in this release. No data migration or rename is required. The existing
> `walletExists` check in `importWallet` (`BarkWalletFFI+WalletCreation.swift:477`)
> and `WalletBackupService.databaseFileName` stay as-is.

---

## Phase 4 — `sendArkoorPayment` returns Void

**`BarkWalletFFI+Transactions.swift`** `send(to:amount:)` (around 240–248):
- `let roundId = try await wallet.sendArkoorPayment(...)` at **242** → drop the
  binding; call returns `Void`.
- Rewrite the success return (244, 247) to not reference `roundId`, e.g.
  `return "Successfully sent \(amount) sats to \(address)."`

The protocol method `send(to:amount:) -> String` (BarkWalletProtocol.swift:132)
can keep returning `String`; only the wrapped FFI return value is gone.

---

## Phase 5 — Remove `maybeScheduleMaintenanceRefresh`

- `Shared/Data/BarkWalletProtocol.swift:108` — remove declaration.
- `BarkWalletFFI+Maintenance.swift:51–64` — remove implementation.
- `Shared/Data/MockBarkWallet.swift:590` — remove mock.
- `Shared/Data/WalletManager/WalletManager+Operations.swift:302–306` — remove wrapper.
- `Shared/Views/Data/VTXOListView.swift:173` — remove/replace the call.
  Determine what the view did with the result (a scheduled block height) and
  whether `getNextRequiredRefreshBlockheight()` (still present) is an adequate
  replacement for the UI, or whether the feature is simply dropped.

---

## Phase 6 — `CustomOnchainWalletCallbacks.sync()`

**`Shared/Data/BDKOnchainWallet.swift`** — add the new required member:

```swift
func sync() throws {
    _ = try syncSync()   // existing syncSync() throws -> UInt64
}
```

Place it in the `// MARK: - CustomOnchainWalletCallbacks Implementation` section
(~line 226). Confirm the protocol wants a synchronous, no-arg, `Void` `sync()`
(Phase 0).

---

## Phase 7 — Optional: expose additive APIs

Not required for the build, but worth doing while the surface is fresh:

- `payLnurl(lnurl:amountSats:comment:wait:) -> LightningSendStatus` — add to
  `BarkWalletProtocol`, `BarkWalletFFI+Lightning.swift`, `MockBarkWallet`, and a
  `WalletManager+Lightning` wrapper. Note the existing
  `LNURL_PAY_IMPLEMENTATION_PLAN.md` — this may complete/replace part of it.
- `syncForceExitedVtxos()` — add if exit handling needs it.

Track these as follow-ups if the goal is a minimal compile-green migration first.

---

## Phase 8 — Build, run, verify

1. `BuildProject` for both ArkeMobile and ArkeDesktop.
2. Smoke-test the three lifecycle paths that changed the most:
   - Create a fresh wallet.
   - Import an existing mnemonic (both "db exists" and "fresh" branches).
   - Open on relaunch.
3. Send an ark-to-ark payment (verify the Void `sendArkoorPayment` path still
   reports success in the UI, driven by Movement events not the return string).
4. Trigger maintenance to confirm the removed refresh helper left no dangling UI.

---

## File checklist

| File | Phases |
|---|---|
| `Shared/Data/BarkWalletProtocol.swift` | 5 (,7) |
| `BarkWalletFFI/BarkWalletFFI+WalletCreation.swift` | 1,2,3 |
| `BarkWalletFFI/BarkWalletFFI+WalletLifecycle.swift` | 1,2,3 |
| `BarkWalletFFI/BarkWalletFFI+Transactions.swift` | 1,4 |
| `BarkWalletFFI/BarkWalletFFI+Maintenance.swift` | 1,5 |
| `BarkWalletFFI/*.swift` (Balance, VTXO, Lightning, Exit, Rounds, Fees, Server, Mailbox, core) | 1 |
| `Shared/Data/BDKOnchainWallet.swift` | 6 |
| `Shared/Data/MockBarkWallet.swift` | 4,5 |
| `Shared/Data/WalletManager/WalletManager+Operations.swift` | 5 |
| `Shared/Views/Data/VTXOListView.swift` | 5 |
| `BarkWalletFFI/BarkWalletFFI+Lightning.swift` + mock + manager | 7 (optional) |

After completion, add `03-impact-analysis.md` (if warranted) and
`04-completion-report.md` mirroring the `Bark-0.6.3-to-0.7.0` folder.
