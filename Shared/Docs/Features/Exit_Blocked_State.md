# Exit Blocked State

**Status:** Planned (2026-07-14)
**Problem:** A unilateral exit can stall because fees can't be covered right now. The app already retries automatically, but the UI shows nothing — worse, it shows "Ready to approve" for a claim that will fail. We need a user-visible "blocked" state.

## Findings (from debug session 2026-07-14)

Two distinct funding failure modes, both already reported by bark and currently dropped:

1. **Processing phase (CPFP fee-bumping).** Exit progression pays anchor-spend fees
   from the onchain wallet. If confirmed onchain balance is too low, bark returns
   `ExitError::InsufficientConfirmedFunds { needed, available }`. Bark itself treats
   this as a *wait state*, not an error (logs "Can't progress exit at this time",
   `bark/src/exit/mod.rs` ~line 583). It arrives **per-VTXO** in the
   `ExitProgressStatus.error` field returned by `progressExits`. Our FFI layer only
   logs it (`BarkWalletFFI+Exit.swift`, `progressExits`).
2. **Claim phase.** The claim fee comes out of the exit output itself. When
   `fee + P2TR_DUST > output`, `drainExits` **throws**
   `ExitError::ClaimFeeExceedsOutput { needed, output }` (`bark/src/exit/mod.rs`
   ~line 895). `ExitProgressionService.autoClaimExits` lets this bubble to the
   generic catch in `checkAndProgressExits`, which swallows it (sets `lastError`,
   retries in 5 min). The exit stays in `Claimable`, so
   `TransactionListItem.hasClaimableExit` keeps showing the "Ready to approve"
   badge (`status_ready_approve`).

Key FFI fact: both errors cross the FFI as **strings** (thiserror-formatted).
Stable markers to match on (use `contains`, not `hasPrefix` — see below):

- `"Insufficient Confirmed Funds"`
- `"Claim Fee Exceeds Output"`

The two paths deliver the string differently:

- `ExitProgressStatus.error` (`String?`, verified in the generated bindings) holds
  the raw bark `ExitError` display string — marker at the start.
- The `drainExits` throw arrives **multiply wrapped** by the time the service sees
  it: `Configuration error: Failed to drain exits: Bark.Error.Inner(message:
  "Drain exits failed: Claim Fee Exceeds Output: ...")` (verified in debug log).

So one `contains`-based classifier covers both. The messages also contain amounts
as BTC decimals, but we deliberately don't parse those — see Decisions.

Trigger for the original session: `esplora.signet.2nd.dev/fee-estimates` returned
54,464.66 sat/vB for all targets 1–25 (signet fee spam). With `feeRateSatPerVb: nil`,
bark uses its `regular` tier = esplora estimate for a 3-block target, so the ~129 vB
claim tx priced out at ~7M sats against a 39,965 sat output. Bark's refusal was correct.

## Decisions

- **Detection only, no prediction.** Classify errors after an attempt fails; don't
  duplicate bark's fee math to predict blockage. The 5-minute retry loop is the refresher.
- **Classify by prefix only; don't parse amounts out of the strings.** The friendly
  messages don't need the numbers ("network fees currently exceed this exit's value"
  is complete without them), and any amount worth showing (exit value, onchain
  balance) comes from our own data. Store the raw error string verbatim and surface
  it in the technical-details area for debugging; raw strings don't go in primary UI
  (developer English, bypasses localization catalogs).
- **Don't touch `ExitStatusParser` / `ParsedExitState`.** They mirror bark's state
  machine. Blocked is an app-level overlay derived at the view level.
- **Debounce:** only surface the badge after 2 consecutive blocked checks (~5 min
  apart) to avoid flapping on a single bad fee estimate.
- **Keep retrying silently.** Blocked is informational, not an error state.
- Message by actionability:
  - Insufficient onchain funds → actionable: "needs ~X sats onchain to continue".
  - Claim fee exceeds output → wait-it-out: "network fees currently exceed this
    exit's value; retrying automatically". No action button.

## Plan

### Phase 1 — Capture & classify — DONE 2026-07-14
- [x] `ExitBlockedReason` enum: `.insufficientOnchainFunds`,
      `.claimFeeExceedsOutput`, `.other` — matched by `contains`, no amount
      parsing; raw error string kept in `ExitBlockedInfo`
      (`Shared/Data/ExitStatus/ExitBlockedInfo.swift`).
- [x] `ExitProgressionService.checkAndProgressExits`: classifies per-VTXO
      `status.error` from `progressExits`; catches `drainExits` errors around
      `autoClaimExits` and records per claimable VTXO.
- [x] Fix: a claim failure no longer aborts steps 4–6 (`syncExits`, cache
      invalidation, Live Activity update).
- [x] Manual path `progressExitsManually` feeds the same classifier. (No manual
      claim UI exists — auto-claim is the only claim path; verified.)
- [x] Clear blocked info on success — **phase-scoped** (see note below).

**Implementation note — `ExitBlockedPhase` (.progression / .claim):** records
carry the phase that failed, and a successful progression only clears
progression-phase records. Without this, the common fee-spike case breaks the
debounce: progression *succeeds* every check (exit sits at Claimable) while the
claim fails, so an unscoped clear would reset the claim record's attempt count
each cycle and it would never reach the 2-attempt threshold. A successful claim
clears any record (the exit is over).

### Phase 2 — Store & expose (in-memory part DONE 2026-07-14)
- [x] Parallel map on WalletManager alongside `cachedExitStatuses`:
      `exitBlockedInfoByVtxoId` (declared in `WalletManager.swift`, accessors in
      `WalletManager+Exits.swift`). Bumps `dataVersion` on change.
- [ ] Persist in `PersistentExitCache` so the state survives relaunch (exit cache
      loads before wallet init — the misleading badge in the original session came
      from cache). Schema check done: all existing fields are defaulted/optional,
      so adding optional blocked fields (reason raw value, raw error string,
      blockedSince, attempt count) is a lightweight migration.
- [x] Accessor `getExitBlockedInfo(for:)` mirroring `getCachedExitStatus(for:)`,
      with the 2-consecutive-checks debounce applied there (via
      `ExitBlockedInfo.isSurfaceable`).

### Phase 3 — Surface in UI — DONE 2026-07-14
- [x] `TransactionModel.exitBlockedInfo` added in
      `TransactionModel+WalletManager.swift` (matches VTXOs via `inputVtxoIds` —
      exit movements carry their VTXOs there, `exitedVtxoIds` is empty for them).
- [x] `TransactionListItem` (Shared, used by both platforms' lists): blocked wins
      over claimable — orange clock badge replaces the blue "Ready to approve".
- [x] `TransactionClaimExitBanner` (iOS): optional `blockedInfo` parameter, shows
      a localized explanation line under the progress bar; passed from
      `TransactionDetailView_iOS`.
- [x] `TransactionTechnicalDetailsView` (iOS): raw error string row with reason,
      attempt count, and copy button.
- [x] Live Activity: `updateLiveActivity` overrides `stepDescription` with a
      paused message when blocked (plain English, like the file's other widget
      strings — Live Activity content isn't routed through catalogs).
- [x] Localization: 6 new keys in Shared catalog (3 badge, 3 explanation), added
      with explicit values; verified intact after build re-extraction.

Skipped deliberately:
- `ActiveExitAlertView_iOS` is referenced nowhere (dead code) — not extended.
- Desktop `TransactionDetailView` has no exit section at all; the shared list
  badge covers macOS. Building a desktop exit detail section is separate work.

### Phase 4 — Tests (classifier part DONE 2026-07-14)
- [x] Classifier unit tests (raw + wrapped messages, unknown fallback) and
      `isSurfaceable` debounce threshold — `Tests/Shared/ExitBlockedInfoTests.swift`,
      6/6 passing on iOS simulator.
- [ ] Record/clear semantics on WalletManager (phase scoping, count reset on
      reason change) — needs a WalletManager test seam or extraction; revisit
      with Phase 2 persistence.

## Post-implementation observations (2026-07-14, second device run)

The original repro self-resolved before the UI could be exercised: the esplora's
3-block target (bark's `regular` tier) dropped to ~2 sat/vB while targets 4–25
stayed spammed at ~56k, and a retry claimed the exit for ~260 sats (onchain
balance 53,110 → 92,815 = +39,705 = 39,965 − fee). The "wait it out" design
worked; the blocked code correctly recorded nothing. **On-device verification of
the badge is still pending** — likely repro: the target-3 estimate spiking again.

Two pre-existing subtleties noticed while reading the post-claim log:

- **Transient balance double-count** right after a claim: the claimed output is
  already in the onchain balance while `pendingExitsTotalSats` still reports the
  exit amount and the movement stays `pending` until bark's reconcile runs.
  Watch for it persisting across sessions.
- **`ClaimInProgress` is invisible to `checkAndProgressExits`** — FIXED
  2026-07-14: the early-return gates in `checkAndProgressExits` and
  `progressExitsManually` now also check `getExitVtxos()` for
  `isClaimInProgress` exits, so the service performs the final
  `ClaimInProgress → Claimed` transition itself instead of relying on the bark
  daemon. Deliberately narrow (not "any unclaimed exit") so terminal states
  like vtxoAlreadySpent don't trigger perpetual re-progression.

## Out of scope (deliberately)

- Predicting blockage before an attempt.
- Passing explicit/clamped fee rates to `drainExits` (separate decision; nil =
  bark-internal estimation is the documented contract).
- Typed errors across the FFI (would remove string parsing; nice-to-have if the
  bindings ever expose them).
- Notifications for persistent blockage (revisit after the badge ships).
