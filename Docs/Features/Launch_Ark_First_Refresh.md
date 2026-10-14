# Launch: Ark Data Before the Onchain Sync

**Status: DECIDED 2026-10-14 (Tier 1, Train 1) — BUILT and REVIEWED
2026-10-14 (uncommitted; adversarial pass in §9, full mobile suite 536/536
on the iOS 27.0 simulator). Field, export 2026-10-14 17:53: pull-to-refresh
confirmed — Step 2b done 0.36 s after refresh start, onchain sync 1.9 s
after it, full refresh 2.65 s. Open: the cold launch with a waiting mailbox
payment (§7), which the export could not show because the device store
evicts the launch's info lines (Tier 2 export item); needs Console.app or
the export fix.**

Backlog entry: `Open_Follow_Ups.md`, Tier 1 → Connectivity and offline,
"Ark data waits for the onchain sync on every refresh".

## 1. Problem

On every full refresh — launch, pull-to-refresh, foreground — the Ark side
of the wallet (new movements, the Ark balance) is read only after the
onchain BDK sync has finished, although bark has the Ark data ready seconds
earlier. Users see the new payment row and the balance late, and the
delay scales with the esplora round-trips, not with anything Ark does.

Measured, Christoph's unattached export 2026-10-14 13:01 (times are seconds
after the launch anchor; wallet ready 13.3 s):

| When | What |
|---|---|
| 1.4 | bark-ffi `open` probes `ark_info()`, fails, logs `[OPEN] Server connection FAILED` |
| 2.4 | wallet open; our `runDaemon()` logs bark's "already running" error |
| 2.9 | Step 1 done, Step 2 begins |
| 5.4 | Step 2 onchain BDK sync done |
| 5.6 | Step 2 Ark sync done (0.15 s) |
| 5.8 | Ark balance read, 5048 sats |
| 6.0 | movements read, one new row saved, Activity list shows it |
| 10.2 | onchain balance returns; Ark balance published only now |
| 12.9 | onchain history stable after 2 sync rounds |
| 13.3 | merge, Step 4, dataVersion, wallet ready, notification listener starts |

Same shape on the 2026-10-12 wallet (26 VTXOs, 250 movements): Step 2
onchain sync 11.6 s, Ark sync 0.1 s, movements done 0.4 s into Step 3, the
onchain balance read 6.3 s. And on the pull-to-refresh at 13:02:01 in the
same export: onchain sync 4.5 s in front of a 0.1 s Ark sync.

## 2. Why, traced

Writer → store → reader for the two surfaces:

- **Activity list.** `TransactionList_iOS` renders a SwiftData `@Query` on
  `PersistentTransaction`. Rows appear when
  `TransactionService.upsertTransactionsFromServerData` saves. That save
  runs in Step 3 of `WalletManager.performRefresh`, after `sync()`. The
  unified merge (Step 3.1) and `dataVersion` are not on the row's path on
  iOS; they feed `WalletManager.transactions` readers (Guard C,
  `hasActiveRefresh`) and the row metadata snapshot.
- **Balance card.** `BalanceService.refreshAllBalances` does
  `try await (arkBalanceResult, onchainBalanceResult)` and publishes both
  afterwards. The onchain balance FFI call waits behind the BDK lock held by
  the Step 3 history sync (`OnchainHistorySyncer.syncUntilStable`), so the
  Ark figure sits unpublished for the whole first sync round.
- **Step 2.** `BarkWalletFFI+Server.swift` `sync()` calls
  `onchainWallet.sync()` first, then `wallet.sync()`. Both are separate FFI
  calls; the ordering is the app's.

## 3. Claims

| # | Claim | Label | Evidence |
|---|---|---|---|
| C1 | The iOS Activity list shows a row at the upsert save, not at Step 3.1 | verified | `TransactionList_iOS.swift` `@Query`; export: row at 6.0 s, Step 3.1 at 13.3 s |
| C2 | bark's `Wallet::sync` does not sync the onchain wallet and does not depend on it having synced | verified | tag `bark-0.7.1`, `bark/src/lib.rs:1980` (the workspace checkout `8adc8e7` is 130 commits past the tag, where the function sits at `:1951`); also true at tag `bark-0.6.2`, `lib.rs:1857`. Doc comment "will not refresh VTXOs or sync the onchain wallet"; sub-syncs are fee rates, mailbox, pending rounds, lightning sends, arkoor sends, lightning claims, boards, offboards, all via the chain source, none via the BDK wallet; the only onchain-wallet sync in `lib.rs` is `sync_onchain` |
| C3 | The bark-ffi `sync()` wrapper only calls `inner.sync()` and logs, and always returns `Ok` | verified | bark-ffi tag `v0.25.0+bark-0.6.2.uniffi-0.31.1`, `src/core/wallet.rs:234`. That tag's `Cargo.toml` pins `bark-0.6.2` while the bindings README maps v0.25.0 to bark 0.7.1 — the two sources disagree on the bark revision inside the shipped xcframework. The conclusion holds at both revisions (C2) |
| C4 | bark stamps a movement's `created_at` with the local clock on insert | verified | `bark/src/movement/manager.rs:66`, `persist/sqlite/query.rs:125` |
| C5 | `refreshAllBalances` publishes nothing until both reads return | verified | `BalanceService.swift:92-116` |
| C6 | The onchain balance read waits behind the Step 3 history sync | derived | export: `Fetching onchain balance` 5.8 s, `Onchain balance retrieved` 10.2 s, right after the BDK `Current balance` line of sync round 1 |
| C7 | The Step 3 movements upsert is idempotent for an unchanged list | verified | attached run 07:37: "saved 0 new, 0 updated" on a second read of 295 movements |
| C8 | `TaskDeduplicationManager.execute(key:)` joins an in-flight job and starts fresh otherwise | verified | `TransactionService.swift:138-149` doc + `TaskDeduplicationManagerTests` |
| C9 | The daemon's open-time sync drains the mailbox before our refresh | verified for one launch | attached run: mailbox check 0.2 s after open; the 13:01 export shows the open-time server probe failing, so this cannot be relied on |
| C10 | `updateTotalBalance` tolerates a missing side and uses the persisted onchain row when present | verified | `BalanceService.swift:165-193`, `setModelContext` loads persisted rows |

No assumed claims remain on the build path. C9 is why the design reads Ark
data itself instead of trusting the daemon.

## 4. Design

### 4.1 Two sync methods instead of one (FFI + protocol)

`BarkWalletFFI+Server.swift`: split `sync()` into

- `syncArk()` — `wallet.sync()` only (C2, C3).
- `syncOnchain()` — `onchainWallet.sync()` only, non-fatal as today.
- `sync()` stays as the composed call for its existing callers and becomes
  `syncArk()` then `syncOnchain()`? **No** — keep its current order. The
  ruling (2026-10-14) is that the four UI callers are untouched; changing
  the composed order would change them. `sync()` therefore keeps
  onchain-then-Ark and simply calls the two new methods in that order.

`BarkWalletProtocol`: add `syncArk()` and `syncOnchain()` next to `sync()`.
Two FFI calls mirrored as two methods is the protocol's own rule (mirror the
FFI surface, no app policy). `MockBarkWallet` gets the two methods with the
same sleep-and-print body as `sync()`. `WalletManager+Operations.swift` gets
the two thin wrappers next to `sync()`.

### 4.2 Step 2 in `performRefresh`

```
Step 1   refreshServer()                       (unchanged)
Step 2a  syncArk()                             mailbox etc., ~0.1–0.15 s
Step 2b  early Ark publish, in parallel:
           transactionService.refreshTransactions()   → rows appear
           balanceService.refreshArkBalance()          → Ark balance published
Step 2c  syncOnchain()                         BDK, 2.5–11.6 s
Step 3   unchanged
```

Step 2b runs even if Step 2a failed: the reads are local and show the
last-known bark state, which is what Step 3 does today on that path
(`sync()` never throws for server reasons — Tier 1 Connectivity item).
`anyServerCallSucceeded` semantics are unchanged (still set after Step 2;
the known gap that Step 2 cannot fail is a separate item).

Step 2b's movements read is `refreshTransactionsAfterWrite()`, the
read-your-own-writes variant (`executeFresh`): Step 2a just wrote, and the
joining `refreshTransactions()` could attach to a notification-path read
that started before the sync and publish the pre-sync list (review finding
3). Step 2b also republishes the unified stored merge
(`mergeTransactions()`, local, ~15 ms) so `WalletManager.transactions`
readers do not lag the SwiftData rows by the onchain sync (review finding
4). Step 3's `refreshTransactions()` then joins or starts fresh as before
(C8); the second upsert is idempotent (C7). The Ark balance read in Step 3
is a second FFI `balance()` call, not deduplicated against 2b's because 2b
has completed by then; keep it, it costs ~0.3 s and keeps Step 3
self-contained.

Log lines: `🔄 [Refresh] Step 2a: Syncing Ark wallet state…`, `Step 2b:
Early Ark publish (movements + Ark balance)…`, `✅ Step 2b: Early Ark
publish done T s after launch anchor`, `Step 2c: Syncing onchain wallet…`.
The upsert's save line gains `⏱️ Newest inserted row is X s old at save`,
where the row date is bark's `completed_at ?? created_at`; that number is
the bark-to-screen lag per launch (asked for by the Train 2 launch-timing
item). `T` is dwell time on a refresh long after launch; the wording says
"after launch anchor" for that reason.

### 4.3 Balance publishes on arrival

`BalanceService.refreshAllBalances`:

```
async let ark = getArkBalanceWithDeduplication()
async let onchain = getOnchainBalanceWithDeduplication()
do { await updateArkBalanceFromResponse(try await ark); updateTotalBalance() }
catch { arkError = … }
do { await updateOnchainBalanceFromResponse(try await onchain); updateTotalBalance() }
catch { onchainError = … }
error = first non-nil of the two, else nil
```

Both reads still start together, so nothing gets slower; the Ark publish
no longer waits for the onchain one. `updateTotalBalance` combines the
fresh Ark figure with the in-memory onchain figure, loaded from the
persisted row at `setModelContext` (C10), so an already-used wallet never
flashes an onchain zero. When that in-memory figure is nil — fresh import,
or a local-only delete and rejoin on the same device, since
`resetBalancesInMemory()` clears it and nothing reloads it — the card shows
an Ark-only total from Step 2b until the onchain read returns in Step 3.
Before this change the same window showed a synthesised all-zero total.
Both are interim numbers under the load wave; the new one is closer to the
truth, not identical to today (review finding 5, device check in §7).

Callers of `refreshAllBalances`, all covered by the same change:
`performRefresh` Step 3, `refreshAfterTransaction` (post-transaction
callback, `refreshAfterVTXOChange`), `refreshBalances` (notification
service on every movement, Lightning claims). The notification path
benefits most: after a received-payment notification the Ark balance no
longer waits for an onchain read that may trigger a BDK sync.

### 4.4 Explicitly unchanged

- Step 3's two-round history sync and the second onchain balance read (the
  2026-08-13 overcount guard) — Train 2's one-sync-per-refresh item.
- The balance card's load wave runs to the end of the full refresh (DECIDED
  2026-10-13); the amount updates beneath it. `isRefreshing` is untouched.
- Step 3.1 merge, `dataVersion`, Guard C inputs, `hasActiveRefresh`.
- Rule 7b: nothing runs before the handle is open; Step 2a is inside
  `performRefresh`, after the open guard.
- Read-only mode path (returns before Step 1).
- The five UI `sync()` callers (`ReceiveViewModel`, `BalanceView_iOS`,
  `ExitStatusDetailView_iOS`, `DataView_iOS`, desktop `DataView`) and the
  two FFI-internal `wallet.sync()` calls (`shutdownWallet` final sync,
  creation diagnostic).
- The notification listener start (separate Tier 2 item; replay semantics
  unverified).

## 5. Sibling sweep

| Site | Status |
|---|---|
| `WalletManager.performRefresh` Step 2 | changed (4.2) |
| `BarkWalletFFI+Server.swift` `sync()` | split, composed order kept (4.1) |
| `BarkWalletProtocol.sync()` + `MockBarkWallet.sync()` | two methods added |
| `WalletManager+Operations.swift` `sync()` | two wrappers added |
| 5 UI `sync()` callers: `ReceiveViewModel:206`, `BalanceView_iOS:204`, `ExitStatusDetailView_iOS:133`, `DataView_iOS:85`, `ArkeDesktop/Views/Data/DataView.swift:113` | exempt — ruling 2026-10-14; the desktop one was missed in the first sweep and found by the review (composed method, same behaviour) |
| `BarkWalletFFI+WalletLifecycle.swift:426` final sync on shutdown | exempt — direct FFI call, order irrelevant |
| `BarkWalletFFI+WalletCreation.swift:277` diagnostic sync | exempt — diagnostic print path |
| `BalanceService.refreshAllBalances` | changed (4.3) |
| `refreshAfterTransaction`, `refreshBalances` | covered via 4.3 |
| `refreshArkBalance`, `refreshOnchainBalance` | unchanged, already single-source |
| `ReadOnlyBalanceService` | exempt — CloudKit rows, no FFI |
| `RefreshModalView.performRefresh` | reads `WalletManager.refresh()`, covered |
| `LightningClaimService` Step 1 "sync wallet state" | exempt — calls the composed `sync()` (`LightningClaimService.swift:151`), so it keeps onchain-then-Ark by the ruling; note for later that every Lightning claim check therefore also pays the onchain sync |

## 6. Fault classes

- **Scope:** every `sync()` caller listed above; the composed method keeps
  its behaviour so none changes.
- **Path asymmetry:** Step 2a failure → Step 2b still runs on local data;
  Ark read failure in 4.3 → onchain publish still happens and vice versa;
  the `error` string names the first failure. Cold start with the open-time
  server probe failing (export 13:01) is the normal case, not an edge.
- **Ownership:** unchanged — `BalanceService` publishes, `WalletManager`
  orders, `TransactionService` writes rows.
- **Boundary assumptions:** C2 and C3 verified at source; no assumed bark
  claim remains.
- **Trusted claims:** all timings from exports, none from docs.

## 7. Verification

- `XcodeRefreshCodeIssuesInFile` per edited file, one `BuildProject`.
- Scoped suites: `TaskDeduplicationManagerTests`, `RefreshExclusionTests`,
  `RefreshRejectionTests`, `BalanceLoadIndicatorModelTests`.
- New test, decision-level only: `refreshAllBalances` publishes the Ark
  balance before the onchain read returns. Needs a wallet stub with a
  controllable onchain delay; if that means widening `MockBarkWallet`, skip
  the test and say so — the mock stays a two-suite stub.
- Adversarial pass (`fault-class-reviewer`) on the commit range: startup
  ordering, caches, money display.
- Full mobile suite once, after the pass.
- Device, unattached, with a payment waiting in the mailbox: cold launch,
  wait a minute, export. Expect: `Step 2b` line within ~0.5 s of `Step 2a`,
  the new row's age at save under 1 s, Ark balance published in the same
  window, onchain figures later, no onchain zero on the card at any point.
  Then one pull-to-refresh, same expectations. Record the look in the Device
  Day doc.
- Device, review finding 5: fresh import of a wallet with onchain funds,
  watch the card between the `Step 2b` line and `Onchain balance retrieved`
  — Ark-only total expected, under the wave; note how long.
- Two devices, review finding 6: the mirrored `ArkBalanceModel` row is now
  saved twice per full refresh (Step 2b and Step 3), each a CloudKit export
  and a `cloudKitDataDidChange` on the secondary. Watch the secondary's
  balance for flicker during a primary launch.

## 8. Out of scope, filed separately

Exporter persistence lag (Tier 2), listener start after refresh (Tier 2),
open-time server probe failure (Tier 1 Connectivity), redundant `runDaemon`
(Tier 4), unused `TransactionListModel` (Tier 4), one onchain sync per
refresh and the wave revisit (Tier 4, Train 2).

## 9. Review record (2026-10-14)

Built 2026-10-14; fresh-context adversarial pass the same day on the
uncommitted diff (`fault-class-reviewer`). No CONFIRMED defect in the money
or startup paths. Dispositions:

| # | Finding | Class | Disposition |
|---|---|---|---|
| 1 | CONFIRMED: bark cite named the HEAD line (`:1951`) not the tag line (`:1980`); bark-ffi tag pins `bark-0.6.2` while the bindings README says 0.7.1 | trusted claims | fixed in code comments, rule 7c and C2/C3; conclusion unchanged at both revisions |
| 2 | CONFIRMED: plan text described a Step 2b log format, a "same as today" fresh-wallet claim and four UI callers that did not match the code or the tree (five callers) | trusted claims | plan corrected (§4.2, §4.3, §5); Step 2b and upsert comments reworded |
| 3 | PLAUSIBLE: Step 2b's joining reads could attach to a pre-sync notification-path read on a non-launch refresh and publish stale data as the early publish | ownership (P2) | fixed for movements: `refreshTransactionsAfterWrite()` (`executeFresh`). Accepted for the Ark balance: its dedup key carries a typed task, which `executeFresh` refuses by design; Step 3 corrects within the refresh; not reachable on the cold launch |
| 4 | PLAUSIBLE: the SwiftData-rows-vs-unified-merge window widened by the onchain sync; no breaking reader found | path asymmetry | fixed: `mergeTransactions()` after the Step 2b reads |
| 5 | PLAUSIBLE: Ark-only total on the card while the in-memory onchain figure is nil (fresh import, post-reset) until Step 3 | money display | accepted as the better interim number under the wave; device check added (§7) |
| 6 | PLAUSIBLE: `ArkBalanceModel` saved twice per refresh, two CloudKit exports | scope (cost) | accepted; skipping the save on unchanged values would also freeze `lastUpdated`, which secondaries sort and age by; two-device look added (§7) |

Reviewer did not verify: build/tests (run after the pass, see below), the
bark revision inside the shipped xcframework, the device looks above, and
concurrent daemon syncs during Step 2a/2b.
