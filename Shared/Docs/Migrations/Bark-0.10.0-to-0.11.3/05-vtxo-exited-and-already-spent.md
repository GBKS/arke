# Surfacing `Exited` VTXO state and `VtxoAlreadySpent` exit state

**Date:** 2026-07-02
**Bark change:** MR [#2117](https://gitlab.com/ark-bitcoin/bark/-/merge_requests/2117),
included in the 0.11.3 bindings the app is already pinned to.
**Status:** ✅ lossless-parse fix implemented — behavioral/UX follow-ups deferred (see below)

## Background

MR #2117 decouples "the user moved this VTXO onchain" from "the protocol
forfeited this VTXO", and adds an explicit terminal exit state for when an exit
can't proceed because the VTXO was already consumed. Two new states result:

- **`VtxoState::Exited`** — a VTXO that is in (or has completed) a unilateral
  exit. Reported by the server as refused (like `Spent`) but distinct: the funds
  moved onchain rather than being forfeited in the protocol. Starting an exit no
  longer immediately marks the VTXO `Spent`; it stays spendable until the exit
  transactions are broadcast, and the exit self-cancels if the VTXO is spent
  first (refresh, arkoor, etc.).
- **`ExitState::VtxoAlreadySpent(ExitVtxoAlreadySpentState { tip_height })`** —
  terminal state entered when the exit cannot proceed because the VTXO was
  already consumed elsewhere. No exit transactions are broadcast.

Because #2117 ships in the release we're already on, **these strings can appear
at runtime today.** Before this change they fell through to lossy defaults
(`Exited` → displayed as "Pending" and leaked into the spendable list;
`VtxoAlreadySpent` → `.unparsed`).

## How the states reach the app (string derivation)

The FFI exposes both as opaque strings (`Vtxo.state`, `ExitVtxo.state`,
`ExitTransactionStatus.state` are all `String` in the generated `Bark.swift`) —
there are no `VtxoStateInfo` / `ExitState` Swift enums to match on, so nothing
broke at compile time; the risk was silent mis-mapping. The exact strings come
from two *different* Rust serializations:

| State | Swift-side match key | Source |
|-------|----------------------|--------|
| `VtxoState::Exited` | `"exited"` | serde `#[serde(rename_all = "kebab-case")]` on `VtxoState` |
| `ExitState::VtxoAlreadySpent` | `"vtxoalreadyspent"` | Rust **`Debug`** variant name (the exit parser reads Debug output, e.g. `VtxoAlreadySpent(ExitVtxoAlreadySpentState { tip_height: 301492 })`) — serde's kebab-case does **not** apply here |

This asymmetry (kebab-case for the VTXO mapper, Debug variant name for the exit
parser) is intentional and matches how each value is actually produced.

## Changes implemented

**VTXO state → `"exited"`**
- `ArkeUI/Sources/ArkéUI/Models/VTXOModel.swift`: added `case exited = "Exited"`
  and covered all five exhaustive switches (`displayName`, `iconName`,
  `iconColor`, `backgroundColor`, `textColor`). Styled with orange +
  `arrow.up.forward.square` to read as "moved onchain".
- `Shared/Data/BarkWalletFFI/BarkWalletFFI+VTXO.swift`: added
  `case "exited": return .exited` to `mapFFIStateToVTXOState`.
- `ArkeMobile/Views/Data/VTXOListView_iOS.swift` and
  `Shared/Views/Data/VTXOListView.swift`: excluded `.exited` from the
  `spendableVTXOs` refresh filter (treated like `.spent`).

**Exit state → `VtxoAlreadySpent`**
- `Shared/Data/ExitStatus/ParsedExitState.swift`: added
  `case vtxoAlreadySpent(VtxoAlreadySpentState)` with a `tipHeight` payload
  (mirrors `StartState`).
- `Shared/Data/ExitStatus/ExitStatusParser.swift`: added the
  `"vtxoalreadyspent"` dispatch case, a `parseVtxoAlreadySpent` function, and an
  `extractTxids` arm (terminal state carries no txids).
- Exhaustive `ParsedExitState` switches updated to handle the new case:
  `ExitTransactionStatus+Parsing.swift`, `TransactionClaimExitBanner.swift`
  (2 sites), `ExitStatusDetailView_iOS.swift` (3 sites),
  `ExitProgressionService+LiveActivity.swift` (2 sites).
- `Tests/Shared/ExitStatusParserTests.swift`: added a parse test.

## Deferred / follow-up (not done here)

Making parse + mapping lossless (above) is complete. The remaining work is
behavioral. **Key context:** the exit subsystem is *SDK-driven polling* —
`ExitProgressionService` does not run its own exit state machine; it polls
`hasPendingExits` / `progressExits` / `listClaimableExits` / `syncExits` and
reflects SDK state. So this work is about **reconciling the app's derived UI and
notifications with the SDK's new terminal state**, not building new logic.

### Two concrete bugs the new terminal state exposes

Both found by reading `ExitProgressionService.swift` /
`ExitProgressionService+LiveActivity.swift`:

1. **Terminal exits skip teardown.** `checkAndProgressExits()` early-returns at
   `if !hasPending { return }` (ExitProgressionService.swift:149), and
   `updateAllLiveActivities()` only runs *after* that (line 193). When a
   `VtxoAlreadySpent` exit flips `hasPendingExits` to false, the whole
   update/teardown block is skipped → the Live Activity is never ended and
   check-in notifications are never cancelled → **dangling Live Activity**.
2. **Cancel is reported as success.** `updateAllLiveActivities` treats "VTXO no
   longer in the exit list" as `endLiveActivity(success: true)`
   (ExitProgressionService+LiveActivity.swift:432–434). A cancelled exit drops
   out of `getExitVtxos()` the same way a claimed one does → the user sees
   **"Move completed!"** for an exit that actually cancelled.

### Recommended sequencing

**Phase 0 — Observe on signet first (cheap, unblocks everything).** The
subsystem mirrors SDK state and the transitions are currently assumed, not
confirmed. On signet: (a) run a normal exit to completion; (b) start an exit
then spend the VTXO via refresh to force `VtxoAlreadySpent`. Capture, at each
step, the real `ExitTransactionStatus.state` strings, the Movement transitions
(expect `Pending` → `Canceled`), and balance snapshots (`pendingExitSat` vs
spendable). Existing `print` logging + the Console view already surface this.
This converts Phases 1 and 3 from guesswork to fact.

**Phase 1 — Correctness (highest value; the real "exit-cancel wiring").** Fix
the two bugs above: end the Live Activity + cancel check-in notifications for
terminal exits even when `hasPendingExits` is false, and distinguish cancelled
(`VtxoAlreadySpent`) from claimed (`Claimed`) *before* the VTXO drops out of the
exit list — inspect the terminal state rather than assuming success.

**Phase 2 — Live Activity terminal state (polish).** Add a dedicated cancelled
`exitState` to `ExitProgressActivityAttributes` + the widget views, replacing
today's `success ? .claimed : .start` binary
(ExitProgressionService+LiveActivity.swift:126) and the `.unparsed`+message
stopgap added in this change.

**Phase 3 — Balance / "funds moved onchain" semantics.** Using Phase 0 data,
confirm no double-count while an exit is in-progress-but-spendable (the VTXO now
stays spendable, movement is `Pending`), and update the "exit started ⇒ funds
gone" assumptions in `TransactionClaimExitBanner`, `ActiveExitAlertView_iOS`,
the active-exit lists, and pending-exit balance math.

**Testing reality:** none of Phases 1–3 are meaningfully unit-testable (SDK +
timer + system Live Activities) — they need a real signet session, which is why
Phase 0 comes first. Land one PR per phase.
