# Change Review Playbook

How to review a change — and, more usefully, **what to ask for**. Companion
to `Testing_Patterns.md` (what to test) and
`../Initialization/Launch_Sequence_Contract.md` (ordering invariants that
review should check against).

Written 2026-09-21 after the VTXO refresh-deduplication work
(`../Features/Refresh_Deduplication.md`) needed four review passes. Each pass
found new defects, but not because it was more thorough than the last —
because it used a **different method**:

| Pass | Method | What it can find |
|------|--------|------------------|
| 1 | Read the diff | Defects visible in changed lines |
| 2 | Run things (all affected targets) | Defects only visible by executing |
| 3 | Trace data flow past the diff | Defects in *unchanged* code the change depends on |
| 4 | Attack the fix; walk error paths | Defects in non-happy paths, and in pass 3's own fix |

The most serious defect in that work — `refreshAfterVTXOChange()` refetching
the Ark-only service while every reader went through the unified service's
*stored* merge, leaving the new guard inert — was one hop away from the
function under review and survived two passes. Reading the diff harder would
never have found it.

**The lesson: repetition doesn't help, changed method does.** "Review it
again" mostly re-reads the diff. Ask for a method instead.

## The prompts

### Default — refute your own fix

For load-bearing work this is usually the only one needed. It's what produced
the fourth pass.

> Try to refute your own fix. For each change you made, state what would have
> to be true for it to actually work, then go check whether it is. Cover the
> error paths, concurrent entry, and cold start. Don't re-read the diff.

### When the change derives a signal, adds a guard, or caches state

Highest value of the set — this is the one that found the stale merge.

> Trace the load-bearing path end to end with file:line — writer → store →
> reader. For each store, is it live or cached, and who invalidates it? Do
> that before commenting on anything else.

### When the change adds a gate or exclusion

Found that five code paths could schedule a refresh while only two consulted
the new guard.

> Enumerate every code path that can reach this, not just the ones in the
> diff. For each, does it go through the new guard or bypass it?

### When the work leans on a design doc

Found that "three writers", "we pin 144 blocks", and "status mapping
verified" were all false. Our docs are load-bearing, which makes stale claims
*more* dangerous, not less.

> List every claim — yours or the doc's — that you relied on but didn't
> execute or trace. Verify each one and correct whatever's wrong in place.

### When a fix changes *when* something becomes true

Found a VoiceOver announcement and the exit-cancellation advisory that had
both been silently inert.

> What else reads the thing whose behaviour you changed? For each consumer,
> does it now fire more, less, or differently?

### The cheap one-liner

Highest value per word. Targets the costliest failure mode: an assistant
asserting something is correct without having checked.

> What did you not verify?

### Two more cheap ones (added 2026-10-07)

Same cost, different target: the judgment calls a diff hides. Ask before
approving any generated change of substance.

> What was the hardest decision you made here, and why did you decide it
> that way?

> What alternatives did you reject, and why?

The first surfaces where the builder had to guess; the second catches a bad
choice made confidently. Neither replaces "what did you not verify?".

### Before the work, not after

Front-loads the check that failed above.

> Before you start: what's the write→read path for this, and what will you
> actually run to verify it?

## Process

**Two passes, not four.**

1. **Build pass** — trace write→read, walk error/concurrent/cold-start paths,
   verify any doc claim being relied on, build and test every affected
   target. Then commit.
2. **Adversarial pass** — one review whose job is to attack the fix, not
   re-read the diff. Genuinely not compressible into pass 1: the fix doesn't
   exist yet.

Then push.

**The gate is push, not commit.** While commits are unpushed they're free to
amend, so commit early rather than treating commit as the moment everything
must be perfect. That removes the pressure that makes extra pre-commit rounds
feel necessary.

**Scale by risk.** Most work needs neither pass: mechanical edits, view
tweaks, doc changes, additive tests. Reserve the full drill for changes where
silent failure is expensive — derived signals and guards, money paths,
startup ordering, seed handling, the bark FFI boundary.

**Pick one prompt, don't stack.** Match the change shape: signal/cache →
trace; new guard → enumerate; doc-driven → claims audit; otherwise → refute.
If the trace already happened during the build pass, skip straight to refute.

**Know what review can't reach.** Some questions are device answers, not
reading answers — whether a movement parses with the expected
`subsystemKind`, whether a refetch really observes its own write. That's what
a feature doc's on-device verification section is for. Past a point, another
review pass is a worse investment than one signet run.

## Expectations

This shape would have compressed the refresh work's four passes into about
two. It would not have made the first pass complete — reviewing one's own fix
reliably finds something, which is why the adversarial pass stays in the
default rather than being an escalation.

## The five fault classes (added 2026-10-07)

A look back over the Done log in `../Open_Follow_Ups_Done.md` found that
about a third of sessions since August went into revisiting generated code,
and that the faults cluster into five classes. None of them is visible from
inside the file being changed; all of them are "the thing that was never
loaded". The adversarial pass checks each one explicitly. Incidents per
class are logged in `Rework_Ledger.md`.

| # | Class | The question to ask | Incidents (Done log) |
|---|-------|---------------------|----------------------|
| 1 | **Scope** — a device-scoped action touching account-scoped state, or the reverse | For every write and delete: which store, and is that store per device or per account? Who else reads it? | FFI `deleteWallet` deleting the synchronizable seed (08-19); local-only delete clearing KVS network config (08-20); local-only delete cascading CloudKit-mirrored assignments (09-23) — three instances of one class |
| 2 | **Path asymmetry** — the read path fixed without its write path; the live store without its cached twin; one of several entry points | Trace writer → store → reader with file:line. Is each store live or cached, and who invalidates it? Enumerate every path that reaches this, not just the diffed one. | `refreshAfterVTXOChange` refetching the Ark-only service while readers used the stored merge (09-21); invalidation fix covering reads but not writes, then the write fix causing a fetch storm (09-25); mirror cleanup inside an `if let` with no else, leaving permanent ghosts (09-24) |
| 3 | **Ownership** — who owns a task, a key, a cancellation, a notification; what runs before the wallet is open | For each shared resource the change touches: who creates it, who removes it, what happens when two callers overlap or the second arrives early? | `execute` removing `executeFresh`'s key (09-24); `cancel`/`cancelAll` never working (invariant generics, found 09-21); remote-change notifications dropped in the 1.5–2.0 s band (09-24); pre-open refresh banner (10-01) |
| 4 | **Boundary assumptions** — what bark, CloudKit or iOS actually does versus what the API name suggests | Which external behaviours does this rely on? For each: verified at the bindings tag / in the FFI source / by log, or assumed? | `initWallet` + `open` disabling the recovery scan (08-10); bark replaying finished exits on a fresh DB (08-13); bark purging claimed exits from `getExitVtxos` (08-13); 150 s/block assumed for signet (09-27) |
| 5 | **Trusted claims** — a doc, comment, log line or tool result taken as true | List every claim relied on but not executed or traced. Verify each. | 33% of a guiding doc's claims wrong (09-21 claims audit); `matchedTxid` "for debugging" but load-bearing (09-27); seeding guard built on the wrong hazard model (role, not import state; 09-25); keyword sweep with `\|` returning false zeros (10-07) |

### Fresh-context adversarial pass

The builder's blind spots persist within a session: the assumptions that
shaped the fix are still loaded and still feel true. So the adversarial pass
runs in a **new context** — a fresh session, or a subagent — that receives
only: the diff (or commit range), the contract(s) for the area, the five
classes above, and this instruction:

> You did not write this change and must assume it is wrong somewhere. For
> each of the five fault classes, state what would have to be true for the
> change to be safe, then go check in the source whether it is. Enumerate
> sibling sites of every pattern the change touches. Report findings as
> CONFIRMED (you read the code that breaks) or PLAUSIBLE (you could not
> rule it out), never as "looks fine". End with: what did you not verify?

It replaces the "refute your own fix" prompt for Tier 0/1 work and runs on
day 7 of the release train (`Release_Train.md`). For Tier 3/4 the self-review
prompts above remain enough.

The prompt is packaged as a repo agent definition,
`.claude/agents/fault-class-reviewer.md` (added 2026-10-07). It is read-only,
fetches the diff and the contracts itself, and reports in the format above.
Invoke it as "run the fault-class-reviewer agent on `<range>`". Agent
definitions are loaded when a session starts, so a session that was already
open when the file was added will not see it (verified 2026-10-07 inside the
Xcode integration). Fallback that works anywhere: spawn a general-purpose
subagent told to read `.claude/agents/fault-class-reviewer.md` and follow it
on the range. Either way the reviewer gets a fresh context, which is the
point.

### Claim labels in plans

Every plan or proposal marks each factual statement it builds on as one of:

- **verified** — executed, traced to file:line, or read at the bindings tag;
- **derived** — follows from verified facts by reasoning the reader can check;
- **assumed** — neither; must be verified before anything is built on it.

An "assumed" claim about bark, CloudKit, or the keychain blocks the build
step until it moves to "verified". This is the plan-stage form of the claims
audit (`Claims-audit review method` in the assistant's memory): checking the
doc against the code before the code exists, instead of after.

### The sweep

Before a change is called done, grep for every sibling of the pattern being
changed — every other call site of the method, every other store written by
the same policy, every other path that reaches the guard — and list them in
the plan with a one-word verdict each (covered / exempt-because / missed).
Three of the worst incidents in the ledger were a second site nobody looked
for. The sweep is a checklist item, not a habit.

### Area contracts (stubs — grow from the ledger)

`../Initialization/Launch_Sequence_Contract.md` is the model: short numbered
rules, each with the incident that produced it and an Enforced / Test
column. It already covers startup, exits, multi-device detection and
deletion (rules 19–26 are the scope rules). The four areas below have no
contract yet; each stub holds the rules the ledger already supports. When a
stub passes about eight rules, move it to its own file next to the launch
contract and link it here.

**Data scope (class 1).**
- S1. Every delete names its scope — `.localOnly` or `.everywhere` — and
  only `WalletDataCleanupService` deletes CloudKit-mirrored rows or
  synchronizable keychain items (launch contract rules 19, 21, 23).
  Enforced: `WalletDataCleanupService`. Test: `WalletWipeCoverage`,
  `TransactionDeletionBlastRadiusTests`.
- S2. The network config is the only account-authoritative state class;
  payment data is the inverse (device-authoritative, mirrored up). A change
  that syncs in the other direction needs a written reason.
  Enforced: `NetworkConfigPersistence`, `reconcileNetworkConfigBeforeWalletOpen`.
  Test: `NetworkConfigReconciliationTests`.
- S3. Seeding default data is gated on import state, never on device role
  (rule 26). Enforced: `CloudKitFirstImportGate`.
  Test: `DefaultDataSeedingDecisionTests`.
- S4. A CloudKit-mirrored row is never deleted outside the cleanup service,
  even to dedupe — see the duplicate-defaults DECIDE item.

**Data paths (class 2).**
- P1. Readers of merged or derived data go through the stored merge
  (`unifiedTransactionService.allTransactions`); a writer that refetches
  must call `mergeTransactions()`. Enforced: `refreshAfterVTXOChange`.
  Test: none.
- P2. A post-write refetch must not join an in-flight fetch that predates
  the write (`executeFresh`, `refreshTransactionsAfterWrite`).
  Test: `executeJoinsFreshTaskAfterDrain`.
- P3. Never read element properties off a cached to-many relationship
  array; fetch and read in one main-actor pass (`live*` accessors). Applies
  to writes as well as reads. Test: `TransactionMetadataResolutionTests`,
  `TransactionMetadataWritePathTests`.
- P4. Cleanup that must always happen does not live inside an optional
  binding — `defer` or an unconditional path (mirror clear, 09-24).
  Test: none (Tier 0 item open).

**Task ownership (class 3).**
- O1. A dedup key is removed only by the task that holds it (Task identity
  `==`). Test: `executeJoinsFreshTaskAfterDrain`.
- O2. A throttle defers, it never drops: anything arriving inside the
  minimum interval is folded into a pending run. Test: `RemoteChangeThrottleTests`.
- O3. Nothing that needs bark runs before the handle is open; it skips with
  a log line (rule 7b). Enforced: `performRefresh`, `BalanceRefreshStatusViewModel`.
- O4. `cancel`/`cancelAll` on the dedup manager are known no-ops; do not
  rely on them until the Tier 4 item lands.

**Bark facts (class 4).** Verified at the bindings tag named; re-verify on
every bump (the migration guides in `../Migrations/` are where that happens).
- B1. The seed-recovery scan runs only on the creating `open`
  (`created_now`); `initWallet` first disables it forever (bark 0.7.x).
- B2. Claimed exits are purged from `getExitVtxos()`; snapshot at drain
  time (`PersistentExitCache`). Cancelled exits: unknown — open question
  under the `cancelExit` item.
- B3. On a fresh DB bark replays finished exits through the state machine
  for ~2 s; they read as in-flight.
- B4. Signet runs ~10 min/block like mainnet; `BlockTimeFormatter.secondsPerBlock`
  is the single source (600).
- B5. `nil` fee rate means internal estimation on mainnet only; off mainnet
  pass the capped app-side rate.
- B6. The daemon auto-starts on `Wallet.open()` since bark 0.7.0; our
  explicit `runDaemon()` may restart it (unconfirmed — Tier 4 item).
