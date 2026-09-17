# Claude Agent Spec: Swift App -> Handle `mailbox_auth_refresh` Wake Pushes

## Goal

Keep the relay supplied with a non-expired mailbox authorization even when iOS doesn't grant the app background-task time, by responding to a silent push from the relay.

## Context

- `bark-ffi`'s `mailbox_authorization()` mints tokens with a fixed 24h expiry. Once the relay's copy expires, the mailbox stops delivering pushes until the app re-registers.
- The app already refreshes in the foreground (in-process timer) and in the background (`BGAppRefreshTask`, identifier `cash.arke.refresh`, via `WalletManager.refreshRelayAuthInBackground()`).
- Field data from the relay (2026-09-17): 124 of 151 registered mailboxes held an expired authorization, including mailboxes registered only 1–2 days earlier. `BGAppRefreshTask` alone is not keeping tokens alive.
- The relay now reads the expiry out of the token and sends a **silent wake-up push** when it is about to lapse, or has. This amends Decision 2 in `Background_Execution.md`: the relay acts on its own initiative in exactly this one case, using nothing but the expiry inside the token the app gave it.

## What the relay sends

Silent background push (`apns-push-type: background`, priority 5, `content-available: 1`, no alert, no sound):

```json
{
  "aps": { "content-available": 1 },
  "type": "mailbox_auth_refresh",
  "mailbox_id": "<MAILBOX_ID_HEX>",
  "authorization_expires_at": 1789735092
}
```

- `authorization_expires_at` is UNIX seconds, the expiry of the token the relay currently holds. It may be in the past.
- `apns-collapse-id` is set per mailbox, so a phone that was unreachable receives at most one.
- Schedule per token: 2h before expiry; 1h before expiry if no re-registration arrived; then 1h after expiry and once a day after that, 7 times in total. Any successful `POST /v1/register` with a new token resets it.
- Sent only to devices registered for that mailbox. Users with notifications disabled are never registered, so they never receive it.

## Work Items

1. **Route the new type before the generic mailbox branch.** In `AppDelegate_iOS`'s `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`, the existing check `type.contains("mailbox")` would match `mailbox_auth_refresh` and send it to `WalletManager.refresh()`, which syncs the wallet but does not re-register. Handle `type == "mailbox_auth_refresh"` first:
   - Call the same core the BGTask uses: `WalletManager.refreshRelayAuthInBackground()` (settings/keychain gating, minimal `openWalletIfNeeded` on a cold background launch, mint + `/v1/register`).
   - Call the `fetchCompletionHandler` exactly once when it finishes: `.newData` on a successful re-registration, `.noData` when there was nothing to do (notifications disabled, no wallet), `.failed` on error. iOS uses this to decide how much background time the app gets in future, so don't report `.newData` on failure.
   - Stay inside the ~30s background window; cancel the in-flight request if it runs long, as the BGTask `expirationHandler` path already does.
2. **Ignore a wake for a different mailbox.** If `mailbox_id` in the payload doesn't match the current wallet's mailbox (wallet was replaced on this device), do nothing and complete with `.noData`. Optionally call unregister for that stale mailbox id.
3. **Report what triggered each registration.** Add an optional `trigger` field to the `POST /v1/register` body:

   | Value | When |
   |---|---|
   | `foreground` | app launch / foreground refresh |
   | `timer` | the in-process expiry timer (`onNeedsRefresh`) |
   | `background_task` | `BGAppRefreshTask` handler |
   | `wake_push` | handling `mailbox_auth_refresh` |
   | `token_change` | APNs device token changed |

   Lowercase letters and underscores only, max 32 chars; anything else is recorded as `unspecified`. The relay counts registrations per trigger, which answers the open question in `Background_Execution.md` ("how often does iOS actually grant BGTask time?") with server-side numbers instead of device logs.
4. **Schedule from the real expiry (optional but recommended).** The `201` response now includes `authorization_expires_at` (UNIX seconds, or `null`). Use it for `RelayRegistrationService.nextRefreshDate` instead of assuming `authTTL = 24h`, so a future TTL change in bark-ffi needs no app change.
5. **Widen the background-task refresh buffer (recommended).** `BGAppRefreshTaskRequest.earliestBeginDate` is advisory; iOS routinely runs the task hours later. With the current ~1h buffer before a 24h expiry, iOS has a one-hour window to get it right, which the field data shows it usually misses. Request the background refresh at roughly half the token's life (`expiry − 12h`). Cost: about one extra registration per day. The foreground timer can keep its tight buffer.

## Relay contract changes (all additive)

- `POST /v1/register` accepts optional `"trigger": "<value>"`.
- `201` response adds `"authorization_expires_at": <unix seconds | null>`.
- Registering with an already-expired token returns `400` with `{"error":"registration failed","detail":"mailbox authorization expired"}` without contacting the Ark server. Same shape as before; treat as "mint a new one and retry".

## Acceptance Criteria

- With the app backgrounded, a `mailbox_auth_refresh` push results in one `POST /v1/register` with `trigger: "wake_push"` and a fresh token; the relay's `/insights/v1/summary` shows it under `auth_refresh.refreshes_after_wake`.
- Same from a terminated (not force-quit) state: cold background launch, wallet opens minimally, registration succeeds within the background window.
- Notifications disabled in app settings: no relay call, completion handler `.noData`.
- Keychain unavailable (device locked before first unlock): completes with `.failed`, no crash, no "no wallet" state written.
- A `mailbox_auth_refresh` push never triggers a full `WalletManager.refresh()` on its own.
- Existing mailbox push types (`mailbox_arkoor`, `mailbox_round_participation_completed`, ...) behave exactly as before.

## Testing

Simulate the push on a device or simulator with a payload file:

```json
{
  "aps": { "content-available": 1 },
  "type": "mailbox_auth_refresh",
  "mailbox_id": "<current wallet mailbox id>",
  "authorization_expires_at": 0
}
```

```bash
xcrun simctl push booted <bundle-id> wake.apns
```

Known limits (accepted, per Decision 4): iOS throttles silent pushes, delays them in Low Power Mode, and never launches a force-quit app for them. A longer-lived token from bark-ffi remains the more robust fix; this covers the gap until then and the long tail after it.
