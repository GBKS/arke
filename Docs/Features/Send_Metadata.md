# Send Metadata

**Status:** Shipped 2026-06-24 (phases 0, 1, 3a, 3b), post-implementation fixes
2026-06-24 (race condition, re-application guard, `hasBeenApplied`, dual write);
write paths made fetch-resolved 2026-09-25; rewritten as a reference 2026-09-27.
The original phase-0 report is in
`../Archive/Implementations/send-metadata-enhancement_phase_0_complete.md`.

Related: `Tag_System.md` (the `TransactionTagAssignment` shape that
`PendingTagAssignment` mirrors), `../Send/SendView_Architecture.md` (where
`+PendingMetadata.swift` sits in the view model), `Wallet_Deletion_And_Rejoin.md`
(wipe coverage).

## Overview

While a payment is in flight the send modal shows three buttons — contact,
tags, note — and the user can fill them in during the sending, success, and
error states. The problem this solves: bark's payment calls return no movement
id, so at send time there is no transaction row to attach metadata to. The
transaction only appears when the next movement sync upserts it.

The feature bridges that gap with a `PendingPaymentMetadata` row created just
before the FFI call. It records what the app knows about the payment (type,
destination, amount, timestamp, and — for settled Lightning payments — the
payment hash) plus whatever the user assigns. When a movement is upserted,
`TransactionService` looks for a matching pending row and copies the contact,
tags, and note onto the `PersistentTransaction`. Edits made after the match are
written to the transaction directly.

## Data model

`Shared/Models/PendingPaymentMetadata.swift` holds both models. They are part
of `SwiftDataHelper.appSchemaModels`, so they live in the same store as the
transaction rows and are included in the full wallet wipe
(`WalletDataCleanupService.deletePendingSendMetadata`).

```swift
@Model
final class PendingPaymentMetadata {
    // Matching identifiers
    var paymentHash: String?          // Lightning only; set after the payment settles
    var destinationAddress: String?
    var amountSats: Int?
    var paymentType: String?          // "lightning" | "ark" | "onchain" | "bip21" (logging only)
    var timestamp: Date = Date()      // when the send was initiated

    // Metadata
    var notes: String?
    @Relationship(deleteRule: .cascade, inverse: \PendingTagAssignment.pendingMetadata)
    var tagAssignments: [PendingTagAssignment]? = []
    @Relationship(inverse: \PersistentContact.pendingPaymentMetadata)
    var contact: PersistentContact?

    // Lifecycle
    var createdAt: Date = Date()
    var isMatched: Bool = false
    var matchedTxid: String?
    var hasBeenApplied: Bool = false

    init(paymentHash: String?, destinationAddress: String?, amountSats: Int?,
         paymentType: String?, timestamp: Date = Date())

    var liveTagAssignments: [PendingTagAssignment]   // fetch-resolved, see below
    var associatedTags: [PersistentTag]
    var hasTags: Bool; var hasContact: Bool; var hasNotes: Bool; var hasMetadata: Bool
    func markAsModified()                            // hasBeenApplied = false
}

@Model
final class PendingTagAssignment {
    var assignedDate: Date = Date()
    @Relationship var tag: PersistentTag?
    @Relationship var pendingMetadata: PendingPaymentMetadata?
    init(tag: PersistentTag, pendingMetadata: PendingPaymentMetadata, assignedDate: Date = Date())
}
```

Inverses live on the existing models: `PersistentContact.pendingPaymentMetadata:
[PendingPaymentMetadata]?` and `PersistentTag.pendingTagAssignments:
[PendingTagAssignment]?`.

On the transaction side nothing was added. The matched metadata lands in the
pre-existing `PersistentTransaction.notes`, `TransactionTagAssignment`, and
`TransactionContactAssignment` rows:

```swift
@Model
final class TransactionContactAssignment {
    var assignedDate: Date = Date()
    @Relationship var contact: PersistentContact?
    @Relationship var transaction: PersistentTransaction?
    init(contact: PersistentContact, transaction: PersistentTransaction, assignedDate: Date = Date())
}
```

### Fetch-resolved tag reads

`liveTagAssignments` does not read the cached `tagAssignments` array. A
CloudKit import can delete `PendingTagAssignment` rows underneath that array,
and touching a property on a deleted instance traps. The accessor fetches the
whole `PendingTagAssignment` table (tiny — only unmatched sends) and filters by
`pendingMetadata?.persistentModelID`, which is instance metadata and cannot
fault. `associatedTags`, `hasTags`, and every write path below go through it.

## Lifecycle of a pending row

### 1. Creation (`SendViewModel+PendingMetadata.swift`)

`SendViewModel.executeSend()` calls `createPendingMetadata(paymentHash: nil,
destination:amount:paymentType:)` after the destination and amount are
resolved and validated, immediately before routing to the payment method. The
row is inserted and saved, and the reference is kept in
`SendViewModel.pendingMetadata` so the modal can bind to it.

`paymentType(for: AddressFormat)` maps `.bitcoin`/`.silentPayments` to
`"onchain"`, `.lightningInvoice`/`.lightning`/`.lnurl`/`.bolt12` to
`"lightning"`, `.ark`/`.bip353` to `"ark"`. It is recorded for logging only;
matching does not read it.

Every `executeSend()` creates a fresh row. A failed send leaves its row behind
(unmatched, deleted by the 24 h cleanup) and a re-send starts with a new, empty
one — metadata entered during a failed attempt is **not** carried over.

### 2. Payment hash (Lightning only)

Bark returns the payment hash only in `LightningSendStatus.paid(paymentHash, _)`.
After each Lightning path (invoice, address, BOLT12, LNURL, and the send-max
retry loop) the view model calls `extractPaymentHash(from:)` and, when present,
`updatePendingMetadataWithPaymentHash(_:)`. `.inProgress` and `.unknown` yield
no hash; those payments fall back to timestamp matching. Ark and onchain sends
never have a hash.

Because the hash is written after the FFI call returns, a movement sync that
races ahead of it matches by timestamp instead. The result is the same row.

### 3. Note pre-population

`prepopulateNoteIfNeeded()` runs right after creation and again after LNURL
resolution (the LNURL description isn't known until then). It only fills an
empty note. `extractPaymentNote()` applies only to `SendMode.quick` and tries,
in order:

1. BIP-21 `label` and `message`, joined as `"{label} - {message}"` when both exist.
2. The BOLT-11 invoice description (`LightningInvoiceParser.extractAmountAndDescription`)
   when `primaryFormat == .lightningInvoice`.
3. `resolvedLNURL?.descriptionText`.

### 4. Matching (`TransactionService+PendingMetadata.swift`)

`upsertTransactionsFromServerData` calls `applyPendingMetadata(to:)` for every
transaction it inserts **and** every existing one it revisits. Matching runs in
`findPendingMetadata(for:context:)` in this order:

| Priority | Rule | Notes |
|---|---|---|
| 0 | `isMatched && matchedTxid == transaction.txid` | Re-application for a row already bound to this transaction |
| 1 | `paymentHash == transaction.paymentHash` among unmatched rows | Exact, case-sensitive; skipped when the transaction has no hash |
| 2 | Timestamp + amount + address among unmatched rows | Best effort, all payment types |

Priority 2 (`findTimestampBasedMatch`) filters unmatched rows by
`abs(timestamp - transaction.date) <= 300 s` (a symmetric ±5 minute window,
`matchingTimeWindow`), then `amountSats == transaction.amount`, then
case-insensitive `destinationAddress == transaction.address` (both must be
non-nil). If several survive, the one whose timestamp is closest to the
transaction date wins and a warning is logged. Losers stay unmatched.

Only unmatched rows are candidates for priorities 1 and 2, and priority 0
short-circuits once a transaction has a row, so the binding is one-to-one: a
pending row matches at most one transaction and a transaction is bound to at
most one row.

Unmatched rows are never matched by payment type, `createdAt`, or any parsed
string from the bark response — the plan's "fallback string parsing" was never
needed.

### 5. Application

`applyPendingMetadata(to:)`:

1. Returns early with a debug log if the matched row has `hasBeenApplied == true`.
2. Copies the note **only if the transaction has none** (never overwrites).
3. Inserts a `TransactionContactAssignment` unless `transaction.hasContact(contact)`.
4. Inserts a `TransactionTagAssignment` for each of `associatedTags` unless
   `transaction.hasTag(tag)`.
5. On first match sets `isMatched = true` and `matchedTxid`; always sets
   `hasBeenApplied = true`.

The row is **not** deleted on match. The user may still be editing it in the
modal, and deleting it would send those edits to a dead object.
`hasContact`/`hasTag` are fetch-based for the same CloudKit-import reason as
`liveTagAssignments`. The upsert loop saves the context; this method does not.

### 6. Editing (`SendMetadataSection.swift`)

Each edit writes to the pending row, then checks `findMatchedTransaction()`
(a `PersistentTransaction` fetch by `matchedTxid`):

- **Transaction exists** — the change is applied to the transaction directly
  as well, so the activity list updates without waiting for a sync. Contact:
  delete all `liveContactAssignments`, insert the new one (or none). Tags:
  delete all `liveTagAssignments`, insert the selected set. Note: assign.
- **Transaction does not exist yet** — `markAsModified()` resets
  `hasBeenApplied` so the next upsert re-applies the whole row.

Both branches end in `try? modelContext.save()`.

### 7. Cleanup

`cleanupOldPendingMetadata()` runs at the top of every
`upsertTransactionsFromServerData` (every movement sync, foreground or
background):

- Matched rows with `createdAt` older than **1 hour** are deleted.
- Unmatched rows with `createdAt` older than **24 hours** are deleted, each
  logged via `logUnmatchedMetadata` (type, amount, age, what metadata it held,
  whether a hash was present).

Both windows are measured from `createdAt`, not from the match time.

## Components

| Component | File | Role |
|---|---|---|
| `SendViewModel.pendingMetadata` | `Shared/Views/Send/SendViewModel/SendViewModel.swift` | The current send's row; bound into the modal from `SendView_iOS` and the desktop `SendView` via `$viewModel.pendingMetadata` |
| `SendViewModel+PendingMetadata` | `Shared/Views/Send/SendViewModel/SendViewModel+PendingMetadata.swift` | `createPendingMetadata`, `extractPaymentHash`, `paymentType(for:)`, `updatePendingMetadataWithPaymentHash`, `extractPaymentNote`, `prepopulateNoteIfNeeded` |
| `SendViewModel+PaymentExecution` | `Shared/Views/Send/SendViewModel/SendViewModel+PaymentExecution.swift` | Calls the above around each payment path |
| `SendModalView` | `Shared/Views/Send/SendModalView.swift` | Owns `SendModalState` (`.sending`, `.success`, `.error(String)`), runs `performSend`, enforces the 800 ms minimum sending display, passes the binding down |
| `SendModalContentView` | `Shared/Views/Send/SendModalContentView.swift` | Single view for all three states: reaction video (`ReactionVideoPair.random()`, idle for sending/error, thumbs-up for success), state title, error text, `SendMetadataSection` when `pendingMetadata != nil`, Done (enabled only on success) or Cancel (error) |
| `SendMetadataSection` | `Shared/Views/Send/SendMetadataSection.swift` | Three 60×44 buttons: contact avatar or `person.fill`, first tag's emoji/colour or `tag.fill`, `text.quote` tinted green when a note exists. Opens `ContactSelectorSheet` (`transactionId: nil`, applied via `onAssignContact`), `TagSelectorSheet` (applied on sheet `onDisappear`; new tags created through `walletManager.tagServiceForEnvironment.createTag`), and `SendNoteEditorSheet`. Implements the dual write |
| `SendNoteEditorSheet` | `ArkeUI/Sources/ArkéUI/Sheets/SendNoteEditorSheet.swift` | Vertical-axis `TextField` (1–5 lines), auto-focus, checkmark to dismiss; the binding setter writes on every keystroke. Whitespace-only notes are stored as `nil` |
| `TransactionService+PendingMetadata` | `Shared/Services/TransactionService/TransactionService+PendingMetadata.swift` | `applyPendingMetadata(to:)`, `cleanupOldPendingMetadata()`, private matching and transfer |
| `TransactionService+Upsert` | `Shared/Services/TransactionService/TransactionService+Upsert.swift` | Calls cleanup once per upsert and `applyPendingMetadata` per transaction (new and existing) |

## Edge cases

| Situation | What happens |
|---|---|
| Payment fails | The row stays unmatched with whatever the user entered; the modal still shows the section (edits go to this row). Cancel dismisses. A new send creates a new empty row; the old one is deleted after 24 h. |
| App backgrounds or is killed mid-send | The row was saved at creation (and on every edit), so it survives. The next movement upsert — foreground or a background refresh — matches and applies it. The modal reference is gone, so no further edits are possible from the send flow. |
| Movement arrives before the user has entered anything | The empty row is matched (`isMatched`, `matchedTxid` set, `hasBeenApplied = true`). Subsequent edits find the transaction and dual-write. |
| Movement arrives after the user edited | Edits set `hasBeenApplied = false`; the upsert applies them on arrival. |
| Movement never arrives / no match | Row is deleted 24 h after creation with a diagnostic log. The user can still tag the transaction from its detail view. |
| Two pending rows fit one transaction | Closest timestamp wins; the other stays unmatched and can match a later transaction or age out. |
| Transaction already had a note | The pending note is not applied; contact and tags still are. |
| Onchain send confirms slowly | If the movement's `date` falls outside ±5 min of the send timestamp, no match. Accepted: users add metadata from the detail view. |
| CloudKit import deletes assignment rows during an edit | Every delete/check goes through a fetch (`live*Assignments`, `hasTag`, `hasContact`), so nothing traps and nothing stale is counted. |

## Lessons / invariants

- **Never delete a matched pending row eagerly.** The UI may still hold it.
  Keep it, flag it, and let the 1 h cleanup remove it.
- **No early return on `isMatched`.** A matched row must be re-applied when the
  user edits after the match; the guard is `hasBeenApplied`, which the UI resets
  via `markAsModified()`.
- **`hasBeenApplied` exists to stop write churn.** Without it every upsert
  re-wrote every recently matched transaction and re-triggered CloudKit sync.
- **Dual write when the transaction exists.** Waiting for the next sync made
  edits look lost; writing to both the pending row and the transaction gives an
  instant UI update while keeping the re-application fallback.
- **Application is additive and non-destructive**: notes never overwrite,
  assignments are skipped if already present. Only the send-flow *edit* path
  replaces a transaction's assignments wholesale.
- **Read relationships through fetches, not cached arrays** (2026-09-25 sweep).
  Cached to-many arrays can list rows a CloudKit import already deleted.
- **Pending rows belong to a wallet.** They must be part of the full wipe or an
  old wallet's leftovers can attach to the next wallet's transactions (gap found
  2026-08-19, fixed).

## Tests

`Tests/Shared/PendingMetadataMatchingTests.swift` (hash match, hash case
sensitivity, timestamp window inside/outside, amount mismatch, address case
insensitivity, closest-timestamp tie-break, full transfer, 24 h cleanup) and
`Tests/Shared/TransactionMetadataWritePathTests.swift`
(`pendingMetadataLiveAssignments`: fetch-resolved tag reads survive a
cross-context delete). Wipe coverage is asserted by `WalletDeletionRejoinTests`
against `SwiftDataHelper.appSchemaModels`.
