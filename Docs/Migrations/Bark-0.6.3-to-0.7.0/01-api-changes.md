# Bark API Changes: Old → New

**Migration:** Bark v0.2.1 → v0.2.2, Bark FFI Bindings v0.6.3 → v0.7.0

This document summarises every public API difference between `Bark-old.swift` and `Bark-new.swift`, and flags the impact on `BarkWalletProtocol.swift`.

---

## 1. New type: `LightningSendStatus` (enum)

The new version introduces a typed status enum that replaces bare `String?` and `LightningSend` returns across all lightning-send entry points.

```swift
public enum LightningSendStatus: Equatable, Hashable {
    case unknown                                          // no record / pruned
    case inProgress(send: LightningSend)                 // HTLC VTXOs locked
    case paid(paymentHash: String, preimage: String)     // settled, preimage proves payment
}
```

---

## 2. `LightningSend` struct — field changes

| Field | Old | New |
|---|---|---|
| `invoice` | ✅ `String` | ✅ `String` |
| `amountSats` | ✅ `UInt64` | ✅ `UInt64` |
| `htlcVtxoCount` | ✅ `UInt32` | ✅ `UInt32` |
| `preimage` | ✅ `String?` | ❌ **removed** |
| `feeSats` | ❌ absent | ✅ **added** `UInt64` |

The preimage has moved to `LightningSendStatus.paid(paymentHash:preimage:)`. Any code reading `LightningSend.preimage` must switch to pattern-matching on `LightningSendStatus`.

---

## 3. `WalletProtocol` — changed method signatures

### 3a. Lightning pay methods: new `wait` parameter + new return type

All three pay methods gain a `wait: Bool` argument and now return `LightningSendStatus` instead of `LightningSend`.

| Method | Old signature | New signature |
|---|---|---|
| `payLightningInvoice` | `(invoice: String, amountSats: UInt64?) async throws -> LightningSend` | `(invoice: String, amountSats: UInt64?, wait: Bool) async throws -> LightningSendStatus` |
| `payLightningOffer` | `(offer: String, amountSats: UInt64?) async throws -> LightningSend` | `(offer: String, amountSats: UInt64?, wait: Bool) async throws -> LightningSendStatus` |
| `payLightningAddress` | `(lightningAddress: String, amountSats: UInt64, comment: String?) async throws -> LightningSend` | `(lightningAddress: String, amountSats: UInt64, comment: String?, wait: Bool) async throws -> LightningSendStatus` |

### 3b. `checkLightningPayment` — return type changed

```swift
// Old
func checkLightningPayment(paymentHash: String, wait: Bool) async throws -> String?

// New
func checkLightningPayment(paymentHash: String, wait: Bool) async throws -> LightningSendStatus
```

---

## 4. `WalletProtocol` — new methods

These did not exist in the old bindings:

```swift
func isInvoicePaid(paymentHash: String) async throws -> Bool
func lightningSendState(paymentHash: String) async throws -> LightningSendStatus
```

`lightningSendState` is a non-blocking status poll, complementing `checkLightningPayment`.

---

## 5. Everything else — unchanged

The following are **identical** between old and new:

- All non-lightning `WalletProtocol` methods (balance, board, exits, vtxos, rounds, sync, etc.)
- `OnchainWalletProtocol` and `OnchainWallet`
- `NotificationHolderProtocol` and `NotificationHolder`
- `CustomOnchainWalletCallbacks`
- `BarkLogger`
- All `Wallet` static constructors (`create`, `createWithOnchain`, `open`, `openWithDaemon`, `openWithOnchain`)
- All structs except `LightningSend`: `Balance`, `ArkInfo`, `Vtxo`, `Movement`, `FeeEstimate`, `LightningReceive`, `LightningInvoice`, `ExitVtxo`, `ExitProgressStatus`, `WalletProperties`, `RoundState`, `PendingBoard`, `OffboardResult`, `OnchainBalance`, `AddressWithIndex`, `ExitClaimTransaction`, `ExitTransactionStatus`, `BlockRef`, `Config`, `CpfpParams`, `Destination`, `OutPoint`
- All enums except the new one: `BarkError`, `Network`, `LogLevel`, `WalletNotification`
- Free functions: `extractTxFromPsbt`, `generateMnemonic`, `validateArkAddress`, `validateMnemonic`

---

## 6. Impact on `BarkWalletProtocol.swift`

### Breaking changes — must update

| Location in protocol | Change required |
|---|---|
| `checkLightningPayment(paymentHash:wait:) -> String?` | Change return type to `LightningSendStatus` |
| `payLightningInvoice(invoice:amountSats:) -> LightningSend` | Add `wait: Bool`, change return type to `LightningSendStatus` |
| `payLightningOffer(offer:amountSats:) -> LightningSend` | Add `wait: Bool`, change return type to `LightningSendStatus` |
| `payLightningAddress(lightningAddress:amountSats:comment:) -> LightningSend` | Add `wait: Bool`, change return type to `LightningSendStatus` |

### Downstream: `LightningSend.preimage` usage

Any implementation or call site that reads `.preimage` from a `LightningSend` must be migrated. The preimage is now only available via:

```swift
if case .paid(let paymentHash, let preimage) = status { … }
```

### New methods to add to the protocol (optional)

```swift
func isInvoicePaid(paymentHash: String) async throws -> Bool
func lightningSendState(paymentHash: String) async throws -> LightningSendStatus
```

---

## 7. Migration cheat-sheet

```swift
// Old: pay and get preimage directly
let send = try await wallet.payLightningInvoice(invoice: inv, amountSats: nil)
let preimage = send.preimage  // was optional on LightningSend

// New: pay and inspect status
let status = try await wallet.payLightningInvoice(invoice: inv, amountSats: nil, wait: true)
switch status {
case .paid(let paymentHash, let preimage):
    // payment confirmed, preimage available
case .inProgress(let send):
    // still in flight — send.feeSats now available for display
case .unknown:
    // not found
}

// Old: poll payment status
let result: String? = try await wallet.checkLightningPayment(paymentHash: hash, wait: false)

// New: poll payment status
let status: LightningSendStatus = try await wallet.checkLightningPayment(paymentHash: hash, wait: false)
// or use the dedicated non-blocking poller:
let status2: LightningSendStatus = try await wallet.lightningSendState(paymentHash: hash)
```
