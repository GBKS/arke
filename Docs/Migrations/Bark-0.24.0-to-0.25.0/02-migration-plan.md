# Migration Plan: Bark FFI v0.24.0 → v0.25.0

Companion to [01-api-changes.md](01-api-changes.md). Phase 1 is mechanical
plumbing; Phase 2 (mailbox authorization lifetime) is the substance of this
bump and the reason the bindings change exists.

## Phase 0 — Package sanity (already done)

`Package.resolved` points at `bark-ffi-bindings` revision `157b0fc` (branch
`master`), uncommitted. The resolved `Bark.swift` carries the 0.25 surface;
contract version 30 unchanged. SPM resolves bindings and binary as a pair —
no manual xcframework step.

## Phase 1 — Compile fixes and protocol plumbing

Mechanical, no design decisions. Order within the phase doesn't matter; build
once at the end.

### 1a. `drainExits(vtxoIds:drainAll:address:feeRateSatPerVb:)`

1. `Shared/Services/ExitProgressionLogic.swift:22` — `ExitClaimWallet`
   requirement gains `drainAll: Bool` after `vtxoIds`. Extend the protocol's
   doc comment with the new contract (empty + false throws; ids parse
   all-or-nothing; unclaimable ids skipped).
2. `Shared/Data/BarkWalletProtocol.swift:106` — same, under the existing
   `MARK: - Exit Operations (Advanced - New in FFI)`; add a short doc comment
   in the file's style (the requirement has none today).
3. `Shared/Data/BarkWalletFFI/BarkWalletFFI+Exit.swift:348` — add the param,
   forward it at :362. Replace the `isEmpty ? "all"` log at :359 with
   `drainAll ? "all" : "\(vtxoIds.count)"`.
4. `Shared/Data/MockBarkWallet.swift:514` — add the param; same log fix at
   :516.
5. `Shared/Data/WalletManager/WalletManager+Operations.swift:183` — add the
   param, forward it. (Zero callers; kept because it mirrors the wallet.)
6. `Tests/Shared/ExitProgressTests.swift:490` — `RecordingClaimWallet` gains
   the param and records it (`drainedAll: Bool?`).
7. `Shared/Services/ExitProgressionLogic.swift:160` — `ExitClaimSequence.run`
   passes `drainAll: false`. See §Judgment calls for why `run`'s own
   signature does **not** change.

### 1b. `mailboxAuthorization(expirySecs:)`

1. Add the single constant. **Home: `RelayRegistrationService`**, as
   `static let mailboxAuthorizationExpirySecs: UInt32 = 30 * 86_400`. It is
   relay policy (how long the relay may read our mailbox), and the service
   already owns the TTL bookkeeping. Not on `BarkWalletProtocol` (policy-free,
   mirrors the FFI) and not in `WalletManager+Notifications` (a caller, not
   the owner). `authTTL` (:113) becomes
   `TimeInterval(Self.mailboxAuthorizationExpirySecs)` so there is one number.
2. `Shared/Data/BarkWalletProtocol.swift:189` — `mailboxAuthorization(expirySecs: UInt32) throws -> String`
   under `MARK: - Mailbox Operations`; doc comment noting the token cannot be
   revoked early.
3. `Shared/Data/BarkWalletFFI/BarkWalletFFI+Mailbox.swift:41/53` — add param,
   forward. (The certain compile break.)
4. `Shared/Data/MockBarkWallet.swift:802` — add param.
5. `Shared/Data/WalletManager/WalletManager+Notifications.swift:269` — pass
   `RelayRegistrationService.mailboxAuthorizationExpirySecs`.

### 1c. `LightningReceive.amountSats: UInt64?`

1. `Shared/Data/BarkWalletFFI/BarkWalletFFI+Lightning.swift:152` —
   `receiveStatus.amountSats.map { "\($0) sats" } ?? "any amount (pending)"`.
2. `:214` — `"amount_sats": receive.amountSats as Any` is not enough (still
   `Optional`); use `receive.amountSats.map { $0 as Any } ?? NSNull()` so the
   JSON dump emits `null` deliberately rather than by warning.
3. `Shared/Services/LightningClaimService.swift:165/191` — same `.map … ??`
   pattern; wording "amount pending".
4. Fixtures: `:493` → `amountSats: nil` (awaiting-payment, amountless);
   `:524` and `MockBarkWallet.swift:698` → a concrete settled amount (e.g.
   `10_000`, matching the mock's other Lightning fixtures).

No localized string in this phase — see README §Corrections. If a
user-visible surface for `LightningReceive` appears later, the string
follows the `defaultValue:` convention ("Any amount" for awaiting-payment,
"Amount pending" for htlcs-ready…delivering) and goes through `L10n` once it
has three call sites.

### 1d. Build

Active scheme ("Arke mobile"). Expect the probable `os.Logger` errors to be
gone after 1c; report anything else that surfaces. Desktop deliberately
unchecked (lean workflow; also already broken by the Docs basename issue).

## Phase 2 — Mailbox authorization lifetime: persist, half-window renewal, foreground trigger

> Status: **Decided** (Christoph, 2026-09-26): 30-day tokens, proactive
> renewal at half-life. Design below is the implementation proposal.

### What exists

`RelayRegistrationService` already:
- tracks `authExpiresAt`, preferring the relay-reported
  `authorization_expires_at` (`registerDevice`, :265);
- schedules the BGTask at mid-life (`backgroundRefreshDate`, :188) and the
  in-process timer at expiry − 1h (`nextRefreshDate`, :178);
- exposes `onNeedsRefresh` (wired in `WalletManager.swift:430–434` to
  `registerForPushNotifications(trigger: .timer)`);
- dedupes launch double-fires via `isRegistrationFresh` (1h window, :135).

`WalletManager+Notifications` already gates every path through
`mintAndRegisterWithRelay` (:230), which consults `isRegistrationFresh`.
`BackgroundTaskCoordinator.handleRefreshTask` / `handleAuthWakePush` call
`refreshRelayAuthInBackground`, which `forceRefresh()`es and re-registers.

### What is missing (the three items)

**2a. Persist the registration state.** Four values move from in-memory to
`UserDefaults`, read on `RelayRegistrationService.init`, written on every
successful `registerDevice`, cleared on `unregisterDevice`, on a 401, and in
`WalletDataCleanupService.clearUserDefaults()` (:454):

| Value | Key (in `UserSettings.swift` extension) | Stored as |
|---|---|---|
| `authExpiresAt` | `com.arke.relay.authExpiresAt` | `timeIntervalSince1970` (matches `com.arke.device.lastHeartbeat`) |
| `lastRegisteredAt` | `com.arke.relay.lastRegisteredAt` | same |
| `lastRegisteredDeviceToken` | `com.arke.relay.lastRegisteredDeviceToken` | string |
| `lastAuthHash` | `com.arke.relay.lastAuthHash` | string (SHA-256 hex, not the token) |
| `lastRegisteredMailboxId` | `com.arke.relay.lastRegisteredMailboxId` | string — guards against a replaced wallet inheriting the old wallet's "no renewal needed" |

The authorization hex itself is **never** persisted — it is a credential; only
its hash is. Persistence lives in `UserDefaults`, not on the service instance,
because `WalletManager` recreates the service per wallet init
(`WalletManager.swift:430`) and nils it on close (`:1148`) — an instance
field would be lost exactly when it matters (cold launch).

**2b. Replace the 1h freshness window with the half-life rule.** One pure,
tested function, and **one derived date that every path shares**:

```swift
/// Midpoint of the authorization's *actual* life as the relay reported it:
/// registeredAt + (expiresAt - registeredAt) / 2. Not "now + remaining/2"
/// (moves every time it is read) and not "expiresAt - 30d/2" (wrong if the
/// relay capped the token to a shorter window - we'd renew on every launch).
nonisolated static func renewalDate(registeredAt: Date, expiresAt: Date) -> Date

/// Renew when: no registration is known, the device token changed, the
/// persisted mailbox id isn't this wallet's, or `now >= renewalDate`.
nonisolated static func needsRenewal(
    registeredAt: Date?,
    expiresAt: Date?,
    registeredDeviceToken: String?,
    currentDeviceToken: String?,
    registeredMailboxId: String?,
    currentMailboxId: String,
    now: Date
) -> Bool
```

`renewalDate` replaces **three** dates that today drift apart:

| Today | Problem | After |
|---|---|---|
| `backgroundRefreshDate` = now + remaining/2 (:188) | re-read on every `.background` (`ArkeMobile.swift:143`), so each backgrounding pushes the BGTask request later — it creeps toward expiry and can never fire early | fixed `renewalDate` |
| `nextRefreshDate` = expiry − 1h (:178), in-process timer | never fires in practice; a resident device (iPad on a stand) would wait 29d 23h | timer sleeps until `renewalDate` |
| `isRegistrationFresh` 1h window (:135) | launch dedupe only; unrelated to token life | `!needsRenewal` |

X-Ray (`relayAuthNextForegroundRefresh`, `WalletManager+Notifications.swift:69`;
row in `BackgroundActivityView_iOS.swift`) currently shows the expiry − 1h
timer date — under 30d tokens it would read "in 29 days", which is not when
anything happens. Point it at `renewalDate` and relabel "next renewal".

`mintAndRegisterWithRelay` (:230) keeps its shape, consulting `needsRenewal`.
`forceRefresh()` still clears state so timer/BGTask/wake-push callers always
re-register — see §Judgment calls 3.

`RelayRegistrationFreshnessTests` gains cases: fresh 30d token → no renewal;
one second before the midpoint → none, at the midpoint → renewal (`>=`
pinned); relay-capped 24h token → renewal at 12h, not at 15d; token changed →
renewal; mailbox id changed → renewal; nil state → renewal; already expired →
renewal. The existing 1h-window cases go with the window.

**2c. Foreground trigger.** `ArkeMobile.swift:158` (`newPhase == .active`)
adds `Task { await walletManager.registerForPushNotifications(trigger: .foreground) }`
when `oldPhase == .background`. Gated by 2b, it is a no-op for ~15 days out
of 30; when it fires, the new token reaches the relay immediately via the
existing `registerDevice` path (the brief's "send the new token to the
notification relay immediately" is what `mintAndRegisterWithRelayCore`
already does).

Launch is already covered: `ArkeMobile.swift:127` and `WalletManager.swift:750`
call `registerForPushNotifications()`, now gated by the persisted state, so
a cold launch with 20 days left does nothing — the "don't renew on every
launch" requirement.

### Interactions to keep straight

- **Relay-reported expiry still wins.** If the relay reads a different expiry
  out of the token than we assume (clock skew, relay-side cap), `registerDevice`
  already prefers it. The half-window rule then runs off the relay's number.
- **Timer and BGTask both move to `renewalDate`** (2b table). The BGTask
  `earliestBeginDate` becomes ~15 days out; iOS may or may not honour that
  horizon, which is exactly why the launch/foreground checks exist. The
  `.background` safety-net submit in `ArkeMobile.swift:143` keeps working but
  now re-submits the *same* date instead of a later one each time.
- **Relay wake pushes** (2h/1h before expiry, `SWIFT_AUTH_WAKE_SPEC.md`) key
  off the expiry the relay read from the token, so they move to day 30 with
  no relay change *if* the relay accepts 30d tokens. **Open check**, see below.
- **Wallet deletion.** `unregisterDevice` tells the relay to forget the
  mailbox, but the authorization stays valid on the Ark server for up to 30
  days — it cannot be revoked. Same exposure class as before, 30× longer.
  Accepted: the relay is ours, the token only grants mailbox *read*, and a
  deleted wallet's mailbox holds nothing new. Record in Multi_Device_Design
  S7 (delete-everywhere) as a note, not a scenario.
- **Persisted state vs. a replaced wallet.** If the wallet is replaced without
  `WalletDataCleanupService` running (shouldn't happen, but the stale-mailbox
  wake handling exists for a reason), a persisted `authExpiresAt` from the old
  wallet would wrongly suppress registration of the new one. Covered by the
  persisted `lastRegisteredMailboxId` in 2a and the mailbox check in
  `needsRenewal`.
- **Notifications toggled off → on.** Off calls `unregisterFromPushNotifications`
  (`NotificationsSettingView_iOS.swift:146`) → `unregisterDevice`, which
  clears the persisted state; on re-registers with no state → mints. ✓
- **Renewal fails at the midpoint** (offline, relay down). Nothing special:
  the token is valid for another ~15 days, and the next launch/foreground
  retries because `now >= renewalDate` stays true. The journal records the
  failure. No backoff needed.

### Scenario walk (the check that produced the table in 2b)

| Scenario | Expected | Holds after plan? |
|---|---|---|
| Update from 0.24 install (no persisted state) | one mint, 30d token | ✓ (nil state → renew) |
| Daily launches, days 1–14 | no relay traffic | ✓ (`now < renewalDate`) |
| Launch or foreground on day 15+ | mint + register immediately | ✓ (2b + 2c) |
| BGTask granted ~day 15 | mint + register | ✓ (`forceRefresh` path unchanged) |
| Phone off 40 days | mint on first launch; never sends the expired token | ✓ (we mint, not resend) |
| APNs token changes | immediate re-register | ✓ (token mismatch) |
| Relay caps the token to 24h (hypothetical — current relay has no cap, see Open checks) | renew every 12h, not every launch | ✓ only with the actual-life midpoint (2b) — **the reason the rule changed** |
| Resident device, never backgrounded | timer renews at midpoint | ✓ after timer moves to `renewalDate` (was expiry − 1h) |
| Wallet deleted on device | relay forgets device; token lives ≤30d on Ark server | ✓ / accepted |
| Wallet replaced without cleanup | new wallet registers | ✓ (mailbox id check) |

### Open checks — all resolved 2026-09-26 from source

1. **Does the relay accept a 30-day token?** ✅ Yes, unchanged.
   `arke-apns-relay-node/src/mailbox-auth.js` reads the i64 expiry out of
   the 105-byte token and only rejects timestamps outside 2020–2100
   (`MIN_EXPIRY_SECONDS` / `MAX_EXPIRY_SECONDS`); there is no TTL cap. The
   register route (`src/index.js:1110`) rejects only an *already expired*
   token with `400 authorization_expired`, and returns the parsed expiry as
   `authorization_expires_at` (`:1169`) — so the app's `registerDevice` will
   see the true 30-day expiry and the relay-capped scenario in the table
   cannot occur with the current relay (the actual-life midpoint rule stays;
   it costs nothing and protects against a future cap).
2. **Does the relay's wake schedule need retuning?** ✅ No. `src/auth-wake.js`
   `nextWakeDueAt` derives every wake from the token's parsed expiry: one at
   `AUTH_WAKE_LEAD_MS` (2h) before, one at half that, then post-expiry
   attempts 1h after and daily ×7. A new registration with a different
   expiry resets the state. With the app renewing at day 15, the pre-expiry
   wakes simply never come due.
3. **Does the Ark server cap the lifetime?** ✅ No (Christoph checked the
   bark code; confirmed here against the local `bark-0.7.1` checkout).
   `server/src/rpcserver/mailbox.rs:20` `check_auth_not_expired` is the only
   validation — expired → `invalid_argument "mailbox authorization
   expired"`, with a 5-second leeway (`lib/src/mailbox.rs:293`). No maximum.
   (The `max_ttl_secs` check found in `~/workspace/noah/server/src/mailbox_auth.rs`
   is a different project's server, not the Ark server Arke talks to.)

What still needs a device: one real registration after the change, to see a
~15-day "next renewal" in X-Ray and the `authorization_expires_at` ≈ 30d in
the relay's response. Everything policy-related is now verified from source.

## Judgment calls — recommendations

1. **`ExitClaimSequence.run` keeps its signature; always `drainAll: false`.**
   Recommendation: do not add a `drainAll` parameter or a "claim all" mode to
   the sequence. Nothing needs it — the service already passes the full
   claimable set explicitly, which is the safer contract (the app knows what
   it asked to claim and records exactly those ids). A `drainAll: true` path
   would let bark decide the set, and `ExitClaimTransaction` can't tell us
   what it chose. Tests pin the decision: (a) full claimable set forwarded
   with `drainAll == false`; (b) a subset forwarded with `drainAll == false`;
   (c) empty `claimableVtxoIds` fails before any effect — implemented as an
   explicit guard at the top of `run` throwing a typed error, so we never
   round-trip to bark to learn what we already know, and the test double
   doesn't have to simulate bark's throw.

1b. **What the user sees if bark throws "filtered down to nothing".** The
   race — every claimable id becomes unclaimable between `listClaimableExits`
   and `drainExits` — lands in the existing `catch` at
   `ExitProgressionService.swift:245`, which records the message per VTXO via
   `claimBlockedUpdates` and retries next interval. Those VTXOs show as
   blocked with bark's message until the next tick's `listClaimableExits`
   drops them. Acceptable and self-healing; no new handling. Worth one line in
   `Features/Exit_Blocked_State.md` so nobody hunts for it later.

2. **"Unclaimable ids are skipped" is now a documented blind spot.**
   `recordClaim(txid, feeSats, claimableVtxoIds)` records every *requested*
   id as drained; if bark skipped one (raced to unclaimable between
   `listClaimableExits` and `drainExits`), we record a claim link for a VTXO
   not in the tx. Same exposure as before 0.25, now spelled out upstream.
   Recommendation: don't work around it in the app (the PSBT could be parsed
   for inputs, but that duplicates bark's job); file an ask in
   `Bark_Bindings_Feedback.md` for `ExitClaimTransaction.vtxoIds` (or
   `skippedVtxoIds`). Add to `Open_Follow_Ups` under Exits.

3. **BGTask and wake-push paths: keep `forceRefresh()` semantics.**
   Recommendation: the background paths continue to re-register
   unconditionally. They only run when the relay or the BGTask scheduler
   asked for a refresh (mid-life date or pre-expiry wake), so gating them
   again on the half-window rule would only fight the relay's schedule. The
   half-window rule governs the *unsolicited* checks: launch and foreground.

4. **Constant location: `RelayRegistrationService`, not a global.** The brief
   asks for "a single constant"; one static on the service that already
   owns `authTTL` is the single source, and `authTTL` derives from it. A
   free-floating global would be a second place to look.

5. **No localized "Any amount" string yet.** Recommendation: not until a
   `LightningReceive` value reaches a view. Adding an unreferenced catalog
   key is deleted by the next IDE build (`xcstrings-rewritten-on-build`).
   Stronger still: Arke never *creates* an amountless invoice — every invoice
   path guards `amountSats > 0` (`BarkWalletFFI+Lightning.swift:103/331/381`,
   `:286` for the optional pay path) — so `nil` is unreachable for this
   wallet's own receives today. It only matters for the debug reads, and for
   correctness if a future feature adds amountless invoices.

6. **On-device verification without waiting 15 days.** No debug UI needed:
   on the simulator, backdate the persisted registration with
   `xcrun simctl spawn booted defaults write <bundle-id> com.arke.relay.lastRegisteredAt -float <epoch>`
   (and `authExpiresAt` likewise), relaunch, and read the journal / X-Ray
   "next renewal" row. On a real device, the X-Ray row confirming a
   ~15-day renewal date after one fresh registration is the check; the day-15
   renewal itself is verified by the journal when it happens.

## Tests

- `ExitClaimSequenceTests` (`Tests/Shared/ExitProgressTests.swift`): three
  new/adjusted cases per Judgment call 1.
- `RelayRegistrationFreshnessTests`: `renewalDate` + `needsRenewal` cases per
  §2b, including the relay-capped-24h case; the existing 1h-window cases are
  deleted with the window. `isWakeForCurrentMailbox` cases stay.
- Scoped runs only for these two files; full mobile suite batched at end of
  task (lean workflow).

## Chores

1. `Bark_Bindings_Unadopted_API.md`: baseline → v0.25.0 @ `157b0fc`; new
   section noting nothing new is unadopted from this bump; Adopted-since
   entry for `mailboxAuthorization(expirySecs:)` and `drainAll`.
2. `Bark_Bindings_Feedback.md`: (a) the expiry parameter shipped — mark our
   ask resolved; (b) new ask: `ExitClaimTransaction` should report included
   or skipped ids.
3. `Open_Follow_Ups.md`: new "Bark 0.25 Migration" section — the two open
   relay checks, the skipped-ids blind spot, on-device verification of the
   persisted-expiry launch path (cold launch → no re-mint; ≥15 days → re-mint,
   or simulated by editing the persisted date).
4. `RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md` / `SWIFT_AUTH_WAKE_SPEC.md`: one
   amendment paragraph each — the 24h assumption is gone, lifetime is now
   `mailboxAuthorizationExpirySecs`.
5. `Launch_Sequence_Contract.md`: add a rule — relay registration at launch
   is gated by persisted authorization state, not attempted unconditionally.
6. 04-completion-report.md.

## Execution order

1. Phase 1 (1a–1c) + build green.
2. Phase 2a–2c + `RelayRegistrationFreshnessTests`.
3. `ExitClaimSequenceTests` additions.
4. Chores 1–5.
5. Mobile test suite batch run; completion report.
6. Christoph: one on-device registration to see the 30d expiry land, and the
   Xcode Docs-exclusion pass for the new Migrations folder.
