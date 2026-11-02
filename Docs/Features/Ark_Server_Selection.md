# Ark Server Selection

**Status:** PROPOSED 2026-10-29, first rulings the same day (see §8). Target:
built within days, not a train-length item. No code has been written.

Rulings so far (DECIDED 2026-10-29): no server switching for existing
wallets, not now and not as a later entry; Esplora field shown and
prefilled; `.testnet` preset dropped; desktop mockup folder stays until
desktop is unparked; servers are CoinOS (URL pending) and Zappin
(`ark.zappin.online`, verified §3). Probe shape, `createWithoutServer: false`
everywhere, and the relay allowlist by name were DECIDED the same day as
recommended (§8). CoinOS is unreachable for native gRPC clients until its
Cloudflare zone enables gRPC (§3).

## 1. The ask

Two new Ark servers exist in the ecosystem. Christoph wants users to be able
to connect to them. The cover screen's top-left button (today a one-tap
mainnet/signet toggle) would open a sheet instead, offering Second mainnet,
Second signet, and a custom server.

## 2. What exists today

Claims are labelled **verified** (read in the file or at the tag),
**derived**, or **assumed**.

### 2.1 The toggle and where it becomes a config (verified)

- `FirstUseView_iOS` has a glass button with the `testtube.2` icon. It flips
  `@Binding var isMainnet`, posts a VoiceOver announcement, and nothing else.
  The binding is `@State private var isMainnet = true` in `OnboardingFlow_iOS`.
- `isMainnet` also drives the cover video (`coffee-shop-chat-2` vs
  `experimenter-small`), the "You will create a test wallet" caption, the
  intro video set (`IntroVideoLibrary.videos(isMainnet:)`), and is passed to
  `CreateWalletView_iOS` and `ImportWalletView_iOS`.
- The bool becomes a `NetworkConfig` only at the create or import call:
  `isMainnet ? NetworkConfig.mainnet : NetworkConfig.signet`, in both views.
- `OnboardingState.usagePattern` and `.selectServer` still exist in the enum
  but render placeholder text; the desktop `ServerSelectionView` mockup
  (Second / Kinto / Bodega, invented fee models) is not wired anywhere and
  does not use bark's `ArkInfo`.

### 2.2 The model (verified)

`NetworkConfig` (`Shared/Data/NetworkConfig.swift`) is a `Codable` struct:
`id`, `name`, `esploraURL`, `arkServerURL`, `arkServerAccessToken`,
`isMainnet`, `networkType`. Presets:

| Preset | id | Ark server | Esplora |
|---|---|---|---|
| `.mainnet` | `mainnet` | `ark.second.tech` | `mempool.second.tech/api` |
| `.signet` | `signet` | `ark.signet.2nd.dev` | `esplora.signet.2nd.dev` |
| `.testnet` | `testnet` | `none_available` | `none_available` |

`NetworkConfig.custom(...)` exists but is unusable as written: it sets
`networkType: "custom"`, which `BarkWalletFFI.convertToFFINetwork` rejects,
so `BarkWalletFFI.init?` returns nil. The chain and the server identity are
one field today. That is the root modelling problem.

### 2.3 Persistence and multi-device (verified)

- `NetworkConfigPersistence` stores **only the id** under
  `com.arke.wallet.networkConfigId`, in UserDefaults (sync) and iCloud KVS
  (detached task). `findConfig(byId:)` resolves only the three presets.
  `load()` falls back to `.mainnet` for an unknown id;
  `reconciliation(...)` returns `.noUsableConfig` for one;
  `syncFromiCloud()` ignores one with a warning.
- Launch_Sequence_Contract rule 22: every open reconciles against the
  account first, nothing reconciles after. Network config is the one
  account-authoritative state class (playbook S2). `SharedStateWipeCoverage`
  lists the KVS key as `.fullWipeOnly`.
- `WalletManager.createWallet` calls `NetworkConfigPersistence.save(config)`
  **before** the FFI create; `importWallet` and `importWalletWithBackup`
  save after the FFI call succeeds.
- `NetworkConfigReconciliationTests` is the only suite; it already asserts
  that `custom_ABC123` yields `.noUsableConfig`.

### 2.4 bark at tag `bark-0.8.0` (verified in `~/workspace/bark`)

- `Wallet::create` connects to the server and **pins `server_pubkey` and
  `server_mailbox_pubkey` in `bark_properties`**. When
  `allow_unreachable_server` is true and the server is down or its
  `ArkInfo` is unsafe, create succeeds with both pubkeys `None` and the
  server is revisited on the next open.
- Every later connection compares the stored pubkey with the server's; a
  mismatch logs "You are connecting to a different server" and
  **`bail!`s**. Switching an existing wallet to another server is therefore
  a bark-level refusal, not an app choice. Changing servers means a new
  wallet (and, for funds, an exit or a send first).
- `Config::chain_source()` errors unless `esplora_address` or
  `bitcoind_address` is set. The library at our tag cannot take the chain
  source from the server, so a custom server **always needs an Esplora URL**
  on the app side. (Second's docs describe a server-provided default chain
  source for the CLI; that is not in our library tag. **Trusted claim, not
  relied on.**)
- `ServerConnection::builder().network(network)` is passed the wallet's
  chain. Whether bark refuses a server whose `ArkInfo.network` differs is
  **not verified**; the proposal does not rely on it (see the probe).

### 2.5 The FFI surface at `v0.26.0-9-g4670c1a` (verified in DerivedData)

- `Config.esploraAddress` is `String?`; `serverAccessToken` is still there
  (bark marks it deprecated).
- Free functions: `readDatadirInfo`, `walletExists`, `initWallet(network:
  mnemonicOrSeed:config:datadir:allowUnreachableServer:)`, validators. There
  is **no pre-open server probe** (no "fetch ArkInfo for this URL"
  function). `ArkInfo` carries `network`, `serverPubkey`, `feeSchedule`,
  `vtxoLifetime` and the rest once a wallet is open.
- The app's `createWallet` opens with `createWithoutServer: true`
  (verified in `BarkWalletFFI+WalletCreation.swift`). With a mistyped
  custom URL this **creates a wallet with no server pinned** instead of
  failing. Harmless today because the two preset URLs are correct; a trap
  the moment users type URLs.

### 2.6 One wallet directory (verified)

`BarkWalletFFI.getWalletDirectory()` is
`Application Support/<bundle>/bark-data-ffi` for every network and server.
A db from another chain fails to open with a network mismatch; a db from
another server on the same chain fails with bark's pubkey refusal.
`WalletManager.importWallet` deletes the directory on mismatch and retries;
`importWalletWithBackup` deliberately does not.

### 2.7 The push relay (verified in `~/workspace/arke-apns-relay-node`)

`ARK_ADDR_ALLOWLIST` defaults to Second's two servers; any other `ark_addr`
is rejected with `ark_addr_not_allowed`. The app sends
`(try await wallet.getConfig()).ark` at registration. A custom-server
wallet gets **no push notifications** until the relay allowlist changes
(operational, outside the app).

### 2.8 Every site that branches on the network (verified by grep)

Chain-shaped (stay keyed on the chain, unaffected by a custom server):

- `FeeRateService` cap: mainnet 10,000 sat/vB, otherwise 50.
- `ExitProgressionService.exitFeeRateOverride()` and the exit list view:
  nil on mainnet, app fast rate elsewhere.
- `VTXORefreshService` last-10%-of-life rule, keyed on `arkInfo.network`.
- `MetadataExportService` network stamp and the import mismatch check.
- `IntroVideoLibrary`, cover video and captions, `AddressValidator`,
  `PaymentDestination.isCompatible`, address colours.

Server-shaped (wrong if keyed on the chain once a custom server exists):

- Faucet: `ActivityView_iOS` faucet button and empty-state copy,
  `ContactDetailView_iOS.isSignetNetwork`, `createDefaultContactsIfNeeded`
  (the Faucetto contact), `ConnectionInfoSheet(isOnSignet:)`. The faucet at
  `arke.cash/api/faucet` pays through Second's signet server; an Ark address
  from a different signet server embeds a different server pubkey, so the
  faucet would fail or refuse. These must key on "Second signet", not
  "signet".
- `SendViewModel.currentNetworkConfig` rebuilds a **preset** from
  `arkInfo.bitcoinNetwork`, which would silently replace a custom config
  with Second's. (Also broken today: bark reports `"bitcoin"`, which
  `BitcoinNetwork(networkType:)` rejects, so on mainnet it already falls to
  the wallet's config. Derived from reading the code, not executed.)
- `ArkConfigModel.isSignetConfig` matches `"signet"` / `"testnet"` as
  substrings of the URLs. No callers; delete rather than fix.
- `NetworkDiagnostics` hardcodes `ark.signet.2nd.dev` (debug-only).
- Relay registration (§2.7).

### 2.9 Backlog state (verified)

"Ark server picker V2 with auto-pick default (plus the cover-screen server
selection mockup)" sits under Future ideas. `Exploration_Season.md`
records "Multiple servers, custom-server entry" as a season candidate and
says the scope doc must state what happens to existing funds, which this
document does (§4.6). `Network_Configuration_Persistence.md` lists custom
ids as Still Open #1.

## 3. The two servers

The bark SDK refuses Arkade addresses outright and Arkade's `arkd` speaks a
different protocol, so only captaind-compatible servers can be entered.

**Zappin, `ark.zappin.online` — verified 2026-10-29** by calling
`bark_server.ArkService/Handshake` and `GetArkInfo` over gRPC with
`grpcurl` and the proto files from the `bark-0.8.0` tag:

| Field | Zappin | Second mainnet (same call) |
|---|---|---|
| network | bitcoin | bitcoin |
| protocol versions | 4–5 | 4–5 |
| round interval | 600 s | 3600 s |
| VTXO expiry delta | 1008 blocks | 4032 blocks |
| exit delta | 144 | 144 |
| board confirmations | 3 | 2 |
| min board | 20,000 sat | 50,000 sat |
| max VTXO | none advertised | 10,000,000 sat |
| board fee | 330 min, 100 base, 1000 ppm | none |

Our bindings (bark 0.8.0) accept protocol versions 4 to 5
(`server-rpc/src/pver.rs` at the tag), so Zappin is compatible at the
handshake level. Not yet done against Zappin: an actual `Wallet::create`
through the FFI, which also runs `check_ark_info_safe`. That is the first
thing the probe (§4.4) will do in the simulator.

**CoinOS, `ark.coinos.io` — verified 2026-10-29, with a transport
problem.** It is a bark server on Bitcoin mainnet, protocol versions 4–5,
120 s rounds, 8640-block expiry, exit delta 144, 3 board confirmations,
1,000 sat minimum board, 5,000,000 sat max VTXO, 300 sat base refresh fee.
Those values came back only over **gRPC-web** (`application/grpc-web+proto`,
decoded with `protoc`). Native gRPC over HTTP/2, which is what bark's
`tonic` client speaks on iOS (`server-rpc` builds with `tonic-native`;
`tonic-web` is wasm-only, verified in `server-rpc/src/client.rs` and
`Cargo.toml` at the tag), was cut off by Cloudflare in front of the server:
`grpcurl` got "server closed the stream without sending trailers" and a
raw gRPC POST got a Cloudflare 403 page. Port 3535 does not answer.
**Verified with bark itself 2026-10-29** (one-off run of
`BarkWalletFFI.probeServer("ark.coinos.io")` in the simulator, test case
removed afterwards): both chain attempts failed inside the handshake with

```
Failed to connect to Ark server: handshake request failed: code: 'Internal error',
message: "protocol error: received message with invalid compression flag: 60
(valid flags are 0 and 1) while receiving response with status: 403 Forbidden"
```

Flag 60 is `<`, the first byte of Cloudflare's HTML 403 page. So the
Cloudflare zone in front of CoinOS does not pass native gRPC, and no
bark-based wallet, ours included, can connect to CoinOS today. This is an
operator-side fix (Cloudflare → Network → gRPC, or a direct endpoint), not
an app change; the form will show "Could not connect to an Ark server at
this address" until CoinOS changes it. The same transport limit applies to
the push relay's Node gRPC client.

Neither server advertises an Esplora; the app supplies one (§4.3).

## 4. Proposal

### 4.1 Split the chain from the server (model)

Keep `NetworkConfig` as the single type every call site already consumes,
but make `networkType` always a real chain (`mainnet` / `signet`) and add
the server identity beside it:

- `networkType` stays the chain. `isMainnet` stays derived from it.
- New `serverKind` (name open): `.secondMainnet`, `.secondSignet`,
  `.custom`. The Second cases are the existing presets; their ids stay
  `mainnet` and `signet` so **no migration** for installed wallets and no
  change for older builds on other devices.
- Custom ids become deterministic: `custom:<chain>:<normalised host>`
  rather than a random UUID, so two devices that type the same server
  agree, and `reconciliation`'s id comparison stays meaningful.
- `.testnet` has no server and no UI; leave it or drop it (ruling 6).
- `arkServerAccessToken` stays nil; bark deprecates it. No token field.

### 4.2 Persist the whole config, not the id

- Add a second key holding the full `NetworkConfig` as JSON, in both
  UserDefaults and KVS, written in the same `save(_:)`. The id key keeps
  being written for compatibility.
- `findConfig(byId:)` resolves presets as now, then falls back to the
  stored JSON if its id matches. `load()`, `reconciliation(...)` and
  `syncFromiCloud()` then handle custom servers without special cases.
- Older builds on another device see an unknown id and **ignore it with a
  warning** (already the behaviour). That alone is not enough (adversarial
  pass 2026-10-29, F1): an older build's `load()` falls back to mainnet, so
  a read-only secondary on build 26 that enters the recovery phrase imports
  onto Second and writes `mainnet` to iCloud; the custom-server device would
  then adopt the preset, re-point a working database, and bark would refuse
  every server call ("Server public key has changed"), with no UI to undo
  it. Two guards close this (reworked after the second pass, 2026-10-30):
  `NetworkConfigPersistence.reapplyDecision` keeps this device's config
  when the account names another server on the *same chain*, a wallet
  database exists, **and** the launch config was resolved from the local
  cache (`WalletManager.networkConfigResolvedFromCacheAtLaunch`; `load()`'s
  mainnet fallback says nothing about the database and still yields, which
  is how a reinstall finds its server). It applies in both directions, so a
  Second-pinned database is not pointed at a custom server either. The kept
  config is restored **locally only** (`saveLocally`), never re-published,
  so two devices on different servers do not fight over the account value.
  And `accountPendingCustomServerId` (reads iCloud directly, because a fresh
  device creates or imports before the launch sync ever ran) plus
  `WalletManager.refuseIfCustomServerPending` make create and import refuse
  any *other* config while the account names a custom server whose JSON has
  not arrived; the pending id is never written into the local cache. A
  device that holds the custom config the account names pushes the JSON up
  if the account's copy is missing (self-heal in `syncFromiCloud`).
  Residual, documented: if the custom server is dead *and* its JSON never
  reached iCloud, other devices are refused on presets until a full wipe
  clears the account keys.
- Add the new key to `SharedStateWipeCoverage` as `.fullWipeOnly`, and to
  `clearEverywhere()`. `clearLocal()` clears the local copy only.
- Same account-authority rule as today (rule 22, S2): the custom config
  is network config, so the account's value wins before an open, never
  after. No new state class is introduced.

### 4.3 The sheet (cover screen)

The top-left button opens a sheet instead of toggling. Content:

- Three rows with a checkmark on the selection: **Second · Bitcoin**
  (default), **Second · Signet (test)**, **Custom server…**.
- Tapping Custom expands or pushes a small form: Ark server URL
  (required, `https://` enforced) and a **Check** action. There is no
  chain picker: the probe (§4.4) detects the chain. On success the form
  shows the detected chain and the server pubkey prefix, and reveals the
  Esplora URL field prefilled with Second's Esplora for that chain
  (editable; bark at our tag needs one, §2.4; DECIDED 2026-10-29: shown and
  prefilled). Optional display name. Save stays disabled until the probe
  passed; editing the URL afterwards invalidates the probe.
- The cover keeps changing video and caption by **chain**, not by server.
  A small label under the button names the server when it is not the
  default (e.g. "Signet · Second" or "Bitcoin · ark.example.com"), so the
  choice is visible before Create or Import.
- The selection lives in `OnboardingFlow_iOS` as a `NetworkConfig` instead
  of the bool; `isMainnet` becomes `config.isMainnet` for the views that
  only need the chain. Create and Import receive the config directly and
  the ternary disappears.
- Accessibility strings (`accessibility_switch_to_testnet` and friends)
  become "Choose network and server" plus the selected value.
- Desktop: parked. `FirstUseView` keeps its toggle; the dead mockup folder
  is a separate ruling (ruling 7).

### 4.4 The probe

The probe runs when the user taps Check in the custom form, before
anything is saved. There is no FFI function that fetches `ArkInfo` for a
URL on its own, and bark does not let the client ask "which chain are
you": `ServerConnection` takes the chain as input and refuses with
`NetworkMismatch { expected, got }` when the server's `ArkInfo.network`
differs (verified, `server-rpc/src/client.rs` at `bark-0.8.0`). The FFI
surfaces that as `Bark.Error.Inner(message:)`, a string, so the chain is
detected by **trying, not by parsing**.

**Recommended: an `initWallet` probe into a scratch directory.** The
bindings' free function `initWallet(network:mnemonicOrSeed:config:datadir:
allowUnreachableServer:)` is `Wallet::create` alone (verified in
`bark-ffi` at rev `4a1c1c0`, `src/muniffi/wallet.rs`): it connects, runs
the handshake and protocol-version check, fetches `ArkInfo`, checks the
chain, runs `check_ark_info_safe`, and writes a properties row. It does
**not** need an Esplora or an onchain wallet, so it is the lightest call
that proves "reachable, bark-compatible, safe, and on chain X".

Procedure, as a static on `BarkWalletFFI` (name open, e.g.
`probeServer(url:) async throws -> ServerProbeResult`):

1. Throwaway mnemonic from `generateMnemonic()`, never stored or logged.
2. Scratch datadir under `tmp/`, never the real `bark-data-ffi`.
3. `initWallet(network: .bitcoin, …, allowUnreachableServer: false)`.
   Success means mainnet. On failure, remove the scratch dir and try
   `.signet`. Success means signet. Both failing means unreachable,
   incompatible or unsafe; show the last error text.
4. `readDatadirInfo(datadir:)` confirms the network that was written.
5. Delete the scratch directory in a `defer`, including on cancellation.

Returned to the form: the chain and, if wanted, the pubkey. The pubkey is
not in `DatadirInfo`; getting it needs a `Wallet.open` of the scratch
wallet with an Esplora (adds the BDK init and a chain-source network check
against the Esplora, a few seconds). Recommendation for the first cut:
chain only from the probe, pubkey and fee schedule visible in X-Ray once
the real wallet exists. The Esplora URL the user accepts is validated by
the real create, which already fails on an unreachable chain source.

Two attempts cost two connects on a wrong-chain server and one otherwise.
Timeouts (corrected after the adversarial pass, F2): a uniffi async call
cannot be interrupted (the bindings trap on `CALL_CANCELLED`) and bark sets
no connect timeout (its request timeout is ten minutes), so the 20 s
ceiling and the caller's cancellation are a *race*, not an interruption:
whichever of the attempts task, the timeout task or the caller's
cancellation finishes first resumes a continuation (`ProbeRace`); an
attempt still in flight is orphaned, the attempts task is cancelled so no
second chain is tried, and the orphan removes its own scratch directory
when the FFI returns. The form shows "did not answer in time" after 20 s
and the field is editable again.

Rejected alternatives: a raw gRPC reachability check (no chain, no
protocol check, needs a gRPC client the app does not have), and "let
Create fail" (§2.5: create does not fail on a bad server today).

### 4.5 Create, import and the save ordering

**`createWithoutServer`, in plain terms.** When the app creates or imports
a wallet, bark first tries to contact the Ark server and writes the
server's public key into the wallet database. That key is what later
proves "this wallet belongs to this server". The flag
`createWithoutServer: true` tells bark: if the server cannot be reached,
create the wallet anyway, leave the key empty, and pin whatever server
answers on the next launch. The app passes `true` on both create and
import today (verified, `BarkWalletFFI+WalletCreation.swift`), so a Second
wallet can be created on a plane. With a user-typed URL the same flag
means a typo creates a wallet with no server at all, and the first server
that answers at that typo'd address later gets pinned, which is not what
the user chose. Options:

1. **`false` everywhere (recommended).** Create and import require the
   server once. Offline creation stops working for Second wallets too; a
   fresh wallet is useless offline anyway, and the error is honest.
2. `false` for custom servers only. Keeps offline Second creation, adds
   a branch that the fault-class review must trace on both paths.

Either way the probe (§4.4) already proved the custom server reachable a
moment earlier, so the flag is a backstop, not the gate.

- `createWallet` saves the config before the FFI create. With a custom
  server that order persists a config whose server may never have worked.
  Move the save after the FFI create succeeds for all three paths, or keep
  it and rely on the probe gate. Recommendation: move it; `importWallet`
  already saves after, so this also removes a path asymmetry.
- Import against a custom server runs bark's recovery scan on that server.
  Importing a phrase that was used on Second into a custom server yields an
  empty wallet with no warning possible (VTXOs live per server). The import
  screen must say so in one sentence when a custom server is selected.
- Backup-file import (`importWalletWithBackup`) carries bark's db, which
  has the pinned server pubkey. Opening it does **not** contact the server
  (verified, `Wallet::open` at `bark-0.8.0`; the key is compared lazily in
  `require_server`), so a wrong server selection would have persisted the
  wrong config and failed later with an unmapped error (adversarial pass
  2026-10-29, F4). The import now calls `refreshServer()` right after the
  open; "public key has changed" becomes
  `BarkErrorArke.backupBelongsToAnotherServer` and the import rolls back
  (restored copy removed, seed and hash restored; the user's backup file
  is untouched). An unreachable server is not a mismatch and the import
  stands.

### 4.6 Existing wallets and switching servers

**DECIDED 2026-10-29: no server switching**, not in this cut and not as a
follow-up entry. The sheet exists only on the cover screen, before a
wallet exists. Rationale, from §2.4: bark refuses a pubkey change, and
VTXOs are per server. A user who wants another server moves funds out,
deletes the wallet, and creates or imports on the new server through the
existing flows. The X-Ray configuration section keeps showing the current
server read-only.

### 4.7 Feature gating with a custom server

- Faucet UI, Faucetto contact, `ConnectionInfoSheet(isOnSignet:)`: key on
  `serverKind == .secondSignet`.
- `SendViewModel.currentNetworkConfig`: return `walletManager.networkConfig`
  and use `arkInfo` only to cross-check the chain. Fixes the existing
  `"bitcoin"` mismatch on the way.
- Relay registration: with a custom server the relay answers
  `ark_addr_not_allowed`. **Where this lives:** the allowlist is an
  environment variable (`ARK_ADDR_ALLOWLIST`) of the relay node in
  `~/workspace/arke-apns-relay-node`, which Christoph operates. It is not
  app code and not the Ark server. Its purpose (README): the relay API
  token ships in the app and is effectively public, so without the list
  anyone could point the relay at a server they control. The relay
  otherwise handles any address generically (one cached gRPC channel per
  address). Options: add the two servers to the list (a redeploy or env
  change on the relay, no code), or set `*`, or leave it. The app side is
  the same in every case: classify the rejection and show "Notifications
  are not available for this server" in Notifications settings instead of
  retrying, since a future server nobody has allowlisted will hit it.
- `ArkConfigModel.isSignetConfig` and siblings: delete (no callers).
- `NetworkDiagnostics`: take the URL from the current config.
- Everything in the chain-shaped list of §2.8 stays as is.

### 4.8 Security notes

- The URL is user input that becomes a TLS endpoint for funds-relevant
  traffic. Enforce `https://`, reject userinfo and paths beyond what bark
  expects, trim whitespace, lowercase the host. ATS already blocks plain
  HTTP in release builds.
- Show the server pubkey (first and last characters) after the probe, so a
  user who got the URL from an operator can compare it with what the
  operator publishes.
- The Esplora URL is a chain-data dependency used for exits and
  confirmations; a hostile Esplora can lie about confirmations. Defaulting
  to Second's Esplora keeps that trust where it is today; the field is
  editable for operators who run their own.
- No remote server list in this cut. A curated list at `arke.cash` (like
  the rates JSON) is a later option and would need signing or pinning to
  be worth more than hand entry.

### 4.9 Sheet design rulings and open copy questions (2026-10-29)

After the first simulator look Christoph ruled (DECIDED 2026-10-29): the
sheet uses the import screen's idiom, dark background, serif gold title,
bordered option cards, not a system list; and the three options are
**Default** (Second's mainnet server), **Development** (Second's signet
server, "for developers") and **Custom server**. "Second" is not a section
header, since most users will not know the company; it appears in the card
subtitles only. Built the same day.

Two questions he raised were proposed as below and **DECIDED as proposed
the same evening ("Agree with your recommendation" / "Yes")**; both are
built (terms link under the Default card, operator footnote in the custom
form, title "Server", "Ark" demoted to descriptions):

**Terms of use.** Facts (verified 2026-10-29 with `grpcurl` against each
server's `GetArkInfo`): the bark protocol carries an `ArkInfo.tos_link`
("Link to the server's terms of service, if any"). Second's mainnet server
advertises `https://second.tech/terms`; Second's signet server, Zappin and
CoinOS advertise none. Our Swift bindings at v0.26 do **not** expose the
field (no `tosLink` in `Bark.swift`), so the app cannot read it from bark
until a bindings bump; this belongs in `Bark_Bindings_Unadopted_API.md`.
The app's own terms at `arke.cash/terms-and-conditions` already say that
using the payments balance means agreeing to Second's terms. Proposal:

1. On the Default card, a small "Terms of use" link row under the subtitle
   opening `https://second.tech/terms` in the browser, hard-coded for the
   preset (the preset is hard-coded too). No checkbox: the app's own terms
   already bind the user and a second consent step on the cover screen is
   friction without legal gain.
2. On the Development card nothing (no terms advertised).
3. In the custom form, after a successful check, a footnote: "Terms of use
   are set by the server operator." When the bindings expose `tosLink`,
   the probe can return it and the footnote becomes a link.
4. A line in `Bark_Bindings_Unadopted_API.md` for `ArkInfo.tos_link`.

**How prominent "Ark" should be.** Proposal: the sheet title becomes
"Server", the cards stay "Default / Development / Custom server", and
"Ark" survives only in the intro ("Your wallet is run through one Ark
server…") and in the probe result ("Ark server found", which is exactly
the technical fact being confirmed). The cover button's accessibility
label becomes "Server and network". The form title becomes "Custom
Server" (unchanged) and its intro keeps "Ark server" once. Reason: users
who know what Ark is will find the word in the description; users who do
not gain nothing from it in a title.

### 4.10 Second design iteration (DECIDED 2026-10-30)

Christoph after the restyle: keep the lab-vial icon (the feature is still
experimental; a reliable server list can earn it a bigger place later); the
first page should be *about the default server* with an "Other options"
step to a second page for Development and Custom, not a list up front; no
pill on the cover. Both open points ruled the same day: page one always
shows the currently selected server, and the Create screen gets the caption
with the wording **"Connects to <host>."** (the Import caption uses the same
verb). View layer only, nothing underneath changes:

- **Icon:** `testtube.2` again. Accessibility label "Server and network",
  value the current selection (invisible, free).
- **Page 1, "Server":** describes the server the wallet will connect to.
  For the default: "Arké connects to Second's Bitcoin server." plus the
  one-sentence explanation that a wallet belongs to one server, the
  "Terms of use" link, and a single row "Other options ›". When a
  non-default is already selected, the same page shows *that* server
  (name or host, chain, the operator-terms footnote for custom) so the
  page always answers "what am I about to connect to"; "Other options"
  still leads to the chooser, which includes Default so the user can go
  back to it.
- **Page 2, "Other options":** the three cards as built today (Default,
  Development, Custom server ›), checkmark on the current one; picking a
  preset pops back to page 1 showing it; Custom server pushes the existing
  form, Save pops back to page 1.
- **Cover:** no pill. The signet notice ("You will create a test wallet.")
  stays, since it is chain-shaped and already existed. For a custom
  *mainnet* server the cover would then show nothing at all, so the
  Create screen gets the same one-line caption the Import screen already
  has ("Creates on <host>.") when the server is not the default. That is
  the one place a forgotten custom choice would otherwise go unnoticed
  until after creation, and creation pins the server for good.

### 4.11a Christoph's mockup (2026-10-30, supersedes the copy below)

Christoph answered the §4.11 proposal with a mockup. Page one is: title
"Server"; one paragraph "A server helps create your wallet and make
payments. Note that this can't be changed later."; a quiet card with the
Second logo in a white rounded tile, "Second", and a gold "Terms of use ↗"
link as the second line; a centred plain text link "Options ›"; the sheet
sized to that content. Variants he specified: no terms line when the
server advertises none; a second line about signet when the server is a
test server; a fallback icon for custom servers. Proposal for the
variants, PROPOSED:

- Development: card "Second" / "Signet test network · coins have no
  value"; no terms line (Second's signet server advertises none).
- Custom: tile with a neutral glyph (`server.rack`) in place of the logo;
  host as the title; "Signet test network · coins have no value" as the
  second line only on signet; no footnote about operator terms (the custom
  form already says it; page one stays minimal).
- Sheet height: page one sized to content via a fixed detent; pushing
  Options or the custom form switches the detent to large
  (`presentationDetents(_:selection:)`), and popping back returns it.
- Signet second line: "Signet test network · coins have no value" (DECIDED
  2026-10-30: casual users must not mistake it for a real option).
- Page two reuses page one's row: tile (logo or glyph), title, one secondary
  line, plus a checkmark on the selected row and a chevron on Custom. The
  secondary line describes the option there instead of linking: Default
  "Second" / "Default · real bitcoin"; Development "Second" / "Signet test
  network · coins have no value"; Custom "Custom server" / "Enter an
  address", or the host and its network once one is saved. The terms link
  lives on page one only, since a link inside a selectable row competes
  with the selection tap.
- Logo asset: `Shared/Media.xcassets/second.imageset` already exists (the
  desktop mockup's `Image("second")`); reuse it if it is the mark in the
  mockup, otherwise replace its image.

**Built 2026-10-30 ("Build it").** `ArkServerSelectionSheet` page one:
title, the mockup paragraph, one `ServerRow` (white tile with the `second`
asset or a `server.rack` glyph, title, secondary line: terms link on
Second mainnet, "Test network · coins have no value" on signet, nothing
otherwise), centred "Options ›". Page two "Options": the same row three
times with checkmark and chevron. The sheet sizes itself: page one's
content height is measured (`onGeometryChange`) and drives a `.height`
detent, pushed pages switch the selection to `.large`, the drag indicator
is hidden. The test-network line says "Test network" rather than "Signet"
so it fits one row beside the tile; the custom form still names the chain.
First simulator walk (six steps, all passed, screenshots
`173123–173441.png`) found three deviations from the mockup, fixed the same
hour: the half-screen detent with ~115 pt of dead space, a visible
grabber, and the signet line wrapping. The second look (`173725–173822.png`)
caught the fitted detent being ~31 pt short (a constant chrome allowance
versus the real nav bar plus home indicator), which collapsed the intro to
one line and fed the shorter measurement back into the detent. Fixed: the
bottom safe area is read live from the same geometry callback and the
paragraph has `fixedSize(horizontal: false, vertical: true)` so a short
detent overflows instead of collapsing. A third look showed the live
safe-area term made the first open 31 pt taller than every return, so it
was dropped: the system keeps the content above the home indicator by
itself. Final look (`174626–174804.png`): page one identical on first open
and after each return (372.9 pt on the 18 Pro Max), two-line paragraph,
31.8 pt under "Options", Options page at full height. The copy proposal
below is superseded.

### 4.11b Row titles (DECIDED 2026-10-30, built the same day: the revised table below)

Christoph: "Second" as the title of both the mainnet and the signet row may
not communicate; perhaps the titles should be Default and Development with
Second in the small text. Proposal: titles name the **role**, the small
text names **what it is**, the logo tile names **who runs it**.

| Row | Tile | Title | Small text |
|---|---|---|---|
| Default | Second logo | Default | "Second", then "Terms of use ↗" on its own line |
| Development | Second logo | Development | "Test network · coins have no value" (Second is the logo) |
| Custom, unsaved | glyph | Custom server | "Enter an address" |
| Custom, saved | glyph | host | "Custom server", or the test-network line on signet |

Same rows on page one and page two, so "Server → Default" on page one is
the word the user then finds checked on the Options page. The Default row
is the only three-line row; the fitted detent absorbs it.

Revision after Christoph's four follow-ups (PROPOSED 2026-10-30): rows are
multi-line by design (small phones wrap anyway); attribution reads "By
Second"; the test network is named both ways, "Signet test network", so
developers get the precise word and everyone else the explanation; the
Development row gets its own tile, the lab vial, which is already the
cover button's icon and the signet video's motif, so "Second" moves into
its text line and the two Second-run rows stop looking alike.

| Row | Tile | Title | Lines below |
|---|---|---|---|
| Default | Second logo | Default | "By Second" · "Terms of use ↗" |
| Development | lab vial | Development | "By Second" · "Signet test network" · "Coins have no value" |
| Custom, unsaved | server glyph | Custom server | "Enter an address" |
| Custom, saved | server glyph | host | "Custom server", plus "Signet test network" · "Coins have no value" on signet |

Built 2026-10-30 ("Build it"): `ServerRow` now takes only the config and
accessory; `title(for:)` and `lines(for:)` hold the table above; the tile
switches on `serverKind` (logo / `testtube.2` / `server.rack`). Simulator
walk, five steps, all passed (`180709–180943.png`): rows read exactly as
the table, no wrapping on the 18 Pro Max, the sheet grows one line for
Development and shrinks for the two-line custom row, checkmark and chevron
share the custom row. Tiles are top-aligned with the title on multi-line
rows; accepted.

### 4.11 Third design iteration (PROPOSED 2026-10-30, Christoph's notes; superseded by §4.11a)

Christoph: page one says "server" seven times; the intro, the card title,
the network line and the detail all repeat each other; the bitcoin icon and
the highlight carry no information; the two paragraphs can be one;
"Other options" can be "Options" without a subline. He can provide a Second
logo. Proposal, copy and layout only:

**Page one, default (the word "server" appears once, in the title):**

```
Server
Arké connects to Second, the default. This can't be
changed once the wallet exists.

[Second logo]  Second
               Terms of use ↗

Options ›
```

- The card is quiet: same fill as the fields, thin stroke, no highlight.
  It is information, not a selection.
- No network line for the default: Bitcoin is the norm and not worth a
  word. The network is named only when it is a test network.
- The logo replaces the bitcoin icon. Asset: `second-logo` in
  `Shared/Media.xcassets` (the themes' shared catalog), square, works on
  the dark sheet; shown at 40 pt with rounded corners. Until the asset
  exists the card shows the name alone.
- "Options" is a plain row with a chevron, not a card, so the card above
  reads as the single subject of the page.

**Page one, development:**

```
Server
Arké connects to Second's test environment on signet. Coins
there have no value. This can't be changed once the wallet
exists.

[Second logo]  Second
               Signet · test network
```

**Page one, custom:**

```
Server
Arké connects to a server you entered. This can't be
changed once the wallet exists.

[server glyph]  ark.zappin.online
                Signet · test network        (only when not mainnet)
                Terms of use are set by the operator.
```

**Page two, "Options":** title "Options", three cards, "server" twice:

- Default — "Second. Real bitcoin."
- Development — "Second's test environment on signet. Free test coins
  from the faucet, no value."
- Custom server › — "Enter an address."

**Create / Import captions:** unchanged ("Connects to <host>.").

## 5. Sweep list

Sites the pattern touches, to be marked covered / exempt / missed in the
review:

- Writers of network config: `WalletManager.createWallet`, `importWallet`,
  `importWalletWithBackup`, `NetworkConfigPersistence.syncFromiCloud`.
- Deleters: `WalletManager.deleteWallet` (`clearLocal`),
  `WalletDataCleanupService` (`clearEverywhere`, `SharedStateWipeCoverage`).
- Readers: `WalletManager.init`, `reconcileNetworkConfigBeforeWalletOpen`,
  the background wake path in `WalletManager+Notifications`,
  `MetadataExportService`, `MetadataBackupSectionView`,
  `SendViewModel.currentNetworkConfig`, `WalletManager+PaymentDestination`.
- `isMainnet` consumers of the onboarding bool: `FirstUseView_iOS`,
  `IntroVideoView_iOS`, `CreateWalletView_iOS`, `ImportWalletView_iOS`,
  `SettingsView_iOS` (intro replay), and the desktop twins (exempt, parked).
- Signet string compares: `VTXORefreshService` (chain, exempt),
  `ActivityView_iOS` ×2, `ContactDetailView_iOS`, `ArkConfigModel`.
- `MockBarkWallet` network properties (DEBUG stub, update to compile only).
- `BarkWalletFFI.makeConfig(from:)`, `convertToFFINetwork`, `init?`.
- Tests: `NetworkConfigReconciliationTests` (extend for custom),
  `WalletDeletionRejoinTests` (inventory), `FeeRateServiceTests` (unchanged).

## 6. Fault-class pass on the proposal itself

- **Scope.** The new KVS key is account-scoped on purpose; it is the same
  state class as the id key and follows the same `.fullWipeOnly` rule.
  Risk: a local-only delete must not clear the KVS copy. Covered by using
  `clearLocal` / `clearEverywhere` unchanged.
- **Path asymmetry.** Three save orderings today (create before, imports
  after); `createWithoutServer: true` only on create. Both get unified in
  §4.4–4.5. The probe must run for Import too, not only Create.
- **Ownership.** `OnboardingFlow_iOS` owns the chosen config until the
  wallet exists; `NetworkConfigPersistence` owns it after. The sheet never
  writes persistence itself.
- **Boundary assumptions.** Two unverified bark behaviours: whether the
  server connection checks the chain (§2.4) and the exact failure mode of
  `check_ark_info_safe` for an incompatible server. Both are covered by
  the probe comparing `arkInfo.network` and by an executed test against a
  wrong URL before Phase 2 is called done.
- **Trusted claims.** Second's "server-provided chain source" is CLI-only
  at our tag; not relied on. The identity and compatibility of the two
  servers is unverified (§3).

## 7. Build plan (target: days, DECIDED 2026-10-29 on timing)

Three work steps, each one build and one scoped test run, then one
adversarial pass over the whole range and the device list.

- **Step 1 — model and persistence** (Shared, no UI). **Built 2026-10-29.**
  `ArkServerKind` (`.secondMainnet`, `.secondSignet`, `.custom`) beside the
  chain on `NetworkConfig`; `isMainnet` derived from the chain; custom id
  `custom:<chain>:<host[:port]>` via `NetworkConfig.custom(...)`; `.testnet`
  and `defaultNetworks` dropped (`presets` = mainnet, signet); full-config
  JSON under `com.arke.wallet.networkConfig` in UserDefaults and KVS beside
  the id; pure `NetworkConfigPersistence.resolve(id:stored:)`;
  `reconciliation(walletNetworkId:cachedConfigId:storedConfig:)`;
  `syncFromiCloud` reads and writes both keys; `SharedStateWipeCoverage`
  entry; `createWallet` saves after the FFI create; `createWithoutServer:
  false` on create and import; `BarkWalletFFI.probeServer(url:)` in
  `BarkWalletFFI+ServerProbe.swift` (`initWallet` into a scratch dir,
  mainnet then signet, 20 s ceiling, cancellation-aware);
  `SendViewModel.currentNetworkConfig` returns the wallet's config (forced
  by the `.testnet` removal, and the Step 3 fix anyway).
  **Executed:** build green; `NetworkConfigReconciliationTests` (11),
  `NetworkConfigCustomServerTests` (7), `WalletWipeCoverageTests` (7) pass;
  `ArkServerProbeLiveTests` (gated on `TEST_RUNNER_ARKE_LIVE_PROBE=1`):
  Second signet detected on the second attempt in under 1 s, which proves
  the chain detection path; Zappin detected as mainnet through the real
  FFI call in under 1 s; `example.com` fails as unreachable; scratch
  directory gone afterwards.
- **Step 2 — the sheet** (iOS). **Built 2026-10-29.**
  `ArkServerSelectionSheet` and `CustomArkServerForm` in
  `Shared/Views/FirstUse/ArkServerSelectionSheet.swift` (Shared so the
  desktop target compiles it; only `FirstUseView_iOS` presents it, with
  medium and large detents). `FirstUseView_iOS` takes a `NetworkConfig`
  binding, the button is `server.rack` and opens the sheet, a glass label
  beside it names any non-default choice ("Signet · Second",
  "Bitcoin · ark.zappin.online"); video and test-wallet notice follow the
  chain. `OnboardingFlow_iOS` holds the config; `CreateWalletView_iOS`,
  `ImportWalletView_iOS` and the in-app seed-entry sheet in
  `ActivityView_iOS` take it. Import shows "Restores on <host>. Only funds
  held on that Ark server are recovered." for custom servers. Form: address
  field → Check → detected chain, Esplora prefilled (stored form, with
  scheme), optional name, Save; editing the address resets the check;
  reopening a saved custom server shows it as already checked. Failure row
  shows the localized headline plus bark's own message (unwrapped from
  `Bark.Error.Inner`). Custom URLs are stored as scheme + lower-cased host.
  **Executed:** build green; the 30 tests of the four scoped suites pass
  (live probe included). Simulator walkthrough 2026-10-29 by the
  device-interaction agent, all ten steps passed (screenshots
  `~/workspace/Arke-sessions/screenshots/2026-10-29/202531–203158.png`):
  default cover without label; sheet rows and checkmarks; Signet label and
  notice and video swap; empty address disables Check; typed
  `HTTPS://Ark.Zappin.Online/` → "Ark server found", Bitcoin, Esplora
  prefilled, Save enabled; edit resets; Save → cover label; reopen shows
  the saved server pre-checked; `example.com` → failure row with detail and
  "Check again"; import caption. Three findings from that look fixed the
  same hour (enum dump in the detail line, host casing, Esplora with and
  without scheme) and the duplicate "Network" header removed. Not a
  defect: the list page is glass at the medium detent and the pushed form
  is opaque at full height (system sheet behaviour); the gold tint on the
  custom row was the video behind the glass. **Not verified:** the iOS 26.5
  simulators are not drivable by the device tools, so the look ran on an
  iPhone 18 Pro Max, iOS 27.0; dark appearance; a very long custom host in
  the cover label. Restyled the same evening per §4.9 (dark, serif, cards,
  Default / Development / Custom server); second simulator look, six steps,
  all passed, screenshots `210702–210940.png`.
- **Step 3 — gating sweep.** **Built 2026-10-29.** `WalletManager.hasSignetFaucet`
  (`serverKind == .secondSignet`) now gates the faucet toolbar button and
  empty-state action in `ActivityView_iOS`, the faucet section in
  `ContactDetailView_iOS`, the Faucetto default contact
  (`createDefaultContactsIfNeeded`) and the faucet hint row inside
  `ConnectionInfoSheet` (new `showsFaucetHint:` parameter; the test-network
  section itself stays chain-shaped on `!isMainnet`).
  `SendViewModel.currentNetworkConfig` was fixed in Step 1. Relay:
  `RelayError.arkServerNotServed` is produced when the 400 body carries the
  relay's allowlist text (`RelayRegistrationService.isArkServerNotServed`;
  the relay keeps the `ark_addr_not_allowed` reason in its logs only, so
  the body text is the signal — a `reason` field in the relay's JSON body
  would make this robust, relay-side change for Christoph);
  `WalletManager.pushUnavailableForServer` stops further registration
  attempts for the session and the Notifications setting shows "Payment
  notifications are not available for this server. Reminders scheduled on
  this device still work." as a footnote and once as an alert when the
  toggle is turned on. `ArkConfigModel.isSignetConfig` / `isTestnet` /
  `isRegtest` deleted (no callers). `NetworkDiagnostics`: its hard-coded
  signet URLs are inside a commented-out block, nothing live; left alone.
  Sweep of the desktop views found no faucet or signet gating to mirror.
  Tests: `RelayDisallowedServerDetectionTests`.
- **Review.** First adversarial pass 2026-10-29 (fault-class-reviewer body
  run as a general-purpose agent over the uncommitted diff). Findings and
  what was done:
  - **F1 CONFIRMED (scope, rule 22)** — build-26 secondary imports the
    phrase, writes `mainnet` to KVS; custom device adopts it and re-points
    a working database; bark then refuses every server call. Fixed:
    `reapplyDecision` + `pendingCustomServerId` +
    `refuseIfCustomServerPending` (§4.2), tests
    `NetworkConfigReapplyGuardTests`.
  - **F2 CONFIRMED (boundary)** — the probe's ceiling could not interrupt
    the FFI call (`CALL_CANCELLED` traps; no bark connect timeout). Fixed:
    `ProbeRace` continuation race (§4.4).
  - **F3 CONFIRMED (ownership)** — `pushUnavailableForServer` never reset.
    Fixed in `resetManagerState`.
  - **F4 CONFIRMED (trusted claim)** — backup import under the wrong server
    did not fail at open. Fixed: `refreshServer()` after the open,
    `backupBelongsToAnotherServer` with rollback (§4.5).
  - **F5 CONFIRMED** — tree post-dated the last build; §4.9 said PROPOSED
    for items Christoph had approved. Rebuilt; doc corrected.
  - **F6/F7** — failure detail overwritten per attempt; probe URL kept a
    path the stored URL dropped. Fixed: `probeFailureDetail`,
    `canonicalServerURL`.
  - **F8 PLAUSIBLE** — live suite flake on the tmp listing. Suite is
    `.serialized`.
  - Filed, pre-existing: the regular open relies on the bindings'
    `createIfNotExists: true` default (Tier 4, Concurrency and the FFI
    boundary).
  Second pass on the fixes, 2026-10-30:
  - **R1 CONFIRMED** — the pending gate read UserDefaults, which only the
    launch sync fills, so it never fired in onboarding. Fixed: the gate
    reads iCloud directly (`accountPendingCustomServerId`).
  - **R2 CONFIRMED** — writing the pending id into the id slot broke a
    signet wallet's second launch (fallback to mainnet). Fixed: the pending
    id is no longer written locally at all.
  - **R3 CONFIRMED** — the re-apply guard was one-sided; a Second database
    could be pointed at a custom server. Fixed: symmetric guard gated on
    "resolved from cache", local-only restore (§4.2); tests updated.
  - **R4 CONFIRMED** — the local pending id was sticky and got re-published.
    Moot with R2's fix; the self-heal push covers the missing-JSON case.
  - **R5 CONFIRMED** — `CreateWalletView_iOS` flattened the pending message
    by keyword. Fixed: typed error shown verbatim.
  - **R6 PLAUSIBLE** — after a server-mismatch rollback the FFI handle stays
    open on an unlinked database (pre-existing shape). Filed: Tier 2
    Two-device.
  - **R7 minor** — a probe cancelled before it armed answers via the next
    checkpoint or the ceiling. Accepted.
  **Design iteration §4.10 built 2026-10-30** (view layer only): lab-vial
  icon back, two-page sheet (current server with terms link or operator
  footnote, then "Other options" with the three cards), no cover pill,
  "Connects to <host>." on the Create screen's creating and finished states
  and on the Import screen. Simulator walk, eight steps, all passed
  (`~/workspace/Arke-sessions/screenshots/2026-10-30/104402–104720.png`):
  default page, Other options, Development auto-pops back, signet notice
  without pill, custom save pops back with host card, checkmark moves to
  the custom card, Import caption. Fix from that look: a taller opening
  detent so page one's last card does not touch the sheet edge. Noted, not
  changed: the signet notice sits over the brightest part of the test video
  (pre-existing contrast); the custom form drops to half height when the
  keyboard closes, so the Esplora field needs a scroll (system behaviour).
  Creation starts on arrival at the Create screen, so its caption is
  informational, not a checkpoint; a pre-creation checkpoint would belong
  on the intro-video screen if ever wanted.
  **Full mobile suite 2026-10-30: 632 tests in 91 suites passed** (live
  probe suite skipped by its gate, run separately: 5/5). Final simulator
  look of the sheet copy the same morning: title "Server", terms link opens
  Safari and the sheet survives the round trip, operator footnote in the
  custom form, accessibility label "Server and network"
  (`~/workspace/Arke-sessions/screenshots/2026-10-30/065155–065425.png`).
- **Device.** Fresh install on the phone, custom server Zappin on mainnet
  with a small boarding amount (min board is 20,000 sat there); a wrong
  URL failing at Check; a Second signet wallet end to end including faucet
  and push; two devices on one account where the second resolves the
  custom config from KVS before its first open; one device on build 26
  ignoring the unknown id. Relay allowlist change before the push check if
  ruled.
  **Done 2026-11-02 (Christoph, physical phone):** wallet on Zappin via
  the custom-server form, Lightning payments received and sent, "all
  smooth". Still open from the list: wrong URL at Check on the phone (seen
  in the simulator only), the Second signet end-to-end, the two-device KVS
  case, and the build-26 device.
  Follow-up ruling the same day: the "Connects to <host>." caption on the
  Create screen is removed (creation starts on arrival, so it was
  informational only); the Import caption stays.
  **Two-device case, 2026-11-02 (second phone's log, read 2026-11-02):**
  the secondary launched with `custom:mainnet:ark.zappin.online` already
  resolvable from its local cache ("resolved from cache: true"), so an
  earlier launch had taken both iCloud keys; step 0-pre reported "Network
  config in sync before wallet open: Zappin"; the device was a demoted
  secondary and initialised read-only from CloudKit (balance and the
  primary's Ark address). No warnings from the network-config path, no
  re-point. **Not exercised by this run:** the bark open on the secondary
  (read-only mode never opens the database), so the same-chain re-point
  guard and bark's pinned-key check were not hit on a device; the first
  sync itself happened on a launch that was not captured.
  **Delete and re-import on Zappin, 2026-11-02 (Christoph, phone):**
  worked. This is the seed-only import path against a custom server:
  server selected in the sheet, `createWithoutServer: false`, bark's
  recovery scan against Zappin, the pending-sync gate passing because the
  chosen config matches the account's id, config saved after the FFI
  success, funds back. Together with the creation test this covers both
  wallet-producing paths on a device. Still not exercised on a device: a
  wrong URL at Check, the Second signet regression look, a build-26 device,
  and the two refusal paths (same-chain re-point, backup from another
  server), which need a deliberately wrong setup.

Definition of done per `Release_Train.md` Tier 1, Rework Ledger line if
anything is revisited.

## 8. Calls

Ruled 2026-10-29:

1. **Scope:** cover screen only; no server switching, now or later. DECIDED.
3. **Esplora field:** shown and prefilled with Second's, editable. DECIDED.
6. **`.testnet` preset:** dropped. DECIDED.
7. **Desktop mockup folder:** stays until desktop is unparked. DECIDED.
8. **Timing:** built within days, inside Train 2. DECIDED.
9. **Servers:** CoinOS (URL pending) and Zappin `ark.zappin.online`. DECIDED.

Ruled 2026-10-29 as recommended (all three DECIDED, "that all sounds good"):

2. **Probe:** the `initWallet` scratch-directory probe, chain
   detected by two attempts, chain only. It is the lightest FFI call that
   proves reachable, protocol-compatible, safe and on which chain; the
   pubkey variant adds a full open against an Esplora for a value X-Ray
   shows anyway once the wallet exists.
4. **`createWithoutServer`:** `false` everywhere. One invariant
   instead of a branch per server kind. For import it is also more
   correct: bark's seed-recovery scan runs only at creation
   (`created_now`, see `bark-recovery-scan-created-now-gate` in the
   ledger), so an import that succeeds without the server yields an empty
   wallet that never recovers on its own. **Derived**, not executed.
5. **Relay allowlist:** add the two servers by name, not `*` (Christoph
   does this on the relay). The list exists because the relay token is public; `*` turns the
   relay into a free polling service against any server. Adding a name
   is an env change. CoinOS also needs its Cloudflare fix before the
   relay can poll it (§3).
10. **CoinOS:** recommend telling the operator about the gRPC transport
   (§3) before any UI work targets them; Zappin can be the Step 1 probe
   target.
