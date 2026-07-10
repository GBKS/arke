# PaymentDestinationSelector

Reference for `PaymentDestinationSelector` — the component that decides which payment
method to use when a payment request offers more than one (e.g. a BIP‑21 URI carrying
Bitcoin + Ark + Lightning), ranks the options by viability and fee, and reports why each
one is or isn't usable.

**Source:** `Shared/Helpers/PaymentDestinationSelector.swift`

> This document was rewritten on 2026-06-25 to match the current code. It replaces three
> older docs (`IMPLEMENTATION_SUMMARY.md`, `QUICK_REFERENCE.md`,
> `PAYMENT_SELECTION_FLOW_DIAGRAM.md`) that still described a `PaymentDestinationPickerView`
> UI which no longer exists. The selector API itself is unchanged and current.

---

## Core idea

The selector exists because **payment formats draw from different balances**, and the app
should pick the cheapest viable one automatically while still letting the user override.

The key insight it encodes:

> **Ark and Lightning payments share the same balance pool** (`arkBalance`), while on‑chain
> Bitcoin and Silent Payments draw from a separate pool (`bitcoinBalance`).

This is why a Lightning option can be marked unviable for the *same* reason an Ark option
is: they compete for the same sats.

## Balance sources

`BalanceSource` records which pool a destination draws from:

| Case | Format(s) | Pool used | `displayName` | `networkName` |
|---|---|---|---|---|
| `.ark` | `.ark` | `arkBalance` | "Payments Balance" | "Ark Network" |
| `.arkViaServer` | `.lightning`, `.lightningInvoice`, `.lnurl`, `.bolt12` | `arkBalance` (routed via Ark server) | "Payments Balance" | "Lightning Network" |
| `.bitcoin` | `.bitcoin`, `.silentPayments` | `bitcoinBalance` | "Savings Balance" | "Bitcoin Network" |

`.bip353` and `.bip21` are wrapper formats expected to be resolved to a concrete format
before ranking; they fall back to `.bitcoin` if they somehow reach the selector.

`.arkViaServer` destinations return `true` from `requiresServerRouting` and are only viable
when the server is reachable (see Viability).

## Default priority (lowest fees first)

`PaymentPreferences.defaultPriority`:

1. `.ark` — same server, instant, typically free
2. `.lightning`
3. `.lightningInvoice`
4. `.lnurl`
5. `.bolt12`
6. `.silentPayments`
7. `.bitcoin`
8. `.bip353`

Lower index = higher priority. Unknown formats sort last.

## Preferences

`PaymentPreferences` (defaults in parentheses):

| Property | Default | Meaning |
|---|---|---|
| `priorityOrder` | `defaultPriority` | Ordered format preference |
| `preferOnChainForLargeAmounts` | `false` | Deprioritize non‑Bitcoin for large amounts |
| `largeAmountThreshold` | `1_000_000` sats | Threshold for the above |
| `minimumArkReserve` | `10_000` sats | Reserve floor for Ark balance |

> **Note:** the `minimumArkReserve` enforcement in `checkViability` is currently commented
> out, so the reserve does **not** affect viability today. The preference is still carried
> for when it's re‑enabled.

## Context

`PaymentContext` is the wallet snapshot used for a single ranking pass. It is meant to be
**short‑lived and created on demand** — `SendViewModel` exposes it as a computed property
(`paymentContext`) rather than storing it.

```swift
PaymentDestinationSelector.PaymentContext(
    arkBalance: Int?,                 // spendable Ark sats
    bitcoinBalance: Int?,             // spendable on-chain sats
    networkConfig: NetworkConfig,
    userPreferences: PaymentPreferences = .default,
    arkServerConnected: Bool = true,
    hasLightningCapability: Bool = true,
    walletManager: WalletManager? = nil   // weak; enables real fee estimation
)
```

`walletManager` is held **weakly**. When present, Lightning destinations get real fee
estimates; when nil, fee estimation degrades gracefully to static fallbacks (no crash).

## Ranking output

Each candidate becomes a `RankedDestination`:

```swift
struct RankedDestination {
    let destination: PaymentDestination
    let balanceSource: BalanceSource
    let availableBalance: Int?
    let estimatedFee: Int?
    let viable: Bool
    let reason: String      // human-readable explanation, viable or not
    let priority: Int       // lower = higher priority
    var requiresServerRouting: Bool { balanceSource == .arkViaServer }
}
```

`rankDestinations` filters to network‑compatible destinations, ranks each, then sorts
**viable first, then by ascending priority**.

## Viability rules (`checkViability`)

In order:

1. `.arkViaServer` destination + server not connected → **not viable** ("Ark server not connected").
2. `.arkViaServer` destination + no Lightning capability → **not viable** ("Lightning not available").
3. No amount specified → **viable** ("No amount specified") — amount entered later.
4. Balance unavailable → **not viable** ("Balance unavailable").
5. `balance < amount + estimatedFee` → **not viable** ("Need _X_ more").
6. `preferOnChainForLargeAmounts` + amount ≥ threshold + non‑Bitcoin → still **viable**, flagged "Large amount: on-chain preferred".
7. Otherwise → **viable** ("Sufficient balance").

## Fee estimation

`estimateFee` (async, private):

- **Lightning formats** (`.lightning`, `.lightningInvoice`, `.lnurl`, `.bolt12`) with a
  known amount and a live `walletManager` → real estimate via
  `walletManager.estimateLightningSendFee(amountSats:)` (gross − amount, clamped ≥ 0).
  Falls back to the static estimate on error or missing `walletManager`.
- **Everything else** → static fallback.

Static fallbacks (`estimateFeeFallback`):

| Format | Fee (sats) |
|---|---|
| `.ark` | 0 |
| Lightning formats | 20 |
| `.bitcoin` | 500 |
| `.silentPayments` | 600 |
| `.bip353` / `.bip21` | 0 |

On‑chain fees can also be computed from a fee rate with
`estimateOnchainFee(for:amount:feeRate:)` (≈140 vB for Bitcoin, ≈180 vB for Silent
Payments × `feeRate` sat/vB).

## API

Static methods on `PaymentDestinationSelector` (all ranking methods are `async`):

| Method | Returns |
|---|---|
| `selectOptimalDestination(from:context:)` | First viable `PaymentDestination?` |
| `rankDestinations(from:context:)` | `[RankedDestination]`, sorted |
| `rankDestination(_:amount:context:)` | Single `RankedDestination?` |
| `canFulfillPayment(_:with:)` | `(feasible: Bool, suggestedDestination: PaymentDestination?)` |
| `isViable(destination:amount:context:)` | `Bool` |
| `viableDestinations(from:context:)` | `[PaymentDestination]` |
| `viabilityReport(from:context:)` | `String` (debug/diagnostic) |
| `balanceSource(for:)` / `availableBalance(for:context:)` / `requiresServerRouting(_:)` | Helpers |
| `estimateOnchainFee(for:amount:feeRate:)` | `Int` |

Convenience methods on `PaymentRequest`:

```swift
await request.selectOptimalDestination(context:)   // PaymentDestination?
await request.rankedDestinations(context:)          // [RankedDestination]
await request.canFulfill(with:)                     // Bool
```

## How the Send flow uses it

The selector is consumed by `SendViewModel` (see `../Send/SendView_Architecture.md` for the
overall Send architecture):

- **`paymentContext`** (`SendViewModel+ComputedProperties.swift`) builds a fresh context
  from current wallet balances + `walletManager` on every access.
- **`lockInPaymentRequest` / `enterQuickMode` / `rankManualDestination`**
  (`SendViewModel+StateManagement.swift`) call `rankedDestinations(context:)`, store the
  result in `viewModel.rankedDestinations`, and auto‑select the first viable destination.
- **`executeSend`** (`SendViewModel+PaymentExecution.swift`) re‑ranks the chosen
  destination with *fresh* balances/fees for a final viability + balance check, then routes
  by `destination.format` to the matching `WalletManager` call (`sendOnchain`, `send`,
  `payLightningInvoice`, `payLightningAddress`, `payLightningOffer`, LNURL resolution).

### Display layer

The ranked destinations are presented through `DisplayDestination` +
`SheetDestinationDisplayView` (+ `PaymentDestinationItem` rows) inside the Flows views
(`ContactPaymentView`, `QuickPaymentView`, `ManualSendView`). The user changes the selected
destination via the sheet that `SheetDestinationDisplayView` presents.

> Historical note: an earlier `PaymentDestinationPickerView` / `PaymentDestinationRow` UI
> served this role but was removed (it had become unreachable — its presentation flag was
> never set). `SheetDestinationDisplayView` is the current mechanism.
