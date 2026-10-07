# Release Train

How open work in `../Open_Follow_Ups.md` gets built, verified and shipped to
TestFlight. Written 2026-10-07 after the backlog was restructured into
priority tiers. This file describes the rhythm; the picks for the current
train live at the top of `Open_Follow_Ups.md` so they sit next to the backlog.

## Why a train

Coding is not the constraint. An AI-assisted session produces a fix with
tests in hours. What slowed the project down for two months was everything
around it: fixes waiting weeks for a device check, proposals sitting
undecided, builds with no identifiable number. The train makes verification
and release scheduled events instead of leftovers.

## The two-week cycle

| Day | What happens | Who |
|---|---|---|
| 1 | **Decide.** Walk the "Decisions needed" section of the backlog; rule or explicitly defer each. Pick the train's items (see "Picking"). | Christoph rules, assistant records |
| 2–7 | **Build.** One cluster per session. Plan first, definition of done stated up front, tests with the change, scoped suite green, backlog updated in the same change, commit plan proposed. | assistant builds, Christoph steers and commits |
| 8 | **Device day.** Run the checklist the assistant prepared the day before: one block per Tier 2 item with the exact steps and the log lines to grep. Two-device scenarios need both phones. | Christoph |
| 9 | **Release candidate.** Bump the build number. Assistant runs a code-review pass over the train's diff. Mobile suite green via `xcodebuild`. Upload to TestFlight. | both |
| 10–14 | **Soak.** Passive Tier 2 items (background kills, relay renewal, auth wakes) are only observable here. Check Organizer crash data once. Normal use with log export at the end. | Christoph |

If a train slips, it slips at the build days, never at the device day or the
release. A smaller release on time beats a bigger one late, because the soak
window is what closes the passive items.

## Picking

Order of pull, every train:

1. Anything in **Tier 0** that is unblocked. Tier 0 should be empty at the
   end of a train; if it is not, nothing from Tier 3 or 4 is picked.
2. **Tier 2** items whose fix is already on the release branch — they go on
   the device-day checklist for free.
3. One **Tier 1** cluster (a feature or a themed group of fixes).
4. One **Tier 3** area pass, only if a Tier 1 item touches that screen anyway.
5. **Tier 4** only when a bindings bump or a neighbouring change makes it
   cheap.

Aim for roughly 60% of the time building, 20% verifying, 20% on the release
and soak. Do not fill the build days to capacity; the device day always finds
something.

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

## Device day conventions

The assistant writes `Docs/Development/Device_Day_<date>.md` the day before:
one section per item, with (a) the setup state, (b) the steps, (c) the exact
log lines or screen states that mean pass, (d) what to export if it fails.
Christoph ticks the sections and pastes the exported log path. Afterwards the
assistant closes the passing items in the backlog and files the failures as
new entries with the evidence attached. Simulator log reads need
`log show --info --debug`, or info lines vanish; device logs redact private
data and simulator logs do not.

## Release conventions

- **Build number bumps on every TestFlight upload** so logs, Organizer
  crashes and field reports map to a build. Until this habit exists,
  fingerprint builds by log lines + `git log -S`.
- **Release notes** are the train's checked-off backlog entries; copy the
  titles into TestFlight "What to test" and name the device-day items that
  testers can exercise.
- **Code review pass** (`/code-review` over the train's range) before the
  upload; findings go to the backlog, not into a last-minute fix unless
  Tier 0.
- **Nothing seed-touching goes to TestFlight unverified**, even if it means
  reverting it off the release.

## Infrastructure this plan assumes (Tier 1 items)

- CI on GitHub running the mobile suite on every push. Until it exists, the
  release-candidate step runs the suite by hand.
- A trustworthy macOS test suite (68 flaky failures today) before desktop
  work rejoins the train. Desktop is parked until then.
- The build-number habit above.

## Review cadence of this document

Revisit after the third train. Questions to answer then: is Tier 0 empty at
each release, did any train skip its device day, how many Tier 2 items were
closed per device day, and did the 60/20/20 split hold.
