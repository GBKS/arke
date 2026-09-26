# VTXO Refresh Deduplication

**Status: APPROVED 2026-09-21 — code IMPLEMENTED same day (Phases 2-5;
Phase 1 partial, see below); on-device signet verification (§6) still
pending, and it is the gate that decides whether symptom 2 is actually
fixed.**

Implementation notes (2026-09-21):
- Phase 1 (**partial**): `RefreshModalView` now routes through
  `refreshVTXOsManually()`, and `refreshAfterVTXOChange()` republishes into
  the unified transaction list — without that second half the refetch never
  reached the readers and Guard C's primary signal was inert (details in the
  §4 Phase 1 note). Of the two halves
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
  the modal reported success for the `isChecking` skip introduced by Phase 2.
  (Correction 2026-09-21: originally justified as "a plausible tap given
  `start()` runs a check on every foreground" — the check is per *launch*,
  so this is a cold-launch race, not a foreground one. Narrower than
  claimed, but the modal still must not report a refresh it didn't start.)
- Scope decision: the three Data/debug force-refresh paths stay direct
  callers by design (`VTXOListView` ×2 platforms,
  `VTXODeveloperActionsView`, `DataView_iOS`'s `maintenanceDelegated()` —
  full list in §3.2). They force the server's hand as a power tool, and the
  replace semantics is the point there. Not routed through the service, and
  therefore also outside the `isChecking` gate. Accepted cost: such a tap can
  strand a local pending round state that does not self-heal at 0.7.1 (F9).
  Acceptable for a debug affordance; it would not be for a user-facing
  button.
- `refreshAfterVTXOChange()` now republishes the unified transaction merge —
  see the §4 Phase 1 note. Pre-existing staleness bug, but Guard C's primary
  signal depended on it.

Companion to `Exit_Refresh_Coordination.md` (which coordinates refresh vs
*exit*; this doc coordinates refresh vs *refresh*). Facts below feed three
corrections back into that doc — see §8.

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
| `VTXORefreshService.checkAndRefreshVTXOs()` | `spendableVtxos()` + fee-schedule free window (+ signet 10% lifespan cap) | immediate check on `start()` — **once per app launch**, from `performInitialization()` — then an hourly `Timer` |
| Manual UI (`RefreshModalView`, `VTXOListView`) | `getVtxosToRefresh()` via `BalanceRefreshStatusViewModel.vtxosNeedingRefresh` | user tap on the balance card |
| bark daemon | `get_vtxos_to_refresh()` (expiry threshold, exit depth, dust) | first attempt event of **every** round (F6) |

"Three" counts *classes* of writer; the manual-UI row covers four distinct
app-side call sites, of which two end up gated — enumerated in §3.2.

The windows overlap by construction: the fee-free window sits near expiry,
exactly where the daemon's `vtxo_refresh_expiry_threshold` kicks in. We do
**not** pin that value — the FFI config passes `nil` ("use defaults"), so it
is bark's default; 144 blocks is the figure our own code mirrors
(`RefreshExclusion.hardExpiryThresholdBlocks`,
`ArkConfigModel.vtxoRefreshThresholdBlocks`), pinned against drift by a test
but not actually under our control. Root cause: the app has no notion of
"this VTXO is already being refreshed", and only bookkeeps a per-check
`isChecking` flag that does nothing across checks or writers.

**Check cadence (corrected 2026-09-21 — earlier text here said "every
foreground", which is wrong).** `vtxoRefreshService.start()` is called once
from `WalletManager.performInitialization()`, so the immediate check runs
**per app launch**, not per foreground: no `.active` /
`willEnterForeground` handler touches the service, and
`triggerVTXORefreshCheck()` has no caller anywhere in the app. After launch
only the hourly `Timer` fires, and a main-run-loop timer doesn't fire while
the app is suspended. `stop()` happens only on wallet deletion / migration
reset. Net cadence: **once per launch, then hourly while not suspended.**
This matters both for reasoning about how often a check races another
writer, and for how to force a check during device verification (§6).

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
  in fact running. **Fixed 2026-09-21:** `ManualRefreshOutcome
  .alreadyIssuedByServer` maps this to "Already refreshing", and the auto
  path stops recording it in `lastError`. Detection is by message text
  (`isAlreadyIssuedRejection`) because the FFI collapses every `Bark.Error`
  into `BarkWalletFFIError.configurationError(_:)` and discards the variant
  — deliberately narrow, anything unrecognised stays an error. Surfacing
  typed FFI errors is an Open_Follow_Ups item.

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
near-expiry VTXO behind a stuck entry is rescued only by the auto check.

Whether that suffices depends on the real cadence, which is **once per app
launch, then hourly while not suspended** (see §1 — the earlier claim of
"at least once per foreground" was wrong). Against a 144-block window
(≈24h on mainnet, ≈6h on signet) an hourly foreground check clears it
easily, and any launch does too. The residual case is an app left suspended
for the whole window with no launch — then nothing fires. Recorded rather
than fixed: the user-visible fallback is that a stuck entry keeps the card
on "Refreshing", and the UI offers no manual override.

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

### 3.2 Signal completeness ≠ gating completeness

Two different claims, easy to conflate:

- **Signal** is writer-complete. F1 means bark writes the movement at
  scheduling time, so `vtxoIdsBeingRefreshed()` sees *any* writer's work,
  including ones this app doesn't route.
- **Gating** is not. Five app-side sites can schedule a refresh; two consult
  the signal:

| Site | Consults Guard C |
|------|------------------|
| `VTXORefreshService.checkAndRefreshVTXOs()` | yes |
| `VTXORefreshService.refreshManually()` (balance modal) | yes |
| `VTXOListView.swift` + `VTXOListView_iOS.swift` force-refresh | no |
| `VTXODeveloperActionsView.swift` single-VTXO `refreshVtxoDelegated` | no |
| `DataView_iOS.swift` `maintenanceDelegated()` | no |

All three ungated sites are Data/debug surfaces, and the scope decision in
the status notes covers them: they exist to force the server's hand, and the
replace semantics is the point. Recorded here because the decision was
originally written as if `VTXOListView` were the only one.

`maintenanceDelegated()` is the notable one — it's bark-side selection
(`maybe_schedule_maintenance_refresh_delegated`), so it can schedule VTXOs we
never saw. Fine for a debug button, not fine if it ever moves to a
user-facing surface.

**Prerequisite for the signal to work at all:** `vtxoIdsBeingRefreshed()`
reads `WalletManager.transactions`, i.e. the unified service's *stored*
merge. `refreshAfterVTXOChange()` must republish it (it calls
`mergeTransactions()`); the Ark-only `transactionService.refreshTransactions()`
alone does not, and for a while didn't — see the §4 Phase 1 note.

Two further conditions, both found on review 2026-09-21 and both fixed:

- **Read-your-own-writes.** `TransactionService.refreshTransactions()` runs
  through `TaskDeduplicationManager`, which *joins* an in-flight task rather
  than starting a new one. A refresh started before our write would satisfy
  the call with pre-write data. Real producers of the `"transactions"` key:
  `WalletNotificationService` on a bark event (the likeliest, since round
  progression emits them), `performRefresh()`'s task group at launch, any
  pull-to-refresh, and `WalletManager+Notifications`' push-driven
  `refresh()`. (Correction 2026-09-21: an earlier draft said
  "`performRefresh()`'s task group on foreground" — no foreground path calls
  `refresh()`; the app-level triggers are launch, pull-to-refresh, and
  notifications.)
  `refreshAfterVTXOChange()` now uses `refreshTransactionsAfterWrite()` →
  `TaskDeduplicationManager.executeFresh`, which drains any in-flight task
  and then fetches fresh. Draining rather than bypassing matters:
  `upsertTransactionsFromServerData` awaits mid-loop while holding a
  pre-fetched snapshot, so two concurrent runs could both insert the same row.
- **The error path writes too.** Per F1 bark creates the `Pending` movement
  *before* server registration, so a throw from `refreshVtxosDelegated` can
  (Fixed 2026-09-24: the drained task's own `execute` creator used to remove
  the key unconditionally on completion, deregistering the still-running
  fresh task — so an `execute` arriving during the fresh run started a
  concurrent one, the exact double-insert hazard the drain exists to prevent.
  Both `execute` variants now remove the key only if it is still their own
  task; pinned by `executeJoinsFreshTaskAfterDrain`.)
  leave a movement behind. Both paths now refetch before propagating —
  scoped to the scheduling call, so read-only failures earlier in the check
  (e.g. offline) don't trigger an hourly refetch. Without this, a failed
  schedule left the app blind to a lingering `Pending` entry and re-offering
  "Refresh now" for it, which F5/F9 turn into stranded local round state.

## 4. Plan

### Phase 1 — App-side visibility bugs (likely explains symptom 2)

Given F1, a pending refresh movement exists from the moment of scheduling,
so `hasActiveRefresh` *should* flip promptly. Two suspects on our side:

- `RefreshModalView.performRefresh()` never triggers a transaction refetch
  after scheduling (the refetch only happens via the dismiss completion's
  `manager.refresh()`). Fix: call `refreshAfterVTXOChange()` on success,
  like the auto path does.

  **This diagnosis was incomplete, found 2026-09-21 on review.** Routing
  through `refreshAfterVTXOChange()` was *not* sufficient, because that
  method refetched the wrong layer: it called the Ark-only
  `transactionService.refreshTransactions()`, while every reader
  (`hasActiveRefresh`, `vtxoIdsBeingRefreshed()`, the balance card) goes
  through `WalletManager.transactions` →
  `unifiedTransactionService.allTransactions`, a **stored** merge whose only
  writer was `mergeTransactions()`, called solely from
  `WalletManager.performRefresh()`. No observer bridged the two.

  Consequences before the fix:
  - the **auto path never merged at all**, so after an automatic schedule the
    movement half of the signal stayed stale indefinitely. Combined with F3
    (`pendingRoundInputVtxos()` empty before issuance) the whole union was
    empty in the scheduled-but-not-issued window — Guard C inert in exactly
    the window it exists for, and the next hourly check free to
    double-schedule;
  - the **manual path** only updated on sheet dismissal via
    `onRefreshComplete` → `manager.refresh()`, which is symptom 2 as
    originally reported.

  Fix: `refreshAfterVTXOChange()` now calls
  `unifiedTransactionService?.mergeTransactions()` after the Ark refetch.
  Local merge, no extra FFI. This was a pre-existing staleness bug affecting
  all six callers (round progression ×2, exit live-activity, notification
  handler), not just refresh — but Guard C's primary signal depended on it.
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
- Apply the §8 corrections to `Exit_Refresh_Coordination.md`.
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

Run on the iPhone against the signet wallet. No log reading required — every
check below is visible in the UI.

### Precondition (get this wrong and the run proves nothing)

The balance card must be showing the orange **"Refresh now"** with a non-zero
amount. That means `getVtxosToRefresh()` is actually returning something. If
it shows a countdown ("Refresh in …") there is nothing to schedule and every
step below passes trivially.

Signet VTXOs expire in ~1 day, so either use one that has aged into the
window or fund a fresh one and come back near its expiry.

### Step 1 — Parsing gate. Do this first.

The only check not visible as behaviour, and the one failure mode the 273
green unit tests cannot see.

Tap "Refresh now", then open the new pending refresh row in Activity →
technical details (`TransactionTechnicalDetailsView` already shows all three
fields):

| Field | Must read |
|-------|-----------|
| Category | `refresh` |
| Subsystem name | `bark.round` |
| Subsystem kind | `refresh` |

`MovementCategory` returns `.refresh` **only** for
`subsystemName == "bark.round"` *and* `subsystemKind == "refresh"`;
anything else maps to `.unknown`. Since `hasActiveRefresh`,
`vtxoIdsBeingRefreshed()` and Guard C all key on `.refresh`, a mismatch
means **the whole signal is permanently empty and Guard C is inert** while
every unit test still passes. If this fails, stop — the fix is in
`MovementCategory`'s mapping, not in anything this doc built.

### Step 2 — The card flips (read-your-own-writes)

From the same tap: the modal shows **"Refresh started"** (not "Already
refreshing"), and the balance card goes orange → blue **"Refreshing"**
promptly — while the sheet is still up or immediately on dismiss, not
minutes later and not only after a pull-to-refresh.

Late or missing flip means the post-write refetch isn't reaching the readers
(§3.2).

### Step 3 — No duplicate schedule (Guard C)

While that refresh is still pending, force another check: **kill the app and
cold-relaunch it.**

Background → foreground does *not* work — the immediate check runs from
`performInitialization()` on launch only (see §1 cadence). There is no
foreground trigger and no debug button.

Pass: Activity gains **no** second pending refresh row, and the card stays
on "Refreshing".

### Step 4 — Raced tap (optional)

Cold-launch and tap "Refresh now" inside the launch check's network window
(a few seconds) → modal reads **"Already refreshing"**. Confirms the
`ManualRefreshOutcome` plumbing. Fiddly to time by hand; treat as a bonus
rather than a gate.

### Not covered here

The `unusable_inputs` → `.alreadyIssuedByServer` path needs the server to
reject an already-issued participation, which can't be provoked reliably from
the app. Left to field observation.

## 7. Constraint for Background Execution Phase 2

`BackgroundTaskCoordinator` documents "delegated refresh kickoff" as intended
`cash.arke.refresh` short-pass scope, but `VTXORefreshService` is effectively
foreground-only: it starts once per launch and then relies on a main-run-loop
`Timer` that doesn't fire while suspended (§1 cadence). A background pass
that calls `refreshVtxosDelegated` directly would get **neither** Guard C nor
the `isChecking` gate, adding a sixth writer that races the launch/hourly
check — and background is where a stale `transactions` read is most likely,
since no view is driving `loadData()`.

When Phase 2 lands (`Background_Execution` plan), route it through
`VTXORefreshService.refreshManually()` rather than the wallet API, and make
sure `refreshAfterVTXOChange()` has run before the exclusion is computed.
`refreshManually()` doesn't require `isRunning`, so it is safe to call while
the service is stopped.

## 8. Corrections owed to Exit_Refresh_Coordination.md

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
