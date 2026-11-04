# Foreign-server Ark addresses

**Status:** DONE 2026-11-04. Built, two adversarial passes (§9, §11),
Coinos device check (§10), simulator pass with a minted address (§12),
copy and layout rework on Christoph's screenshots (§12), and the full
device list of §8, §10 and §12 including the cold offline launch run by
Christoph on his phone the same day, all good. Not yet in a TestFlight
build. Backlog entry closed to the Done log 2026-11-04.

## 1. Problem

Until the Ark server selection landed (`Ark_Server_Selection.md`,
2026-11-02) every Arké wallet sat on Second's mainnet or signet server, so an
Ark address from another server could not occur between Arké users. With a
custom server (Zappin today) it can, and the app handles it badly:

- `AddressValidator.detectArkNetwork` reads the `ark1` / `tark1` prefix
  only. A foreign address parses, ranks and gets selected.
- bark refuses at send time. The FFI wrapper (`BarkWalletFFI.send(to:amount:)`)
  rewraps the error as `BarkWalletFFIError.configurationError("Failed to
  send payment: Ark address is for different server")`, raw bark text.
- In a BIP-21 carrying an Ark and a Lightning or bitcoin option, the ranker
  puts the Ark row on the Payments balance (one row per balance, DECIDED
  2026-10-28, `Send_Onchain_From_Payments.md` §9.1) and drops the option
  that would have worked.

Funds are not at risk: bark validates before cosigning and the VTXOs stay
spendable (binding doc on `sendArkoorPayment`, verified at rev 4670c1a).
This is a UX fault, Tier 1.

## 2. Rulings (Christoph, 2026-11-04)

1. Ship in the custom-server release (DECIDED).
2. Generic copy; the Bool call cannot say why (DECIDED).
3. The release does not wait for Tier 0 (DECIDED).

## 3. Claims the plan rests on

| # | Claim | Label |
|---|---|---|
| C1 | `Wallet.validateArkoorAddress(address:) async throws -> Bool` exists in the pinned bindings (rev 4670c1a, `Package.resolved`); doc: "same network and server, a supported VTXO policy, and only delivery mechanisms this bark supports … Errors only when the address does not parse." | verified, read in DerivedData `Arke-gknak…` (the other DerivedData checkout is the stale 0.25 line) |
| C2 | bark-ffi at the pinned rev 4a1c1c0 implements it as `self.inner.validate_arkoor_address(&addr).await.is_ok()`: every `ArkoorAddressError`, including `Other` (no server connection), becomes `false`. | verified, `git show 4a1c1c0:src/core/wallet.rs` after fetching `~/workspace/bark-ffi` |
| C3 | bark 0.8.0 checks network, then `ark_id().is_for_server(server_pubkey)`, then VTXO policy, then delivery; `require_server` connects lazily, so a cold offline wallet fails with `Other`. | verified, `git show bark-0.8.0:bark/src/arkoor.rs`, `bark/src/lib.rs` |
| C4 | `parsePaymentRequest(payment:)` exists too and reports `invalidArkAddress(reason:)` per option. Not adopted here: it replaces the app parser (Tier 4 Track B). | verified, same bindings file |
| C5 | Every ranking path funnels through `PaymentDestinationSelector.rankDestination(_:amount:context:exactFee:source:)`: `rankDestinations(from:)` → `rankDestinations(_:)` → it; `selectOptimalDestination`, `viableDestinations`, `isViable`, `viabilityReport` and the pre-send fresh ranking in `SendViewModel.executeSend` call it directly. Only `rerankDestinations` (sync, typed-amount re-rank) bypasses it. | verified by reading the file and grepping callers |
| C6 | The sheet rows render `viable` + `viabilityReason` (`FundingSourceRow` via `DisplayDestination`); `executeSend` throws `SendError.destinationNotViable(reason)` ("Cannot send: …") when the fresh ranking is unviable. So an unviable row is both shown and blocked without a new gate. | verified |
| C7 | `WalletManager.isArkServerReachable` is optimistic (true before the first sync). A reachability check gated on it would run before the server handshake and, per C2, call every address undeliverable. | verified, `WalletManager+ProcessState.swift` |
| C7a | `connectionStatus.isConnected` is not strict either: launch Step 2a sets it after `syncArk()`, and bark 0.8.0 `Wallet::sync` returns `()` and only warns on failure, so the flag is true after any post-open refresh, offline included. The first build gated on it. | verified by the review pass (`WalletManager.swift` Step 2a, bark `lib.rs`), see §9 |
| C7b | bark 0.8.0 `Wallet::ark_info()` is `self.inner.server.get()`: a read of the server cell with no network call. Non-nil means the connection is warm, and on a warm cell `validate_arkoor_address` does no network I/O (`ServerConnection::ark_info` is a cache read, the key check a db read). | verified, `git show bark-0.8.0:bark/src/lib.rs`, review pass for the warm path |
| C8 | QuickPaymentView and ContactPaymentView pick `rankedDestinations.first(where: viable)`; `sorted` puts viable rows first; `oneRowPerBalance` then keeps the first row per balance. An unviable Ark row therefore yields the Lightning or Payments-onchain row for Payments. | derived from the code read, pinned by the new tests |
| C9 | A wallet created without a server pinned (`Ark_Server_Selection.md` §2, bad custom URL) has no server connection; the check reports every Ark address undeliverable there. Such a wallet cannot send Ark anyway. | derived |

## 4. Design

**FFI boundary.** `BarkWalletProtocol.validateArkoorAddress(address:) async
throws -> Bool`, mirroring the FFI (no policy). `BarkWalletFFI` wraps the
call and classifies `Bark.Error` into `BarkWalletFFIError.configurationError`
like its neighbours; preview mode returns true. `MockBarkWallet` returns true.

**Policy, in `WalletManager.canPayArkAddress(_:) async -> Bool?`.**
`nil` means unknown and never blocks: no wallet, no warm server connection,
or a thrown validation (unparseable address; the send surfaces that
itself). Otherwise bark's answer. The warm-connection gate is bark's own
`arkInfo()` through `getArkInfo()` (C7b): neither app flag can serve (C7,
C7a), and a warm cell also means the validation itself does no network I/O.

**Memory, `ArkAddressReachability` (`Shared/Helpers`).** A main-actor
class holding bark's verdicts per address, scoped by the current server
URL so a wallet re-created on another server starts clean without a
lifecycle hook. `check(_:)` asks the probe once and remembers `true` and
`false`; unknown is not remembered, so the next ranking asks again.
`known(_:)` reads without asking. `WalletManager.arkReachability` owns the
app's instance (probe: `canPayArkAddress`); tests build one with a canned
probe.

**Ranker.** `PaymentContext` carries `arkReachability: ArkAddressReachability?`;
both production builders (`WalletManager.createPaymentContext`,
`SendViewModel.paymentContext`) pass the manager's instance. The async
funnel `rankDestination` calls `check` once per `.ark` destination; the
pure `rank` reads `known` for both the async path and the sync
`rerankDestinations`, so a verdict survives even when `oneRowPerBalance`
has dropped the Ark row from the rows the view model holds (§9, finding 2).
`checkViability` places the check right after the server-connection gate
and before the amount checks. `RankedDestination` and the re-rank
signature are unchanged.

**Copy.** One new string at the call site: `viability_ark_unreachable`,
"Your Ark server can't deliver to this address". It appears in the sheet row
and, through `destinationNotViable`, in the send error.

**Not changed.** `AddressValidator` keeps the prefix check (format
detection, not reachability). `parsePaymentRequest` stays unadopted. The
`.bip353` fallback in `executeSend` that sends an unresolved BIP-353 string
as Ark is pre-existing and out of scope.

## 5. Sweep of sibling sites

| Site | Status |
|---|---|
| `rankDestinations(from:context:)` and the seven `rankedDestinations(context:)` callers (SendViewModel ×4, QuickPaymentView ×2, ContactPaymentView ×2) | covered through the funnel (C5) |
| `executeSend` fresh ranking | covered (calls `rankDestination`) |
| `rerankDestinations` | covered: `rank` reads the remembered verdict (first build carried a set that `oneRowPerBalance` emptied, §9) |
| `processStateService.updateConnectionStatus` writers (launch Step 2a, `refreshAll`) | exempt after §9: no longer consulted; both write connected and never disconnected |
| `selectOptimalDestination`, `viableDestinations`, `isViable`, `viabilityReport` | covered through the funnel |
| `SendViewModel+MaxSendable` | exempt: reads `availableBalance` only |
| `ContactAddressService.parsePaymentRequest` | exempt: parsing, no reachability |
| `AddressValidator.detectArkNetwork` | exempt by design (§4) |
| BIP-353 resolution → Ark address | covered: the resolved address ranks like any other |
| Desktop views | Shared ranker, compiles into both targets; desktop parked, not built |

## 6. Tests (`PaymentDestinationSelectorTests`)

- BIP-21 with a foreign Ark, a Lightning and a bitcoin option: Payments row
  is Lightning, Savings stays, no Ark row survives.
- The same request re-ranked from the request (as the first fee estimate
  does) keeps Lightning (finding 2's scenario).
- Bare foreign Ark address: one row, unviable, the new reason, through
  rank and re-rank.
- Unknown reachability (nil): the Ark row stays viable and the probe is
  asked again next time.
- The probe is asked only for Ark destinations and a settled verdict is not
  asked twice.
- A scope (server) change forgets the verdicts.

## 7. Verification log

- 2026-11-04, first build: `PaymentDestinationSelectorTests` 16 of 16 on
  the iPhone 17 Pro simulator via `xcodebuild`; then the adversarial pass
  (§9).
- 2026-11-04, after the rework: `PaymentDestinationSelectorTests` 18 of 18;
  full mobile suite via `xcodebuild` on the iPhone 17 Pro simulator, 638
  tests, 633 passed, 0 failed, 5 skipped (the live-probe tests that need
  `TEST_RUNNER_ARKE_LIVE_PROBE=1`). Result bundle
  `Test-Arke mobile-2026.11.04_09-06-47-+0100.xcresult`.
- 2026-11-04, Coinos device check by Christoph (§10): refusal, BIP-21
  fallback, same-server sends all as expected.
- 2026-11-04, after §10 and its review (§11): scoped suite 23 of 23; full
  mobile suite 643 tests, 638 passed, 0 failed, 5 skipped. Result bundle
  `Test-Arke mobile-2026.11.04_10-20-56-+0100.xcresult`.
- 2026-11-04, simulator pass (§12): the four UI scenarios of §10's device
  list pass on the iPhone 17e signet simulator with a minted
  foreign-server signet address. Not a substitute for the Device stage.
- 2026-11-04, after the copy and layout rework (§12): simulator re-check
  of the three flows passed; scoped suite 23 of 23; full mobile suite 643
  tests, 638 passed, 0 failed, 5 skipped. Result bundle
  `Test-Arke mobile-2026.11.04_13-04-43-+0100.xcresult`.
- 2026-11-04, Device stage, Christoph's phone: every item of §8, §10 and
  §12 (foreign address in quick, manual and contact flows with the
  reworked copy; BIP-21 fallback to Lightning, including typing above the
  Payments balance; same-server sends; cold offline launch with a
  same-server address staying viable). All good. Closes the entry.

## 12. Simulator pass (2026-11-04, iPhone 17e signet wallet)

**Why a minted address.** The simulator wallet is on Second's signet
server; Coinos and Zappin are mainnet, and the network filter runs before
the ranker, so their addresses would show the wrong-network caption, not
the reachability path. bark's check is a local comparison of the
address's Ark id against the wallet's server key, so an address minted
for a server that does not exist exercises it exactly. Recipe, for the
next device day: a scratch crate depending on `ark-lib` from a worktree
of `~/workspace/bark` at tag `lib-0.8.0`, calling
`ark::Address::new(true, serverPubkey, VtxoPolicy::new_pubkey(userPubkey), vec![])`
with fixed throwaway keys (`[0x11; 32]`, `[0x22; 32]`); the builder
refuses an empty delivery list, `Address::new` does not, and the FFI doc
calls such an address valid. Output used:
`tark1ptd4e9vezqqpyvmtletjk8ewtpxsdrpctkkqrgjqyv9u8ng2ff88jy2zlrwhr7fcccrhn2`.
Nothing about it is secret or spendable.

**Results** (screenshots and notes in
`~/workspace/Arke-sessions/screenshots/2026-11-04/index.md`):

1. Quick flow via Paste: "Pay from Payments" row with the address and
   the orange reason, no amount field, no fee row, italic caption in the
   button's place. Pass.
2. Manual flow, address typed: the row appears with the reason, amount
   and fee absent, caption shown. Pass. Observation: the recipient field
   still shows "Valid" with a green check above a row that says it cannot
   be paid.
3. Contact flow, contact "Other Server" with the address: caption plus
   reason, no amount field, no Send button. Pass. Observation: beneath it
   the pre-existing red error card "Cannot send to this contact - no
   viable payment methods" with Copy Error and Retry also renders (set in
   `SendViewModel+Initialization` when `initialPick` finds no viable
   row). It duplicates the caption and Retry cannot help. Test contact
   deleted afterwards.
4. BIP-21 `bitcoin:?ark=<minted>&lightning=test@example.com` (accepted
   without an onchain address): Payments row is the Lightning one, amount
   field present; after typing far above the ₿ 10,000 Payments balance
   the row reads "Need … more", is still the Lightning row, and the form
   does not collapse. Same via the typed route. Pass.

**Copy and layout rework (Christoph, from the screenshots, DECIDED
2026-11-04).** The screens said one thing two or three times ("Your Ark
server can't deliver to this address" in the row, "Your wallet has no way
to pay this" beneath, and in the contact flow the red "Cannot send to this
contact" card with a useless Retry), the copy named "Ark", which the app
avoids, and read badly. Rulings and what was built:

1. Copy: "Address belongs to a different server" (`viability_ark_unreachable`;
   "server" alone is established vocabulary from the server sheet). Caveat
   recorded: bark's answer is a plain no, and in rare cases the cause is an
   unsupported address type or a wallet without a server rather than a
   server mismatch.
2. One message, one place: the caption is gone everywhere
   (`L10n.sendNothingPayable` removed). Quick and manual flows show the
   row with its orange reason and nothing below. The contact flow, whose
   plain card has no reason line, shows the one reason in the row's style
   where the form would be.
3. The "no viable payment methods" error is not set when `nothingPayable`
   is true, at the three `initialPick` sites in
   `SendViewModel+Initialization`; the error card stays for real failures.
4. A row nothing can pay drops its "Pay from Payments" title:
   `DisplayDestination.unpayable`, read by `SheetDestinationDisplayView`,
   and `PaymentDestinationItem` skips an empty title.

Simulator re-check after the rework (same minted address, screenshots in
the day's index from 12:57 on): manual and quick flows show one card with
the shortened address and the orange line, nothing above or below;
the contact flow shows the orange line alone under "Sending to / Other
Server", no error card. Observation for Christoph: in the contact flow
the line floats centred with no card around it, which reads sparser than
the other two flows; the plain-address card is not rendered in this state
(pre-existing, the selected destination is not set when no row is
viable). Scoped suite 23 of 23 after the rework.

Left as is: the manual flow's "Valid" check above the row (the format is
valid; polish at most). Noted in passing, unrelated: the New Contact
editor showed an empty form again after Save, and a contact whose address
is not primary has no quick send button in the picker; Tier 3 Contacts if
confirmed on device.

**Simulator notes.** `simctl pbcopy` did not reach the app's pasteboard
on the headless simulator and `Simulator.app` was not running, so the
subagent copied text through an in-app field's Select All → Copy. The
Paste button appears only in Scan mode and clipboard presence is re-read
on appear / become-active, so a relaunch was needed after each copy.

## 8. Device check (owed)

On a Second wallet: paste a Zappin Ark address → row greyed with the reason,
send blocked with the same copy; a BIP-21 with Zappin Ark + Lightning →
Payments row is Lightning and pays, and stays Lightning once an amount is
typed; a same-server Ark address still ranks and pays. Offline cases: **cold
offline launch** (airplane mode on before launch, then paste a same-server
Ark address) → row viable, no "can't deliver" (unknown never blocks; this is
the case finding 1 would have broken); airplane mode after a warm session →
same-server address still viable.

## 9. Adversarial pass (2026-11-04, `fault-class-reviewer`, working-tree diff)

- **CONFIRMED, classes 5 and 4 — the connection gate was not strict.**
  `connectionStatus.isConnected` turns true after launch Step 2a's
  `syncArk()`, whose bark call cannot fail, so a cold offline launch would
  have made bark answer `false` for every Ark address and the app would
  have blocked same-server sends with the foreign-address copy. Fixed: the
  gate is bark's `arkInfo()` (C7b). Ledger line added.
- **CONFIRMED, class 2 — the carried verdict died with the dropped row.**
  `oneRowPerBalance` removes the unviable Ark row from the rows the view
  model holds, so the first typed-amount re-rank (fired by the first fee
  estimate) found no carried ids, rebuilt the Ark row viable and dropped
  Lightning. Fixed: verdicts live in `ArkAddressReachability`, read by
  `rank` on both paths; pinned by `rerankAfterDroppedArkRowKeepsLightning`.
  Ledger line added.
- **PLAUSIBLE, class 3/4 — no connect timeout.** With the stale gate, a
  ranking on a cold cell would have awaited a gRPC connect with bark's
  10-minute request timeout. Moot after the fix: the validation runs only on
  a warm cell, where it does no network I/O (C7b).
- **PLAUSIBLE, minor — other `Other` failures get the generic copy.** A
  changed server or mailbox pubkey, or a wallet created without a server,
  also yields `false`, so same-server addresses would read "Your Ark server
  can't deliver to this address". Accepted under ruling 2 (generic copy);
  those wallets cannot send Ark at all. Recorded here, no code change.
- Not verified by the reviewer: build and tests (run by the session), bark
  0.8.0 `Wallet::open`'s eager connect behaviour, tonic's connect timeout,
  `FundingSourceRow` rendering, two-device scenarios, desktop compilation.

## 10. Nothing payable: the form has nothing to offer (DECIDED 2026-11-04)

**Device evidence, Christoph, 2026-11-04, Coinos V3 beta (Coinos runs its
own Ark server):** a Coinos Ark address was refused with the reason and
could not be sent to; a BIP-21 with the Coinos Ark address, a Lightning
invoice and an onchain address offered Lightning and onchain only;
same-server addresses still paid. Observation: with the bare Coinos
address pasted, the amount field still accepted input although nothing
could be sent.

**Precedent.** The quick flow already hides the amount input and replaces
the Send button with an italic caption when the address is for another
network. That is the right model when nothing the user types can change
the outcome, and it respects the 2026-10-27 ruling (no reason line under
the button; the row explains).

**Rulings (Christoph, 2026-11-04):** hide amount and fee as proposed, not
disable in place; include in this release; fix the manual flow's missing
row in the same change; the cold-offline-launch device check follows after
the code work.

**The distinction that matters.** "No viable row" also holds for "Need
500 sats more", where the amount must stay editable. The rows now carry a
typed `ViabilityReason` (the string is derived from it) with
`blocksRegardlessOfAmount`: true only for blocks that belong to the
request itself, `arkUnreachable` and `lightningUnavailable`; false for
the shortfall, the viable reasons, and the two transient blocks.
`balanceUnavailable` is a loading gap that resolves by itself;
`serverNotConnected` lifts when the server returns, and the send form has
no trigger to re-rank on either, so hiding the field for them would leave
no way out but dismissing (§11, finding 3; the first cut had
`serverNotConnected` in the set). Transient rows stay grey with their
reason and the Send button stays disabled, as before.
`PaymentDestinationSelector.nothingPayable(_:)` is true when the ranking
is non-empty and every row is blocked that way; an empty ranking means
"not ranked yet", not "blocked". `sorted` orders viable rows first, then
fixable unviable rows, then dead ones, so `oneRowPerBalance` never lets a
dead Ark row displace a Lightning row the user could repair (§11,
finding 1).

**Built.** Quick flow: `needsAmountInput` is false, the fee row is not
rendered, and `L10n.sendNothingPayable` ("Your wallet has no way to pay
this") takes the button's place; the network-mismatch caption keeps
precedence. Manual flow: the pay-from row now also appears when nothing is
payable, so the reason has a place (before, a bare Ark address showed no
row at all and the user learned of it from the alert after tapping Send);
amount, fee and button are replaced by the caption. Only the view model's
live ranking counts there; the static BIP-353 fallback rows assume viable.
Contact flow: the same hide-and-caption, read from the live ranking
(`effectiveRankedDestinations`); a plain contact address renders a simple
card with no reason line, so the caption there carries the first row's
reason beneath it (§11, finding 2; the first cut read the view's own
BIP-353-only ranking and claimed the rows showed reasons).

**Sweep.** `RankedDestination.reason` stays as a computed string, so the
view model's logs, `DisplayDestination` and the examples file compile
unchanged; the one constructor is `rank`; no file under `ArkeDesktop/`
reads `RankedDestination`. Desktop not built (parked). `SendBlocker`
untouched: it gates a visible button, and in this mode none of the three
flows renders one.

**Tests.** `foreignArkAloneIsNothingPayable`, `shortfallKeepsTheForm`,
`anyViableRowKeepsTheForm` (also the empty ranking),
`serverDownLightningKeepsTheForm`, `amountAboveBalanceKeepsTheFixableRow`.

**Device check (owed, on top of §8).** Quick flow with a bare Coinos
address: row greyed with the reason, no amount field, no fee row, caption
in the button's place. Manual flow with the same address typed: the row
appears with the reason, same hiding. Contact flow with a contact holding
a Coinos Ark address: caption plus reason, no amount field. A same-server
address with an amount above the balance: amount field stays, row says
"Need … more". A BIP-21 with Coinos Ark + Lightning and an amount typed
above the Payments balance: the Lightning row stays with "Need … more"
and the amount field stays (§11, finding 1).

## 11. Adversarial pass on §10 (2026-11-04, `fault-class-reviewer`)

- **CONFIRMED, class 2 — a dead row displaced the fixable one.**
  `nothingPayable` was composed over `oneRowPerBalance`'s output. With a
  foreign Ark and a Lightning option, typing past the Payments balance
  made both rows unviable; priority then preferred Ark, the reducer kept
  the dead Ark row, and the form collapsed with no field left to lower the
  amount. Fixed in `sorted`: fixable unviable rows outrank dead ones.
  Pinned by `amountAboveBalanceKeepsTheFixableRow`. Ledger line added.
- **CONFIRMED, classes 2 and 5 — the contact flow read the wrong ranking.**
  Its nothing-payable check read the view's own `@State` ranking, written
  only for BIP-353, so for a plain contact address it was always empty and
  nothing was hidden; the plain card also shows no reason, contrary to the
  §10 text. Fixed: reads `effectiveRankedDestinations`; the caption carries
  the first row's reason. Not pinned by a unit test (view composition);
  on the device list. Ledger line added.
- **PLAUSIBLE, class 3 — no exit from the mode for a transient reason.**
  Every re-rank trigger sits behind a control the mode removes, and nothing
  re-ranks on connection change, so a `serverNotConnected` entry would have
  been sticky once the connectivity gap is fixed (today the flag never goes
  false mid-session, so the state was unreachable). Resolved by scope:
  `serverNotConnected` is no longer in `blocksRegardlessOfAmount`; the
  mode is reserved for blocks that belong to the request itself.
- **PLAUSIBLE, class 2, cosmetic — re-paste flash.** Pasting a second
  request clears the ranking before the new one lands, so the old form can
  show for a frame. Pre-existing shape, sub-100 ms expected; not changed.
- Not verified by the reviewer: device behaviour, bark `Wallet::sync`
  error swallowing, SwiftUI focus state when the field leaves the
  hierarchy, desktop compilation.
