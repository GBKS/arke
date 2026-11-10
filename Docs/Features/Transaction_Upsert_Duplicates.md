# Transaction Upsert Duplicates

**Status:** OPEN (Tier 1 Data safety). Found by the 2026-10-12 adversarial
pass on the orphan-log fix; the sibling "Tag and contact lookups answer by
txid, not by row" (PLAUSIBLE, code-review 2026-10-21) stays as its own short
entry in the backlog and keys off cause (b) below.

Moved verbatim from `Open_Follow_Ups.md` on 2026-11-10 (backlog hygiene pass, relocation only; the open entry is now a stub pointing here).

## 1. The upsert deletes mirrored rows

- [ ] **The transaction upsert deletes duplicate `PersistentTransaction`
  rows itself** (`TransactionService+Upsert.swift`,
  `buildExistingTransactionDictionary`: `modelContext.delete` + save on a
  repeated txid, on both the full-list and the notification path). The row
  is CloudKit-mirrored and cascades to tag and contact assignments, so the
  dedupe silently drops one side's assignments; contract rule 23 reserves
  mirrored-row deletion for `WalletDataCleanupService`. Where duplicates
  come from: (a) `processSingleMovement` is not routed through
  `taskManager`, so a notification upsert can insert `movement_N` inside one
  of the full-list upsert's suspension points and the full pass, working from
  its pre-suspension snapshot, inserts `movement_N` again (PLAUSIBLE, not
  reproduced; the 2026-10-09 log shows "0 new" on every full pass); (b) two
  devices each creating the same movement row and CloudKit merging both.
  Fix shape: merge assignments onto the survivor before deleting, or route
  the notification path through the same task key and keep the first row.
  Found by the 2026-10-12 adversarial pass on the orphan-log fix; test that
  would settle (a): interleave a single-movement upsert inside a full-list
  upsert at its first `await`.
