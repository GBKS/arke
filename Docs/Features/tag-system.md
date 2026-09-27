# Tag System

**Status:** Shipped and maintained. Rewritten against the code 2026-07-09 (merged in the former root `tags-view-architecture.md`; see Update History).

## Overview

The tag system provides transaction categorization for both platforms (macOS and iOS). Users create custom tags with a name, color, and emoji, assign them to transactions, and the assignments survive server data refreshes and sync across devices via CloudKit. The system is built on SwiftData with a junction-table architecture and follows the app's coordinator pattern: views talk to `WalletManager`, which delegates to `TagService`.

```
SwiftUI Views → TagsViewModel → WalletManager (coordinator) → TagService → SwiftData
                                                                  ↕
                                                             CloudKit sync
```

## Core Components

### Models

| Type | Location | Role |
|------|----------|------|
| `TagModel` (struct) | ArkéUI package (`Models/TagModel.swift`) | Pure presentation value type — no SwiftData/Bark dependency, preview-friendly, with `samples` |
| `TagModel+Persistence` | `Shared/Models/` | App-side bridging: `init(from:)` / `toPersistentTag()` |
| `PersistentTag` (@Model) | `Shared/Models/` | SwiftData-persisted tag |
| `TransactionTagAssignment` (@Model) | `Shared/Models/` | Junction table: tag ↔ transaction |
| `PendingTagAssignment` (@Model) | `Shared/Models/PendingPaymentMetadata.swift` | Junction table: tag ↔ pending payment metadata (send metadata that arrives before its transaction) |
| `TagStatistic` (struct) | `Shared/Services/TagService.swift` | Per-tag usage stats: transaction count, net/sent/received amounts, offchain/onchain/total fees, formatted variants |

### Service Layer

- **`TagService`** (`Shared/Services/`) — `@MainActor @Observable`; all CRUD, assignment, query, and statistics operations; owns the in-memory `tags: [TagModel]` cache
- **`WalletManager+Tags`** (`Shared/Data/WalletManager/`) — coordinator delegation; views never touch `TagService` directly (there is no environment injection of the service)
- **`TransactionService+AutoTagging`** — Balance system tag for internal transfers, contact auto-assignment
- **`TransactionService+Upsert` / `+PendingMetadata`** — tag preservation during refreshes, pending-metadata matching

### View Layer

Business logic is shared; presentation is per-platform (~75–80% code reuse):

- **`TagsViewModel`** (`Shared/Views/Tags/`) — `@MainActor @Observable`; statistics loading, CRUD actions (delegating to `WalletManager`), sheet presentation state, and sorting: tags ordered by net amount, zero-transaction tags at the bottom, system tags last
- **`TagsView`** (macOS, `ArkeDesktop/Views/Tags/`) — `ScrollView` + `Grid` for multi-column alignment, `NetChangeBar` net-amount visualization, `TagsGraph`, menu-based row actions, fixed-size sheets, optional navigation callback
- **`TagsView_iOS`** (`ArkeMobile/Views/Tags/`) — `List` + `NavigationLink`, swipe actions (edit/delete), context menus, pull-to-refresh, `.presentationDetents([.medium, .large])` sheets, `ContentUnavailableView` empty state, required navigation callback
- **Shared components** — `TagChip` (ArkéUI), `TagEditor` + `TagValidation` (`Shared/Views/Tags/Editor/`), `TagSelectorSheet`, `TransactionTagView`; `TagRowContent` (desktop) is an optional shared row layout

Usage:

```swift
// macOS — navigation callback optional
TagsView(onNavigateToActivity: { tag in navigationPath.append(ActivityFilter.tag(tag)) })

// iOS — navigation callback required
TagsView_iOS { tag in navigationPath.append(ActivityFilter.tag(tag)) }
```

## Data Model Design

### Junction Table Approach

`TransactionTagAssignment` links tags and transactions instead of a direct many-to-many `@Relationship`:

```
PersistentTag ←→ TransactionTagAssignment ←→ PersistentTransaction
```

**Benefits:** relationship control during server refreshes, extensible metadata (`assignedDate`), efficient lookups in both directions, explicit lifecycle management.

### CloudKit Constraints

All persisted models are written for CloudKit compatibility:

- No `@Attribute(.unique)` — uniqueness (e.g. tag names) is enforced in `TagService` with fetch-before-insert checks
- Every stored property has a default value
- All relationships are optional (`[TransactionTagAssignment]? = []`)

### Model Definitions

```swift
@Model
final class PersistentTag {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#007AFF"
    var emoji: String = "🏷️"
    var createdDate: Date = Date()
    var isSystemTag: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \TransactionTagAssignment.tag)
    var tagAssignments: [TransactionTagAssignment]? = []

    @Relationship(deleteRule: .cascade, inverse: \PendingTagAssignment.tag)
    var pendingTagAssignments: [PendingTagAssignment]? = []
}
```

`PersistentTag` also carries the statistics computed properties (`transactionCount`, `totalTransactionAmount` = received − sent, `sentAmount`, `receivedAmount`, `offchainFees`, `onchainFees`, `totalFees`) that `TagService.getTagStatistics()` aggregates into `TagStatistic` values.

```swift
@Model
final class TransactionTagAssignment {
    var assignedDate: Date = Date()
    @Relationship var tag: PersistentTag?
    @Relationship var transaction: PersistentTransaction?
}
```

`PendingTagAssignment` mirrors this shape but links a tag to `PendingPaymentMetadata` instead of a transaction — it holds tag choices made during send until the matching transaction appears (see `Features/send-metadata-enhancement.md`).

## TagService

### Operations

```swift
// Tag management
func createTag(_ tagModel: TagModel) async throws -> TagModel   // rejects duplicate names
func updateTag(_ updatedTag: TagModel) async throws
func deleteTag(_ tagId: UUID) async throws                      // PERMANENT — cascade deletes assignments

// Assignments
func assignTag(_ tagId: UUID, to transactionTxid: String) async throws
func unassignTag(_ tagId: UUID, from transactionTxid: String) async throws

// Queries
func getTransactionsWithTag(_ tagId: UUID) async throws -> [TransactionModel]
func getTagsForTransaction(_ transactionId: String) async throws -> [TagModel]
func getTagStatistics() async throws -> [TagStatistic]

// Lifecycle & bulk
func createDefaultTagsIfNeeded() async
func deleteAllTags() async throws   // wallet deletion with cloud-data removal
```

Notes:

- **Deletion is permanent.** There is no soft delete / `isActive` flag; removing a tag cascade-deletes all its assignments.
- All mutating operations run through `TaskDeduplicationManager` (keyed per operation + target) to prevent concurrent duplicates.
- `setModelContext(_:)` is only called once a wallet exists; it loads tags and starts CloudKit observation.

### CloudKit Sync

Implemented (not a future enhancement):

- Models are CloudKit-compatible (see constraints above), so SwiftData/CloudKit syncs tags and assignments across linked devices.
- `TagService` subscribes to `.cloudKitDataDidChange` (debounced 1 s) and reloads its tag cache when remote changes land. See `CloudKit/CloudKit_Realtime_Sync.md` for the notification pattern.
- Default-tag creation batches all inserts into a single `save()` so first-run setup triggers one CloudKit sync, not nine.

### Error Handling

```swift
enum TagServiceError: LocalizedError {
    case noModelContext
    case tagNotFound(UUID)
    case transactionNotFound(String)
    case tagAlreadyExists(String)
    case tagAlreadyAssigned
    case assignmentNotFound
}
```

User-facing messages surface through the service's observable `error` property (`clearError()` to dismiss).

## Default Tags & System Tags

`TagModel.createDefaultTags()` (ArkéUI) defines **9 defaults**, created on first run when no tags exist:

Savings 💰, Food 🍕, Transport 🚗, Shopping 🛒, Bills 📄, Income 💰, Investment 📈, Gift 🎁, and **Balance 👜** — the only *system tag* (`isSystemTag: true`).

System tag behavior:

- The **Balance** tag marks internal transfers (board/offboard/refresh movements between the wallet's own balances). `TransactionService.autoTagInternalTransfer(_:)` applies it automatically, creating the tag on demand if the user deleted it.
- System tags sort to the end of the Tags view list.

## Tag Preservation During Refreshes

Server refreshes must not destroy user categorization:

- **Upsert strategy** (`TransactionService+Upsert`): existing `PersistentTransaction` rows are updated in place, so SwiftData keeps their `tagAssignments` relationships automatically; assignment counts are logged for verification.
- **Orphaned transactions** (present locally, missing from server) are preserved by default when tagged; `cleanupOrphanedTaggedTransactions()` exists for manual cleanup.
- **New transactions** start untagged, then pass through auto-tagging (Balance system tag, contact auto-assignment) and pending-metadata matching.

## WalletManager Integration

`WalletManager+Tags` exposes the full tag API to views (`tags`, `createTag`, `updateTag`, `deleteTag`, `assignTag`, `unassignTag`, `getTransactionsWithTag`, `getTagStatistics`, `getTransactionTags`, `transactionHasTags`, `createDefaultTagsIfNeeded`, `clearTagError`). Views and view models depend on `WalletManager` only; `TagService` is an implementation detail behind it.

## Update History

| Date | Change |
|------|--------|
| 2026-07-09 | Rewritten against the code (inventory Step 23). Corrected stale claims: delete is permanent (no soft delete/`isActive`), CloudKit sync is implemented, 9 default tags incl. Balance system tag, `TagModel` lives in ArkéUI, junction points to `PersistentTransaction`, statistics include fee breakdown, no `@Environment(TagService.self)` injection. Merged the view-layer architecture from root `tags-view-architecture.md` (now in `Archive/Implementations/`) |
| 2025-10-30 | Original implementation doc (4 development steps) |
