# Transaction Architecture Migration Guide

This document outlines the new transaction architecture and how to migrate from the old system.

## What Changed

### Old Architecture Problems
- `TransactionModel` with random UUIDs that changed on every refresh
- Dual model system (`TransactionModel` + `TransactionModel`)
- In-memory transactions array that got replaced on refresh
- Complex deduplication and syncing logic
- No support for user metadata like tags

### New Architecture Benefits
- `TransactionModel` as the single source of truth
- Stable server-derived transaction IDs
- Direct SwiftData observation in UI
- Upsert strategy that preserves user data
- Ready for CloudKit sync
- Foundation for transaction tagging

## Key Changes

### 1. TransactionModel is now Primary
```swift
// OLD: Using TransactionModel everywhere
@State var transactions: [TransactionModel] = []

// NEW: Direct SwiftData observation
@Query(sort: \TransactionModel.date, order: .reverse) 
private var transactions: [TransactionModel]
```

### 2. TransactionService Simplified
```swift
// OLD: Complex in-memory management
var transactions: [TransactionModel] = []
var hasLoadedTransactions: Bool = false

// NEW: Simple refresh state
var isRefreshing: Bool = false
```

### 3. UI Updates Automatically
```swift
// OLD: Manual UI updates after service changes
transactionService.transactions // Changes trigger UI updates

// NEW: SwiftData observation handles everything
@Query private var transactions: [TransactionModel] // Auto-updates
```

## Migration Steps for Your Views

### Update Transaction Lists
```swift
// OLD
struct MyView: View {
    @Environment(TransactionService.self) private var transactionService
    
    var body: some View {
        ForEach(transactionService.transactions) { transaction in
            // Use transaction.id, transaction.type, etc.
        }
    }
}

// NEW  
struct MyView: View {
    @Query(sort: \TransactionModel.date, order: .reverse) 
    private var transactions: [TransactionModel]
    
    var body: some View {
        ForEach(transactions) { transaction in
            // Use transaction.txid, transaction.transactionType, etc.
        }
    }
}
```

### Property Name Changes
- `transaction.id` → `transaction.txid` 
- `transaction.type` → `transaction.transactionType`
- `transaction.status` → `transaction.transactionStatus`
- Formatted properties work the same (`formattedAmount`, `formattedDate`)

### Environment Setup
Make sure your app provides the ModelContainer:
```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: TransactionModel.self)
    }
}
```

## Benefits You Get

1. **Instant UI**: Persisted transactions load immediately
2. **Real-time Updates**: SwiftData handles all UI synchronization
3. **Stable Identity**: Transaction IDs are consistent across refreshes
4. **Ready for Tags**: Architecture supports user metadata
5. **CloudKit Ready**: Easy to enable sync later
6. **Better Performance**: No data duplication or conversion overhead

## Backward Compatibility

The `transactionModel` property on `TransactionModel` is available (but deprecated) for gradual migration:

```swift
// Temporary compatibility
let oldStyleTransaction = TransactionModel.transactionModel
```

## Testing

Use the new mock data helpers:
```swift
#Preview {
    @Previewable @State var service = TransactionService(...)
    
    MyView()
        .environment(service)
        .modelContainer(for: TransactionModel.self, inMemory: true)
}
```
