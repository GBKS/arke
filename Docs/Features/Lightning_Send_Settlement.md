# Lightning Send Settlement (`wait: false`)

**Status:** 🔨 BUILT + REVIEWED 2026-11-18. Step 0 (bindings bump) built,
full mobile suite 751/751 before Step 1. Step 1 built; fault-class pass §9
(one CONFIRMED finding fixed the same day); post-review full mobile suite
764/764 (107 suites, `LightningSettlementTests` 13 of them); de/ja/zh-Hant
for the four new keys applied, lint clean. Device check §5j: all four formats and the refunded failure passed on
mainnet 2026-11-18 (§9a; the failure reported, not logged). Left: a
first-after-launch send with a log (diagnostic for the slow first send,
not a gate), and the bump's signet onchain check (§4.5), of which only the exit's
progress to confirmation is still open (migration README status). Reference implementation: PR #11 on GitHub
(`lightning-send-wait-false`), rewritten here in the repo's workflow rather
than merged (agreed with its author 2026-11-18).

## 1. Problem

An outside report (2026-11-17) traced slow Lightning deliveries to three
factors. Two are server-side (bark-to-server handoff with several round
trips, Lightning routing). The third is ours: Arké pays with `wait: true`,
bark then polls the server every 2 s and that sleep does not wake on the
mailbox's "payment succeeded" message, and Arké runs its full refresh before
it shows "Sent". Measured on the PR branch: "Sent" trailed bark's own
knowledge by 0.3 to 2.0 s before, 0.02 to 0.06 s after.

## 2. Today's behaviour (verified 2026-11-18 unless labelled)

- **V1 verified.** All four pay calls use `wait: true`:
  `WalletOperationsService.payLightningInvoice` and the three direct calls
  in `WalletManager+Lightning` (`payLightningAddress`, `payLnurl`,
  `payLightningOffer`).
- **V2 verified.** Only the invoice path awaits the transaction-completed
  callback (`refreshAfterVTXOChange`, backup transaction count) before it
  returns. The other three formats never run that callback.
- **V3 derived, not reproduced.** A pay call that returns `.unknown` is only
  logged (`logLightningPaymentStatus`); `executeSend` returns normally and
  `SendModalView.executeSend` sets `.success`, so a failed and refunded
  payment reads "Payment Sent". That a refunded failure returns `.unknown`
  follows from F1 and F6 below.
- **V4 verified.** `BarkWalletFFI.payLightningInvoice` starts
  `pollLightningPaymentStatus` on every `.inProgress` return: a 1 s loop of
  up to 60 `checkLightningPayment(wait: false)` calls. That FFI call
  *drives* the action (`drive_action`, `UntilParkOrDone`); it is not a
  read.
- **V5 verified.** `SendModalView` enforces an 800 ms minimum "Sending"
  display, which caps the visible gain.
- **V6 verified.** `WalletOperationsService.isAnyTransactionRunning` and
  `isAnyLightningOperationRunning` have no readers outside the service.

## 3. bark facts relied on

Read at `~/workspace/bark` tag `bark-0.8.1` and `~/workspace/bark-ffi`
revision `ca8f174` (the crate the v0.27.0 bindings pin). The 0.26→0.27
migration README repeats the ones that count as bark facts.

- **F1 verified.** `Wallet::lightning_send_state` (`bark/src/lightning/pay.rs`)
  returns `Paid` if the paid-invoice record exists, else `InProgress` if the
  send's checkpoint exists, else `Unknown`. The binding's
  `lightningSendState` never drives the action.
- **F2 verified (read); the race itself derived.** Settlement writes the paid
  record, finishes the movement, then removes the checkpoint
  (`settle_lightning_send_payment`, `settle_lightning_send_with_preimage`).
  A read between bark's two lookups can return `Unknown` once for a paid
  send.
- **F3 verified.** `wait: true` is `DriveMode::UntilDone`: the pending poll
  sleeps `PAYMENT_PENDING_POLL_INTERVAL` (2 s) and retryable errors sleep
  with quadratic backoff inside the call. `wait: false` is
  `UntilParkOrDone`: `run_action_loop` saves the checkpoint on
  `Advance::Retry` and returns the error. The HTLC cosign is
  `retry_unless_rejected`, so a network error after `checkpoint.create`
  leaves a pending send that the daemon finishes; an error before it
  (`start_lightning_send`: server connect, chain tip, VTXO selection) leaves
  nothing.
- **F4 verified.** bark-ffi's `pay_lightning_*` return
  `lightning_send_state(invoice.payment_hash())` after the drive. The Swift
  `.unknown` case carries no hash, so an `.unknown` straight from
  `payLightningAddress` / `payLnurl` / `payLightningOffer` cannot be read
  again (the invoice path parses its own hash). Bindings ask, see §8.
- **F5 verified.** bark 0.8.1's `LightningSend::advance` settles from the
  stored paid record first, and `mailbox.rs` calls
  `settle_lightning_send_with_preimage` on the server's message. This is
  the fix `wait: false` needs (CHANGELOG 0.8.1, MR 2663).
- **F6 verified (read).** A failed payment revokes its HTLCs and ends `Done`
  (checkpoint removed → `Unknown`). A revocation that keeps failing stays
  checkpointed and is reported with `hasFailedRevocation`.
- **F7 verified.** Generated `Bark.swift` diff v0.26.1 → v0.27.0: `expirySecs:
  UInt64? = nil` added to `bolt11Invoice` and `bolt11InvoiceForAddress`;
  new `presignEmergencyExit`, `remainingExitTransactions` and their types;
  recovery types reordered, not removed. No app code change. The binary
  changes: bark-ffi `4a1c1c0` → `ca8f174`, uniffi 0.31.1 → 0.31.2, bark
  0.8.0 → 0.8.1 (bdk_wallet 3.2.0, marked BREAKING in bark's onchain
  wallet).
- **F8 assumed, gates §5d.** With the FFI poll of V4 removed, bark's daemon
  (playbook B6) and mailbox are the only drivers of a parked send. If a
  `wait: false` send does not settle on device without that poll, keep a
  slow fallback driver instead of deleting it. Bound read by the review
  (bark-0.8.1 `daemon/mod.rs`): the daemon re-drives pending sends once per
  `sync_interval` (app passes nil, bark default 60 s) and only while it
  considers itself connected, so on the transient-error path, or with the
  mailbox stream down, "Sent" can trail settlement by up to about a minute
  where `wait: true` retried in-call at 1, 4 and 9 s.

## 4. Step 0 — bindings bump (DECIDED 2026-11-18: its own commit, ahead of the behaviour change)

1. Christoph, in Xcode: Package Dependencies → `bark-ffi-bindings` → rule
   Revision `66d047f7ee08c2bca3675605ea7a88bc8b50adb3` (the commit behind
   tag `v0.27.0+bark-0.8.1`; today `4670c1ad…`). `Package.resolved` follows.
2. `Docs/Migrations/Bark-0.26.1-to-0.27.0/README.md`: F1–F7 above, the
   "not reviewed" list (bdk 3.2.0, rounds, Lightning receive, mailbox, exit
   presigning), playbook facts B1 and B6 re-verified at 0.8.1, B2/B3/B7/B8
   marked not re-verified.
3. `Bark_Bindings_Unadopted_API.md` baseline and the three new surfaces;
   `Setup.md` tag line; `Docs/README.md` version mention.
4. Build; full mobile suite once.
5. Signet device check (bdk 3.2.0): onchain send, board, refresh, Lightning
   receive and claim, exit progress. Owed before the bump counts as done.

## 5. Step 1 — behaviour change

a. **Protocol.** `pendingLightningSends() -> [LightningSend]` on
   `BarkWalletProtocol`, FFI and mock (mirrors the FFI; no policy).
b. **`LightningSettlement`** (`Shared/Services`, `nonisolated enum`): one
   function that takes the pay call's status, an optional known hash and a
   `readState` closure, polls `lightningSendState` every 100 ms and returns
   `.paid` or throws a typed `LightningSendFailure`:
   `.notSent` (refunded: `.unknown` twice, or a failed state), `.heldByServer`
   (`hasFailedRevocation`), `.outcomeUnknown` (hashless `.unknown`, F4),
   `.statusUnreadable` (read error). One `.unknown` is read again (F2). No
   upper bound: `wait: true` had none either; `retryForSecs` is the lever
   if one is wanted later.
c. **`WalletManager.payLightning`** wraps all four formats with
   `wait: false`. Snapshot `pendingLightningSends()` before a hashless call;
   on a pay-call error, wait for the one send that appeared (by hash for an
   invoice), otherwise rethrow (F3). The wait runs in its own task so a
   dismissed sheet does not drop it. The transaction-completed callback runs
   after settlement for all four formats (fixes V2) and after "Sent", in a
   detached task.
d. **Remove `pollLightningPaymentStatus`** from the FFI pay path (V4), gated
   by F8.
e. **Send modal.** `.notSent`, `.heldByServer` and `.statusUnreadable`
   render under the existing "Payment Failed" title with the messages in
   §6; `.outcomeUnknown` too until §7 is ruled.
f. **Strings** with `defaultValue:`; catalog pass after the build;
   translations through `Scripts/apply_translations.py`.
g. **Tests** (`Tests/Shared/LightningSettlementTests.swift`): decisions only:
   unknown once then paid, unknown twice, failed revocation, read error,
   hashless unknown, paid inside the pay call. `payLightning`'s error path
   with a test double conforming to `BarkWalletProtocol` inside the test
   target, not `MockBarkWallet`.
h. **Sweep.** `executeWithRetry` (send-max) retries any error whose text
   contains "insufficient" or "balance"; `.notSent`'s text contains
   "balance", so the loop now rethrows every `LightningSendFailure` before
   the text match (review F1, 2026-11-18; the first version of this line
   read only the "insufficient" half and said "covered").
   `IncrementalPaymentTestView_iOS` goes through `WalletManager`: covered.
   `MockBarkWallet.lightningSendState` and the FFI preview path return
   `.unknown` today and must report `.paid`, or DEBUG sends never end:
   covered in (a). Lightning receive `wait:` parameters: exempt, different
   state machine. `WalletNotificationService`: unchanged, movement events
   still refresh balances.
i. **Review.** Tier 1 money path: fault-class-reviewer pass over the Step 1
   range, then the full mobile suite.
j. **Device (mainnet, Christoph).** All four formats to "Sent"; one failure
   (an invoice no route can reach); time from tap to "Sent" against the
   `⚡ Lightning payment settled` log line; a send with the FFI poll gone
   settles (F8). The transient-error path (airplane mode during the
   handoff) is best effort.

## 6. Failure messages — DECIDED 2026-11-18

Title "Payment Failed" for the first two; the third renders under a fourth
modal state titled "Payment Not Confirmed" (§7, DECIDED).

| Case | Message |
|---|---|
| `.notSent` | "The payment did not go through. The amount is back in your balance." |
| `.heldByServer` | "The payment did not go through. The server still holds the amount; Arké keeps trying to get it back." |
| `.statusUnreadable` / `.outcomeUnknown` | "Arké could not confirm this payment. Check Activity before you pay again." |

Precedent: `SendError.paymentsOnchainSendUnsettled` and
`offboard_error_pending` already word a checkpointed-but-unfinished send as
"did not complete yet … the wallet finishes it on the next sync".

## 7. Rulings (DECIDED 2026-11-18)

- **Title for an unknown outcome:** a fourth modal state, title "Payment
  Not Confirmed", for `.outcomeUnknown` and `.statusUnreadable`. Part of
  Step 1 (§5e).
- **Mainnet Esplora default stays** `mempool.second.tech/api`. Instead, the
  Esplora URL becomes changeable in Settings for the built-in servers, so a
  nearer explorer (for example `mempool.space/api`) can be tried on real
  devices. Separate backlog item, Tier 3 Settings, after Step 1. Background
  that led here: presets resolve to the constant by id
  (`NetworkConfigPersistence.resolve`), the URL is handed to bark at every
  open and used by the fee estimator, exit diagnostics and the reachability
  probe; chain-source latency sits inside the Lightning handoff
  (`start_lightning_send` fetches the chain tip, the HTLC step the anchor
  transaction) but does not touch the server round trips. Unknowns that the
  trial is meant to answer: mempool.space's public rate limits against
  bark's gap-50 scans at launch, and whether its deployment serves Asia
  locally. From this Mac both explorers answer `/blocks/tip/hash` in about
  0.1 s.

### 7a. Esplora setting — design notes, PROPOSED 2026-11-18

- **Storage.** `resolve(id:stored:)` returns the preset and ignores the
  stored copy. Proposed: when the stored config has a preset id, return the
  preset with the stored `esploraURL` applied, so the override lives in the
  same persisted `NetworkConfig` blob, syncs through the iCloud KVS mirror
  like the rest of the network config (the one account-authoritative state
  class) and is wiped with it. No new key, `SharedStateWipeCoverage`
  unchanged; verify that claim against the inventory when building.
- **Effect.** bark reads the URL at open, so the change applies at the next
  launch; the row says so. No close-and-reopen flow.
- **UI.** A Settings row showing the current explorer, editing with the
  existing `ServerFormField`, the server sheet's `/blocks/tip/hash` probe
  before saving, and "Reset to Second's explorer".
- **Tests.** `resolve` with and without an override; the existing
  `NetworkConfigReconciliationTests` expectation stays.

## 8. Build record (2026-11-18)

- New: `Shared/Services/LightningSettlement.swift` (`LightningSendFailure`,
  `LightningSettlement.start` / `.wait`), `Tests/Shared/LightningSettlementTests.swift`.
- Changed: `WalletManager+Lightning` (`payLightning` wrapper, all four
  formats `wait: false`, refresh after settlement), `WalletOperationsService`
  (`wait: false`, no in-line refresh), `BarkWalletProtocol` + `BarkWalletFFI+Lightning`
  + `MockBarkWallet` (`pendingLightningSends`; preview and mock
  `lightningSendState` report `.paid`; `pollLightningPaymentStatus` removed),
  `SendModalState` (`.unconfirmed`), `SendModalView` (typed catch),
  `SendModalContentView` (title, message, buttons for the fourth state).
- Strings: `error_lightning_not_sent`, `error_lightning_held_by_server`,
  `error_lightning_not_confirmed`, `status_payment_not_confirmed`, extracted
  with values by the build; translations pending.
- Sweep (§5h) re-checked after building: `SendOperation_iOS` hands the
  `executeSend` closure to `SendModalView` unchanged, so the typed failure
  reaches the modal; `checkLightningPayment` keeps one caller, the FFI's own
  pass-through, after the poll's removal; `SendModalState` switches are all
  in `SendModalContentView`; the offboarding, boarding and refresh modals
  use their own state enums.

## 9. Review record (fault-class pass, 2026-11-18)

- **F1 CONFIRMED (class 5 and 2), fixed the same day.** Send-max retry loop
  would have retried a `.notSent` failure as a balance error; typed rethrow
  added in `executeWithRetry`. Rework ledger row.
- **F2 PLAUSIBLE (class 4), filed Tier 3 Send.** For address, LNURL and
  offer sends the common failure (server reports Failed on the first poll)
  revokes inside the pay call and returns a hashless `.unknown`, so it reads
  "Payment Not Confirmed" rather than "Payment Failed". Safe direction; the
  §6 message for a refund is unreachable for those formats until bindings
  ask 24 lands. Settled by one device send to an unreachable address and
  the `did not settle: outcomeUnknown` vs `notSent` log line.
- **F3 PLAUSIBLE (class 4), recorded under F8.** Transient-error and
  mailbox-down paths wait for the daemon's 60 s tick. Device check §5j
  decides whether a slow fallback driver comes back (PROPOSED, Tier 4 FFI).
- **F4 PLAUSIBLE (class 3, low).** No upper bound on the wait and no dismiss
  while "Sending"; same shape as `wait: true` while a driver runs, but with
  the daemon stopped the wait would never end. B6 mitigates; a run with the
  daemon stopped would settle it.
- **F5 exempt.** `.notSent` is wrong only on the `allowLightningSendToExit`
  path, which nothing in the app calls.
- Sound by the reviewer's reading: sheet dismissal mid-wait (uniffi calls
  are not cancellable, the settlement task is unstructured), wallet close
  mid-wait ends in `.statusUnreadable`, the refresh in a detached task
  (metadata matching tolerates either order), the hashless snapshot, scope
  (no new store writes).
- Not verified by anyone yet: everything on device (§5j), how often the
  server's first poll already says Failed, the server's `retry_for`
  default, and the report's claim that `wait: true` did not wake on the
  mailbox message (plausible: the drive holds the action lock across its
  sleeps).

## 9a. Device check progress (§5j)

- **2026-11-18, BOLT11 invoice to an Alby Hub node, mainnet, two sends.**
  First felt like about 8 s (no log), second snappy. Log of the second:
  the mailbox "send finished (success)" message arrived right after the
  pay call returned `.inProgress`, bark settled from it, and the app read
  `.paid` within the same second (`⚡ Lightning payment settled` at
  13:07:13 against the first in-handoff balance refresh at 13:07:11). The
  mailbox path of F8 is confirmed for the happy case, one data point. The
  post-settlement refresh ran after "Sent" as designed. Still owed: the
  other three formats, a failure, and a first-after-launch send with a log
  (the 8 s first send is unexplained; likely cold gRPC and Esplora
  connections plus first-time route finding on the receiving node).
- **2026-11-18, Lightning address (Wallet of Satoshi), mainnet.** Second
  format passed. Log: bark opened two cold TLS 1.3 connections in sequence
  before its handoff, `walletofsatoshi.com` for the LNURL metadata and
  `livingroomofsatoshi.com` for the invoice callback, both HTTP/1.1 with no
  session to resume; then the usual handoff, movement created about
  13:14:12, pay call returned about 13:14:13, mailbox success between
  13:14:13 and 13:14:15, `settled` read at 13:14:15. The gap between the
  mailbox success and our `.paid` read is inside that two-second window and
  not measurable from the export, so the settled log line now carries the
  wait duration in milliseconds. bark also logged "lnurl-pay invoice
  description hash does not commit to the endpoint metadata" for this
  endpoint; informational, the payment went through.
- **2026-11-18, BOLT12 offer (Phoenix iOS), mainnet.** Third format
  passed, the fastest of the three: movement created about 13:18:55, pay
  call returned with bark's "Paid invoice: lni1…" line and `.inProgress`
  at 13:18:57, mailbox success and our `.paid` read in the same second.
  The offer-to-invoice fetch before the movement is not measurable: no
  timestamped line falls in that window, and the export there is about
  2,000 lines of UIKit keyboard-layout noise (five `UIKBDynamicRenderFactory`
  warnings per keyboard frame). During the handoff the movement-triggered
  balance refreshes opened three resumed TLS sessions to the explorer and
  ran a full Esplora sync each ("Finished syncing with esplora"), which is
  the cost behind the Tier 3 Refresh entry. Still owed: LNURL, one failure,
  a first-after-launch send with a log.
- **2026-11-18, LNURL-pay (`lnurl1…` of the same Wallet of Satoshi
  address), mainnet.** Fourth format passed; all four formats now reach
  "Sent" through the new path. This one was slow on the far side: pay call
  returned about 13:27:01, the mailbox success arrived only after two
  health-check ticks (about 13:27:08 to 13:27:12), our `.paid` read followed
  it within the next second, and the new log line reports "settled after
  12s 79ms of waiting". The 12 s sat between bark's handoff and the
  server's success message, so on the Lightning or server side (the
  report's factors 2 and 3); the same payment under `wait: true` would
  have taken the same plus up to one 2 s poll. The app-side wait itself
  did not add measurable time on any of the four sends. Whether the server
  knew earlier than it told the mailbox cannot be seen from the client.
  Still owed: one failure, a first-after-launch send with a log.
- **2026-11-18, failure case, mainnet.** Invoice from the Alby Hub on the
  home Umbrel, Hub taken offline, then paid: "Payment Failed" with the
  refund message, amount back, as designed. Reported by Christoph ("worked
  great"), not read from a log; the export at that point still held the
  LNURL send. The hashless failure (F2) was not produced; see §9.
- **Idea, not filed:** for addresses and LNURL the app already has an
  LNURL resolver; fetching the invoice itself and paying it as BOLT11 would
  skip bark's duplicate fetch and give the app the hash (closing F2 without
  the bindings ask), at the price of the movement recording an invoice
  instead of the address, which the Contacts work needs. Only worth a
  ruling if the bindings ask stalls.
- **Observed on the way:** four full balance refreshes (onchain via
  Esplora + Ark) inside three seconds, three of them fired by movement
  notifications during bark's handoff (`movementCreated`, two
  `movementUpdated`), the fourth ours after settlement. Pre-existing
  behaviour of `WalletNotificationService`; filed PROPOSED in Tier 3
  Refresh.

## 10. Bindings ask

Carry the payment hash on `LightningSendStatus.unknown` (or return the
resolved invoice alongside the status) so a hashless `.unknown` can be read
again. Goes into `Bark_Bindings_Feedback.md` with Step 1.

## 11. Not in scope

Server-side handoff and routing (the report's factors 2 and 3). The
`retryForSecs` policy. Event-driven "Sent" from `movementUpdated` instead of
the 100 ms poll: possible later, the poll is a local database read.
