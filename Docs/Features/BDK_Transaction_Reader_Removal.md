# BDK Transaction Reader Removal

**Status:** Phase 2 DONE (2026-08-13) — the shadow BDK wallet is no longer
created at startup (no more full scans on create/import/open); it survives
only as the lazily-created `BDKFeeEstimator` for send-flow fee estimation.
Phase 1 done + verified on-device the same day. Next: Phase 3, blocked on
the upstream estimate/drain ask (§3.4 / feedback §2.5b).
**Created:** 2026-08-12
**Trigger:** bark FFI bindings added `transactions()` to `OnchainWalletProtocol`
(plus `tipHeight()` and `utxos()`), answering feedback item §2.5 in
`Bark_Bindings_Feedback.md`.

## 1. Background

`Shared/Data/BDKTransactionReader.swift` is a second, read-only BDK wallet we
run in parallel to bark's built-in `OnchainWallet`, on the same descriptors,
because the FFI historically exposed no onchain transaction history. It costs:

- A duplicate wallet database (`bdk_transactions.db` in the BDK data dir).
- A background **full scan** on every wallet create, import, and open
  (`BarkWalletFFI+WalletCreation.swift:218,499`,
  `BarkWalletFFI+WalletLifecycle.swift:318`).
- Duplicate Esplora sync traffic on every history fetch and every fee
  estimate (`txReader.sync()` before each use).
- The entire `bdk-swift` package dependency — `BDKTransactionReader.swift` is
  the only file importing `BitcoinDevKit`.
- A standing descriptor-drift / coin-selection-drift risk against bark's
  internal BDK wallet.

### Current consumers

| Consumer | What it uses |
|---|---|
| `BarkWalletFFI.getOnchainTransactions()` (`BarkWalletFFI+Transactions.swift:19`) | `sync()` + `getTransactionDetails()` → `OnchainTransactionModel` |
| `WalletManager.estimateOnchainFeeWithBDK` (`WalletManager+Fees.swift:118`) | `sync()` + `estimateFee()` (BDK `TxBuilder`) |
| `WalletManager.calculateOnchainMaxSendable` (`WalletManager+Fees.swift:150`) | `sync()` + `calculateMaxSendable()` (BDK drain builder) |
| Startup diagnostics (`BarkWalletFFI+WalletLifecycle.swift:224`, commented out) | `getFirstNAddresses()` |

Downstream of `getOnchainTransactions()`: `OnchainTransactionService`
(30 s cache + SwiftData upsert into `OnchainTransactionEntity`),
`UnifiedTransactionService` / `TransactionModel+OnchainAdapter` (conversion to
`TransactionModel` + `PersistentTransaction`), `TransactionLinkingService`
(movement↔onchain links). The fee-estimation paths feed
`SendViewModel+FeeEstimation` and `SendViewModel+MaxSendable`.

## 2. What the new FFI provides

```swift
// OnchainWalletProtocol (bark 0.16 bindings)
func transactions() async throws -> [WalletTransaction]  // requires prior sync()
func tipHeight() async throws -> UInt32
func utxos() async throws -> [OnchainUtxo]

struct WalletTransaction {
    var txid: String
    var txHex: String              // raw tx, consensus-serialized
    var onchainFeeSats: UInt64?    // nil for inbound / foreign-funded txs
    var balanceChangeSats: Int64   // net: received − sent over wallet outputs
    var confirmation: BlockRef?    // nil = mempool
    var isCpfp: Bool               // spends a P2A fee anchor (exit fee child)
}

struct BlockRef { var height: UInt32; var hash: String }   // ⚠️ no timestamp
```

The app already syncs the built-in onchain wallet
(`BarkWalletFFI+Server.swift:138`), so `transactions()` is meaningful after
our normal sync flow.

## 3. Gap analysis

### 3.1 Block timestamp (history — solvable app-side)

`BlockRef` carries height + hash only. We use `confirmationTime.timestamp` as
the transaction **date** everywhere (adapters:
`date: onchain.timestamp ?? Date()`, sorting in `getOnchainTransactions`,
persistence in `OnchainTransactionEntity.confirmationTimestamp`).

**Plan:** resolve timestamps app-side, cheaply:

1. On mapping, if the txid already exists in `OnchainTransactionEntity` with a
   `confirmationTimestamp`, reuse it (block timestamps are immutable; the
   hash from `BlockRef` guards against reorgs — refetch only if hash changed).
2. For new confirmations, fetch `GET {esplora}/block/{hash}` once per unique
   block hash and read its `timestamp` field. Same Esplora base URL the app
   already uses (`FeeRateService` is the existing HTTP-to-Esplora pattern).
   Cache in-memory per session; the entity upsert persists it after that.
3. Fallback when the fetch fails: keep the transaction with a nil timestamp —
   the existing `?? Date()` fallback and height-based sorting still work, and
   the next refresh retries.

**Upstream ask (parallel):** add block time to `BlockRef` (or a `blockTime`
field on `WalletTransaction`). bark's internal BDK wallet has this data.
Extends §2.5 in `Bark_Bindings_Feedback.md`.

### 3.2 Gross sent/received (history — derivable)

`WalletTransaction` gives only the net `balanceChangeSats`; our model persists
gross `sent`/`received`. Actual downstream needs:

- **Display amounts** (`netAmount`, `isIncoming`, `displayAmount`) — pure net,
  no gap.
- **Self-transfer display amount** (`UnifiedTransactionService.swift:237,305`):
  shows `received` for self-transfers. For a self-transfer *all* outputs are
  ours by definition, so `received == sum(tx outputs)` — decodable from
  `txHex`.
- **Exit fee attribution guard**
  (`PersistentTransaction.userPaidOnchainFeeSat`, line 164): demotes fee when
  `onchainSent == 0` (wallet didn't fund the tx, e.g. a third party's CPFP on
  our anchor). Maps cleanly: bark sets `onchainFeeSats = nil` exactly when the
  wallet didn't index the funding prevouts, so `fee != nil ⇔ wallet-funded`.
  The `fee > 0` guard already excludes the nil case.
- **Exit claim fallback fee** (`ExitStatusDetailView_iOS.swift:209`):
  `exitVtxo.amountSats − received` for inbound claim txs. Inbound means
  `sent == 0`, so `received == balanceChangeSats`. No gap.

**Derivation rules for the mapper.** Phase 0 (2026-08-12) disproved the draft
rule "`fee != nil` ⇔ wallet-funded": bark reports fees for **pure receives
too** (e.g. +50 000 with fee 165), because `bdk_esplora` fetches previous
txouts during sync, making `calculate_fee` succeed for any indexed tx.
Classify by **net sign** instead:

| Case | Condition | sent | received | model fee |
|---|---|---|---|---|
| Inbound | `net > 0` | `0` | `net` | `nil` (preserve current semantics: the reader never computed fees for receives; don't start showing them) |
| Wallet-funded | `net < 0` | `sumOutputs(txHex) + fee` | `sent + net` | `onchainFeeSats` |
| Wallet-funded, fee nil (rare: fresh CPFP pre-sync) | `net < 0`, `fee == nil` | `-net` | `0` | `nil` (self-heals next sync) |

The wallet-funded derivation assumes all *value-bearing* inputs are ours —
P2A anchors are 0-value, so a CPFP child's foreign anchor input doesn't skew
it. Verified against all five Phase 0 txs, including both CPFP children
(e.g. send: outputs 193 041 + fee 601 → sent 193 642, received 143 041 —
exact match with the reader).

`sumOutputs(txHex)` needs a tiny raw-tx output parser (version/marker/varint
inputs skip/varint outputs → sum the 8-byte values). ~50 lines, fully
unit-testable, and it removes the need for BDK's `Transaction` type. Place it
`nonisolated` in Shared (parsing-layer convention from the 0.16 migration).

### 3.3 `isSelfTransfer` (history — derivable)

Reader currently computes it via `isMine` over all outputs; the motivating
case was exit intermediary/fee txs. Mapping:

`isSelfTransfer = isCpfp || (fee != nil && balanceChangeSats == -Int64(fee))`

(all non-fee value stayed in the wallet ⇒ every output is ours). The
self-transfers this flag actually marks in practice are the exit CPFP fee
children — see §3.5 for the full exit-package analysis, which is where the
real behavior deltas live.

### 3.5 Exit package interweaving (verified against bark 0.6.1 source)

Verified in the pinned FFI + bark sources
(`bark-ffi` tag `v0.21.0+bark-0.6.1.uniffi-0.31.1` → `bark` rev `bark-0.6.1`;
fetched into `~/workspace/bark{,-ffi}`, read via `git show` at the tag — the
working copies there are stale):

- `transactions()` = `bark::onchain::OnchainWallet::list_transaction_infos()`,
  which iterates the wallet's **BDK canonical tx graph** — the same graph
  bark's own operations write into. Board/send txs are applied at signing
  time (`finish_psbt` → `apply_unconfirmed_txs`), and our **exit CPFP fee
  children are applied the moment bark creates them**
  (`store_signed_p2a_cpfp`, called from `Exit::progress_exits_with_cpfp`).
- `is_cpfp` = any input with empty witness *and* empty scriptSig (a BIP-431
  P2A anchor spend carries no signature).
- The **exit package txs themselves** (the chain spending VTXO prevouts,
  paying to exit scripts) are in **neither** wallet's list: they touch no
  wallet SPK, and nothing calls `register_tx` in bark 0.6.1. They are tracked
  exclusively by the exit subsystem (`getExitStatus` / `ExitTransactionStatus`
  / our `PersistentExitCache`). My earlier draft's claim that they'd "flip to
  inbound" was wrong — they never appeared in either pipeline.

Per-transaction-class visibility:

| Tx class | Shadow BDK reader (SPK scan) | bark `transactions()` |
|---|---|---|
| Board funding, plain send/receive | seen | seen (applied at signing + scan) |
| Exit package txs (VTXO → exit scripts) | not seen | not seen (exit subsystem only) |
| Our exit CPFP child | seen once Esplora indexes it; fee via manual `sent−received` fallback (**underestimates by the anchor value**) | seen **immediately** (pre-propagation), `isCpfp = true`, but `onchainFeeSats` almost certainly **nil** — the anchor prevout is fed to the tx builder as a foreign utxo (`add_fee_anchor_spend`), never inserted into the graph, so `calculate_fee` can't resolve it |
| Third-party CPFP on our anchor | not seen | not seen (enters our data only via exit status, filtered by `extractUserFundedTransactionIds` origin check) |
| Claim/drain tx (exit output → our address) | seen as inbound, fee nil | seen as inbound via scan, fee nil |

Two consequences for the migration:

1. **Hard integration point:** `TransactionLinkingService.relinkExitMovements`
   resolves exit movements to `onchain_<txid>` records whose txids come from
   `ExitStatusParser.extractUserFundedTransactionIds`. Those links only work
   for txids that exist in the onchain pipeline's output — i.e. CPFP children
   and claim txs. Bark's list contains both (CPFP children even earlier than
   the reader saw them), so linking should get *better*, but the A/B
   diagnostic (Phase 0) must confirm txid-set equality before we swap.
2. **CPFP child fee regression risk — DISPROVEN by Phase 0** (2026-08-12):
   bark reported exact fees (3 193 / 3 165 sats) for both CPFP children,
   identical to the reader's — `bdk_esplora` fetches previous txouts during
   sync, so `calculate_fee` resolves even the foreign anchor prevout (and
   the reader, it turns out, was also using real `calculateFee`, not its
   manual fallback). Residual window: a CPFP child applied at creation on
   *this* device (`store_signed_p2a_cpfp`) may report `fee = nil` until the
   next chain sync fetches its prevouts — transient, self-healing, handled
   by the fee-nil derivation row in §3.2. No upstream ask needed.

### 3.4 Fee estimation & max sendable (NOT covered — blocks full removal)

`OnchainWalletProtocol` has no estimate/prepare/drain function. The
lookalikes don't help:

- `Wallet.estimateSendOnchainFee` estimates the **ark offboard** (round send),
  already wrapped as our `estimateSendToOnchainFee`.
- `prepareTx` / `prepareDrainTx` exist only on
  `CustomOnchainWalletCallbacks` — the interface *foreign implementations
  provide*, not callable on the default BDK-backed wallet.

So `SendViewModel`'s direct-onchain fee preview and send-max still need the
shadow BDK wallet until upstream adds an API. Note the shadow estimate is
already approximate today: its coin selection isn't guaranteed to match what
bark's internal wallet picks when `send()` actually runs — send-max especially
rides on that. An upstream estimate is the only exact answer.

**Upstream ask:** `OnchainWallet.estimateSend(address, amountSats, feeRate)
-> FeeEstimate`-style call plus a drain variant (or
`prepareTx`/`prepareDrainTx` promoted onto `OnchainWalletProtocol` returning a
PSBT/fee without broadcasting). Add as a new item in
`Bark_Bindings_Feedback.md`.

**Fallback if upstream stalls:** local estimator over `utxos()` with
deterministic P2TR vsize math (single-descriptor BIP86 wallet: keyspend input
≈ 57.5 vB, P2TR output 43 vB, ~10.5 vB overhead) and branch-and-bound-ish
largest-first selection. No worse in principle than the shadow wallet's
selection mismatch, and it drops the dependency — but it's new consensus-ish
math to own. Decide only if the upstream ask is rejected.

## 4. Phased plan

### Phase 0 — A/B diagnostic (run 2026-08-12: PASSED)

DEBUG-only comparison in `BarkWalletFFI.getOnchainTransactions()`: after the
BDK reader produces its models, sync bark's onchain wallet, fetch
`transactions()`, and log txid-set differences plus a per-tx field comparison
(tag `🆚 [TxCompare]`). Run on an imported signet wallet with two receives,
two exit CPFP children, one send, and a completed (pre-import) exit. Results
(`debug_logs.txt`, 2026-08-12):

- [x] txid sets match: 5/5 identical. Caveat: bark's *first* post-import sync
      returned 4/5 — revealed-SPK sync walks the address chain incrementally,
      so the second CPFP child (whose funding input was the first child's
      change) appeared on the second sync. Converges; the reader's full scan
      gets there in one pass. Post-import history may briefly be one sync
      behind.
- [x] User-funded txids with `onchain_` records all present in bark's list
      (the CPFP children). The claim tx and exit package txs have no record
      in *either* pipeline — see §5 notes.
- [x] `onchainFeeSats` is **not** nil for CPFP children — exact fees, equal
      to the reader's (§3.5 point 2 disproven). Bark even reports fees for
      pure receives (§3.2 rule reworked accordingly).
- [x] `balanceChangeSats == received − sent` on every tx (`net ✓` × 5).
- [x] Confirmation heights identical on every tx.

Verdict: bark's list is a drop-in equal (or better — CPFP children can appear
pre-propagation on the exiting device) source for Phase 1.

### Phase 1 — migrate history to `transactions()`

Internal swap; `BarkWalletProtocol.getOnchainTransactions()` signature,
`OnchainTransactionModel`, `OnchainTransactionEntity`, and everything
downstream stay untouched (no SwiftData migration).

1. New `nonisolated` mapper in Shared (suggested:
   `Shared/Data/OnchainTransactionMapper.swift`):
   `[WalletTransaction] + tipHeight + timestampResolver → [OnchainTransactionModel]`,
   including the raw-tx output-sum parser and the §3.2/§3.3 derivations.
2. Timestamp resolution per §3.1 (entity reuse → Esplora block fetch → nil).
3. Rewrite `getOnchainTransactions()` to `onchainWallet.sync()` +
   `transactions()` + mapper. Keep the existing sort (unconfirmed first, then
   newest); use confirmation height as tiebreaker when timestamps are nil.
4. Unit tests for the mapper: output-sum parser against fixture hexes,
   self-transfer derivation (incl. `isCpfp`), sent/received reconstruction,
   inbound/outbound/fee-nil cases, timestamp merge preferring persisted
   values.
5. On-device A/B on the signet wallet (it has exits, claims, self-transfers):
   log both pipelines' outputs side by side before deleting the old path.

### Phase 2 — shrink the reader to a lazy fee-estimation helper (DONE 2026-08-13)

1. ✅ `BDKTransactionReader` creation removed from all three lifecycle sites
   (create / import / open) along with the three background
   `sync(fullScan: true)` tasks — the startup/battery win.
2. ✅ Renamed to `BDKFeeEstimator` (file + class), shrunk to init + sync +
   `estimateFee` + `calculateMaxSendable`; diagnostics and history methods
   deleted. Header documents why it still exists (no upstream estimate API).
3. ✅ Created lazily via `BarkWalletFFI.ensureFeeEstimator()` (in +Fees) on
   the first `WalletManager+Fees` call, from `cachedMnemonic`. A fresh
   database triggers a one-time full scan (`createdFreshDatabase` flag);
   afterwards the persisted `bdk_transactions.db` allows the incremental
   per-call sync those paths already do. Cleared on wallet shutdown.

### Phase 3 — full removal (blocked on upstream)

Precondition: onchain estimate/drain API lands in the bindings (§3.4), or we
accept the local-estimator fallback.

1. Rewire `WalletManager+Fees` to the new FFI call; delete the reader file.
2. Drop the `bdk-swift` package from the project.
3. One-time cleanup: delete `bdk_transactions.db{,-journal,-wal,-shm}` from
   the BDK data dir on first launch after the change.
4. Mark §2.5 resolved in `Bark_Bindings_Feedback.md`.

### Bookkeeping (with Phase 1)

- Update `Bark_Bindings_Feedback.md`: note under §2.5 that `transactions()`
  shipped and what remains (block time on `BlockRef`); add the new asks —
  onchain estimate/drain (§3.4), history pagination (§6). (The CPFP-fee ask
  was dropped after Phase 0 disproved the risk.)
- Track phases in `Open_Follow_Ups.md` (entry added 2026-08-12).

## 6. Related observation: no pagination on history APIs

Neither `Wallet.history()` (movements) nor `OnchainWallet.transactions()`
takes a limit/cursor — every call serializes the full history across the FFI
(`historyByPaymentMethod` filters, but doesn't paginate). Assessment:

- **Not the near-term bottleneck.** At mobile-wallet scale (hundreds to a few
  thousand entries) a full-vec FFI round trip is milliseconds. BDK itself has
  no paginated tx listing, so `transactions()` inherits that shape.
  `WalletTransaction.txHex` makes it the heavier of the two — a full raw tx
  per entry — which is fine at our counts but the first thing to hurt.
- **Our own pipeline amplifies it more than the FFI does.** Every refresh:
  `getMovements()` re-serializes all movements to pretty-printed JSON and
  re-parses; `OnchainTransactionService.persistTransactions` runs one
  `FetchDescriptor` per tx for upsert; `UnifiedTransactionService` re-converts
  everything. All O(n) per refresh with large constants. If history growth
  ever becomes a problem, fixing our re-processing (delta detection by
  txid/movement-id set, batched upserts) buys more than FFI pagination would.
- **Upstream ask (low priority):** cursor- or since-based variants
  (`history(afterId:)`, `transactions(sinceHeight:)`) so long-lived wallets
  don't pay O(all-time) per sync — bark's movements live in SQLite, so a
  `LIMIT/OFFSET` variant is cheap to add. File alongside the other asks, not
  as a blocker.

## 5. Risks / open questions

- **CPFP child fee attribution**: resolved by Phase 0 — bark reports exact
  fees (§3.5 point 2). Only the transient fresh-creation fee-nil window
  remains, covered by the §3.2 derivation table.
- **Post-import first-sync lag — found on-device, FIXED 2026-08-13**: the
  first history fetch after a fresh seed import returned **0** transactions
  (its sync raced ahead of `AddressService.loadAddresses()` revealing index
  0 — revealed-SPK sync with nothing revealed scans nothing), and discovery
  then converged only over several sync rounds (one mid-walk sync briefly
  overcounted the balance: 289,848 = a change output not yet seen as
  spent). The reader's old background full scan masked this. Fix shipped:
  `WalletManager.refresh` awaits the address load before the parallel
  service group, and `getOnchainTransactions()` runs
  `OnchainHistorySyncer.syncUntilStable` (loop while the txid set changes,
  cap 5, seeded with the previous fetch's txids → steady state = one sync).
  Regardless: upsert only, never prune by absence (the pipeline already
  behaves this way). Follow-on fix (same day): the parallel balance read
  could capture the mid-walk overcount and keep it until a manual refresh —
  the refresh task group now re-reads the onchain balance right after the
  history fetch stabilizes (`refreshOnchainBalance()`, local-state read).
- **Pre-existing, surfaced by Phase 0, not migration blockers** (candidates
  for their own follow-ups):
  - The **claim tx** (`32a20c5d…`) is in *neither* pipeline, and its 8,839
    sats are missing from the balance — a real funds-visibility bug, network-
    verified 2026-08-13. The claim DID go to a wallet-owned address
    (`ExitProgressionLogic` drains to `getOnchainAddress()`), but this wallet
    was **seed-imported**: the original device's revealed-address index was
    lost, and the claim address sits more than the stop-gap (10) beyond the
    used-address band. The receive screen does NOT burn indices
    (`AddressService` reuses the unused address); the index consumers are
    (a) `ExitClaimSequence.run`, which reveals a fresh address as its first
    step on *every claim attempt* — including failed, auto-retried ones —
    bypassing `AddressService` tracking entirely, and (b) the app's
    20-unused-address cap, which exceeds the scan gap of 10.
    Neither the reader's gap-10 full scan nor bark's revealed-SPK sync
    reaches it. Both pipelines equally blind — not a migration issue, but
    tracked as its own bug in `Open_Follow_Ups.md`. Consequence here:
    `relinkExitMovements` logs "onchain_32a20c5d… not found" forever, and
    the wallet under-reports by the claim amount.
  - On an **imported** wallet, restored CPFP children come back with
    `origin: Block` (bark downloaded them from the chain), so
    `extractUserFundedTransactionIds` classifies them as third-party and
    never links them to the exit movement — even though this user funded
    them. Their fees still enter totals via their standalone onchain records
    (`userPaidOnchainFeeSat`: fee > 0, sent > 0), so totals are right; only
    the movement linkage is lost after restore.
- **Old persisted rows**: entities written by the BDK pipeline keep their
  gross sent/received; new upserts overwrite with derived values. Net-based
  display is unaffected; watch the `TransactionUpsertDateFreezeTests`
  contract when timestamps get re-resolved.
- **`sync()` cost**: `getOnchainTransactions()` will call
  `onchainWallet.sync()` per fetch (as it did `txReader.sync()`). If bark's
  sync is noticeably heavier, lean on `OnchainTransactionService`'s 30 s
  cache or skip the sync when one ran recently (Server.swift already syncs).
- **Esplora block fetch** adds one request per *new* confirmed block hash —
  bounded and cacheable, but it is a new failure surface for dates.
- **`txHex` size**: history responses now carry full raw txs across the FFI.
  Fine at our tx counts; noted in case a wallet has thousands of txs.
