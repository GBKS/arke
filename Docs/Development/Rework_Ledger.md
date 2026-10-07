# Rework Ledger

One line per time generated code had to be revisited: when, what, which of
the five fault classes it belongs to (`Change_Review_Playbook.md`), how it
was found, and which contract rule or test it produced. Reviewed every third
release train (`Release_Train.md`). The point is not blame; it is to see
which class dominates so the next contract rule or test goes where the
faults actually are, and to check whether the day-7 review is catching them
before the device day and the field do.

Classes: **1 Scope** · **2 Path asymmetry** · **3 Ownership** ·
**4 Boundary assumption** · **5 Trusted claim**.
Found by: **review** (a review pass) · **device** (on-device verify) ·
**field** (TestFlight / real use) · **audit** (claims audit) · **tests**.

## Seed entries (reconstructed 2026-10-07 from the Done log)

| Date | Change revisited | Class | Found by | Produced |
|------|------------------|-------|----------|----------|
| 2026-08-10 | `initWallet()` + `open` shipped for months; seed-recovery scan never ran on import | 4 | audit (bark source) | Launch rule 1; single-step `Wallet.open` |
| 2026-08-13 | Fresh-import Live Activity respawned "Move complete" — bark replays finished exits ~2 s | 4 | device | B3; `recreateMissingActivities` after first check |
| 2026-08-13 | Balance overcount after import — parallel read captured bark's mid-walk state | 2 | device | `refreshOnchainBalance()` after history stabilises |
| 2026-08-19 | 2026-08-12 deletion-strategy fix defeated: FFI `deleteWallet` still deleted the synchronizable seed on every deletion | 1 | review | Launch rule 19; S1 |
| 2026-08-19 | `PendingPaymentMetadata` / `PendingTagAssignment` missing from the full wipe | 1 | tests (`WalletWipeCoverage`) | wipe-coverage inventory |
| 2026-08-20 | Local-only delete cleared the shared KVS network config; secondary stranded on mainnet | 1 | device (two-device) | Launch rule 21; `clearLocal()` / `clearEverywhere()` |
| 2026-09-21 | `refreshAfterVTXOChange` refetched the Ark-only service while every reader used the stored merge — new guard inert | 2 | review (pass 3) | P1; `mergeTransactions()` |
| 2026-09-21 | Post-write refetch joined a fetch that predated the write | 2 | review | P2; `executeFresh` |
| 2026-09-21 | Refresh doc claims "three writers", "we pin 144", "status mapping verified" all false | 5 | audit | claims-audit method; feedback §2.7 |
| 2026-09-21 | `TaskDeduplicationManager.cancel`/`cancelAll` never worked (invariant generics) | 3 | review | O4; Tier 4 item |
| 2026-09-21 | Full wipe offered to a non-last device under CloudKit lag | 1 | audit (Multi_Device_Design) | KVS mirror consulted first; `KVSDeviceRegistryTests` |
| 2026-09-23 | Local-only delete destroyed every tag/contact assignment account-wide (`deleteWallet()` after the strategy-aware service) | 1 | device (two-device) | Launch rule 23; `TransactionDeletionBlastRadiusTests`; S1 |
| 2026-09-23 | Wallet ran a whole session on the wrong network — `hasSavedConfig()` guard disarmed by the very sync that fetched the value | 2 | device | Launch rule 22; `reconcileNetworkConfigBeforeWalletOpen` |
| 2026-09-23 | Secondary seeded its own default tags/contacts (18 tags, 3 contacts) — role-based guard | 5 | device (two-device) | first fix |
| 2026-09-23 | Activity list crashed on launch reading a cached relationship array during CloudKit import | 2 | field (crash) | P3; `TransactionMetadataResolutionTests` |
| 2026-09-24 | `execute` removed `executeFresh`'s key → concurrent duplicate | 3 | review | O1; `executeJoinsFreshTaskAfterDrain` |
| 2026-09-24 | Override offered on a healthy two-device account (`.localOnly` ⇒ override) | 5 | device (two-device) | `shouldOfferOverride`; `OverrideAvailabilityTests` |
| 2026-09-24 | `unregisterCurrentDevice` mirror cleanup inside `if let` with no else → permanent ghosts | 2 | review | P4 (partial); Tier 0 item (1) |
| 2026-09-24 | `CloudKitObserver` dropped remote changes in the 1.5–2.0 s band instead of deferring | 3 | review | O2; `RemoteChangeThrottleTests` |
| 2026-09-24 | Background launch killed holding a store lock (`.test` probe on every `BarkWalletFFI.init`) | 3 | field (Organizer) | probe removed; task assertions |
| 2026-09-25 | Seeding guard was a half-fix: hazard is store-not-imported, not device role; reinstalled primary still duplicated | 5 | review | Launch rule 26; S3; `DefaultDataSeedingDecisionTests` |
| 2026-09-25 | Invalidation fix covered reads, not writes | 2 | review | P3 extended; `TransactionMetadataWritePathTests` |
| 2026-09-25 | The write-path fix made refresh a fetch storm (O(transactions × contact usage)) | 2 | review | `TransactionMetadataSnapshot` bulk bridge |
| 2026-09-27 | Refresh reminder fired ~4× early on signet — 150 s/block assumed for non-mainnet | 4 | field (log) | B4; `BlockTimeFormatter.secondsPerBlock` |
| 2026-09-27 | Hourly auto-refresh silently skipped after 60 s — read an expired cache value | 2 | review | async `getEstimatedBlockHeight()` |
| 2026-09-27 | `matchedTxid` documented "for debugging" but load-bearing | 5 | audit | Tier 3 item |
| 2026-09-27 | Desktop build broken: Xcode dropped the Shared exception set during the Docs move | 4 (tooling) | tests (build) | `#if canImport(ActivityKit)` island |
| 2026-10-01 | Pre-open refresh → sticky `walletNotInitialized` banner | 3 | field (log) | Launch rule 7b; O3 |
| 2026-10-07 | Backlog audit: first keyword sweep used `\|` in rg (literal pipe) → false "not implemented" verdicts for native contacts, identicons, fee picker | 5 | review (self) | memory rule: `a|b` alternation |

## Running entries

Add below as they happen, newest last. One line each; link the backlog item
or Done-log entry if the write-up is long.

| Date | Change revisited | Class | Found by | Produced |
|------|------------------|-------|----------|----------|
