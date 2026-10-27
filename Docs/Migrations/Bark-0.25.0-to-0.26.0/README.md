# Bark FFI Bindings Migration: v0.25.0 → v0.26.0

**Date:** 2026-10-25
**Status:** 🔨 Track A BUILT 2026-10-25 — build green, full mobile suite
538/538, adversarial pass done (two confirmed findings fixed, ledger);
device scenarios, CloudKit schema deployment, build 26 and the users'
procedure are Christoph's next steps. See
[04-completion-report.md](04-completion-report.md). Track B is filed under
Tier 4 "Bindings adoption" as the follow-on Train 2 cluster.
**Bark Version:** v0.7.1 → **v0.8.0**
**FFI Bindings Version:** v0.25.0 → v0.26.0 (resolved checkout
`ada76c33da82b77a794eb991f390c2cc042d373d`, tag `v0.26.0+bark-0.8.0`,
branch `master`; UniFFI contract version **30, unchanged** — verified at
`Bark.swift:12315`)
**Patch re-pin 2026-10-27:** v0.26.1+bark-0.8.0 (`4670c1a`), taken as an
exact-revision pin in the project. No migration folder of its own: the
Swift wrapper builds from the same `bark-ffi` crate commit `4a1c1c0`
(`swift/rust/Cargo.toml`, both tags) against the same bark-wallet 0.8.0,
and `swift/Sources/Bark` is byte-identical; the release carried
React Native and Dart notification fixes, Android packaging, and a new
xcframework checksum from the rebuild. Verified by diff of the two tags.

## Why this bump is different

The previous bumps were binding housekeeping with one feature each. This
one is a **recovery release**: two mainnet users have wallets that hold
VTXOs the server already spent in a refresh (the Tier 0 "wallet state
diverged" cluster), Second's remedy is recovery from seed, and every
client-side recovery fix is newer than the bark 0.7.1 our bindings carried.
`bark-0.8.0` contains all of them (`f83de1901`, `d9e305d0e`, `e9e78ad33`,
`f85ca92ac` — all verified as ancestors of the tag 2026-10-25). Christoph
also has a four-day-old refresh that is not finishing, which gives a third
device scenario (an in-place upgrade, not a re-import).

So the plan is cut for shipping the recovery path first and safely:

- **Track A — the release (DECIDED 2026-10-25):** compile fixes, the balance
  fields and total so the Ark total does not shrink, the new terminal exit
  state folded into today's cancelled handling, bark's logger kept
  unredacted, docs. Then the adversarial pass on the FFI boundary, three
  device scenarios, TestFlight build 26.
- **Track B — Train 2 cluster, PROPOSED:** everything else the binding
  surface offers or changes (proper `vtxoSwept` domain case, claim links
  from `vtxoIds`, movement ids, the exit-estimate rewrite, unified payment
  parsing, `walletExists`, finished-exit listing). Nothing in Track B is
  needed for the users' recovery.

Rulings recorded 2026-10-25 (Christoph): two-track split — **yes**; bark
logger stays public for this release — **yes**; server-side `server-0.8.0`
deployed — **"I believe it is"** (treated as **assumed**; the recovery
path degrades to the mailbox reader if not, see below); in-app "recover and
ignore the backup" path — **no, written instructions only**; needs-refresh
sats shown inside the balance card's Pending figure for this release
(option 1 in chat) — **yes** (02-migration-plan.md Phase 2 item 5).

## The things this repo must get right

1. **An app update alone does not heal a diverged wallet.** bark 0.8.0's
   `Wallet::sync` (`bark/src/lib.rs`, read at the tag) still never asks the
   server about VTXOs the wallet believes spendable; its one recovery-shaped
   addition, `catchup_recovery_vtxos`, re-posts our own VTXO ids for *future*
   recovery. The users must **re-import from seed on the new build**. A seed
   import in Arké is a creating `Wallet.open` with `skipRecovery: false`
   (`openImportedWallet`, Launch_Sequence_Contract rule 2), which is where
   bark's `recover_from_seed` runs. **Verified.**

2. **The iCloud database backup is a trap, and the trap is the Rejoin
   screen.** The only caller of the backup restore is `restoreWalletIfNeeded`
   in `WalletManager.performInitialization`: no local database plus a
   backup in iCloud Drive → the old, diverged `db.sqlite` comes back and
   the recovery scan never runs (bark scans only on the creating open —
   playbook B1, `created_now` gate still at `bark/src/lib.rs:1392` in
   0.8.0). After a **local-only** delete the device shows
   `RejoinWalletView`, whose single button runs exactly that path. The
   seed import (`WalletManager.importWallet(mnemonic:)` →
   `BarkWalletFFI.importWallet` → `openImportedWallet`) never calls the
   restore; it only logs whether a backup exists and writes a fresh backup
   at the end. The **full wipe deletes the backup** (`Backups/db.sqlite`,
   scope `.fullWipeOnly`), and the full wipe is offered only on the last
   registered device — a second device that still runs Arké re-registers
   itself on every launch, so "unlink it" does not get a user there. The
   user procedure in `02-migration-plan.md` is therefore part of the
   deliverable: other device deletes first, then full wipe, then import,
   never "Rejoin This Wallet". **Verified** (fresh-context pass 2026-10-25,
   findings 1 and 2).

3. **The xpub lookup degrades safely on an older server.** 0.8.0 recovery
   runs `recover_from_xpub` first; a `tonic::Code::Unimplemented` from the
   server logs "Server doesn't support VTXO recovery by xpub" and recovery
   continues with both mailboxes (`bark/src/recovery.rs:639-647`). The
   server-side mailbox checkpoint paging fix `dfd425d4a` is in
   `server-0.8.0` and **not** in `server-0.7.1`. Whether Second's server was
   on 0.8.0 was assumed at planning time; Christoph's mainnet re-import on
   2026-10-25 took the xpub path ("Server scanned 141 xpub children …"), so
   the server runs 0.8.0. **Verified** on both sides.

4. **The spendable balance shrinks unless the app adds the new field.**
   0.7.1 summed every `Spendable`-state VTXO; 0.8.0 moves expired and
   max-exit-depth VTXOs into `needs_refresh` and keeps them out of
   `spendable` (`bark/src/balance.rs`, both tags read). `ArkBalanceResponse`
   and `ArkBalanceModel` each compute their own `totalSat` from five fields,
   so the Ark total shown would drop by `needsRefresh + pendingArkoorSend +
   pendingOffboard`. The review pass found a fourth gap that predates this
   bump: `Balance.claimableLightningReceiveSats` (present since 0.7.1) is
   mapped nowhere, so the app total was already short by it. Phase 2 maps
   all four. The data half of the Tier 0 cluster's "balance card
   needs-refresh state" lands here; the card copy stays with that item.
   **Verified.**

6. **A non-"Unimplemented" error from the xpub lookup fails the whole
   recovery.** `recover_from_seed` tolerates only `tonic::Code::Unimplemented`
   from `recover_vtxos_by_xpub`; any other status is re-raised at the end
   (`xpub_result?`, `bark/src/recovery.rs:803`) even when both mailboxes
   recovered everything. In Arké that is `recoveryReport() == nil`, which
   `ImportRecoveryLogic` treats as "scan never ran": wipe the seconds-old
   database, reopen, bounded retries, then accept without recovery and log
   "Recovery scan never completed" — deterministically, in exactly the
   export the users would send. What Second's deployed server (or a proxy
   in front of it) answers for an unknown RPC is **not known**. Device
   scenario 2 is the test; if neither the xpub success line nor the
   fallback line appears and the report is nil, stop and ask Second before
   the procedure goes out. **Verified** on the client side (review pass
   finding 11), **unknown** on the server side.

5. **Two new breaking facts that nothing in the review predicted:**
   bindings commit `01db51c` makes `OSBarkLogger` interpolate every record
   as `.private` by default, which would turn bark's recovery lines into
   `<private>` in device logs and sysdiagnose — exactly the lines the users'
   next log export must show. `barkAttachOSLogger(maxLevel:redactMessages:)`
   keeps the old behaviour with `redactMessages: false` (DECIDED). And the
   first build after the bump fails on a stale precompiled module for the
   new binary (`barkFFI.h has been modified since the module file … was
   built`); deleting the `barkFFI-*.pcm` directories under
   `Intermediates.noindex/SwiftExplicitPrecompiledModules` (or Clean Build
   Folder) clears it. **Verified** (executed 2026-10-25).

7. **The full wipe deletes every synced row, and per-payment notes cannot
   come back.** `WalletDataCleanupService.deleteCloudKitData` removes
   transactions with their tag and contact assignments, tags, contacts,
   pending metadata, the exit cache, balances, device rows, addresses and
   the profile; nothing is exempt. The metadata export ("Contacts &
   Metadata" under Manual Backup) carries contacts, tags and profile, but
   its per-payment annotations are keyed by `movement_<id>`, which bark
   restarts from 1 after a seed import, and bark's recovery creates no
   movements for recovered funds. So notes and tags on payments are lost
   by design of the key, and an old export imported after new payments
   would misfile them. The procedure now says export first, import right
   after the re-import, and what the users will not get back. **Verified**
   (second review pass, user-outcome trace, 2026-10-25).

8. **Savings funds are invisible after a seed import unless the app runs
   bark's onchain initial scan.** Nothing calls
   `OnchainWalletProtocol.initialScan(birthdayHeight:)`; `sync` covers only
   revealed addresses, and a fresh import reveals index 0. Same hole as
   feedback ask 7c (8,839 sats, network-verified). One call after
   `openImportedWallet` fixes it with no UI; Phase 4 of Track A, **DECIDED
   2026-10-25**. **Verified** on the absence of the call, **derived** on the
   index-0 reasoning.

Rulings after the two review passes (2026-10-25): Phase 4 in Track A —
**yes**; soak overlap — moot, Christoph is back from Lugano and Train 1's
soak is closed before build 26 ships (minor findings recorded separately
by him); the xpub RPC question — answered from source, see chore 4b in
02-migration-plan.md.

## Corrections to the pre-repo review

The review's binding-level diff is accurate in full (every signature,
field and case re-read from the resolved checkout). Its repo-impact and
behaviour claims over-predict, as in every previous bump:

- ❌ "`pay*` `retryForSecs` and `estimateEmergencyExitFee` `feeMargin` will
  stop the build." — **No.** `BarkWalletFFI` holds the concrete
  `Bark.Wallet` class (`BarkWalletFFI.swift:79`), where both parameters
  default to `nil` (`Bark.swift:3979-4019`, `:3192`). Only bark's own
  `WalletProtocol` lacks the defaults and nothing conforms to it. The
  lightning file compiles apart from its `LightningSend` constructors.
  `estimateEmergencyExitFee` has no caller at all (it is the DECIDED Train 2
  Tier 1 Exits item, still unbuilt).
- ❌ "Rename `finishPsbt` if the project implements
  `CustomOnchainWalletCallbacks`" — nothing does (same zero-hit grep as
  0.19→0.23 and 0.24→0.25; the protocol's only signature change between the
  tags is that rename).
- ❌ "Handle `ExitStateKind.vtxoSwept`" — no reference to `ExitStateKind`
  in the repo.
- ❌ "Simplify the `setLogger` already-installed guard" — there is none; the
  one call is `barkAttachOSLogger(maxLevel: .debug)` at
  `BarkWalletFFI.swift:67`. The real logger change is the redaction default
  (fact 5).
- ❌ "`getExitStatus` now also returns finished exits; the app no longer needs
  to save them at drain time." — **Not a behaviour change.** bark 0.7.1's
  `get_exit_status` already served live *and* finished exits from the
  persisted exit table with the same Rust doc comment; only the Swift
  comment is new. What stays true is playbook fact B2: `getExitVtxos()`
  lists live exits only (now stated in its doc at `Bark.swift:2254-2257`).
  `PersistentExitCache` is not made redundant by this bump; the new
  `listFinishedExits` is a Track B adoption question. Bonus for B2's open
  question: a cancelled exit's row "remains on disk for auditing"
  (`cancel_exit`, both tags).
- ❌ "Replace `fundable` uses" — there are none; `ExitView_iOS.calculateExitCost`
  still prices exits by hand. The Tier 1 entry that *plans* on `fundable`
  needs rewriting (Track B).
- ⚠️ "Every exhaustive switch on `ExitState`" — exactly **two** switch
  directly on the Bark enum and fail (`ExitVtxo+Extensions.swift:20`,
  `ParsedExitState+Bark.swift:27`). The other ten or so switch on the
  app's own `ParsedExitState`, a Codable enum persisted in exit snapshots.
  Whether that enum gains a `vtxoSwept` case is the real decision; Track A
  folds the new state into `vtxoAlreadySpent` (lossy, documented, pinned by
  a test), Track B adds the case.
- ⚠️ "Likely hits the mock wallet and ExitClaimSequence tests" — the
  verified list is **21 errors in 11 files** (`01-api-changes.md` §4), all
  mechanical.

## Impact summary

- **Compile errors:** 21 verified (per-file diagnostics after the module
  cache was cleared; the compiler stops after the first failed job, so the
  build summary showed one). One warning (`sendArkoorPayment` unused
  result).
- **Protocol changes (Track A): none.** `BarkWalletProtocol` compiles
  unchanged; every break is in conformers, fixtures, the exit cache and the
  two Bark-enum switches.
- **User-visible behaviour from the recompile alone:** Ark total drops for
  any wallet with expired VTXOs or an arkoor send / offboard in flight
  (fact 4) — fixed in Track A; bark log lines go private (fact 5) — fixed
  in Track A; `pendingInRoundSat` now counts the locked *inputs* of a round
  instead of its requested outputs, and `claimableLightningReceive` counts
  only after the preimage is revealed (bark changelog #2509) — accepted,
  breakdown rows only.
- **Behaviour changes with no code on our side:** finished exits stop
  rewriting their movement on every sync (#2610, feedback ask 11); round
  registration no longer locks inputs until an attempt starts, and an
  awaiting participation that lost inputs shrinks, is cancelled, or is
  re-delegated on sync (#2443) — the candidate explanation for Christoph's
  stuck refresh, **derived** from the changelog, device scenario 1.
- **Deferred to Track B:** `03-impact-analysis.md` §5 lists each item with
  the backlog entry it serves.

## Documents

1. **[01-api-changes.md](01-api-changes.md)** — verified API diff with
   verbatim declarations, the verified error list, and the behaviour
   changes read from bark source.
2. **[02-migration-plan.md](02-migration-plan.md)** — Track A phases, tests,
   the device checklist with the three scenarios, the user procedure, and
   chores; Track B as a PROPOSED list.
3. **[03-impact-analysis.md](03-impact-analysis.md)** — the review angles
   (money, exits, recovery, startup, logging, tests) and the backlog match:
   what this bump closes, changes, or must not trample.
4. **04-completion-report.md** — to be written when Track A lands.

## Verification note

Binding declarations were read from the resolved checkout's `Bark.swift`
at `ada76c3` and diffed against the previous checkout at `157b0fc` (both
present under DerivedData `SourcePackages/checkouts/bark-ffi-bindings`,
the two `Arke-*` DerivedData folders hold one each). Bark behaviour was
read from `~/workspace/bark` at tags `bark-0.7.1`, `bark-0.8.0`,
`server-0.7.1` and `server-0.8.0`. Repo facts (conformers, call sites,
persistence paths, the import flow, the backup restore) were verified by
grep, file reads and one build with per-file diagnostics on 2026-10-25.
Not executed: any test, any device run, any recovery.

The plan itself had a fresh-context adversarial pass on 2026-10-25
(general-purpose agent, read-only, handed the four files and the
playbook): fifteen findings, all folded in — the Rejoin-screen trap, the
second-device rule, the unmapped claimable-lightning-receive field, five
`ArkBalanceModel` constructors in `ReadOnlySyncedDataTests`, the
round-trip mapping test that must not gain the new case, `isCancelled`
already omitting `.canceled`, the card and forfeit-summary arithmetic, a
non-existent bark symbol in §3.6, the xpub error path, and screen wording
in the procedure.

`Package.resolved` already points at `ada76c3` on branch `master`
(uncommitted). The pin-to-tag item in the Train 2 ops list (Xcode UI,
Christoph's hands) matters more for this release than usual: the users'
fix depends on exactly this binary.
