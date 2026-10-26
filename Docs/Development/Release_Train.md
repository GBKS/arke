# Release Train

How open work in `../Open_Follow_Ups.md` gets built, verified and shipped to
TestFlight. Written 2026-10-07 after the backlog was restructured into
priority tiers; rewritten 2026-10-10 from a fixed two-week calendar to a
stage-gated train (DECIDED 2026-10-10: Christoph's schedule is not regular
enough for fixed dates; the sequence of stages is what matters). This file
describes the rhythm; the picks and the current stage of the running train
live at the top of `Open_Follow_Ups.md` so they sit next to the backlog.

## Why a train

Coding is fast; correct coding is not. An AI-assisted session produces a
first draft with tests in hours, but roughly a third of past sessions went
into revisiting generated code for faults no single file reveals:
device-scoped actions on account-scoped state, read paths fixed without
their write paths, task ownership, wrong assumptions about what bark does,
and claims in docs taken on trust (the five fault classes in
`Change_Review_Playbook.md`, with the incidents behind each in
`Rework_Ledger.md`). The other half of the slowdown was everything around
the code: fixes waiting weeks for a device check, proposals sitting
undecided, builds with no identifiable number.

The train budgets for both. Every cluster ends with a fresh-context review
against the five classes before it reaches a device, effort estimates carry
a 30% rework allowance, and verification and release are stages that cannot
be skipped instead of leftovers.

## The six stages

A train is one release. Its stages close in order, each on a condition, not
a date. A stage that is waiting for its owner simply waits; nothing behind
it starts early, nothing in front of it is skipped.

| Stage | Owner | Closes when |
|---|---|---|
| **Decide** | Christoph | Every entry in the backlog's "Decisions needed" is ruled or explicitly deferred (deferring is a ruling); the train's picks are confirmed (see "Picking"). Assistant records. |
| **Build** | assistant | The picks are done, **or roughly two weeks of working time are used, whichever comes first**. One cluster per session: plan first with every claim labelled verified / derived / assumed, the sweep of sibling sites listed, definition of done stated up front, tests with the change, scoped suite green, backlog updated in the same change, commit plan proposed. Christoph steers and commits. |
| **Review** | assistant | A fresh-context adversarial pass per cluster (`fault-class-reviewer`, handed only the diff and the area) has run; every finding is fixed or filed and each confirmed one has a `Rework_Ledger.md` line; the device checklist (`Device_Day_<date>.md`, dated the day it is written) exists. |
| **Device** | Christoph | The checklist has been run, both phones where a scenario needs them; passes closed in the backlog with date and build number, failures filed with the evidence attached. Happens whenever Christoph is next home with both devices after Review closes. |
| **Release** | both | Build number bumped, `/code-review` pass over the train's range done, mobile suite green via `xcodebuild`, **CloudKit schema deployed to Production** if any `@Model` changed since the last deploy (run a Debug build once so Development has the fields, then "Deploy Schema Changes…" in the CloudKit Console for `iCloud.gbks.sigma`; TestFlight builds talk to Production, which never creates types on its own — found 2026-10-26, Production had no schema at all until then), TestFlight upload done, release notes copied from the checked-off entries. |
| **Soak** | Christoph | About a week of normal use on the TestFlight build with one Organizer look and a log export at the end. Passive Tier 2 items (background kills, relay renewal, auth wakes) are only observable here, so a train is not closed before its soak. |

## Rules that replace the calendar

- **The two weeks are a soft budget for Build, not a deadline for the
  train.** When the budget is used, the assistant stops adding clusters and
  moves to Review with what is done. Scope shrinks; the sequence never does.
  A smaller release that went through every stage beats a bigger one that
  skipped Device.
- **Build and Review are the assistant's stages, so a train keeps moving
  while Christoph travels.** The Device stage waits with its checklist
  already written. One cap: no second train enters Build while the first is
  unreviewed, so the unverified pile can never exceed one release.
- **Soak may overlap with the next train's Decide and Build.** It may not
  overlap with the next Release: the soak's findings go into the next
  train's picks first.
- **Nothing seed-touching goes to TestFlight unverified**, even if it means
  reverting it off the release at the Release stage.
- **Tier 0 should be empty at Release.** If it is not, the next train picks
  nothing from Tier 3 or 4.

## Picking

Order of pull, every train:

1. Anything in **Tier 0** that is unblocked, in the order the "Current
   train" block ranks it (field evidence, size of loss, cost of the fix
   including its device step).
2. **Tier 2** items whose fix is already on the release — they go on the
   device checklist for free.
3. One **Tier 1** cluster (a feature or a themed group of fixes).
4. One **Tier 3** area pass, only if a Tier 1 item touches that screen anyway.
5. **Tier 4** only when a bindings bump or a neighbouring change makes it
   cheap.

Aim for roughly 60% of the time building, 20% verifying, 20% on the release
and soak. Do not fill the Build budget to capacity; the device stage always
finds something.

## Definition of done by tier

- **Tier 0 and anything touching seeds, deletion, exits or funds**: unit test
  pinning the decision + on-device check, two devices where the scenario
  involves them. No exceptions. See the memory rule "seed-touching changes:
  definition of done" and `Initialization/Launch_Sequence_Contract.md` for
  the invariants a fix must add a rule to.
- **Tier 1**: tests for logic, on-device look for UI, log evidence named in
  the backlog entry.
- **Tier 2**: the named log lines or screens observed; the item is checked
  off with the date and the build number.
- **Tier 3**: simulator screenshot or RenderPreview is enough. Copy changes
  ride along with whatever train is next.
- **Tier 4**: tests green, nothing else.
- **Translations**: never gate a train; they cannot break anything and ride
  along.

## Device stage conventions

The assistant writes `Docs/Development/Device_Day_<date>.md` when Review
closes, dated that day: one section per item, with (a) the setup state,
(b) the steps, (c) the exact log lines or screen states that mean pass,
(d) what to export if it fails. Christoph ticks the sections and pastes the
exported log path whenever he runs it. Afterwards the assistant closes the
passing items in the backlog and files the failures as new entries with the
evidence attached. Simulator log reads need `log show --info --debug`, or
info lines vanish; device logs redact private data and simulator logs do
not.

## Release conventions

- **Build number bumps on every TestFlight upload** so logs, Organizer
  crashes and field reports map to a build. Until this habit exists,
  fingerprint builds by log lines + `git log -S`.
- **Release notes** are the train's checked-off backlog entries; copy the
  titles into TestFlight "What to test" and name the device-stage items that
  testers can exercise.
- **Code review pass** (`/code-review` over the train's range) before the
  upload; findings go to the backlog, not into a last-minute fix unless
  Tier 0.

## The "Current train" block

At the top of `Open_Follow_Ups.md`. It names the train, the stage it is in
with the date that stage opened, the soft Build target date, the ranked
picks with their reasons, the explicit deferrals with their reasons, and
the device and soak lists. When a train closes, it is summarised in one
line under "Past trains" (what shipped, which stages waited and for how
long, how many ledger lines each stage produced) and the block is rewritten
for the next train.

## Infrastructure this plan assumes (Tier 4 items)

- CI on GitHub running the mobile suite on every push. Until it exists, the
  Release stage runs the suite by hand.
- A trustworthy macOS test suite (68 flaky failures today) before desktop
  work rejoins the train. Desktop is parked until then.
- The build-number habit above.

## Season trains (PROPOSED)

A season is a named run of trains with the pick weighting changed on
purpose and a consolidation train budgeted at the end. The first one
proposed is the exploration season in `Exploration_Season.md` (2026-10-07):
features and scope docs over stability, the app labelled experimental,
flagged features with kill-or-ship dates, and a floor of Tier 0, seed,
schema, network-config and money-path work that keeps the full process
throughout. Parked by Christoph 2026-10-09 until the most important items
are worked off; not a decision until he rules on the calls at the end of
that document.

## Review cadence of this document

Revisit after the third train, together with `Rework_Ledger.md`. Questions
to answer then: was Tier 0 empty at each Release, did any train skip Review
or Device, how long did Device and Release wait for their owner (the
real-life test of the stage model), how many Tier 2 items were closed per
device checklist, did the 60/20/20 split hold, how many ledger lines did
Review produce versus Device versus the field (Review should be catching
most of them), and which fault class dominates — that class gets the next
contract rule or test.
