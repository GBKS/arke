# Lightning Receive State

**Status:** OPEN (Tier 1 Connectivity). Pairs with the short backlog entries
"Invoice request timeout" and "Invoice creation polish".

Moved verbatim from `Open_Follow_Ups.md` on 2026-11-10 (backlog hygiene pass, relocation only; the open entry is now a stub pointing here).

## 1. No claim loop, no state, no error

- [ ] **A stuck Lightning receive is invisible, and cannot be cancelled or
  exited**: Second's 2026-10-06 disclosure says the follow-on denial of
  service "could degrade Lightning receives on Bark-based wallets" (server
  fixes `9111622f9`, `6fd9834ff`). Corrected 2026-10-09: **the app has no
  claim loop at all.** `LightningClaimService` has been disabled since
  commit a894888 (2026-04-10, constructor commented out at
  `WalletManager.swift:390-391`; every `lightningClaimService?.start()` is a
  no-op on nil), so its 30 s poll / `htlcs-ready` / swallowed-error code is
  dead. Receives are claimed inside bark's own `sync()`
  (`try_claim_all_lightning_receives` at tag bark-0.7.1, `lib.rs:1980,2012`),
  which only `warn!`-logs failures — the app sees neither state nor error.
  `cancelLightningReceive`, `attemptLightningReceiveExit`,
  `lightningReceiveState`, `tryClaimLightningReceive`,
  `pendingLightningReceives` exist on `BarkWalletFFI+Lightning.swift` with
  zero live callers. Decide whether to delete the service or revive it as
  the state source for the UI; then surface pending receives with their
  state on the invoice sheet and in Activity, show the last claim error when
  it repeats, and offer cancel / exit for a receive that never settles. Pair
  with "Invoice request timeout" above.
