# API Changes: Bark FFI Bindings v0.13.0 → v0.14.0 (Bark v0.4.0 → v0.5.0)

Diff of the generated `Bark.swift` is **purely additive**. No method was removed,
no existing signature changed, no type was renamed. Existing call sites compile
unchanged *except* where they construct `Vtxo` or `LightningReceive` directly
(memberwise initializers gained parameters) or switch on `LightningReceive.state`.

---

## 1. New `Wallet` methods

### `bolt11InvoiceForAddress`

```swift
open func bolt11InvoiceForAddress(
    amountSats: UInt64,
    claimDestination: String,
    description: String? = nil,
    token: String? = nil
) async throws -> LightningInvoice
```

Creates an invoice whose claimed VTXO is delivered to `claimDestination` (an Ark
address), letting that wallet receive while offline.

The claim is signed directly to the destination address's own policy, so the
invoicing wallet has no custodial control and cannot redirect the payment. It can
still *strand* it: delivering the signed output to the destination's mailbox is a
separate step only the invoicing wallet can perform, and the recipient has no
independent way to recover the funds until it happens. Delivery resumes
automatically on restart, so a crash recovers on its own — but running this for
someone else means they trust you to stay online and eventually deliver, not that
they trust you with custody.

A `claimDestination` owned by this wallet is claimed locally instead of going
through its mailbox.

### `recoveryReport`

```swift
open func recoveryReport() -> RecoveryReport?
```

**Not async, not throwing** — reads the stored result of a scan that already ran.

Result of the seed-recovery scan performed during `Wallet.open()`, or `nil` if no
report was produced. Recovery only runs on the open that *creates* the wallet
locally (fresh create/import), and not at all when `WalletOpenArgs.skipRecovery`
is set — so this is empty on every subsequent open. It is also empty when the
scan itself failed outright (bark logs that and lets `open` succeed), so an empty
result does **not** prove no funds are missing.

`isComplete == false` means funds may still be missing; retry the report's
`failed` ids with `recoverVtxos`.

### `recoverVtxos`

```swift
open func recoverVtxos(vtxoIds: [String]) async throws -> RecoveryReport
```

Recovers the given VTXO ids from the server, importing the ones this wallet owns
that are still spendable. Use it to retry ids a previous scan reported as
`failed`.

### `refreshVtxosScheduled`

```swift
open func refreshVtxosScheduled(
    vtxoIds: [String],
    scheduledHeight: UInt32
) async throws -> RoundState?
```

Schedules a delegated refresh for `scheduledHeight` instead of the next round.
The refresh fee is priced against the VTXO's remaining lifetime at that height,
and the server charges less the closer a VTXO is to expiry, so **scheduling
further out never costs more than refreshing now**.

Companion to the existing `refreshVtxosDelegated(vtxoIds:)`; pairs naturally with
`getNextRequiredRefreshBlockheight()`.

---

## 2. New types

### `RecoveryBucket`

```swift
public struct RecoveryBucket: Equatable, Hashable, Sendable {
    public var vtxoIds: [String]
    public var totalSats: UInt64
}
```

One bucket of a `RecoveryReport`. `totalSats` only sums the VTXOs whose amount is
known, so it can under-count `failed`, where a VTXO may have failed before being
fetched. `vtxoIds` is sorted (upstream buckets them unordered).

### `RecoveryReport`

```swift
public struct RecoveryReport: Equatable, Hashable, Sendable {
    public var recovered: RecoveryBucket
    public var skipped:   RecoveryBucket
    public var foreign:   RecoveryBucket
    public var failed:    RecoveryBucket
    public var exited:    RecoveryBucket
    public var isComplete: Bool
}
```

Outcome of a recovery scan: every VTXO id the scan looked at, bucketed by what
was decided about it.

| Bucket | Meaning | Funds at risk? | Retryable? |
|---|---|---|---|
| `recovered` | Spendable VTXOs successfully re-imported | No | — |
| `skipped` | Deliberately left out: spent into a newer recovered VTXO, exited on-chain, or reported non-spendable by the server | No | — |
| `foreign` | No matching key derivable within the gap limit (50 consecutive unused indices) | **Possibly** — for a mailbox scan these are most likely this wallet's own VTXOs keyed beyond the limit | No — needs a wider gap limit, not a retry |
| `failed` | Could not be decided due to an error; not known to be spent | **Possibly** | **Yes** — via `recoverVtxos` |
| `exited` | Already fully exited on-chain | No | — |

`isComplete` is `true` only when the scan accounted for every VTXO — i.e. both
`failed` and `foreign` are empty.

The `skipped` vs `failed` distinction is the load-bearing one: `skipped` was a
decision, `failed` was an absence of one.

For `recoverVtxos` specifically, a `foreign` id just means the caller passed an id
this wallet doesn't own.

---

## 3. Changed struct fields

All three are **appended** fields. Reading them is free; *constructing* these
structs now requires the new argument.

### `Vtxo` — new field

```swift
public var registered: Bool
```

Whether this VTXO's recovery state has been asserted with the server: its id
posted to the recovery mailbox and its signed transaction chain registered. Only
ever moves `false → true`; the sync-time catch-up re-uploads the ones still
`false`.

New memberwise init parameter order:

```swift
Vtxo(id:amountSats:expiryHeight:kind:state:exitDepth:exitTxWeightWu:registered:)
```

### `LightningReceive` — new field

```swift
public var claimDestination: String?
```

Ark address the claimed VTXO is delivered to, for receives created with
`bolt11InvoiceForAddress`. `nil` for ordinary receives claimed by this wallet,
and **always `nil` once settled** — the settled record does not carry the
destination. Do not rely on it to identify a delivered receive after settlement.

New memberwise init parameter order:

```swift
LightningReceive(paymentHash:invoice:amountSats:state:paymentPreimage:settledAt:claimDestination:)
```

### `WalletOpenArgs` — new field

```swift
public var skipRecovery: Bool = false
```

Whether to skip the seed-recovery mailbox scan. The scan runs on the open that
creates the wallet locally and **makes network calls**; its result is available
from `recoveryReport()`. Has a default value, so existing construction sites
compile unchanged.

---

## 4. Changed behavior

### `LightningReceive.state` gained a value

```
"awaiting-payment" | "htlcs-ready" | "preimage-revealed" | "delivering" | "settled"
                                                            ^^^^^^^^^^^ new
```

`"delivering"` sits between `"preimage-revealed"` and `"settled"`. It's a
`String`, not an enum, so nothing fails to compile — but any `switch`/`if` chain
that doesn't handle it will treat a receive as unknown/stuck in the moment right
before it settles.

### Wallet creation/import now performs a network-backed recovery scan

Unless `WalletOpenArgs.skipRecovery` is set, the open that creates the wallet
locally now runs a seed-recovery mailbox scan. Implications:

- Create/import is slower and needs network reachability to be fully effective.
- If the scan fails, `open` still succeeds and `recoveryReport()` returns `nil`.
- A restore flow should call `recoveryReport()` after open and surface
  `isComplete == false` (plus the `failed`/`foreign` buckets) to the user.

---

## 5. Migration checklist

**Hard compile errors** (only if you construct these types — mocks, fixtures,
SwiftUI previews, decoders):

- [x] Add `registered:` to every `Vtxo(...)` construction site
- [x] Add `claimDestination:` to every `LightningReceive(...)` construction site

**Silent behavior gaps:**

- [x] Handle `"delivering"` in every `LightningReceive.state` switch / comparison
      / UI status mapping
- [x] Decide whether create/import should pass `skipRecovery: true`, and if not,
      read `recoveryReport()` after open and surface incomplete recovery
      (decision: skip on fresh create, scan + log on seed import)
- [x] Don't use `claimDestination` to identify delivered receives after
      settlement — it's always `nil` there (no code relies on it)

**Optional new surface to expose** (not adopted; see completion report):

- [ ] `bolt11InvoiceForAddress` — offline/delegated Lightning receive
- [ ] `recoveryReport()` / `recoverVtxos(vtxoIds:)` — recovery UI + retry
- [ ] `refreshVtxosScheduled(vtxoIds:scheduledHeight:)` — cheaper scheduled
      refresh vs. `refreshVtxosDelegated`
- [ ] `Vtxo.registered` — surface unregistered VTXOs if useful for diagnostics

---

## 6. Verified non-changes

A symbol-level comparison of both generated files confirms:

- No public symbol present in v0.13.0 is absent in v0.14.0
- No existing method signature (name, parameter labels, types, return type)
  changed
- No struct lost a field; no enum lost a case
- New uniffi checksums added only for the four new methods; all existing
  checksums unchanged
