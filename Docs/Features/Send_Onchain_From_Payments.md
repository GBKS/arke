# Send Onchain From Payments: A Second Funding Source For Bitcoin Addresses

**Status: DONE 2026-10-28 (Tier 1 "Send and fees", Train 2): built,
reviewed, picker reworked the same day after Christoph's first look (§9,
§9.2), device-checked on signet (§6). Asked by Neil (Second) on 2026-10-07,
planned 2026-10-27. Default source and the five picker rules were DECIDED
2026-10-10 (Done log); rule (1)'s "settles at the next round" rested on a
wrong claim (§2.1) and was replaced 2026-10-27 (§7). The adversarial pass
(§8) confirmed three findings and raised four plausible ones; all seven
are fixed in the same tree. Full mobile suite after §9.2: 617/617 (§8).**

## 1. What is wrong today

A bitcoin address can only be paid from Savings. Verified by trace:

- `PaymentDestinationSelector.balanceSource(for:)` maps `.bitcoin` and
  `.silentPayments` to `.bitcoin`, so `availableBalance(for:)` reads the
  onchain balance and `rankDestination` emits one entry per address.
- `SendViewModel.executePayment` routes `.bitcoin` / `.silentPayments` to
  `walletManager.sendOnchain`, the BDK onchain wallet at the chosen tier.
- The Ark-to-onchain path exists at every layer below the view model:
  `BarkWalletProtocol.sendToOnchain` / `estimateSendToOnchainFee`,
  `BarkWalletFFI+Transactions.sendToOnchain` (bark `Wallet.sendOnchain`),
  `WalletOperationsService.sendToOnchain`, `WalletManager.sendToOnchain`.
  Its only UI caller is `OffboardingModalView.performOffboarding`, which
  sends to the wallet's own onchain address. The estimate is also called
  from `OffboardingModalFormView` and from the "Ark balance to onchain"
  branch of `SendViewModel.calculateMaxSendableOnchain`, which is
  unreachable: `balanceSource` never returns `.ark` for a bitcoin address.

Consequence (Neil's report, and the backlog's "scanned Noah QR, onchain
failed with error building tx"): a user with coins only in Payments sees a
bitcoin address as "Exceeds balance" or gets a BDK build error, although
bark could pay it from the offchain balance.

## 2. What bark actually does (verified at bark-0.8.0, bindings 4670c1a)

### 2.1 The path is a collaborative offboard, not a round

`Wallet::send_onchain` (`bark/src/offboard.rs:66`) starts an offboard
action with `StartOffboardSpec::SendOnchain { amount }`. Per
`bark/src/actions/offboard.rs`: bark first runs an arkoor split to produce
an exact-sized VTXO plus change, registers the split with the server, asks
the server to build the offboard transaction (`prepare_offboard`), signs
its forfeits, and broadcasts. The call returns at
`Progress::AwaitingConfirmations` with `OffboardResult { txid,
movementId }`. No round participation anywhere on the path; the recipient
sees an unconfirmed onchain transaction right away and it confirms like
any Bitcoin payment. The same shape exists at bark-0.7.0 and 0.7.1
(`offboard.rs:55`), so the "round-based path, settles at the next round"
wording in the 2026-10-07 backlog entry and in DECIDED rule (1) was wrong
when written.

### 2.2 The fee

`start_offboard` fetches `srv.offboard_feerate()` and prices the send with
`ark.fees.offboard.calculate(destination_spk, amount, offboard_feerate,
vtxo)` through `spend_input_selection().fee_scheme(…)`; the fee depends on
which VTXOs get selected (the ppm-by-expiry table) and on a rate the
server chooses. There is no client-side priority. The bindings expose
`estimateSendOnchainFee(address:amountSats:) -> FeeEstimate` (gross, fee,
net, `vtxosSpent`); the app wraps it as `estimateSendToOnchainFee`. The
fee is added on top of the amount (`deduct_fees_from_gross_amount` is
false for `SendOnchain`), so the recipient receives exactly the amount.
The app cannot compute this fee itself (backlog Tier 4, "three `getPpm`
copies" entry); it must ask bark.

### 2.3 Error path: a thrown error does not mean nothing happened

`run_offboard` persists a checkpoint before driving. A transient failure
parks the action and the call throws "could not complete yet … remains
pending and will be retried on wallet sync"; `sync_pending_offboards`
re-drives it on the next sync. A rejection by the server fails the
movement and releases the inputs. The UI therefore cannot treat an error
from `sendToOnchain` as "not sent": the pending amount appears in
`Balance.pendingOffboardSats` (mapped into the balance card's held figure
since v0.26) and the payment may complete minutes later.

### 2.4 Which balance is spendable this way

`Balance.spendableSats` excludes `needsRefreshSats` (VTXOs expired or at
the server's exit-depth limit), and bark's input selection for
`send_onchain` skips VTXOs at the depth limit (test name
`send_onchain_skips_vtxos_at_exit_depth_limit`, `testing/tests/server/mod.rs:820`,
read by name only). `walletManager.arkBalance?.spendableSat`, which the
send flow already uses for Lightning, is therefore the right viability
balance for a Payments-funded onchain send.

### 2.5 What the movement looks like

`get_or_create_movement` records `Subsystem::OFFBOARD`, kind
`send_onchain`, the fee, and `.sent_to([MovementDestination::bitcoin(destination, net)])`.
The app maps `bark.offboard` + `send_onchain` to `MovementCategory.onchainSend`
(`MovementCategory.from`), so a third-party send lands in the same category
as today's own-address offboards from the modal. `TransactionService+AddressLinking`
links `receivingAddress` when `AddressService.isOwnAddress` is true, and
`PersistentTransaction.isInternalTransfer` for `.onchainSend` is exactly
`receivingAddress != nil`. The pending-metadata match
(`findTimestampBasedMatch`: time window, exact amount, address) works
unchanged because the movement destination carries the address and net
amount.

## 3. Design

### 3.1 Model: the funding source becomes part of the choice

- `PaymentDestinationSelector.BalanceSource` gains a case for "Payments
  balance, offboarded through the Ark server" (working name
  `.arkToOnchain`; display name "Payments Balance", network name "Bitcoin
  Network via Ark"). `.arkViaServer` is not reused: it implies the
  Lightning capability check.
- `rankDestination` becomes `rankDestinations(for:)`, returning one
  `RankedDestination` per (destination, source). For `.bitcoin` it emits
  the Savings entry (unchanged) and a Payments entry whose
  `availableBalance` is `context.arkBalance`, whose fee comes from
  `estimateSendToOnchainFee` when an amount is known and is nil otherwise
  (no static constant, DECIDED 2026-10-27 for Lightning), and whose
  `priority` is the Savings priority plus one so it sorts right after
  Savings and before `.bip353`. `.silentPayments` gets no Payments entry:
  bark's offboard takes a `bitcoin::Address` script, and a silent-payment
  output needs sender-side key derivation bark does not do (derived from
  the `OffboardRequest { script_pubkey, … }` shape; not executed).
- `PaymentDestination` is not touched. It is `Codable` and feeds
  `ContactAddressModel`; a funding flag on it would leak into persistence.
  Instead the view model gets `selectedFundingSource: BalanceSource?` next
  to `selectedDestination`, and every "which row is selected" comparison
  moves from `destination.id` to a small `Hashable` key
  (`destination.id`, `balanceSource`). `DisplayDestination` carries the
  `BalanceSource` value, not only its display name.

### 3.2 Ranking cadence (DECIDED rules 2 and 3)

- Smart pick once on load with whatever the request carries (today's
  `lockInPaymentRequest` / `enterQuickMode` / `rankManualDestination`).
  Savings is the default when both are viable (rule 1). Without an amount
  every row is viable, so the pick (`PaymentDestinationSelector.initialPick`)
  prefers the first viable row whose balance holds anything: an empty
  Savings balance starts the address on Payments, which is Neil's case
  (review F3 found the first draft never reached this).
- Re-rank with the typed amount, debounced like the Lightning fee, so the
  Payments row's fee and both rows' viability stay current (today ranking
  runs once at parse time; `QuickPaymentView` re-ranks only on appear and
  on request change).
- No automatic switch during amount input. `QuickPaymentView`'s
  `onChange(of: amount)` currently re-selects the optimal entry when the
  current one turns non-viable; rule (3) retires that. The exceeds-balance
  state carries the information instead (rule 4: name both balances when
  neither covers amount plus fee).

### 3.3 Fee row, picker and gate

- Savings source: unchanged (BDK per-tier quote, speed sheet,
  `OnchainFeeQuote`, `SendBlocker` onchain branch).
- Payments source: fee row shows bark's estimate as `.value`,
  `.estimating` while the request is open, `.unavailable` when it failed;
  no speed disclosure (`shouldShowFeeDisclosure` false), no mainnet
  ceiling check (the rate is the server's, not Esplora's). `SendBlocker`
  treats this source like Lightning, not like the BDK path: `isOnchain`
  must mean "Savings through the shadow estimator", as its doc comment
  already says, so the flag is derived from the selected source and not
  from the format. `.unavailable` blocks Send for this source (DECIDED
  2026-10-27; Lightning still passes, which is a separate line if ever).
- `isOnchainDestination`, `maxSpendableAmount`, `availableBalanceText`
  and `calculateMaxSendable` read the selected source. The existing
  "Ark balance to onchain" send-all loop in `calculateMaxSendableOnchain`
  becomes reachable; its convergence logic needs the same review the BDK
  branch got on 2026-10-27 (no cap-and-refit exists for it yet).

### 3.4 Execution

`executePayment` routes on (format, source): `.bitcoin` + Payments calls
`walletManager.sendToOnchain(to:amount:)`; pending metadata keeps
`paymentType` "onchain". The fresh pre-send ranking passes the bark fee as
`exactFee`. Errors are classified at the FFI boundary: bark's parked
message ("could not complete yet … retried on wallet sync", the only
signal the binding carries) becomes `BarkWalletFFIError.offboardPending`,
which the send flow and the offboarding modal both word as "did not
complete yet, retried on the next sync, shows as pending" (§2.3); every
other failure happened before bark committed anything and reads as a plain
failure (review F5). A later item can adopt `OffboardResult.movementId`
to attach metadata by id (Track B, `Bark_Bindings_Unadopted_API.md`).

### 3.5 Activity labels

Three sites in `TransactionModel+DisplayHelpers` (`.onchainSend` with
`subsystemName == "bark.offboard"` → "Moved …" / "Payments to savings")
and two in `TransactionIconView` (same test → offboarding icon) key on
`isInternalTransfer` instead, so a third-party send from Payments reads
"Sent" / "From savings" and the modal's own-address offboard keeps
"Moved". The display code runs on ArkéUI's `TransactionModel`, whose
`isInternalTransfer` for `.onchainSend` was itself the subsystem test
(review F1): the own-address link now crosses the bridge as
`TransactionModel.sentToOwnAddress`, set from `receivingAddress != nil`
in `TransactionModel+Persistence`. Until the address-linking pass runs
after the upsert, a fresh own-address offboard reads "Sent" for a moment.
`FeeSummaryView` needs no change: `FeeSummaryViewModel.classifyTransaction`
already splits sends from internal moves by `isInternalTransfer`, and the
"Move to Savings" figure that folds `onchainSend` into offboarding reads
only the internal bucket, so a third-party send lands under "Average Send
Fee" on the Bitcoin network (verified 2026-10-27). **Verify before
building (assumed):** that the address the
offboarding modal sends to (`manager.onchainAddress`) is one
`AddressService.isOwnAddress` knows, or the modal's offboards regress from
"Moved" to "Sent".

### 3.6 Row copy

Both rows show source, address and fee; no settlement caption (DECIDED
2026-10-27, replacing rule (1)'s "settles at the next round"):

- Savings row: unchanged ("Savings (Bitcoin)", address, fee at the chosen
  speed).
- Payments row: title "Payments (Bitcoin)", address, "Fee ~X" from bark.
  `AddressFormat.simplifiedDisplayName` bakes "Savings" into the
  `.bitcoin` name, so the row title has to come from the source, not the
  format.

## 4. Sibling sweep (to be re-run at build time)

| Pattern | Sites | Plan |
|---|---|---|
| `balanceSource(for:)` callers | `PaymentDestinationSelector` (rank, availableBalance, requiresServerRouting), `SendViewModel+ComputedProperties`, `SendViewModel+MaxSendable`, `PaymentDestinationSelectorExamples` | all read the selected source; Examples file is sample code, exempt |
| Selection by `destination.id` | `SheetDestinationDisplayView`, `QuickPaymentView`, `ContactPaymentView` (binding), `SendViewModel+ComputedProperties.feeDisplayState`, `SendViewModel+PaymentExecution` (cached ranking fallback), `ConfirmedDestinationCard` (counts only) | composite key |
| `isOnchainDestination` readers | `SendViewModel+FeeEstimation`, `+ComputedProperties` (fee state, gate), flows' fee disclosure | source-derived |
| `bark.offboard` display tests | `TransactionModel+DisplayHelpers` ×3, `TransactionIconView` ×2, `FeeSummaryView` | `isInternalTransfer` |
| `sendToOnchain` callers | `OffboardingModalView`, new send path | shared error wording for the parked case |

## 5. Tests

No `PaymentDestinationSelector` suite exists today (only
`OnchainRoughFeeEstimateTests` touches it). Add pure-logic tests, runnable
with the xcodebuild recipe:

- ranking emits Savings then Payments for `.bitcoin`, nothing extra for
  `.silentPayments`, Lightning and Ark;
- Savings first when both viable; Payments the first viable when Savings
  is empty; Payments non-viable when `arkBalance < amount + fee`;
- fee is nil for the Payments row when the estimate fails (no constant);
- `SendBlocker` for the Payments source: `.estimating` blocks, no tier
  cases, no ceiling case;
- the Activity label decision: "Moved" only with a linked receiving
  address, for both `offboard` and `send_onchain` kinds.

## 6. Review and device

Money path and FFI boundary: Tier 1 process in full. Adversarial pass by
`fault-class-reviewer` on the commit range before the full mobile suite.
Device day on signet with the simulator test wallet and the phone: send
from Payments to a third-party address (the other wallet's onchain
address) with Savings empty and with Savings funded; one own-address
offboard from the modal to confirm "Moved" survives; one forced parked
error if reachable (airplane mode after the arkoor step) to see the error
wording and the held balance. Not seed-touching.

Device check, 2026-10-28, Christoph on his phone, signet, latest tree
(including the §9.2 caption): payments both ways between Arké and the
Noah signet wallet over Ark, Lightning and onchain, plus boarding and
offboarding. The send from Payments to Noah's onchain address ran with
Savings empty and with Savings funded; it showed in Activity as an onchain
payment, and the own-address offboard from the modal still showed
"Moved". All worked. Not run: the forced parked error (optional above);
`BarkWalletFFIError.offboardPending` and its wording are covered by
reading and the review only.

## 7. Rulings

DECIDED 2026-10-27: no settlement caption on the Payments row (§3.6
replaces rule (1)'s wording); a failed bark estimate blocks Send for the
Payments source (§3.3). `FeeSummaryView` needs no change (§3.5).

### 7.1 Open: the quick flow's auto-switch

`QuickPaymentView.onChange(of: amount)` re-selects the first viable entry
whenever the currently selected one is non-viable in `rankedDestinations`.
Today that list is built once on appear, usually without an amount, so
every entry is viable and the switch almost never fires. Rule (3) adds
re-ranking with the typed amount; from then on a Savings selection that
stops covering the amount would be swapped for Payments mid-keystroke,
which is exactly what rule (3) forbids. The two cannot coexist. Options:

- (a) **Retire the switch in this change** (recommended). Re-ranking and
  the switch are one behaviour; shipping one without the other either
  leaves the stale list in place or introduces the forbidden swap. The
  exceeds-balance state already tells the user the selected source cannot
  cover the amount, and the row opens the picker. Side effect: Lightning
  versus Ark alternatives from a BIP-21 or BIP-353 request also stop
  switching, which is rule (3) applied as written.
- (b) **Keep the switch, re-rank anyway.** Violates rule (3) as soon as
  the typed amount crosses a balance.
- (c) **Re-rank only for the picker rows, switch on nothing.** Same result
  as (a) with more code paths.

DECIDED 2026-10-27: (a), in this change.

## 8. Review (fault-class pass, 2026-10-28)

Fresh-context `fault-class-reviewer` over the working-tree diff. All
fixed the same day; ledger lines for the four that were defects of this
session's own draft.

| # | Verdict | Class | Finding | Fix |
|---|---|---|---|---|
| F1 | CONFIRMED | 5, 2 | Activity relabel was a no-op: ArkéUI `TransactionModel.isInternalTransfer` for `.onchainSend` was the subsystem test; the own-address link never crossed the bridge | `sentToOwnAddress` on the model, bridged from `receivingAddress`; `OnchainSendLabelTests` |
| F2 | CONFIRMED | 2 | Manual BIP-353 picker lost its alternatives: selecting fired `rankManualDestination`, which rebuilt a one-destination ranking | request handed to the view model first; `rankManualDestination` ranks the request when it holds the destination |
| F3 | CONFIRMED | 5 | "Empty Savings starts on Payments" never happened without a request amount (every row viable) | `initialPick` prefers a row whose balance holds anything |
| F4 | PLAUSIBLE | 3 | Offboard fee keyed on the request amount, row and debounce on the typed one; "still current" returned before the flag's `defer` | one `offboardEstimateAmount` key; early return clears the flag |
| F5 | PLAUSIBLE | 4 | "May still complete" wording applied to failures that happen before bark's checkpoint | `BarkWalletFFIError.offboardPending` classified by bark's parked message; plain failure otherwise; modal shares the wording |
| F6 | PLAUSIBLE | 2 | Payments send-all loop returned its last probe even when it did not fit | returns the largest amount whose gross fitted, else nil |
| F7 | PLAUSIBLE | 3 | Quick-flow tap re-ranked the whole request, pricing the Payments row at the server before a Savings send | the live ranking is used when it covers the request |

Not verified by the pass or since: any device behaviour (no signet send
from Payments executed), the pending-metadata match for an offboard
movement, bark's executor error path beyond `run_offboard`, fee drift
between estimate and send if input selection differs, the desktop target
(changed, not built, parked by rule). The quick view's offboard fee label
when the cache is empty renders the row's dash; a worded "not available"
state is a copy follow-up.

## 9. BUILT 2026-10-28 — the picker asks "Pay from", not "Select Payment Method"

Christoph's first simulator look: the sheet repeats the contact card and
the address on every row and its title names the old question. The
sheet predates this change (built for "which of these addresses"); the
common case is now one address paid from two balances.

Proposal: every row is a balance plus a way out of it (Payments via
Lightning / Ark / Bitcoin, Savings via Bitcoin), so one row shape covers
both questions.

- Title "Pay from".
- Row: balance name primary ("Payments" / "Savings"), available amount
  under it; trailing the fee for the typed amount, "Free", or the
  non-viable reason in orange. Gold border on the selected row as today.
  The rail ("Lightning", "Ark", "onchain") appears as a caption only
  when two rows share a balance and need telling apart (a BIP-21 where
  Payments can pay via Lightning or onchain). It is never "Bitcoin": the
  currency is always bitcoin, and the address beneath already shows the
  rail (Christoph, 2026-10-28).
- No contact and no address per row; the form already shows the
  recipient. The short address returns only when two rows share balance
  and rail (a contact with two bitcoin addresses).
- Collapsed row in the form: the balance alone ("Savings" / "Payments")
  with the address beneath, replacing `AddressFormat.simplifiedDisplayName`'s
  "Savings (Bitcoin)" / "Payments (Lightning)" titles.
- Localize the ranker's reason strings ("Need X more", "Ark server not
  connected"), which are English today and become more visible.

Considered and parked: an inline segmented "Savings | Payments" control
for the two-row case. Cannot show balance, fee and reason per option, and
the quick flow still needs the sheet for three rows; revisit after the
device look if two rows still feel heavy.

DECIDED 2026-10-28 ("build it"): title "Pay from"; no recipient in the
sheet; row and collapsed titles are the balance alone, the rail only as
a disambiguating caption.

Built as `FundingSourceRow` (ArkéUI, previewable) inside the existing
sheet in `SheetDestinationDisplayView`; `BalanceSource.shortName` /
`railName` carry the words, `DisplayDestination.title` / `railName`
expose them, and the ranker's reasons are localized. One stumble caught
by `rowTitlesNameTheBalance`: the first key names collided with the
existing `balance_payments` / `balance_savings` catalog entries ("Payments
Balance"), which kept their value; renamed to `funding_source_*`. The
old `nav_title_select_payment_method` and the short-lived
`send_source_payments_bitcoin` keys have no users.

### 9.1 DECIDED and BUILT 2026-10-28 — one row per balance

Christoph's phone, a BIP-21 with an Ark and a bitcoin address: three rows
("Payments Ark", "Savings", "Payments onchain"), the first and third
reading as duplicates, rail captions showing. The Payments-onchain twin
of the bitcoin address is dominated whenever the same request lets the
Payments balance reach the payee directly (Ark or Lightning): same
balance, a fee instead of free, an onchain confirmation instead of an
instant transfer. It earns its place only for a bare bitcoin address.

Proposal: after ranking, keep one row per balance, the best-ranked
viable path for that balance (priority order already puts Ark before
Lightning before onchain). Savings stays the bitcoin address. With each
balance appearing once the rail captions never fire, so "Ark" and
"onchain" leave the sheet; the collapsed row's address prefix shows the
rail. Tests: BIP-21 with Ark + bitcoin yields Payments (Ark) and Savings
only; a bare bitcoin address still yields Savings and Payments.

Known edge, to file separately: an Ark address from another server
would win the Payments row and bark would reject it, while the dominated
path would have worked. The ranker does not check Ark reachability; the
0.26 bindings' address validation call is the fix, out of scope here.

DECIDED 2026-10-28: one row per balance. Built as
`PaymentDestinationSelector.oneRowPerBalance`, applied after sorting in
both `rankDestinations(from:)` and `rerankDestinations`; rows on the kept
row's own rail survive (two bitcoin addresses stay two rows). Tests
`oneRowPerBalanceDropsTheDominatedPath`, `sameRailRowsAreNotDominated`.

### 9.2 DECIDED and BUILT 2026-10-28 — the collapsed row says "Pay from"

Christoph's phone, a contact's bitcoin address: the collapsed row showed
"Savings" directly above Testo's address, inside the recipient card. In
that position a caption describes the thing beneath it, and contacts carry
several addresses, so it read as "Testo's savings address", not as the
balance the money leaves. Amends §9's "collapsed row: the balance alone".

DECIDED 2026-10-28: the collapsed caption reads "Pay from Savings" /
"Pay from Payments", same position and style; the sheet rows keep the
balance alone, since the sheet title already says "Pay from". Built as
`DisplayDestination.payFromTitle` (key `send_pay_from_source %@`), used
only by `SheetDestinationDisplayView.primaryDestinationItem`; test
`collapsedRowSaysPayFrom`. Where a flow passes `formatNameOverride` (a
BIP-353 name, a contact's address) the override still replaces the
caption, unchanged by this ruling.

Considered and filed as PROPOSED (`Open_Follow_Ups.md`, Tier 3 Send):
move the source control out of the recipient card into the amount card's
balance row.

Full mobile suite, iPhone 17 Pro simulator, 2026-10-28: 580 of 580
passed after the review fixes (`Test-Arke mobile-2026.10.28_08-03-25`)
and again after the §9 picker rework (`…_08-36-48`). After the §9.1
rulings, 616 of 616 (`…_11-33-40`); after §9.2, 617 of 617
(`…_17-14-49`).
The scoped suites (`PaymentDestinationSelectorTests`, `SendGateTests`,
`OnchainSendLabelTests`, bridging and metadata suites) ran separately
first, 49 of 49.
