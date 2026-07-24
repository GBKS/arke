# Migration Plan: Bark FFI v0.11.3 → v0.12.1

**Migration:** Bark v0.3.0 → v0.4.0, FFI Bindings v0.11.3 → v0.12.1

Concrete, ordered plan. Line numbers are from the working tree at planning time
(2026-07-24) and will drift — treat them as anchors, not guarantees. Verify all
new signatures against the resolved package's generated `Bark.swift` in
`DerivedData/.../SourcePackages/checkouts/bark-ffi-bindings/swift/Sources/Bark/`
(do **not** use `~/workspace/bark-ffi-bindings`).

---

## Phase 0 — Verify real signatures ✅ DONE (2026-07-24)

Verified against `Bark.swift` in DerivedData SourcePackages (v0.12.1, `8f9c899`):

- `boardAll() -> PendingBoard`, `boardAmount(amountSats:) -> PendingBoard`,
  `progressExits(feeRateSatPerVb:)`, `runDaemon()`, `syncExits()` — no
  `onchainWallet:` params.
- `maintenanceWithOnchain` / `maintenanceWithOnchainDelegated` — gone.
  (`maintenance()`, `maintenanceDelegated()`, `maintenanceRefresh()` remain.)
- `lightningReceiveState(paymentHash:) -> LightningReceive` (non-optional),
  `tryClaimLightningReceive(paymentHash:wait: Bool = false) -> LightningReceive`.
- `LightningReceive`: `state: String`, `paymentPreimage: String?`,
  `settledAt: Int64?`; booleans gone.
- `bolt11Invoice(amountSats:description:token: String? = nil)`.
- `CustomOnchainWalletCallbacks`: `isMine(scriptPubkeyHex:)` + `registerTx(txHex:)`
  added; the three tx-lookup methods gone; `sync()` etc. unchanged.
- Upstream: `ExitState` +`Canceled` only; `ExitTxStatus` identical; exit states
  still Debug-formatted strings; `ExitError.InsufficientConfirmedFunds` message
  prefix unchanged; no `BarkPersister` in Swift surface.
- **Completeness:** `git diff 9be2240..8f9c899 -- swift/` in the package
  checkout (exact old→new pins) shows `Bark.swift` as the only file with API
  changes, and every changed declaration is covered by Phases 1–5. Nothing
  else changed (`WalletNotificationsExtension.swift` untouched).

## Open decisions (settle before/at Phase 4)

1. **`BDKOnchainWallet`: update or delete?** It's dead code (instantiated
   nowhere). Update = mechanical (Phase 4a); delete = also remove
   `BDKCpfpHelper` if orphaned (Phase 4b) — check `BDKTransactionReader` and
   others for shared use first.
2. **`Canceled` parser hardening (Phase 6):** include or defer. Recommended:
   include (~10 lines + test); closes a live-activity-respawn gap before it
   can bite.

---

## Phase 1 — Drop `onchainWallet:` arguments (mechanical)

- `BarkWalletFFI+VTXO.swift:231` — `wallet.boardAmount(amountSats:)`.
- `BarkWalletFFI+VTXO.swift:265` — `wallet.boardAll()`.
- `BarkWalletFFI+Exit.swift:264` — `wallet.progressExits(feeRateSatPerVb:)`.
- `BarkWalletFFI+Exit.swift:312` — `wallet.syncExits()`.
- `BarkWalletFFI+WalletLifecycle.swift:382` — `wallet.runDaemon()`.

In each, the `guard let onchainWallet = onchainWallet` preflight becomes an
unused binding. Keep the guard as a sanity check only where the error message
adds diagnostic value (board/exit paths); use `guard onchainWallet != nil` or
drop it — don't leave unused-variable warnings.

**`runDaemon` signature ripple** (drop the parameter everywhere):

- `BarkWalletFFI+WalletLifecycle.swift:372` — wrapper becomes `runDaemon()`.
- `BarkWalletProtocol.swift:215` — declaration becomes `runDaemon()`; update
  the doc comment (callback-wallet caveat no longer applies).
- `MockBarkWallet.swift:856` — stub becomes `runDaemon()`.
- `WalletManager.swift:571` — call becomes `try await ffiWallet.runDaemon()`.

---

## Phase 2 — Delete removed maintenance methods

- `BarkWalletFFI+Maintenance.swift:51-78` — delete `maintenanceWithOnchain()`.
- `BarkWalletFFI+Maintenance.swift:107-134` — delete
  `maintenanceWithOnchainDelegated()`.
- `BarkWalletProtocol.swift:109,114` — delete both declarations.
- `MockBarkWallet.swift:600-603,611-613` — delete both stubs.
- `WalletManager+Operations.swift:317-322` — delete the
  `maintenanceWithOnchainDelegated()` passthrough.
- `DataView_iOS.swift:65` — inside an already commented-out block; update or
  remove the stale comment so it doesn't reference a deleted API.

No live callers exist (verified by repo-wide grep).

---

## Phase 3 — Lightning receive reshape

### Rename + signature (contained: protocol / FFI / mock only)

- `BarkWalletProtocol.swift:167` →
  `func lightningReceiveState(paymentHash: String) async throws -> LightningReceive`
  (non-optional).
- `BarkWalletProtocol.swift:168` →
  `@discardableResult func tryClaimLightningReceive(paymentHash: String, wait: Bool) async throws -> LightningReceive`.
- `BarkWalletFFI+Lightning.swift:480-500` — rename, return non-optional,
  propagate the thrown unknown-hash error; the `isPreview` branch can no longer
  return nil — prefer returning a stub
  (`LightningReceive(..., state: "awaiting-payment", paymentPreimage: nil, settledAt: nil)`)
  over throwing, consistent with other preview branches.
- `BarkWalletFFI+Lightning.swift:502-525` — return the `LightningReceive` from
  `wallet.tryClaimLightningReceive`.
- `MockBarkWallet.swift:720-729` — `lightningReceiveState` throws instead of
  returning nil; `tryClaimLightningReceive` returns a stub `LightningReceive`
  (new memberwise init: `state:`, `paymentPreimage:`, `settledAt:`).

### Boolean → `state` string consumers

- `LightningClaimService.swift:178,236` — claimable filter →
  `$0.state == "htlcs-ready"`.
- `LightningClaimService.swift:162-163` — debug prints → print `state`.
- `LightningClaimService.swift:21` — update flow doc comment.
- `BarkWalletFFI+Lightning.swift:153-162` (`getLightningInvoiceStatus`) —
  status text from `state`: `"htlcs-ready"` → ready to claim,
  `"preimage-revealed"` / `"settled"` → claimed, `"awaiting-payment"` →
  waiting.
- `BarkWalletFFI+Lightning.swift:209-212` (`listLightningInvoices` JSON) —
  replace the two booleans with `"state": receive.state` (optionally add
  `"settled_at"`); same status mapping.

No other `LightningReceive` field consumers exist (verified). App-side
`paymentPreimage` plumbing is unaffected.

---

## Phase 4 — `BDKOnchainWallet` (pick one)

### 4a. Update (keeps changeset a pure migration)

- Delete `getWalletTx(txid:)` (`BDKOnchainWallet.swift:302-317`),
  `getWalletTxConfirmedBlock(txid:)` (319-341), `getSpendingTx(outpoint:)`
  (343-362).
- Add `isMine(scriptPubkeyHex:)` — hex → `Script`, delegate to BDK
  `wallet.isMine(script:)` (already used at line 705).
- Add `registerTx(txHex:)` — hex → `Transaction`, apply to the BDK wallet as
  an unconfirmed tx (BDK 2.x `applyUnconfirmedTxs` or equivalent; verify the
  exact bdk-swift API in the resolved checkout).

### 4b. Delete

- Remove `BDKOnchainWallet.swift`; check whether `BDKCpfpHelper.swift` is then
  orphaned (its only stated consumer) and remove too. Requires an Xcode
  target-membership pass (Shared/ sync has per-target exception lists).

---

## Phase 5 — `bolt11Invoice` token (no-op, confirm only)

`BarkWalletFFI+Lightning.swift:111` compiles unchanged. Leave `token:`
defaulted.

Context (see 01-api-changes §4): the token is an **anti-DoS claim credential**
for wallets with no spendable VTXO to attest with (i.e. empty-wallet first
receive), issued out-of-band by the server operator and persisted by bark in
the receive checkpoint. No token source exists in Arke today; without one,
claims authenticate via VTXO attestation exactly as in 0.11.3 — no regression.
If "onboard via Lightning receive into an empty wallet" ever becomes a product
goal, that's when `getLightningInvoice` needs a token parameter threaded
through.

---

## Phase 6 — Optional hardening: parse `ExitState::Canceled`

- `ExitStatusParser.swift:33-50` — add `case "canceled":` producing a new
  `ParsedExitState` case (Debug string will look like `Canceled(...)` /
  `Canceled { .. }`; parse leniently, payload not needed). Adding the enum case
  makes the compiler flag every exhaustive `switch` over `ParsedExitState`
  (e.g. `ExitProgress`, `ExitTransactionStatus+Parsing`) — treat those errors
  as the checklist of mapping sites rather than pre-enumerating them here.
- `ExitProgress.swift:84-112` — map the new case to phase `.cancelled`
  (like `.vtxoAlreadySpent`).
- `ExitProgress.swift:183-187` — exclude it from the aggregate's active set
  (like `.vtxoAlreadySpent`).
- Add an `ExitStatusParserTests` case with a `Canceled` state string, and an
  `ExitProgressTests` case asserting cancelled phase + aggregate exclusion.

Rationale: unreachable today (no cancel-exit API in bindings), but if it ever
surfaces the current fallback shows a cancelled exit as an active "Preparing"
exit and can keep the live activity alive.

---

## Phase 7 — Build + tests

1. `BuildProject` (iOS). Fix stragglers the compiler finds.
2. Run the Shared test suite via xcodebuild (MCP RunAllTests cancels — known):
   `ExitStatusParserTests`, `ExitProgressTests`, `ExitBlockedInfoTests` are the
   logic-adjacent ones; batch the full mobile suite at task end per the lean
   workflow.
3. Desktop target: not in rotation; note status only.
4. Runtime smoke (deferred to on-device pass): board, lightning receive +
   auto-claim, exit progression on signet.
