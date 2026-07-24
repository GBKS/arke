# Bark API Changes: Old → New

**Migration:** Bark v0.3.0 → v0.4.0, Bark FFI Bindings v0.11.3 → v0.12.1

All signatures below are ✅ verified against the generated `Bark.swift` of the
resolved v0.12.1 package in DerivedData SourcePackages (revision `8f9c899`,
2026-07-24). Completeness is ✅ verified by `git diff 9be2240..8f9c899`
(the exact old→new pins from `Package.resolved`) inside the package checkout:
`Bark.swift` is the only file with API changes, and every changed declaration
in that diff is covered by sections 1–5 below. Sections 6–9 cover upstream
rust-side findings that do **not** appear in the Swift binding diff but matter
at runtime.

---

## 1. Onchain wallet bound once at `Wallet.open()` (breaking)

`WalletOpenArgs.onchain: OnchainWallet?` is now the *only* place the onchain
wallet is supplied. Five `Wallet` methods dropped their `onchainWallet:`
parameter:

```swift
// Old                                                    // New
boardAll(onchainWallet:) -> PendingBoard                  boardAll() -> PendingBoard
boardAmount(onchainWallet:amountSats:) -> PendingBoard    boardAmount(amountSats:) -> PendingBoard
progressExits(onchainWallet:feeRateSatPerVb:)             progressExits(feeRateSatPerVb:)
runDaemon(onchainWallet:)                                 runDaemon()
syncExits(onchainWallet:)                                 syncExits()
```

**Our status:** both `Wallet.open` call sites already pass
`WalletOpenArgs(datadir:onchain:...)` (`BarkWalletFFI+WalletLifecycle.swift`,
`BarkWalletFFI+WalletCreation.swift` ×2), so the daemon/board/exit/sync calls
retain onchain access with zero setup work. Return types unchanged
(`PendingBoard` was already the return in 0.11.3).

---

## 2. Two maintenance methods removed (breaking)

- `maintenanceWithOnchain(onchainWallet:)` — deleted, no replacement.
- `maintenanceWithOnchainDelegated(onchainWallet:)` — deleted, no replacement.

These existed only to thread an onchain wallet into maintenance. With the
wallet bound at open time, plain `maintenance()` / `maintenanceRefresh()` /
`maintenanceDelegated()` cover the same ground.

**Our status:** wrappers exist in `BarkWalletFFI+Maintenance.swift`, declared
in `BarkWalletProtocol`, stubbed in `MockBarkWallet`, passed through in
`WalletManager+Operations`. The only "caller" is inside a commented-out debug
block in `DataView_iOS.swift` — clean delete.

---

## 3. Lightning receive status/tracking reshaped (breaking)

```swift
// Old
lightningReceiveStatus(paymentHash:) async throws -> LightningReceive?   // nil = unknown hash
tryClaimLightningReceive(paymentHash:wait:) async throws                  // -> Void

// New
lightningReceiveState(paymentHash:) async throws -> LightningReceive      // throws on unknown hash
tryClaimLightningReceive(paymentHash:wait: Bool = false) async throws -> LightningReceive
```

`LightningReceive` struct (verified):

```swift
public struct LightningReceive {
    var paymentHash: String
    var invoice: String
    var amountSats: UInt64
    var state: String            // "awaiting-payment" | "htlcs-ready" | "preimage-revealed" | "settled"
    var paymentPreimage: String? // was non-optional; now populated once known
    var settledAt: Int64?        // unix seconds, set only once settled
}
```

Removed: `hasHtlcVtxos: Bool`, `preimageRevealed: Bool`.

The rust FFI produces `state` from exact string literals (verified in bark-ffi
`src/types.rs`) — safe to compare with `==`, no casing/prefix tricks.

**Boolean → state mapping:**

| Old check | New check |
|---|---|
| `hasHtlcVtxos && !preimageRevealed` (claimable) | `state == "htlcs-ready"` |
| `preimageRevealed` (claimed) | `state == "preimage-revealed"` or `"settled"` |
| `!hasHtlcVtxos && !preimageRevealed` (waiting) | `state == "awaiting-payment"` |

**Our consumers:** `LightningClaimService` (claimable filter + debug prints),
`BarkWalletFFI+Lightning.swift` `getLightningInvoiceStatus` (status text) and
`listLightningInvoices` (JSON dict). The rename itself is fully contained in
`BarkWalletProtocol` + `BarkWalletFFI+Lightning` + `MockBarkWallet` — no other
callers exist in the repo. App-side `paymentPreimage` plumbing
(TransactionModel / PersistentTransaction / MovementMetadata) is already
optional and fed from Movement metadata, not `LightningReceive` — unaffected.

---

## 4. `bolt11Invoice` gains optional `token:` (additive)

```swift
bolt11Invoice(amountSats:description:token: String? = nil) async throws -> LightningInvoice
```

**What the token is** (verified in bark 0.4.0 source,
`bark/src/actions/lightning/receive.rs`): an **anti-DoS credential for the
claim step**, stored as `anti_dos_token` on the receive record. When the wallet
claims a paid Lightning receive, the Ark server demands proof the claimer is a
legitimate wallet. The default proof is a **VTXO attestation** — signing with a
spendable VTXO the wallet already owns. A wallet with *zero spendable VTXOs*
(fresh wallet, first-ever receive) can't produce one; the token is the fallback
(`LightningReceiveAntiDos::Token`), sent in `PrepareLightningReceiveClaimRequest`
at claim time. Tokens are issued out-of-band by the server operator.

"Moves to invoice generation" (changelog) means the token is now handed to bark
when *creating* the invoice and persisted inside the crash-safe receive
checkpoint, so the claim can be recovered after a crash without re-supplying
it. It is **not** sent to the server at invoice-generation time.

**No change needed** — defaults to `nil`; with no token, claims authenticate
via VTXO attestation, which works whenever the wallet already holds funds
(same behaviour as 0.11.3, which never exposed a token at all). Implication to
remember: Lightning receive into a *completely empty* wallet may be rejected by
server anti-DoS until we have a token source (e.g. an onboarding voucher from
the server operator) to thread through `getLightningInvoice`.

---

## 5. `CustomOnchainWalletCallbacks` reshaped (breaking, dead-code conformer)

Removed (pull model):

```swift
getWalletTx(txid:) throws -> String?
getWalletTxConfirmedBlock(txid:) throws -> BlockRef?
getSpendingTx(outpoint:) throws -> String?
```

Added (push model, verified):

```swift
isMine(scriptPubkeyHex: String) throws -> Bool   // does this script belong to your keychains?
registerTx(txHex: String) throws                  // Bark pushes an unconfirmed tx to you
```

Unchanged: `getBalance`, `prepareTx`, `prepareDrainTx`, `finishPsbt`,
`makeSignedP2aCpfp`, `storeSignedP2aCpfp`, `sync`.

**Our status:** the only conformer is `BDKOnchainWallet`
(`Shared/Data/BDKOnchainWallet.swift`) — **instantiated nowhere**; production
uses Bark's built-in `OnchainWallet.default()`. The only outside reference is a
comment in `BDKCpfpHelper.swift`. It must be updated (or deleted) to compile.
If kept: BDK's `wallet.isMine(script:)` maps directly onto `isMine`, and
`registerTx` can apply the tx as unconfirmed to the BDK wallet.

---

## 6. Upstream: `ExitState` gains `Canceled` (runtime-only, not in Swift diff)

Exit state fields (`ExitProgressStatus.state`, `ExitTransactionStatus.state` +
`history`, `ExitVtxo.state`) are untyped `String`s produced by the rust FFI via
`format!("{:?}", ...)` **Debug formatting** — verified unchanged in bark-ffi
v0.16.0 `src/types.rs`. So the string format our `ExitStatusParser` assumes
still holds.

Diff of `bark/src/exit/models/states.rs` between tags `bark-0.3.0` and
`bark-0.4.0`:

- `ExitState`: gains exactly one variant — **`Canceled`** (set is now Start,
  Processing, AwaitingDelta, Claimable, ClaimInProgress, Claimed,
  VtxoAlreadySpent, Canceled).
- `ExitTxStatus`: **identical** (VerifyInputs, AwaitingInputConfirmation,
  AwaitingCpfpBroadcast, AwaitingConfirmation, Confirmed). Our parser already
  handles all of these plus legacy pre-0.3.0 names — no work needed.

**Reachability:** the v0.12.1 bindings expose **no cancel-exit API** and the
app never calls one, so `Canceled` cannot be produced by this integration
today (only e.g. a datadir shared with bark-cli, or a future bindings bump).

**Failure mode if it appears:** `ExitStatusParser.parseState` falls to
`default:` → `.unparsed` → `ExitProgress` maps to phase `.preparing` at step 1,
and the aggregate initializer counts it as an *active* exit (only
`vtxoAlreadySpent` is filtered) — i.e. a cancelled exit would look in-flight
and could keep the live activity alive. See plan for the optional hardening.

---

## 7. Upstream: `ExitError` gains variants — no impact

Full 0.4.0 variant list fetched from `bark/src/exit/models/error.rs`. The one
we depend on textually, `InsufficientConfirmedFunds`, still formats as
`"Insufficient Confirmed Funds: {needed} is needed but only {available} is available"`
— which matches the substring marker in `ExitBlockedInfo.swift`
(`"Insufficient Confirmed Funds"`). The fee-blocked exit classification
survives unchanged.

---

## 8. Upstream: `BarkPersister` changes — out of scope

The changelog notes `BarkPersister` gains required methods and loses
pending-offboard methods. Zero occurrences of any persister type in the
generated Swift bindings — it's a rust-side integration point we don't touch.

---

## 9. Unchanged (verified)

`Error` enum, `WalletOpenArgs`, and all other structs: `ArkInfo`, `Balance`,
`BlockRef`, `Config`, `CpfpParams`, `Destination`, `ExitClaimTransaction`,
`ExitProgressStatus`, `ExitTransactionStatus`, `ExitVtxo`, `FeeEstimate`,
`LightningInvoice`, `LightningSend`, `Movement`, `OffboardResult`,
`OnchainBalance`, `OutPoint`, `PendingBoard`, `RoundState`, `Vtxo`,
`WalletProperties`.
