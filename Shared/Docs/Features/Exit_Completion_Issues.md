# Exit Completion Issues — Fee Double-Counting, Terminal State, Live Activity

**Created:** 2026-07-19
**Origin:** Field test — unilateral exit of 4 VTXOs concurrent with a delegated
refresh. 2 exits self-cancelled (`VtxoAlreadySpent`), 2 completed. Three
symptoms observed afterwards.
**Bark version verified against:** local checkout `~/workspace/bark`
(bark-0.3.0 / bindings 0.11.3). Rust line refs below are from that checkout —
re-verify on every bark bump.

Related: `Exit_Refresh_Coordination.md` (the cancellation race itself),
`Exit_Blocked_State.md`, `../Bark_Bindings_Feedback.md` (upstream feedback doc —
issue 2a belongs there).

---

## Symptom 1 — Combined exit fees exceed what the wallet actually paid

### Root cause: shared onchain transactions are fee-counted once per movement

Bark creates **one exit movement per exiting VTXO** (each `ExitVtxo` carries
its own `movement_id`). The app links each movement to all user-funded onchain
txids extracted from that VTXO's exit status:

- `TransactionLinkingService.relinkExitMovements` /
  `extractLinkableTransactionIds` (`Shared/Services/TransactionService/TransactionLinkingService.swift:35,299`)
  union txids per movement and call `linkParentToChild`, which happily adds the
  **same onchain child to multiple parents' `childTxids`**
  (`TransactionLinkingService.swift:364` — note `child.parentTxid` is
  last-writer-wins, so the reverse link is already inconsistent).
- `totalFeesIncludingLinked` (`Shared/Models/TransactionModel+Persistence.swift:116`)
  then adds each child's full `userPaidOnchainFeeSat` to **every** movement
  that links it.

Two classes of legitimately shared transactions:

1. **Shared exit-package ancestors.** Sibling VTXOs from the same round share
   ancestor transactions in their exit chains (round tx, branch txs). Each
   appears in both VTXOs' exit statuses → linked into both movements.
2. **The shared claim transaction.** `autoClaimExits` drains *all* claimable
   VTXOs with a single `drainExits` tx
   (`Shared/Services/ExitProgressionService.swift:252`), and `recordClaimFee`
   stores its fee on the one `onchain_<txid>` record
   (`WalletManager+Exits.swift:262`). That claim txid shows up in every
   drained VTXO's status → its fee is counted once per completed exit.

So with 2 completed exits, the claim fee and every shared ancestor fee are
each counted twice.

### Proposed fix

Keep the linking as-is (transaction details legitimately want to show shared
txs under both exits). Fix the **summation**: in
`totalFeesIncludingLinked`, divide each child's fee by the number of exit
movements whose `childTxids` contains that child (fee share). Deterministic,
and per-row amounts sum to the true total.

Implementation notes:

- `childTxids` is stored JSON-encoded, so a `#Predicate` "array contains"
  won't work; fetch exit movements (`sourceType == "ark" &&
  subsystemCategory == "exit"`) once and count in memory. Cheap — exit
  movements are rare.
- Rounding: give the remainder to the movement with the lowest txid (or
  movementId) so shares still sum exactly to the fee.
- Same helper should feed the exit details sheet and transaction details
  (`formattedTotalFeesIncludingLinked`), not just the list row.
- Extend `Tests/Shared/ExitFeeAttributionTests.swift`: two exit movements
  sharing one child tx → each shows fee/2, sum == fee; claim tx shared by two
  claimed exits; unshared txs unaffected.

---

## Symptom 2 — Completed/cancelled exits keep "refreshing"; cancelled ones jump to the top

Two independent causes.

### 2a — Cancelled exit movements get `completed_at` bumped by bark on every sync (upstream bug)

Verified in the bark checkout:

- `ExitState::progress` pre-checks "VTXO spent under us" **before** matching on
  the current state (`bark/src/exit/progress/states.rs:26-31`). The guard is
  `!self.warrants_exited_vtxo() && vtxo.state == Spent` — and
  `VtxoAlreadySpent.warrants_exited_vtxo()` is `false`
  (`bark/src/exit/models/mod.rs:180`). So an already-cancelled exit re-enters
  the guard on **every** progress/sync call and returns a **fresh**
  `VtxoAlreadySpent { tip_height: <current tip> }`.
- `Exit::sync` treats any state inequality as a state change
  (`bark/src/exit/mod.rs:~670`, `state_changed = exit.state() != &pre_state`).
  Tip height advanced → "changed" → `reconcile_vtxo_and_movement` calls
  `finish_movement(movement_id, Canceled)` **again** (`bark/src/exit/mod.rs:639`).
- `finish_movement` unconditionally sets `completed_at = now()`
  (`bark/src/movement/manager.rs:350`).

The app then faithfully mirrors it: movement date = `completedAt ?? createdAt`
(`TransactionService+Parsing.swift:320`), `updateExistingTransaction` copies
the new date (`TransactionService+Upsert.swift:225`), and the list sorts by
date → cancelled exits resurface at the top after every launch/sync in which
the chain tip moved.

Claimed exits are immune: `warrants_exited_vtxo()` is `true` for `Claimed`,
so the guard is skipped and `ExitClaimedState::progress` returns itself
unchanged.

**Fixes:**

- **Upstream (report):** match `VtxoAlreadySpent` before the spent-guard (it's
  terminal), or compare state *kinds* for `state_changed`, or make
  `finish_movement` idempotent for already-finished movements. Add to
  `Shared/Docs/Bark_Bindings_Feedback.md`.
- **App-side mitigation (works regardless):** in `updateExistingTransaction`,
  don't move a transaction's date once it is in a terminal status and the
  incoming status is the same terminal status (concretely: skip the date
  update when `existing == .cancelled && incoming == .cancelled`). First
  transition pending → cancelled still updates the date once, which is
  correct.

### 2b — Completed exits flash blue on launch: completion is never persisted

Answer to the question "is it possible that exits never get a final completed
state in their data model?" — **for the exit-status side, yes**:

- On launch, `loadExitCacheFromDisk` deliberately does **not** reconstruct
  exit objects; `cachedExitVtxos`/`cachedExitStatuses` start **empty**
  (`WalletManager+Exits.swift:57`; note `exitStatusJson: nil` is always
  written at `:134`, so `PersistentExitCache` couldn't help even if read).
- `TransactionListItem.amountTextColor` (and `transactionIconColor`, plus the
  same logic in `TransactionDetailView_iOS.swift:344-398`) special-cases exits:
  `currentExitStatus` → nil at launch (empty cache,
  `TransactionModel+WalletManager.swift:58`) → falls back to
  `subsystemKind == "claimed"` — which **never matches**: bark's exit
  movements have `subsystem_kind = "start"`, the only kind the exit subsystem
  emits (`bark/src/subsystem/mod.rs:155`) → renders blue/in-progress.
- Once `refreshExitCache` completes (network round-trips), the claimed status
  arrives and the row turns white.

**However**, the movement status itself IS terminal and IS persisted: bark
marks the movement `Successful` exactly when the exit reaches `Claimed`
(`bark/src/exit/mod.rs:638`), which the app maps to `.confirmed`. During the
whole exit lifecycle the movement stays `Pending`.

**Fix:** for exit movements, treat the *persisted movement status* as the
primary completion signal instead of the in-memory exit cache:

- In the exit branches of `TransactionListItem` /
  `TransactionDetailView_iOS`, check `transaction.transactionStatus ==
  .confirmed` → complete (white/normal colors) **before** consulting
  `currentExitStatus`. `.cancelled` already wins today
  (`TransactionListItem.swift:108,161`).
- Extract this into one shared helper (e.g. `TransactionModel.exitDisplayPhase`
  or `isExitComplete`) so list row, detail view, and desktop stay in
  agreement — today the same cascade is duplicated ~4×.
- The dead `subsystemKind == "claimed"` fallback should be removed or replaced
  by the status check.

No new persistence needed. (Persisting `isClaimed` into the transaction record
via `PersistentExitCache` remains an option, but it's redundant given the
movement status.)

### 2c — "They still get refreshed every launch" (context, mostly by design)

`_performExitCacheRefresh` intentionally fetches statuses for **all** exits
including claimed ones — `relinkExitMovements` needs claimed statuses to link
claim/CPFP txids (comment at `WalletManager+Exits.swift:193`). And bark keeps
terminal exits in `exit_vtxos` forever (no forget/archive API in 0.11). So
per-launch polling of terminal exits is expected; the *visible churn* comes
from 2a/2b above. Optional optimization: skip `includeHistory`/re-fetch for
exits already known claimed *and* already fully linked.

---

## Symptom 3 — Live Activity persists after all exits are terminal

### Root cause: cancelled exits count as "active", so the activity is recreated every launch

- `ExitVtxo.isActive` is just `!isClaimed`
  (`Shared/Views/Activity/ExitVtxo+Extensions.swift:85`), so a
  `VtxoAlreadySpent` exit is "active" forever.
- Every launch: `ExitProgressionService.start()` →
  `reattachToExistingActivities()` → `recreateMissingActivities()` filters
  `getExitVtxos().filter { $0.isActive }` — non-empty thanks to the cancelled
  exits → **recreates the Live Activity**
  (`Shared/Services/ExitProgressionService+LiveActivity.swift:135`).
- The subsequent `updateAllLiveActivities()` computes the aggregate: cancelled
  statuses are excluded, the claimed ones yield phase `.complete`
  (`ExitProgress.swift:182-208`) → `endLiveActivity(success: true)` → final
  "Move complete!"/all-steps-done state with
  `dismissalPolicy: .after(.now + 3600)` — visible for up to an hour
  (`ExitProgressionService+LiveActivity.swift:110`).
- Next launch: repeat. So yes — directly related to symptom 2: terminal exits
  never leave bark's exit list, and the app's `isActive` misclassifies
  cancelled ones.

### Proposed fix

1. Add a real "in-flight" predicate: not claimed **and** not
   `VtxoAlreadySpent`. The `ExitVtxo.state` here is the FFI string, so either
   extend `ExitVtxo+Extensions` with an `isCancelled` check
   (`extractStateCaseName(state) == "VtxoAlreadySpent"`) or go through
   `ExitStatusParser`. Use it in `recreateMissingActivities` (and audit the
   other `isActive` / `activeUnilateralExits` consumers —
   `WalletManager+Exits.swift:18` filters only `isClaimed` too, which likely
   keeps the exit banner alive for cancelled exits; `Exit_Refresh_Coordination.md`
   already lists banner/Live Activity follow-ups as open).
2. Never *create* an activity for a batch that is already all-terminal —
   `recreateMissingActivities` should bail when nothing is in flight, instead
   of relying on the immediate end-with-1h-lingering.
3. Optional: when `endLiveActivity` is called during launch reattachment (as
   opposed to a live completion the user should see), use a short/immediate
   dismissal instead of `+3600`.

---

## Suggested execution order

| Phase | Scope | Files |
|-------|-------|-------|
| 1 ✅ (2026-07-20) | Live Activity: in-flight predicate + no recreate-when-terminal (symptom 3, smallest, most visible) | `ExitVtxo+Extensions.swift`, `ExitProgressionService+LiveActivity.swift` |
| 2 ✅ (2026-07-20) | Terminal display state from movement status + shared helper (symptom 2b) — `TransactionModel.isExitComplete`; note the iOS detail view's old cascade only checked the dead `subsystemKind == "claimed"`, so exits there were *permanently* blue | `TransactionModel+WalletManager.swift`, `TransactionListItem.swift`, `TransactionDetailView_iOS.swift` |
| 3 ✅ (2026-07-20) | Freeze date for already-cancelled movements (symptom 2a mitigation) — covered by `Tests/Shared/TransactionUpsertDateFreezeTests.swift` (3 tests green) | `TransactionService+Upsert.swift` |
| 4 ✅ (2026-07-20) | Fee share for multiply-linked children (symptom 1) — fee ÷ linking-movement count, remainder to first movement by txid; 2 new tests, full mobile suite green | `TransactionModel+Persistence.swift`, `ExitFeeAttributionTests.swift` |
| 5 ✅ (2026-07-20) | Upstream: 2a added to `Bark_Bindings_Feedback.md` (§1.4 + summary ask 11); audit done — `activeUnilateralExits` now filters `isInFlight` (was leaking cancelled exits into the settings exit-action disable and attention counts), blocked-record prune likewise; refresh exclusion (`VTXORefreshService.exitingVtxoIds`) deliberately unchanged, over-excluding spent VTXOs is harmless | docs + `WalletManager+Exits.swift` |

Testing: unit tests for phase 4 (fee shares) and phase 3 (date freeze) are
straightforward. Phases 1–2 need an on-device pass with a claimed + cancelled
exit mix — the existing test wallet state from this field test is ideal;
verify before wiping it.

## Decisions (resolved 2026-07-20)

- Phase 2 / historical `.confirmed`-but-not-claimed exit movements: no
  historical data exists to compare against — unilateral exit is a rarely used
  emergency feature. Treat `.confirmed` as claimed; no migration concern.
- Phase 4: use the **fee share** approach (divide each multiply-linked child's
  fee by the number of exit movements linking it) — every row stays honest and
  totals sum to what was actually paid.
- Cancelled exit movements **do show fees when fees were paid** (exit package
  partially broadcast before cancellation). No special-casing: existing linking
  plus fee sharing already produces this.
