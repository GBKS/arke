# API Changes: Bark FFI Bindings v0.15.0 → v0.16.0 (Bark v0.6.0, unchanged)

Verified against `git diff 0b63390 5c72f6e -- swift/Sources/Bark/Bark.swift`
in the resolved package checkout. `WalletProtocol` is byte-for-byte identical
(94 methods; the only edits are two doc comments on `payLightningAddress` /
`payLightningOffer` dropping the "UniFFI-only, not wasm-compatible" note).
Every break is a **field type change on an existing struct**; no method was
added to or removed from `WalletProtocol`, nothing was renamed.

---

## 1. `ArkInfo.feeScheduleJson: String` → `feeSchedule: FeeSchedule`

The server fee schedule is no longer a JSON string to decode yourself.

```swift
public struct FeeSchedule: Equatable, Hashable {
    public var board: BoardFees
    public var offboard: OffboardFees
    public var refresh: RefreshFees
    public var lightningReceive: LightningReceiveFees
    public var lightningSend: LightningSendFees
}

public struct BoardFees: Equatable, Hashable {
    public var minFeeSats: UInt64
    public var baseFeeSats: UInt64
    public var ppm: UInt64            // parts-per-million on the boarded amount
}

public struct OffboardFees: Equatable, Hashable {
    public var baseFeeSats: UInt64
    public var fixedAdditionalVb: UInt64   // fixed vB charged on top of output size
    public var ppmExpiryTable: [PpmExpiryFeeEntry]
}

public struct RefreshFees: Equatable, Hashable {
    public var baseFeeSats: UInt64
    public var ppmExpiryTable: [PpmExpiryFeeEntry]
}

public struct LightningReceiveFees: Equatable, Hashable {
    public var baseFeeSats: UInt64
    public var ppm: UInt64            // parts-per-million on the received amount
}

public struct LightningSendFees: Equatable, Hashable {
    public var minFeeSats: UInt64
    public var baseFeeSats: UInt64
    public var ppmExpiryTable: [PpmExpiryFeeEntry]
}

public struct PpmExpiryFeeEntry: Equatable, Hashable {
    public var expiryBlocksThreshold: UInt32
    public var ppm: UInt64            // ppm applied for this expiry period
}
```

No other `ArkInfo` field changed. New memberwise init (only the
`feeSchedule` parameter differs, same position as `feeScheduleJson` was):

```swift
ArkInfo(network:serverPubkey:roundIntervalSecs:nbRoundNonces:vtxoExitDelta:
        vtxoExpiryDelta:htlcSendExpiryDelta:htlcExpiryDelta:maxVtxoAmountSats:
        requiredBoardConfirmations:maxUserInvoiceCltvDelta:minBoardAmountSats:
        lnReceiveAntiDosRequired:feeSchedule:maxVtxoExitDepth:)
```

⚠️ **Name collision:** ArkéUI also exports a `FeeSchedule` (the app's
Bark-free presentation model, different field spellings: `minFeeSat: Int`
vs `minFeeSats: UInt64`, `*FeeStructure` sub-types). Files importing both
`Bark` and `ArkeUI` must qualify: `BarkWalletFFI+Configuration.swift`,
`MockBarkWallet.swift`, `VTXORefreshService.swift` (bare `FeeSchedule`
params at 289/335). See [02-migration-plan.md](02-migration-plan.md) §1.

## 2. `Vtxo.state: String` → `VtxoState`

```swift
public enum VtxoState: Equatable, Hashable {
    /// Available; can be spent in a future round.
    case spendable
    /// Locked by an operation. `holder` is `None` only for the narrow
    /// window between creating a fresh locked VTXO and pinning it to a
    /// specific operation, so a locked VTXO can legitimately carry no
    /// lock reason yet.
    case locked(holder: VtxoLockHolder?)
    /// Consumed.
    case spent
    /// In (or completed) a unilateral exit.
    case exited
}

public enum VtxoLockHolder: Equatable, Hashable {
    /// A wallet action checkpoint. `id` is upstream's `WalletActionId`
    /// (an opaque string).
    case action(id: String)
    /// A pre-action subsystem, keyed by its movement.
    case movement(id: UInt32)
}
```

`Vtxo.kind` is **still `String`** — leave it alone. No other `Vtxo` field
changed. Memberwise init:

```swift
Vtxo(id:amountSats:expiryHeight:kind:state:exitDepth:exitTxWeightWu:registered:)
```

Old string values were lowercase (`"spendable"`, `"locked"`, `"spent"`,
`"exited"`) — Swift case names match them exactly.

Affects every `Vtxo` producer in `WalletProtocol`: `allVtxos()`,
`spendableVtxos()`, `getExpiringVtxos(thresholdBlocks:)`,
`getVtxosToRefresh()`, `getVtxoById(vtxoId:)`, `vtxos()`.

## 3. Exit state: `String` → `ExitState`

`ExitVtxo.state`, `ExitProgressStatus.state`, `ExitTransactionStatus.state`
all went `String` → `ExitState`; `ExitTransactionStatus.history` went
`[String]?` → `[ExitState]?`. No other field on those three structs changed
(`ExitVtxo`: vtxoId/amountSats/isClaimable; `ExitProgressStatus`:
vtxoId/error; `ExitTransactionStatus`: vtxoId/transactionCount).

```swift
public enum ExitState: Equatable, Hashable {
    /// The exit was requested at the given tip.
    case start(tipHeight: UInt32)
    /// The exit transaction chain is being broadcast and confirmed.
    case processing(tipHeight: UInt32, transactions: [ExitTx])
    /// Fully confirmed; waiting out the exit delta until claimable.
    case awaitingDelta(tipHeight: UInt32, confirmedBlock: BlockRef, claimableHeight: UInt32)
    /// The exit output can be claimed.
    case claimable(tipHeight: UInt32, claimableSince: BlockRef, lastScannedBlock: BlockRef?)
    /// A claim transaction has been broadcast.
    case claimInProgress(tipHeight: UInt32, claimableSince: BlockRef, claimTxid: String)
    /// Terminal: the exit output was claimed (or spent deeper in the tree).
    case claimed(tipHeight: UInt32, txid: String, block: BlockRef)
    /// Terminal: the VTXO was already spent offchain, so the exit cannot proceed.
    case vtxoAlreadySpent(tipHeight: UInt32)
    /// Resumable: the user canceled the exit before its final transaction
    /// was broadcast. The VTXO stays spendable.
    case canceled(tipHeight: UInt32)
}

public struct ExitTx: Equatable, Hashable {
    public var txid: String
    public var status: ExitTxStatus
}

public enum ExitTxStatus: Equatable, Hashable {
    /// Inputs are still being verified.
    case verifyInputs
    /// Waiting for the given input txids to confirm. Sorted for a stable
    /// order (upstream keeps them in a set).
    case awaitingInputConfirmation(txids: [String])
    /// Ready for its CPFP child to be broadcast.
    case awaitingCpfpBroadcast
    /// CPFP child broadcast; waiting for confirmation.
    case awaitingConfirmation(childTxid: String, origin: ExitTxOrigin)
    /// Confirmed in a block.
    case confirmed(childTxid: String, block: BlockRef, origin: ExitTxOrigin)
}

public enum ExitTxOrigin: Equatable, Hashable {
    /// Broadcast by this wallet.
    case wallet(confirmedIn: BlockRef?)
    /// Seen in the mempool.
    case mempool
    /// Seen confirmed in a block.
    case block(confirmedIn: BlockRef)
}
```

This is an upgrade, not just a rename: the enum carries `tipHeight`,
`claimableHeight`, `claimableSince`, `claimTxid`, and per-tx CPFP status
directly — everything `ExitStatusParser` used to scrape out of Rust Debug
strings with regexes and brace counting.

⚠️ **Name shadowing (twice):** the app already defines its own
`ExitTxStatus` (`Shared/Data/ExitStatus/ParsedExitState.swift:124`) **and**
its own `ExitState` — the live-activity enum in
`Shared/Models/ExitProgressActivityAttributes.swift:53`
(`enum ExitState: String, Codable`, consumed by ArkeWidgets, which does
not import Bark). Being same-module, the app's types shadow Bark's in app
code — no ambiguity error, but any code meaning the binding's types must
write `Bark.ExitTxStatus` / `Bark.ExitState`. The live-activity enum keeps
its name; do not rename it as part of this migration.

Note the new `ExitTxStatus` has **no** `needsSignedPackage` /
`needsBroadcasting` / `broadcastWithCpfp` cases — those were pre-0.11 bark
debug variants that only survive in the app's persisted snapshots.

Affects: `progressExits(feeRateSatPerVb:)`, `listClaimableExits()`,
`getExitVtxos()`, `getExitStatus(vtxoId:includeHistory:includeTransactions:)`.

## 4. Additive: `OnchainWalletProtocol` gains four methods

```swift
/// Cached network fee-rate estimates from the wallet's chain source.
func feeRates() async throws -> FeeRates
/// Current chain tip height from the wallet's chain source.
func tipHeight() async throws -> UInt32
/// Every wallet transaction with fee, balance change, confirmation and
/// CPFP flag. Requires a prior `sync` to be meaningful.
func transactions() async throws -> [WalletTransaction]
/// The wallet's unspent outputs. Requires a prior `sync` to be meaningful.
func utxos() async throws -> [OnchainUtxo]
```

```swift
public struct FeeRates: Equatable, Hashable {
    public var fastSatPerKwu: UInt64
    public var regularSatPerKwu: UInt64
    public var slowSatPerKwu: UInt64
}

public struct WalletTransaction: Equatable, Hashable {
    public var txid: String
    /// The raw transaction, consensus-serialized as hex.
    public var txHex: String
    /// Total fee paid, when computable. `nil` for inbound or
    /// collaboratively-funded txs whose foreign prevouts aren't indexed.
    public var onchainFeeSats: UInt64?
    /// Net change to the wallet's balance: received minus sent.
    public var balanceChangeSats: Int64
    /// `Some` if confirmed in a block, `nil` if still in the mempool.
    public var confirmation: BlockRef?
    /// `true` when this tx spends a P2A fee anchor — i.e. it is a CPFP
    /// child bumping the parent that created the anchor (exit fee txs).
    public var isCpfp: Bool
}

public enum OnchainUtxo: Equatable, Hashable {
    /// A standard wallet UTXO.
    case local(outpoint: OutPoint, amountSats: UInt64, confirmationHeight: UInt32?)
    /// A spendable unilateral-exit output claimed from a VTXO.
    case exit(vtxoId: String, amountSats: UInt64, height: UInt32)
}
```

The concrete `OnchainWallet` class implements all four.
`CustomOnchainWalletCallbacks` did **not** gain corresponding callbacks, so
on a callback-backed onchain wallet these throw `Error.Inner` at runtime —
only the BDK-backed wallet supports them.

Three cautions for eventual adoption (deferred; see plan §6):

1. **Units.** `FeeRates` is sat/kWU; the app's API is sat/vB.
   `satPerVb = satPerKwu / 250` (1 kWU = 250 vB) — round up, floor at 1.
2. **Backend.** BDK-backed wallets only (see above).
3. **Ordering.** `transactions()` / `utxos()` require a prior `sync()`.

## 5. Verified non-changes (guard against over-eager refactors)

- `LightningReceive.state` is **still a `String`**
  (`"awaiting-payment" | "htlcs-ready" | "preimage-revealed" | "delivering" | "settled"`). Do not convert.
- Unchanged: `Wallet` class surface, `NotificationHolder`,
  `CustomOnchainWalletCallbacks`, `WalletOpenArgs`, `Config`, `Movement`,
  `LightningSend`, `LightningReceive`, `RoundState`, `PendingBoard`,
  `RecoveryReport`/`RecoveryBucket`, `Balance`, `OnchainBalance`,
  `FeeEstimate`, `ExitClaimTransaction`, `Destination`, `CpfpParams`,
  `BlockRef`, `OutPoint`, `WalletProperties`, `AddressWithIndex`,
  `LightningInvoice`, `OffboardResult`.
- Unchanged enums: `Error` (still the single `.Inner(message:)` case),
  `WalletNotification`, `LightningSendStatus`, `Network`, `LogLevel`.
- `FeeEstimate` is unchanged — the new `*Fees` structs describe the
  server's *schedule*; they are not a new return type for `estimate*`.

## 6. Migration checklist

**Hard compile errors:**

- [ ] Qualify `FeeSchedule` where `Bark` + `ArkeUI` are both imported
      (`BarkWalletFFI+Configuration`, `MockBarkWallet`,
      `VTXORefreshService:289,335`)
- [ ] Replace `FeeSchedule.from(jsonString: ffiArkInfo.feeScheduleJson)`
      with a `Bark.FeeSchedule → ArkéUI.FeeSchedule` field mapper
- [ ] `mapFFIStateToVTXOState` + `VTXOModel.init(from:)`: switch on
      `VtxoState` instead of `String` (exhaustive, no `default:`)
- [ ] `$0.state == "locked"` filters → `if case .locked`
      (`PendingRoundsListView_iOS:141`, `RoundStateDebugger:30`)
- [ ] Mock/preview `Vtxo(state: "…")` constructions → enum cases
      (`MockBarkWallet:449,459,476,505`, `BarkWalletFFI+VTXO:382`)
- [ ] New mapper `Bark.ExitState → ParsedExitState` (+ `Bark.ExitTx`/
      `Bark.ExitTxStatus`/`Bark.ExitTxOrigin`/`Bark.BlockRef` → app types)
- [ ] `ExitTransactionStatus+Parsing`: `parsedState`/`parsedHistory` use
      the mapper, not `ExitStatusParser`
- [ ] `ExitVtxo+Extensions:263` `formattedHistory`:
      `history.joined(separator:)` doesn't exist on `[ExitState]`
- [ ] `ExitProgress:68` `.unparsed(status.state)` — argument is no longer
      a `String`
- [ ] `ExitProgressionService+LiveActivity:345` calls
      `ExitStatusParser.parseState(status.state)` directly → mapper
- [ ] `ExitStatusDetailView_iOS:735` `Text(status.state)` (needs a
      `String`), and `:805,818` `ExitStatusParser.parseState(state)` on
      history entries — the history-row subview must take
      `Bark.ExitState` (raw text via `String(describing:)`) and use the
      mapper
- [ ] `ExitStatusSnapshot`: v2 Codable format + v1 string fallback;
      `snapshotStatus` API rework (can no longer rebuild a Bark struct)
- [ ] `WalletManager+Exits:203` `hasPrefix("Claimed")` → parsed-state check
- [ ] Test fixtures: `ExitProgressTests.makeStatus(state: String)` and
      `ExitProgressStatus(state: "…")` at `ExitProgressTests:414,415,429`,
      `ExitStatusParserTests` status constructions,
      `ExitBlockedInfoTests:145,189` `ExitVtxo(state:)` and the
      Rust-Debug-string `ExitTransactionStatus` fixtures at `:185,242`,
      `ExitFeeAttributionTests` `status()` fixture (~line 62) — see plan
      §4 for how string fixtures reroute to the legacy-decode path

**Silent behavior gaps:**

- [ ] Old persisted snapshots (Rust-Debug strings, incl. pre-0.11 case
      names) must still decode — keep `ExitStatusParser` as legacy decoder
- [ ] `ExitVtxo+Extensions.extractStateCaseName` works by luck on the new
      enum — replace with a real `switch` over `ExitState`
- [ ] `VtxoState.locked` now carries an optional holder; map `.exited` →
      `VTXOState.exited` as `mapFFIStateToVTXOState` already does.
      `VTXOModel.init(from:)` currently defaults unknowns (incl.
      `"exited"`) to `.pending` — a latent mislabel the enum switch fixes
- [ ] Display/log format drift: enum case names are lowerCamelCase where
      the old strings were CamelCase — `ExitVtxo.stateDisplayName`'s
      `default:` branch would show "canceled" instead of "Canceled" (add
      an explicit case), and FFI debug logs interpolating `.state`
      (`BarkWalletFFI+Exit:146,155,204,269,271`) change format (harmless)

**Deferred (separate pass):**

- [ ] Back `getUTXOs()` (currently a stub returning `[]`),
      `getOnchainTransactions()`, `getLatestBlockHeight()` with the new
      onchain methods — see plan §6
