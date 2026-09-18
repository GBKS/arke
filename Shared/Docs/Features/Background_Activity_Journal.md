# Background Activity Journal

An on-device, app-side event journal for background execution, surfaced in
X-Ray — so a user (or a developer without a tethered device) can see
whether wakes, registrations, and background passes are actually
happening. The client-side counterpart to the relay's event logging.

Status: **PHASES 1+2 DONE** (2026-09-18) — journal + all seven
instrumentation points + compaction on scenePhase→active, and the X-Ray
surface (`BackgroundActivitySectionView_iOS` status header in DataView +
`BackgroundActivityView_iOS` event list with clear) are shipped; 248
mobile tests green, zero new warnings, catalog keys extracted (English
only — de/ja/zh-Hant passes pending like other recent strings). Screen
confirmed working on device 2026-09-18 (screenshots). **Phase 3 also DONE
2026-09-18**: on-demand "Check relay registration" row (typed
`fetchRegistrations` over GET /v1/registrations — the relay truncates
device tokens server-side to an 8-char suffix; response carries no auth
expiry, so the row shows presence + per-device updated_at) and the
journal section appended to `DebugLogExporter` output. Still open:
Phase 1 item 4 (simulated BGTask wake → journal rows readable at next
foreground launch — a device/simulator debugger run; the new screen is
the natural place to check) and an on-device look at the cross-check row.

**First field findings (2026-09-18, from device screenshots — both fixed
same day):** the journal immediately surfaced (1) every foreground launch
registering with the relay twice (`token_change` + `foreground`, seconds
apart — the launch flow and APNs token observer both fire, each minting a
new token the hash dedupe can't catch; fixed with a 1h freshness dedupe
in `mintAndRegisterWithRelay`, defeated by a changed device token and by
`forceRefresh()` so timer/BGTask/wake-push paths always re-register —
pinned by `RelayRegistrationFreshnessTests`), and (2) `coldLaunch`
elapsed times inflated by iOS prewarming (up to hours of dwell; fixed by
detecting `ActivePrewarm` — prewarmed launches journal
`detail: "prewarmed"` with no elapsed, and the OSLog wallet-ready line
now carries the flag too). `bgTaskScheduled` details are now local-time
ISO. Small open polish: the events list bottom row can sit under the
floating tab pill.

## Goal

Answer "is background execution working on *this* device?" from inside the
app: last relay registration and via which trigger, last wake per source,
next scheduled BGTask, and a reverse-chronological event history — without
Console.app, sysdiagnose, or relay-side access.

## Why OSLog can't power this (the core constraint)

The notice-level OSLog lines shipped in Background_Execution Phase 1 are
the right tool for tethered debugging, but the app cannot read them back
across sessions: iOS restricts `OSLogStore` to
`.currentProcessIdentifier` scope (`.system` needs a private
entitlement) — see the limitation already noted in
`DebugLogExporter.swift`. Background wakes are, almost by definition,
*other* sessions: short-lived cold launches that end before the user next
opens the app. An in-app view therefore requires the app to persist its
own journal. This is not duplicating OSLog; it covers a blind spot OSLog
structurally has. (Same reason `DebugLogExporter` exports say "no log
entries found for this session" for exactly the background scenarios
worth diagnosing — Phase 3 fixes that too.)

## Decisions (2026-09-17, from the approved proposal)

1. **On-device only, no upload.** The relay counts its side
   (`/insights/v1/summary`); the journal stays local. Privacy story stays
   trivially clean.
2. **Fixed enum of event kinds, no free-form payloads.** This is a
   wake-plumbing diagnostic, not an analytics framework. Adding a kind is
   a deliberate code change.
3. **No secrets in events, by construction.** Timestamp, kind, outcome,
   trigger, elapsed, small bounded detail — never amounts, addresses,
   mnemonics, mailbox ids, or tokens. This is what justifies decision 4.
4. **`FileProtectionType.none` on the journal file.** A pre-first-unlock
   wake (the keychain-unavailable branch) must be able to journal itself —
   that's one of the events we most want to see. Safe because of
   decision 3.
5. **Always-on, not a debug toggle.** Write cost is negligible; the value
   is that the data exists *before* you wondered.
6. **iOS-only.** Background wakes don't exist on desktop; the X-Ray
   section is `#if os(iOS)`.

## Design

### Journal service

`Shared/Services/BackgroundEventJournal.swift` (`#if os(iOS)`), an actor:

- **Storage**: append-only JSONL at
  `Application Support/Diagnostics/background-events.jsonl`, one compact
  JSON object per line. No SwiftData/SQLite: a cold background launch
  must append within the 30s window without touching the model container
  or wallet init, and bark's sqlite stays untouched.
- **API**: `func append(_ event: BackgroundEvent)` (fire-and-forget from
  call sites — never block or fail the pass over journaling) and
  `func recentEvents(limit: Int) -> [BackgroundEvent]` for the UI.
- **Ring buffer**: cap ~1,000 events / 30 days. Compaction (rewrite
  keeping the tail) runs at *foreground* launch only — the background
  wake path stays pure-append.
- **Event schema** (Codable struct, versioned):

  ```json
  {"v":1,"ts":1789735092.5,"kind":"wake_push","outcome":"refreshed","trigger":"wake_push","elapsedMs":420,"detail":null,"pid":8412}
  ```

  `pid` distinguishes cold launches from in-session events (a run of
  identical pids = one process session). `detail` is a short bounded
  string for things like an OSStatus code — never user data
  (decision 3).
- **Event kinds** (initial set, one enum):

  | Kind | Emitted from | Payload |
  |---|---|---|
  | `bgTaskWake` | `BackgroundTaskCoordinator.handleRefreshTask` | outcome, elapsedMs |
  | `wakePush` | `BackgroundTaskCoordinator.handleAuthWakePush` | outcome, elapsedMs |
  | `mailboxPush` | `AppDelegate_iOS.didReceiveRemoteNotification` (generic branch) | detail = push type |
  | `relayRegistration` | `WalletManager.mintAndRegisterWithRelay` | trigger, outcome |
  | `bgTaskScheduled` | `BackgroundTaskCoordinator.scheduleRefresh` | detail = requested date |
  | `foregroundTimerFired` | `RelayRegistrationService.scheduleAuthRefresh` timer body | — |
  | `coldLaunch` | app init / `LaunchTiming` | elapsedMs (launch → wallet ready) |

  The `bgTaskScheduled` + `bgTaskWake` pair is the point: requested-at vs
  actually-ran answers the BGTask-grant question per device, visibly.
  Phase 2/4 of Background_Execution (lightning claim, exit progression
  passes) add kinds when they route through the coordinator.

### X-Ray screen

- **Section row** in `ArkeMobile/Views/Data/DataView_iOS.swift`
  (`#if os(iOS)` not needed there; the file is mobile-only) →
  `BackgroundActivityView_iOS`.
- **Status header** (derived, answers "is it working?" at a glance):
  - Last successful relay registration: when + trigger.
  - Token expiry / next foreground refresh (needs a read-only
    `authExpiresAt`/`nextRefreshDate` exposure on
    `RelayRegistrationService` via `WalletManager`).
  - Next scheduled BGTask: live from
    `BGTaskScheduler.getPendingTaskRequests` (async), not the journal.
  - Last wake per source (BGTask / wake push / mailbox push), from the
    journal.
  - Notifications setting + APNs token present (the gates).
- **Event list** below: reverse-chronological journal rows — kind icon,
  outcome color, relative timestamp, expandable detail. Plus a "clear
  journal" action.
- Follow the previewable-models pattern: the header/list rows render from
  a plain model struct so previews need no live services.

### Relay cross-check (both ends in one screen)

A "Relay's view" row calling the existing
`RelayRegistrationService.listRegistrations(mailboxId:)` on demand
(button, not automatic — no background network from a diagnostics
screen), showing whether the relay currently holds a registration for
this mailbox and its expiry. App says "registered at T" (journal), relay
confirms (live) — the full loop, no server access needed.

### Debug log export hookup

`DebugLogExporter.generateLogFile` gains a journal section: append the
last N journal lines after the OSLog body (clearly delimited). This fills
the "no log entries found for this session" hole for user-submitted
diagnostics — background events survive into exports even though OSLog
entries from those sessions don't.

## Phases

### Phase 1 — Journal + instrumentation

1. `BackgroundEvent` model + `BackgroundEventJournal` actor (JSONL
   append, tail-read, compaction, file-protection `.none`,
   injected file URL for tests).
2. Instrument the seven call sites above. All already exist and already
   log at notice level — journaling is one added line each.
3. Unit tests (`Tests/Shared/BackgroundEventJournalTests.swift`):
   encode/decode round-trip, append/read, compaction keeps tail,
   corruption tolerance (a torn last line must not poison reads —
   skip undecodable lines).
4. Verify a cold-launch BGTask wake (`_simulateLaunchForTaskWithIdentifier`)
   produces journal rows readable at next foreground launch.

### Phase 2 — X-Ray screen

1. Expose read-only registration state (`authExpiresAt`,
   `nextRefreshDate`) through `WalletManager` for the header.
2. `BackgroundActivityView_iOS` (header + list + clear), section row in
   `DataView_iOS`. New strings take `defaultValue:` /
   L10n accessors per the localization convention; catalog keys extract
   on the next IDE build.
3. Previews via plain preview models (no MockBarkWallet expansion).

### Phase 3 — Cross-check + export

1. "Relay's view" on-demand row via `listRegistrations`.
2. `DebugLogExporter` journal section.

Phase 1 is independently useful (journal exists, verifiable via export
or the files app later); 2 and 3 are small and can land together.

## Acceptance

- Backgrounded + `simctl` wake push → open X-Ray → a `wakePush` row with
  outcome `refreshed`, and the header shows the fresh registration with
  trigger `wake_push`.
- Overnight on a real device: a 3am BGTask or wake push leaves rows
  readable at breakfast (this becomes the practical vehicle for the
  SWIFT_AUTH_WAKE_SPEC on-device verify, which stays tracked in
  Open_Follow_Ups.md).
- Pre-first-unlock wake journals its keychain-unavailable outcome
  (validates decision 4).
- A debug log export contains the journal section with background-session
  events absent from the OSLog body.
- Journal file never exceeds its cap; a corrupted line doesn't blank the
  screen.

## Open questions

- **Header copy/design**: X-Ray is "your wallet data, raw" — how polished
  should the status header read? (Assume raw-but-tidy until decided.)
- **Clear vs. auto-expiry only**: is a user-facing "clear journal" wanted,
  or is the 30-day ring enough? (Plan assumes both; trivial either way.)
- **Desktop**: skip entirely (decision 6) — revisit only if desktop ever
  gains scheduled background work.

## References

- `Shared/Services/BackgroundTaskCoordinator.swift`,
  `Shared/Services/RelayRegistrationService.swift`,
  `Shared/Data/WalletManager/WalletManager+Notifications.swift` — the
  instrumentation choke points (all wake sources already funnel here)
- `Shared/Services/DebugLogExporter.swift` — the OSLogStore scope
  limitation this works around, and the Phase 3 hookup
- `ArkeMobile/Views/Data/DataView_iOS.swift` — X-Ray root (mobile)
- [Background_Execution.md](Background_Execution.md) — the wake layers
  this observes; [SWIFT_AUTH_WAKE_SPEC.md](../SWIFT_AUTH_WAKE_SPEC.md) —
  the acceptance criteria this makes testable
- Relay-side counterpart: `/insights/v1/summary` event counters
  (arke-apns-relay-node)
