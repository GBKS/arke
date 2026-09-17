# Bark FFI Bindings Migration: v0.23.0 → v0.24.0

**Date:** 2026-09-17
**Status:** ✅ Complete 2026-09-17 — Phase 1 + Phase 2 (approved
foreign-retry) shipped, chores done; see
[04-completion-report.md](04-completion-report.md). Remaining: opportunistic
on-device import smoke (tracked in `Open_Follow_Ups.md`)
**Bark Version:** v0.7.0 → v0.7.1
**FFI Bindings Version:** v0.23.0 → v0.24.0 (resolved checkout
`788c6f22946a77e46b918b23fdca84b07bb7285f`, branch `master`; UniFFI contract
version **30, unchanged** — verified at `Bark.swift:10045`)

## Overview

A small, additive bump themed around the **VTXO key gap limit**: the run of
consecutive unused seed-derived key indices a scan crosses before concluding a
VTXO isn't ours. The hardcoded limit of 50 became a configurable
`Config.vtxoKeyGapLimit` defaulting to **250**, per-call `gapLimit` overrides
appeared on import/recovery, and a batch `importVtxos` method was added.
Nothing was removed or renamed.

Five binding-level changes ([01-api-changes.md](01-api-changes.md)):

1. `importVtxo` gained `args: ImportVtxoArgs? = nil` (§1.1).
2. New `importVtxos(encodedVtxos:args:) -> [String]` batch method + new
   `ImportVtxoArgs` struct, all fields defaulted (§1.2).
3. `recoverVtxos` gained `gapLimit: UInt32? = nil` (§1.3).
4. `Config` gained `vtxoKeyGapLimit: UInt32?` — **no default in the memberwise
   init** (§1.4).
5. `WalletOpenArgs.onchain` lost its `= nil` default (§1.5).

Plus two new free functions, `defaultVtxoKeyGapLimit()` (→ 250) and
`maxVtxoKeyGapLimit()` (→ 100_000) (§2).

## The things this repo must get right

1. **Exactly one compile break.** The single `Config(...)` construction site —
   `makeConfig` at `BarkWalletFFI+Configuration.swift:234` — needs
   `vtxoKeyGapLimit: nil` added. That is the entire Phase 1. Everything else
   compiles unchanged:
   - `importVtxo`: `BarkWalletFFI` has its own one-arg wrapper
     (`BarkWalletFFI+VTXO.swift:466`) that calls the generated method, whose
     new `args:` defaults to `nil`. `BarkWalletProtocol.swift:83` is satisfied
     by the *wrapper*, not the generated class, so protocol, wrapper, and
     `MockBarkWallet.swift:482` all still line up.
   - `recoverVtxos`: one call site (`BarkWalletFFI+WalletCreation.swift:613`),
     compiles via the `gapLimit: UInt32? = nil` default.
   - `WalletOpenArgs`: all four construction sites
     (`WalletLifecycle.swift:253`, `WalletCreation.swift:202/474/558`) already
     pass `onchain: builtInWallet` explicitly. The lost default breaks nothing.

2. **The recompile alone changes behavior: gap limit 50 → 250.** Passing
   `vtxoKeyGapLimit: nil` opts into the new library default of 250 (was a
   hardcoded 50). This affects the seed-recovery scan — which in our
   architecture runs **only on the import-from-mnemonic path** (the
   `created_now` gate; see `Launch_Sequence_Contract.md`) — and the ownership
   scan inside `importVtxo`. Wider limit = fewer VTXOs misclassified as
   `foreign`, at the cost of slower no-match scans. We accept the new default
   deliberately; it is the fix for the `foreign` misclassification our
   0.13→0.14 docs complained about.

3. **The `gapLimit` override on `recoverVtxos` is the real prize.** The
   0.13→0.14 migration doc (`01-api-changes.md` §RecoveryReport) recorded that
   `foreign` ids "need a wider gap limit, not a retry" — impossible then. Now
   possible: after the existing `failed`-ids retry at
   `WalletCreation.swift:613`, a second pass over `report.foreign.vtxoIds`
   with a widened `gapLimit` can rescue a wallet's own VTXOs keyed beyond the
   scan horizon. This is a **proposal**, not decided — see
   [02-migration-plan.md](02-migration-plan.md) Phase 2.

## Corrections to the pre-repo review

The review's binding-level diff is **accurate in full** — every signature was
re-verified verbatim against the resolved checkout (see
[01-api-changes.md](01-api-changes.md)). Its repo-impact guesses repeat the
0.19→0.23 pattern of predicting breaks we don't have:

- ❌ "`BarkWalletProtocol.swift:83` … will no longer match the conforming
  type's method and needs updating." — **Wrong.** It assumes the generated
  class conforms to the protocol directly. It doesn't; `BarkWalletFFI`'s
  one-arg wrapper satisfies the protocol and itself compiles via the new
  parameter's `nil` default. Zero breaks.
- ❌ "`WalletOpenArgs(...)` calls that omitted `onchain:` will fail to
  compile." — **None exist.** All four sites pass it explicitly.
- ❌ "Search for hardcoded '50' gap-limit references in comments/UI/tests." —
  **Swept; nothing to update.** The only bark-specific "50" mentions are in
  the historical `Migrations/Bark-0.13.0-to-0.14.0` docs, which we don't
  rewrite. Every other gap-limit hit in the repo is the unrelated BIP44
  *address* gap limit (20) in `AddressService`.
- ⚠️ "Add `importVtxos` … if the app currently imports VTXOs one at a time in
  a loop." — **It doesn't.** `WalletManager.importVtxo`
  (`WalletManager+Operations.swift:348`) has zero callers today; there is no
  loop to convert. Batch import is Unadopted-API material, not migration work.
- ✅ The `Config.vtxoKeyGapLimit` compile break is real — one site, as
  predicted.

## Impact summary

- **Compile errors:** exactly **one** — `makeConfig` at
  `BarkWalletFFI+Configuration.swift:234`. Fix: add `vtxoKeyGapLimit: nil`.
- **User-visible behavior from the recompile:** import-from-mnemonic recovery
  scans get wider (50 → 250) and can take somewhat longer; fewer own-VTXOs
  land in `foreign`.
- **New-API adoption (proposed):** `foreign`-ids retry with widened
  `gapLimit` in the import recovery path.
- **Deferred:** `importVtxos` batch, `ImportVtxoArgs` knobs
  (`skipStatusCheck`, `allowPartial`), protocol mirroring of the new
  parameters, gap-limit free functions → `Bark_Bindings_Unadopted_API.md` +
  `Open_Follow_Ups.md`.
- **Build result:** ✅ green after the one-line fix (2026-09-17, active
  scheme; no other errors surfaced, confirming the single-break analysis).

## Documents

1. **[01-api-changes.md](01-api-changes.md)** — verified API diff with
   verbatim declarations and repo call-site inventory.
2. **[02-migration-plan.md](02-migration-plan.md)** — the one Phase 1 edit,
   the Phase 2 foreign-retry proposal, deferred items, and test strategy.
3. **04-completion-report.md** — to be written when the work lands.

## Verification note

Unlike 0.19→0.23 there is **no matched-pair footgun**: Bark is consumed as an
SPM package (`bark-ffi-bindings` @ `788c6f2`), so bindings and binary resolve
together. Several FFI checksums moved (`importVtxo`, `importVtxos`,
`recoverVtxos`, plus the two new free functions), but SPM makes a mismatch
impossible; a `uniffiEnsureInitialized` failure would indicate a stale
DerivedData package graph, fixed by a clean resolve.

All new/changed declarations were read directly from the resolved checkout's
generated `Bark.swift` (line refs in 01-api-changes.md). The claim that each
is new *relative to 0.23.0* comes from the pre-repo old-vs-new diff review
(the 0.23 `Bark.swift` was not re-diffed here). Repo-impact facts —
construction-site counts, the wrapper architecture, `WalletOpenArgs` explicit
arguments, the zero-caller status of `WalletManager.importVtxo`, the "50"
sweep — were verified directly by grep against the working tree on
2026-09-17.
