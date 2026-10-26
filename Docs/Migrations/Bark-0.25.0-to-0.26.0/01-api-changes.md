# API Changes: Bark FFI v0.25.0 → v0.26.0 (bark 0.7.1 → 0.8.0)

All declarations below were read verbatim from the resolved checkout's
generated `Bark.swift` (revision `ada76c3`, tag `v0.26.0+bark-0.8.0`); line
numbers refer to that file. "Old" declarations come from the previous
checkout at `157b0fc`, diffed directly on 2026-10-25. Repo call-site facts
were verified by grep, file reads and per-file compiler diagnostics the
same day.

Bindings commits between the tags: 22, of which one changes Swift-side
behaviour (`01db51c`, §3.4); the rest are supply-chain and CI work plus
the release itself. Bark commits between `bark-0.7.1` and `bark-0.8.0`: 245.

## 1. Changed signatures

### 1.1 `sendArkoorPayment` returns the movement id

```swift
// Old (0.25)
open func sendArkoorPayment(arkAddress: String, amountSats: UInt64) async throws

// New (0.26) — protocol :2499, class :4401
func sendArkoorPayment(arkAddress: String, amountSats: UInt64) async throws -> UInt32
```

Upstream doc (verbatim, :2493-2498): "Send an out-of-round payment to an Ark
address. An address this bark cannot deliver to (see `validateArkoorAddress`)
is rejected up front, leaving the VTXOs spendable rather than cosigned.
Returns the id of the movement that records the payment."

Changelog #2610 adds: `send_arkoor_payment` "no longer returns before the
payment is done when a wallet sync drives it at the same time".

**Repo impact: one warning.** `BarkWalletFFI+Transactions.swift:226` discards
the result ("Result of call … is unused"). This is feedback ask 3 answered;
the heuristic payment-matching subsystem (`PendingPaymentMetadata`,
`Send_Metadata.md`) can be simplified against it — Track B.

### 1.2 `sendOnchain` returns `OffboardResult`

```swift
// Old (0.25)
open func sendOnchain(address: String, amountSats: UInt64) async throws -> String

// New (0.26) — protocol :2505, class :4422
func sendOnchain(address: String, amountSats: UInt64) async throws -> OffboardResult
// OffboardResult (:7916): txid: String, movementId: UInt32   (movementId is new)
```

Upstream doc (:2501-2504): "Send `amount_sats` from the offchain balance to
an onchain address, as an offboard. Returns the offboard txid and its
movement id."

**Repo impact: two errors** in `BarkWalletFFI.sendToOnchain`
(`BarkWalletFFI+Transactions.swift:275` os.Logger interpolation of the
result, `:279` returning it as `String`). The old `String` was the txid, and
the one UI caller discards it (`OffboardingModalView.swift:91`,
`_ = try await manager.sendToOnchain(…)`); `WalletOperationsService.swift:51`
only logs it. Return `result.txid`, log the movement id.

### 1.3 `pay*` gained `retryForSecs: UInt64?` (defaulted on the class)

```swift
// New (0.26) — class :3955 / :3979 / :3996 / :4019
open func payLightningInvoice(invoice: String, amountSats: UInt64?, wait: Bool = false, retryForSecs: UInt64? = nil) async throws -> LightningSendStatus
open func payLightningOffer(offer: String, amountSats: UInt64?, wait: Bool = false, retryForSecs: UInt64? = nil) async throws -> LightningSendStatus
open func payLightningAddress(lightningAddress: String, amountSats: UInt64, comment: String?, wait: Bool = false, retryForSecs: UInt64? = nil) async throws -> LightningSendStatus
open func payLnurl(lnurl: String, amountSats: UInt64, comment: String?, wait: Bool = false, retryForSecs: UInt64? = nil) async throws -> LightningSendStatus
```

The `WalletProtocol` requirements (:2395-2414) carry no defaults. Semantics
(`sendPayment` doc, :2509-2516): "`retry_for_secs` is how long the Ark
server keeps trying to pay, capped to the server's maximum; `None` leaves it
to the server and 0 makes a single attempt."

**Repo impact: compiles unchanged** — `BarkWalletFFI` calls the class
(`wallet: Wallet?`, `BarkWalletFFI.swift:79`). Mirroring the parameter on
`BarkWalletProtocol` (protocol mirrors the FFI) is Track B; no caller needs
a non-default today.

### 1.4 `estimateEmergencyExitFee` gained `feeMargin: Double?` (defaulted)

```swift
// New (0.26) — protocol :2227, class :3192
open func estimateEmergencyExitFee(vtxoIds: [String], feeRateSatPerVb: UInt64?, destination: String?, feeMargin: Double? = nil) async throws -> EmergencyExitFeeEstimate
```

Upstream doc (:2213-2226), the parts that change the Tier 1 Exits plan:
"`fee_margin` scales the broadcast leg (finite and non-negative; default
1.2). The estimate never reads the onchain wallet, so it works before the
wallet holds funds and with callback wallets too." `EmergencyExitFeeEstimate.fundable`
(:6347) is kept for binary compatibility but documented **deprecated**:
"bark dropped this field. Compare `exit_broadcast_fee_sats` against the
onchain balance instead; this one goes away in a later release."

**Repo impact: none today** — no caller. The DECIDED Tier 1 Exits entry
(`Open_Follow_Ups.md` → Tier 1 → Exits) describes the 0.7.1 estimator
(confirmed-coin CPFP simulation, `fundable`, onchain sync) and must be
rewritten before it is built (Track B).

### 1.5 `CustomOnchainWalletCallbacks.finishPsbt` → `signPsbt`

```swift
// Old                                   // New (0.26) — :855
func finishPsbt(psbtBase64: String) throws -> String
func signPsbt(psbtBase64: String) throws -> String
```

Doc (:841-854): sign and finalize **without** recording the transaction;
bark calls `registerTx` after broadcast; rejected unless the unsigned tx is
unchanged. The only signature change on the protocol between the tags.

**Repo impact: none.** No conformer; all four `WalletOpenArgs` sites pass
`OnchainWallet.default` (`BarkWalletFFI+WalletCreation.swift:212/482`,
`openImportedWallet`, `BarkWalletFFI+WalletLifecycle.swift:204`).

## 2. Changed types

### 2.1 `ExitState` / `ExitStateKind` gained `vtxoSwept`

```swift
// ExitState (:9263) — new case :9307
case vtxoSwept(tipHeight: UInt32, spentInputs: [OutPoint])
// ExitStateKind (:9456) — new case :9465
case vtxoSwept
```

Changelog #2542: reported "when an exit ends because an output its chain
needed was spent on chain. It carries the exit transaction inputs that were
taken. `ExitError` gained a matching `VtxoSwept` variant, kept apart from
`VtxoAlreadySpent` because the cause differs." bark-rest adds: fee
estimation "returns a distinct error for such a VTXO rather than reporting
it as already spent, and suggests attempting a refresh."

**Repo impact: two compile errors, one design decision.**

| Site | Switches on | Change |
|---|---|---|
| `ExitVtxo+Extensions.swift:20` `stateDisplayName` | `Bark.ExitState` | **error** — add `.vtxoSwept` to the `.vtxoAlreadySpent, .canceled` arm |
| `ExitVtxo+Extensions.swift:84` `isCancelled` | `Bark.ExitState` (`if case`) | not an error, **must** include `.vtxoSwept` or swept exits read as in flight forever (`isInFlight`) |
| `ParsedExitState+Bark.swift:27` `ParsedExitState(from:)` | `Bark.ExitState` | **error** — Track A maps to `.vtxoAlreadySpent(.init(tipHeight:))` (lossy); Track B adds a domain case |
| `ParsedExitState+Bark.swift:~110` `Bark.ExitState(from:)` reverse | `ParsedExitState` | no change in Track A |
| `ExitStatusParser.swift:542`, `ExitProgress.swift:109`, `ExitTransactionStatus+Parsing.swift:84`, `ExitProgressionService+LiveActivity.swift:238/391`, `ExitStatusDetailView_iOS.swift:783/879` | `ParsedExitState` | no change in Track A; all gain a case in Track B |
| `ExitStatusParser.swift:172` legacy Debug-string parser | strings | no change (pre-0.16 snapshots only); Track B adds `VtxoSwept(…)` parsing if the enum gains the case |
| `ExitStateKind` | — | zero references in the repo |

### 2.2 Records with new fields (memberwise inits changed)

| Record | Line | New fields |
|---|---|---|
| `Balance` | :5134 | `needsRefreshSats` (:5144), `pendingArkoorSendSats` (:5153), `pendingOffboardSats` (:5158) |
| `ExitClaimTransaction` | :6604 | `vtxoIds: [String]` (:6611), `skippedVtxoIds: [String]` (:6616) |
| `ExitTransactionStatus` | :6812 | `transactions: [ExitTransactionPackage]` (:6824) |
| `LightningSend` | :7546 | `paymentHash: String` (:7552), `movementId: UInt32?` (:7557) |
| `OffboardResult` | :7916 | `movementId: UInt32` (:7924) |
| `PendingBoard` | :8186 | `movementId: UInt32` (:8193) |

`Balance.spendableSats` doc (:5141-5143): "Sats that can be spent right now.
Excludes `needs_refresh_sats`." `needsRefreshSats` (:5145-5149): "Sats in
VTXOs that have expired or reached the server's maximum exit depth. They
can still be offboarded, exited or refreshed, but not sent out-of-round
until maintenance has refreshed them."

New types: `BalanceSummary` (:5253), `ExitTransactionPackage` (:6748),
`ExitChildTransaction` (:6511, carries `origin: ExitTxOrigin`,
`feeRateSatPerKwu`, `totalFeeSats`), `PaymentMethod` (:10153),
`PaymentMethodParsingError` (:10319), `PaymentResult` (:10434),
`PaymentRequest` (:8104), `AvailablePaymentMethod` (:5062), `Bip321Uri`
(:5346), `Bip321UriOptions` (:5435), `Bolt11InvoiceDetails` (:5758),
`DatadirInfo` (:6094), `DebugInfo` (:6173).

**Repo impact:** the `Balance` fields are read in one place
(`BarkWalletFFI+Balance.swift:52`, mapping into `ArkBalanceResponse`) and
dropped — see §3.1. The other five records are **constructed** in the
sites listed in §4.

## 3. Behaviour changes on unchanged signatures (read from bark source)

### 3.1 Balance overhaul (changelog #2509) — **verified at both tags**

bark 0.7.1 `Wallet::balance` (`bark/src/lib.rs:1580`): `spendable` = sum of
every VTXO passing `VtxoStateKind::Spendable`, no expiry check. bark 0.8.0
(`bark/src/balance.rs:160-167`): a VTXO with `needs_refresh(tip,
max_exit_depth)` — `expiry_height <= tip || exit_depth >= max` — goes to
`needs_refresh` instead. `Balance::total = spendable + needs_refresh +
pending()`, `pending()` sums the seven pending fields including the two new
ones. Also: `pending_in_round` now counts the *locked inputs* of a round
rather than the requested outputs; `claimable_lightning_receive` counts
only after the preimage is revealed; `pending_exit` is always present (was
`Option`, the Swift type was already `UInt64`).

**Repo impact:** `ArkBalanceResponse.totalSat` / `totalPendingSat`
(`Shared/Models/ArkBalanceResponse.swift`) and the duplicated pair on the
SwiftData model `ArkBalanceModel` (`Shared/Models/ArkBalanceModel.swift`,
CloudKit-mirrored singleton, defaults on every stored property) sum five
fields. A pre-existing gap surfaced by the review: bark's
`claimableLightningReceiveSats` (in `Balance` since 0.7.1) is mapped
nowhere, so the app total was already short by it; with the three new
fields the mapping would still be one short. Phase 2 maps four fields.
Consumers of the total: `TotalBalanceModel` (`grandTotalSat`, the Ark
share), `BalanceView_iOS` via `BalanceDetailCard` (spendable, pending and
total rendered separately plus the breakdown rows — so `spendable +
pending` must still equal `total` after the change), `ArkBalanceView`, and
`DeleteWalletSettingView.syncedForfeitSummary` (`totalSat - pendingExitSat`
on read-only secondaries). Consumers of `spendableSat` (send caps,
`PaymentDestinationSelector`, `BalanceService`, `WalletManager`) are
**correct as is** — they want what can be sent. Constructors of
`ArkBalanceResponse`: `BarkWalletFFI+Balance` (preview and live),
`MockBarkWallet`, `WalletManager+Export` (built from the `ArkBalanceModel`,
not the FFI). Constructors of `ArkBalanceModel`: `BalanceService` (two),
`ReadOnlyBalanceService`, `TotalBalanceModel`, and **five in
`Tests/Shared/ReadOnlySyncedDataTests.swift`** (memberwise, two with
`lastUpdated:`). No site decodes `ArkBalanceResponse` from stored JSON (it
is only encoded into the export), so the new keys need no decoding
defaults.

### 3.2 `getExitStatus` — **not a change**; `getExitVtxos` doc now explicit

bark 0.7.1 `get_exit_status` (`bark/src/exit/mod.rs`) already read
`persister.get_exit_vtxo_entry` and was documented "live or finished, if
any"; 0.8.0 is byte-identical there. New Swift docs: `getExitStatus`
(:2248-2251) "Status of one exit, live or finished. `None` if no exit was
ever started for the VTXO"; `getExitVtxos` (:2254-2257) "**Live exits
only.** Finished exits leave this list; see `list_finished_exits` and
`get_exit_status`"; `listFinishedExits` (:2325-2330) "…They stay queryable
after completion, so a client need not snapshot them at drain time."
Playbook B2 holds. `cancel_exit` at both tags: "the canceled row remains on
disk for auditing" — answers the open question under the `cancelExit`
backlog item.

### 3.3 `drainExits` now reports what it claimed

`ExitClaimTransaction.vtxoIds` / `skippedVtxoIds` — our feedback ask 19
from the 0.25 bump, answered. `ExitClaimSequence.run`
(`ExitProgressionLogic.swift:178-199`) still links the *requested* ids via
`effects.recordClaim(txid, claimTx.feeSats, claimableVtxoIds)`. Track B
switches it to `claimTx.vtxoIds` and logs `skippedVtxoIds`; the
`drainAll` rule from 0.25 is unchanged.

### 3.4 Swift-side logger redaction (bindings `01db51c`) — **verified**

`OSBarkLogger` now interpolates with `privacy: .private` unless constructed
with `redactMessages: false`; `barkAttachOSLogger(subsystem:maxLevel:redactMessages:)`
(`LoggerExtension.swift:70-74`) forwards it. Rust side: `setLogger` doc
(:12270-12278) "Calling this again replaces the current logger and level …
`clear_logger` turns logging off"; new `clearLogger()` (:12265). The app's
only call: `BarkWalletFFI.swift:67` `try barkAttachOSLogger(maxLevel: .debug)`
— no guard, nothing to simplify; **must pass `redactMessages: false`**
(DECIDED 2026-10-25) or device exports and sysdiagnose lose every bark line.

### 3.5 Recovery (changelog #2536, #2609, #2618, plus the 0.7.1-dated reader fixes)

`recover_from_seed` (`bark/src/recovery.rs:731-805`): xpub lookup first
(`recover_from_xpub`, falls through on `Unimplemented`), then the regular
mailbox, then the recovery mailbox, each from checkpoint 0; every VTXO not
settled by the lookup is resolved against the server (spent → stored spent,
no validation; spendable → validated and checked for an emergency exit);
three retry passes over `failed`; `sync_pending_rounds` claims recovered
delegated-round outputs. Two error-path nuances (verified): only
`tonic::Code::Unimplemented` from the xpub RPC is tolerated (`Ok(false)`,
logged "Server doesn't support VTXO recovery by xpub"); any other xpub
error is deferred and re-raised by `xpub_result?` at the end, so the whole
`recover_from_seed` returns `Err` even after both mailboxes recovered
everything. And the two mailbox scans use `?`, so a regular-mailbox failure
aborts before the recovery mailbox is read. In Arké an `Err` surfaces as
`recoveryReport() == nil` → `ImportRecoveryLogic` wipe-and-reopen retries →
`acceptWithoutRecovery` ("Recovery scan never completed"). `RecoveryReport`,
`RecoveryBucket`, `recoverVtxos(vtxoIds:gapLimit:)` (:2449),
`recoveryReport()` (:2456) and `recoveryStatus()` (:2469) are
**unchanged**, so `ImportRecoveryLogic` and `retryRecoveries` compile and
keep their meaning.

### 3.6 Rounds (changelog #2443) — **derived from the changelog, not traced**

Registration no longer locks inputs; a participation awaiting its round
"shrinks to the ones it still has, or is canceled when too little remains";
a delegated one that lost inputs "is resubmitted with the rest". The
changelog names a `sync_awaiting_round_participations` pass; that symbol
does not exist at the tag. The code is `try_shrink_participation`,
`adopt_participation` and `recover_delegated_participation` in
`bark/src/round/mod.rs`, driven from `sync_pending_rounds` (which
`Wallet::sync` joins) and from `handle_round_participation_completed` in
`bark/src/mailbox.rs`. Candidate explanation for a refresh that never
finishes: `sync_pending_rounds` does talk to the server about *recorded*
participations, so a wallet whose stuck state is a stored participation
may settle there without a re-import; a wallet that simply missed the
forfeit message (the users' case) cannot. Affects the premises of `Refresh_Deduplication.md` Guard C
(`pendingRoundInputVtxos()` is "empty for delegated refreshes until the
server issues the round" — now also true for interactive ones until an
attempt starts). Swift `RoundState` is unchanged (diffed).

## 4. Verified error list (per-file diagnostics, 2026-10-25)

| File | Line(s) | Error |
|---|---|---|
| `Shared/Views/Activity/ExitVtxo+Extensions.swift` | 20 | switch must be exhaustive |
| `Shared/Data/ExitStatus/ParsedExitState+Bark.swift` | 27 | switch must be exhaustive |
| `Shared/Data/BarkWalletFFI/BarkWalletFFI+Transactions.swift` | 275, 279 (+ warning 226) | `OffboardResult` interpolated / returned as `String` |
| `Shared/Data/BarkWalletFFI/BarkWalletFFI+Lightning.swift` | 24, 280, 325, 375 | `LightningSend` missing `paymentHash`, `movementId` |
| `Shared/Data/BarkWalletFFI/BarkWalletFFI+Exit.swift` | 352 | `ExitClaimTransaction` missing `vtxoIds`, `skippedVtxoIds` |
| `Shared/Data/MockBarkWallet.swift` | 325, 643, 660, 677 / 527 | `LightningSend` ×4 / `ExitClaimTransaction` |
| `Shared/Models/PersistentExitCache.swift` | 95 | `ExitTransactionStatus` missing `transactions` |
| `Tests/Shared/ExitProgressTests.swift` | 50 / 496 | `ExitTransactionStatus` / `ExitClaimTransaction` |
| `Tests/Shared/ExitStateMappingTests.swift` | 136 | `ExitTransactionStatus` |
| `Tests/Shared/ExitBlockedInfoTests.swift` | 196, 266 | `ExitTransactionStatus` |
| `Tests/Shared/ExitFeeAttributionTests.swift` | 76 | `ExitTransactionStatus` |
| `Tests/Shared/ExitStatusParserTests.swift` | 289 | `ExitTransactionStatus` |

21 errors, 11 files. Nothing in ArkéUI, ArkeWidgets or ArkeDesktop
references a changed type (grep); desktop stays unbuilt (parked).

## 5. New API (none adopted in Track A)

Wallet: `balanceSummary()` (:2133), `bip321Uri(options:)` (:2140),
`debugInfo()` (:2197), `estimatePaymentFee(method:amountSats:)` (:2240),
`listAllExits` / `listFinishedExits` / `listLiveExits(includeHistory:includeTransactions:)`
(:2322/2331/2336), `parsePaymentRequest(payment:)` (:2390),
`sendPayment(method:amountSats:comment:wait:retryForSecs:)` (:2517).
Global: `walletExists(datadir:)` (:12252 — read-only, "a corrupt wallet is
never mistaken for an absent one", throws on an unreadable database),
`readDatadirInfo(datadir:)` (:12235), `decodeBolt11Invoice(invoice:)`
(:12144), `clearLogger()` (:12265).

## 6. Verified non-changes

UniFFI contract 30 (:12315). `Error` enum cases, `Config`, `WalletOpenArgs`,
`ArkInfo`, `RoundState`, `MovementStatus`, `MovementKind`, `Notification`,
`RecoveryReport`, `RecoveryBucket`: identical between the checkouts
(diffed). No method was removed. `Package.resolved` resolves `master` @
`ada76c3` (uncommitted).

## 7. Migration checklist (Track A)

- [ ] Phase 1: the 21 compile fixes + `isCancelled` includes `.vtxoSwept`
      (`02-migration-plan.md` §1)
- [ ] Phase 2: balance fields on `ArkBalanceResponse` and `ArkBalanceModel`,
      totals include `needsRefreshSat` and the two new pending buckets,
      breakdown rows, log line (§2)
- [ ] Phase 3: `barkAttachOSLogger(maxLevel: .debug, redactMessages: false)` (§3)
- [ ] Tests: `ExitStateMappingTests` swept→already-spent pin;
      `ArkBalanceTotalsTests` (new); scoped runs, full mobile suite once
      after the adversarial pass
- [ ] Adversarial pass (`fault-class-reviewer`, FFI boundary + balance +
      exits), findings fixed or filed
- [ ] Device: the three scenarios (§Device checklist)
- [ ] Chores: unadopted-API doc baseline → v0.26.0; feedback doc asks
      3/6/8/11/12/17/19; backlog (Current train, Tier 4 "Next bump", Tier 0
      cluster notes, Track B entries); `Docs/README.md` Migrations line
- [ ] `04-completion-report.md`
