# Bark FFI Bindings Migration: v0.26.1 → v0.27.0

**Date:** 2026-11-17
**Status:** 🔨 BUILT 2026-11-17 with the Lightning `wait: false` change. iOS
simulator `build-for-testing` green; `LightningSettlementTests` compiled, not
run; no full suite, no device run.
**Bark Version:** v0.8.0 → **v0.8.1**
**FFI Bindings Version:** v0.26.1 → v0.27.0 (tag `v0.27.0+bark-0.8.1`,
revision `66d047f7ee08c2bca3675605ea7a88bc8b50adb3`, exact-revision pin;
UniFFI contract version **30, unchanged**, verified in the generated
`Bark.swift`). The `bark-ffi` crate moves from `4a1c1c0` to `ca8f174`
(`swift/rust/Cargo.toml`, both tags), so the binary changes.

One file instead of the usual four: the Swift surface change is additive and
needs no code change.

## Why this bump

Lightning sends now start with `wait: false` and the app waits for bark's
preimage itself (`LightningSettlement`). That needs bark 0.8.1's fix for
"lightning sends that stay pending after they are paid" (CHANGELOG v0.8.1,
MR 2663): the mailbox and the daemon sync loop now drive a pending send to
its end, and a send whose invoice is paid is finished from the stored
preimage.

## API changes (generated `Bark.swift`, the two tags diffed)

| Change | Repo impact |
|---|---|
| `bolt11Invoice` and `bolt11InvoiceForAddress` gain `expirySecs: UInt64? = nil` | None. `BarkWalletFFI.getLightningInvoice` uses the default |
| New `presignEmergencyExit(vtxoIds:feeRateSatPerVb:) -> PresignedExits` and its types | Unadopted, recorded in `Bark_Bindings_Unadopted_API.md` |
| New `remainingExitTransactions(vtxoIds:) -> RemainingExitTransactions` and its types | Unadopted, same |
| Other hunks reorder generated converters | None |

The Lightning change adds one protocol method, `pendingLightningSends()`,
which mirrors an FFI method that predates v0.27.0.

## Behaviour the app now relies on (read at `bark-0.8.1`)

Read with `git show bark-0.8.1:<path>` in the bark repo.

1. `lightning_send_state` (`bark/src/lightning/pay.rs`) returns `Paid` if
   the paid-invoice record exists, else `InProgress` if the send's
   checkpoint exists, else `Unknown`. **Verified (read).**
2. A failed payment revokes its HTLCs and the action ends with
   `Advance::Done`, which removes the checkpoint, so the state reads
   `Unknown` (`bark/src/actions/lightning/pay.rs`, `Progress::RevocableHtlcs`).
   A revocation that fails moves to `Progress::RevocationStuck` and keeps its
   checkpoint (`hasFailedRevocation`). **Verified (read).**
3. A settlement writes the paid record first and removes the checkpoint
   last (`settle_lightning_send_payment`, `settle_lightning_send_with_preimage`).
   A read between bark's two lookups can therefore give `Unknown` once for
   a paid send; `LightningSettlement` reads again. **Verified (read).**
4. `lightningSendState` never advances the action (binding doc comment).
   **Verified (read, bindings).**
5. `pay*(wait: false)` returns the state read after the drive parks:
   `InProgress` normally, `Paid` or `Unknown` if the payment finished inside
   the call. **Derived**: the `bark-ffi` Rust is not in the bindings
   checkout; this follows from item 1 and `make_lightning_payment_with`.
6. With `wait: true` a failed and refunded payment also returned `Unknown`,
   which the app logged and then showed as "Payment Sent". **Derived** from
   items 2 and 5; not reproduced.
7. In `DriveMode::UntilParkOrDone` (`wait: false`) an `Advance::Retry`
   saves the checkpoint and returns the error to the caller
   (`bark/src/actions/mod.rs`, `run_action_loop`). The HTLC cosign and the
   payment start give Retry on any error that is not a rejection, so a pay
   call can throw while its send stays pending, and the daemon finishes it
   on its next sync. `wait: true` slept and retried inside the call.
   **Verified (read).** `WalletManager.payLightning` therefore waits for the
   send after a failed call: by hash for an invoice, otherwise the one send
   that appeared in `pendingLightningSends()` during the call.

## Other bark 0.8.1 changes, not reviewed for this bump

`bark/src` changes 25 files between the tags (+1835/-235). Beyond Lightning
sends, the CHANGELOG and diff show: `bdk_wallet` 3.2.0, marked BREAKING in
bark (wallet-owned signers; after a reload `OnchainWallet::inner` holds no
keys; the app uses bark's built-in onchain wallet), `onchain/bdk.rs`
(+547), round ownership attestations (`round/mod.rs`), Lightning receive
(`lightning/receive.rs`), the mailbox, and exit presigning. **Not
verified.** Before this counts as done: a signet device check of onchain
send, board, refresh, Lightning receive and claim, and exit progress.

## Playbook bark facts

B1 and B6 re-verified at `bark-0.8.1` (`lib.rs`, unchanged lines); B6's
binding default (`runDaemon: Bool = true`) re-verified in the generated
`Bark.swift`. B2, B3, B7 and B8 not re-verified for this bump.

## Known gap

`.unknown` returned directly by `payLightningAddress`, `payLnurl` or
`payLightningOffer` has no payment hash, so the read-again of item 3 cannot
run there (invoices pass the hash parsed from the invoice). The mailbox
handler can wait on the send's lock and settle as soon as the pay call's
drive releases it, just before bark-ffi's own state read, so the window is
narrow but real. **Not verified**: bark-ffi's after-drive read is not
readable locally. Backlog: Tier 1 Send.
