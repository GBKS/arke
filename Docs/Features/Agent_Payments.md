# Agent Payments

An AI agent (Claude Desktop) asks Arké Desktop to pay a Lightning invoice. The
desktop forwards the request over a direct local link to Arké Mobile, which is
the primary device and the only one that can spend. The person approves on the
phone, the phone pays, and the preimage travels back to the agent as proof of
payment.

**Status: PARKED (2026-10-06).** Built for the BTC++ Berlin hackathon and
demoed end to end on devices (Claude Desktop → Mac → phone approval → paid
→ treat delivered); the project won 2nd prize. The work lives on the branch
`hackathon/agent-payments` as a draft PR and is not merged into main. The
demo shop runs at https://doghouse.arke.cash (its own repo, `arke-doghouse`).
Before reviving it, read §12 and §13. §2 lists what Christoph decided for the
hackathon.

---

## 1. Why this shape

- **The agent never holds spending authority.** Only the primary device can
  spend (`../Architecture/Multi_Device_Design.md`, capability matrix). The
  agent can only *ask*; a human approves on a separate device.
- **It answers the prompt-injection question.** A malicious page can make the
  agent request a payment, but the phone shows the amount and description
  decoded from the invoice itself, and the agent's stated reason is labelled as
  unverified.
- **The preimage is the proof.** The agent doesn't have to trust the app's
  word; the preimage proves the invoice was paid. Bark already returns it:
  `LightningSendStatus.paid(paymentHash, preimage)`
  (`Shared/Data/BarkWalletFFI/BarkWalletFFI+Lightning.swift`).

## 2. Decisions (Christoph, 2026-10-01)

| Decision | Consequence |
|---|---|
| No relay changes | No push; the relay repo is untouched |
| No CloudKit | No records, zones, subscriptions or schema changes, so nothing permanent in iCloud |
| No QR pairing | The link key is derived from the seed both devices already hold (§4.2) |
| The phone app being open is fine | No wake-up mechanism; the phone keeps the screen awake while the feature is on |
| One isolated PR | Reverting the PR removes the feature completely (§9) |
| Demo: the Byte treat shop | Built and live (§10). Lives in its own repo; nothing in Arké depends on it beyond the demo. **Don't build or change it from this repo** |
| Ordering goes through the MCP script's `http_request` tool (2026-10-01, replaces "ordering through Claude's web fetch") | Claude's web fetch refused the order links in `llms.txt` (it only opens links from searches or the user's own messages), and its code sandbox can't reach the shop. The script runs on the Mac with normal network access (§6.1) |

## 3. Architecture

```
Claude Desktop
   │  MCP (stdio)
   ▼
arke-agent-mcp  (small script, outside the app) ── http_request ──▶ doghouse.arke.cash
   │                                               (reads llms.txt, orders, gets an invoice)
   │  HTTP on 127.0.0.1
   ▼
Arké Desktop ── shows the pending request
   ║  local link: Network.framework, peer-to-peer Wi‑Fi, TLS with a seed-derived PSK
   ▼
Arké Mobile (primary, app open) ── approval sheet → Face ID → payLightningInvoice
   ║
   ╚══ status + preimage back the same way ══▶ the MCP tool result
```

### 3.1 Why a separate MCP script (proposed)

Claude Desktop starts MCP servers as stdio subprocesses; it cannot attach to an
already-running app. Two ways to bridge that:

- **(Chosen) A small stdio MCP script** that turns tool calls into HTTP calls
  to the app's loopback API. The app then speaks plain JSON and has no MCP code
  or new package dependency. Built as `Tools/agent-mcp/arke-agent-mcp.mjs`:
  plain Node 18+, no npm dependencies (MCP over stdio is newline-delimited
  JSON-RPC). Setup in `Tools/agent-mcp/README.md`.
- **The app speaks MCP itself** over Streamable HTTP on loopback, with
  `mcp-remote` as the stdio bridge. That's fewer moving parts at run time, but
  the app has to implement MCP's JSON-RPC, session and streaming handling.

## 4. The local link

### 4.1 Transport

- Network.framework, with `includePeerToPeer = true`, so it works even when
  venue Wi‑Fi blocks devices from seeing each other, or with no Wi‑Fi at all.
- **The Mac listens; the phone connects.** The Mac already needs incoming
  connections for the loopback API.
- Messages are newline-delimited JSON (§5); JSON encoding escapes newlines
  inside strings, so no framer is needed. The TLS-PSK setup follows Apple's
  "Building a custom peer-to-peer protocol" sample.
- Keep it in **new files**, separate from `ProximityExchangeManager`
  (MultipeerConnectivity, `_arkepayment`), so the PR stays isolated.

### 4.2 Trust without pairing

- **Link key:** `HKDF<SHA256>(BIP39 seed bytes, info: "arke-agent-link-v1")`,
  computed independently on both devices and used as the TLS pre-shared key.
  Only devices holding this wallet's seed can complete the handshake. HKDF is
  one-way, so the key doesn't reveal the seed, and the fixed label keeps it
  separate from bark's keys.
- **Use seed bytes, not the mnemonic string,** so different whitespace or
  Unicode normalization can't produce different keys on the two devices.
- **Discovery name:** the Bonjour instance name is `arke-` plus 4 bytes of
  `HKDF(seed, info: "arke-agent-discovery-v1")` in hex, so the phone only sees
  Macs running the same wallet. A separate label keeps it independent of the
  PSK. (Built this way instead of from the wallet hash, so discovery doesn't
  depend on iCloud key-value storage having synced.)
- **Roles:** after the handshake, both sides exchange `hello` (§5). The phone
  refuses requests unless it is currently primary. The Mac shows the phone's
  name and role from the device registry. The registry is for display and role
  checks only; the PSK is what authenticates.

### 4.3 Seed handling (seed-touching code, read-only)

- Read through `SecurityService.loadMnemonic()`, the path the app already uses.
- Keep the derived key in memory only. Never log it, persist it or put it in
  the X-Ray journal.
- **Secondary without the seed:** a Mac that is a read-only secondary (seed not
  yet delivered by iCloud Keychain) can't derive the key. It shows "This Mac
  doesn't have the recovery phrase yet", and the API returns
  `link_unavailable`. Before the demo, confirm the Mac has the seed.

### 4.4 Staying alive

- The phone disables auto-lock (`isIdleTimerDisabled`) while the feature is on,
  because a locked screen suspends the app and drops the link.
- Reconnect on `scenePhase == .active` and when the Mac's listener comes back.
- Both apps show a link status indicator, e.g. "Connected: iPhone (primary)".

## 5. Messages over the link

Every message is `{ "type": ..., "v": 1, ... }`.

| Type | Direction | Fields |
|---|---|---|
| `hello` | both | `deviceId`, `deviceName`, `role` (primary/secondary), `network`, `appVersion` |
| `pay_request` | Mac → phone | `id` (UUID), `invoice`, `reason` (agent-supplied), `agent` (e.g. "Claude"), `createdAt` |
| `pay_status` | phone → Mac | `id`, `state`, plus `preimage` / `paymentHash` (hex) / `feeSats` when paid, `error` when refused or failed |
| `cancel` | Mac → phone | `id` (the agent gave up, or the request timed out) |

`state` is one of: `received`, `awaiting_approval`, `paying`, `paid`,
`declined` (the person said no), `refused` (an automatic check in §7 failed;
`error` says which), `failed`, `expired`.

**Rules:**
- **A different network in `hello` drops the link.** Both sides must be signet.
- **Each `id` is paid at most once.** The phone keeps the outcome of every
  handled `id` for the session. If the same `pay_request` arrives again (e.g.
  re-sent after a reconnect), the phone answers with the stored `pay_status`
  and doesn't show the sheet again.
- The Mac re-sends pending requests after a reconnect. Thanks to the rule
  above, that's safe.

## 6. Agent side

### 6.1 MCP tools (served by the script)

| Tool | Input | Result |
|---|---|---|
| `request_payment` | `invoice` (bolt11), `reason` | Waits up to about 45 s; returns `paid` with `preimage` + `paymentHash` (both hex), `declined`, `refused` + reason, `failed`, or `pending` + `request_id` |
| `get_payment_status` | `request_id` | Current state, with the same fields as above |
| `http_request` | `url`, optional `method` (GET/POST), optional JSON `body` | Status, content type and body (max 100 KB). For reading `llms.txt` and placing orders |

`http_request` only allows public https URLs. It resolves the host and refuses
loopback, private, link-local and multicast addresses, and checks again on
every redirect (max 3). So a prompt injection can't point it at the Mac's own
loopback API or the local network.

Errors return straight away with plain wording so Claude can explain them:
`phone_not_connected` ("Open Arké on your phone"), `link_unavailable`,
`mainnet_refused`, `invalid_invoice`, `over_cap` ("Over the 15,000-sat limit
set on the phone").

### 6.2 The app's loopback API (Arké Desktop)

Port 48211 (`AgentPayments.loopbackPort`):
- `GET /agent/status` → `{link, phone?, role?, message?}`
- `POST /agent/payments` with `{invoice, reason, agent?}` → `{id, state, amountSats, description}`
- `GET /agent/payments/{id}` → `{id, state, preimage?, paymentHash?, feeSats?, error?, message?}`, with `?wait=45` for long-polling (max 120)
- Loopback interface only. Every request must send an `X-Arke-Agent` header,
  otherwise 403. A custom header forces a CORS preflight that the server never
  answers, so a web page in a browser can't submit requests. Any local process
  could still call it, but it can only *request*; the phone approves.

## 7. Phone: checks and approval

Automatic checks before showing the sheet. Any failure answers `refused` with
the matching error, without showing the sheet:
- This device is primary.
- The wallet's network is not mainnet (hard check in code, not a setting).
- The invoice decodes and its network matches the wallet's (signet invoices
  start with `lntbs`).
- It hasn't expired and has an amount (no zero-amount invoices).
- The amount is at or below the demo cap: 15,000 sats (`AgentPayments.demoCapSats`;
  Christoph raised it from 10,000 on 2026-10-02). Every item on the shop's menu
  is now under the cap, so nothing there is refused automatically.

The sheet shows:
- The amount, with fiat via `FiatAmountText`.
- The **description** decoded from the invoice, e.g. `Byte treat: kibble`.
- The **payee** only as a shortened node pubkey, or not at all. For Ark
  Lightning receives the invoice's payee is the Ark server's Lightning node,
  not the shop, so never label it with the shop's name.
- The agent's reason in a separate "The agent says" box, marked as unverified.

The review screen stays plain (no video) so the attention stays on what's
being approved. Only after a successful payment does the sheet switch to the
thumbs-up success screen used elsewhere: a `ReactionVideoPair` thumbs-up
video, "Payment Sent", the amount and description, a success haptic and the
gold Done button (Christoph, 2026-10-02).

Then Approve (Face ID) or Decline. Paying goes through
`WalletManager.payLightningInvoice(invoice:amountSats:)`, so the payment shows
up as an ordinary transaction. `.paid` maps to `paid` with the preimage and
payment hash; any other result or a thrown error maps to `failed` with the
error text.

**Activity note (Christoph, 2026-10-02: invoice description only).** Just
before paying, the phone inserts a `PendingPaymentMetadata` row with the
invoice's payment hash, amount and description as the note, exactly like the
send screen (`Send_Metadata.md`). When the movement sync upserts the
transaction, `TransactionService` matches the row by payment hash and copies
the note, e.g. `Byte treat: kibble`, so it shows in the activity list on both
devices. The agent's reason is never stored, since it's unverified text.

## 8. Desktop UI (minimal)

- A link status indicator.
- A pending-request card: amount, description, the agent's reason, and a
  "Waiting for approval on iPhone" state that updates to paid / declined /
  refused / failed.
- No history screen. The paid transaction already appears in Activity once
  sync catches up.

## 9. Isolation and revert

The feature is behind an **"Agent payments (experimental)" toggle, off by
default, on both apps**. Nothing listens or advertises unless it's on.

Reverting the PR removes:
- New Swift files:
  - `Shared/Services/AgentPayments/AgentLinkProtocol.swift`: constants, wire
    format, seed-derived key, TLS-PSK parameters, message connection.
  - `Shared/Services/AgentPayments/AgentInvoice.swift`: BOLT11 decoding for the
    checks (network incl. `lntbs` → signet, amount, description, hash, expiry).
  - `ArkeDesktop/AgentPayments/`: `AgentPaymentsMacService` (listener +
    request store), `AgentLoopbackServer`, `AgentPaymentsDesktopViews` (host
    modifier, request card, settings toggle).
  - `ArkeMobile/AgentPayments/`: `AgentPaymentsPhoneService` (browser,
    checks, approve/pay, at-most-once), `AgentPaymentsPhoneViews` (host
    modifier, approval sheet, settings toggle).
- Hook-in points, one line each: `.agentPaymentsDesktopHost()` in
  `ArkeDesktop.swift`, `.agentPaymentsPhoneHost()` in `ArkeMobile.swift`, and
  the toggle rows in both Experimental settings sections.
- `ArkeMobile/Info.plist`: `_arkeagent._tcp` under `NSBonjourServices`, and
  `NSFaceIDUsageDescription` (the app had none, so Face ID wouldn't have been
  offered). `NSLocalNetworkUsageDescription` already exists; its wording
  ("nearby users") is fine for the demo.
- Desktop sandbox: **Incoming Connections (Server)** from NO to YES
  (`ENABLE_INCOMING_NETWORK_CONNECTIONS`). Christoph sets this in Signing &
  Capabilities; no hand edits to `project.pbxproj`. The desktop likely also
  needs `NSBonjourServices` and `NSLocalNetworkUsageDescription`, because macOS
  has local network privacy too. Confirm during the link test (§11, step 1).
- `Tools/agent-mcp/` (the MCP script).

**Outside the repo:** the local `claude_desktop_config.json` entry, and the
shop (§10). Arké doesn't change any iCloud, relay or server state, and adds no
SwiftData models.

## 10. Demo: the Byte treat shop (live)

https://doghouse.arke.cash shows Byte, second.tech's mascot. Agents read
https://doghouse.arke.cash/llms.txt, order a treat, and get a Lightning
invoice. Once it's paid, the treat drops in front of Byte on the page. Built
in its own repo, `arke-doghouse`, on one DigitalOcean droplet. Tested end to
end: Claude Desktop ordered and returned an invoice, it was paid by hand in
Arké, and the treat appeared.

### 10.1 Why the shop needs an always-on wallet

From bark's source (`~/workspace/bark`, 2026-09-30): creating an invoice
doesn't wait for payment (`bolt11_invoice` in `bark/src/lightning/receive.rs`).
When the invoice is paid, the Ark server notifies the receiving wallet through
its mailbox, and the wallet must be online to call
`try_claim_lightning_receive` (`bark/src/mailbox.rs`). Claiming reveals the
preimage, and only then does the payer's payment finish. So the shop runs
`barkd`, which claims automatically. If the shop wallet hasn't been funded,
the claim can fail and the payment hangs on the phone.

### 10.2 How Claude orders

Through the MCP script's `http_request` tool: Claude reads `llms.txt`, then
sends `POST /api/orders` with `{"item": "kibble"}`. Each order returns a
fresh `invoice` and a `statusUrl`.

Claude's built-in web fetch doesn't work for this: it can't POST, and it
refused the GET order links listed in `llms.txt`, because it only opens links
from search results or the user's own messages. Its code sandbox can't reach
the shop either. The GET order links stay in `llms.txt` as a fallback for
other agents.

- **The `orderId` is the invoice's payment hash**, so
  `sha256(preimage) == orderId`. `llms.txt` tells the agent this, so Claude can
  check its own proof.

### 10.3 What the invoices look like

- **Network:** signet, prefix `lntbs`, issued through the Ark server Arké also
  uses, https://ark.signet.2nd.dev.
- **Description:** always `Byte treat: <item>`.
- **Payee:** the Ark server's Lightning node, not the shop (§7).
- **Amount:** always set.
- **Expiry:** 2 days, set by the Ark server, so "expired" won't come up in a
  demo. To test the expiry check, use an old or hand-made invoice.

| Item | Sats | Notes |
|---|---|---|
| `bone` | 1,000 | |
| `kibble` | 2,100 | |
| `squeaky-toy` | 5,000 | |
| `steak` | 12,000 | Under the 15,000-sat cap, so it reaches the approval sheet |

### 10.4 Test invoices while building (no Claude needed)

```sh
curl -s 'https://doghouse.arke.cash/api/orders/new?item=bone' | jq -r .invoice
curl -s https://doghouse.arke.cash/api/orders/<orderId> | jq .status   # awaiting_payment | delivered | expired
```

Each order call creates a fresh invoice. Keep https://doghouse.arke.cash open
to watch deliveries.

### 10.5 On stage

1. **Layout:** three panels: Claude Desktop, the Byte page, and the phone
   mirrored (QuickTime). In Claude Desktop, make sure the `arke` MCP server
   is on, and turn off any browser MCP (e.g. Puppeteer) so Claude doesn't
   reach for it.
2. **Prompt:** "Byte looks hungry. He lives at https://doghouse.arke.cash.
   Read https://doghouse.arke.cash/llms.txt and buy him something under 3,000
   sats." Claude reads the menu, picks the bone or the kibble, orders with
   `http_request`, then calls `request_payment` with the invoice and a reason.
3. The Mac shows the request card and the phone shows the sheet. Face ID →
   paid → the treat drops on the page. Claude fetches the order's `statusUrl`
   and reports `delivered`.
4. **The decline:** "Now get him the steak." The steak (12,000 sats) is
   under the 15,000-sat cap, so it reaches the sheet; tap Decline ("Byte
   doesn't need a steak") and Claude explains it was declined.
5. **Pitch points:** keys never leave the phone, approval that resists prompt
   injection, the preimage as proof. Next steps: spending allowances /
   per-agent budgets, and Nostr Wallet Connect (NIP-47) for interoperability.

**Today's stopgap (works now):** without the Arké side, ask Claude to give you
the invoice, pay it by hand in Arké, then say "Paid. Check whether Byte got
it."

## 11. Build order

| # | Step | Status / done when |
|---|---|---|
| 0 | Signet Lightning test: pay a shop invoice with the normal Arké send flow | ✅ Done: settled, treat delivered |
| 1 | **Link test (riskiest):** seed-derived PSK, Mac listener, phone connects, `hello` both ways | 🔨 Built, compiles. Device check: both toggles say "Connected" |
| 2 | Message framing + `pay_request` / `pay_status` / `cancel`, at-most-once rule | 🔨 Built. Device check: re-sending after a reconnect doesn't show the sheet again |
| 3 | Phone checks (§7) + approval sheet + pay | 🔨 Built. Device check: a shop invoice is paid; the steak can be declined |
| 4 | Desktop loopback API + pending card | 🔨 Built. Device check: `curl` round trip (`Tools/agent-mcp/README.md`) returns a preimage whose sha256 equals the `orderId` |
| 5 | MCP script + Claude Desktop config | 🔨 Built; stdio handshake and tool list checked locally. Device check: Claude completes `request_payment` |
| 6 | Byte shop (§10) | ✅ Done: live at doghouse.arke.cash |
| 7 | Ordering from Claude Desktop | 🔨 `http_request` built; reading `llms.txt` and the private-address refusals checked locally (no order placed). Web fetch and the GET order links proved unreliable (§10.2). Device check: Claude orders with `http_request` |
| 8 | End-to-end run of §10.5, then rehearsal: app switch / reconnect, phone not connected, decline the steak, expired invoice, airplane-mode Wi‑Fi | Every failure gives a clear message to Claude |

**Fallback if step 1 slips:** a debug path where the Mac pays directly, shown
honestly as "single-device mode". The demo still works; only the approval on
the phone is missing.

## 12. Open questions

- MCP script vs MCP inside the app (§3.1). Recommended: the script.
- Whether to add a bearer token to the loopback API (§6.2).
- The exact Claude Desktop tool-call timeout. The 45 s wait plus
  `get_payment_status` is designed to work whatever it turns out to be.

## 13. Reviving

Things to know before picking this back up:

- **Rebase first.** The branch was cut from `366637a` (2026-10-01). The two
  `.xcstrings` files carry build-extraction churn; on conflict, take main's
  version and rebuild in Xcode so the agent strings are re-extracted.
- **Project setting:** the branch sets the Mac's App Sandbox "Incoming
  Connections (Server)" to YES (`ENABLE_INCOMING_NETWORK_CONNECTIONS`). It's
  needed for the loopback API and the link listener.
- **Hackathon shortcuts to revisit before shipping:**
  - The 15,000-sat cap is a constant, not a setting (§7).
  - The loopback API trusts any local process that sends the `X-Arke-Agent`
    header (§6.2).
  - Requests live only in memory; nothing survives an app restart.
  - The phone has to stay open with the screen awake (§4.4); a real version
    needs a wake-up path, which the hackathon ruled out (§2).
  - New strings have English defaults only; no translations.
- **The shop** (`arke-doghouse`, doghouse.arke.cash) is a separate repo and
  droplet; it may no longer be running.
