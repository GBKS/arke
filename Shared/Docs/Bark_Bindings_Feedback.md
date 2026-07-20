# Bark & Bark FFI Bindings — Integration Feedback from Arké

**Audience:** Second team (bark + bark-ffi-bindings)
**From:** Arké — iOS/macOS wallet built on the Swift bindings
**Versions reviewed:** bark 0.11.3 bindings (bark v0.3.0), with migration history back to bindings 0.6.3
**Date:** July 2026

Arké exercises nearly the entire binding surface: arkoor sends, boarding,
offboarding, unilateral exits (including fee-blocked recovery UX), BOLT11/
BOLT12/LNURL, movements, rounds, the notification stream, and the daemon.
This document collects everything we've had to work around, ordered by the
cost it imposes on us. Each item includes where the workaround lives in our
codebase, so claims are verifiable.

Short version: **the biggest wins are all the same fix — let typed data
cross the FFI instead of strings.** Where you've done this (`FeeEstimate`,
`LightningSendStatus`, `Movement`), integration is easy. Where strings leak
through (exit states, errors, VTXO states), we've built fragile parsers that
break silently on every release.

---

## Priority 1 — costs us correctness

### 1.1 Exit state crosses the FFI as Rust `Debug` strings

`ExitTransactionStatus.state` and `.history` are `format!("{:?}", …)` output:

```
"Processing(ExitProcessingState { tip_height: 301492, transactions: [ExitTx { txid: …, status: AwaitingInputConfirmation { txids: {…} } }] })"
```

We need the data inside — tip heights, claimable heights, txids, CPFP child
txids and origins, block refs — to drive the exit progress UI, fee
attribution, and transaction linking. So we maintain a **~540-line parser**
(`Shared/Data/ExitStatus/ExitStatusParser.swift`) that reverse-engineers Rust
struct Debug syntax with regexes and brace counting, plus a test suite
(`Tests/Shared/ExitStatusParserTests.swift`) that exists mainly to detect
when your Debug format changes.

It does change. In 0.11, `BroadcastWithCpfp` was renamed to
`AwaitingConfirmation` and `AwaitingCpfpBroadcast` was added. No compile
error, no runtime error — exits just silently stopped parsing until we
diffed the strings by hand. This is the unilateral exit path, i.e. exactly
the code that must work when the user is already in a bad situation.

**Ask:** expose the exit state machine as UniFFI enums/records. Sketch:

```
[Enum]
interface ExitState {
    Start(u32 tip_height);
    Processing(u32 tip_height, sequence<ExitTx> transactions);
    AwaitingDelta(u32 tip_height, BlockRef confirmed_block, u32 claimable_height);
    Claimable(u32 tip_height, BlockRef claimable_since, BlockRef? last_scanned);
    ClaimInProgress(u32 tip_height, BlockRef claimable_since, string claim_txid);
    Claimed(u32 tip_height, string txid, BlockRef block);
    VtxoAlreadySpent(u32 tip_height);
};
```

Same for `ExitTx.status` (incl. CPFP child txid and `TxOrigin`
Wallet/Mempool/Block — we need the origin to distinguish user-funded CPFP
children from third-party anchor spends for fee attribution). If typed enums
are too much churn, versioned JSON with a published schema would still be a
huge improvement over `Debug` output.

`ExitProgressStatus.state` (also a bare `String`) should get the same
treatment.

### 1.2 The error type collapsed to a single string case

Bindings 0.10 had `BarkError` with 14 typed cases. 0.11 has:

```swift
public enum Error { case Inner(message: String) }
```

We now make **product decisions by substring-matching undocumented Display
strings**:

| String we match | What it drives | Where |
|---|---|---|
| `"Insufficient Confirmed Funds"` | Entire "exit blocked, add onchain funds" feature | `Shared/Data/ExitStatus/ExitBlockedInfo.swift` |
| `"Claim Fee Exceeds Output"` | "Waiting for lower fees" exit state | same |
| `"connect"` / `"server"` | Connection-failure classification | `BarkWalletFFI+Balance.swift` |
| `"DataAlreadyExists"` | Open-vs-create disambiguation | `BarkWalletFFI+WalletLifecycle.swift` |
| `"bad-txns-inputs-missingorspent"` | Exit failure diagnostics | `BarkWalletFFI+Exit.swift` |

Any rewording upstream silently breaks user-facing behavior, and we have no
way to know the full set of messages we should handle.

**Ask:** restore typed error cases (or at minimum stable machine-readable
error codes) with structured payloads; keep the prose for humans. Two
adjacent bugs:

- The bare name `Error` shadows `Swift.Error` in every `import Bark` file,
  forcing `Swift.Error` / `Bark.Error` qualification project-wide. Please
  rename (`BarkError` was fine).
- `errorDescription` is `String(reflecting: self)`, so
  `.localizedDescription` yields `Bark.Error.Inner(message: "…")` instead of
  the message. Clients must pattern-match just to get clean text.

### 1.3 Fund-moving operations return no correlation handle

`sendArkoorPayment` returns `Void` as of 0.11 (previously at least a round
id). No send/pay/board call tells us which `Movement` it created.

Consequence: to attach the user's own note/contact/tags to the payment they
just sent, we built a heuristic matching subsystem
(`Shared/Models/PendingPaymentMetadata.swift`,
`TransactionService+PendingMetadata.swift`, plus its own test suite): match
by payment hash when Lightning, else by destination address + amount + time
window, with mark-as-matched bookkeeping to avoid double-application. That is
a lot of machinery — with inherent misattribution risk for repeated
same-amount payments — to answer *"which transaction did I just create?"*

**Ask:** return the created movement id from every operation that produces a
movement, and/or accept a client-supplied idempotency/metadata key.
`Movement.metadataJson` already exists — a client-writable field there
(`wallet.setMovementMetadata(id, json)` or a parameter on send) would delete
this entire subsystem.

---

### 1.4 Cancelled exit movements are re-finished on every sync

Found in the field (2026-07-19), verified against tag `bark-0.3.0`. When an
exit self-cancels (`VtxoAlreadySpent`, e.g. a refresh spent the VTXO first),
the movement's `completed_at` keeps creeping forward forever:

- `ExitState::progress` runs the "VTXO spent from under us" pre-check before
  matching on the current state (`bark/src/exit/progress/states.rs`, the
  guard at the top of `impl ExitStateProgress for ExitState`). The guard
  fires when `!self.warrants_exited_vtxo()` and the VTXO is `Spent` — and
  `VtxoAlreadySpent::warrants_exited_vtxo()` is `false`, so an exit already
  in the terminal `VtxoAlreadySpent` state re-enters the guard on **every**
  progress/sync call and returns a **fresh** `VtxoAlreadySpent` carrying the
  current tip height.
- `Exit::sync` decides `state_changed` by full state inequality
  (`exit.state() != &pre_state`), so a tip-height change alone counts as a
  state change.
- `reconcile_vtxo_and_movement` then calls
  `finish_movement(movement_id, Canceled)` again, and `finish_movement`
  unconditionally sets `completed_at = now()` and dispatches
  `movementUpdated`.

Consequence: any client sorting history by completion date shows cancelled
exits pinned to the top after every sync in which the chain tip advanced,
plus `movementUpdated` notification spam for long-dead movements. We now
freeze dates client-side for already-cancelled movements
(`Shared/Services/TransactionService/TransactionService+Upsert.swift`), so
our history stays correct only as long as that workaround holds.

**Ask:** any one of these stops the churn — match `VtxoAlreadySpent` before
the spent-guard (it's terminal), compare state *kinds* rather than full state
values for `state_changed`, or make `finish_movement` idempotent for
already-finished movements.

---

## Priority 2 — costs us reliability and battery

### 2.1 Event coverage is thin, so we poll for everything else

The notification stream emits three events: `movementCreated`,
`movementUpdated`, `channelLagging`. Everything else is polled. Our current
standing inventory on iOS:

| Poller | Interval | Exists because there's no event for… |
|---|---|---|
| `LightningClaimService` | 30 s | a receive becoming claimable |
| `RoundProgressionService` | 60 s | round progress / completion |
| `ExitProgressionService` | 5 min | exit state transitions |
| `VTXORefreshService` | 60 min | approaching refresh/expiry heights |
| `pollLightningPaymentStatus` (ad hoc) | 1 s × 60 | send settlement after `.inProgress` |
| `waitForServerConnection` (ad hoc) | 1 s, 20 s timeout | connection state changes |

That's four permanent timers plus two ad-hoc loops on a phone, all doing
FFI round-trips that are usually no-ops. Events for **exit state
transitions, round phase changes, lightning receive claimable, lightning
send settled/failed, connection state, and new chain tip** would let us
delete most of this.

**Stream ergonomics:** the pull model
(`nextNotification()` / `cancelNextNotificationWait()`) forces every client
to hand-roll the listen loop, reconnect-with-backoff, and error counting
(`Shared/Services/WalletNotificationService.swift`). Because the stream has
no documented liveness guarantees, we also run a health-check timer whose
only job is to detect a silently dead stream. Documented semantics (does it
ever end? can it stall?) — or a callback-interface alternative — would help.

### 2.2 No deterministic wallet close

Cleanup happens on Rust `Drop`. Our shutdown
(`BarkWalletFFI+WalletLifecycle.swift`, `shutdownWallet()`) sleeps 500 ms
**three separate times** hoping SQLite handles and the datadir lock are
released before we back up or delete files. That's a race, not a protocol.

**Ask:** an explicit `wallet.close()` that flushes and returns only when the
datadir lock is released. (Related: docs say the daemon "is stopped
automatically when the wallet is dropped" — but Swift clients have no
deterministic drop, so `stopDaemon()` + `close()` is the path that matters.)

### 2.3 No "does a wallet exist here?" API

We probe filenames (`db.sqlite`, `bark.sqlite`, …) to decide whether to show
onboarding. The 0.11 rename of `bark.sqlite` → `db.sqlite` broke that
detection and nearly caused a restore-over-fresh-wallet data loss
(`Shared/Services/WalletBackupService.swift` still carries the migration
shim).

**Ask:** `walletExists(datadir)` or `datadirInfo(datadir)` returning
presence, schema version, and network. And please treat database filename
changes as documented breaking changes.

### 2.4 Connection state is not queryable or observable

`arkInfo()` returning `nil` is the only "am I connected?" signal, and it
conflates "not connected" with other failures. After `Wallet.open` we poll
it in a loop to know when the wallet is usable.

**Ask:** a `connectionStatus()` query plus a status-change event.

### 2.5 `OnchainWallet` exposes no transaction history

To show onchain history we run a **second, parallel BDK wallet**
(`Shared/Data/BDKTransactionReader.swift`) on the same descriptors, purely
read-only. Double sync traffic, double storage, and a standing risk of
descriptor drift between your BDK instance and ours.

**Ask:** `OnchainWallet.listTransactions()` (txid, sent, received, fee,
confirmation block/time is all we need).

### 2.6 `forceRescan` was removed with no replacement

0.11 dropped `forceRescan` from creation, and `WalletOpenArgs` has no rescan
flag. If onchain state is ever wrong there is now no recovery API short of
deleting the datadir.

---

## Priority 3 — ergonomics and polish

**Lightning**

- `LightningSend` has no `paymentHash` field. After
  `.inProgress(send:)` we parse the payment hash **out of the BOLT11 string
  ourselves** (`LightningInvoiceParser.extractPaymentHash`) to poll
  settlement — and for BOLT12 there is no invoice to parse. Please add the
  hash to `LightningSend`.
- `LightningSendStatus` has no `failed` case (`unknown` / `inProgress` /
  `paid`). Failure is only discoverable via `stuckFailedLightningSends()` or
  timing out a poll loop. A `failed(reason)` case would let us show honest
  status.
- `LightningReceive` encodes status as two booleans (`hasHtlcVtxos`,
  `preimageRevealed`) that every client must recombine into
  waiting/claimable/claimed. An explicit status enum would prevent divergent
  interpretations.
- `wait: true` variants have no timeout/cancellation parameter, which makes
  them risky to call from mobile lifecycles; we mostly use `wait: false` +
  our own polling as a result.

**Rounds**

- `RoundState` is `{ id: UInt32, ongoing: Bool }`. When a round stalls we
  can tell the user nothing — our debug helper literally prints a list of
  guesses (`Shared/Helpers/RoundStateDebugger.swift`). Phase, attempt count,
  and next-attempt time would make round UX possible.

**Types**

- `Vtxo.state` and `Vtxo.kind` are bare strings (`"locked"`, `"pubkey"`, …)
  with no documented value set — enums, please. (Recent additions
  `exitDepth` / `exitTxWeightWu` are great, and are typed — thank you.)
- `Movement.status`, `subsystemName`, `subsystemKind`: same.
- `Movement.createdAt/updatedAt/completedAt` are strings; timestamps or at
  least a documented format would remove parsing guesswork.
- `getExitStatus(includeTransactions: true)` returns only a
  `transactionCount` — the transactions themselves aren't accessible.

**Behavior**

- Without an explicitly configured fallback fee rate, bark seeds its fee
  cache at 1 sat/vB and fee estimation **errors whenever Esplora is
  unreachable**. We hardcode a 10 sat/vB fallback
  (`BarkWalletFFI.defaultFallbackFeeRateSatPerVb`) to survive offline
  moments. A sane built-in fallback (or documented offline behavior) would
  be safer for clients that don't discover this the hard way.

---

## Release process

0.10 → 0.11 landed the create/open restructure, `Config.network` removal,
the error-type collapse, `sendArkoorPayment`'s return-type change, the DB
filename rename, *and* the exit-state renames in one release — with no
upstream migration guide. We wrote our own binding-diff documents to migrate
(`Shared/Docs/Migrations/…`), and had to do the same for 0.6.3 → 0.7.0.
A short upstream CHANGELOG with breaking changes flagged, per release, would
meaningfully cut integration cost for every binding consumer.

---

## What's working well

Credit where due — these made integration genuinely pleasant, and are the
pattern we're asking you to extend everywhere:

- **`FeeEstimate`** (gross/fee/net/vtxosSpent) — exactly the right shape.
- **`LightningSendStatus`** replacing bare strings in 0.7.0 — the error
  collapse in 0.11 went the opposite direction; 0.7.0 was the right one.
- **`Movement`** carrying `paymentHash` / `lightningInvoice` /
  `lightningOffer` since 0.10.
- **`runDaemon` / `stopDaemon`** — good fit for mobile foreground/background.
- **`barkAttachOSLogger`** — bark's Rust logs landing in the unified log
  under `tech.second.bark` has been invaluable for field debugging.
- **Doc comments** on newer fields (`exitDepth`, `exitTxWeightWu`,
  `LightningSend.hasFailedRevocation`) are exactly the right level of detail.

## Summary of asks

| # | Ask | Deletes on our side |
|---|---|---|
| 1 | Typed exit states (and `ExitTx` statuses) | 540-line Debug-string parser + its test suite |
| 2 | Typed errors / stable error codes; rename `Error` | All substring-based error classification |
| 3 | Movement id (or metadata key) returned from sends | Heuristic payment-matching subsystem |
| 4 | Events: exit/round/lightning/connection/tip | 4 standing timers + 2 ad-hoc poll loops |
| 5 | `wallet.close()` with deterministic resource release | Three 500 ms shutdown sleeps (a race) |
| 6 | `walletExists()` / datadir info | Filename probing (data-loss near-miss in 0.11) |
| 7 | `OnchainWallet.listTransactions()` | Entire parallel read-only BDK wallet |
| 8 | `paymentHash` on `LightningSend`; `failed` status case | Client-side BOLT11 parsing; poll-timeout guessing |
| 9 | Richer `RoundState`; enum `Vtxo`/`Movement` fields | Guesswork UI and undocumented string matching |
| 10 | Upstream migration notes per release | Hand-written binding-diff docs |
| 11 | Stop re-finishing cancelled exit movements (`completed_at` churn) | Date-freeze workaround in transaction upsert |
