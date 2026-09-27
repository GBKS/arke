# Swift App -> Mailbox Relay Registration

## Goal

Implement iOS-side relay registration so the app can receive APNs notifications for Ark mailbox updates.

## Context

- Relay server is already deployed and reachable (relay.arke.cash).
- Relay API endpoints:
  - `POST /v1/register`
  - `DELETE /v1/register`
  - `GET /v1/registrations?mailbox_id=...`
- If `RELAY_API_TOKEN` is enabled on server, requests must include one of:
  - `x-relay-token: <token>`
  - `Authorization: Bearer <token>`

## Required Inputs From App

- `mailbox_id`: hex string (wallet mailbox id)
- `authorization_hex`: short-lived mailbox authorization hex
- `ark_addr`: Ark server URL (`http://` or `https://`)
- `device_token`: APNs token as 64-char lowercase hex
- `apns_topic`: app bundle identifier

## Work Items

1. Add push permission + APNs token handling.
2. Convert APNs `Data` token to lowercase hex string.
3. Create `RelayRegistrationService` with async functions:
   - `registerDevice(...)`
   - `unregisterDevice(...)`
   - `listRegistrations(mailboxId:)`
4. Add auth header support (both custom header and Bearer are acceptable).
5. Re-register when either changes:
   - APNs token changes
   - wallet emits fresh `authorization_hex`
6. On logout/account removal, call unregister.
7. Add minimal retry/backoff for transient network errors and HTTP `429`.

## HTTP Contract

### Register

- Method: `POST`
- Path: `/v1/register`
- Body:

```json
{
  "mailbox_id": "<UNBLINDED_ID_HEX>",
  "authorization_hex": "<MAILBOX_AUTH_HEX>",
  "ark_addr": "https://ark.example.com:3535",
  "device_token": "<64_HEX_APNS_TOKEN>",
  "apns_topic": "com.example.app"
}
```

- Expected success: `201` with JSON containing `status = "registered"`.

### Unregister

- Method: `DELETE`
- Path: `/v1/register`
- Body:

```json
{
  "mailbox_id": "<UNBLINDED_ID_HEX>",
  "device_token": "<64_HEX_APNS_TOKEN>"
}
```

- Expected success: `200` with JSON containing `status = "unregistered"`.

### List

- Method: `GET`
- Path: `/v1/registrations?mailbox_id=<UNBLINDED_ID_HEX>`
- Expected success: `200` with registration count and token suffixes.

## Error Handling Requirements

- `400`: treat as validation or auth payload issue; log response body.
- `401`: relay API token missing/invalid; fail fast and surface actionable message.
- `429`: read `retry_after_seconds` (or `Retry-After`) and retry once delay has elapsed.
- `5xx` or transport failures: retry with exponential backoff (short cap).

## Suggested Swift Types

```swift
struct RelayRegisterRequest: Codable {
    let mailbox_id: String
    let authorization_hex: String
    let ark_addr: String
    let device_token: String
    let apns_topic: String
}

struct RelayUnregisterRequest: Codable {
    let mailbox_id: String
    let device_token: String
}
```

## Acceptance Criteria

- Fresh install path works end-to-end:
  - APNs permission granted
  - token acquired
  - registration returns `201`
- Token refresh path works:
  - new token triggers re-register
- Authorization refresh path works:
  - new `authorization_hex` triggers re-register
- Logout path works:
  - unregister returns `200`
- Invalid relay token path is visible and diagnosable (`401`).

## Deliverables For This Task

- A small, testable `RelayRegistrationService` implementation.
- Integration points in app lifecycle (launch, foreground refresh, logout).
- Basic logging for request id/status/error body (without leaking sensitive secrets).
