# Completion Report: Bark FFI v0.23.0 → v0.24.0

**Completed:** 2026-09-17 (same-day: docs → Phase 1 → Phase 2 → chores)
**Result:** build green both phases, `ImportRecoveryLogicTests` 8/8 green
(4 pre-existing + 4 new)

## What shipped

### Phase 1 — compile fix (one line, as planned)

`BarkWalletFFI+Configuration.swift` `makeConfig`: added
`vtxoKeyGapLimit: nil` to the single `Config(...)` construction. Build was
green on the first try after the edit — no unlisted construction sites
surfaced, confirming the single-break analysis in 01-api-changes.md.

Behavior change accepted deliberately: `nil` now means the library default of
**250** (was a hardcoded 50), widening the import-path recovery scan and the
`importVtxo` ownership scan.

### Phase 2 — widened `foreign`-ids recovery retry (approved by Christoph,
recommended width `maxVtxoKeyGapLimit()`)

`BarkWalletFFI+WalletCreation.swift`:

- `ImportRecoveryLogic.retryPasses(failedIds:foreignIds:widenedGapLimit:)` —
  new pure planner returning ordered `RetryPass` values: `failed` ids retry
  with the configured gap limit (ownership already proven; transient errors),
  `foreign` ids retry with the widened limit (no key derivable within the
  configured horizon). The buckets deliberately stay separate passes so
  transient failures never pay the widened scan's worst case, and the cheap
  pass runs first.
- `retryFailedRecoveries` → `retryRecoveries`: pass-driven loop calling
  `recoverVtxos(vtxoIds:gapLimit:)` per pass with
  `maxVtxoKeyGapLimit()` (100_000) as the widened limit. An errored pass is
  logged and skipped — the import itself never fails here (consistent with
  the acceptWithoutRecovery philosophy).
- `logRecoveryReport`: the foreign warning now says "retrying with widened
  gap limit"; the definitive "genuinely foreign or keyed beyond 100_000
  indices" warning moved into the retry, emitted only when the widened pass
  also leaves ids foreign.

Tests: 4 new cases in `ImportRecoveryLogicTests` pin the planner (clean scan
→ no passes; failed keeps configured limit; foreign gets widened limit; both
buckets → two ordered passes, never merged).

### Chores

- `Bark_Bindings_Unadopted_API.md`: baseline bumped v0.19.0 → v0.24.0
  (@ `788c6f2`), new v0.24 section (importVtxos, ImportVtxoArgs knobs, free
  functions), catch-up v0.23 section (the bump-time update had been skipped),
  §3 internal-use table updated, first entry in Adopted-since.
- `Open_Follow_Ups.md`: new "Bark 0.24 Migration" section with the three
  deferrals (batch import, protocol mirroring, on-device import smoke);
  0.23's stale unadopted-API checkbox closed.

## Verification

- Builds: green after Phase 1 (26.7s) and after Phase 2 (13.1s), active
  scheme ("Arke mobile"); desktop deliberately unchecked per the current
  lean workflow.
- Scoped tests: `ImportRecoveryLogicTests` 8/8 passed via test plan
  "Arke mobile".
- Full mobile suite: batch run at end of task (lean workflow) — result
  recorded in the session, not blocking this report.
- On-device: seed import tested by Christoph 2026-09-17, works. (Per-pass
  retry log lines not inspected — fine unless a foreign-VTXO case appears.)

## Deviations from the plan

None of substance. The plan's "merge rescued into the report the same way
the failed-retry does" turned out to be aspirational — the existing failed
retry only *logs* its outcome (the report object is bark-owned and not
re-queried), so the widened pass does the same: log recovered/still-foreign
counts. If a future feature needs the rescued ids programmatically,
`recoverVtxos`'s returned `RecoveryReport` is already in hand at that call
site.
