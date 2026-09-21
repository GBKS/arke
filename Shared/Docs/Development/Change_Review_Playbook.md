# Change Review Playbook

How to review a change — and, more usefully, **what to ask for**. Companion
to `testing-patterns.md` (what to test) and
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
