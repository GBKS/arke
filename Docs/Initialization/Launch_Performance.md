# Launch Performance

**Status:** OPEN (Tier 4 Startup; the one-onchain-sync-per-refresh
restructuring is a DECIDED 2026-10-12 Train 2 candidate that needs its own
design pass). Companion to `Launch_Sequence_Contract.md` (the invariants) and
`../Features/Launch_Ark_First_Refresh.md` (the Step 2 reorder that was split
out of section 1 on 2026-10-14).

Moved verbatim from `Open_Follow_Ups.md` on 2026-11-10 (backlog hygiene pass, relocation only; the open entry is now a stub pointing here).

## 1. Field cold launches and the two onchain syncs

- [ ] **Field cold launches run 10–20s, one at 74s** (background event
  journal of the mainnet user, 2026-10-04..09; the 2026-10-07 export caught
  the launch refresh still inside Step 3 at 11s, no "Step 3.1" yet). Which
  Step 3 task is the long pole — `refreshAllBalances`, the onchain sync, or
  the block-height fetch? Add per-task timings to the Step 3 task group
  before guessing. Same timings answer the older **18s gap between
  `initialize()` called and executed** (device log 2026-09-08, suspect the
  dedup/queueing layer; merged 2026-10-09). Related: the CoreData error
  flood and the whole-app background launch below.
  Measured 2026-10-12 on Christoph's phone (mainnet, 26 VTXOs, 250
  movements, 1 onchain tx), two launches of the same build: attached to
  Xcode, wallet ready at 48 s with a 20 s call→execute gap; unattached,
  27.7 s with a 61 ms gap — so the call→execute gap is a debugger artefact,
  not the dedup layer. Unattached breakdown: open 0.3 s, server connect
  1.0 s, Step 2 11.9 s of which the BDK onchain sync inside `sync()`
  (`BarkWalletFFI+Server.swift`, runs before the Ark sync) is 11.6 s and
  the Ark sync 0.1 s; Step 3 13.5 s, movements done after 0.4 s, the rest
  is the onchain balance read (6.3 s) and "Onchain history stabilized after
  2 sync round(s)" (6.7 s). About 25 of 27.7 s are esplora/BDK syncs, run
  twice per launch. Long pole answered; the lever is one onchain sync per
  refresh instead of two, or the Step 2 onchain sync off the launch path.
  DECIDED 2026-10-12: Train 2 candidate, not Train 1 — the second sync is
  the 2026-08-13 balance-overcount guard ("history stabilised"), so the
  restructuring needs its own design pass. DECIDED 2026-10-13: once this
  has landed, revisit whether the balance card's load wave should end when
  the Ark data is fresh instead of at the end of the full refresh (today
  that would only halve the window, because Step 2's onchain sync precedes
  the Ark sync); until then the wave stays honest to the full refresh.
  Data points 2026-10-14 evening (journal, unattached, same build as the
  Ark-first change): cold launches of 26.5 s and 32.6 s four seconds apart,
  no step breakdown because the export had evicted the launch's info lines;
  the pull-to-refresh a minute later took 2.65 s with a 1.9 s onchain sync,
  so esplora was not slow at that moment. Christoph saw the balance and
  list refresh quickly and the load wave run about 12 s — if the wave
  ended at 12 s, `refresh()` returned then and the remaining ~20 s to
  "Wallet ready" sat in the post-refresh part of `initializePrimaryMode`
  (exit cache, default-data seeding, arkInfo, service starts), which took
  80 ms in the 13:01 export. Unexplained; needs a Console.app launch.
  DECIDED 2026-10-14 (evening): the wave stays honest to the full refresh
  for now, even though the Ark-first change made "end it at Step 2b"
  possible; Christoph wants to watch the new launch behaviour for a few
  days first. Revisit after that.
  2026-10-14: the Step 2 reorder (Ark sync first, early Ark publish) was
  split out as the Tier 1 Connectivity item "Ark data waits for the onchain
  sync on every refresh" (DECIDED, Train 1); what stays here is the
  one-onchain-sync-per-refresh restructuring and the "Ark-fresh ends the
  wave" revisit.

## 2. The redundant explicit daemon start

- [ ] **Explicit daemon start is redundant and logs a bark error** (B6
  re-verified at bark 0.8.0, 2026-10-25: `Wallet::open` calls
  `start_daemon()` when `WalletOpenArgs.run_daemon` is set, and the Swift
  `WalletOpenArgs` has had `runDaemon: Bool = true` all along — so the fix is
  either dropping the launch `runDaemon()` call or opening with
  `runDaemon: false` where the app wants to own the start): bark
  0.7.1's `Wallet::open` starts the daemon itself (`Starting daemon for
  wallet …` is logged before `Existing wallet opened successfully` on every
  launch, 2026-10-14), so `initializePrimaryMode`'s `runDaemon()` call
  produces `Called Wallet::start_daemon while daemon was already running` at
  error level on every launch, and the FFI wrapper still logs "Wallet daemon
  started successfully". Check the bindings for whether `runDaemon` is
  still needed on any path (create/import, after `stopDaemonWait`), then
  drop or guard the launch call and fix the misleading success line. Also
  counts toward the "four BDK syncs per launch" observation: the daemon's
  own esplora sync at open, Step 2's, and the two Step 3 history rounds.
  (The Tier 4 concurrency line "Daemon auto-start on `Wallet.open()` (bark
  0.7.0)" said the same thing and was merged here 2026-10-19.)
