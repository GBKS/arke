# API Changes: Bark FFI v0.24.0 → v0.25.0

All declarations below were read verbatim from the resolved checkout's
generated `Bark.swift` (revision `157b0fc`); line numbers refer to that file.
Repo call-site facts verified by grep and file reads on 2026-09-26.

## 1. Changed API

### 1.1 `drainExits` gained `drainAll: Bool`

```swift
// Old (0.24)
open func drainExits(vtxoIds: [String], address: String, feeRateSatPerVb: UInt64?) async throws -> ExitClaimTransaction

// New (0.25) — protocol Bark.swift:2163, class Bark.swift:2949
func drainExits(vtxoIds: [String], drainAll: Bool, address: String, feeRateSatPerVb: UInt64?) async throws -> ExitClaimTransaction
open func drainExits(vtxoIds: [String], drainAll: Bool = false, address: String, feeRateSatPerVb: UInt64?) async throws -> ExitClaimTransaction
```

Upstream doc, verbatim (Bark.swift:2156–2162):

> Build a PSBT claiming exited VTXOs to `address`.
>
> Draining everything must be asked for with `drain_all`, so an id list
> filtered down to nothing is an error rather than a sweep. Ids are parsed
> all-or-nothing; well-formed ids that are not claimable are skipped.

Three semantic consequences:

1. **Empty `vtxoIds` + `drainAll == false` throws.** Previously it swept every
   claimable exit.
2. **Ids parse all-or-nothing.** One malformed id fails the whole call (no
   partial claim). Previously unspecified.
3. **Well-formed but unclaimable ids are silently skipped.** The returned
   `ExitClaimTransaction` (still just `psbtBase64` + `feeSats`) does not say
   which ids made it into the PSBT.

**Repo impact: compiles unchanged, semantics need review.** The wrapper call
at `BarkWalletFFI+Exit.swift:362` compiles via the `= false` default. But the
protocol layer must mirror the parameter (protocol mirrors the FFI, no
app-policy params — `barkwalletprotocol-mirrors-ffi`):

| Declaration / call | File:line | Change |
|---|---|---|
| `ExitClaimWallet.drainExits` requirement | `Shared/Services/ExitProgressionLogic.swift:22` | add `drainAll: Bool` |
| `BarkWalletProtocol` (refines `ExitClaimWallet`) | `Shared/Data/BarkWalletProtocol.swift:106` | add `drainAll: Bool` |
| `BarkWalletFFI.drainExits` | `Shared/Data/BarkWalletFFI/BarkWalletFFI+Exit.swift:348` | add param, forward it; fix `isEmpty ? "all"` log at :359 |
| `MockBarkWallet.drainExits` | `Shared/Data/MockBarkWallet.swift:514` | add param; fix `isEmpty ? "all"` print at :516 |
| `WalletManager.drainExits` pass-through | `Shared/Data/WalletManager/WalletManager+Operations.swift:183` | add param, forward it (zero callers today) |
| `RecordingClaimWallet.drainExits` (test double) | `Tests/Shared/ExitProgressTests.swift:490` | add param; record it |
| `ExitClaimSequence.run` call | `Shared/Services/ExitProgressionLogic.swift:160` | pass `drainAll: false` |

**Call-site inventory — no `[]`-means-all caller exists.** The only
production chain is `ExitProgressionService.checkAndProgressExits`
(`ExitProgressionService.swift:235–241`): `listClaimableExits()` →
`if !claimableExits.isEmpty` → `autoClaimExits(claimableExits)` (:287) →
`ExitClaimSequence.run(claimableVtxoIds: claimableExits.map { $0.vtxoId }, …)`.
The "claim all" UX is therefore already "every claimable id, explicitly", and
`drainAll: false` preserves it. `WalletManager.drainExits` has no callers.
Mentions in `ExitView_iOS.swift:44/57` and `WalletManager+Exits.swift:500`
are comments only.

### 1.2 `mailboxAuthorization()` gained `expirySecs: UInt32`

```swift
// Old (0.24)
open func mailboxAuthorization() throws -> String   // fixed 24h expiry baked into bark-ffi wallet.rs

// New (0.25) — protocol Bark.swift:2280, class Bark.swift:3477
func mailboxAuthorization(expirySecs: UInt32) throws -> String
open func mailboxAuthorization(expirySecs: UInt32) throws -> String
```

Upstream doc, verbatim (Bark.swift:2274–2279):

> Create a hex-encoded authorization that lets whoever holds it read this
> wallet's mailbox from the Ark server for `expiry_secs` from now, so 86400
> for 24 hours. An authorization cannot be revoked early, so keep the
> window short.

No default on the parameter — every caller must choose. **This parameter was
requested by Christoph** for the Arke relay: the fixed 24h expiry, combined
with iOS's unreliable background execution, left 124 of 151 registered
mailboxes with expired tokens (`SWIFT_AUTH_WAKE_SPEC.md`,
`Features/Background_Execution.md`). The relay could not mint its own tokens,
and the wake-push workaround ("A longer-lived token from bark-ffi remains the
more robust fix") was always a stopgap.

**Repo impact: the one certain compile break, plus a design phase.**

| Declaration / call | File:line | Change |
|---|---|---|
| `BarkWalletProtocol.mailboxAuthorization` | `Shared/Data/BarkWalletProtocol.swift:189` (MARK: Mailbox Operations) | add `expirySecs: UInt32` |
| `BarkWalletFFI.mailboxAuthorization` | `Shared/Data/BarkWalletFFI/BarkWalletFFI+Mailbox.swift:41`, FFI call at :53 | **compile break**; add param, forward |
| `MockBarkWallet.mailboxAuthorization` | `Shared/Data/MockBarkWallet.swift:802` | add param |
| Only call site: `mintAndRegisterWithRelayCore` | `Shared/Data/WalletManager/WalletManager+Notifications.swift:269` | pass the new constant |

Existing relay-side bookkeeping that the new lifetime interacts with
(`Shared/Services/RelayRegistrationService.swift`, all **in-memory**):

- `authTTL = 24 * 60 * 60` (:113) — documented as "matches the expiry
  bark-ffi bakes in"; becomes derived from the new constant.
- `freshRegistrationWindow = 60 * 60` (:108) + `isRegistrationFresh` (:135,
  pure static at :147) — launch double-fire dedupe; superseded by the
  half-window rule (02-migration-plan.md §Phase 2).
- `registerDevice` (:220) prefers the relay's `authorization_expires_at`
  (:265) over `authTTL`, so the relay's read of the token governs.
- `nextRefreshDate` = expiry − 1h (:178) drives the in-process timer
  (`scheduleAuthRefresh`, :367); `backgroundRefreshDate` = now + remaining/2
  (:188) drives the BGTask. Both derive from `authExpiresAt`, so they follow
  the new lifetime automatically.
- `forceRefresh()` (:399) clears state so timer/BGTask/wake-push paths always
  re-register.

Nothing persists `authExpiresAt`, `lastRegisteredAt`, `lastRegisteredDeviceToken`
or `lastAuthHash` across launches.

### 1.3 `LightningReceive.amountSats` became `UInt64?`

```swift
// Old (0.24)
public var amountSats: UInt64

// New (0.25) — Bark.swift:6114
/**
 * `None` for an amountless invoice that has not settled yet. It used to
 * report 0, which a UI cannot tell from a genuine zero.
 */
public var amountSats: UInt64?
```

Only `LightningReceive` changed. The other `amountSats` properties stay
`UInt64`: `Destination` (:5195), `ExitVtxo` (:5692), `LightningInvoice`
(:6052), `LightningSend` (:6289), `PendingBoard` (:6793), `Vtxo` (:7253).
The `amountSats: UInt64?` *parameters* on `payLightningInvoice` /
`payLightningOffer` were already optional.

**Repo impact: four reads, three fixtures, no UI, no tests.** `LightningReceive`
values come from three protocol methods (`lightningReceiveState`,
`tryClaimLightningReceive`, `pendingLightningReceives` —
`BarkWalletProtocol.swift:176–180`) and are never mapped into an app model.

| Read | File:line | Today | Note |
|---|---|---|---|
| `status += "  Amount: \(receiveStatus.amountSats) sats\n"` | `BarkWalletFFI+Lightning.swift:152` | `getLightningInvoiceStatus` debug string | warning (optional interpolation); would print `Optional(…)` / `nil` |
| `"amount_sats": receive.amountSats` in `[String: Any]` | `BarkWalletFFI+Lightning.swift:214` | `listLightningInvoices` JSON dump | warning; `nil` → JSON `null` |
| `logger.debug("Receive #…: \(receive.amountSats) sats…")` | `LightningClaimService.swift:165` | log | **probable compile error** — no `OSLogInterpolation` overload for Optional |
| `logger.debug("• \(receive.amountSats) sats - …")` | `LightningClaimService.swift:191` | log | same |

Neither `getLightningInvoiceStatus` nor `listLightningInvoices` has a view
caller on either platform (reached only through
`WalletManager+Lightning.swift:65/73` → `WalletOperationsService`, which no
view calls). The claim totals in `LightningClaimService` (:210, :246) use
`claimableLightningReceiveBalanceSats()`, a plain `UInt64`, and the
`htlcs-ready` filters (:179, :236) read `.state` — none depend on the amount.

| Fixture | File:line | Today | Semantics now |
|---|---|---|---|
| `lightningReceiveState` preview | `BarkWalletFFI+Lightning.swift:493` | `amountSats: 0, state: "awaiting-payment"` | a genuine zero; should be `nil` (amountless, unsettled) |
| `tryClaimLightningReceive` preview | `BarkWalletFFI+Lightning.swift:524` | `amountSats: 0, state: "settled"` | settled always has an amount; use a concrete value |
| `MockBarkWallet.tryClaimLightningReceive` | `MockBarkWallet.swift:698` | `amountSats: 0, state: "settled"` | same |

Nothing in `Tests/`, ArkéUI, ArkeDesktop or ArkeWidgets references
`LightningReceive`. Neither `Shared/Localizable.xcstrings` nor the ArkéUI
catalog has an "Any amount" / "Amount pending" key (closest:
`placeholder_amount_optional` "Add amount (optional)", `send_amount_fixed`
"Amount is fixed").

### 1.4 `CustomOnchainWalletCallbacks` contract tightened

Protocol at Bark.swift:791–876 (`getBalance` :798, `prepareTx` :811,
`prepareDrainTx` :823, `finishPsbt` :835, `makeSignedP2aCpfp` :876). Per the
pre-repo review: `prepareTx` must pay every destination the exact amount
(change allowed); every `prepareDrainTx` output must pay `address`;
`finishPsbt` must not change the unsigned tx; `makeSignedP2aCpfp` must spend
the given parent; a throwing `getBalance` falls back to the last value or 0.

**Repo impact: none.** No type in the repo conforms to
`CustomOnchainWalletCallbacks` (grep for `CustomOnchainWallet`,
`OnchainWalletCallbacks`, `OnchainWallet.custom`, `prepareDrainTx`,
`makeSignedP2aCpfp`, `finishPsbt` over all Swift sources: zero hits outside
docs). All four `WalletOpenArgs(… onchain:)` sites pass an
`OnchainWallet.default(network:mnemonic:config:datadir:)` instance:
`BarkWalletFFI+WalletCreation.swift:212→233`, `:482→505/516`,
`openImportedWallet` `:580–589`, `BarkWalletFFI+WalletLifecycle.swift:204→262`.
The `BDKOnchainWallet` class older docs describe (`Docs/BDK/*`) no longer
exists. Nothing to report; no behavior changes.

## 2. Verified non-changes

- UniFFI contract version stays **30** (`Bark.swift:10194`).
- No other method, struct or enum that `BarkWalletProtocol` or
  `ExitClaimWallet` declares changed. `ExitClaimTransaction` is still
  `{ psbtBase64, feeSats }` — it does **not** report which ids were included
  (relevant to §1.1 point 3).
- `Package.resolved` already resolves `bark-ffi-bindings` `master` @
  `157b0fc` (change uncommitted in the working tree, 2026-09-26).

## 3. Migration checklist

- [x] Phase 1: `drainAll` plumbing through `ExitClaimWallet`,
      `BarkWalletProtocol`, `BarkWalletFFI`, `MockBarkWallet`,
      `WalletManager`, `RecordingClaimWallet`; `ExitClaimSequence` passes
      `drainAll: false`; log strings fixed; `mailboxAuthorization(expirySecs:)`
      plumbing + constant; `amountSats` reads and fixtures — build green
      2026-09-26 (the two predicted `os.Logger` errors were real)
- [x] Phase 2: relay-auth persistence + mid-life renewal rule + foreground
      trigger — 2026-09-26 (02-migration-plan.md)
- [x] Tests: `ExitClaimSequenceTests` +3 (6/6); `RelayRegistrationRenewalTests`
      (9) + `RelayRegistrationPersistenceTests` (4) replace the 1h-window
      suite; full mobile suite 408 passed, 0 failed — 2026-09-26
- [x] Update `Bark_Bindings_Unadopted_API.md` baseline → v0.25.0 — done
- [x] Record `ExitClaimTransaction` included-ids gap in
      `Bark_Bindings_Feedback.md` (§1.3 addendum, ask #19); expiry parameter
      credited under "What's working well" — done
- [x] Record open items in `Open_Follow_Ups.md` (new "Bark 0.25 Migration"
      section + Localization item) — done
- [x] Write 04-completion-report.md — done
