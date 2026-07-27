# Background Execution

Plan for running time-sensitive wallet work while the app is backgrounded or
terminated: accepting incoming Lightning payments, starting delegated
refreshes, and progressing unilateral exits.

Status: **PLANNING** — big-picture design, no implementation yet.
Companion doc: [RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md](../RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md)
(the relay auth token refresh is Phase 1 of this plan and has its own
detailed work items there).

## Decisions (2026-07-23)

1. **Keychain**: migrate the mnemonic to
   `kSecAttrAccessibleAfterFirstUnlock` so background wakes on a locked
   device can open the wallet. (Verify iCloud Keychain sync still works —
   that was the reason for the current class.)
2. **The relay never acts on its own initiative.** It forwards mailbox
   messages and — as a later fallback — fires wake-up pushes the app
   explicitly requested ("wake me at time T"). No chain watching, no
   knowledge of user transactions, no relay-side scheduling decisions.
3. **Layering**: scheduled `BGTask`s are the primary self-wake mechanism;
   the app-requested relay wake-up push is the fallback if field data
   shows iOS doesn't grant enough BGTask time; visible "open the app"
   notifications are the floor.
4. **Accepted limit**: a user who force-quits the app or ignores
   notifications gets no background progress. Visible notifications are
   the last line; we don't engineer past that.

## Goal

Today, all wallet maintenance stops the moment iOS suspends the app. A user
who backgrounds or closes Arké can miss incoming Lightning payments, skip
free refresh windows, and stall a unilateral exit for days. We want the
right work to happen at the right time without requiring the app to be
open — and a graceful, user-visible fallback when iOS won't give us
background time.

## What exists today

### Foreground-only maintenance loops

All four services share the same shape: a repeating `Timer` plus a
single-pass `checkAndX()` method. The single-pass methods are exactly what
any background primitive wants to call — the refactor is "detach the pass
from the timer," not "rewrite the logic."

| Service | Interval | Single pass does |
|---|---|---|
| `LightningClaimService` | 30s | `wallet.sync()`, then claim pending Lightning receives |
| `ExitProgressionService` | 5min | `progressExits`, auto-claim claimable exits, `syncExits`, update Live Activities |
| `VTXORefreshService` | 1h | free-window refreshes — already uses `refreshVtxosDelegated` |
| `RoundProgressionService` | 60s | round state polling |
| `RelayRegistrationService` | ~23h `Task.sleep` | re-mint the 24h mailbox auth token via `onNeedsRefresh` |

### An existing background wake channel

- `Info.plist` declares `UIBackgroundModes: [remote-notification]`.
- The relay (`relay.arke.cash`) subscribes to the Ark mailbox for
  registered wallets. The mailbox protocol
  (`arke-apns-relay-node/protos/mailbox_server.proto`) carries five
  message types, and the relay (`src/apns-sender.js`) forwards each as a
  distinctly-typed APNs push — but in **two different modes**:
  - **Silent background pushes** (`pushType: background`, priority 5,
    `contentAvailable: 1`, no alert):
    `mailbox_round_participation_completed`, `mailbox_recovery_vtxo_ids`.
  - **Visible alert pushes** (sound + banner, **no `content-available`**):
    `mailbox_arkoor` ("Received ₿X"),
    `mailbox_incoming_lightning_payment` ("Receiving ₿X — Open Arké to
    accept it."), `mailbox_lightning_send_finished`.
- This split matters: iOS only calls
  `didReceiveRemoteNotification(fetchCompletionHandler:)` in the
  background for `content-available` pushes. A pure alert push runs **no
  app code** until the user taps it (or the app is foreground, via
  `willPresent`). So today's *actual* background wake channel is only the
  two silent types. For incoming payments (arkoor and Lightning), the
  user gets a banner but the wallet does nothing until tap.
- When app code *does* see a mailbox push (foreground, tap, or the silent
  types), `AppDelegate_iOS` matches `type.contains("mailbox")` and posts
  `.mailboxUpdateReceived`, which
  `WalletManager+Notifications.setupMailboxNotificationObserver()` routes
  to `WalletManager.refresh()`.
- Everything above depends on relay registration, which is gated on the
  app's own `notifications_enabled` setting
  (`WalletManager+Notifications.registerForPushNotifications()` returns
  early when it's off). Users who disable notifications have **no push
  layer at all** — BGTasks are their only automated background path.

So for incoming Lightning payments the message plumbing (mailbox → relay
→ APNs → handler) already exists end to end, but it arrives as an alert
push, not a wake — turning it into one is a **small relay payload change**
(APNs allows `alert` + `content-available: 1` on the same push). The whole
channel also lives only as long as the relay holds a non-expired mailbox
authorization (24h TTL), which is the gap the relay auth plan closes. And
even a delivered wake currently only refreshes; it doesn't claim or run
the other maintenance passes.

### Human-as-scheduler fallbacks

- Exit check-in local notifications (`ExitProgressionNotifications`):
  "open the app to progress your exit." Tapping posts
  `.exitCheckInReceived`.
- VTXO refresh reminder notification (`VTXORefreshService`).
- Exit progress Live Activity (`ArkeWidgets`), updated **locally only** —
  it goes stale as soon as the app is suspended.

### What does NOT exist

- No `BGTaskScheduler` usage anywhere. No `fetch`/`processing` background
  modes declared. No `BGTaskSchedulerPermittedIdentifiers`.
- No client-side differentiation of mailbox push types — every
  `mailbox_*` push funnels into the same `refresh()`, which does not
  claim Lightning receives or progress exits.
- No relay-side awareness of exit state (the mailbox doesn't carry exit
  checkpoints).
- No ActivityKit push token plumbing.

## Hard constraints (design around these first)

### 1. Keychain accessibility gates everything

The mnemonic was stored with `kSecAttrAccessibleWhenUnlocked`
(`SecurityService.swift`, chosen to allow iCloud Keychain sync). Most
background wakes fire while the device is **locked** — and in that state
the wallet cannot be opened at all.

**Decided (see Decisions above): migrate to
`kSecAttrAccessibleAfterFirstUnlock`** in Phase 1. This is standard for
wallets doing background work; it slightly weakens at-rest protection
(readable after first unlock post-boot, even while re-locked).

**Status 2026-07-27: implemented and verified on device.** `saveMnemonic`
now writes `AfterFirstUnlock`, and
`SecurityService.migrateMnemonicAccessibilityIfNeeded()` migrates existing
items in place (atomic `SecItemUpdate` carrying the data, verified
delete+re-add fallback, read-back verification), called from the `.found`
branch of wallet state detection — the one spot where the keychain is
provably readable. Unit-tested in
`Tests/Shared/KeychainAccessibilityMigrationTests.swift`. iCloud Keychain
sync verified with a two-device clean-room test (2026-07-27): fresh wallet
on the old build synced to the second device; after migrating the primary,
the second device kept the seed, and on update it logged "item already
kSecAttrAccessibleAfterFirstUnlock" — i.e. the accessibility change itself
propagated via iCloud Keychain sync.

Even after the migration, the background entry point must treat "keychain
unavailable" as a normal branch — it still happens between reboot and
first unlock, and the startup wallet detection hardening
(`Shared/Docs/Initialization/`) already deals with the same failure mode
at cold launch/prewarming. Keep the two consistent; never treat it as
"no wallet".

### 2. Nothing iOS gives us is guaranteed

- `BGAppRefreshTask`: ~30s, opportunistic; cadence decided by iOS from
  usage patterns. Rarely-opened apps get very little.
- `BGProcessingTask`: minutes of runtime, but typically overnight/charging.
- Silent push (`content-available: 1`): budget-limited (a few per hour);
  **delivery to the app stops entirely if the user force-quits** via the
  app switcher.
- `BGContinuedProcessingTask` (new API — see DocumentationSearch): lets
  user-initiated work continue after backgrounding with system-visible
  progress; cancelled if the user swipes the app away.
- Visible alert pushes are always delivered/displayed, but only run app
  code when tapped.

Therefore the architecture is **layered** (Decision 3):

1. Event-driven mailbox pushes (already ship) for things the server
   genuinely knows first — incoming payments.
2. Scheduled `BGTask`s as the primary self-wake mechanism for
   deadline-driven work (exits, refreshes, auth).
3. App-requested relay wake-up pushes ("wake me at time T") as the
   fallback, if Phase 1 field data shows BGTasks don't fire often enough.
4. Local notifications as the floor: guaranteed delivery (even after
   force-quit), scheduled at deadline + grace so they only surface when
   the layers above failed, and cancelled/pushed forward by every
   successful pass (see "Local notifications" under Architecture). Past
   an ignored notification we accept there is no further recourse
   (Decision 4).

Note: layers 1 and 3 (and the visible-push parts of layer 4's remote
cousins) only exist for users with the app's `notifications_enabled`
setting on — it gates relay registration entirely. For opted-out users,
layer 2 (BGTasks) is the whole system.

### 3. The 30s window includes cold launch

A `BGAppRefreshTask` or silent-push wake of a terminated app pays for
process launch + `WalletManager` init + bark wallet open + (usually) an
Esplora-backed `sync()` before doing any useful work. We have no timing
data for this. Measure it early (Phase 1 logging) — it decides whether
app-refresh tasks are viable at all or whether everything heavy needs
`BGProcessingTask`.

## Use cases → primitives

### Incoming Lightning payments (hardest: latency is seconds)

Claiming requires the wallet keys — no server can do it for us. Two
distinct scenarios:

1. **User is showing an invoice and backgrounds the app.** The payer is
   watching a spinner; the claim loop must survive a few more seconds.
   Options: `beginBackgroundTask(withName:expirationHandler:)` for the
   ~30s grace period, or `BGContinuedProcessingTask` for a longer,
   user-visible "waiting for payment" continuation. This is client-only
   work and can ship independently of any relay change.
2. **Payment arrives out of the blue** (reusable offers). The signal
   plumbing **already exists**: the Ark mailbox carries an
   `IncomingLightningPaymentMessage` and the relay forwards it as a
   `mailbox_incoming_lightning_payment` push — but as a **visible alert
   without `content-available`** ("Receiving ₿X — Open Arké to accept
   it."), so today it wakes the *user*, not the app. Two gaps, both
   small:
   - Relay: add `content-available: 1` to that push (alert + wake on the
     same notification is legal APNs).
   - Client: route the wake into a pass that runs
     `LightningClaimService.checkAndClaimReceives()` instead of just
     `refresh()` (Phase 2). After a successful background claim, the
     already-delivered "open to accept" banner is stale — remove it via
     `removeDeliveredNotifications` and post a corrected "Received ₿X".
   The existing visible banner doubles as the fallback for when the wake
   is throttled or the device is locked — it already ships. Still to
   determine: how long the Ark server holds the HTLC — that defines the
   real deadline — and whether the mailbox message fires at HTLC arrival
   (pre-claim) with enough time left to act.

### Delegated refreshes (easiest win)

The delegation model (`refreshVtxosDelegated`, `maintenanceDelegated` in
the bark bindings) means the app needs only seconds of runtime: sign the
delegation, hand the round to the server, done — the server completes it
offline. `getNextRequiredRefreshBlockheight()` gives a concrete deadline
to derive `earliestBeginDate` from. The foreground logic already exists in
`VTXORefreshService`; the background version is "call the same pass from a
`BGAppRefreshTask`."

### Unilateral exits (days-long, cadence over latency)

Progression needs periodic CPFP bumps and a final claim — multiple network
calls and broadcasts, more than a 30s window wants. Best fit:
`BGProcessingTask` (require network; consider not requiring power).

Exits are the most cadence-tolerant use case: once started (foreground,
user-initiated), a late bump or claim only costs latency, never funds. So
best-effort scheduling is acceptable — and it should be **adaptive, not
fixed-interval**: each run reads the exit's block heights, which bark
already exposes (`allExitsClaimableAtHeight()`,
`ExitProgress.waitForUnlock(claimableHeight:)`,
`getLatestBlockHeight()`), and requests the next wake at the next
interesting moment — capped at ~1.5h during Processing (bump cadence),
one wake near the claimable height during AwaitingDelta rather than
pointless hourly ones. Asking only for wakes we use also improves how
often iOS's scheduler grants them. (Note: today's check-in reminders are
*not* height-derived — `ExitProgressionNotifications` schedules a fixed
90-minute × 5 sequence from "now"; the adaptive model replaces that.)

- If BGTasks prove too unreliable in the field, the same computed
  deadline feeds the app-requested relay wake-up (see relay section) —
  the app decides *when*, the relay just delivers the nudge.
- Live Activities update **locally on each wake** (background runs can
  update them). Relay-pushed Live Activity content is ruled out by
  Decision 2 — it would require the relay to know exit state. Staleness
  between wakes is accepted; multi-day exits outlive the ~8h activity
  lifetime anyway.
- Existing check-in notifications stay as the backstop, and are the
  accepted limit for force-quit users.

### Relay auth refresh (the enabler — do first)

If the mailbox token lapses, the push channel dies, and push is the wake
source everything else leans on. The full design is in
[RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md](../RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md).
One amendment from this plan: build its scheduling/registration plumbing
as the shared coordinator below, not as a relay-auth-only one-off.

## Architecture

### One coordinator, one maintenance pass

A single `BackgroundTaskCoordinator` (iOS-only, likely
`ArkeMobile/` or `Shared/Services/` with `#if os(iOS)`), owning:

- Two BGTask identifiers, registered in `AppDelegate_iOS` at launch:
  - `cash.arke.refresh` (`BGAppRefreshTask`) — short passes: relay auth,
    delegated refresh kickoff, lightning claim check.
  - `cash.arke.maintenance` (`BGProcessingTask`) — heavy passes: exit
    progression/claim, full sync.
- The silent-push entry point (called from
  `didReceiveRemoteNotification`), wrapped in `beginBackgroundTask`
  protection.

All wake sources funnel into one shared **maintenance pass**:

1. Bail out cleanly if the keychain/wallet is unavailable (locked device,
   no wallet) — optionally escalating to a visible notification if
   something urgent is pending.
2. Refresh relay auth if due.
3. `wallet.sync()`.
4. Claim pending Lightning receives.
5. Progress/claim exits (skip in the app-refresh variant if time is short;
   the `expirationHandler` must cancel cleanly mid-step).
6. Start delegated refreshes if free/needed.
7. Post escalation local notifications for anything the pass discovered
   but could not fix — fee-blocked exit, failed claim, keychain locked
   with urgent work pending (see "Local notifications" below).
8. Compute the **soonest upcoming deadline** — auth expiry, next required
   refresh blockheight, next exit checkpoint — and reschedule **all wake
   layers** against it: submit the next BGTask request(s) at T, and
   cancel + reschedule the local reminder notifications to T + grace.
   Always reschedule, success or failure. (Once the relay wake-up API
   exists, POST the same deadline there too; whichever wake fires first
   runs the pass and reschedules everything.)

Foreground timers keep calling the same per-service passes they call
today; over time they can collapse into calls to the shared pass. Services
stop owning "when," and keep owning "what."

### The relay stays dumb: mailbox forwarder + alarm clock

The relay is the only component we control that never sleeps, but per
Decision 2 it never acts on its own initiative. It already forwards all
five mailbox message types (including incoming Lightning payments). Its
single planned addition is an **app-requested wake-up API** — a dumb
alarm clock:

- Client: `POST /v1/wakeups { device_token, fire_at }` (replace
  semantics — one pending wake per device — plus a cancel). Sent from the
  maintenance pass alongside the BGTask request, for the same deadline.
- Relay: persist the timestamp, send a silent push (`contentAvailable:
  1`) at `fire_at`, delete. It learns nothing but "this device wants a
  nudge at time T"; wake times can be rounded/jittered if even that
  timing pattern is a concern.
- This subsumes the relay auth plan's open question about a relay-decided
  "auth about to expire" push: the app requests a wake at
  expiry-minus-buffer instead, keeping the relay's behavior uniform.

Silent pushes arrive when the server sends them — a far stronger timing
property than BGTask's advisory `earliestBeginDate` — but they still have
an iOS budget, can be deferred somewhat, and never launch a force-quit
app. Hence fallback, not foundation (Decision 3): build it only if
Phase 1 field data shows BGTasks alone don't fire often enough.

### Local notifications: the guaranteed layer

Local notifications are the only layer iOS never withholds: they fire on
time with no APNs budget, no scheduler discretion, no network — and they
survive force-quit, which nothing else does. The trade-off is absolute:
they run zero code. They display, and on tap they launch the app. Their
executor is the human. Existing users of this layer:
`ExitProgressionNotifications` (exit check-in reminders, tap →
`.exitCheckInReceived`) and `VTXORefreshService` (refresh reminder).

Three roles in this architecture:

1. **Deadline backstop, offset behind automation.** The reminders are
   driven by the same deadline computation as the BGTask/relay wakes,
   but scheduled at **T + grace** rather than T — they exist to fire
   only when the automated layers at T presumably failed. (Today the two
   users schedule independently and differently: exits as a fixed
   90-minute × 5 sequence from "now", VTXO refresh at its computed
   deadline. The coordinator unifies both onto deadline + grace. Both
   already gate on `notifications_enabled` and UN authorization — keep
   that.)
2. **Self-cancelling nag.** Every successful maintenance pass — from any
   wake source — cancels pending reminders and reschedules them past the
   next deadline plus grace (step 8). Consequence: **if background
   execution works, the user never sees a reminder.** A check-in
   notification appearing means "automation failed for this deadline";
   silence is the success signal. `ExitProgressionService.start()`
   already does a version of this (`cancelAllCheckInReminders()` on
   foreground start).
3. **The voice of a silent wake.** A background pass can *post* local
   notifications (step 7), which is how it talks to the user when it
   woke but couldn't finish: fee-blocked exit (surface immediately
   instead of at the next app open — the exit-blocked-state work already
   computes this), claim pending but keychain locked pre-first-unlock,
   broadcast failure.

Don't conflate the two visible-banner kinds: the relay's visible
*remote* pushes ("payment received") announce external events; *local*
notifications are deadline reminders and failure escalations from
inside. Same UI surface, different jobs — and only the local ones are
part of the wake-layer scheduling above.

### Concurrency and safety notes

- A background wake can race a foreground launch or another wake. The
  wallet-open path must be reentrant-safe; `TaskDeduplicationManager` and
  the maintenance pass should guard against overlapping passes (the
  services' existing `isClaiming`/`isChecking` flags do this per-service).
- bark's sqlite is same-process here — no app-group/extension access.
  **Do not** attempt wallet work from a Notification Service Extension;
  that would mean cross-process sqlite access.
- Background broadcasts (exit claims) spend real money on mainnet. The
  pass reuses the exact same code paths as foreground (fee caps,
  `exitFeeRateOverride`), so no new policy — but log every background
  broadcast loudly.

## Phases

### Phase 1 — Relay auth background refresh + coordinator skeleton

Implement RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md, but house the BGTask
registration/scheduling in the `BackgroundTaskCoordinator` so later phases
plug in. Add OSLog throughout (several services still `print`), including
timing of cold launch → wallet ready → pass complete, and a per-wake-source
log line — this is the field data that tells us how much background time
iOS actually grants and whether the 30s budget is workable.

*OSLog groundwork done 2026-07-27:* `RelayRegistrationService`,
`LightningClaimService`, `ExitProgressionService` (+LiveActivity
extension), and `RoundProgressionService` converted from `print` to
`Logger` (categories match the old bracket prefixes; per-tick chatter at
debug, actions at info, money-moving/summary lines at notice with
`privacy: .public` so they persist for TestFlight field data).
`LaunchTiming` (Shared/Services/) anchors at both apps' `init()` and logs
cold launch → wallet ready (notice) from the end of
`WalletManager.initialize()`. Still to come with the coordinator
(steps 3–4): pass-complete timing and the per-BGTask-wake-source lines;
remote-push wake logging already existed in `AppDelegate_iOS`.

*Coordinator skeleton done 2026-07-27:*
`Shared/Services/BackgroundTaskCoordinator.swift` (`#if os(iOS)`), with
both identifiers + `fetch`/`processing` modes declared in
`ArkeMobile/Info.plist`. The `cash.arke.refresh` handler is registered
from `application(_:didFinishLaunchingWithOptions:)` and currently logs
its wake (notice), reschedules first, honors `expirationHandler`, and
completes — no wallet work yet. A safety-net `scheduleRefresh()` fires
on scenePhase → background. Verified on simulator (registration at
launch, no crash, submit hits the expected `unavailable` branch) and
**on device** (2026-07-27): `_simulateLaunchForTaskWithIdentifier` fires
the handler — wake logged, rescheduled, completed. Remaining for step 4:
wire the relay auth refresh into the handler and drive
`earliestBeginDate` from the real token expiry.

Also in Phase 1: **migrate the mnemonic keychain item to
`AfterFirstUnlock`** (decided) — in-place re-add with the new
accessibility attribute, plus verification that iCloud Keychain sync
still works. Without this, every locked-device wake in later phases is a
no-op. *Done and device-verified 2026-07-27 (see the keychain constraint
section above) — iCloud Keychain sync confirmed working with the new
class, including propagation of the attribute change itself.*

### Phase 2 — Widen the mailbox push wake into a full pass

Two halves, both small:

- **Relay**: add `content-available: 1` to the alert push types
  (`mailbox_arkoor`, `mailbox_incoming_lightning_payment`) so they wake
  the app instead of only showing a banner. Today only
  `round_participation_completed` and `recovery_vtxo_ids` are silent
  wakes.
- **Client**: route mailbox wakes into the maintenance pass (sync +
  Lightning claim at minimum, replacing the bare `refresh()`) with
  `beginBackgroundTask` protection. On successful background claim,
  replace the stale "open to accept" banner
  (`removeDeliveredNotifications` + corrected local notification).

Verify on-device that the wake actually fires and the claim completes
within the window. **This phase, not Phase 5, is what makes
out-of-the-blue Lightning receives work in the background** — the
message plumbing already exists; it just doesn't wake anything yet.

### Phase 3 — Delegated refresh from `BGAppRefreshTask`

Schedule against `getNextRequiredRefreshBlockheight()`. Reuse
`VTXORefreshService`'s existing pass. Small, high value.

### Phase 4 — Exit progression via `BGProcessingTask`

Progress + claim from the processing task, adaptively rescheduled against
the exit's block heights (see the exit use-case section). Update the Live
Activity locally on each run. Move the check-in reminders to the
T + grace / self-cancelling model in the same phase — this is also when
"reminders only appear when automation failed" becomes true for exits.

### Phase 5 — Lightning receive polish

- 5a (client-only): keep the claim loop alive when the user backgrounds
  the app while showing an invoice (`beginBackgroundTask` or
  `BGContinuedProcessingTask`) — belt-and-suspenders alongside the
  Phase 2 push wake, and the only path that works when silent pushes are
  throttled.
- 5b: tune the visible-push fallback for the locked-device / throttled
  cases. The "Receiving ₿X — Open Arké to accept it." banner **already
  ships** (it's the current alert push); what remains is the interplay
  with Phase 2's auto-claim (stale-banner replacement) and any copy/timing
  refinement informed by the HTLC hold-window answer below.

### Phase 6 (contingent) — Relay wake-up API

The app-requested alarm-clock endpoint described in the relay section.
Build only if Phase 1 field data shows BGTasks don't fire often enough;
the client side is small because the maintenance pass already computes
the deadline it would send.

## Open questions

- ~~**iCloud Keychain sync with `AfterFirstUnlock`**~~: RESOLVED
  2026-07-27 — verified on device with a two-device clean-room test; sync
  works, and the migrated accessibility attribute propagates to other
  devices on its own (secondary logged "already migrated" without having
  run the migration locally first).
- **HTLC hold window**: how long does the Ark server hold an incoming
  HTLC before it fails, and does the `IncomingLightningPaymentMessage`
  fire early enough in that window to claim from a background wake?
  (The message plumbing is confirmed — mailbox → relay →
  `mailbox_incoming_lightning_payment` push already ships — but as an
  alert-only push; the wake itself needs Phase 2's `content-available`
  addition.)
- **Cold-launch timing budget**: how long from background launch to
  "wallet ready"? Decides app-refresh vs. processing task placement for
  each pass step. Answered by Phase 1 logging.
- **How often does iOS actually grant `BGAppRefreshTask`/
  `BGProcessingTask` time** for our usage patterns? Field data from
  Phase 1 decides whether Phase 6 (relay wake-up API) gets built.

Resolved by the 2026-07-23 decisions: keychain accessibility (migrate to
`AfterFirstUnlock`), relay autonomy (never — dumb app-requested alarms
only), force-quit semantics (accepted limit; visible notifications are
the last line, no in-app "background updates are off" plumbing for now).

## References

- [RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md](../RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md) — Phase 1 detail
- [APNS_MAILBOX_SPEC.md](../APNS_MAILBOX_SPEC.md) — relay registration contract
- `Shared/Services/LightningClaimService.swift`, `ExitProgressionService.swift`,
  `VTXORefreshService.swift`, `RelayRegistrationService.swift` — the passes
- `Shared/Services/ExitProgressionNotifications.swift` — check-in
  reminders (currently fixed 90-min × 5 sequence)
- `Shared/Data/ExitStatus/` — `ExitProgress`, `BlockRef`: the block
  heights adaptive exit scheduling reads
- `ArkeMobile/AppDelegate_iOS.swift` — push entry points
- `Shared/Data/WalletManager/WalletManager+Notifications.swift` — relay registration + mailbox observer
- `~/workspace/arke-apns-relay-node` — relay source; `src/apns-sender.js`
  (push types per mailbox message), `protos/mailbox_server.proto`
  (mailbox message types)
- `Shared/Docs/Initialization/` — startup wallet detection hardening (same
  keychain-unavailable failure mode)
- Apple: BackgroundTasks framework (`BGAppRefreshTask`, `BGProcessingTask`,
  `BGContinuedProcessingTask`), ActivityKit push updates
