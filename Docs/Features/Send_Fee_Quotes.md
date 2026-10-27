# Send Fee Quotes: One Quote Per Tier, A Fee Row That Says What It Knows

**Status: BUILT and REVIEWED 2026-10-27 (Tier 1 "Send and fees", Train 2).
Four commits on `main` (`20c4ac4`, `c46daf4`, `2fe0f62`, review fixes).
Adversarial pass §5: two confirmed findings, both fixed the same session;
four plausible, two fixed, two filed. Simulator walkthrough §6 on the
signet test wallet PASSED for every state except "Exceeds balance", which
the wallet could not produce (§6.3). Owed: the device look on Christoph's
phone (§7).**

Backlog entries: `Open_Follow_Ups.md`, Tier 1 "Send and fees": the fee
row three-state proposal (onchain half closed by this), the blind
estimator (option (a) built here, device evidence owed), and the send-all
overshoot filed from §6.3.

## 1. What was wrong

Before an onchain destination's fee was priced, the send flow showed a
placeholder of rate × 140 vB in the same type as a priced fee. The
placeholder also stood in whenever the shadow BDK wallet's estimate
failed, which the blind-estimator entry says is routine on real devices.
Three more defects sat behind it, all traced on 2026-10-27:

- The 140 vB constant is the P2WPKH size; bark's wallet is BIP86, where
  one input and two outputs come to 154 vB. The simulator priced the
  simplest send at 7,839 sats for 50 sat/vB, 157 vB, so the placeholder
  ran about a tenth low.
- The single-fee cache was keyed by amount and priority, not address, and
  `clearAll` did not reset it; a new recipient inherited the old fee.
- The pre-send viability check priced every onchain send with the rough
  medium-tier number regardless of the chosen tier.

The speed sheet showed tier names and time ranges only; the rate line was
commented out and no fee appeared until a tier was picked and a new
estimate ran.

## 2. Design

**`OnchainFeeQuote`** (`Shared/Views/Send/OnchainFeeQuote.swift`): one
BDK quote for one address, amount and rate set, holding a result for every
`FeePriority` tier, `.fee(Int)` or `.unaffordable`. A quote matches the
current inputs completely or does not count; nothing invalidates it by
hand. Changing the rates, the amount or the address makes the quote
non-matching and the next estimate replaces it.

**`WalletManager.estimateOnchainFees`**: syncs the shadow wallet once (the
only network step) and builds one transaction per tier locally, so three
tiers cost what one did. A tier BDK cannot fund is reported as
`.insufficientFunds`, typed at the estimator boundary
(`BDKFeeEstimatorError.insufficientFunds`, mapped from BDK's
`CreateTxError.InsufficientFunds` and `.CoinSelection`); any other build
error aborts the quote. When every tier is unfundable while bark's
`onchainBalance.spendableSat` covers the amount, the shadow wallet is
behind and the method runs one full scan and quotes again (backlog
option (a)).

**`FeeDisplayState`** (ArkéUI): `value`, `estimating`, `approximate`,
`unaffordable`, `unavailable`. `FeeDisplayView` renders a tilde and
secondary colour for approximate, a spinner with "Estimating…", "Exceeds
balance", or a dash, and speaks each state. `OnchainFeeQuote.displayState`
is the pure decision: a matching quote wins (priced tier → value,
unaffordable tier → unaffordable); otherwise estimating while the newest
request is open; otherwise approximate. The placeholder is never shown
while a request is open, and a quote for other inputs is never shown.

**Request lifecycle** (`SendViewModel+FeeEstimation`): a generation
counter; a reply from a superseded request is dropped, the "estimating"
flag clears only when the newest request finishes. `resetOnchainFeeQuote`
cancels the debounce, bumps the generation and clears the flag and quote;
called from `clearAll` and when the amount is emptied. A destination
change triggers a quote in all three presenters (the quote is keyed by
address).

**Viability**: `PaymentDestinationSelector.rankDestination(exactFee:)`
takes the quoted fee at the chosen tier when the quote covers the send;
`executeSend` passes it, so the gate judges the send by the fee it will
pay. Without a matching quote the gate uses the rough placeholder as
before, now at 155 vB.

**Speed sheet**: `FeeOptionRow` shows name and time on the left, fee and
rate on the right; an unaffordable tier reads "Exceeds balance" and is
disabled. `FeeSelectionSheet` reads the flow's current quote, so a tier
switch is instant.

## 3. Verified facts the design rests on

- BDK's `TxBuilder.finish` + `calculateFee` is local once synced; the
  network cost is `sync(fullScan:false)` (read in `BDKFeeEstimator`).
- `amount` is whole sats as a string in fiat mode and after send-all, so
  `Int(amount)` equals the quote's `amountSats` (reviewer, read).
- `OnchainFeeRates.rate(for:)` is an exhaustive switch; a new
  `FeePriority` case fails to compile rather than quoting a hole.
- Every new ArkéUI string passes `bundle: .module`; catalog values checked
  after the build: `~%@`, `Estimating…`, `Exceeds balance`, `%llu sat/vB`.

## 4. Tests

`OnchainRoughFeeEstimateTests`: the placeholder covers a 154 vB Taproot
send at the same rate, silent-payment destinations share the floor, the
placeholder scales with the rate. `OnchainFeeDisplayStateTests`: matching
quote wins, tier switch reads the quote, an unaffordable tier says so
even while estimating, other amount / address / rates never stand in,
estimating hides the placeholder, no amount is approximate. 11 tests,
green on the iPhone 17 Pro simulator.

## 5. Adversarial pass (fault-class-reviewer, range `20c4ac4^..2fe0f62`)

| # | Verdict | Finding | Resolution |
|---|---|---|---|
| F1 | CONFIRMED, path asymmetry | `executeSend` ranks first and throws `destinationNotViable` on the rough medium fee before the exact-fee line runs; the 155 vB bump made that gate stricter and blocked send-all at medium | `rankDestination(exactFee:)`; `executeSend` passes the quoted fee |
| F2 | CONFIRMED, trusted claim | After send-all at one tier the faster tiers cannot be built; the quote came back with holes, the row showed "approximate" for a tier BDK had priced out, and the matching quote blocked a re-quote forever | Per-tier result with `.unaffordable`; typed insufficient-funds error; quote always complete |
| F3 | PLAUSIBLE | Destination change never triggered a quote; a contact with two onchain addresses showed approximate after switching | Trigger added in the three presenters |
| F4 | PLAUSIBLE, ownership | `clearAll` and the empty-amount path cleared the quote but not the generation, task or flag; "Estimating…" could persist | `resetOnchainFeeQuote` |
| F5 | PLAUSIBLE | Send stays tappable while the row says "Estimating…"; a send in that window pays the new rate while the gate judged by the rough one | Filed as PROPOSED (gate Send on `.estimating`) |
| F6 | PLAUSIBLE, low | `exactOnchainFee` keys on `selectedDestination`; quick mode resolves `destinationId`; unreachable with the default priority order | Filed as a note |

Not verified by the reviewer: BDK change handling at the exact send-all
amount; overlapping shadow-wallet syncs from two concurrent requests
(pre-existing exposure, assumed serialised by the binding); whether bark's
own `OnchainWallet.send` builds the same shape as the shadow wallet.

## 6. Simulator walkthrough (iPhone 17e, signet test wallet, 2026-10-27)

Screenshots in `~/workspace/Arke-sessions/screenshots/2026-10-27/`.

### 6.1 States seen

| Step | Fee row |
|---|---|
| Address entered, no amount | `~₿ 7,750` grey, accessibility "Approximate, not yet priced" |
| 1000 sats typed | `₿ 7,839` after the debounce and quote (spinner seen at the send-all step) |
| Sheet | Fast `₿ 7,839`, Medium `₿ 7,839`, Slow `₿ 7,713`, all `50 sat/vB` (signet clamp) |
| Fast picked | `₿ 7,839` at once, no "Estimating…" |
| Send-all | `Estimating…` with spinner, then `₿ 8,451` |
| Amount cleared | `~₿ 7,750` again, Send disabled |

### 6.2 Log lines

```
Quoting onchain fees for 1000 sats at fast 50 / medium 50 / slow 50 sat/vB
Fee estimator finds no funds for 1000 sats while bark holds 141572 spendable; running one full scan and quoting again
Onchain fees quoted for 1000 sats: fast 7839, medium 7839, slow 7713
Onchain (BDK): Exact calculation complete / Max sendable: 141960 sats
Onchain fees quoted for 141960 sats: fast 8451, medium 8451, slow 8451
```

The second line is the blind-estimator retry firing: the shadow wallet had
been full-scanned at 09:44 the same morning and still found no funds for
the incremental sync at 10:43; one full scan healed it. Simulator
evidence, not device evidence, so the backlog entry stays open.

### 6.3 Findings from the walkthrough

- **Send-all overshoots bark's balance.** Send-all returned 141,960 sats
  against a Savings balance of 141,572; with the 8,451 fee the shadow
  wallet funds 150,411 sats, 8,839 more than bark reports. 8,839 sats is
  the figure of feedback ask 7c (funds on an address bark has not revealed
  after a seed import), so the shadow wallet sees coins bark does not. The
  amount field flags "Exceeds available" in orange, yet Send stays enabled;
  the pre-send gate throws `insufficientBalance` at tap time. Pre-existing
  (the send-all path is unchanged); filed.
- **"Exceeds balance" not reproducible here** for the same reason: the
  shadow wallet could fund every tier. The state is pinned by unit tests
  and needs a wallet whose shadow view matches bark's.
- **Equal rates, different fees**: Slow priced 7,713 against 7,839 at the
  same clamped 50 sat/vB. BDK's coin selection is not deterministic across
  builds. Cosmetic on signet, where the clamp makes the tiers equal.
- **Row layout** overflowed on the 17e (time ranges truncated, "~1-2
  hours" wrapped); fixed the same session by moving the rate under the
  fee on the right.
- "Estimating…" was not caught right after typing because the 500 ms
  debounce runs while the keyboard is up; the state was seen at send-all.

## 7. Device checklist (owed)

1. Mainnet phone, onchain address, amount typed: tilde placeholder, then
   "Estimating…", then a priced fee; sheet shows three different fees at
   three different rates; a tier switch is instant.
2. Send-all at medium, then open the sheet: Fast reads "Exceeds balance"
   and cannot be picked (needs a wallet whose shadow view matches bark's).
3. Export: `Fee estimator finds no funds … running one full scan` followed
   by `Onchain fees quoted` closes the blind-estimator entry.
4. VoiceOver pass over the fee row and the three sheet rows.
