# API Changes: Bark FFI Bindings v0.19.0 → v0.23.0 (Bark v0.6.1 → v0.7.0)

Declarations below are quoted verbatim from the generated `Bark.swift` in the
resolved checkout (`4c86dcc`). UniFFI contract version is **30 in both** — no
toolchain bump. **Nothing was removed or renamed**; every symbol
`BarkWalletProtocol` declares still exists with the same signature. The breakage is
confined to three record layouts and one callback protocol — and, as
[README.md](README.md) documents, **none of the three record changes break a call
site in this repo** because the app never constructs those FFI structs.

---

## 1. Source-breaking-shaped changes (verified)

### 1.1 `RoundState` gained two fields

```swift
public struct RoundState: Equatable, Hashable {
    public var id: UInt32
    public var ongoing: Bool
    public var state: RoundFlowKind      // NEW
    public var scheduledHeight: UInt32?  // NEW
    public init(id: UInt32, ongoing: Bool, state: RoundFlowKind, scheduledHeight: UInt32?)
}

public enum RoundFlowKind: Equatable, Hashable {
    case delegatedPending       // waiting for its scheduled round; see scheduledHeight
    case pending                // interactive, waiting for its round
    case ongoing                // being played out with the server
    case awaitingConfirmations
    case failed
    case canceled
}
```

- `ongoing` stays and is documented as equivalent to `state` being `.pending` or
  `.ongoing`, kept for compatibility — existing reads keep working.
- `scheduledHeight` is only meaningful while `state == .delegatedPending`.
- **Repo impact: none.** No `RoundState(...)` construction exists in the app, tests,
  or previews. Protocol surface that *returns* `RoundState`
  (`pendingRoundStates() -> [RoundState]`, `refreshVtxosDelegated(vtxoIds:) ->
  RoundState?`) is unaffected — the values flow through from the FFI.

### 1.2 `Config.vtxoRefreshExpiryThreshold`: `UInt32?` → `UInt16?`

```swift
public var vtxoRefreshExpiryThreshold: UInt16?   // was UInt32?
```

Integer *literals* still compile; a typed `UInt32`/`Int` variable would not.
**Repo impact: none.** The single construction site (`makeConfig`,
`BarkWalletFFI+Configuration.swift:236`) passes `vtxoRefreshExpiryThreshold: nil`.

### 1.3 `ArkInfo` gained `vtxoLifetime: UInt32`

Inserted **between** `vtxoExitDelta` and `vtxoExpiryDelta`:

```swift
public struct ArkInfo: Equatable, Hashable {
    public var network: Network
    public var serverPubkey: String
    public var roundIntervalSecs: UInt64
    public var nbRoundNonces: UInt32
    public var vtxoExitDelta: UInt32
    public var vtxoLifetime: UInt32      // NEW
    public var vtxoExpiryDelta: UInt32   // DEPRECATED upstream, same value as vtxoLifetime
    public var htlcSendExpiryDelta: UInt32
    public var htlcExpiryDelta: UInt32
    public var maxVtxoAmountSats: UInt64?
    public var requiredBoardConfirmations: UInt32
    public var maxUserInvoiceCltvDelta: UInt16
    public var minBoardAmountSats: UInt64
    public var lnReceiveAntiDosRequired: Bool
    public var feeSchedule: FeeSchedule
    public var maxVtxoExitDepth: UInt16
    // memberwise init inserts vtxoLifetime between vtxoExitDelta and vtxoExpiryDelta
}
```

`vtxoExpiryDelta` still exists and carries the same value, documented as deprecated
("upstream renamed this to `vtxo_lifetime` … goes away once upstream drops it").

- **Repo impact: no construction break** (no `Bark.ArkInfo(...)` anywhere).
- **Reads to migrate** (deprecation hygiene, the one mechanical Phase-1 edit):
  - `BarkWalletFFI+Configuration.swift:183` — `vtxoExpiryDelta:
    Int(ffiArkInfo.vtxoExpiryDelta)` → `Int(ffiArkInfo.vtxoLifetime)`.
  - `BarkWalletFFI+Configuration.swift:173` — the debug-log interpolation of
    `ffiArkInfo.vtxoExpiryDelta`.
- **Do NOT rename** the app model field. `ArkInfoModel.vtxoExpiryDelta: Int`
  (`ArkeUI/Sources/ArkéUI/Models/ArkInfoModel.swift:18`) and its Codable key
  `vtxo_expiry_delta` are part of the metadata-export JSON schema. Only the *source*
  of the value moves to `vtxoLifetime`.

### 1.4 `CustomOnchainWalletCallbacks` gained a required method

```swift
public protocol CustomOnchainWalletCallbacks: AnyObject {
    func getBalance() throws -> UInt64
    func prepareTx(destinations:feeRateSatPerVb:) throws -> String
    func prepareDrainTx(address:feeRateSatPerVb:) throws -> String
    func finishPsbt(psbtBase64:) throws -> String
    func isMine(scriptPubkeyHex:) throws -> Bool
    func registerTx(txHex:) throws
    func evictTx(txid: String) throws   // NEW
    func makeSignedP2aCpfp(params:) throws -> String
    func storeSignedP2aCpfp(txHex:) throws
    func sync() throws
}
```

> Bark calls `evictTx` when a CPFP it broadcast was RBF-replaced by a competing
> party, so the tx's inputs should return to coin selection immediately instead of
> waiting for the sync eviction grace period.

- **Repo impact: none.** No type in the repo conforms to
  `CustomOnchainWalletCallbacks`; the app uses the built-in BDK onchain wallet
  (`OnchainWallet.default(...)`, `BarkWalletFFI+WalletCreation.swift:183,453`). Skip.

### 1.5 FFI checksums moved on unchanged signatures

`customonchainwalletcallbacks_{make_signed_p2a_cpfp, store_signed_p2a_cpfp, sync}`,
`wallet_recovery_report`, and `wallet_validate_arkoor_address` have new checksums
with identical Swift signatures (UniFFI hashes docstrings into the metadata). A
binary/`Bark.swift` mismatch fails at `uniffiEnsureInitialized()` with
`apiChecksumMismatch` at **runtime**, not compile time. → clean build + DerivedData
wipe in Phase 0.

---

## 2. New API, ranked by relevance to `BarkWalletProtocol`

### High — should go into the protocol

**`Wallet.stopDaemonWait() async throws`** (verified, `Bark.swift:2345`)
> Stop the background daemon and wait until its tasks have finished. No-op when no
> daemon is running.

Fixes a real race: `deleteWallet()` → `shutdownWallet()`
(`BarkWalletFFI+WalletLifecycle.swift:377`) → `stopDaemon()`
(`wallet.stopDaemon()`), which returns before tasks drain, then the datadir is
removed. Use `stopDaemonWait()` on the delete path.

**`OnchainWallet.initialScan(birthdayHeight: UInt32?) async throws -> UInt64`**
(verified, `Bark.swift:1705`)
> Run once after restoring from a mnemonic: `sync` only covers addresses this wallet
> instance has revealed, so it never finds transactions from a previous incarnation.
> Gap-limited full scan on esplora (`birthday_height` ignored there), block scan from
> `birthday_height` on bitcoind. Returns total balance in sats.

The import path (`openImportedWallet`, `BarkWalletFFI+WalletCreation.swift:547`)
recovers VTXOs via `recoveryReport()` but has no onchain-history recovery. Wire this
in. Esplora ignores `birthdayHeight`, so `nil` is acceptable.

**`Wallet.estimateEmergencyExitFee(vtxoIds:feeRateSatPerVb:destination:) async throws -> EmergencyExitFeeEstimate`**
(verified, `Bark.swift:2153`)

```swift
public struct EmergencyExitFeeEstimate: Equatable, Hashable {
    public var exitBroadcastFeeSats: UInt64  // CPFP fees paid now from confirmed onchain funds
    public var claimFeeSats: UInt64          // later batched drain-tx fee, deducted from recovered value
    public var totalFeeSats: UInt64          // sum of the two
    public var feeRateSatPerVb: UInt64       // rate the broadcast leg was priced at
    public var txsToBroadcast: UInt64        // exit txs still needing broadcast + bump
    public var fundable: Bool                // false ⇒ the exit stalls midway even if a single bump looks affordable
}
```

Pass an **empty** `vtxoIds` to price exiting the whole wallet. It syncs the onchain
wallet first (slow call). `fundable == false` is the single most useful exit-UI
pre-flight signal. It errors on callback-backed onchain wallets — **moot here** (BDK
backed), but handle the error rather than surfacing a generic failure.

**`Wallet.recoveryStatus() -> RecoveryStatus`** (verified, `Bark.swift:2302`;
synchronous, non-throwing)

```swift
public enum RecoveryStatus: Equatable, Hashable {
    case notRun                      // wallet already existed locally, or skipRecovery set
    case failed(message: String)     // scan errored; funds may be missing until retried
    case completed(report: RecoveryReport)
}
```

`recoveryReport() -> RecoveryReport?` still exists (`Bark.swift:2289`) but cannot
distinguish "never ran" from "failed". The app currently reads `recoveryReport()`
(`BarkWalletFFI+WalletCreation.swift:572,610,621`). Moving to `recoveryStatus()`
lets `.failed` get a distinct, retryable presentation.

### Medium — adopt if the feature is wanted

**`OnchainWallet.evictTx(txid: String) async throws`** (verified, `Bark.swift:1690`)
> Only for a tx definitively superseded on-chain (RBF-replaced exit CPFP); evicting a
> still-in-flight tx invites a self-inflicted double-spend.

**Externally funded board (payjoin-style)** (verified):
```swift
func boardFundingAddress() async throws -> BoardFundingInfo             // Bark.swift:2093
func boardPsbt(psbtBase64:keypairIndex:expiryHeight:) async throws -> PendingBoard  // :2095

public struct BoardFundingInfo: Equatable, Hashable {
    public var address: String
    public var expiryHeight: UInt32
    public var keypairIndex: UInt32
}
```
The funding script commits to the derived keypair and expiry height, so
`keypairIndex` and `expiryHeight` must be persisted and passed back **unchanged**,
including on retries. Only if external board funding is a planned feature.

### Low — informational

- `validateArkoorAddress(address:)` — doc clarification only, no signature change.
- `importVtxo(vtxoBase64:)` / `vtxoEncoded(vtxoId:)` — unchanged.

---

## 3. Verified non-changes (guard against over-eager refactors)

- **No `BarkWalletProtocol` method changed** — `importWallet`, `deleteWallet`,
  `getArkInfo`, `pendingRoundStates`, `refreshVtxosDelegated`, `progressPendingRounds`,
  `cancelPendingRound`, `getConfig`, the `estimate*` family, `stopDaemon` all keep
  their signatures.
- `RoundState.ongoing` still exists (compatibility alias) — do not remove reads.
- `ArkInfo.vtxoExpiryDelta` still exists (deprecated) — migrate reads but expect no
  compile break.
- `recoveryReport() -> RecoveryReport?` still exists alongside the new
  `recoveryStatus()`.

---

## 4. Migration checklist

**Phase 0 — matched pair:**
- [ ] Confirm `.xcframework`/dylib and `Bark.swift` swapped together; wipe
      DerivedData; clean build (guards against runtime `apiChecksumMismatch`).

**Phase 1 — the one mechanical edit:**
- [ ] `BarkWalletFFI+Configuration.swift:183` `Int(ffiArkInfo.vtxoExpiryDelta)` →
      `Int(ffiArkInfo.vtxoLifetime)`
- [ ] `BarkWalletFFI+Configuration.swift:173` debug-log interpolation → `vtxoLifetime`
- [ ] Do **not** touch `ArkInfoModel.vtxoExpiryDelta` / its `vtxo_expiry_delta` key
- [ ] Confirm the build is green with no other edits (no construction-site breaks)

**Phase 2 — adopt new API (protocol + mock + real wallet):** see
[02-migration-plan.md](02-migration-plan.md).
- [ ] `stopDaemonWait()` on `BarkWalletProtocol`; use it in the `deleteWallet()` path
- [ ] `initialScanOnchain(birthdayHeight:)` on the protocol; wire into
      `openImportedWallet`; mock no-ops it
- [ ] `estimateEmergencyExitFee(...)` on the protocol as an exit pre-flight
- [ ] `recoveryStatus()` on the protocol, replacing `recoveryReport()` ambiguity

**Phase 3 — optional (ask first):** `RoundFlowKind`-rich round UI; externally funded
board; `OnchainWallet.evictTx`.
