# Mainnet Fee Rate: A Sanity Ceiling Instead of an Uncapped Path

**Status: BUILT and REVIEWED 2026-10-19 (Tier 0, Train 1, pulled forward
in the 2026-10-19 cut for the Lugano TestFlight). Adversarial pass §8: no
code defect, four findings, all acted on the same session. Scoped suite
17/17 and full mobile suite 565/565 on the iPhone 17 Pro simulator (§9).
Device step (§6) PASSED 2026-10-19 on the mainnet phone (Christoph; export
`Docs/debug_logs.txt`, §6.1). Rulings in §10 DECIDED the same day: ceiling alone for
Lugano, the send gate is a Train 2 Tier 1 item. Uncommitted; rides with
the 2026-10-19 backlog edits.**

Backlog entry: `Open_Follow_Ups.md`, Tier 0, "Mainnet fee rate can still
crash the app" (found in the 2026-10-08 audit, parser harness executed the
same day). Area docs: `../Send/Payment_Destination_Selector.md` for the
ranker, `Exit_Architecture.md` for the exit cost estimate, playbook fact B5
for the exit fee-rate rule.

## 1. Problem

`FeeRateService` turns an Esplora `/fee-estimates` response into three
`UInt64` tiers. Off mainnet the tiers are capped at 50 sat/vB (commit
`7e1cc97`, 2026-07-20, for signet fee spam). On mainnet the cap closure
returned nil, documented as "Mainnet is NEVER capped — a real fee spike
there is information, not noise". The only guard on that path was added on
2026-10-04 (`73b31df`): values that do not fit `UInt64` are dropped, because
converting them trapped inside the parser itself.

Everything between 1 and about 1.8 × 10¹⁹ sat/vB therefore passed, and two
readers multiply the rate without checking:

| Reader | Arithmetic | Traps from | Reached when |
|---|---|---|---|
| `PaymentDestinationSelector.estimateOnchainFee` (`PaymentDestinationSelector.swift:482`) | `Int(feeRate * estimatedVBytes)`, vBytes 140 or 180 | ≈ 6.6 × 10¹⁶ (the `Int` conversion) | any onchain or silent-payment destination is ranked, shown or max-sent; three call sites (§3) |
| `ExitView_iOS.calculateExitCost` (`ExitView_iOS.swift:313-323`) | `totalParentVbytes * feeRateSatPerVb` and `(claimTxWeight / 4) * feeRateSatPerVb` in `UInt64`, then `UInt64(Double * 1.15)` | ≈ 2.4 × 10¹⁵ for ten VTXOs at depth 3; lower with more VTXOs | the Exit screen opens with uncovered VTXOs |

The backlog entry called the ranker "the only such arithmetic site". It is
the only `Int(...)` conversion; the exit estimate is a second overflow
site and traps earlier.

A rate like that is not a mainnet fee market, it is a poisoned or buggy
estimator. That is exactly the case a sanity ceiling is for.

## 2. Trace (claims labelled)

- **verified** Every non-default `OnchainFeeRates` is built in
  `FeeRateService.parse` (`FeeRateService.swift`); the only other
  constructor call in the tree is `OnchainFeeRates.default`
  (`ArkeUI/.../FeePriority.swift:80`). Grep over `Shared`, `ArkeMobile`,
  `ArkeDesktop`, `ArkeWidgets`, `ArkeUI`, `Tests`.
- **verified** The cap closure in `WalletManager.swift:405-408` returned nil
  on mainnet and 50 elsewhere; `parse` applied `min(rounded, maxRate ?? UInt64.max)`.
- **verified** Readers of the rate and what each does with it, §3.
- **verified** BDK's `FeeRate.fromSatPerVb(satVb:)` throws
  `FeeRateError.ArithmeticOverflow` instead of trapping
  (`bdk-swift/Sources/BitcoinDevKit/BitcoinDevKit.swift:4648`, `:16663` in
  DerivedData), so the two BDK estimate paths fail soft.
- **verified** bark-ffi's `OnchainWallet::send` builds the rate with
  `bitcoin::FeeRate::from_sat_per_vb(..).context("Invalid fee rate")?`, an
  error and not a panic. The line is identical at `~/workspace/bark-ffi`
  tags `v0.25.0+bark-0.6.2`, `v0.27.0+bark-0.7.0`, `v0.28.0+bark-0.7.1`
  (`src/core/onchain.rs:127`) and `v0.29.0+bark-0.7.1` (`:128`). The Swift
  package the app builds against is a different repo, `bark-ffi-bindings`
  at tag `v0.25.0+bark-0.7.1` (rev `157b0fc`, `Package.resolved`); its
  version numbers are not comparable with bark-ffi's (first draft of this
  plan said the revision "sits between" two bark-ffi tags — wrong, §8 F1).
  Not read: bdk_wallet's own weight × rate arithmetic inside `w.send` at
  10,000 sat/vB.
- **verified** `progressExits` / `drainExits` receive nil on mainnet
  (`ExitProgressionService.swift:170-173`, `UnilateralExitListView_iOS.swift:239`),
  so the app rate never reaches bark's exit code on mainnet (fact B5).
- **derived** The confirmation screen at 250,000 sat/vB (the harness
  payload): the BDK estimate throws insufficient funds for any realistic
  wallet (35 million sats of fee for a 140 vB transaction), the cache stays
  empty, and `SendViewModel+ComputedProperties.swift:171-177` falls back to
  `estimateOnchainFee` — the screen shows a 0.35 BTC fee and the send
  button stays enabled (`ManualSendView.canSend` never looks at the fee);
  the tap is then refused by the app's own viability check, not by bark:
  `SendViewModel+PaymentExecution.swift:134-143` throws from the ranker's
  `balance < amount + estimatedFee` (`PaymentDestinationSelector.swift:311-326`).
  No crash, an absurd number, no send. The open question in the backlog
  entry ("what the confirmation screen shows") is answered by trace, not by
  execution.
- **derived — the trade-off, stated plainly (reviewer F2, §8).** With the
  ceiling the same poisoning yields a 1.4 million sat fee for a 140 vB
  transaction. That *passes* the viability check for any wallet whose
  onchain balance covers amount + 1.4 million sats, and the send then
  reaches `OnchainWallet.send` at 10,000 sat/vB. The only guard left is the
  user reading the fee line on the confirmation screen. So the ceiling
  turns a formerly refused poisoned send into a possible, visibly
  overpriced one, while removing the crash. The hazard class is not new:
  any uncapped rate below the old refusal point (say 5,000 sat/vB, 700,000
  sats of fee) already behaved this way before the fix. Whether a rate at
  the ceiling should instead disable onchain sends with a reason ("fee
  estimate unreliable", the explicit-gate pattern, O5) is a product ruling
  Christoph owns; see §10.
- **assumed, not load-bearing** The highest next-block estimate mainnet has
  produced is in the low thousands of sat/vB (halving-block inscriptions,
  2024-04-20). The ceiling leaves several times that headroom; if the
  figure is wrong by 2× the design still holds, because a clamped rate is
  logged and still sends.

## 3. The sweep

Every reader of a mainnet rate, from `grep -rn "currentFeeRates\|onchainFeeRates\|rate(for:"`:

| Site | Uses the number for | Verdict |
|---|---|---|
| `PaymentDestinationSelector.estimateFee` → `estimateOnchainFee:482` | ranking fee, `Int(rate * vB)` | **covered** by the ceiling (max 1.8 million) |
| `SendViewModel+ComputedProperties.swift:171-177` | displayed fee when no BDK fee is cached, same function | covered |
| `SendViewModel+MaxSendable.swift:190-195` | fallback after a BDK failure, same function; `balance - estimatedFee` in `Int` | covered |
| `PaymentDestinationSelector.swift:311,324`, `SendViewModel+PaymentExecution.swift:142` | `amount + estimatedFee` viability adds in `Int` (added by the reviewer, §8) | covered — fee ≤ 1.8 million |
| `SendViewModel+FeeEstimation.swift:59-65`, `+MaxSendable.swift:170-176` | BDK `fromSatPerVb` | exempt — throws, caught |
| `SendViewModel+PaymentExecution.swift:172-174` → `BarkWalletFFI.sendOnchain` | FFI send | exempt — FFI returns an error; now also bounded |
| `ExitView_iOS.calculateExitCost:313-323` | `UInt64` products, `Double` round trip | **covered** by the ceiling (ten VTXOs at depth 3: 7,590 × 10,000 × 2.0 × 1.15 ≈ 1.7 × 10⁸) |
| `ExitProgressionService.exitFeeRateOverride`, `UnilateralExitListView_iOS:239` | nil on mainnet, fast tier elsewhere (cap 50) | exempt — B5 |
| `FeeRatesSectionView:40`, `FeeSelectionSheet:41` / `FeeOptionRow`, `ExitCostEstimateCard` | string interpolation; `Int(estimate.lowCost)` of a bounded product | exempt — display |
| `MockBarkWallet` | prints the rate | exempt — DEBUG stub |
| `OnchainFeeRates.default` | 10 / 5 / 2 | exempt — constants |
| `NoExitView.swift:305` `highCost - onchainBalance` | bounded product, behind `canAfford` | exempt — display |
| `ArkeDesktop/Views/Send/SendView.swift:159,241,290` | passes `viewModel.onchainFeeRates` to Shared views | exempt — pass-through |
| `ArkeUI/.../FeeSchedule.swift:80-84` `fixedAdditionalVb * feerateSatPerVb` | a third multiplication site, server fee schedule | exempt — zero callers in app or tests (reviewer, §8) |
| `Bark.swift:2183` `estimateEmergencyExitFee`, `:2404` `Wallet.sendOnchain(address:amountSats:)` | binding surface | exempt — unadopted / no fee parameter |

No site was found that computes with a rate from any other source.
`OnchainFeeRates` is `Sendable, Equatable` and not `Codable`, so there is
no decode path that could construct one from stored data.

## 4. Design (DECIDED 2026-10-19, ceiling value 10,000 confirmed by Christoph)

1. `FeeRateService.mainnetMaxRateSatPerVb = 10_000`, next to the existing
   `nonMainnetMaxRateSatPerVb = 50`. The constant's comment states the
   invariant: every rate the app computes with is bounded by one of the two.
2. The cap closure and the `parse(maxRate:)` parameter are no longer
   optional. The default for both is the mainnet ceiling, so a caller that
   forgets the cap gets the loosest bound the arithmetic can hold, not the
   old pass-through. `WalletManager` returns the mainnet ceiling for
   mainnet and the spam cap elsewhere.
3. One warning log when a fetch's fast tier equals the cap, naming the
   Esplora host, so a field export shows a clamp. On signet under spam
   this line is routine; on mainnet it is the signal that the item was
   right to exist.
4. No checked arithmetic at the two sites. The ceiling bounds them by
   construction (§3), and the construction-site invariant is pinned by the
   grep in §2 and the test in §5 rather than by a second guard that would
   never fire.
5. (after review) Both closures, Esplora URL and cap, are read before the
   15 s request rather than one before and one after, so a network-config
   switch mid-request cannot pair one network's rates with the other's
   cap. The clamp warning logs the host with default (private) privacy,
   like every sibling Esplora-URL line; on a device export the host is
   redacted, on the simulator it is readable.

Not changed: fact B5 and the exit override (nil on mainnet), the
`UInt64(exactly:)` drop of unrepresentable values (still needed, the
rounding happens before the clamp), the 50 sat/vB spam cap.

## 5. Tests

`Tests/Shared/FeeRateServiceTests.swift`, suite `FeeRateServiceTests`:

- `testMainnetCeilingPassesRealSpikesThrough` — 800 / 500 / 300 pass
  unchanged under the ceiling (replaces `testNilCapPassesHighRatesThrough`,
  which pinned the uncapped behaviour).
- `testMainnetCeilingClampsPoisonedEstimator` — the 2026-10-08 harness
  payload (250,000 on every target) comes out at the ceiling on all tiers.
- `testDefaultCapIsMainnetCeiling` — `parse` without a cap argument clamps
  6.7 × 10¹⁶, the first value that used to trap the ranker.
- `testCeilingKeepsRankerArithmeticInRange` — `estimateOnchainFee` at the
  ceiling returns 1,400,000 and 1,800,000 for the two transaction sizes,
  pinning that the constant and the arithmetic agree.

## 6. Device step (Tier 0 definition of done)

The fault cannot be reproduced on a device without a poisoned Esplora, and
the code path for sane rates is unchanged. The device step is therefore a
regression look on the mainnet phone with the new build:

1. Data screen, fee rates section: three sane values and a "last updated"
   time, no clamp warning in the export.
2. Send to an onchain address: the destination ranks and the fee line
   shows a plausible number for the medium tier.
3. Exit screen: the cost estimate renders.

Log fingerprint of the build: `Fee rate estimate clamped to the` exists in
the binary (`git log -S`), the line itself should not appear on mainnet.

### 6.1 Result (2026-10-19, Christoph, mainnet phone, debug build)

| Step | Evidence in `Docs/debug_logs.txt` | Verdict |
|---|---|---|
| 1 Data screen | `Fee rates updated: fast 2, medium 2, slow 1 sat/vB` (Esplora `mempool.second.tech/api`, network `bitcoin`) | PASS |
| 2 Send to an onchain address | `Ranked 1 destinations`, selected destination Bitcoin; BDK threw `CoinSelection … 0 BTC available`, so the fee came from the fallback: `Using conservative fallback: 19720 sats (fee: 280 sats)` — exactly 2 sat/vB × 140 vB through `estimateOnchainFee`, the arithmetic the ceiling bounds | PASS for this item; the BDK "0 BTC available" against 20,000 sats onchain is a pre-existing gap, filed Tier 1 "Send and fees" |
| 3 Exit screen | `Estimating exit cost… Fee rate: 2 sat/vB, VTXOs to exit: 33, Estimated cost: 75019 sats, Can afford: false` | PASS |
| 4 Clamp line | no `clamped to the` in 4,119 lines | PASS |

Other lines in the same export, none caused by this change: eleven
`client connection error: hyper::Error(IncompleteMessage)` from bark's
Esplora client reusing an idle keep-alive connection (the sync that
followed succeeded), and one `[UnifiedTxService] Duplicate txid found`
warning for a working dedupe. Both filed as one Tier 4 noise line.

## 7. Verification record

- IDE build with test targets: green (2026-10-19).
- `xcodebuild test … -only-testing:ArkeMobileTests/FeeRateServiceTests`,
  iPhone 17 Pro simulator by id (the name-based destination fails on this
  machine): TEST SUCCEEDED, counts in §9.
- Full mobile suite: §9, run after the adversarial pass per the 2026-10-11
  ruling.

## 8. Adversarial pass (`fault-class-reviewer`, fresh context, 2026-10-19)

Handed the three-file diff, the area and this plan. It re-ran the scoped
suite itself (17/17) and found no code defect that crashes or loses funds.
Four findings, all acted on the same session:

| # | Verdict / class | Finding | Resolution |
|---|---|---|---|
| F1 | CONFIRMED, 5 | §2 said the deployed bindings revision "sits between" two bark-ffi tags; the Swift package is a different repo (`bark-ffi-bindings` `v0.25.0+bark-0.7.1`) with incomparable numbers. Conclusion unaffected (line identical at four bark-ffi tags). | §2 corrected |
| F2 | CONFIRMED, 5 | §2 said "bark would then refuse" a poisoned send; the app's viability check does. And the plan did not state that the ceiling turns a formerly refused poisoned send into a possible one. | §2 trade-off bullet; ruling in §10 |
| F3 | PLAUSIBLE, 1 | the clamp warning logged the Esplora host `privacy: .public` where every sibling line is debug-level private; a custom network's host is user-chosen. | privacy annotation removed |
| F4 | PLAUSIBLE, 2 | pre-existing: the URL closure was read before the request and the cap closure after it, and the 300 s cache is not invalidated on a network-config change (`feeRateService` is created once, never reset). Worst case ≤ 300 s of the other network's cap; cannot loosen mainnet. | closure skew fixed (§4.5); the cache residual filed as a Tier 4 line |

Also from the pass, folded into §3: the viability adds and three further
exempt sites, and the `FeeSchedule` multiplication nobody calls.

Not verified by the reviewer: the device step; bdk_wallet's internal
arithmetic at 10,000 sat/vB; whether a fee fetch can run before the
pre-open network reconcile (traced, no caller found, not executed); the
full suite.

## 9. Results

| Check | Result |
|---|---|
| IDE build with test targets | green, 2026-10-19 |
| `FeeRateServiceTests` (scoped, `xcodebuild`, iPhone 17 Pro by id) | 17 passed, 0 failed; the four new tests among them |
| Reviewer's own scoped run | 17/17 |
| Full mobile suite (`xcodebuild`, same simulator, after the adversarial pass) | 565 passed, 0 failed, 0 skipped |
| Device step §6 | PASSED 2026-10-19, mainnet phone, debug build (§6.1) |
| Desktop | not built, parked |

## 10. Rulings (DECIDED 2026-10-19, Christoph: "I'll follow your recommendation")

- **Ceiling value: 10,000 sat/vB.** Any value from about 5,000 up keeps
  the arithmetic safe; 10,000 leaves several times the headroom over the
  highest estimates mainnet has produced.
- **Behaviour at the ceiling (F2): ship the ceiling alone for Lugano.** A
  clamped rate still prices and sends, visibly overpriced. The
  explicit-gate pattern (O5) — fast tier at the ceiling disables onchain
  sending with "fee estimate unreliable", Ark and Lightning stay usable —
  is a Train 2 Tier 1 item, filed under "Send and fees" in the backlog,
  with its own device look because it is new policy on the send path.
