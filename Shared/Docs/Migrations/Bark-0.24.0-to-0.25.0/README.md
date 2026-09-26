# Bark FFI Bindings Migration: v0.24.0 → v0.25.0

**Date:** 2026-09-26
**Status:** ✅ Complete 2026-09-26 — Phases 1–2 shipped same day as the docs,
chores done; see [04-completion-report.md](04-completion-report.md).
On-device first-registration check passed 2026-09-26 (30-day expiry, 15-day
renewal in X-Ray, no re-registration on the second launch). Remaining: the
day-15 renewal observation (tracked in `Open_Follow_Ups.md`).
**Bark Version:** v0.7.1 (unchanged)
**FFI Bindings Version:** v0.24.0 → v0.25.0 (resolved checkout
`157b0fcda0a0a5782ad2904ed3002a7080293047`, branch `master`; UniFFI contract
version **30, unchanged** — verified at `Bark.swift:10194`)

## Overview

A small bump with **three behavioral changes and one tightened contract**,
none of them additive-only. The theme is "stop guessing": an empty id list no
longer silently means "sweep everything", an amountless invoice no longer
reports `0`, and the mailbox authorization lifetime is now the caller's
choice instead of a baked-in 24 hours.

The four binding-level changes ([01-api-changes.md](01-api-changes.md)):

1. `drainExits` gained `drainAll: Bool` (defaulted `false` on the generated
   class). Empty `vtxoIds` with `drainAll == false` now **throws** instead of
   sweeping; ids parse all-or-nothing; well-formed but unclaimable ids are
   skipped (§1.1).
2. `mailboxAuthorization()` became `mailboxAuthorization(expirySecs: UInt32)`.
   The hex authorization cannot be revoked early (§1.2). **This parameter is
   the one Christoph requested** — the old fixed 24h expiry left many phones
   with expired relay registrations and no incoming-payment notifications.
3. `LightningReceive.amountSats` is now `UInt64?` — `nil` for an amountless
   invoice that has not settled yet (was `0`) (§1.3).
4. `CustomOnchainWalletCallbacks` contract tightened (exact-amount
   destinations, drain outputs, unchanged unsigned tx, CPFP parent, balance
   fallback) (§1.4).

## The things this repo must get right

1. **Exactly one certain compile break, two probable.** Certain:
   `BarkWalletFFI+Mailbox.swift:53` calls `wallet.mailboxAuthorization()`
   with no argument. Probable: the two `os.Logger` interpolations of
   `receive.amountSats` in `LightningClaimService.swift:165/191` (Optional
   has no `OSLogInterpolation` overload). Everything else compiles unchanged —
   the generated `drainExits` defaults `drainAll` to `false`, so the wrapper
   call at `BarkWalletFFI+Exit.swift:362` is source-compatible. The
   `drainExits` change is **semantic, not syntactic**.

2. **"Claim all" already means "claim every claimable id, explicitly".** The
   single production path is `ExitProgressionService.checkAndProgressExits`
   → `autoClaimExits` → `ExitClaimSequence.run`, which passes
   `claimableExits.map { $0.vtxoId }` behind an `!isEmpty` guard. Nothing in
   the repo passes `[]` to mean "all", so `drainAll: false` everywhere
   preserves the existing UX exactly. The only casualties are two log strings
   that print `"all"` for an empty list (`BarkWalletFFI+Exit.swift:359`,
   `MockBarkWallet.swift:516`) — now a lie, since empty throws.

3. **The mailbox renewal work is mostly already built.** `RelayRegistrationService`
   tracks `authExpiresAt`, prefers the relay-reported expiry, schedules the
   BGTask at mid-life, runs an in-process timer, and handles wake pushes.
   What is *missing* is exactly three things, and they are the substance of
   this migration:
   - **persistence** — all registration state is in-memory, so every cold
     launch re-mints (fine at 24h, wasteful at 30d);
   - **the half-window rule** — the launch gate is a 1h freshness window,
     not "renew when less than half the token's life remains";
   - **a foreground trigger** — the `.active` scenePhase handler in
     `ArkeMobile.swift:158` does not touch the relay today.

   A scenario walk (02-migration-plan.md §Scenario walk) added a fourth: the
   three existing refresh dates (BGTask "now + remaining/2", timer
   "expiry − 1h", launch "1h window") drift apart, and the BGTask one creeps
   later on every backgrounding. They collapse into one `renewalDate` at the
   midpoint of the token's *actual* reported life — which also keeps a
   relay-capped token from triggering a re-mint on every launch.

4. **30 days runs against upstream's advice, deliberately.** The upstream doc
   says "an authorization cannot be revoked early, so keep the window short."
   Christoph chose 30 days for relay-load reasons (field data: 124/151
   mailboxes had expired tokens under the 24h regime). Recorded as
   **Decided**, with the trade-off spelled out in 02-migration-plan.md §Phase 2.
   Neither the relay (`arke-apns-relay-node`, parses expiry, no cap) nor the
   Ark server (`bark-0.7.1`, expiry check only) limits the lifetime —
   verified from source 2026-09-26, so no server-side change accompanies
   this migration.

## Corrections to the pre-repo review

The review's binding-level diff is **accurate in full** — all three
signatures and the `CustomOnchainWalletCallbacks` contract were re-verified
verbatim against the resolved checkout. Its repo-impact guesses over-predict,
as in the last two bumps:

- ❌ "Any place that relied on an empty array meaning 'claim all' must pass
  `drainAll: true`." — **No such place exists.** Verified by reading every
  `drainExits` caller (there is one production chain plus a zero-caller
  `WalletManager.drainExits` pass-through). `drainAll: true` is never passed
  in the app after this migration.
- ❌ "Also check `ExitClaimWallet` (ArkeUI)." — **Wrong package.**
  `ExitClaimWallet` lives in `Shared/Services/ExitProgressionLogic.swift:20`,
  not in ArkéUI, and yes, it declares `drainExits` (line 22). It needs the
  parameter, and so does its test double `RecordingClaimWallet`
  (`ExitProgressTests.swift:479`).
- ❌ "Fix every use: formatting, sums, sorting, comparisons, view models.
  Show nil as 'Any amount' / 'Amount pending'." — **There is no UI surface.**
  Four reads exist (two debug-status strings, one JSON dump, two log lines,
  all in `BarkWalletFFI+Lightning.swift` and `LightningClaimService.swift`).
  No app model, row, sum, sort, or view model is built from
  `LightningReceive`; the two wrapper methods that format it
  (`getLightningInvoiceStatus`, `listLightningInvoices`) have **no view
  callers** on either platform. Neither string catalog has an "Any amount"
  key. Adding one with no caller would be dead on arrival — the build-time
  re-extraction deletes orphaned keys (`xcstrings-rewritten-on-build`). Plan:
  plain non-localized wording in the debug text; add a localized string only
  if a user-visible surface appears.
- ❌ "If the project implements `CustomOnchainWalletCallbacks`, check…" —
  **It doesn't.** All four `WalletOpenArgs` sites pass an
  `OnchainWallet.default(...)` instance (`WalletCreation.swift:212/482`,
  `WalletLifecycle.swift:204`). Same verified non-impact as 0.19→0.23.
- ✅ The `mailboxAuthorization` compile break is real — one site.
- ⚠️ "Renew proactively on app launch/foreground and in background refresh
  when less than half the window remains" — correct requirement, but note the
  BGTask half already exists (`backgroundRefreshDate` at
  `RelayRegistrationService.swift:188` is mid-life). Only the *decision
  rule* and *persistence* are new.

## Impact summary

- **Compile errors:** 1 certain (`BarkWalletFFI+Mailbox.swift:53`), 2
  probable (`LightningClaimService.swift:165/191`), 2 warnings
  (`BarkWalletFFI+Lightning.swift:152/214`).
- **Protocol changes:** `BarkWalletProtocol.drainExits` and
  `.mailboxAuthorization` gain a parameter each; `ExitClaimWallet.drainExits`
  likewise. Fan-out: `BarkWalletFFI`, `MockBarkWallet`, `WalletManager`
  pass-through, `RecordingClaimWallet`.
- **User-visible behavior from the recompile alone:** none — until the
  mailbox call site is fixed the app doesn't compile; once fixed with 30
  days, relay registrations stop expiring daily.
- **New behavior (planned):** persisted relay-auth expiry, half-window
  renewal on launch/foreground/BGTask, foreground scenePhase trigger.
- **New gap to record upstream:** `ExitClaimTransaction` still doesn't report
  which ids the PSBT actually includes, so "unclaimable ids are skipped" is
  invisible to `recordClaim` — see 02-migration-plan.md §Judgment calls.
- **Deferred:** nothing new from the binding surface itself.

## Documents

1. **[01-api-changes.md](01-api-changes.md)** — verified API diff with
   verbatim declarations and repo call-site inventory.
2. **[02-migration-plan.md](02-migration-plan.md)** — three phases, the
   mailbox renewal design, judgment calls with recommendations, tests,
   chores.
3. **[04-completion-report.md](04-completion-report.md)** — what landed,
   verification, deviations from the plan.

## Verification note

Bark is consumed as an SPM package (`bark-ffi-bindings` @ `157b0fc`,
`Package.resolved` change currently uncommitted in the working tree), so
bindings and binary resolve together — no matched-pair footgun.

All changed declarations were read directly from the resolved checkout's
generated `Bark.swift` (line refs in 01-api-changes.md). The claim that each
is changed *relative to 0.24.0* comes from the pre-repo old-vs-new review
plus the 0.23→0.24 doc's recorded signatures (the 0.24 `Bark.swift` was not
re-diffed). Repo-impact facts — the single `drainExits` production chain, the
absence of `[]` callers, `ExitClaimWallet`'s location, the four `amountSats`
reads and three fixtures, the no-view-caller status of the two Lightning
status methods, the `OnchainWallet.default` sites, and the in-memory-only
relay state — were verified by grep and file reads against the working tree
on 2026-09-26.

**Desktop note:** this folder adds another `README.md` / `01-api-changes.md`
/ `02-migration-plan.md` / `04-completion-report.md` set to the flat-copied
Docs folder. ArkeDesktop's build is already broken by the 0.23 and 0.24
folders for the same reason (`desktop-build-broken-duplicate-doc-basename`);
this folder needs the same Xcode-UI exclusion pass when that is fixed.
