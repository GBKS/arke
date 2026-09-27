# DataVersion Observation Pattern

## Overview
This document describes the `dataVersion` observation pattern implemented to ensure SwiftUI views automatically update when transaction relationships (contacts, tags) change in SwiftData.

## The Problem
SwiftData relationships on `@Model` objects are not automatically observed by SwiftUI. When a `TransactionContactAssignment` or `TransactionTagAssignment` is created/deleted, views displaying `transaction.associatedContacts` or `transaction.associatedTags` don't automatically refresh because the transaction object itself hasn't changed—only its relationships have.

## The Solution
We've implemented a lightweight observable trigger in `WalletManager`:

```swift
@MainActor
@Observable
class WalletManager {
    /// Increments whenever persistent relationships change (contacts, tags, etc.)
    /// Views can observe this to refresh when relationship data changes
    var dataVersion: Int = 0
    
    // ... rest of the class
}
```

### When dataVersion is Incremented
The `dataVersion` property is incremented after any operation that modifies transaction relationships:

1. **Contact Assignments**
   - `assignContact(_:to:)` - Basic contact assignment
   - `assignContactWithAddressLearning(_:to:)` - Assignment with address learning and bulk assignment
   - `unassignContact(_:from:)` - Remove specific contact
   - `removeContactAssignment(from:)` - Remove all contacts

2. **Tag Assignments**
   - `assignTag(_:to:)` - Assign tag to transaction
   - `unassignTag(_:from:)` - Remove tag from transaction

### How Views Observe dataVersion

#### 1. TransactionList
The computed `transactions` property accesses `walletManager.dataVersion`, creating an observation dependency:

```swift
private var transactions: [TransactionModel] {
    let context = modelContext
    
    // Access dataVersion to create observation dependency
    // This ensures the view updates when relationships change
    _ = walletManager.dataVersion
    
    // ... fetch logic
}
```

When `dataVersion` changes, SwiftUI re-evaluates `transactions`, which triggers a fresh fetch from SwiftData, picking up the new relationship assignments.

#### 2. TransactionListItem
The view accesses `dataVersion` in its computed properties and body:

```swift
struct TransactionListItem: View {
    @Environment(WalletManager.self) private var walletManager
    
    var body: some View {
        // Access dataVersion at the beginning
        let _ = walletManager.dataVersion
        
        // ... rest of the view
    }
    
    private var transactionDisplayText: String {
        // Access dataVersion to create observation dependency
        _ = walletManager.dataVersion
        
        // Access relationship data
        if let contact = transaction.associatedContacts.first {
            // ... display logic
        }
    }
}
```

#### 3. TransactionContactView & TransactionTagView
These views use `.task(id:)` to reload their data when `dataVersion` changes:

```swift
.task(id: transaction.txid) {
    await loadAssignedContact()
}
.task(id: walletManager.dataVersion) {
    // Reload contact when dataVersion changes
    await loadAssignedContact()
}
```

This pattern ensures that when a contact is assigned to a transaction in one view, all other views displaying that transaction's contacts automatically refresh.

## Advantages

1. **Centralized Change Management**: All relationship mutations flow through WalletManager
2. **Automatic Propagation**: SwiftUI's observation system handles updates automatically
3. **Lightweight**: Single `Int` property with minimal overhead
4. **Scalable**: Works for all relationship types (contacts, tags, future additions)
5. **Explicit Logging**: Console logs show when and why `dataVersion` increments
6. **No Prop Drilling**: Views observe through `@Environment`, no need to pass triggers

## Performance Considerations

- **Minimal Overhead**: A simple integer increment is extremely cheap
- **Scoped Updates**: Only views that access `dataVersion` will re-evaluate
- **Efficient Fetches**: SwiftData fetches are already optimized and cached
- **Predictable**: Changes are synchronous and deterministic

## Future Enhancements

This pattern can be extended to support:
- Transaction notes
- Transaction categories
- Custom metadata
- Any other relationship-based data

Simply increment `dataVersion` after the relationship change, and all observing views will automatically update.

## Debugging

To debug when and why views are updating:
1. Look for console logs: `"📊 DataVersion incremented to X after [operation]"`
2. Add breakpoints in views' computed properties where `dataVersion` is accessed
3. Use Xcode's SwiftUI inspector to see when body gets re-evaluated

## Testing

When writing tests for relationship changes:
1. Capture the initial `dataVersion` value
2. Perform the operation (assign contact, assign tag, etc.)
3. Assert that `dataVersion` has incremented
4. Assert that views reflect the new relationship data

Example:
```swift
@Test("Contact assignment increments dataVersion")
func testContactAssignmentIncrementsDataVersion() async throws {
    let walletManager = WalletManager(useMock: true)
    let initialVersion = walletManager.dataVersion
    
    try await walletManager.assignContact(contactId, to: transactionId)
    
    #expect(walletManager.dataVersion == initialVersion + 1)
}
```
