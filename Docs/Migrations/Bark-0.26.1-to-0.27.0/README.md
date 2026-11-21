# Bark FFI Bindings Migration: v0.26.1 → v0.27.0

**Date:** 2026-11-18
**Status:** ✅ DONE 2026-11-18, committed as `401156d`. Build green, full
mobile suite 751/751 on the new binary before any app change. Signet
device check the same day (Christoph): onchain send from Payments and from
Savings, receive, board, offboard, and a unilateral exit of three VTXOs
started, progressed and completed, which exercised the bdk 3.2.0
signer change on the exit's CPFP children and the claim. Companion plan:
`../../Features/Lightning_Send_Settlement.md`.
**Bark Version:** v0.8.0 → **v0.8.1**
**FFI Bindings Version:** v0.26.1 → v0.27.0 (tag `v0.27.0+bark-0.8.1`,
commit `66d047f7ee08c2bca3675605ea7a88bc8b50adb3`, exact-revision pin as
before). The `bark-ffi` crate moves from `4a1c1c0` to `ca8f174` and uniffi
from 0.31.1 to 0.31.2 (`swift/rust/Cargo.toml` at both tags), so the binary
changes even though the Swift surface change is small.

## Why this bump

Lightning sends move to `wait: false` with the app waiting for bark's
preimage. That needs bark 0.8.1's fix for "lightning sends that stay pending
after they are paid" (CHANGELOG v0.8.1, MR 2663): `LightningSend::advance`
now settles from the stored paid record and the mailbox handler finishes a
send from the server's message.

## API changes (generated `Bark.swift`, the two tags diffed 2026-11-17)

| Change | Repo impact |
|---|---|
| `bolt11Invoice` and `bolt11InvoiceForAddress` gain `expirySecs: UInt64? = nil` | None, `BarkWalletFFI.getLightningInvoice` uses the default |
| New `presignEmergencyExit(vtxoIds:feeRateSatPerVb:) -> PresignedExits` with `PresignedExit`, `PresignedExitChild`, `PresignedExitPackage`, `PresignedExitStatus`, `PresignedWave`, `ExitFeeInfo`, `ExitTransactionInfo` | Unadopted; recorded in `Bark_Bindings_Unadopted_API.md` |
| New `remainingExitTransactions(vtxoIds:) -> RemainingExitTransactions` with `RemainingExit` | Unadopted, same |
| `RecoveryBucket`, `RecoveryReport`, `RefreshFees` move within the file | None, still present with the same fields |

No method the app calls is removed or re-typed. **Verified** by diffing the
generated file between the tags in a blobless clone; `recoverVtxos` keeps
its signature at both tags.

## Behaviour the Lightning change relies on

Facts F1–F6 in the companion plan §3, read at `bark-0.8.1`
(`~/workspace/bark`, `git show bark-0.8.1:<path>`) and bark-ffi `ca8f174`
(`~/workspace/bark-ffi`). Summary:

1. `lightning_send_state`: paid record, then checkpoint, then `Unknown`.
2. Settlement writes the paid record first and removes the checkpoint last;
   one `Unknown` read can be a settlement in progress.
3. `wait: false` is `DriveMode::UntilParkOrDone`; a retryable error saves the
   checkpoint and returns the error. The HTLC cosign is retry-unless-rejected.
4. bark-ffi's `pay_lightning_*` return `lightning_send_state` for the
   resolved invoice's hash; the Swift `.unknown` case drops that hash.
5. A failed payment ends `Done` (`Unknown`); a stuck revocation keeps its
   checkpoint with `hasFailedRevocation`.

## Other bark 0.8.1 changes, not reviewed for this bump

From the CHANGELOG: `bdk_wallet` 3.2.0 (BREAKING in bark: the onchain
wallet keeps its own signers; after a reload `OnchainWallet::inner` holds no
private keys), exit presigning and remaining-exit listing, BOLT12 offers in
fiat no longer panic, zstd no longer advertised to the server,
`bolt11_invoice_builder` with expiry. **Not verified** beyond the CHANGELOG.
Before the bump counts as done: a signet device check of onchain send,
board, refresh, Lightning receive and claim, and exit progress.

## Playbook bark facts

Re-verified at `bark-0.8.1` on 2026-11-18: B1 (`lib.rs:1392`, `if
!created_now`), B6 (`lib.rs:1413`, `if args.run_daemon`; binding default
`runDaemon: Bool = true`), B7 (`balance.rs` unchanged between the tags), B2
(`exit/mod.rs` diff is additive, load-time filtering untouched). Not
re-verified: B3 (timing observation), B8 (`onchain/bdk.rs` +547 lines for
bdk_wallet 3.2.0; the signet onchain check stands in).

## Documents

- `Docs/Bark_Bindings_Unadopted_API.md`: baseline v0.27.0, the two new exit
  surfaces, `expirySecs`.
- `Docs/Development/Setup.md`: tag line.
- `Docs/Development/Change_Review_Playbook.md`: B1/B6 re-verified line, B2/B8
  notes.
- `Docs/README.md`: version mention.
