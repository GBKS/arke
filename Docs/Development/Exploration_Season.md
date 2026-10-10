# Exploration Season

**Status:** PROPOSED 2026-10-07 — written from a conversation with Christoph;
nothing here is decided until he rules on the calls at the end. Once ruled,
the decided parts move into `Release_Train.md` (season trains) and the picks
into the "Current train" block of `../Open_Follow_Ups.md`.

## What this is

A run of release trains with the pick weighting inverted: new features and feature scoping over stability, the app labelled
experimental for the duration, every new feature behind a flag or in the
Experimental section of Settings. The ten features come from Christoph's
roadmap blog post. The goal is to move the app towards its end state and
learn what the shared architecture underneath those features wants to be,
while the user base and the funds at stake are still small.

It is a **mode**, not a speed. The train rhythm stays (decide, build,
review, device day, TestFlight, soak). What changes is what gets picked,
how much review the non-money surfaces get, and what "done" means for a
flagged feature. The season runs in four phases with exit criteria, the last
of which is consolidation, so it cannot quietly become the new normal.

## Why now

- Few users, none depending on the app for daily money. Instability is
  cheap now and gets more expensive with every user and every sat.
- The design is not at its end state. Serial, careful work polishes screens
  that profiles, policies and a programmatic send path will reshape anyway.
- Pulling on the shared core from several features at once teaches the
  shape of that core. Serial work cannot.
- A public "experimental" story invites feedback while changes are cheap.

## The floor that does not move

A feature flag hides a screen. It does not hide a SwiftData model change, a
`WalletManager` edit or a contacts-model refactor. Those ship to every device
on the account whether the toggle is on or off, and the CloudKit schema is
additive-only, so an experimental model is permanent the moment it syncs.
Most of the `Rework_Ledger.md` entries live in exactly that shared core.

During the season the following keep the full process (plan with labelled
claims, sibling sweep, fresh-context adversarial pass, device verification,
definition of done per `Release_Train.md`), without exception:

- Everything Tier 0 and everything the seed-touching rule covers: mnemonic
  keychain item, iCloud KVS wallet hash, deletion, registration, exits.
- Network configuration (account-authoritative, pre-open): the multiple
  servers feature lands here.
- Any SwiftData schema change, any new CloudKit-mirrored row, any new
  shared key (must be added to `SharedStateWipeCoverage`).
- Any code path that moves money: `WalletManager` send/receive, fee
  selection, the bark FFI boundary.
- Startup ordering (`../Initialization/Launch_Sequence_Contract.md`).

The boundary is drawn by **area and file**, not by feature, so a feature
cannot argue its way under it. A flagged feature that needs a model change
gets the model change built and reviewed as a normal Tier 1 item first, then
the flagged UI on top.

## What relaxes above the floor

- Flagged UI, new screens, assets, sound, themes, intents that call existing
  send/receive entry points: Tier 3 definition of done (simulator screenshot
  or RenderPreview), a one-paragraph plan instead of a labelled-claims plan,
  no day-7 adversarial pass unless the diff crosses the floor.
- Scope documents replace build days for the features that cannot reach
  code this season (see the sorted list).
- Translations are ignored for flagged features until the flag ships.
- The 60/20/20 build/verify/release split shifts towards build; the device
  day still happens every train for the floor-touching diff and for Tier 2.
- The compound loop keeps running regardless: backlog entries, ledger lines,
  Done-log write-ups. "It's experimental" is not a reason to skip them.

## The experimental label and the gate

The label (TestFlight notes, in-app banner or Settings header, website) is
honest signalling. It tells testers what to expect. It does not make a
mainnet user's loss smaller. Two gate options, Christoph to pick one:

- **G1 — opt-in toggle with warning.** Experimental features are off by
  default, enabled per feature in the Experimental section, each toggle's
  footer says what is unfinished.
- **G2 — G1 plus non-mainnet only.** Toggles are disabled on mainnet with a
  footer explaining why. Features reach mainnet only when they graduate out
  of the season.

Recommendation: G2 for anything that touches a payment (intents, swaps UX,
usernames send path), G1 for everything else (sound, expression, habits,
accounting).

## Flags

Convention proposed for the season:

- One `@AppStorage` key per feature, prefixed `experimental.`, read through a
  single `ExperimentalFeatures` accessor so the registry is greppable. DEBUG
  builds may force a flag on; release builds never do.
- Every flag is listed in the registry table below with a **kill-or-ship
  date** no later than the consolidation train. On that date the feature
  either graduates (flag removed, full definition of done met) or the code
  is deleted. No flag outlives the season.
- A flag's footer in Settings names what is unfinished, in one sentence.

| Flag | Feature | Added | Kill-or-ship | Outcome |
|---|---|---|---|---|
| (none yet) | | | | |

## The three shared abstractions

Most of the ten features sit on one of these. They are designed on paper in
Phase 1, together, before any feature that depends on them is built. Each gets a short design doc under `Docs/Architecture/` with a
`**Status:**` line.

1. **Profiles.** Today a contact is a name plus addresses. Usernames,
   payment-info sharing, the receive screen and the agents hub all want a
   profile: identity, one or more payment handles, display preferences,
   possibly an avatar. This refactor rewrites the contacts model and is a
   schema change, so it lives under the floor. Anything contacts-adjacent
   built before it exists is rework by construction (Scope fault class).
2. **Policy engine.** Good habits (nudges when a threshold is crossed) and
   the agents hub (allowances, per-agent limits, approvals) are the same
   machinery: rules over balance, frequency, counterparty and fee, evaluated
   at well-defined points, with a UI that explains the rule. Designed once.
3. **Programmatic send.** App Intents, Siri, the agents hub and swaps all
   need to construct and execute a payment without the `SendView` state
   machine. Today that logic is spread across the send views and
   `WalletManager`. A typed request → quote → confirm → execute API, with the
   confirmation step owned by the app, is the piece under all four. It is on
   the money path, so under the floor.

## The ten features, sorted

"Reachable place" is the best state each can be in by the end of the season
given external dependencies as of 2026-10-07. Facts marked **verified** were
read in the repo this session; **reported** came from Christoph; the rest is
derived.

### Can land behind a flag this season

- **Good habits.** Backup-phrase reminders with age, balance-vs-security
  nudges, "you paid onchain fees N times this month where Lightning was
  available". All from local data; the only shared piece is the policy
  engine. Reachable: shipped behind a flag, graduating candidate.
- **Deeper OS integration.** App Intents for "send to contact" and "show
  balance", Shortcuts, Siri phrases; the widget target already has an
  `AppIntent.swift` (verified). Depends on programmatic send for anything
  that pays. New targets (watch app, intents extension if needed) are
  Xcode-UI changes Christoph makes by hand. Reachable: intents and widgets
  behind a flag; watch app scoped, not built.
- **Personal expression.** Custom backgrounds or imagery on top of the four
  themes; `Features/Theme_System.md` has the parked palette work. Needs no
  shared abstraction. Reachable: shipped behind a flag.
- **Sound.** A small soundscape for send, receive, confirm and error; the app
  has haptics in five views (verified) and no audio. Needs sound design
  assets, which is external work. Reachable: shipped behind a flag once
  assets exist; code is small.
- **Swaps, UX half.** Christoph's split: partner research is a doc, but the
  user flow (buy, sell, "pay in a stablecoin") can be explored behind a flag
  against a mock provider protocol, partner-agnostic, so the UX survives a
  partner change. Lands on programmatic send. Reachable: flow mocked
  end-to-end on signet; no real provider.
- **Multiple servers, custom-server entry.** Reported: a second Ark server
  is live, run by someone from Coinos. `NetworkConfig.custom(...)` exists at
  the data level with no UI on `main` (verified by grep). This sits under
  the floor (network config, pre-open), and switching servers means a
  different VTXO set, effectively a different wallet, so the scope doc must
  say what happens to existing funds. Reachable: a custom-server field in
  onboarding and a server-switch flow with full process, no flag. The
  "server picker V2" from Future ideas stays parked.

### Scope document and a go/no-go this season

- **Usernames and social.** Christoph: can go ahead without BOLT-12, less
  useful until then (a name resolves to a reusable Ark address and an
  LNURL-pay endpoint, not an offer). Needs the profiles abstraction, a
  directory service (server-side, outside this repo), abuse and squatting
  rules, and a decision on paid short names. Reachable: profiles design,
  directory API spec, a reserve-a-name flow against a mock directory behind
  a flag if the profiles model lands early. The real directory and billing
  are their own project.
- **Swaps, partner half.** Research of candidate providers, what they need
  (KYC, jurisdictions, API shape, settlement rails), what self-custody and
  privacy allow. Ends in a named shortlist or a "not yet".
- **Payment hub for agents.** `Docs/Features/Agent_Payments.md` and the
  phone + desktop code exist on `hackathon/agent-payments` (verified), not on
  `main`. Desktop is parked with an untrustworthy test suite. Reachable: the
  spec revived into a scope doc, the policy engine designed with the agents
  use case as a second consumer, and a decision on whether the phone-side
  service comes to `main` behind a flag.
- **Accounting.** Christoph is not sure there is meat here beyond the
  existing tags, contacts, metadata export and fee summary. Reachable: a
  half-day scope note that either names a concrete gap (Clams-compatible
  export, periodic statements, cost basis) or moves the item to Future
  ideas. Default if nobody argues for it: Future ideas.
- **Desktop and multi-device.** Already called a bigger, focused effort; the
  macOS suite blocks desktop work (Tier 1). Reachable this season: nothing
  built. A scope doc records what "smooth cross-device" means given what
  Second has said about native multi-client support.

### Expected yield

Realistically five or six flagged features and four scope docs with
decisions. Phase 1 will say so before anything is built, and may shrink
Phase 3 to a handful of features.

## Phases

The season is organised in phases, not dates. A phase ends when its exit
criterion is met, not when a train does; a phase may span several trains or
share one. Tier 0 and Tier 2 work continues in every train regardless of
phase, and the device day and the review day keep happening.

### Phase 1 — Scope

Nothing is built. The phase is about iterating scope documents until each
feature has a clear shape and a ruling.

- One scope doc per feature, under `Docs/Features/` with a `**Status:**`
  line, iterated with Christoph until it answers: what the feature is for
  this app, what the smallest useful version is, which shared abstraction it
  sits on, which parts cross the floor, what is external to the repo, and
  which flag and gate it would ship behind.
- One design doc per shared abstraction (profiles, policy engine,
  programmatic send) under `Docs/Architecture/`, written against the scope
  docs that depend on them so the consumers shape the design.
- Each scope doc ends in one of **build** (goes to Phase 3), **foundation
  first** (waits on a Phase 2 item), **scope only** (parked with a named
  external trigger) or **drop** (moves to Future ideas or is deleted).
- The flag registry above is filled with candidates from the docs.

Exit criterion: Christoph has ruled on every scope doc and every abstraction
design, and the sorted list in this document has been re-sorted from the
docs rather than from the guesses here.

### Phase 2 — Foundations

The under-the-floor work that Phase 1 decided is needed, with the full
process: the profiles model and migration, the programmatic send API, the
policy engine core, the custom-server entry if it was green-lit. Also the
scaffolding above the floor: the `ExperimentalFeatures` accessor, the
Experimental section layout, the experimental label in the app and in
TestFlight notes.

Exit criterion: every foundation a Phase 3 feature depends on has met its
tier's definition of done, including the device check.

### Phase 3 — Flagged features

The features Phase 1 marked **build**, each behind its flag, with the
relaxed process above the floor. Order of pull: features with no Phase 2
dependency first (habits, expression, sound), then those on a landed
foundation (intents, swaps UX against the mock provider, usernames reserve
flow). A feature may graduate early if it meets the full definition of done.

Exit criterion: every **build** feature is either behind a flag on
TestFlight or has been re-ruled as scope only or drop.

### Phase 4 — Consolidation

Tier 0, 1 and 2 only. Every flag ships or dies on its kill-or-ship entry.
The experimental label is removed or narrowed to the features that remain
flagged. The ledger is reviewed to compare the season's rework against the
trains before it, and this document's status moves to done with a one-line
summary per feature.

Exit criterion: the flag registry is empty or every remaining row has a
graduation item in the backlog, and Tier 0 is empty.

## Risks named up front

- **Flags that never ship or die.** Mitigated by the kill-or-ship column and
  Phase 4; the registry is reviewed in the Decide stage of every train.
- **The floor erodes** because a feature "only needs a small model tweak".
  Mitigated by the area-and-file boundary and by routing every schema change
  through a normal Tier 1 item first.
- **The compound loop stops.** Ledger and backlog keep running; the Phase 4
  ledger review will show whether the season's rework rate differed from the
  trains before it.
- **Docs instead of learning.** Every scope doc ends with a decision and, for
  blocked features, the named external trigger (bark release, partner
  signed, operator live) that unparks it.
- **Debt lands on one person.** Phase 4 is part of the season, not a
  follow-up. If it is skipped, the season was a drift.
- **Mainnet testers on experimental code.** Gate G2 for anything on a
  payment path; the label alone is not a control.

## Calls Christoph owns

- [ ] **DECIDE — run the season at all**, starting with Phase 1. It ends
  when Phase 4's exit criterion is met, not on a date.
- [ ] **DECIDE — the floor** stays as written above, non-negotiable for the
  season.
- [ ] **DECIDE — gate G1 or G2** (recommendation: G2 on payment paths, G1
  elsewhere).
- [ ] **DECIDE — Phase 4 is part of the season**, Tier 0/1/2 only, and the
  season is not done until it is.
- [ ] **DECIDE — the three abstraction designs are Phase 1 work**, iterated
  alongside the scope docs, before any dependent feature is built.
- [ ] **DECIDE — accounting**: scope note or straight to Future ideas.
- [ ] **DECIDE — agents hub**: does the phone-side service from the hackathon
  branch come to `main` behind a flag this season, or stays a scope doc.
- [ ] **DECIDE — usernames without BOLT-12**: build the reserve flow against
  a mock directory this season, or profiles design only.
