# Exit Cost Estimate via `estimateEmergencyExitFee`

**Status:** DECIDED 2026-10-19 (Train 2, Tier 1 Exits; Christoph: "do it"),
not built. Premises rewritten for bark 0.8.0 / bindings v0.26.0 on 2026-10-25;
the 0.7.1 description is kept below for the record. Error rule DECIDED
2026-10-19: a thrown estimate never blocks the exit. When the build starts,
this doc takes the labelled claims, the sibling sweep and the review record.

Moved verbatim from `Open_Follow_Ups.md` on 2026-11-10 (backlog hygiene pass, relocation only; the open entry is now a stub pointing here).

## 1. The backlog entry as ruled

- [ ] **Replace the hand-rolled exit cost estimate with
  `estimateEmergencyExitFee`** (DECIDED 2026-10-19 as a Train 2 Tier 1
  item, Christoph: "do it"; supersedes the Tier 3 "exit pre-flight" line,
  which was an addition — this is a replacement). **Premises changed at
  bark 0.8.0 (bindings v0.26.0, 2026-10-25): `fundable` is deprecated and
  no longer computed from confirmed coins, the estimate never syncs or reads
  the onchain wallet, `exitBroadcastFeeSats` already includes a `feeMargin`
  (default 1.2). Rewrite the build steps below per
  `Migrations/Bark-0.25.0-to-0.26.0/01-api-changes.md` §1.4 before
  building: compare `exitBroadcastFeeSats` against the confirmed onchain
  balance in the app; the "unconfirmed funds pass our check" argument is
  moot.** The 0.7.1 description follows for the record. Today
  `ExitView_iOS.calculateExitCost` (`:285-358`) prices a forced move
  itself: no tree-tx deduplication, guessed depth 1–3, a 1.5–2.0× CPFP
  multiplier, a 10–15 % margin, three scenarios rendered as a range by
  `ExitCostEstimateCard`, and `canAfford` checked against
  `manager.onchainBalance?.totalSat` (`:115-116`). Bark's estimator at
  `bark-0.7.1` (`bark/src/exit/estimate.rs`, read at the tag 2026-10-19)
  resolves each VTXO's real exit chain, skips confirmed txs, dedupes shared
  txids, prices in-mempool packages as RBF replacements, simulates the
  serial CPFP walk against **confirmed** coins to produce `fundable`, and
  signs a real claim tx for its weight; it returns
  `exitBroadcastFeeSats` / `claimFeeSats` / `txsToBroadcast` separately.
  So this is a correctness fix as well: unconfirmed onchain funds pass our
  check and stall bark's walk. Build: (1) protocol method + `MockBarkWallet`
  stub (`estimateEmergencyExitFee(vtxoIds:feeRateSatPerVb:destination:)`,
  on `WalletProtocol` at v0.25.0, `Bark.swift:2183`); (2) map
  `EmergencyExitFeeEstimate` into the ArkéUI model — show the two legs as
  bark splits them (broadcast paid now from Savings, claim deducted later
  from the recovered amount), `fundable` replaces `canAfford`, the
  low/mid/high scenarios and min/max transaction counts go; (3) same
  fee-rate rule as `ExitProgressionService.exitFeeRateOverride`: nil on
  mainnet, capped fast rate off mainnet (with an explicit rate bark prices
  both legs at it, matching today's approximation); (4) delete the
  weight-formula comment block at the top of `ExitView_iOS.swift`.
  **Error rule DECIDED 2026-10-19:** when the estimate throws (unknown /
  already-exited / spent / non-standard VTXO, or an FFI error) the exit is
  **not** blocked — a forced move is a recovery action; show "cost could
  not be estimated" and keep Start enabled with the warning. Today the
  estimate never fails, so this is new behaviour. Preconditions verified:
  the app passes bark's BDK-backed `OnchainWallet.default` at `Wallet.open`
  (`BarkWalletFFI+WalletLifecycle.swift:262`), which the binding requires
  (callback-backed wallets error). Caveats: slow — the binding doc says it
  syncs the onchain wallet first (doc claim, not traced in the Rust);
  latency on device not measured. Review: adversarial pass (exit money
  path), then a signet forced move on device with one unconfirmed onchain
  input to see `fundable == false` behave. Sibling sites that keep their
  own rate logic and are *not* touched: `ExitProgressionService:170-173`,
  `UnilateralExitListView_iOS:239`.
