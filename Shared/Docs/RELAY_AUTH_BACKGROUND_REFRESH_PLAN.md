# Relay Authorization Background Refresh Plan

> **Amended 2026-07-27** to match the superseding decisions in
> [Background_Execution.md](Features/Background_Execution.md) (this plan is
> its Phase 1): the BGTask identifier is the shared `cash.arke.refresh`
> (not a relay-auth-only `cash.arke.relayAuthRefresh`), and the
> scheduling/registration plumbing lives in a standalone
> `BackgroundTaskCoordinator` (not a `WalletManager` extension), so later
> phases plug into the same coordinator.
>
> **Status 2026-07-27: implemented** (work items 1–5). The handler runs
> `WalletManager.refreshRelayAuthInBackground()` — settings/keychain gating
> (keychain-unavailable = retry, never "no wallet"), minimal
> `openWalletIfNeeded` on cold background launches, then the same
> mint + `/v1/register` core as the foreground path
> (`mintAndRegisterWithRelay()`). `RelayRegistrationService.nextRefreshDate`
> (expiry − buffer) is the single timing source: the in-process timer, the
> BGTask request submitted on every successful registration, and the
> backgrounding safety net all use it. `expirationHandler` cancels the
> in-flight Task (propagates into URLSession); reschedule always happens —
> chain-preserving submit at wake, accurate-deadline replace on completion.
> Device-verified 2026-07-27 via `_simulateLaunchForTaskWithIdentifier`:
> the background pass re-registered with the relay and rescheduled at the
> fresh token's expiry-minus-buffer (0.06s warm; cold-launch timing comes
> from Phase 1 field data). Also verified: the opted-out branch
> (notifications disabled → "nothing to do", success, no relay call).

## Goal

Keep the mailbox relay (`relay.arke.cash`) supplied with a non-expired
`authorization_hex` even when the app is backgrounded or has been
terminated by the OS, so a mailbox never silently stops delivering push
notifications just because the user hasn't opened the app recently.

## Context

- `bark-ffi`'s `mailbox_authorization()` mints a token with a fixed 24h
  expiry (`bark-ffi/src/core/wallet.rs`).
- The relay (`arke-apns-relay-node`) is handed that token once at
  `POST /v1/register` and reuses it for every backfill/subscribe call and
  every reconnect until it receives a fresh one. It cannot mint its own —
  only the wallet holds the mailbox private key.
- `RelayRegistrationService` ([Shared/Services/RelayRegistrationService.swift](../Services/RelayRegistrationService.swift))
  now schedules an in-process refresh ~1h before the 24h token expires
  (`onNeedsRefresh`, wired in `WalletManager.swift` to
  `registerForPushNotifications()`). This was the "simple fix" for the
  incident where the Ark server admin reported the relay hammering their
  server with rejected, long-expired authorizations.
- **The gap this plan addresses:** that refresh is a plain `Task { try await
  Task.sleep(...) }`. iOS suspends in-process timers once the app is
  backgrounded for more than a few seconds/minutes, and kills the process
  outright under memory pressure or after extended background time. A user
  who doesn't open the app for 24h+ will still end up with a stale relay
  registration, exactly the failure mode we just fixed for the
  foreground/alive case.

## Why `BGAppRefreshTask` alone may not be enough

`BGTaskScheduler` app-refresh tasks are opportunistic: the OS decides when
(and whether) to actually run them based on usage patterns, battery, and
network conditions. Apps the user opens rarely get *very* infrequent
background time — there's no guaranteed cadence. This is a real risk for a
24h-expiry token if the buffer window is tight, and needs to be designed
around rather than assumed away. See "Open Questions" below for a
complementary silent-push approach that doesn't have this problem.

## Design

1. **Register the task identifier early.** In
   `ArkeMobile/AppDelegate_iOS.swift`, call
   `BGTaskScheduler.shared.register(forTaskWithIdentifier: "cash.arke.refresh", using: nil) { task in ... }`
   before `application(_:didFinishLaunchingWithOptions:)` returns (required
   by the API — registering later is a no-op). `cash.arke.refresh` is the
   shared short-pass (`BGAppRefreshTask`) identifier from
   Background_Execution.md; relay auth is its first tenant.
2. **Declare capabilities in Info.plist** (`ArkeMobile/Info.plist`):
   - Add `fetch` and `processing` to the existing `UIBackgroundModes`
     array (currently only `remote-notification`).
   - Add a new `BGTaskSchedulerPermittedIdentifiers` array containing
     **both** `cash.arke.refresh` and `cash.arke.maintenance` — permitted
     identifiers ship baked into the app's Info.plist, so declaring the
     Phase 4 processing-task identifier now avoids a later plist change.
     Only `cash.arke.refresh` gets a handler in this plan.
3. **Task handler** does the same work `onNeedsRefresh` already does today —
   mint a fresh `mailboxAuthorization()` from the wallet and re-POST
   `/v1/register` — via `WalletManager.registerForPushNotifications()`.
   Wrap it in the task's `expirationHandler` contract:
   - Call `task.expirationHandler = { operation.cancel() }` so we stop
     cleanly if the OS revokes execution time mid-request.
   - Call `task.setTaskCompleted(success:)` when the network call finishes
     (or is cancelled).
   - **Always reschedule the next occurrence before returning**, success or
     failure — a missed/failed run must not end the refresh cycle.
4. **Scheduling policy.** Submit a `BGAppRefreshTaskRequest` with
   `earliestBeginDate` set relative to the *real* token expiry (reuse
   `authTTL`/`authRefreshBuffer` from `RelayRegistrationService`, i.e.
   request to run ~1h before the 24h mark), not a fixed constant — so if the
   auth TTL policy ever changes, both refresh paths stay in sync.
   - Submit this request every time a registration/refresh succeeds
     (foreground or background), mirroring how `scheduleAuthRefresh()`
     re-arms itself today.
   - Also submit one opportunistically on `scenePhase`/`applicationDidEnterBackground`
     if none is currently scheduled, as a safety net.
5. **Keep the existing in-process timer as-is.** It already handles the
   common case (app stays alive, or user reopens it before expiry). The
   background task is purely for the case where the process gets suspended
   or killed before that timer fires.

## Work Items

1. Add `BGTaskSchedulerPermittedIdentifiers` (both identifiers) + `fetch`
   and `processing` background modes to `ArkeMobile/Info.plist`.
2. Register the task handler in `AppDelegate_iOS.swift` at launch.
3. Add a standalone `BackgroundTaskCoordinator` (iOS-only — `ArkeMobile/`
   or `Shared/Services/` with `#if os(iOS)`; see the Architecture section
   of Background_Execution.md) that:
   - Submits/cancels `BGAppRefreshTaskRequest`s.
   - Implements the launch handler: mint auth, re-register, complete task,
     reschedule.
   - Is where later phases plug in (mailbox-push entry point, maintenance
     pass, `BGProcessingTask`) — services keep owning "what", the
     coordinator owns "when".
4. Call the "submit next refresh" entry point from:
   - `RelayRegistrationService.scheduleAuthRefresh()` success path (or a
     sibling hook alongside `onNeedsRefresh`), so foreground and background
     scheduling share one source of truth for timing.
   - App entering background, as a safety net if nothing is scheduled yet.
5. Add debug logging (with an OSLog subsystem, not `print`, unlike the
   existing service) distinguishing "background task ran" vs "foreground
   timer ran" vs "skipped — nothing due yet", so we can tell from device
   logs/TestFlight whether the OS is actually granting background time
   often enough in practice.
6. Manually verify via Xcode's debugger simulation command:
   ```
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"cash.arke.refresh"]
   ```

## Acceptance Criteria

- Task identifier registered and declared in Info.plist; app doesn't crash
  or assert on launch (mis-registering is a common source of launch-time
  crashes).
- Killing the app and simulating the background task run (via the debugger
  command above) successfully re-registers with the relay and reschedules
  the next occurrence.
- `expirationHandler` cancels in-flight work cleanly (verified by forcing
  expiration in the simulator) and still reschedules.
- No behavior regression to the existing foreground refresh path in
  `RelayRegistrationService` — that shipped fix stays as the primary/first
  line of defense; this background task is a fallback for when it can't run.

## Open Questions

- **Is `BGAppRefreshTask` reliable enough on its own?** Open, answered by
  this plan's field-data logging. The fallback shape is decided, though:
  per Background_Execution.md Decision 2 (the relay never acts on its own
  initiative), a relay-decided "your auth is about to expire" push is
  ruled out. Instead the contingent Phase 6 **app-requested wake-up API**
  covers this case uniformly — the app POSTs a wake for
  expiry-minus-buffer, the relay just delivers a silent push at that
  time. Build only if the field data shows BGTasks don't fire often
  enough.
- Do we need a `BGProcessingTask` instead/in addition, if minting +
  registering ever needs more time/resources than `BGAppRefreshTask`'s
  short execution window allows? Current work (one wallet call + one HTTP
  POST) should comfortably fit; revisit if that changes.
