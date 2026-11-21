# Bark FFI Bindings Migration: v0.27.0 → v0.28.0

**Date:** 2026-11-20
**Status:** ✅ DONE 2026-11-20, device-checked, commit plan proposed
(uncommitted). Three rulings DECIDED the same day (board lifetime,
recovery retry, interim entry closed); revision pinned in Xcode; build
green; adversarial pass returned (seven findings, one CONFIRMED fixed, see
below); full mobile suite after it 769/769 in 107 suites; device day the
same afternoon, all sections passed
(`Development/Device_Day_2026-11-20.md`: mainnet small sends against the
0.9.0 server, board expiry at the full server lifetime, seed import, exit
to confirmation, regression, relaunch). Owed: the TestFlight release
(Plan step 8) with the three release-note lines. The bump is Tier 1 (money path: every Lightning and Ark send against Second's
mainnet server, which runs bark 0.9.0 since 2026-11-19), so it gets the
adversarial pass and a signet device day before it is done.
**Bark Version:** v0.8.1 → **v0.9.0**
**FFI Bindings Version:** v0.27.0 → v0.28.0 (tag `v0.28.0+bark-0.9.0`,
published 2026-11-20 00:24 UTC; the tag is an annotated tag object
`c93f778ea30962d14267e99adcdae5d07864a659`, which is what the project pins,
and SwiftPM resolves it to commit `1c65cc1375974e89bbe344a9de9fd3a9da392d3f`
in `Package.resolved`). The `bark-ffi` crate moves
from `ca8f174` to `773b171` (tag `v0.32.0+bark-0.9.0.uniffi-0.31.2`),
uniffi stays 0.31.2 (`swift/rust/Cargo.toml` at both tags). Binary
XCFramework checksum
`617065cbd6725066c35c7e608210f886f24baa0b03807803e31ab40395ef1ba2`.

## Why this bump

Two reasons from Second, both **verified** in the bark 0.9.0 CHANGELOG
(`~/workspace/bark`, `git show bark-0.9.0:CHANGELOG.md`):

1. **Security fix** (MR 2803, reported by MrHodl): bark did not check that
   the unlock hash of its forfeits matched the one locking its new VTXOs.
   Client-side fix, no API change.
2. **Dust rejection** (MR 2822): the 0.9.0 server refuses an arkoor cosign
   request that puts an output below 330 sats on the checkpoint tx, and any
   request without a checkpoint tx. bark 0.8.1 and older leave dust change
   there whenever a part's non-dust outputs sum below 660 sats, so small
   sends and small-change sends fail with "upgrade your wallet and retry".
   Observed on mainnet 2026-11-19 (`Features/Lightning_Send_Settlement.md`
   §12). bark 0.9.0 puts every dust output in the isolation tx, also when
   all outputs are dust, so the payment shape the server refuses is no
   longer produced.

The shipped TestFlight build (bark 0.8.0) is affected the same way, so this
bump wants a TestFlight release behind it.

## API changes (generated `Bark.swift`, the two tags diffed 2026-11-20)

Diffed in a blobless clone (`/tmp/arke-bindings-compare/bindings`,
`git diff v0.27.0+bark-0.8.1 v0.28.0+bark-0.9.0 -- swift/Sources/Bark/Bark.swift`,
1060 diff lines). The NWC surface is not in the Swift file at all; it lives
behind a Cargo feature the Swift crate does not enable (`bark-ffi`
`src/muniffi/nwc.rs` is feature-gated, the Swift diff has no `Nwc` symbol).

| Change | Repo impact |
|---|---|
| `Config.init` gains a required `boardLifetime: UInt16?` parameter between `vtxoExitMargin` and `htlcRecvClaimDelta` | **Compile break, two sites.** `BarkWalletFFI.makeConfig` (value `UInt16.max`, see "Board lifetime") and the scratch-wallet `Config` in `BarkWalletFFI+ServerProbe` (`nil`, it never boards). The probe site was missed by the first grep and found by the build; sweep rule, again. |
| `RecoveryReport` gains `notFound` and `abandoned` buckets; `isComplete` now also requires no `abandoned` | None at compile time (the app reads, never constructs). `logRecoveryReport` and `retryRecoveries` in `BarkWalletFFI+WalletCreation` should log the two new buckets and retry `abandoned` alongside `failed` (binding doc: `recoverVtxos` is "to retry ids a previous recovery reported as `failed` or `abandoned`"). |
| `RecoveryStatus` gains `.inProgress(report:)` (wire tag 3; `.completed` moves to 4) | None at compile time, the app never switches on `RecoveryStatus`. Semantics matter, see "Recovery" below. |
| New `pendingRecovery() -> RecoveryReport?`, new `syncPendingRecovery()` | Unadopted; record in `Bark_Bindings_Unadopted_API.md`. |
| `recoverVtxos` now fails while a seed recovery is being driven | `retryRecoveries` runs right after the creating open; with 0.9.0 the recovery may still be in progress then, so the retry can error. The existing `catch` logs and skips, so the import does not fail, but the retry pass may become a no-op. See "Recovery". |
| `boardAmount` / `boardAll` / `boardFundingAddress` gain `expiryHeight: UInt32? = nil` | None, defaults apply at the three call sites in `BarkWalletFFI+VTXO`. |
| `boardPsbt(psbtBase64:funding: BoardFundingInfo)` replaces the keypair-index form; `BoardFundingInfo.keypairIndex` becomes `userPubkey: String`; new `legacyBoardFundingAddress(keypairIndex:expiryHeight:)` | None, the app calls none of these. Unadopted list. |
| `ArkInfo` gains `maxRoundParticipationOutputs: UInt32` | None, `ArkInfoModel` is built field by field. Optional: log it with the other fields in `getArkInfo`. |
| `CpfpParams.currentPackageFeeSats` becomes `replacedFeeSats`, `replacedFeeRateSatPerVb`, `incrementalRelayFeeSatPerVb`, `parentInMempool` (RBF rules per bitcoind) | None, the app uses bark's built-in BDK onchain wallet, not `CustomOnchainWalletCallbacks`. |
| `ExitTxStatus.confirmed(childTxid:block:origin:)` keeps its shape, but `childTxid` is **always empty** and `origin` is **always `.block(confirmedIn: block)`** (bark 0.9.0 dropped both fields; bark-ffi fills them for compatibility) | Compiles unchanged. `ExitTxStatus(from:)` in `ParsedExitState+Bark` keeps mapping it. One reader: `ExitTxStatus.cpfpChild`, which feeds `ExitStatusParser.extractTxids` (txid sets, user-funded CPFP fee linking); it now returns nil for an empty child txid. Residual (review F2): the wallet's CPFP child of a confirmed exit is only reachable through the history snapshot of `AwaitingConfirmation`, filed in Tier 2 Exits. `ExitStateMappingTests` covers both shapes. |
| `stopDaemonWait` semantics: a second concurrent call returns at once without waiting; a start made during the wait goes ahead afterwards | `BarkWalletFFI+WalletLifecycle.stopDaemonWait` and the import retry loop call it once each on a serialised path, so no change expected. Worth one read during review (ownership fault class). |

No method the app calls is removed. **Verified** by the diff above; the
uniffi checksum block confirms the changed method set (`board_*`,
`recover_vtxos`, `recovery_report`, `recovery_status`, `stop_daemon_wait`,
`make_signed_p2a_cpfp`) and the three new ones (`legacy_board_funding_address`,
`pending_recovery`, `sync_pending_recovery`).

## Behaviour changes that reach the app

### Recovery from seed resumes on every sync (MR 2678)

**Verified** at the binding docs and `bark/src/lib.rs` (`sync` calls
`sync_pending_recovery`; new `bark/src/actions/recovery.rs`). A VTXO whose
status the server cannot give yet stays locked and is retried on every sync,
up to `MAX_RECOVERY_ATTEMPTS` (40), after which it lands in `abandoned`
(still locked, retryable with `recoverVtxos`). The creating open therefore
no longer guarantees a final report: `recoveryReport()` is a snapshot as the
open saw it, `recoveryStatus()` can be `.inProgress`.

Repo impact on `ImportRecoveryLogic` / `openImportedWallet`:

- `decision(hasReport:attempt:)` treats a nil report as "the scan errored,
  wipe and retry". At 0.9.0 nil still means `NotRun` or `Failed`, and
  `.inProgress` carries a report, so the wipe-and-retry rule still only
  fires on a failed start. **Derived**, confirm when building.
- A `Recovery` checkpoint now exists as a `WalletActionCheckpoint`
  (`balance.rs`: held VTXOs are no part of the balance). The import's
  "VTXOs still pending" log line and the post-import balance may read lower
  until the recovery parks done. Worth a line in the import screen's
  expectations, not a code change.
- `retryRecoveries` right after open may hit "fails while a recovery from
  seed is being driven". **DECIDED 2026-11-20:** `openImportedWallet`
  switches on `recoveryStatus()` instead of testing the report for nil:
  `.completed(report)` logs and retries as today, with `abandoned` ids
  folded into the `failed` pass; `.inProgress(report)` logs the partial
  report and skips both retry passes. **Who resumes it (review F1, read at
  `bark-0.9.0`):** only `Wallet::sync()` calls `sync_pending_recovery`
  (`lib.rs`); the daemon's own loop does not. In the app that is `syncArk`
  inside `performRefresh`, which `initialize()` runs when onboarding hands
  over after the import (`MainView_iOS`), then every refresh after that.
  `.failed(message)` logs the message, then the existing wipe-and-retry;
  `.notRun` is treated like `.failed` (see "What was built"). The widened-gap `foreign`
  pass is lost for `.inProgress` imports; filed as a follow-up rather than
  built around (foreign ids are rare). The import screen's wording should
  allow for a balance that grows over the next syncs.

### Board lifetime defaults to 3 days on mainnet (MR 2802)

**Verified** at `bark/src/config.rs` (`board_lifetime: 72 * 6` on mainnet,
4320 on testnets, capped at the server's `vtxo_lifetime`) and the Swift
`Config.boardLifetime` doc. Until now a board VTXO lived the server's full
VTXO lifetime; at 0.9.0 it expires 432 blocks after boarding unless the app
sets `boardLifetime` or passes `expiryHeight`. With bark's refresh threshold
at 144 blocks (mainnet default, unchanged) a mainnet board now needs its
first refresh within about two days, which costs a round and a refresh fee.

**DECIDED 2026-11-20: pass `boardLifetime: UInt16.max`.** bark takes
`min(board_lifetime, ark_info.vtxo_lifetime)` before its range checks
(`board.rs` `funding_address`, read at `bark-0.9.0`), so the result is
today's behaviour exactly. Reasoning: once a board VTXO expires the server
can sweep the funding output alone, and every defence the app has is
foreground (launch-time refresh check, manual refresh, the "Time to
Refresh" local notification scheduled from each VTXO's own expiry height);
there is no background refresh pass and the expiry safety net
(`refreshVtxosScheduled`, DECIDED 2026-10-10) is unbuilt. A 3-day board
deadline would make "board Friday, reopen Tuesday" a loss. Revisit the
value when the safety net lands. Open question for Second: will the server
cap board lifetimes by policy? The cap applies either way. The value is a
`Config` field, so it applies at the next open, not retroactively.

### Exit transaction confirmation (MR 2815)

**Verified** in the CHANGELOG, bark-ffi `types.rs` and the Swift diff. bark
now treats an exit tx as confirmed by its own confirmation, so an exit that
confirms without a CPFP child, or before its child, keeps progressing. The
daemon also scans for force-exited VTXOs on every sync pass, not only at
start. App side: the exit state machine mapping is unchanged; the
`PersistentExitCache` snapshots written by older builds still carry a child
txid and a `.wallet` origin in `confirmed`, which round-trips through the
reverse mapper as before. `ExitTransactionStatus+Parsing` and `ExitProgress`
only test `case .confirmed`, no field read. Nothing to change, one test
fixture to re-label.

### Lightning sends

MR 2664: a retry of a failed Lightning payment gets its own movement.
MR 2771: fix of the send action when the HTLC cosign fails. **Not yet
re-read** against facts F1–F6 of `Features/Lightning_Send_Settlement.md`
§3; `bark/src/actions/lightning/pay.rs` changed by about 190 lines at
0.9.0 and `lightning_send_state` in `lib.rs` is untouched in the diff. The
F1–F6 re-read is part of the build step. The user-visible effect of 2664:
a retried failed send shows as a second Activity row instead of reviving
the first.

### Rounds and refresh

MR 2812: a round participation is capped at 1000 inputs; a refresh takes the
1000 VTXOs that expire first; the server bans the inputs of a cosigner that
withholds round signatures (9 blocks); `max_arkoor_amount` now applies to
Lightning sends; `ArkInfo.maxRoundParticipationOutputs` is new. The
consolidating-refresh interim (DECIDE entry, PROPOSED 2026-11-19) is moot
once this bump ships: 0.9.0 isolates dust change client-side, so no driver
is left for a consolidating refresh as a feature. **DECIDED 2026-11-20:**
closed to the Done log as superseded; the "Refresh all" advice for users on
the shipped 0.8.0 build goes into the TestFlight release note instead.

### Database

bark 0.9.0 adds sqlite migration 43 (an index on `bark_vtxo_state` and a
rebuilt `most_recent_vtxo_state` view; `persist/sqlite/migrations/m0043_index_vtxo_state.rs`).
The db migrates forward on the first open. **Assumed, not verified:** a
0.8.1 build will refuse a db at version 43, so a TestFlight user who installs
build N+1 cannot go back to build N. Same situation as every earlier bump
with a migration; note it in the release notes.

## Other bark 0.9.0 changes, not reviewed for this bump

From the CHANGELOG: NWC (not in the Swift surface), `BoardBuilder` and
`board_psbt` API (unused), `MakeCpfpFees::Rbf` replacement rules (bark's own
BDK wallet handles it; the exit's CPFP fee bumps now follow bitcoind's RBF
rules, which may raise bump fees on a stuck exit), `board_psbt` refuses a
funding address too close to expiry, server-side hardening and watchman fee
bumps. **Not verified** beyond the CHANGELOG.

## Playbook bark facts

Re-read at `bark-0.9.0` on 2026-11-20 (`~/workspace/bark`): B1 (`lib.rs:1479`,
`if !created_now`, still gates the recovery start; the recovery itself now
continues on later opens via sync, which is new behaviour, not a change to
the gate), B6 (`lib.rs:1506`, `if args.run_daemon`; binding default
`runDaemon: Bool = true` unchanged in the diff), B7 (`balance.rs` adds the
`Recovery` checkpoint arm, nothing else), B2 (`exit/mod.rs` diff is the RBF
field rename only, load-time filtering untouched). Not re-verified: B3
(timing), B8 (`onchain/bdk.rs` not in the 0.9.0 diff stat top list, so
likely unchanged; confirm with `git diff --stat`).

## Plan

Ordered; each step is its own commit except where noted.

1. **Pin the revision in Xcode** (Package Dependencies → bark-ffi-bindings
   → exact revision `c93f778ea30962d14267e99adcdae5d07864a659`). Christoph
   does this in the UI; never in `project.pbxproj`.
2. **Compile fix:** `makeConfig` gains `boardLifetime: UInt16.max` with a
   comment pointing here.
3. **Recovery edits** in `BarkWalletFFI+WalletCreation` per the ruling
   above: switch on `recoveryStatus()`; log `notFound` and `abandoned`;
   include `abandoned` ids in the `failed` retry pass; skip retries on
   `.inProgress`; a coverage test on `ImportRecoveryLogic` for the new
   bucket and the skip; file the lost `foreign` pass. This absorbs the
   Tier 4 backlog entry "`recoveryStatus()` adoption" (log `.failed`,
   distinguish never-ran), since the import path has to switch on
   `recoveryStatus()` anyway to see `.inProgress`.
4. **Mapper note + fixture** in `ParsedExitState+Bark` and
   `ExitStateMappingTests` for the always-empty child txid.
5. **Docs:** `Bark_Bindings_Unadopted_API.md` (baseline v0.28.0;
   `pendingRecovery`, `syncPendingRecovery`, `legacyBoardFundingAddress`,
   board `expiryHeight`, `maxRoundParticipationOutputs`),
   `Development/Setup.md` tag line, playbook B-facts lines, `README.md`
   version mention, this file's status, backlog: close the Tier 1 Send
   entry and the DECIDE interim entry to the Done log (same commit).
6. **Full mobile suite once** after the adversarial pass (Tier 1 rule).
7. **Signet device day:** a sub-330-sat Lightning send and an Ark send with
   dust change against a 0.9.0 server (the point of the bump); import from
   seed and watch the recovery park and resume across two syncs; board and
   check the new VTXO's expiry height against the ruling; one exit
   progressed to confirmation; a Lightning send failed at HTLC cosign and
   retried (MR 2664/2771).
8. **Release:** TestFlight build with the dust fix called out, plus the
   "cannot downgrade" note.

## What was built (2026-11-20)

- `BarkWalletFFI+Configuration.makeConfig`: `boardLifetime: UInt16.max`
  with the reasoning in a comment. `BarkWalletFFI+ServerProbe`: `nil`.
- `ImportRecoveryLogic`: `decision(hasReport:)` becomes
  `decision(outcome:)` over a Bark-free `RecoveryOutcome` (`notRun`,
  `failed`, `inProgress`, `completed`); `completed` and `inProgress`
  accept, `failed` and `notRun` wipe-and-retry until the cap. New
  `shouldRetryAfterOpen(outcome:)` is true only for `completed`.
  `retryPasses` takes `abandonedIds`, folded into the `failed` pass,
  de-duplicated. Review F6: on a creating open under 0.9.0 a `.completed`
  report has empty `failed` and `abandoned` buckets by construction
  (`recovery.rs`: completed means no failed left; 40 attempts cannot
  happen in one drive), so only the `foreign` pass can run there; the
  merged pass is kept for `recoverVtxos` callers and future bark versions.
  One deviation from the ruling's wording: `.notRun` is
  treated like `.failed` (wipe and retry) rather than "log only", because
  that is what the pre-bump code did for every nil report and `.notRun`
  cannot occur on a creating open with `skipRecovery: false`.
- `openImportedWallet` switches on `recoveryStatus()`; logs now carry
  `abandoned` and `notFound` counts and the `.failed` message.
- `ParsedExitState+Bark`: comment on the always-empty `childTxid`.
  `ParsedExitState.cpfpChild`: nil for an empty child txid (review F3:
  `extractAllTransactionIds` had started inserting "" as a txid).
  `ExitStateMappingTests`: the forward fixture uses the 0.9.0 shape, the
  round-trip fixture keeps the pre-0.9.0 shape and says why, plus a
  `cpfpChild` test for both shapes.
- Recovery log lines in `BarkWalletFFI+VTXO.recoverVtxos` and the retry
  pass now carry `abandoned` and `notFound` counts (review sweep).
- `Docs/Initialization/Launch_Sequence_Contract.md` rule 2 rewritten
  (review F7): "never started" wipes, "started" is kept.
- `ImportRecoveryLogicTests`: rewritten for the outcome enum, plus the
  in-progress-never-wipes, not-run, retry-gate and abandoned-dedupe cases.

Sweep for `Config(` memberwise inits: `makeConfig` covered, `ServerProbe`
covered (after the build caught it), `MockBarkWallet` exempt (no FFI
`Config`), tests exempt (none construct one). Sweep for `RecoveryReport` /
`RecoveryStatus` readers: `BarkWalletFFI+WalletCreation` only. Sweep for
`ExitTxStatus.confirmed` consumers: `ParsedExitState+Bark` (both
directions), `ExitTransactionStatus+Parsing` and `ExitProgress` (pattern
match only, no field read), `ExitStateMappingTests`.

## Documents

- `Docs/Bark_Bindings_Unadopted_API.md`: baseline v0.28.0, "New in
  v0.28.0" section (`pendingRecovery`, `syncPendingRecovery`, board
  `expiryHeight`, `BoardFundingInfo` / `legacyBoardFundingAddress`,
  `maxRoundParticipationOutputs`, `CpfpParams` RBF fields).
- `Docs/Development/Setup.md`: tag line, tag-object vs commit note.
- `Docs/Development/Change_Review_Playbook.md`: B1 (starts vs resumes), B2,
  B6, B7 re-verified lines.
- `Docs/README.md`: version mention.
- `Docs/Initialization/Launch_Sequence_Contract.md`: rule 2.
- `Docs/Open_Follow_Ups.md` / `Open_Follow_Ups_Done.md`: interim entry
  closed, `recoveryStatus()` entry absorbed, foreign-pass follow-up filed
  (Tier 4), CPFP-child-linking residual filed (Tier 2 Exits).

## Adversarial pass (2026-11-20, fault-class-reviewer, uncommitted diff)

Seven findings. CONFIRMED: F3 (empty-string txid in `extractAllTransactionIds`,
fixed). PLAUSIBLE: F1 (daemon does not drive a parked recovery; traced,
wording fixed, `initialize()`'s refresh is the resumer), F2 (CPFP child
linking after a fast confirmation; `cpfpChild` hardened, residual filed
Tier 2). Sound after checking: F4 (`.inProgress` reachable on the creating
open and correctly kept; `.notRun` unreachable; no lock collision on the
`.completed` retry), F5 (`UInt16.max` clamps before every range check on
both app board paths), F6 (buckets disjoint; the merged pass is dead on
this path). Doc drift: F7 (contract rule 2, fixed). Not verified by the
reviewer: the post-import resume on a flaky server (device), the history
snapshot before a fast confirmation (device), balance while VTXOs are
held by the recovery checkpoint, a backup taken mid-recovery restored on a
second device.
