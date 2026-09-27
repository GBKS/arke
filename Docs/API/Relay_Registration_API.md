# Relay Registration API

**Status:** Reference for the contract the app implements in `Shared/Services/RelayRegistrationService.swift`. Originally the implementation spec (`APNS_MAILBOX_SPEC.md`, root); reframed as a reference and moved here 2026-09-27. The relay's own source is the authority: `~/workspace/arke-apns-relay-node` (`src/`), see also `Features/Background_Execution.md` for how registration fits the background-execution design and the auth wake push.

The relay (`relay.arke.cash`) subscribes to the Ark mailbox for registered wallets and forwards mailbox messages as APNs pushes. The app registers one (mailbox, device token) pair per wallet per device.

## Endpoints

- `POST /v1/register`
- `DELETE /v1/register`
- `GET /v1/registrations?mailbox_id=...`

If `RELAY_API_TOKEN` is enabled on the server, requests carry one of `x-relay-token: <token>` or `Authorization: Bearer <token>`.

## Inputs the app supplies

- `mailbox_id`: hex string (the wallet's mailbox id, `BarkWalletFFI.mailboxIdentifier()`)
- `authorization_hex`: mailbox authorization minted by bark (`mailboxAuthorization(expirySecs:)`; the app uses 30 days since bark-ffi 0.25 — `RelayRegistrationService.mailboxAuthorizationExpirySecs`)
- `ark_addr`: Ark server URL (`http://` or `https://`)
- `device_token`: APNs token as 64-char lowercase hex
- `apns_topic`: app bundle identifier
- `trigger` (optional, added 2026-09-17): why this registration happened — `foreground`, `timer`, `background_task`, `wake_push`, `token_change`. Lowercase letters and underscores, max 32 chars; anything else is recorded as `unspecified`. The relay counts registrations per trigger.

## Register

`POST /v1/register`

```json
{
  "mailbox_id": "<UNBLINDED_ID_HEX>",
  "authorization_hex": "<MAILBOX_AUTH_HEX>",
  "ark_addr": "https://ark.example.com:3535",
  "device_token": "<64_HEX_APNS_TOKEN>",
  "apns_topic": "com.example.app",
  "trigger": "foreground"
}
```

Success: `201` with `status = "registered"` and `authorization_expires_at` (UNIX seconds, or `null`) — the expiry the relay read out of the token. The app uses it for `authExpiresAt` (fallback: the local TTL) and derives both the foreground timer and the mid-life BGTask date from it.

Registering with an already-expired token returns `400` with `{"error":"registration failed","detail":"mailbox authorization expired"}` without contacting the Ark server; treat as "mint a new one and retry".

## Unregister

`DELETE /v1/register`

```json
{
  "mailbox_id": "<UNBLINDED_ID_HEX>",
  "device_token": "<64_HEX_APNS_TOKEN>"
}
```

Success: `200` with `status = "unregistered"`. Idempotent — `removed: 0` is still success. The app calls it on wallet deletion (`unregisterDevice`, which also clears local registration state and cancels the BGTask chain) and for orphaned registrations named by an auth wake for a different mailbox (`unregisterStaleMailbox`, which touches no current-wallet state). The two must not be conflated.

## List

`GET /v1/registrations?mailbox_id=<UNBLINDED_ID_HEX>`

Success: `200` with the registration count and device-token suffixes. Used by the X-Ray relay cross-check row.

## Error handling

- `400`: validation or payload problem (including the expired-token shape above); log the response body.
- `401`: relay API token missing or invalid; fail fast with an actionable message.
- `429`: read `retry_after_seconds` (or `Retry-After`) and retry after the delay.
- `5xx` or transport failure: retry with short exponential backoff.

## When the app registers

- APNs token acquired or changed (`token_change`)
- App launch and return to foreground, gated by `needsRenewal` (registration is skipped while the current authorization is not yet due for its mid-life renewal) — `foreground`
- In-process expiry timer — `timer`
- `BGAppRefreshTask` (`cash.arke.refresh`) — `background_task`
- Relay-initiated `mailbox_auth_refresh` silent push — `wake_push`

All registration is gated on the app's `notifications_enabled` setting; users who disable notifications are never registered and receive no pushes.

## Push types the relay sends

Forwarded from the mailbox: `mailbox_round_participation_completed`, `mailbox_recovery_vtxo_ids` (silent, `content-available: 1`); `mailbox_arkoor`, `mailbox_incoming_lightning_payment`, `mailbox_lightning_send_finished` (visible alert pushes, no `content-available`). Relay-originated: `mailbox_auth_refresh` (silent). The app routes on the payload's `type` field in `AppDelegate_iOS`.
