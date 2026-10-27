# Send Fee Quotes: One Quote Per Tier, A Fee Row That Says What It Knows

**Status: BUILT and REVIEWED 2026-10-27 in two batches (Tier 1 "Send and
fees", Train 2). Batch 1 (§1–§6): `20c4ac4`, `c46daf4`, `2fe0f62`,
`157609e`. Batch 2 (§8): `4323294`, `df7f125`, `bd2f5a4`, `2f8357c` and the
follow-up fixes. Both adversarial passes' confirmed findings fixed the same
day; two PROPOSED questions remain in the backlog. Simulator walkthroughs
PASSED for every state the signet wallet can produce. Owed: the device look
on Christoph's phone (§7, extended in §8.6).**

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

## 8. Second batch: picker, minimum, gates, Lightning (2026-10-27, DECIDED)

Christoph's rulings after reviewing the batch 1 screenshots: remove the
sat/vB line; show the minimum only as a conditional hint; collapse tiers
that share a rate; and fold in the four open fee issues so the area is not
revisited. Built as three steps plus review fixes.

### 8.1 One row per distinct rate

`FeeTierGroup` (ArkéUI) groups the tiers by equal rate, fastest first; a
group is named and timed by its fastest member because that rate meets the
shortest target in the group. The sheet shows one row per group, selects
by group membership, and writes the representative tier on pick; with one
group the fee row loses its chevron and never opens the sheet. On a quiet
mainnet mempool the 1-, 3- and 6-block estimates are all 1 sat/vB, so one
row is the normal mainnet case, not a signet quirk. `selectedFeePriority`
may still name a non-representative tier; the send pays
`rate(for: selectedFeePriority)`, identical by construction (reviewer).
The shadow wallet builds once per distinct rate so two tiers at one rate
never show two fees.

Each tier owns its Esplora target (`confirmationTargetBlocks` 1 / 3 / 6,
bark's own constants, verified in `bark/src/chain.rs` on master) and
`FeeRateService` reads the same numbers; the duration shown is
`BlockTimeFormatter.confirmationEstimate(forBlocks:)`, "~10 min",
"~30 min", "~1 hr". The sat/vB line is gone; the rate lives in X-Ray.

### 8.2 Minimum as a hint

The permanent "Minimum" row on the amount card is replaced by an orange
caption "Minimum is ₿ 546" shown only while the typed amount is under the
destination's minimum (onchain dust; Ark and Lightning have none). Fiat
entry mode uses the sats behind the field (`currentAmountSats`).

### 8.3 One gate for the Send button

`SendBlocker.evaluate` (`SendGate.swift`) is a pure decision read by the
manual, contact and quick flows through their `sendViewModel` handle, with
`SendBlockedReasonText` as the one orange line under the button:

| Blocker | When | Line under Send |
|---|---|---|
| `feeEstimateUnreliable` | onchain, mainnet fast tier at the ceiling (`WalletManager.isMainnet`, the cap's own predicate) | "The fee estimate is unreliable right now. Onchain sending is paused." |
| `noAmount` | nothing typed | none |
| `belowMinimum` | under the minimum | none, the card's hint explains |
| `estimatingFee` | onchain quote open, from the first keystroke | "Estimating the fee…" |
| `unaffordableTier` | the chosen speed priced out of the balance | "This speed exceeds your balance. Pick a slower one." |
| `exceedsAvailable` | amount plus the shown fee over the balance, locked invoice amounts included | "More than your available balance" |

### 8.4 Send-all within bark's balance

`OnchainSendAll.cappedAmount` caps the shadow wallet's drain at bark's
`spendableSat` minus the drain fee. The capped amount is no longer a
drain: re-quoted as a recipient amount it carries a change output and a
larger fee (review F1), so the send-all path re-quotes and `refit`s until
amount plus fee fits, keeping the largest amount that fitted across the
shadow wallet's non-deterministic coin selection (the first simulator
pass left 2,887 sats behind before the best-of loop).

### 8.5 Lightning half

`PaymentDestinationSelector.estimateFee` returns nil instead of a static
constant when no estimate could be made; viability judges the amount
alone. The Lightning row shows "Estimating…" while the request is open
(generation-owned flag, stale replies dropped, cache valid only for the
amount it was made for) and "unavailable" on failure. The unrendered
`feeText` chain through `SendAmountInput`, `AmountInputSection`, the three
flows and both presenters is deleted.

### 8.6 Adversarial pass (range `4323294^..bd2f5a4`)

| # | Verdict | Finding | Resolution |
|---|---|---|---|
| F1 | CONFIRMED | Capped send-all re-quotes with a change output; the gate refuses it | `refit` loop, §8.4 |
| F2 | CONFIRMED | Lightning estimating flag unowned under overlapping calls; cached fee shown for another amount | Generation counter; amount-keyed cache read; `clearAll` resets |
| F3 | CONFIRMED | Placeholder shown and Send enabled during the 500 ms debounce and after a failed quote | Estimating from the first keystroke; failed-quote gating filed as PROPOSED |
| F4 | pre-existing gap | Locked invoice amounts skipped every balance check | Still exempt from the minimum, refused above the balance |
| F5 | PLAUSIBLE | Gate and cap read "mainnet" from two predicates | Gate reads `WalletManager.isMainnet` |
| F6 | PLAUSIBLE, low | Lightning destination viable on amount alone when its estimate fails | Accepted; bark rejects at send, the row says unavailable |
| F7 | hygiene | Four stale ArkéUI keys after the build | Dropped |

Not verified by the reviewer: BDK adds a change output at the capped
amount (standard behaviour, confirmed indirectly by the simulator's 2,887
sat slack); bark's own send at the capped amount; whether Send can be
tapped inside the debounce on a device.

Simulator walkthrough (iPhone 17e, signet, build `2f8357c`): no Minimum
row; hint at 300; "Estimating…" and the caption from the first keystroke;
priced fee ₿ 7,713; no chevron, no sheet (one rate); send-all 130,972 with
fee 7,713 inside 141,572, Send enabled, no caption; placeholder when
cleared. Two follow-up fixes from it: the best-of loop in §8.4 and an
immediate reset when the amount is emptied (a spinner flashed during the
debounce). Noted, not fixed: the send-all control responds to its label
text, not the whole row.

Device checklist additions: mainnet sheet shows two or three rows only
when the rates differ; tier switch pays the representative's rate; "fee
estimate unreliable" line with a forced clamp (custom network at a
poisoned Esplora); a Lightning invoice above the Ark balance is refused
before the tap.
