# VTXO Refresh Deduplication

**Status: APPROVED 2026-09-21 — code IMPLEMENTED same day (Phases 2-5;
Phase 1 partial, see below); on-device signet verification (§6) still
pending, and it is the gate that decides whether symptom 2 is actually
fixed.**

Implementation notes (2026-09-21):
- Phase 1 (**partial**): `RefreshModalView` now routes through
  `refreshVTXOsManually()`, which subsumes the refetch fix. Of the two halves
  of the parsing check, only **status** was verified statically —
  `mapMovementStatus` lowercases and handles `pending`, unknowns default to
  `.pending`; the stale status comment in `MovementData.swift` corrected. The
  **category** half is still unverified and is the one that can silently
  break the whole signal — see the §6 gate.
- Phase 2: `RefreshExclusion` (pure, unit-tested 9/9) + Guard C in both
  service paths + `WalletManager.vtxoIdsBeingRefreshed()`;
  `pendingRoundInputVtxos()` adopted on the protocol.
- Phase 3 (**with a deliberate deviation**): the orange "Refresh now" side is
  implemented as specified; the blue "Refreshing" side still keys on
  `hasActiveRefresh` (pending `.refresh` movements) rather than the full
  `vtxoIdsBeingRefreshed()` union — see §3.1.
- Manual refresh now returns a `ManualRefreshOutcome`
  (`scheduled` / `nothingToDo` / `alreadyInProgress`) and
  `refreshVTXOsManually()` throws when the service is missing. Without this,
  the modal reported success for the `isChecking` skip introduced by Phase 2 —
  a plausible tap given `start()` runs a network-bound check on every
  foreground.
- Scope decision: the Data/debug `VTXOListView` force-refresh buttons stay
  direct callers by design — they force-refresh **all** spendable VTXOs as a
  power tool, and the server's replace semantics is the point there. Not
  routed through the service, and therefore also outside the `isChecking`
  gate. Accepted cost: such a tap can strand a local pending round state that
  does not self-heal at 0.7.1 (F9). Acceptable for a debug affordance;
  it would not be for a user-facing button.

Companion to `Exit_Refresh_Coordination.md` (which coordinates refresh vs
*exit*; this doc coordinates refresh vs *refresh*). Facts below feed three
corrections back into that doc — see §7.

## 1. Problem

Two observed symptoms, one root cause:

1. **Double-scheduling.** The app can call `refreshVtxosDelegated` for VTXOs
   that already have a live delegated refresh request. Nothing app-side
   excludes them, and bark-side selection doesn't either (fact F2).
2. **"Refresh now" during an ongoing refresh.** The balance card shows the
   orange call-to-action while a refresh is already scheduled or running,
   inviting the user to trigger the duplicate manually.

Three independent writers schedule refreshes from overlapping VTXO pools:

| Writer | Selection | Trigger |
|--------|-----------|---------|
| `VTXORefreshService.checkAndRefreshVTXOs()` | `spendableVtxos()` + fee-schedule free window (+ signet 10% lifespan cap) | hourly timer; immediate check on `start()` (every foreground) |
| Manual UI (`RefreshModalView`, `VTXOListView`) | `getVtxosToRefresh()` via `BalanceRefreshStatusViewModel.vtxosNeedingRefresh` | user tap on the balance card |
| bark daemon | `get_vtxos_to_refresh()` (expiry threshold, exit depth, dust) | first attempt event of **every** round (F6) |

The windows overlap by construction: the fee-free window sits near expiry,
exactly where the daemon's `vtxoRefreshExpiryThreshold` (we pin 144 blocks)
kicks in. Root cause: the app has no notion of "this VTXO is already being
refreshed", and only bookkeeps a per-check `isChecking` flag that does
nothing across checks or writers.

## 2. Verified bark facts

Source-read at the **bark-0.7.1 tag** — the release our bark-ffi 0.24
bindings wrap — by a spike agent in the bark repository (2026-09-21; first
pass against master `bark-0.7.1-67-ge80b807ee`, then re-verified against the
tagged release). Line refs are bark-repo paths as reported by the spike.

| # | Fact | Where (bark @ 0.7.1) |
|---|------|----------------------|
| F1 | `refresh_vtxos_delegated` creates the **refresh movement at scheduling time**, `Pending` status, input VTXO ids included — before server registration | `round/mod.rs:2058-2074` |
| F2 | `get_vtxos_to_refresh()` / `spendable_vtxos()` do **not** exclude VTXOs with a pending delegated request; inputs stay spendable until the server issues the participation into a round | `lib.rs:1743-1755`, `lib.rs:2314-2320`, test `round.rs:635-657` |
| F3 | `pending_round_input_vtxos()` is **empty before issuance**; only after the round is issued are inputs locked and listed | `round/mod.rs:2410-2429`, test `round.rs:660-680` |
| F4 | A local `NonInteractivePending` round state is stored after successful server registration (movement first, round-state row second — tiny crash window with movement but no row) | `lib.rs:2279-2291`, `round/mod.rs:2146-2160` |
| F5 | On duplicate delegated requests for the same inputs, the **server deletes the older pending participation**; if the first was already issued, the second is rejected with `unusable_inputs`. No local dedupe exists | `round/mod.rs:275-288`, `round/mod.rs:1965-1977` |
| F6 | The daemon performs maintenance refresh by **interactively joining the first attempt event of every round** (`join_round_for_maintenance_refresh`); it does *not* use delegated scheduling. It creates a movement, locks inputs, and stores round state before acting — fully visible via F1/F3 signals | `daemon/mod.rs:111-125`, `lib.rs:1856-1871` |
| F7 | Pending round states are cleaned up on final Confirmed/Failed/Canceled from `sync_pending_rounds()`; sync errors leave rows persisted (retried by the daemon's periodic sync) | `round/mod.rs:2440-2505` |
| F8 | `cancel_pending_round` / `try_cancel()` **errors for `NonInteractivePending`** — a pending delegated refresh cannot be cancelled through that API | `round/mod.rs:328-340` |
| F9 | bark-0.7.1 has **no re-delegation machinery** (added later upstream): when a newer request steals inputs from an older pending participation, the older local state does not re-delegate or self-cancel — it lingers until a later sync reconciles it | release diff vs master |

### Consequences of double-scheduling on our release

Not fund loss (F5: server validates spendability and replaces rather than
double-accepting), but concretely harmful:

- duplicate `Pending` refresh movements → duplicate rows in Activity;
- orphaned local pending round states with **no self-healing** (F9) — the
  exact "lingering pending round states" identified as the race **amplifier**
  in the 2026-07-11 exit-cancellation incident
  (`Exit_Refresh_Coordination.md`);
- if the first request was already issued, the second call surfaces
  `unusable_inputs` to the user as "Refresh Failed" — for a refresh that is
  in fact running.

Prevention app-side is the only mitigation until a bindings bump picks up
upstream's re-delegation logic.

## 3. Design: one canonical "being refreshed" signal

Because one writer (the daemon) is not app code, the signal must be derived
from wallet-level state, never app-side bookkeeping. From F1/F3/F6 the
complete signal is:

```
vtxoIdsBeingRefreshed =
      input ids of pending `.refresh` movements   // covers scheduled-not-issued,
                                                  // in-round, and daemon windows (F1, F6)
    ∪ pendingRoundInputVtxos()                    // belt-and-braces for the issued
                                                  // window (F3); NOT sufficient alone
```

The movement component is **primary** — it is the only cover for the
scheduled-but-not-issued window (F3) and it is data we already fetch
(`transactions()`). `pendingRoundInputVtxos()` adoption is belt-and-braces
and could ship later without weakening the fix. An app-side "ids I already
submitted" ledger was considered and rejected: F1 makes it redundant, and it
could never see daemon activity.

Every consumer uses one `WalletManager` helper; no view-local variants.

**Safety valve — near-expiry overrides the exclusion.** F7/F9 mean a
`Pending` refresh movement can get stuck (sync error, or a replaced
duplicate with no self-healing at 0.7.1). If Guard C honored a stuck entry
forever, its VTXOs would be permanently excluded from auto-refresh and could
expire — the exact fund-loss Guard B's fail-open stance exists to prevent.
Rule: when a VTXO is inside the hard expiry threshold
(`vtxoRefreshExpiryThreshold`, ours pinned at 144 blocks), the auto-refresh
path ignores the being-refreshed exclusion and schedules anyway. Worst case
is a benign duplicate the server resolves by replacement (F5); the
alternative is a missed renewal. The card may keep showing "Refreshing" in
this state — acceptable.

**The valve is auto-path-only in practice.** As built it lives in
`RefreshExclusion`, so both service paths honour it — but the user cannot
reach it: `hasVtxosToRefresh` ANDs `!hasActiveRefresh`, so a stuck pending
movement hides the "Refresh now" button entirely, and the modal's own list
(`BalanceRefreshStatusViewModel.loadData()`) filters by the being-refreshed
set with no valve, which would disable the confirm button anyway. Net: a
near-expiry VTXO behind a stuck entry is rescued only by the hourly /
on-foreground auto check. That is sufficient to prevent expiry (the window is
144 blocks ≈ 6h on mainnet, and the check runs at least once per foreground),
so this is recorded rather than fixed.

### 3.1 Deviation: `hasActiveRefresh` stays movement-only

Phase 3 specifies blue "Refreshing" whenever `vtxoIdsBeingRefreshed()` is
non-empty. As built, that state keys on `hasActiveRefresh` — the movement
half only. Reason: `hasActiveRefresh` is a synchronous computed property read
from view bodies, and the round-input half needs an `await` on the FFI.
Wrapping it would push an async fetch into every consumer for a component
that F1 makes near-redundant (the movement is written first, at scheduling
time, so it is present whenever round inputs are locked; the only documented
divergence is F4's crash window, which goes the other way).

The asymmetry is deliberate but worth knowing: **Guard C uses the union, the
card's "Refreshing" state uses half of it.** If a case ever turns up with
locked round inputs and no pending movement, the card will under-report while
the exclusion still holds.

## 4. Plan

### Phase 1 — App-side visibility bugs (likely explains symptom 2)

Given F1, a pending refresh movement exists from the moment of scheduling,
so `hasActiveRefresh` *should* flip promptly. Two suspects on our side:

- `RefreshModalView.performRefresh()` never triggers a transaction refetch
  after scheduling (the refetch only happens via the dismiss completion's
  `manager.refresh()`). Fix: call `refreshAfterVTXOChange()` on success,
  like the auto path does.
- Verify our movement parsing keeps a scheduled-but-not-issued refresh
  movement as `.refresh`/`.pending` with `inputVtxoIds` populated
  (`TransactionService+Parsing.swift` transfer-operation path).
  Partially retired by static review (2026-09-21): identity is safe — the
  app keys transactions as `movement_<id>` (synthetic, stable across the
  pending→confirmed lifecycle, `TransactionService+Parsing.swift:217`), not
  by round txid, and `inputVtxoIds` flows movement → `TransactionData` →
  `PersistentTransaction` → `TransactionModel` intact. Two remaining checks:
  - **status-string mapping** — `MovementData.swift:13` commented the states
    as `"Pending"/"Finished"/"Failed"/"Cancelled"` while bark's wire strings
    are `pending/successful/failed/canceled`
    (`Exit_Refresh_Coordination.md` §2 fact 5). *Retired statically
    2026-09-21:* `mapMovementStatus` lowercases, handles `pending`, and
    defaults unknowns to `.pending`; comment corrected.
  - **category mapping** — still open, and the higher-risk half.
    `MovementCategory` returns `.refresh` only for
    `subsystemName == "bark.round"` **and** `subsystemKind == "refresh"`,
    `.unknown` otherwise (`MovementCategory.swift:208-219`). Every consumer —
    `hasActiveRefresh`, `vtxoIdsBeingRefreshed()`, Guard C — keys on
    `.refresh`. If a delegated refresh movement carries a different
    subsystem/kind at scheduling time, the whole signal is silently and
    permanently empty, and that alone would explain symptom 2. Resolve on
    device, not by source reading (§6).

**Verification gate:** schedule a refresh from the modal on the signet
wallet and log `transactions()`, `getVtxosToRefresh()` immediately after.
If the pending movement is there and correctly parsed, F1 holds through our
FFI and the rest of the plan proceeds unchanged.

### Phase 2 — Canonical signal + Guard C (exclusion at every scheduling site)

- `WalletManager.vtxoIdsBeingRefreshed() -> Set<String>` per §3.
- Adopt `pendingRoundInputVtxos()` in `BarkWalletProtocol` +
  `BarkWalletFFI+VTXO.swift` (thin mirror, no app policy) + `MockBarkWallet`
  stub; update `Bark_Bindings_Unadopted_API.md`.
- Exclusion, mirroring Guard B's shape **and its fail-open rationale** (on
  lookup error proceed unfiltered — a duplicate schedule is benign next to a
  missed near-expiry renewal):
  - `VTXORefreshService.checkAndRefreshVTXOs()` — alongside `exitingVtxoIds()`;
  - `VTXORefreshService.refreshManually()`;
  - `BalanceRefreshStatusViewModel.loadData()` — exclusion becomes
    **unconditional**. (Correction 2026-09-21: the `if hasActiveRefresh` gate
    this replaces was *redundant*, not the blind spot — the view-local helper
    already returned an empty set when no refresh was pending, and
    `hasVtxosToRefresh` ANDs `!hasActiveRefresh` regardless. What the change
    actually buys is the round-input half of the signal. Symptom 2 is
    Phase 1's refetch, or the unverified category mapping.)
- Consolidate the manual path: `RefreshModalView` routed through the
  service / `refreshVTXOsManually()` so selection + exclusions live in one
  place. (`VTXOListView`'s debug force-refresh deliberately stays direct —
  see scope decision in the status notes.)
- Put the manual path behind the same `isChecking` gate as the auto check —
  today `refreshManually` can interleave with an in-flight
  `checkAndRefreshVTXOs` (both suspend at awaits), and each would read a
  pre-exclusion snapshot of the other's work.

### Phase 3 — Balance card state machine

- "Refreshing" (blue) whenever `vtxoIdsBeingRefreshed()` is non-empty —
  covering the whole scheduled→issued→confirmed window, daemon included.
  (Built movement-only instead — see §3.1.)
- "Refresh now" (orange) only when refreshable VTXOs exist that are *not*
  in the being-refreshed set.
- Pending-round state isn't push-observable: the view model fetches it in
  `loadData()`; existing triggers (`transactionVersion`, `reloadTrigger`,
  30s timer) suffice once Phase 1's refetch fix lands.

### Phase 4 — Piggyback fixes in `VTXORefreshService`

- Bump `lastRefreshTime` / `autoRefreshCount` only when
  `refreshVtxosDelegated` returned a round state (today no-op runs count as
  refreshes).
- Move `requestAuthorization` out of the per-cycle notification scheduling
  path (check settings; request once) — a denied prompt is currently
  re-attempted every cycle.

### Phase 5 — Upstream + docs

- `Bark_Bindings_Feedback.md`: (a) `refresh_vtxos_delegated` /
  `get_vtxos_to_refresh` should exclude inputs with live delegated requests
  (or document the replace semantics); (b) `try_cancel` erroring on
  `NonInteractivePending` leaves no cancel path for delegated refreshes;
  (c) note the re-delegation machinery upstream as a concrete reason for the
  next bindings bump.
- Apply the §7 corrections to `Exit_Refresh_Coordination.md`.
- `Open_Follow_Ups.md` entry for anything deferred.

## 5. Tests

Extract the auto-refresh eligibility filter (vtxos × exiting ids ×
being-refreshed ids × fee window × signet lifespan cap) into a pure function
and unit-test it — today the logic is embedded in the service and untested.
Test the union logic of `vtxoIdsBeingRefreshed` with fixture transactions.

Done 2026-09-21: `RefreshExclusion` covers the **exclusion** half (exiting ×
being-refreshed × valve), 9 tests. Still untested, deliberately deferred:

- the **fee window × signet lifespan cap** half — `findVTXOsForAutoRefresh`
  remains embedded in `VTXORefreshService`. Not touched by this work, so no
  new risk, but the extraction the section asked for is only half done.
- the **union logic** of `vtxoIdsBeingRefreshed()` — it reads
  `WalletManager.transactions` and the FFI, so testing it needs a seam that
  doesn't exist yet. Its two halves are individually simple; the untested
  part is the plumbing, which the §6 gate exercises instead.

## 6. On-device verification (definition of done)

On the signet wallet (precondition: a VTXO that `getVtxosToRefresh()`
actually returns — on signet expiry is ~1 day, so either wait for one to age
into the window or fund a fresh VTXO and come back near its expiry):
1. **Phase 1 gate — parsing.** Immediately after scheduling, log the raw
   movement and the parsed model:
   `subsystemName`, `subsystemKind`, `status`, `inputVtxoIds`, and the
   resulting `category`/`status` on the `TransactionModel`. Pass = category
   `.refresh`, status `.pending`, inputs populated. **Anything else means the
   canonical signal is empty and Guard C is inert**, regardless of the unit
   tests passing — so check this one first, before the behavioural steps.
2. Tap "Refresh now" → card flips to "Refreshing" promptly and stays there
   until the round confirms; no second "Refresh now" in between. The modal
   shows "Refresh started", not "Already refreshing".
3. While the delegated request is pending, force the hourly/foreground check
   → log shows the eligible VTXOs excluded, no duplicate
   `refreshVtxosDelegated` call, no duplicate pending movement in Activity.
4. Tap "Refresh now" while a check is known to be running (e.g. immediately
   on foreground) → modal shows "Already refreshing" and no second schedule
   is issued. Confirms the `ManualRefreshOutcome` plumbing.

## 7. Corrections owed to Exit_Refresh_Coordination.md

1. **`cancelPendingRound` is not a remedy for pending delegated rounds**
   (F8) — the open force-move pre-flight item prescribes cancel-and-proceed;
   for delegated refreshes that path errors. Redesign: wait/warn instead.
2. **Daemon behavior** (F6): interactive first-attempt joins, not
   `maybe_schedule_maintenance_refresh_delegated` (facts table entry 1 is
   right, entry 6's delegated-scheduling attribution to the daemon is not,
   at our release).
3. **No re-delegation at bark-0.7.1** (F9): stale pending states from
   replaced duplicates don't self-heal — strengthens the amplifier analysis
   of the 2026-07-11 incident.
