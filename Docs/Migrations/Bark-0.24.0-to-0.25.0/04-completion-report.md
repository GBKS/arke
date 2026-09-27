# Completion Report: Bark FFI v0.24.0 → v0.25.0

**Completed:** 2026-09-26 (same day: docs → Phase 1 → Phase 2 → chores)
**Result:** build green (active scheme "Arke mobile", tests included); full
mobile suite **408 passed, 0 failed** via `xcodebuild test`; scoped suites
`ExitClaimSequenceTests` 6/6, `RelayRegistrationRenewalTests` 9/9,
`RelayRegistrationPersistenceTests` 4/4, `StaleWakeDecisionTests` 4/4.

## What shipped

### Phase 1 — protocol plumbing and compile fixes

**`drainExits(vtxoIds:drainAll:address:feeRateSatPerVb:)`** — parameter
mirrored on `ExitClaimWallet` (`ExitProgressionLogic.swift`, with the 0.25
contract in the doc comment), `BarkWalletProtocol`, `BarkWalletFFI+Exit`,
`MockBarkWallet`, the `WalletManager+Operations` pass-through and the
`RecordingClaimWallet` test double. `ExitClaimSequence.run` passes
`drainAll: false` and now throws `ClaimError.noVtxoIds` on an empty list
before touching the wallet. The two `isEmpty ? "all"` log strings now key
off `drainAll`. No `drainAll: true` exists anywhere in the app.

**`mailboxAuthorization(expirySecs:)`** — mirrored on the protocol, wrapper
and mock. The single constant lives on `RelayRegistrationService`:
`static let mailboxAuthorizationExpirySecs: UInt32 = 30 * 86_400`, and the
old `authTTL = 24h` is now derived from it. The one call site
(`WalletManager+Notifications.mintAndRegisterWithRelayCore`) passes it.

**`LightningReceive.amountSats: UInt64?`** — four reads fixed with
`.map { "\($0) sats" } ?? "amount pending"` (log/debug text; the JSON dump
emits `null`); fixtures: awaiting-payment preview → `nil`, the two settled
fixtures → `10_000`. No localized string (no UI surface; Arke never creates
amountless invoices — see README §Corrections).

Compile breaks matched the prediction exactly: the mailbox call, plus the two
`os.Logger` interpolations in `LightningClaimService` (Optional has no
`OSLogInterpolation` overload — confirmed real).

### Phase 2 — relay authorization: persist, mid-life renewal, foreground trigger

`RelayRegistrationService`:

- **`PersistedRegistration`** (`nonisolated struct`, Equatable): auth hash,
  expiry, registered-at, device token, mailbox id. Written through to
  UserDefaults on every change (`UserDefaults.relay*Key`, five keys in
  `UserSettings.swift`), loaded in `init` — the instance is recreated per
  wallet init, so it can't be the memory. The authorization hex is never
  stored. `.empty` removes every key, so "cleared" and "never registered"
  read the same.
- **`renewalDate`** = `registeredAt + (expiresAt − registeredAt) / 2` — the
  midpoint of the token's *actual* reported life. Replaces
  `nextRefreshDate` (expiry − 1h) and `backgroundRefreshDate`
  ("now + remaining/2", which crept later on every backgrounding). The
  in-process timer, the BGTask request (`registerDevice` success path,
  `BackgroundTaskCoordinator.handleRefreshTask`, the `.background` safety
  net in `ArkeMobile.swift`) and X-Ray all read it.
- **`needsRenewal(...)`** (pure static + instance wrapper) replaces
  `isRegistrationFresh` and its 1h window: renew when no registration is
  known, the device token changed, the persisted mailbox id isn't this
  wallet's (case-insensitive), or `now >= renewalDate`.
- `registerDevice` writes the whole struct on success (relay-reported expiry
  still preferred); 401, `unregisterDevice` and `forceRefresh` set `.empty`.
  The timer clears state directly rather than via `forceRefresh()` — that
  would cancel the very task about to call the relay, and a cancelled task's
  URLSession call throws.

`WalletManager+Notifications`: `mintAndRegisterWithRelay` consults
`needsRenewal(currentDeviceToken:currentMailboxId:)`; `relayAuthBackgroundRefreshDate`
and `relayAuthNextForegroundRefresh` collapsed into `relayAuthRenewalDate`.

`ArkeMobile.swift`: the `.active` scenePhase return (from `.background`)
now calls `registerForPushNotifications(trigger: .foreground)` — a no-op
until the midpoint, then mints and sends immediately.

`WalletDataCleanupService.clearUserDefaults` removes the five relay keys
(`UserDefaults.relayRegistrationKeys`); the wipe inventory lists them.

X-Ray (`BackgroundActivityView_iOS`): "Next timer refresh" row became
"Next auth renewal" (`data_bg_next_renewal_label`, extracted by the IDE
build; the old key and its translations were dropped by re-extraction —
follow-up in `Open_Follow_Ups.md` Localization).

### Tests

- `ExitClaimSequenceTests` +3: full claimable set → explicit ids +
  `drainAll == false`; subset → same; empty ids → `ClaimError.noVtxoIds`
  before any wallet call or effect.
- `RelayRegistrationFreshnessTests.swift` rewritten: `RelayRegistrationRenewalTests`
  (midpoint date; fresh token not renewed on days 1–14; boundary at exactly
  the midpoint with `>=`; expired renews; **relay-capped 24h token renews at
  12h, not on every launch**; token change; other mailbox; case-insensitive
  mailbox; every nil-state combination) and `RelayRegistrationPersistenceTests`
  (empty by default; round trip; `.empty` removes every key; the wipe key
  list covers every field). `StaleWakeDecisionTests` unchanged.

### Chores

- `Bark_Bindings_Unadopted_API.md`: baseline → v0.25.0 @ `157b0fc`; v0.25
  section (nothing unadopted; `drainAll: true` recorded as deliberately
  unused); three Adopted-since entries.
- `Bark_Bindings_Feedback.md`: §1.3 addendum + ask #19
  (`ExitClaimTransaction.vtxoIds` / `skippedVtxoIds`); the expiry parameter
  and the other two 0.25 changes credited under "What's working well".
- `Open_Follow_Ups.md`: "Bark 0.25 Migration" section (on-device checks,
  relay-side confirmation, skipped-ids gap, Multi_Device S7 note, desktop
  Docs exclusion) + Localization item for the new X-Ray key.
- `RELAY_AUTH_BACKGROUND_REFRESH_PLAN.md`, `SWIFT_AUTH_WAKE_SPEC.md`,
  `Features/Background_Execution.md`: 24h assumptions amended in place.
- `Launch_Sequence_Contract.md`: **rule 27** — launch/foreground relay
  registration is gated by persisted authorization state.
- `Features/Exit_Blocked_State.md`: note on "filtered down to nothing" claim
  errors (self-healing via the existing per-VTXO blocked recording).

## Verification

- Builds: green after Phase 1 (32.6s), after Phase 2 (31.1s), after the
  isolation fixes (24.3s); IDE builds, so the string catalog was re-extracted
  each time. Desktop deliberately unchecked (lean workflow; already broken by
  the Docs basename issue).
- Warnings: ten "main actor-isolated static property referenced from
  nonisolated context" on the new UserDefaults keys → fixed with
  `nonisolated static let`; "main actor-isolated conformance to Equatable" on
  `PersistedRegistration` → fixed with `nonisolated struct`. The project
  builds with `InferIsolatedConformances` and default main-actor isolation,
  so any type a nonisolated test compares needs the modifier. The two
  isolated-conformance warnings left in the test compile are pre-existing
  (`WalletManager.FreshWalletOrigin`, `WalletManager.swift:128`) — not from
  this migration, left alone.
- Full mobile suite: 408 passed, 0 failed (`xcodebuild test`, iPhone 17 Pro
  simulator). The MCP `RunSomeTests` still reports tests as "not run" — use
  xcodebuild, as before.
- On-device (Christoph, 2026-09-26, iPhone on signet): the first run of the
  build registered with a 30-day token; the second run's post-init
  registration path logged "Skipping relay registration (trigger:
  foreground) - authorization not yet due for renewal" and made no relay
  call — the churn the migration exists to remove is gone on launch two.
  X-Ray shows "Relay auth expires" 30 days out and "Next auth renewal" 15
  days out, i.e. the relay reported the full 30-day expiry (no cap) and the
  midpoint math matches. Remaining observation: the actual day-15 renewal
  (`Open_Follow_Ups.md`). No green baseline existed before the work (the
  bindings bump broke the build), so the first Phase 1 build is the baseline.

## Deviations from the plan

1. **`ClaimError.noVtxoIds` is a typed error on `ExitClaimSequence`** rather
   than a generic throw, so the test pins the exact case and the service's
   per-VTXO blocked recording gets a stable message. The service never hits
   it (it guards `!isEmpty` itself); it is a contract, not a code path.
2. **`forceRefresh()` now also clears the device token and mailbox id** (it
   sets `.empty`); the old version kept `lastRegisteredDeviceToken`. Harmless:
   every `forceRefresh` caller re-registers immediately, and `needsRenewal`
   treats missing state as "renew" anyway.
3. **X-Ray key renamed** (`data_bg_next_timer_label` → `data_bg_next_renewal_label`)
   rather than editing the old key's default value, because the label's
   meaning changed, not just its wording. Costs three translations.
4. **The JSON dump** uses `NSNull()` for a nil amount instead of `as Any`
   (which would still have been an Optional-in-Any warning) — `null` in the
   output is the honest representation.
5. **Nothing in `Multi_Device_Design.md` yet** — the S7 note about the
   non-revocable 30-day token is in `Open_Follow_Ups.md` rather than edited
   into the design doc; questions-are-not-decisions applies (it's a note for
   a scenario Christoph owns).
