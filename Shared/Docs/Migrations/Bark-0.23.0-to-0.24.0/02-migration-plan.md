# Migration Plan: Bark FFI v0.23.0 → v0.24.0

Companion to [01-api-changes.md](01-api-changes.md). Phase 1 is a one-line
edit; the substance of this bump is the Phase 2 decision.

## Phase 0 — Package sanity (already done)

`Package.resolved` already points at `bark-ffi-bindings` revision `788c6f2`
(branch `master`), and the resolved `Bark.swift` carries the 0.24 surface.
Bark is an SPM package, so bindings and binary resolve as a pair — no manual
xcframework swap, no checksum-mismatch risk beyond a stale DerivedData
package graph (clean resolve if `uniffiEnsureInitialized` ever fatals).

## Phase 1 — Fix the one compile break

**`BarkWalletFFI+Configuration.swift`, `makeConfig` (line 234):** append the
new trailing parameter to the `Config(...)` construction:

```swift
userAgent: userAgent,  // e.g. "arke-ios/17" (v0.11+)
vtxoKeyGapLimit: nil  // Use default (250, v0.24+; was hardcoded 50 pre-0.24)
```

That is the entire phase. Do **not** go hunting for other breaks — the
review's other predicted breaks were verified absent (README §Corrections):
`importVtxo` is insulated by the app's wrapper, all `WalletOpenArgs` sites
pass `onchain:` explicitly, `recoverVtxos` compiles via its default.

**Deliberate behavior change to acknowledge, not code around:** `nil` now
means a gap limit of 250 instead of 50. Effects:

- Import-from-mnemonic is the only path that runs the seed-recovery scan
  (`created_now` gate — `Launch_Sequence_Contract.md`); its scan gets wider
  and possibly slower, and fewer own-VTXOs should land in `foreign`.
- The ownership scan inside `importVtxo` widens identically.
- Wallet create/open elsewhere is unaffected (scan suppressed by design).

We want this. Pinning 50 to "preserve behavior" would preserve the bug the
0.13→0.14 docs recorded (own VTXOs beyond index 50 misclassified as
`foreign`).

**Verification:** build both platforms. No logic changed → no scoped test run
needed (lean workflow); the mobile suite runs at end of task as usual.

## Phase 2 — PROPOSAL: retry `foreign` ids with a widened gap limit

> Status: **approved and shipped 2026-09-17** — Christoph approved the
> recommendation (`maxVtxoKeyGapLimit()`); see 04-completion-report.md for
> what landed, including one deviation note on report merging.

**Context.** The import recovery path
(`BarkWalletFFI+WalletCreation.swift:600–640`) currently:
1. runs the open-time recovery scan,
2. retries `report.failed.vtxoIds` once via `recoverVtxos` (line 613),
3. merely logs `report.foreign.vtxoIds` (line 634) — because until 0.24 there
   was nothing to do about them.

`foreign` means "no matching key derivable within the gap limit". For a
mailbox/import scan these are most likely this wallet's own VTXOs keyed
beyond the horizon. 0.24 makes them recoverable: pass a wider `gapLimit` to
`recoverVtxos`.

**Proposed shape.** After the existing `failed` retry, one extra pass:

```swift
if !report.foreign.vtxoIds.isEmpty {
    let rescued = try await wallet.recoverVtxos(
        vtxoIds: report.foreign.vtxoIds,
        gapLimit: maxVtxoKeyGapLimit()  // 100_000 — see trade-off below
    )
    // merge rescued into the report the same way the failed-retry does
}
```

**The open decision — how wide:**

| Option | Pros | Cons |
|--------|------|------|
| `maxVtxoKeyGapLimit()` (100_000) | Never misses an own-VTXO; principled ceiling from the library | A scan that matches nothing runs the limit to its end — worst-case slow, and *every* genuinely-foreign id pays it |
| Fixed multiple, e.g. `4 × defaultVtxoKeyGapLimit()` (1000) | Bounded cost | Arbitrary; still misses pathological wallets |

Import-from-mnemonic is a rare, user-initiated, "thorough beats fast" flow,
and the pass only runs when `foreign` is non-empty — so the recommendation is
`maxVtxoKeyGapLimit()`. But note the true-foreign case (e.g. a VTXO genuinely
belonging to someone else in the mailbox) pays the full no-match scan.

**Scope notes:**

- This stays inside `BarkWalletFFI` — no `BarkWalletProtocol` change needed;
  the protocol exposes the recovery *outcome*, not the scan mechanics.
- Tests: extend `ImportRecoveryLogicTests` with a foreign-ids-rescued case
  and a still-foreign-after-widening case.
- The existing log line at `WalletCreation.swift:634` ("possibly beyond gap
  limit") becomes conditional on the widened pass also failing.

## Deferred (record in Open_Follow_Ups.md + Bark_Bindings_Unadopted_API.md)

1. **`importVtxos` batch + `ImportVtxoArgs` knobs** — no import loop exists
   in the app today (`WalletManager.importVtxo` has zero callers). Adopt when
   a multi-VTXO import feature (e.g. mailbox batch receive) appears; batch
   does one key scan + one write, and `allowPartial: true` plus the returned
   kept-ids list is the natural retry contract for it.
2. **Protocol mirroring of `args:` / `gapLimit:`** — `BarkWalletProtocol`
   mirrors the FFI, so widening `importVtxo(vtxoBase64:args:)` on the
   protocol would be consistent; but no caller passes them yet, and the
   protocol change fans out to `MockBarkWallet` and the wrapper for zero
   current benefit. Mirror when the first real caller needs a non-default.
3. **`defaultVtxoKeyGapLimit()` / `maxVtxoKeyGapLimit()`** — no
   user-configurable gap limit exists; adopt as validation bounds if one is
   ever surfaced in settings (and `maxVtxoKeyGapLimit()` immediately if the
   Phase 2 proposal is approved).

## Execution order

1. Phase 1 edit + build both platforms green.
2. Christoph decides Phase 2 (yes/no + gap-limit width).
3. If approved: Phase 2 implementation + `ImportRecoveryLogicTests` additions.
4. Chores: `Bark_Bindings_Unadopted_API.md` bump-baseline update,
   `Open_Follow_Ups.md` deferrals, `04-completion-report.md`.
5. Mobile test suite batch run at end of task.
