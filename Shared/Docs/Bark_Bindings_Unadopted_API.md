# Bark Bindings — Unadopted API

Record of capability that exists in the bark FFI bindings but is not yet
adopted by the app, with the feature implications of each item. Serves as
roadmap inspiration: when looking for the next feature, check here first —
some features are one protocol method away.

**Baseline:** bark-ffi-bindings **v0.25.0** (bark **v0.7.1**), pinned to
`master` @ `157b0fc`. Compared against `Shared/Data/BarkWalletProtocol.swift`
and actual `BarkWalletFFI` usage on 2026-09-26.

**Maintenance:** on every bindings bump, diff the new `WalletProtocol` in the
package checkout against the previous version (the DerivedData checkout at
`SourcePackages/checkouts/bark-ffi-bindings` has the full git history — diff
the release commits) and add new methods here. When an item is adopted, move
it to the Adopted-since list at the bottom with the date. Sibling doc:
`Bark_Bindings_Feedback.md` (things bark should change; this doc is things
*we* haven't used yet).

---

## New in v0.25.0 (bark v0.7.1)

Theme: "stop guessing" — three signatures changed, nothing was added. Full
diff and repo impact in `Migrations/Bark-0.24.0-to-0.25.0/`. All three
changes were adopted at the bump (see Adopted-since); **nothing from this
release is unadopted.** For the record, the one knob we deliberately don't
use:

### `drainExits(… drainAll: true …)` — sweep every claimable exit

The app always passes an explicit id list with `drainAll: false`
(`ExitClaimSequence`, pinned by `ExitClaimSequenceTests`). A sweep would let
bark choose the set, and `ExitClaimTransaction` still doesn't report which
ids ended up in the PSBT, so we'd lose the claim-tx ↔ VTXO link that
`recordClaim` persists. Not a feature target; recorded so nobody "adopts"
it as a simplification.

## New in v0.24.0 (bark v0.7.1)

Theme: the VTXO key gap limit became configurable (hardcoded 50 →
`Config.vtxoKeyGapLimit`, default 250). Full diff and repo impact in
`Migrations/Bark-0.23.0-to-0.24.0/`. Adopted immediately: the
`recoverVtxos(vtxoIds:gapLimit:)` override (widened `foreign`-ids retry in
the import recovery path, 2026-09-17 — see Adopted-since). Unadopted:

### `importVtxos(encodedVtxos:args:) -> [String]` — batch VTXO import

Imports several VTXOs under a single key scan and a single write (not just a
loop over `importVtxo`). Returns the ids now held — stored by this call or
already present — so a failed batch is retryable. One failure discards the
whole batch unless `args.allowPartial`. No adoption target exists:
`WalletManager.importVtxo` currently has zero callers. Adopt when a
multi-VTXO import feature appears (e.g. mailbox batch receive); the
kept-ids return plus `allowPartial: true` is the natural retry contract.

### `ImportVtxoArgs` knobs on `importVtxo` (all fields defaulted)

`gapLimit: UInt32?` (per-call override of the configured scan limit),
`skipStatusCheck: Bool` (skip the per-VTXO server state check — faster but
can leave spent VTXOs marked spendable), `allowPartial: Bool` (batch-only,
see above). The app's `importVtxo` wrapper passes none of these; mirror them
onto `BarkWalletProtocol` when the first real caller needs a non-default.

### `defaultVtxoKeyGapLimit() -> UInt32` / `maxVtxoKeyGapLimit() -> UInt32`

Free functions returning the default (250) and the cap (100_000; higher
values are rejected at wallet open/create — "an unbounded limit is unbounded
work"). `maxVtxoKeyGapLimit()` is adopted by the widened foreign retry;
`defaultVtxoKeyGapLimit()` remains unused — natural validation bound if a
user-configurable gap limit ever ships in settings.

---

## New in v0.23.0 (bark v0.7.0)

Catch-up entry (this doc was not updated at the 0.23 bump on 2026-09-08).
Additive lifecycle/recovery/exit-fee surface; full diff in
`Migrations/Bark-0.19.0-to-0.23.0/01-api-changes.md`. Adopted at the bump:
`stopDaemonWait()` (all shutdown paths). Still unadopted — tracked as
checklist items under "Bark 0.23 Migration" in `Open_Follow_Ups.md`:

- **`OnchainWallet.initialScan(birthdayHeight:)`** — recovers pre-existing
  onchain history on seed import; `sync()` alone never finds it.
- **`estimateEmergencyExitFee(...)`** — exit pre-flight showing broadcast vs
  claim fees; `fundable == false` should block/warn. Slow (syncs first).
- **`recoveryStatus()`** — distinguishes a failed recovery scan from one that
  never ran; the import path still infers from `recoveryReport()` nil-ness.
- **`RoundState.state: RoundFlowKind` / `scheduledHeight`** — richer round
  progress than the `ongoing` bool the app reads today.
- **Externally funded board** (`boardFundingAddress` / `boardPsbt`) and
  **`OnchainWallet.evictTx(txid:)`** — no current feature target.

---

## 0. New in v0.19.0

No API surface change — the generated `Bark.swift` diff is doc-comment-only.
The documented drop behavior of `Wallet` changed: dropping the object now
shuts down the whole daemon (v0.18.0 only cancelled the mailbox processor
task). Nothing to adopt; lifetime audit on 2026-08-23 confirmed every drop
site already calls `stopDaemon()` (via `shutdownWallet()`) first, and
`BarkWalletFFI.importWallet` gained the same shutdown-before-replace guard
as `createWallet` to keep it that way.

---

## 1. New in v0.18.0

The v0.17.0 → v0.18.0 bump was purely additive: three new wallet methods and
their supporting types. Nothing was removed or changed.

### 1.1 `cancelExit(vtxoId:) -> ExitCancelResult` — cancel a unilateral exit

Cancels a not-yet-broadcast exit. Idempotent (`canceled == true` even if it
was already cancelled). On `canceled == false`, `reason: ExitCancelFailure`
is one of `.notExiting`, `.tooLate(state: ExitStateKind)` (past the abortable
window), `.alreadyBroadcast(txid:)`. Genuine faults (db, chain source) still
throw. Ships with the new `ExitStateKind` enum — a payload-free discriminator
(`start … claimed, vtxoAlreadySpent, canceled`) that mirrors our
`ParsedExitState` case list exactly (minus our `unparsed` fallback).

This is the API our `ParsedExitState.canceled` doc comment was waiting for.
Feature implications:

- **Escape hatch for fee-blocked exits** (the `Exit_Blocked_State.md`
  feature): blocked exits are currently surfaced with no way out. A "Cancel
  exit" action is the natural remedy; `.tooLate` / `.alreadyBroadcast` map
  cleanly to "can't cancel anymore" messaging.
- **Live Activity gap**: the `ExitState` enum in
  `ExitProgressActivityAttributes.swift` has no `canceled` /
  `vtxoAlreadySpent` cases. An in-app cancel must end the activity or show a
  terminal state, or it displays a stale in-flight exit.
- **§1.4 date-bump exposure**: upstream bark still re-finishes cancelled-exit
  movements on every sync (`Bark_Bindings_Feedback.md` §1.4). Before shipping
  a cancel button, verify the `TransactionUpsertDateFreeze` workaround covers
  explicit `canceled`, not just `vtxoAlreadySpent`.
- **`PersistentExitCache`**: bark purges claimed exits from `getExitVtxos()`;
  check whether cancelled exits are purged too, and snapshot at cancel time
  if so.
- **Stuck-wallet probe**: on the stuck signet wallet (exit txs bark claims
  broadcast but that don't exist on the network), `cancelExit` would likely
  answer `.alreadyBroadcast(txid:)` from bark's belief — useful evidence for
  the upstream report.

### 1.2 `lockVtxos(vtxoIds:holder:)` / `unlockVtxos(vtxoIds:expectedHolder:)`

Manual VTXO locking (the `VtxoLockHolder` type existed since v0.17; only the
methods are new). No current call site, deliberately deferred — every
protocol method costs a mock stub.

Future use worth remembering: §1.4 documents exits self-cancelling as
`vtxoAlreadySpent` because a background refresh spent the VTXO first. Locking
VTXOs the moment the user enters an exit (or send) selection flow, unlocking
on completion/abandon, is exactly the mechanism to prevent that race.

### 1.3 `startExitForVtxosIncludingNonStandard(vtxoIds:)`

Same shape as `startExitForVtxos`, but includes VTXOs the standard path
skips. No doc comment ships in any generated binding, so the precise meaning
of "non-standard" is unstated; presumably VTXO policies/types the normal exit
path filters out. The app has no non-standard-VTXO concept anywhere. Adopt
only when a concrete need appears — e.g. a stuck wallet whose VTXOs the
standard exit path refuses.

---

## 2. Pre-existing, never adopted

Methods present in the bindings before v0.18.0 that neither
`BarkWalletProtocol` exposes nor `BarkWalletFFI` uses internally.

### Visibility of in-flight operations

- **`pendingBoards() -> [PendingBoard]`** / **`pendingBoardVtxos() -> [Vtxo]`**
  — boards in flight. Today a board is invisible between initiation and
  confirmation; Activity/Data views could show it as a pending row.
- **`pendingLightningSends() -> [LightningSend]`** /
  **`pendingLightningSendVtxos() -> [Vtxo]`** — in-flight lightning sends.
  We only surface the failure end (`stuckFailedLightningSends`); the happy
  path in progress is invisible.
- ~~**`pendingRoundInputVtxos() -> [Vtxo]`**~~ — adopted 2026-09-21, see §4.
  Remaining idea from this entry: explaining "missing" balance in the UI
  while a round is in progress (balance dips are currently unexplained).

### History & contacts

- **`historyByPaymentMethod(paymentMethodType:paymentMethodValue:) ->
  [Movement]`** — movement history filtered by payment method. Natural fit
  for the Contacts feature: a contact detail view could show the payment
  history with that lightning address / ark address without us filtering
  client-side.

### Receive flows

- **`bolt11InvoiceForAddress(amountSats:claimDestination:description:token:)`**
  — a BOLT11 invoice whose claim goes to a *different* ark address. Enables
  receive-on-behalf flows: generate an invoice that pays directly into
  another wallet/device (multi-device setups, send-a-request-to-be-paid for
  a contact).

### Offboarding

- **`offboardAll(bitcoinAddress:) -> OffboardResult`** +
  **`estimateOffboardAllFee(address:)`** — empty the entire offchain balance
  to an onchain address in one call. Natural fit for a "cash out" feature and
  for the wallet-deletion flow (the VTXO-expiry follow-ups in
  `Open_Follow_Ups.md` want a deletion warning about forfeitable offchain
  balance; "offboard everything first" is the actionable remedy).

### Maintenance & scheduling

- **`refreshVtxosScheduled(vtxoIds:scheduledHeight:) -> RoundState?`** —
  schedule a refresh at a future block height. Pairs with the Background
  Execution plan: instead of hoping a BGTask lands before expiry, register
  the refresh with the server at a chosen height.

### Validation & utilities

- **`validateArkoorAddress(address:) -> Bool`** — FFI-backed ark address
  validation; could back/replace parts of our own `AddressValidator` for ark
  addresses in the Send flow.
- **`signExitClaimInputs(psbtBase64:)`** — sign a custom exit-claim PSBT.
  `drainExits` covers the whole claim path today; only needed if we ever
  build custom claim transactions (e.g. batching with other outputs).
- **`fingerprint() -> String`** — wallet fingerprint; cheap addition to
  Settings/debug info for support and multi-device disambiguation.
- **`peekAddress(index:)`** — inspect a derivation index without revealing
  it. Relevant to the claimed-exit-funds-invisible-after-import follow-up
  (burned derivation indexes): a diagnostic could peek indexes past the gap
  limit without advancing state.

---

## 3. Used internally, but not on `BarkWalletProtocol`

These are adopted (called by `BarkWalletFFI`) but invisible to the protocol,
so they can't be mocked or exercised by protocol-level tests. Listed so
nobody re-discovers them as "missing":

| Binding method | Where used |
| --- | --- |
| `maintenance()` | `BarkWalletFFI+WalletCreation.swift` (last-resort diagnostic) |
| `recoverVtxos(vtxoIds:gapLimit:)` / `recoveryReport()` | `BarkWalletFFI+WalletCreation.swift` (import recovery scan; widened `foreign` retry since v0.24) |
| `maxVtxoKeyGapLimit()` | `BarkWalletFFI+WalletCreation.swift` (widened retry's gap limit) |
| `refreshVtxos(vtxoIds:)` | `BarkWalletFFI+VTXO.swift` |
| `offboardVtxos(vtxoIds:bitcoinAddress:)` | `BarkWalletFFI+Exit.swift` |
| `tryClaimAllLightningReceives(wait:)` | `BarkWalletFFI+Lightning.swift` |
| `properties()` | `BarkWalletFFI+WalletCreation.swift` |
| `newAddressWithIndex()` | `BarkWalletFFI+Balance.swift` |
| `estimateSendOnchainFee(address:amountSats:)` | `BarkWalletFFI+Fees.swift` |

If a feature needs to drive one of these through `WalletManager` or tests,
promote it onto the protocol first (per the convention: the protocol mirrors
the FFI, policy lives in `WalletManager`).

---

## 4. Adopted since this record started

(Move items here with the date when they land on the protocol / in a feature.)

- **`recoverVtxos` `gapLimit:` override + `maxVtxoKeyGapLimit()`** —
  2026-09-17, same day as the v0.24 bump: the import recovery path now
  retries `foreign`-bucketed ids with the widest accepted gap limit
  (`ImportRecoveryLogic.retryPasses`, pinned by `ImportRecoveryLogicTests`).
  Internal to `BarkWalletFFI`, not on the protocol.
- **`pendingRoundInputVtxos()`** — 2026-09-21, on the protocol
  (`BarkWalletFFI+Rounds.swift`). Belt-and-braces half of the
  "being refreshed" signal in `WalletManager.vtxoIdsBeingRefreshed()`
  (Guard C, `Refresh_Deduplication.md`); note it is **empty** for delegated
  refreshes until the server issues the round — the pending refresh
  movement covers that window.
- **`mailboxAuthorization(expirySecs:)`** — 2026-09-26, same day as the
  v0.25 bump, on the protocol. Our own ask: the lifetime is now
  `RelayRegistrationService.mailboxAuthorizationExpirySecs` (30 days),
  renewed at mid-life; registration state is persisted across launches
  (`PersistedRegistration`, pinned by `RelayRegistrationRenewalTests` /
  `RelayRegistrationPersistenceTests`).
- **`drainExits(vtxoIds:drainAll:…)`** — 2026-09-26, on the protocol and
  `ExitClaimWallet`; always `drainAll: false` (see v0.25 section above).
- **`LightningReceive.amountSats: UInt64?`** — 2026-09-26; no UI surface
  today (debug reads only), fixtures updated.
