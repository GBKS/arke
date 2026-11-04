# MCP Server

**Status:** PARKED 2026-11-01 with the shape DECIDED (table below) and the
details PROPOSED. Plan for letting an AI agent on a Mac drive the Arké
wallet through a Model Context Protocol (MCP) server, built in three
separate tracks. Track 2 starts only after desktop parity
(`Desktop_Parity.md`) is done, and this doc gets a review pass before any
Track 2 work begins. Parked so the Ark server selection work can finish.

Related: `Agent_Payments.md` exists only on the branch
`hackathon/agent-payments` (read it with `git show
hackathon/agent-payments:Docs/Features/Agent_Payments.md`); the
hackathon design it records is the seed of Track 2. `Desktop_Parity.md` is
Track 1. `../Development/Exploration_Season.md` names "programmatic send"
and the policy engine as under-the-floor pieces; Track 2 builds the first,
Track 3 the second.

## Decisions so far

| Date | Decision |
|---|---|
| 2026-11-01 | **One primary device, always.** Only one device talks to the Ark server, so the single-primary model stays. The primary can be the phone or the Mac, and the user chooses. A request raised on a secondary device is forwarded to the primary, which approves and executes. (Christoph, in chat.) |
| 2026-11-01 | **Three tracks, in order:** desktop parity → MCP-ready minimum (single payments, as in the hackathon) → MCP expansion (policy engine, allowances, more tools). Each track has its own definition of done. (Christoph, in chat.) |
| 2026-11-01 | **Transport: local link first, CloudKit later.** Track 2 ships the seed-keyed peer-to-peer link from the hackathon (option A in §Transport). The CloudKit-mirrored request queue (option B) follows as a later step for durability and reach. (Christoph, in chat.) |
| 2026-11-01 | **Approval requests may be account-shared state.** The user sees pending and past agent requests on every device signed into the same iCloud account. This is the ruling option B needs; it is the second account-shared state class after network config, and `CLAUDE.md`'s "do not generalize the account wins" rule still holds for everything else. (Christoph, in chat.) |
| 2026-11-01 | **Track 2 after parity.** Desktop parity is its own effort and completes first; the three parity items MCP depends on are not pulled forward. (Christoph, in chat.) |
| 2026-11-01 | **Hackathon design doc stays on its branch** until Track 2 starts. (Christoph, in chat.) |
| 2026-11-01 | **Server architecture as in §Server architecture:** official Swift SDK inside the app, Streamable HTTP on loopback, `.mcpb` shim for Claude Desktop. Reviewed again before work starts. (Christoph, in chat.) |
| 2026-11-01 | **The two spikes run before detailed Track 2 planning.** (Christoph, in chat.) |
| 2026-11-01 | **No hosted connector.** Arké will not run an MCP endpoint of its own on public HTTPS that relays agent requests to the user's devices, even though it would reach Claude on iPhone and the web. A server on the money path that sees invoices and agent reasons is not appropriate for a self-custodial, client-first wallet. The MCP server runs only inside the user's own app. (Christoph, in chat.) |
| 2026-10-01 | Hackathon decisions (no relay changes, no CloudKit, no QR pairing, phone stays open) were for the hackathon only and do not bind these tracks. |

Nothing is open at the decision level. Detail-level proposals (sheet of
tools, token handling, the shim) are reviewed when the doc is unparked.

## What exists today (verified 2026-11-01)

- `WalletManager` is `@MainActor @Observable`, view-free, and exposes typed
  `async throws` operations for send (Ark, onchain, Lightning invoice,
  Lightning address, LNURL, BOLT-12 offer), receive (addresses, invoices),
  balance, history, contacts, tags, refresh, boarding and exits.
- Three things keep it from being callable without the UI:
  - the open sequence (store subscription, service activation, wallet
    detection with keychain retries, primary / read-only choice) lives in
    `MainView`'s `.task`, on both platforms, not in the manager;
  - send routing, retry and pending metadata live in `SendViewModel`
    (`executeSend`, `executeWithRetry`, `PendingPaymentMetadata`), and the
    amount arrives as a `String`;
  - BIP-353 and LNURL resolution are called from the send views.
- The macOS target is sandboxed with incoming connections **off**. A
  loopback listener needs that build setting on (Xcode UI, not pbxproj).
- A separate binary cannot read the app's keychain group, sandbox container
  or bark `walletDir`, and a sandboxed app cannot spawn child processes. So
  the MCP endpoint runs **inside the ArkeDesktop process** as an HTTP server
  on loopback. Claude Code and most other clients connect to it directly;
  Claude Desktop still needs a stdio shim (§Server architecture).
- Only the primary can spend (`../Architecture/Multi_Device_Design.md`,
  capability matrix). A secondary can read balance, history, contacts and
  tags, and show addresses.
- Mobile has `remote-notification` background mode and receives CloudKit
  pushes for the SwiftData mirror; `CloudKitObserver` posts
  `.cloudKitDataDidChange` on import. The relay
  (`~/workspace/arke-apns-relay-node`) holds APNs tokens per mailbox and
  already sends auth wake pushes.

## Track 1 — Desktop parity

`Desktop_Parity.md`. The MCP tracks need from it only:

- the macOS test suite trustworthy (Tier 1 backlog item), since Track 2
  changes money paths that must be testable on the Mac;
- `MainView` lifecycle parity (foreground re-check, protected-data re-check,
  CloudKit stop on delete), so a Mac primary behaves like a phone primary;
- the Activity screen current, so agent payments are visible and attributable.

The rest of parity (exits, X-Ray, Lightning sheet, contacts polish) is
wanted for the desktop product, not for MCP.

## Track 2 — MCP-ready minimum

**Definition of done:** an agent in Claude Desktop can ask the wallet to pay
one Lightning invoice; a person approves on the primary device; the preimage
comes back to the agent. The primary may be the Mac or the phone. Every step
is testable on the Mac and device-checked on two devices.

### 2.1 Wallet bootstrap outside the view

A `WalletBootstrapper` (Shared, non-view) that owns the sequence now in both
`MainView.task` implementations: subscribe to the ubiquitous store, set the
model context, activate services, detect the wallet, choose primary or
read-only, call `initialize`. Both MainViews call it; nothing else changes.
Startup-shaped: `Launch_Sequence_Contract.md` rules 1–6 and 22 apply, full
review, adversarial pass.

### 2.2 Payment executor (programmatic send)

A typed `request → quote → confirm → execute` service in Shared, pulled out
of `SendViewModel`:

- `PaymentRequest` (already in `Shared/Helpers/PaymentRequest.swift`) in,
  `PaymentQuote` (rail, amount, fee estimate, destination summary) out;
- `execute(quote, confirmation)` where the confirmation token is minted only
  by the app's approval UI, never by the caller;
- BIP-353 and LNURL resolution move from the views into the executor;
- `SendViewModel` becomes a consumer of the executor, so the send screens
  keep working unchanged. Money path: Tier 1 review depth.

App Intents and Siri would consume the same executor later; that is the
reason to do this once, properly.

### 2.3 Request model and transport

A `PaymentApprovalRequest` with id, invoice, agent name, agent-supplied
reason (labelled unverified), created-at, state machine as in the hackathon
(`received → awaiting_approval → paying → paid | declined | refused |
failed | expired`). When the Mac **is** the primary the request never leaves
the process. When it is a secondary, the request travels to the primary over
the transport chosen in §Transport.

### 2.4 Approval UI on both platforms

One Shared approval sheet (amount and description decoded from the invoice,
reason labelled, Approve / Decline), presented on whichever device is
primary; the phone adds Face ID before paying, the Mac adds Touch ID or
password through `LocalAuthentication`. A "Pending requests" list in
Settings on both platforms, and an "Agent" origin on the resulting
transaction so Activity shows who asked.

### 2.5 A real MCP server in the app

Not the hackathon's bespoke JSON API plus script. ArkeDesktop speaks MCP
itself over Streamable HTTP on `127.0.0.1`, built on the official Swift SDK
(§Server architecture). Tools in Track 2: `request_payment`,
`get_payment_status`, and the read-only `get_balance` because every client
quickstart wants one call that cannot fail. The `http_request` tool from the
hackathon is dropped; it existed for the demo shop.

Convenience is a feature of this track, not of Track 3: a Settings page with
an on/off switch, the port and the bearer token, a "Copy config for Claude
Code / Claude Desktop / Cursor" button per client, and a one-click bundle
for Claude Desktop (§Server architecture, Connecting clients).

### 2.6 Minimum policy

Two settings, not a constant: a per-request cap in sats and a master
"Agent payments" switch. Every request requires a human approval in this
track; allowances are Track 3.

### Track 2 verification

Unit: executor decision tests (rail choice, cap, state machine). Mac: the
suite, once trustworthy. Device: Mac secondary + phone primary, Mac primary
alone, declined, expired, cap exceeded, app restarted with a pending request.
The link's key derivation is seed-touching, so the two-device check is part
of the definition of done, not optional.

## Track 3 — MCP expansion

Not planned in detail; listed so Track 2 leaves room for it.

- Policy engine (`Exploration_Season.md`): allowances per agent, per-period
  limits, counterparty rules, approvals only above a threshold. Designed once
  for agents and for the "good habits" nudges.
- Agent identities: more than one agent, each with its own token, name and
  policy.
- Read tools: history, contacts, tags, addresses, invoice creation.
  Read tools work on a secondary Mac without any forwarding.
- MCP resources (balance, recent activity as readable documents) and
  prompts (a "pay this invoice safely" template) once tools are stable.
- Stateful transport with server-sent events, so a pending approval can
  push its outcome instead of being polled.
- Durable request log, exportable like metadata.

## Server architecture (PROPOSED 2026-11-01)

### Library

Use the official **MCP Swift SDK** (`modelcontextprotocol/swift-sdk`,
maintained with Apple). Checked 2026-11-01 from its repository: current
release 0.12.1, implements the 2025-11-25 protocol revision, Swift tools
6.1, macOS 13+, products `MCP`; dependencies swift-log, swift-system,
eventsource and swift-nio. It ships `Server` with `withMethodHandler` for
`ListTools` / `CallTool`, a `Tool` type with JSON-schema `inputSchema`, and
four server transports: `StdioTransport`, `StatelessHTTPServerTransport`,
`StatefulHTTPServerTransport` and an Apple-only `NetworkTransport`.

Two facts shape the design:

- The HTTP server transports handle the protocol, **not the socket**. The
  app must own an HTTP/1.1 listener and hand requests to the transport. The
  hackathon's `AgentLoopbackServer.swift` (Network.framework, 248 lines) is
  the right size for that listener; Hummingbird would also work but adds a
  framework for one route.
- The SDK does not yet implement the 2026-07-28 protocol revision (stateless
  handshake, `server/discover`). Clients negotiate down, so this is not a
  blocker, but version pinning and a re-check at each bump belong in the
  bindings-bump routine. Community forks that track the newer revision
  exist; staying on the official package is the safer default.

The SDK is the first non-bark package on the money path. The rule from
`CLAUDE.md` applies: policy lives in the app, the SDK only transports.

### Shape inside the app

```
MCP client ── HTTP 127.0.0.1:<port> ──▶ LoopbackListener (Network.framework)
                                           │ bearer token check
                                           ▼
                                   StatelessHTTPServerTransport
                                           ▼
                                      MCP.Server
                                       tools/list, tools/call
                                           ▼
                              AgentToolRouter (Shared, @MainActor)
                               ├─ request_payment → PaymentApprovalRequest → executor (§2.2)
                               ├─ get_payment_status
                               └─ get_balance → WalletManager
```

- Stateless transport in Track 2: request and response per call, no
  sessions, no SSE. The pending-approval wait is a `get_payment_status`
  poll, as the hackathon did, with a short server-side wait so a single
  call usually returns the outcome. Stateful transport is a Track 3 upgrade.
- Loopback only (`requiredInterfaceType = .loopback`), bearer token minted
  once with `SecRandomCopyBytes`, stored in the keychain, shown in
  Settings. Every request without it is `401`, including `tools/list`.
- The sandbox's "Incoming Connections (Server)" setting goes on (Xcode UI).
- The server starts only when the wallet is open and the switch is on;
  it stops on wallet delete and on app quit. Nothing MCP runs before the
  bark handle is open.

### Connecting clients

| Client | How it reaches a local HTTP server | What Arké offers |
|---|---|---|
| Claude Code | native: `claude mcp add --transport http arke http://127.0.0.1:<port>/mcp --header "Authorization: Bearer …"` | "Copy command" button |
| Cursor, Windsurf, VS Code, Codex and others | native HTTP entries in their MCP config | "Copy JSON" button |
| Claude Desktop | **stdio only** for local servers; the Connectors UI refuses `http://` and `localhost` because connectors are reached from Anthropic's servers (issue closed "not planned" 2026-05-12). A stdio shim is required. | an `.mcpb` bundle (below) |

The Claude Desktop path, in order of convenience:

1. **`.mcpb` bundle** (MCP Bundles, formerly Desktop Extensions; the format
   now lives in the MCP project and supports binary servers). Arké ships
   `Arke.mcpb` containing a small stdio-to-HTTP shim plus a manifest; the
   user double-clicks it, Claude Desktop installs it, the manifest's
   `user_config` asks for the token once. The shim is a tiny Swift
   executable built with the same SDK (`StdioTransport` on one side,
   `HTTPClientTransport` on the other), signed and notarized with the app,
   universal binary. **Assumed, needs a spike:** that a notarized Swift
   binary inside an `.mcpb` launches cleanly from Claude Desktop on a Mac
   with Gatekeeper defaults.
2. **Fallback:** a "Copy Claude Desktop config" button that emits a
   `mcpServers` entry using `npx mcp-remote` or the DePasquale
   `mcp-http-stdio-bridge`. Requires Node on the user's Mac; fine for
   developers, not for the product.

The shim is **not** the hackathon script: it carries no tool knowledge, it
only forwards. Tool definitions live in one place, the app.

### User experience, honestly

What the person does, per client, with the design above:

| Client | Steps after flipping the switch in Arké Settings |
|---|---|
| Claude Code | paste one command |
| Cursor and other HTTP-native clients | paste one JSON snippet |
| Claude Desktop | download `Arke.mcpb`, double-click, click Install |
| Claude on iPhone, claude.ai in a browser | **nothing works**: these only reach connectors over public HTTPS |

Refinement so the token never appears: the copy buttons embed it, and the
`.mcpb` shim reads port and token from a file the app writes into its own
container (the shim runs unsandboxed under Claude Desktop and can read
`~/Library/Containers/GBKS.Arke/…`). Then no client setup involves typing
a secret. **Assumed, part of spike 2.**

Writing Claude Desktop's config file from the app is not a shortcut: it
sits outside the sandbox, needs a user-granted file access, and Anthropic
has changed what that file accepts more than once. The bundle is the
sanctioned path.

**Considered and rejected (DECIDED 2026-11-01): a hosted connector.** An
Arké-run MCP endpoint on public HTTPS would reach Claude on iPhone and the
web and skip the Mac entirely, but it puts an Arké server on the money path
that sees invoices and agent reasons. Not appropriate for a self-custodial,
client-first wallet. The consequence is accepted: Claude on iPhone and
claude.ai cannot talk to Arké; agents reach the wallet only through an app
running on a device the user owns. If Anthropic later lets Claude clients
reach a local or LAN endpoint directly, that path reopens without any
server of ours.

### Spikes before Track 2 is planned in detail

1. Add the SDK to a scratch target; serve `tools/list` and `get_balance`
   through `StatelessHTTPServerTransport` behind a Network.framework
   listener; connect from Claude Code. Half a day's worth of steps: package
   add, listener, two handlers, one `claude mcp add`.
2. Build the stdio shim as a second executable, pack it with `mcpb pack`,
   install into Claude Desktop, call `get_balance`.
3. Check App Store review implications of the incoming-connections
   entitlement and of a bundled command-line helper, if the Mac app is
   ever meant for the App Store rather than Developer ID.

## Transport between secondary and primary (DECIDED 2026-11-01: A first, then B)

The question is how a request raised on a secondary reaches the primary and
how the answer comes back. The local case (Mac is primary) needs none.
Ruling: Track 2 ships **A**, the local link, because it exists and keeps
every byte on the user's devices; **B** follows for durability and for
requests to reach a phone that is not in the room. The table is kept for
the record and for the B step.

What choosing A first means for Track 2:

- The link key is derived from the seed (`HKDF(seed, "arke-agent-link-v1")`),
  so the transport is **seed-touching, read-only**. Per `CLAUDE.md`, nothing
  about it is done on green tests; it needs the two-device check.
- Both apps open and nearby, phone awake. The hackathon's idle-timer trick
  stays until B lands; the approval sheet says so.
- Requests live in memory on the Mac until B; the Mac shows "waiting for
  iPhone" and the agent gets `link_unavailable` when no primary is reachable.
- Design `PaymentApprovalRequest` as a value type with no transport fields,
  so B can persist the same type as a `@Model` without a rename.

| Option | How | For | Against |
|---|---|---|---|
| **A. Local link** (hackathon) | Network.framework peer-to-peer, TLS with a seed-derived pre-shared key, Bonjour name derived from the seed | No server, works offline and off venue Wi‑Fi; built and demoed; key derivation is read-only seed use | Both apps open and nearby; phone awake with the screen on; no wake path; requests lost on restart |
| **B. iCloud (CloudKit)** | A `PaymentApprovalRequest` row in the private database, mirrored by SwiftData like tags and contacts; the primary's existing CloudKit push wakes the import, the app observes `.cloudKitDataDidChange` and shows the sheet | Uses infrastructure every device already runs; works anywhere; durable across restarts; encrypted at rest by Apple | Latency is seconds to tens of seconds (**assumed**, not measured); a `@Model` is permanent once deployed to Production; payment data is device-local by policy today, so a request queue is a new account-shared state class and needs a ruling; CloudKit pushes do not wake a suspended phone reliably (**assumed**) |
| **C. Relay** | The Mac posts the request to the APNs relay, the relay pushes to the primary's mailbox token, the phone fetches and answers through the relay | Real wake path; low latency; relay already knows tokens and sends auth wakes | Relay code changes and a new API; **the relay sees the invoice and the reason, which the 2026-11-01 no-hosted-connector ruling argues against**; `RelayRegistrationService` is iOS-only today, so the Mac has no relay identity yet |
| **D. B + C wake** | Request and answer in CloudKit, relay push only as a wake signal carrying the request id, no payload | Durable and wakeable; the relay sees only an opaque id | Two systems to keep consistent |

The 2026-11-01 recommendation was B first; the ruling went A first because
it is built and demoed, and B comes as a later step. Before the B step:
measure CloudKit round-trip latency between a Mac and a phone with the app
foregrounded and backgrounded, and name the `@Model` carefully, since a
deployed field is permanent (`CLAUDE.md`, SwiftData section). D is the
wake path if the phone-asleep case matters then.

## Hackathon branch (recommendation)

Do **not** rebase the branch. Reuse it piecemeal when Track 2 starts.

Facts: one commit, cut from `366637a` on 2026-10-01; main is 104 commits
ahead, including the Bark 0.26 bump, the send fee cluster, the "Pay from"
work and large catalog churn. The branch's new files still apply to main
cleanly (`git apply --check` on 2026-11-01), and the `WalletManager`
members it calls (`payLightningInvoice`, `isReadOnlyMode`,
`loadMnemonic`) still exist. Its modified files (`.xcstrings`, Info.plist,
both `SettingsView`s, the two app entry points, `project.pbxproj`) conflict
or must be redone in the Xcode UI.

Reuse by value:

| Keep as is | Keep as reference, rewrite | Drop |
|---|---|---|
| `Docs/Features/Agent_Payments.md` (bring to main as the Track 2 design record) | `AgentLinkProtocol.swift`, `AgentInvoice.swift` if option A is chosen; else only the invoice decoder | `http_request` tool |
| the Claude Desktop setup steps from `Tools/agent-mcp/README.md` | `AgentLoopbackServer.swift` becomes the HTTP listener in front of the SDK transport (add the token) | `Tools/agent-mcp/arke-agent-mcp.mjs` (the app speaks MCP itself now; a tool-less shim replaces it) |
| the request state machine and message vocabulary | phone and Mac services, re-based on the executor (§2.2) and the chosen transport | in-memory request store |
| | `AgentPaymentsPhoneViews` / `DesktopViews` → one Shared approval sheet (R1 in `../Development/Platform_Porting_Rules.md`) | |

Keep the branch and the draft PR as they are; they are the record of what
won the prize. Close the PR when Track 2 lands.

## When this doc is unparked

1. Re-read §Server architecture against the then-current Swift SDK release
   and Claude Desktop's local-server story; both moved twice in 2026.
2. Run the two spikes.
3. Re-check `WalletManager` and `SendViewModel` for drift from the
   "What exists today" section.
4. Then plan Track 2 in detail: executor, bootstrapper, request model,
   approval sheet, link, server, settings page, bundle.
