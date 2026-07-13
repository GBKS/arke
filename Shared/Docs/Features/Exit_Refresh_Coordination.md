# Exit ⇄ Refresh Coordination

**Created:** 2026-07-13
**Origin:** Mainnet field incident 2026-07-11 — a user's unilateral exit
("force move") self-cancelled overnight because a refresh spent the exiting
VTXO. Funds were safe (the refresh renewed them), but the app showed the exit
as a stalled, eternally pending "Forcing Move".
**Bark version verified against:** tag `bark-0.3.0`
(= bindings release `v0.11.3+bark-0.3.0`). **Re-verify §2 on every bark bump.**

Related: `Shared/Docs/Migrations/Bark-0.10.0-to-0.11.3/05-vtxo-exited-and-already-spent.md`
(state parsing — done; Live Activity / banner follow-up phases — still open).

## 1. The race in one paragraph

Since bark MR #2117, starting a unilateral exit does **not** mark the VTXO
spent: it stays `Spendable` until the exit chain is actually broadcast, and
the exit **self-cancels** (`ExitState::VtxoAlreadySpent`) if anything spends
the VTXO first. Refreshes are the thing that spends VTXOs. Nothing in bark or
in the app prevents both operations from targeting the same VTXO
concurrently; whichever settles first wins, and a refresh (server-cosigned)
beats an exit chain waiting on confirmations essentially every time.

The outcome is always funds-safe — the competing spend is the user's own
wallet — but the UX reads as a stalled/failed withdrawal.

## 2. Verified bark behavior (tag `bark-0.3.0`)

Re-check each of these when bumping the bindings; file locations are in the
bark repo (`gitlab.com/ark-bitcoin/bark`).

| # | Fact | Where |
|---|------|-------|
| 1 | Daemon auto-joins **every round's first attempt** to refresh VTXOs (`join_round_for_maintenance_refresh`) | `bark/src/daemon.rs:174` |
| 2 | Selection = `get_vtxos_to_refresh` = all `Spendable` VTXOs matching `RefreshStrategy::should_refresh_if_must`; **no exit-manager exclusion** | `bark/src/lib.rs:2118` |
| 3 | Must-refresh criteria: exit depth ≥ server `max_vtxo_exit_depth`, or expiry within `Config.vtxo_refresh_expiry_threshold`. Should-refresh adds: depth ≥ max/2, uneconomical to exit, dust — included only when at least one must-refresh VTXO exists | `bark/src/vtxo/selection.rs` |
| 4 | `start_exit_for_vtxos` leaves VTXO state untouched ("that happens in `progress_exits` once we've actually broadcast the exit chain"); movement goes Pending → Successful or **Canceled** | `bark/src/exit/mod.rs` (~line 200) |
| 5 | Movement status strings: `pending` / `successful` / `failed` / **`canceled`** (single l) | `bark/src/movement/mod.rs:24-27` |
| 6 | Delegated refreshes (`refresh_vtxos_delegated`, `maybe_schedule_maintenance_refresh_delegated`) execute **server-side at the next round even if the app is closed** | `bark/src/lib.rs` |

Consequence of 1+2+4: **bark's own daemon can refresh a VTXO mid-exit and
cancel the user's exit, and the app cannot intercept it.** This is the
suspected trigger in the field incident (VTXO likely met a depth criterion;
our own auto-refresh service was ruled out — see §5).

## 3. Scenario analysis

How the system behaves per server posture, and what each scenario demands of
the design. (Analysis 2026-07-13; fact-checked against tag `bark-0.3.0`.)

### 3.1 Server completely offline

Exit works — the chain is pre-signed and needs only the chain source
(Esplora). The refresh race **cannot occur**: manual refresh fails, the
daemon has no rounds to join, and scheduled delegated refreshes can't execute
(the server that would execute them is down). Requirements:

- The exit flow and Guard A must degrade gracefully when server calls fail
  (`getVtxosToRefresh` touches server-advertised info) — never block exit
  because a guard check errored.
- Server connectivity and chain connectivity are different things; track and
  surface them separately.
- Residual risk is expiry, not the race → see 3.3's escalation-ladder gap.

### 3.2 Server cooperative, spotty connection

The race **amplifier** — likely what produced the 2026-07-11 incident.
Failed-looking refreshes can leave live delegated requests server-side;
pending round states linger locally; the daemon re-joins round events on
reconnect and refreshes immediately. The race window becomes "any moment
after connectivity resumes", including mid-exit-broadcast. Requirements:

- Guard A's pending-round check is most valuable here; sync pending round
  state on reconnect *before* permitting a new force move.
- Surface lingering pending rounds with an explicit cancel
  (`cancelPendingRound`) instead of letting them lurk.

### 3.3 Malicious server (stall, then sweep expired VTXOs)

**A malicious server cannot cancel an exit via the refresh race** — refresh
spends require the user's wallet to sign round participation, and pre-expiry
the server cannot spend the VTXO at all. `VtxoAlreadySpent` is always
self-inflicted. What a malicious server *can* do:

- **Stall toward expiry, then sweep.** The only defense is exiting with
  enough lead time — and neither bark nor Arké has an automatic
  exit-before-expiry fallback: bark's `Config.vtxo_exit_margin` (default 12
  blocks) is only consumed by Lightning HTLC timing (`lightning/receive.rs`),
  and our `VTXORefreshService` only schedules *refresh* reminders. A deep
  exit chain (the incident VTXO had 12 txs confirming sequentially) needs a
  much larger margin than 12 blocks. **This is the biggest gap this analysis
  surfaced** — see work item below and the upstream section.
- **Poison guard inputs.** `max_vtxo_exit_depth` and the fee schedule are
  server-advertised; they drive bark's must/should-refresh flags. Guards may
  use them for *suggestions*, never hard blocks.
- **Weaponize a hard block.** If Guard A blocks exit while "a pending round
  includes this VTXO", an eternally-pending round becomes a server-side lever
  to prevent exit through our own UI. Any block needs a local override:
  "cancel the scheduled renewal and force move anyway."

### 3.4 Server cooperative and online (normal case)

The incident scenario — the race lives *here* because a healthy daemon joins
every round. Guards A/B plus the upstream exclusion fix cover it. Product
note: with a cooperative server, a unilateral exit is usually the wrong tool
(a cooperative offboard is cheaper and faster); the force-move flow should
say so and position itself as the emergency path — which also shrinks the
population exposed to the race.

### Design principles (fall out of 3.1–3.4)

1. **Exit fails open; refresh fails closed.** Exit must always be executable
   from local data + chain access alone; nothing driven by server state may
   make force move unavailable without a local override.
2. Server-advertised parameters are untrusted inputs — suggestions only.
3. Expiry needs an escalation ladder ending in a proactive exit prompt, with
   margin scaled to the VTXO's actual exit-chain depth (`exitTxWeightWu` /
   chain length), not a fixed constant.
4. Track server connectivity and chain connectivity separately.

## 4. Work items

### Scope decisions (2026-07-13)

- **Force move is full-wallet evacuation.** Partial (per-VTXO) exits are out
  of scope as a product concept; the flow uses `startExitForEntireWallet`
  semantics: leaving the Ark entirely, so nothing that serves *staying*
  (refresh rounds, incoming payments) is wanted while an exit runs.
- **Near-term work is contained to the exit view/flow.** Wallet-level
  surfaces of the §3.3 escalation ladder (scheduled notifications, balance
  banner, auto-exit policy) are explicitly deferred; §3 remains the rationale
  and design reference for when they're picked up.

### Done

- **Movement status mapping** — bark's `canceled` previously fell through the
  unknown-status default to `.pending` (the "stalled" display). Now maps to
  `TransactionStatusEnum.cancelled` (new case, neutral gray, "Cancelled
  move"/"Cancelled send…" copy). `.cancelled` deliberately short-circuits the
  unilateral-exit display overrides in `TransactionModel+DisplayHelpers`,
  `TransactionListItem`, and `TransactionDetailView_iOS`, which otherwise
  report unclaimed exits as pending forever. (2026-07-13)
  Spelling is deliberately split: bark's wire string is `canceled` (single l)
  and is matched only at the parse boundary; our enum case, persisted string,
  and UI copy use `cancelled`, consistent with Swift/Apple API convention
  (`Task.isCancelled`) and the app's existing copy ("cannot be cancelled").
  Don't "unify" this.
- **Guard B in `VTXORefreshService`** — both paths (`checkAndRefreshVTXOs`
  auto-refresh and `refreshManually`) now exclude VTXOs whose ids appear in
  `getExitVtxos()`. Deliberately fail-open on lookup error: a missed
  exclusion only risks the benign self-cancel race, while skipping a
  near-expiry refresh risks real fund loss. (2026-07-13)

- **Ongoing-refresh note in `NoExitView`** — first slice of the force-move
  pre-flight: when a refresh transaction is pending, the pre-exit screen shows
  an advisory ("your balance is being refreshed; a forced move started now
  would be cancelled by it"). Advisory only — never gates the Start button
  (design principle 1). Signal is the new canonical
  `WalletManager.hasActiveRefresh` (pending `.refresh` transactions;
  `BalanceRefreshStatusViewModel` now delegates to it). Does *not* cover
  server-side pending delegated rounds or daemon maintenance refreshes — those
  remain in the pre-flight item below. (2026-07-13)

### Open — app side (exit view scope)

- **Force-move pre-flight (supersedes "Guard A").** Before starting the exit:
  - Server reachable → advisory: a cooperative offboard is cheaper/faster;
    force move is the emergency path. Proceed allowed (fail-open, §3.3).
  - Pending delegated rounds exist → require cancel-and-proceed
    (`cancelPendingRound`); never a dead end.
  - Show time/cost estimates from the wallet's own exit data (chain depth,
    `exitTxWeightWu`).
- **Stop signing during an active exit.** On force-move start: stop the
  daemon (`stopDaemon`) and suppress app-side refresh triggers
  (`VTXORefreshService`, refresh UIs) until the exit claims or the user
  abandons it. Removes the daemon maintenance-refresh race without waiting
  for upstream. Invariant to engineer: `Wallet.open` restarts the daemon
  implicitly on every launch — the stopped state must be re-asserted at
  startup from persisted exit state. Trade-off (acceptable for full
  evacuation): incoming payments and round processing pause while exiting.
- **Guard B (refresh initiation) — remaining call sites.** Mostly subsumed by
  "stop signing during an active exit" above, but kept as a cheap
  belt-and-braces invariant (protects against the daemon-restart-on-launch
  window). `VTXORefreshService` is done (see Done). Still open — exclude ids
  from the exit VTXO list (*not* the VTXO state — `Exited` only appears
  post-broadcast) in:
  - `BalanceRefreshStatusViewModel.vtxosNeedingRefresh` (feeds `RefreshModalView`),
  - developer refresh in `VTXOListView` / `VTXOListView_iOS`.
- **Exit-detail copy.** Where the exit shows `VtxoAlreadySpent`, present it as
  benign: "Move cancelled — this balance was renewed by a refresh instead;
  your funds are unaffected." Replaces raw Rust debug string + step counter in
  `ExitStatusDetailView_iOS` / `TransactionClaimExitBanner` /
  `TransactionExitDetailsView`.
- **Debug export redaction.** The user-initiated log export renders txids,
  VTXO ids, movement statuses, and exit states as `<private>` — which is
  precisely the information support needs. Make these public in the export
  path.
- **DEFERRED — Expiry escalation ladder surfaces (from §3.3).** When refresh
  keeps failing (or the server is unreachable) and expiry approaches,
  escalate to a proactive exit prompt while margin remains — margin computed
  from the VTXO's exit-chain depth, not a fixed constant. Needs wallet-level
  surfaces (scheduled local notifications à la `VTXORefreshService`, balance
  banner, and an auto-exit policy decision), so it is outside the current
  exit-view scope. Today's only pre-expiry defense is a refresh reminder
  notification — useless against a stalling or dead server. Within the exit
  view, the ladder's only near-term contribution: once margin is short, the
  pre-flight advisory flips from "prefer renewal" to "do this now."
- **Migration doc 05 phases 1–3** (Live Activity teardown, cancelled ≠
  claimed, balance semantics) remain as scoped there.

### Open — upstream

- **File bark issue:** `join_round_for_maintenance_refresh` should exclude
  exit-manager VTXO ids (likely one-line fix; facts in §2 are the evidence,
  the 2026-07-11 incident is the repro narrative). Until fixed, Guard A's
  warning is a mitigation, not a fix.
- **Raise the exit-margin gap:** `Config.vtxo_exit_margin` is documented as
  the safe-exit block budget but is only used for Lightning HTLC timing;
  bark has no exit-before-expiry fallback for regular VTXOs (§3.3). Worth an
  upstream discussion alongside the daemon-exclusion issue.
- **When the upstream fix ships:** the daemon-warning half of Guard A becomes
  obsolete — revisit this doc and simplify.

## 5. Field incident reference (2026-07-11)

Mainnet, iPhone, app 1.0 (17). Reporter was a technical user (CTO of another
company implementing the Ark protocol) deliberately testing exit
functionality — treat the report as expert QA, not end-user confusion.
User received two VTXOs, force-moved one
(35k sats, 12-tx exit chain); the other exited successfully. Overnight a
refresh round spent the exiting VTXO → `VtxoAlreadySpent(tip_height: 957529)`;
the wallet re-attempted and re-aborted the exit every sync. Display showed
"Forcing Move … Step 1 of 12" indefinitely because (a) `canceled` was
unparsed → pending, and (b) exit-status display overrode status with
"pending until claimed". Ruled out: our `VTXORefreshService` (only fires in
the fee-schedule free window, which was ~23 days away). Not determined:
daemon vs. manual refresh tap (user was not asked in time). Balance
reconciled fully; no funds lost; no fee paid for the cancelled exit (its leaf
tx was never broadcast).

## 6. Validation

None of the guards are unit-testable (SDK + timers + server rounds). Signet
scenario, same as migration doc 05 Phase 0:

1. Receive a VTXO, start a force move, then trigger a refresh of the same
   VTXO → exit must cancel; verify Guard B hides the VTXO from refresh UIs
   and Guard A warns/blocks beforehand; verify the movement shows "Cancelled
   move" (gray), not pending/failed.
2. Run a normal exit to completion → no regressions in claimed display.
