# Bark API Changes: Old → New

**Migration:** Bark v0.2.5 → v0.3.0, Bark FFI Bindings v0.10.0 → v0.11.3

This document summarises every public API difference between the old and new
generated Swift bindings, and flags the impact on our code. Signatures marked
"⚠️ verify" should be double-checked against the resolved package's generated
`Bark.swift` in DerivedData before implementation — the analysis below is
derived from a binding diff, not a compile.

---

## 1. Wallet creation / opening restructured (breaking)

### Old — five static factories on `Wallet`

```swift
Wallet.create(mnemonic:config:datadir:)
Wallet.createWithOnchain(mnemonic:config:datadir:onchainWallet:forceRescan:)
Wallet.open(mnemonic:config:datadir:)
Wallet.openWithDaemon(mnemonic:config:datadir:)
Wallet.openWithOnchain(mnemonic:config:datadir:onchainWallet:)
```

### New — one init path + one open path

```swift
// Free function; returns nothing. Creates on-disk wallet state.  ⚠️ verify arg list
func initWallet(
    network: Network,
    mnemonicOrSeed: String,
    config: Config,
    datadir: String,
    allowUnreachableServer: Bool
) async throws

// Opens an already-initialised wallet.  ⚠️ verify WalletOpenArgs fields
static func Wallet.open(
    network: Network,
    mnemonicOrSeed: String,
    config: Config,
    args: WalletOpenArgs
) async throws -> Wallet

struct WalletOpenArgs {
    var runDaemon: Bool          // defaulted true
    var datadir: String          // ✅ verified REQUIRED — no default; must be passed
    var onchain: OnchainWallet?  // defaulted nil — onchain wallet now passed HERE
    var createIfNotExists: Bool  // defaulted true
    var createWithoutServer: Bool// defaulted false
}
```

**Mapping:**

> `datadir` is **required** in `WalletOpenArgs` and must be supplied in every
> construction below (in addition to the `datadir` passed to `initWallet`).

| Old call | New equivalent |
|---|---|
| `Wallet.create(...)` | `initWallet(...)` then `Wallet.open(..., args: WalletOpenArgs(datadir: datadir, createIfNotExists: true))` |
| `Wallet.createWithOnchain(..., onchainWallet:, forceRescan:)` | `initWallet(...)` then `Wallet.open(..., args: WalletOpenArgs(datadir: datadir, onchain: builtInWallet, createIfNotExists: true))` |
| `Wallet.open(...)` | `Wallet.open(network:, ..., args: WalletOpenArgs(datadir: datadir))` |
| `Wallet.openWithDaemon(...)` | `Wallet.open(..., args: WalletOpenArgs(runDaemon: true, datadir: datadir))` |
| `Wallet.openWithOnchain(..., onchainWallet:)` | `Wallet.open(..., args: WalletOpenArgs(datadir: datadir, onchain: builtInWallet))` |

> **`forceRescan` is dropped (✅ verified).** There is no rescan parameter on
> `initWallet` *or* `WalletOpenArgs` in the generated bindings. The old
> `forceRescan: true` intent has no API to map onto and is simply gone.

---

## 2. `Config.network` removed; `userAgent` added (breaking)

- `Config` no longer has a `network` field. `Network` is passed as a separate
  argument to `initWallet` / `Wallet.open` / `OnchainWallet.default`.
- `Config` gains `userAgent: String?`.

Every `Config(...)` construction must drop `network:` and add `userAgent:`. Every
read of `config.network` / `finalConfig.network` must switch to the network value
held separately.

---

## 3. `OnchainWallet.default(...)` gains `network:` (breaking)

```swift
// Old
OnchainWallet.default(mnemonic:config:datadir:)
// New  ⚠️ verify param order
OnchainWallet.default(network:mnemonic:config:datadir:)
```

---

## 4. Error type: `BarkError` → `Error` (breaking, wide sweep)

```swift
// Old: 14 typed cases
enum BarkError: Error {
    case Network(...), InsufficientFunds(...), InvalidVtxoId(...), /* … */
}

// New: single case, name shadows Swift.Error
enum Error {
    case Inner(message: String)
}
```

Two consequences:

1. The bare name `Error` collides with `Swift.Error` in any `import Bark` file.
   Reference it qualified: `Bark.Error`. (See the existing memory note on this.)
2. Granular case-matching is gone — only the message string is available. Any
   logic branching on a specific old case must instead inspect the message.

Our code never switches on specific `BarkError` cases (it only does
`catch let error as BarkError { … error.localizedDescription … }`), so the sweep
is mechanical: `catch let error as BarkError` → `catch let error as Bark.Error`.

> ✅ verified: `Bark.Error` conforms to `Foundation.LocalizedError`, so
> `.localizedDescription` compiles. **But** `errorDescription` is
> `String(reflecting: self)`, so it yields `Bark.Error.Inner(message: "…")` rather
> than the clean message. Any user-facing string that needs the raw message should
> extract it via `if case .Inner(let m) = error`.

---

## 5. `WalletProtocol` method changes

### 5a. Removed

```swift
func maybeScheduleMaintenanceRefresh() async throws -> UInt32?   // GONE
```

### 5b. `sendArkoorPayment` now returns Void (breaking)

```swift
// Old
func sendArkoorPayment(arkAddress:amountSats:) async throws -> String  // returned a round id
// New
func sendArkoorPayment(arkAddress:amountSats:) async throws            // Void
```

### 5c. New methods (additive — optional to expose)

```swift
func payLnurl(lnurl:amountSats:comment:wait:) async throws -> LightningSendStatus
func syncForceExitedVtxos() async throws
```

### 5d. `wait:` defaults (additive)

`wait:` on the lightning send/claim functions now defaults to `false`; existing
explicit call sites are unaffected.

---

## 6. `CustomOnchainWalletCallbacks` gains `sync() throws` (breaking)

Our `BDKOnchainWallet` declares conformance, so it must add a `sync() throws`
member or it will fail to compile — independent of whether it is currently wired
via `OnchainWallet.custom(callbacks:)`.

```swift
func sync() throws   // NEW required member
```

`BDKOnchainWallet` already has `syncSync() throws -> UInt64`; the new requirement
is a thin `Void`-returning wrapper.

---

## 7. Everything else — unchanged

All other structs, enums, free functions, and `WalletProtocol` /
`OnchainWalletProtocol` / `NotificationHolderProtocol` methods are byte-for-byte
identical: `RoundState`, `Vtxo`, `ExitVtxo`, `FeeEstimate`, `LightningSendStatus`,
`LightningReceive`, `LightningSend`, `ExitProgressStatus`, `ExitTransactionStatus`,
`ExitClaimTransaction`, `WalletNotification`, etc.
