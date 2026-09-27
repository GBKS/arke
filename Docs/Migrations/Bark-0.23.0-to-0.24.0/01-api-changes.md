# API Changes: Bark FFI v0.23.0 → v0.24.0

All declarations below were read verbatim from the resolved checkout's
generated `Bark.swift` (revision `788c6f2`); line numbers refer to that file.
Repo call-site facts verified by grep on 2026-09-17.

## 1. Changed / new API

### 1.1 `importVtxo` gained an `args` parameter

```swift
// Old (0.23)
open func importVtxo(vtxoBase64: String) async throws

// New (0.24) — Bark.swift:3228
open func importVtxo(vtxoBase64: String, args: ImportVtxoArgs? = nil) async throws
```

Upstream doc notes: the VTXO is stored in the state the server reports for it
(an already-spent one is recorded as spent rather than refused), and despite
the historical `vtxoBase64` parameter name, hex as returned by `vtxoEncoded`
is accepted too.

**Repo impact: none.** The generated default keeps the single FFI call site
(`BarkWalletFFI+VTXO.swift:481`) source-compatible, and the app's own one-arg
wrapper (`BarkWalletFFI+VTXO.swift:466`) is what satisfies
`BarkWalletProtocol.swift:83` and what `MockBarkWallet.swift:482` mirrors.
`WalletManager.importVtxo` (`WalletManager+Operations.swift:348`) currently
has **zero callers**.

### 1.2 New batch method `importVtxos` + new struct `ImportVtxoArgs`

```swift
// Bark.swift:3254
open func importVtxos(encodedVtxos: [String], args: ImportVtxoArgs? = nil) async throws -> [String]
```

Imports several VTXOs under a **single key scan and a single write** — the
reason it exists rather than being a loop over `importVtxo`. Returns the ids
now held (stored by this call or already present), so a failed batch can be
retried. One failing VTXO discards the whole batch unless `allowPartial`.

```swift
// Bark.swift:5812 — every field defaulted in the init
public struct ImportVtxoArgs: Equatable, Hashable {
    /// Gap limit for the ownership key scan, overriding
    /// Config.vtxoKeyGapLimit for this call. Default: nil (use configured).
    public var gapLimit: UInt32?
    /// Import as spendable without asking the server for each VTXO's state.
    /// Faster, but can leave spent VTXOs marked spendable, which then fail
    /// when selected as inputs. Default: false.
    public var skipStatusCheck: Bool
    /// Keep the VTXOs that import successfully when another in the batch
    /// fails; the returned ids are the ones kept. Default: false.
    public var allowPartial: Bool
}
```

**Repo impact: none required.** No import loop exists to convert (§1.1).
Record on `Bark_Bindings_Unadopted_API.md`.

### 1.3 `recoverVtxos` gained a `gapLimit` parameter

```swift
// Old (0.23)
open func recoverVtxos(vtxoIds: [String]) async throws -> RecoveryReport

// New (0.24) — Bark.swift:3827
open func recoverVtxos(vtxoIds: [String], gapLimit: UInt32? = nil) async throws -> RecoveryReport
```

Upstream doc, verbatim: *"`gap_limit` overrides `Config.vtxo_key_gap_limit`
for the key scan that decides which of `vtxo_ids` this wallet owns. Widen it
to reach ids a previous scan bucketed as `foreign`."* That is exactly the
capability our 0.13→0.14 doc recorded as missing (`foreign` ids "need a wider
gap limit, not a retry").

**Repo impact: compiles unchanged** at the one call site,
`BarkWalletFFI+WalletCreation.swift:613` (the `failed`-ids retry inside the
import recovery path; `foreign` ids are currently only logged at line 634).
Not on `BarkWalletProtocol`. Adoption proposal in 02-migration-plan.md §Phase 2.

### 1.4 `Config` gained `vtxoKeyGapLimit: UInt32?` — no init default ⚠️

```swift
// Bark.swift:4871; init parameter at 4888 — NO default value
public var vtxoKeyGapLimit: UInt32?
```

Upstream doc: *"Default: 250. Capped at 100_000; a higher value is rejected
when the wallet is opened or created."* `nil` means the library default —
which is **250, up from the previously hardcoded 50**, so a plain recompile
already widens every ownership/recovery scan.

**Repo impact: the one compile break.** Single construction site: `makeConfig`
at `BarkWalletFFI+Configuration.swift:234`. Fix: append
`vtxoKeyGapLimit: nil  // Use default (250, v0.24+)` after `userAgent`.

### 1.5 `WalletOpenArgs.onchain` lost its `= nil` default

```swift
// Old (0.23)
onchain: OnchainWallet? = nil

// New (0.24) — Bark.swift:7272 — required at every construction
onchain: OnchainWallet?
```

**Repo impact: none.** All four construction sites already pass
`onchain: builtInWallet` explicitly:
`BarkWalletFFI+WalletLifecycle.swift:253`,
`BarkWalletFFI+WalletCreation.swift:202`, `:474`, `:558`.

## 2. New free functions

```swift
// Bark.swift:9932 — default for Config.vtxoKeyGapLimit (250)
public func defaultVtxoKeyGapLimit() -> UInt32

// Bark.swift:9973 — largest accepted vtxoKeyGapLimit / gapLimit override
// (100_000). "A scan that matches nothing runs the limit to its end, so an
// unbounded limit is unbounded work."
public func maxVtxoKeyGapLimit() -> UInt32
```

Useful for validating any future user-configurable gap limit, and as the
principled ceiling for a `foreign`-retry override. No current call sites
needed.

## 3. Doc-only change

`RecoveryReport.foreign`'s doc comment now describes the gap limit as the
*configured* run of consecutive unused key indices (250 by default) instead of
the old hardcoded "50 consecutive unused indices". Repo sweep for stale "50"
references found none outside the historical 0.13→0.14 migration docs (left
as-is — they were correct when written). All other "gap limit" hits in the
repo are the unrelated BIP44 onchain-address gap limit (20) in
`AddressService`.

## 4. Verified non-changes

- UniFFI contract version stays **30** (`Bark.swift:10045`) — no
  scaffolding-wide changes.
- No method, struct, or enum that `BarkWalletProtocol` declares changed other
  than as listed above; the remaining diff is uniffi-internal plumbing
  (`FfiConverterOptionTypeImportVtxoArgs`, moved API checksums for the five
  touched/new symbols).

## 5. Migration checklist

- [x] Phase 1: `vtxoKeyGapLimit: nil` in `makeConfig`
      (`BarkWalletFFI+Configuration.swift:234`) — done 2026-09-17
- [x] Build green (active scheme, 2026-09-17; desktop deliberately unchecked
      per current lean workflow)
- [x] Decide Phase 2 foreign-retry proposal — approved and shipped
      2026-09-17 with `maxVtxoKeyGapLimit()` (02-migration-plan.md)
- [x] Update `Bark_Bindings_Unadopted_API.md` — done 2026-09-17 (baseline →
      v0.24.0, incl. 0.23 catch-up section)
- [x] Record deferrals in `Open_Follow_Ups.md` — done 2026-09-17
- [x] Write 04-completion-report.md — done 2026-09-17
