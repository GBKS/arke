# Siri AI and App Intents

**Status:** PROPOSED 2026-11-04, sequenced **behind desktop parity**
(`Desktop_Parity.md`, DECIDED below). Plan for exposing Arké's content and
actions to the system through App Intents, and from there to Siri AI
through Apple's Siri AI Developer Preview. Shares two prerequisites with
`MCP_Server.md` Track 2 (wallet bootstrap outside the view, payment
executor) and is the second client of both.

Related: `MCP_Server.md` (the executor and the no-hosted-connector ruling),
`../Development/Exploration_Season.md` ("Deeper OS integration" entry),
`../Architecture/Multi_Device_Design.md` (capability matrix: only the
primary spends), `Background_Execution.md` (the exit Live Activity).

## Decisions so far

| Date | Decision |
|---|---|
| 2026-11-04 | **Transaction history goes into the Spotlight index.** Try it and feel it out in practice; revisit after the first on-device run. Identifiers, addresses, preimages and anything else with no use outside the app stay `visibility: .internal`. (Christoph, in chat.) |
| 2026-11-04 | **Sequenced behind desktop parity**, alongside MCP Track 2. Not pulled forward. (Christoph, in chat.) |
| 2026-11-04 | **Mac first.** The Mac is the first test bed for Phases 1, 2 and 4, on a second APFS volume running the 27.3 beta, not the main install. The iPhone check is still owed before release. (Christoph, in chat.) |
| 2026-11-04 | **No App Intents spike before parity.** Desktop parity completes first; the plain iOS 26 foundation waits with the rest. (Christoph, in chat.) |

Nothing is open at the decision level. Detail-level proposals (entity
shapes, the skill text, the secondary-device behaviour in Phase 3) are
reviewed when the doc is unparked.

## What Apple shipped (verified 2026-11-04)

Read from the announcement (developer.apple.com/news, 2026-11-03) and the
App Intents documentation pages "Siri AI Developer Preview", "Bringing
custom actions and content to Siri", "Orchestrating complex actions with
app skills", `ToolIntent`, `GenerableEntity`, `IntentVisibility`,
`SiriEvaluations`. Symbol names are quoted as documented.

- **Tool intents.** `@AppIntent(.tool)` on a new or existing intent adopts
  `ToolIntent`. Siri calls it when the person names the app, when the app
  is in the foreground, when one of its Live Activities is active, or when
  one of its entities appears in a search result. Title, description and
  per-parameter title and description are what the model reads; Apple
  says to write them for someone who does not know the app, including
  units and formats.
- **Not every intent should be a tool.** Apple's own exclusions: widget
  configuration intents, single steps inside a shortcut, and "intents with
  side effects that a person needs to start explicitly, such as placing an
  order and paying for it". That sentence shapes the send design below.
- **Entities.** Every `@Property`, `@ComputedProperty` and
  `@DeferredProperty` takes a `description`, an `IntentAuthenticationPolicy`
  (`.alwaysAllowed`, `.requiresAuthentication`,
  `.requiresLocalDeviceAuthentication`) and a `visibility` (`.default` or
  `.internal`; internal properties are never surfaced to Siri or Shortcuts
  and must not carry a Spotlight indexing key). The entity can set a
  static `authenticationPolicy` for the whole type. Apple's sample is a
  bank account: balance behind local-device authentication, routing
  number internal. Finance is explicitly in scope; there is no finance
  schema domain (primary domains are audio, calendar, camera, clock, mail,
  maps, messages, notes, phone, photos, reminders, system search, video),
  so everything here is a custom tool.
- **Generable entities.** `@AppEntity(.generable)` on a
  `TransientAppEntity` adopts `GenerableEntity`: Siri fills the struct
  from the request without running a query. Properties must be plain
  values, `AppEnum`s, other generable entities, or arrays of those; the
  compiler rejects anything else.
- **Discovery.** Siri finds entities through the Spotlight index
  (`IndexedEntity`, iOS 18 baseline, with `indexingKey` on properties) or,
  failing that, an `EnumerableEntityQuery`. Onscreen context ("this
  payment") uses the existing user-activity annotation API. Cross-app
  handoff ("send it to Bob in Messages") needs the entity to be
  `Transferable`.
- **App skills.** A `Skills.skillsbundle` resource (one per app target,
  File > New > File from Template > Skills Bundle) containing
  `Skills/<name>/SKILL.md` files in the Agent Skills format: `name` and
  `description` frontmatter plus a Markdown body of at most 10,000
  characters. Siri reads the body only after the description matched.
  Apple: skills "can't enforce deterministic behavior" and Siri "doesn't
  sequentially perform the tool intents that your skill lists". Refer to
  tools by what they do, not by type name.
- **Testing.** A Siri Integration Advisor in Xcode; the `SiriEvaluations`
  framework (scripted `SiriScenario` / `UserTurn` with `Calls`, `Finds`,
  `OnScreen`, `SiriResponse` expectations, run from Swift Testing or
  XCTest); the iOS 27.0 `AppIntentsTesting` framework for intents and
  queries out of process. Skills and Siri itself need a real device or a
  Mac, not the simulator.
- **No new entitlement**, no separate program.

Constraints:

| Constraint | Detail |
|---|---|
| OS and SDK | iOS, iPadOS, macOS, visionOS **27.3 beta**. All new symbols carry `27.3 beta` availability. This Mac runs Xcode 27.1 with SDK 27.1 (verified `xcodebuild -version`), so the preview parts need a beta Xcode. The deployment target is 26.2, so tool types are gated `@available(iOS 27.3, macOS 27.3, *)`. |
| Distribution | Development builds and **internal** TestFlight only. External testers and App Store builds do not get the preview behaviour. App Store submission opens in spring; the API may change during the preview. |
| Language | Siri language must be English, French, Japanese, Korean, Portuguese or Spanish. German is not supported, so the de catalog does not reach Siri. |
| Region | "Siri AI is currently unavailable in the EU in iOS, iPadOS, and watchOS." macOS is not named in that sentence. |
| Age and quota | Not available under 13; daily usage limits apply. |
| Model exposure | Default-visibility properties are "listed to people and to the model". The documentation does not say which request text or entity values leave the device for Private Cloud Compute. **Assumed open**, not verified; see §Privacy. |

## What exists today (verified 2026-11-04)

- No App Intents in the app targets. The widget target has only the Xcode
  template code: `ConfigurationAppIntent` ("Favorite Emoji"), the timer
  control (`Arke_WidgetsControl`, `StartTimerIntent`, `TimerConfiguration`).
  None of these may become tools; they are cleanup.
- No `CoreSpotlight`, no `NSUserActivity` and no `userActivity(_:)`
  anywhere in `Shared`, `ArkeMobile`, `ArkeDesktop` or `ArkeWidgets`
  (grep). Spotlight indexing and onscreen context both start from zero.
- The exit Live Activity (`ExitProgressLiveActivity`,
  `ExitProgressActivityAttributes`) exists and is updated locally. While it
  is active, Siri AI accepts requests about Arké without the app name.
- `WalletManager` is `@MainActor @Observable`, view-free, with typed
  `async throws` operations for send, receive, balance, history, contacts,
  tags, refresh and exits (`MCP_Server.md`, "What exists today"). The three
  things that keep it from being callable without the UI are the same
  three MCP lists: the open sequence lives in both `MainView.task`s, send
  routing lives in `SendViewModel`, BIP-353 and LNURL resolution are called
  from the send views.
- Data that would back entities: `PersistentTransaction`,
  `PersistentContact`, `PersistentContactAddress`, `PersistentTag`,
  `TransactionTagAssignment`, `TransactionContactAssignment`,
  `ArkBalanceModel`, `OnchainBalanceModel`. The cached-relationship rule
  from `CLAUDE.md` applies to every entity query: read through the `live*`
  accessors or a `TransactionMetadataSnapshot`, never off a cached to-many
  array.
- Capability matrix: balance, history, contacts, tags and addresses on
  every device; send, rounds and exits on the primary only. Lightning
  invoice creation needs the open bark handle (derived: it is a bark call),
  so a read-only secondary without the seed can offer addresses but not
  invoices.

## Scope, by risk

Each phase is a separate backlog item when it is scheduled. Phases 1 and 2
need no preview API and are useful on iOS 26 (Shortcuts, Spotlight, the
Action button, Control Center). The `.tool` trait and the skill are added
on top behind the availability gate.

### Phase 1 — Read entities and intents (any device)

- `BalanceEntity`: Ark and onchain balance, pending amounts. Amounts
  `.requiresLocalDeviceAuthentication`. One "Show my balance" intent.
- `TransactionEntity` over `PersistentTransaction` plus its snapshot:
  direction, amount, date, contact names, tag names, note, rail, state.
  Indexed in Spotlight (DECIDED above). Internal: txid, VTXO ids,
  addresses, invoices, preimages, exit data.
- `ContactEntity`, `TagEntity`: name, note, counts. Addresses internal.
- Onscreen context on the transaction detail screen so "tag this payment
  as lunch" and "who did I pay here" resolve to the visible row.
- "Tag a payment" and "assign a contact" intents: write metadata, never
  money. Both are `UndoableIntent` candidates.
- Entity queries build a snapshot per entity in one main-actor pass.
  Spotlight indexing hooks into the places that already write
  `PersistentTransaction` and the CloudKit import observer, so a secondary
  device indexes what it mirrors.

### Phase 2 — Receive (no funds leave)

- `InvoiceEntity` (Lightning invoice, amount, description, expiry) and
  `AddressEntity` (Ark address, onchain address, Lightning address),
  `Transferable` as plain text plus a QR image, so "create an invoice for
  20,000 sats and send it to Bob in Messages" works end to end. This is
  Apple's headline cross-app pattern.
- "Create invoice" intent, generable parameters amount and note. Needs
  the bark handle, so it needs §Prerequisites item 1 before it can run
  from a cold launch.

### Phase 3 — Payment draft (money path, primary only)

Not "Siri pays". Siri prepares, Arké confirms:

- `PaymentDraft`, a generable transient entity: recipient (contact name,
  or raw destination string: invoice, Lightning address, BIP-353 name, Ark
  or onchain address, BOLT-12 offer), amount with unit, note, tags.
- "Prepare payment" tool intent: resolves the destination through the
  executor (`MCP_Server.md` §2.2, `request → quote → confirm → execute`),
  returns the quote as a snippet, and opens the app on the existing
  confirmation screen with Face ID or Touch ID. The confirmation token is
  minted only by the app's approval UI, as the executor requires. No
  intent ever calls execute.
- On a secondary device the intent either forwards into the Track 2
  approval path or refuses with a clear dialog; which one follows the
  transport decision in `MCP_Server.md`.
- Tier 1 review depth, adversarial pass, two-device check before "done".

### Phase 4 — The skill

One `SKILL.md`, English, under 10,000 characters: amounts are sats unless
the person says bitcoin or a fiat currency; how to tell an invoice, a
Lightning address, a BIP-353 name, an Ark address and an onchain address
apart and which tool takes which; never choose a rail yourself; every
payment ends on the confirmation screen; tags are categories, contacts
are people; exits and rounds are not payments. The same text is the seed
of the MCP server's prompts in Track 3. Skill descriptions are not
deterministic, so nothing in the skill is a guard; guards stay in code.

### Phase 5 — Live Activity and relevance

With the exit Live Activity active, "how is my exit going" without the app
name; an `ExitEntity` over `PersistentExitCache` and the exit progress
state. Low value, last.

## Privacy and data exposure

- The index is on device, but the model reads default-visibility
  properties. Until Apple documents what reaches Private Cloud Compute,
  treat every default-visibility property as potentially leaving the
  device and keep the internal list generous. Revisit after the first run
  and after reading the preview's privacy notes when they appear.
- Every entity and every intent result that carries an amount or a
  counterparty is behind `.requiresLocalDeviceAuthentication`. Apple notes
  the per-property policy applies only to Siri's responses, so intents
  that return sensitive values set the policy at the intent level too.
- Nothing seed-touching is reachable from an intent. No intent reads the
  mnemonic, the keychain seed item or the iCloud KVS wallet hash. Deletion,
  registration and exits have no intents.
- Logger output stays unlocalized and never includes entity values.

## Platform and testing (DECIDED 2026-11-04: Mac first)

Christoph asked whether the Mac is the better first test bed, since the EU
restriction names iOS, iPadOS and watchOS but not macOS. The reasoning
below led to the ruling in the table above.

- **Verified:** the announcement's EU sentence does not name macOS; the
  developer preview is listed for macOS 27.3; `SiriEvaluations` and the
  preview symbols carry macOS 27.3 availability; this Mac is an M1 Pro on
  macOS 27.2 (Apple Intelligence capable).
- **Derived:** intents and entities are Shared code, so they compile into
  ArkeDesktop without project changes and the Mac exercises the same code
  iOS will run. Phases 1 and 2 work on a secondary Mac per the capability
  matrix. Phase 3 needs a Mac primary, which is exactly what desktop parity
  delivers, so "behind parity" and "test on the Mac" line up.
- **Costs:** the preview needs macOS 27.3 beta plus a beta Xcode on the
  only development machine, or a second APFS volume with the beta. The
  macOS unit suite is untrustworthy until the parity Tier 1 item lands, so
  entity and executor tests run on the iOS simulator as usual and only the
  Siri conversation itself runs on the Mac. Siri's language on the Mac
  must be set to English. Onscreen context needs annotations in the
  desktop views as well, so Phase 1's "this payment" cases need the
  desktop transaction detail view current (parity Batch 3 or later).
- **Ruling:** the Mac is the first test bed for Phases 1, 2 and 4, on a
  second APFS volume rather than the main install. The iPhone remains the
  product; an iPhone check with Siri in English, outside the EU or after
  the restriction lifts, is owed before anything is recorded as
  device-checked for release.

## Prerequisites and ordering

1. `WalletBootstrapper` out of both `MainView.task`s (`MCP_Server.md`
   §2.1). An intent arriving while the app is cold runs in the app process
   with no wallet open; without the bootstrap every intent beyond Phase 1's
   cached reads fails. Startup-shaped, `Launch_Sequence_Contract.md`
   rules apply, full review. Shared with MCP Track 2, built once.
2. Payment executor (`MCP_Server.md` §2.2). Phase 3 only.
3. Desktop parity complete (DECIDED above), then MCP Track 2 and this plan
   are ordered against each other when both are unparked.
4. A 27.3 beta toolchain and a device or volume on 27.3 for the `.tool`
   trait, the skill and `SiriEvaluations`. Phases 1 and 2 without the
   trait need none of this.

A Phase 1 spike without the preview trait (plain iOS 26 App Intents,
Spotlight, Shortcuts) was considered because it would answer the
cold-launch question for prerequisite 1. DECIDED 2026-11-04: it waits for
parity with the rest.

## Verification per phase

- Unit (iOS simulator): entity snapshot construction against the
  cached-relationship rule; intent parameter resolution; executor decision
  tests for Phase 3; `AppIntentsTesting` for queries once a 27.x test host
  is available.
- Mac or device: the Shortcuts app lists every intent with correct titles
  and descriptions; Spotlight finds a transaction by contact name and by
  tag; Siri Integration Advisor has no open suggestions; a
  `SiriEvaluations` scenario set per phase, run more than once because
  responses vary.
- Device day: the Phase 3 payment never executes without the confirmation
  screen; a secondary device refuses or forwards; an intent on a cold
  launch opens the wallet and completes.

## When this doc is unparked

Re-read the preview documentation first; Apple says the API may change.
Re-verify every symbol in §What Apple shipped against the installed SDK,
re-check the EU and language constraints, and check whether Apple has
published what the model receives.
