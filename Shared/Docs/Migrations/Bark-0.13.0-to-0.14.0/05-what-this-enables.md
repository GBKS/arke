# What v0.14.0 Enables (Product Opportunities)

Forward-looking companion to [01-api-changes.md](01-api-changes.md) — not a
record of the migration, none of this is implemented. Four things, and they
share a theme.

## 1. Lightning receive while the app is dead

`bolt11InvoiceForAddress` + `LightningReceive.claimDestination` + the
`"delivering"` state.

Unlocks async receive without custody: a Lightning Address that resolves to
your users, invoices that stay payable after the app is backgrounded or
killed, push-style "you got paid while you were away." The service doing the
claiming provably can't spend the proceeds — it can only stall delivery. Also
gives you the merchant-terminal shape, where an always-on till mints invoices
that sign straight to a treasury address it can't touch.

For Arke this dovetails with the background-execution work
(`Shared/Docs/Features/`, mailbox push wake): the phone is the *recipient*
side, so someone has to run the always-on invoicing service.

## 2. Restore from seed phrase alone

`recoveryReport()`, `recoverVtxos(vtxoIds:)`, `WalletOpenArgs.skipRecovery`,
`Vtxo.registered`.

This is probably the biggest one. VTXOs are off-chain, so they aren't
discoverable by scanning the blockchain the way on-chain UTXOs are — in v0.13
the recovery story was the manual `vtxoEncoded` / `importVtxo` pair, i.e. the
user had to have personally stashed serialized VTXOs somewhere. That's not a
consumer-viable backup story.

v0.14 registers VTXOs to a server-side recovery mailbox and scans it
automatically on the open that creates the wallet locally. So "lost my phone,
here's my seed phrase" can now actually return the off-chain balance.
Practically that means: a real restore flow, a progress/result screen driven
by the report's buckets, and a retry button wired to `recoverVtxos` for the
`failed` ones. (The migration wired the scan + logging on seed import; the UI
is the open follow-up in [04-completion-report.md](04-completion-report.md).)

Read the caveats though — an empty report doesn't prove nothing's missing, and
`foreign` ids sitting past the 50-index gap limit aren't retryable, only
re-scannable with a wider limit. Don't show users a green checkmark on `nil`.

## 3. Expiry protection for a wallet that's offline for weeks

`refreshVtxosScheduled(vtxoIds:scheduledHeight:)`.

VTXOs expire, and refreshing costs a fee that shrinks the closer you get to
expiry. Previously the cheap option required you to be online near expiry to
take it. Now you can pre-commit a delegated refresh at a future height and go
dark — you get the cheaper price *and* you don't have to be present. Feed it
`getNextRequiredRefreshBlockheight()` and it becomes a set-and-forget guard
against a user who doesn't open the app for a month coming back to expired
funds or a forced unilateral exit.

## 4. An honest "your funds are recoverable" indicator

`Vtxo.registered`.

It only moves false → true, and sync backfills the stragglers. So you can
actually tell the user whether their current balance is covered by seed
recovery yet, instead of asserting it. Useful right after receiving — "still
securing this payment, keep the app open a moment" — and as a diagnostic when
a restore comes back incomplete.

---

**The through-line:** every one of these removes a requirement that the wallet
be online at a specific moment it can't control. Online when someone pays you,
online near expiry, online to have ever backed up local state. For a mobile
Ark wallet, which is exactly the environment where you can't guarantee any of
that, this release is mostly about making the thing survive being a phone.

The cost is a new trust surface: whoever claims your delegated invoices can
strand them, and seed recovery leans on the server's mailbox being intact.
Neither is custody, but both are liveness assumptions worth being explicit
about in the UI.
