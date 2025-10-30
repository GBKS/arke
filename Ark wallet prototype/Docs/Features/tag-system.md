# Tag System Implementation

## Overview

The tag system provides comprehensive transaction categorization and organization capabilities for the macOS Bitcoin wallet. Users can create custom tags, assign them to transactions, and maintain these assignments even during server data refreshes. The system is built on SwiftData with a robust junction table architecture and integrates seamlessly with the existing service layer.

## Architecture

### Core Components

#### 1. Data Models
- **PersistentTag (@Model)**: SwiftData-persisted tag storage
- **TransactionTagAssignment (@Model)**: Junction table for tag-transaction relationships
- **TagModel (struct)**: UI-friendly tag representation
- **Enhanced TransactionModel**: Includes tag relationship support

#### 2. Service Layer
- **TagService**: Observable service for all tag operations (CRUD, assignments, statistics)
- **WalletManager Integration**: Coordinator pattern with computed properties and delegation
- **TransactionService Enhancement**: Tag preservation during server refreshes

#### 3. Architecture Pattern
```
SwiftUI Views → WalletManager (coordinator) → TagService → SwiftData
                     ↑                          ↓
              Computed Properties        @Observable Updates
```

## Data Model Design

### Junction Table Approach

The system uses `TransactionTagAssignment` as a junction table instead of direct `@Relationship` arrays:

```swift
PersistentTag ←→ TransactionTagAssignment ←→ TransactionModel
     ↑                    ↑                        ↑
   1:many             junction table            1:many
```

**Benefits:**
- **Better relationship control** during server refreshes
- **Extensible metadata** support (assignment date, notes, etc.)
- **Easier query performance** and indexing
- **Explicit lifecycle management** of tag assignments

### Model Definitions

#### PersistentTag
```swift
@Model
class PersistentTag {
    var id: UUID
    var name: String
    var colorHex: String
    var emoji: String
    var isActive: Bool
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \TransactionTagAssignment.tag)
    var assignments: [TransactionTagAssignment] = []
    
    // Computed properties and convenience methods
}
```

#### TransactionTagAssignment
```swift
@Model
class TransactionTagAssignment {
    var tag: PersistentTag?
    var transaction: TransactionModel?
    var assignedAt: Date
    var id: UUID
}
```

## Service Layer Implementation

### TagService Features

#### Core Operations
- **CRUD Operations**: Create, read, update, delete (soft delete) tags
- **Assignment Management**: Assign/unassign tags to/from transactions  
- **Query Operations**: Get transactions by tag, tag statistics, filtering
- **Default Management**: Auto-create default tags on first run

#### Observable Properties
```swift
@Observable
class TagService {
    var tags: [TagModel] = []
    var error: String?
    var isLoading: Bool = false
    
    // Computed properties
    var activeTags: [TagModel] { ... }
    var activeTagCount: Int { ... }
    var hasTags: Bool { ... }
}
```

#### Key Methods
```swift
// Tag management
func createTag(_ tagModel: TagModel) async throws -> TagModel
func updateTag(_ tagModel: TagModel) async throws -> TagModel
func deleteTag(_ tagId: UUID) async throws

// Assignment operations
func assignTag(_ tagId: UUID, to transactionId: String) async throws
func unassignTag(_ tagId: UUID, from transactionId: String) async throws

// Query operations
func getTransactionsWithTag(_ tagId: UUID) async throws -> [TransactionModel]
func getTagStatistics() async throws -> [TagStatistics]
```

### WalletManager Integration

#### Coordinator Pattern
WalletManager acts as a coordinator, providing a unified interface:

```swift
// Tag management delegation
func createTag(_ tagModel: TagModel) async throws -> TagModel {
    guard let tagService = tagService else {
        throw BarkError.commandFailed("Tag service not initialized")
    }
    return try await tagService.createTag(tagModel)
}

// Computed properties for UI
var tags: [TagModel] { tagService?.tags ?? [] }
var activeTags: [TagModel] { tagService?.activeTags ?? [] }
var hasTagsAvailable: Bool { tagService?.hasTags ?? false }
```

#### Environment Injection
```swift
// SwiftUI environment setup
var tagServiceForEnvironment: TagService? { tagService }

// Usage in views
@Environment(TagService.self) private var tagService
@Environment(WalletManager.self) private var walletManager
```

## Tag Preservation System

### Server Refresh Enhancement

The system preserves tag assignments during server data updates through enhanced TransactionService logic:

#### Upsert Strategy
```swift
// Existing transactions preserve tag relationships automatically
if let existingTransaction = existingTransactionDict[transactionData.txid] {
    // Update transaction properties from server
    existingTransaction.amount = transactionData.amount
    // ... other updates
    
    // SwiftData preserves tagAssignments relationship automatically
    if !existingTransaction.tagAssignments.isEmpty {
        preservedTagCount += existingTransaction.tagAssignments.count
    }
}
```

#### Orphaned Transaction Handling
- **Detection**: Identifies transactions that exist locally but not on server
- **Preservation**: Tagged orphaned transactions are preserved by default
- **Manual Cleanup**: `cleanupOrphanedTaggedTransactions()` method available
- **Detailed Logging**: Comprehensive monitoring and reporting

### Data Integrity Guarantees

1. **Existing Tag Preservation**: All `TransactionTagAssignment` relationships survive server updates
2. **New Transaction Handling**: New transactions start with clean state (no tags)
3. **Orphaned Management**: Tagged transactions missing from server are preserved with detailed logging
4. **Cascade Rules**: Proper SwiftData deletion cascading ensures no orphaned relationships

## Default Tags System

### Auto-Creation
The system creates 8 default tags on first initialization:

```swift
let defaultTags = [
    TagModel(name: "Income", colorHex: "#2ECC40", emoji: "💰"),
    TagModel(name: "Expense", colorHex: "#FF4136", emoji: "💸"),
    TagModel(name: "Investment", colorHex: "#0074D9", emoji: "📈"),
    TagModel(name: "Savings", colorHex: "#3D9970", emoji: "🏦"),
    TagModel(name: "Bills", colorHex: "#FF851B", emoji: "🧾"),
    TagModel(name: "Entertainment", colorHex: "#B10DC9", emoji: "🎮"),
    TagModel(name: "Food", colorHex: "#FFDC00", emoji: "🍔"),
    TagModel(name: "Transport", colorHex: "#85144B", emoji: "🚗")
]
```

### Conditional Creation
- Only created if no tags exist in the system
- Runs automatically after wallet initialization
- Background execution without blocking startup

## SwiftUI Integration

### Environment Setup
```swift
// App-level setup
.environment(walletManager.tagServiceForEnvironment)

// ModelContainer configuration
.modelContainer(for: [
    TransactionModel.self,
    ArkBalanceModel.self,
    OnchainBalanceModel.self,
    PersistentTag.self,
    TransactionTagAssignment.self
])
```

### View Integration Examples

#### Tag Management View
```swift
struct TagManagementView: View {
    @Environment(TagService.self) private var tagService
    @Environment(WalletManager.self) private var walletManager
    
    var body: some View {
        List(walletManager.activeTags) { tag in
            TagRow(tag: tag)
        }
        .toolbar {
            Button("Create Tag") {
                Task {
                    let newTag = TagModel(name: "New Tag", colorHex: "#FF0000", emoji: "🏷️")
                    try await walletManager.createTag(newTag)
                }
            }
        }
        .refreshable {
            // Tags refresh automatically via @Observable
        }
    }
}
```

#### Transaction with Tags
```swift
struct TransactionRowView: View {
    let transaction: TransactionModel
    @Environment(WalletManager.self) private var walletManager
    
    var body: some View {
        VStack {
            // Transaction details
            Text(transaction.formattedAmount)
            
            // Tag display
            if !transaction.associatedTags.isEmpty {
                TagChipView(tags: transaction.associatedTags)
            }
        }
    }
}
```

## Performance Considerations

### Optimizations
- **Task Deduplication**: Prevents concurrent operations using `TaskDeduplicationManager`
- **Soft Delete**: Tags are deactivated rather than deleted for better performance
- **Computed Properties**: Efficient tag counting and filtering
- **Junction Table Queries**: Optimized for both tag→transactions and transaction→tags lookups

### Memory Management
- **Observable Pattern**: Automatic UI updates without manual state management  
- **SwiftData Integration**: Efficient relationship management and caching
- **Minimal Overhead**: Tag preservation adds minimal processing during refreshes

## Error Handling

### TagService Errors
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

### Error Strategy
- **Specific Error Types**: Clear identification of failure modes
- **User-Friendly Messages**: Localized error descriptions via `error` property
- **Recovery Methods**: `clearError()` for UI error dismissal
- **Comprehensive Logging**: Console output for debugging

## Testing Strategy

### Manual Testing Scenarios
1. **Tag CRUD Operations**: Create, update, delete tags
2. **Assignment Management**: Assign/unassign tags to transactions
3. **Server Refresh Preservation**: Verify tags survive transaction updates
4. **Default Tag Creation**: Confirm auto-creation on first run
5. **Error Handling**: Test all error conditions and recovery

### Observable Testing
- **UI Updates**: Verify automatic updates via @Observable pattern
- **Service Integration**: Confirm WalletManager delegation works correctly
- **Environment Injection**: Test SwiftUI environment access patterns

## Future Enhancements

### Planned Features
- **Tag Categories**: Hierarchical organization of tags
- **Bulk Operations**: Tag multiple transactions simultaneously
- **Advanced Statistics**: Usage analytics and insights
- **Tag Templates**: Predefined tag sets for workflows
- **Export/Import**: Tag data backup and synchronization

### CloudKit Sync
The architecture is designed to support CloudKit synchronization:
- **SwiftData Foundation**: Models ready for cloud sync
- **Relationship Integrity**: Junction table approach supports sync conflicts
- **Unique Identifiers**: UUID-based IDs suitable for distributed systems

## Benefits Summary

### User Experience
✅ **Persistent Organization**: Tags survive all server updates  
✅ **Instant Feedback**: Real-time UI updates via SwiftData observation  
✅ **Flexible System**: Custom tags with colors and emojis  
✅ **Default Setup**: Ready-to-use tags on first launch  
✅ **Clean Interface**: Integrated with existing wallet UI patterns

### Developer Experience  
✅ **Consistent Architecture**: Follows established service patterns  
✅ **Observable Integration**: Automatic UI synchronization  
✅ **Comprehensive API**: Full CRUD and assignment operations  
✅ **Error Handling**: Detailed error types and recovery methods  
✅ **Extensible Design**: Ready for advanced features and sync capabilities

### System Reliability
✅ **Data Integrity**: Junction table approach ensures relationship consistency  
✅ **Server Compatibility**: Tag assignments preserved during data refreshes  
✅ **Performance**: Minimal overhead with intelligent caching  
✅ **Fault Tolerance**: Graceful handling of edge cases and errors

---

*Implementation completed across 4 development steps. Current as of: October 30, 2025*