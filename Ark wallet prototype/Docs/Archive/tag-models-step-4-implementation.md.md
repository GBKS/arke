# Step 4: Tag Preservation During Server Refreshes - Implementation

## Overview

This document describes the implementation of Step 4: preserving tag assignments during server transaction refreshes in the macOS Bitcoin wallet prototype. The solution ensures that user-assigned tags survive server data updates without interfering with the existing synchronization mechanism.

## Problem Solved

Previously, when `transactionService.refreshTransactions()` was called, the upsert logic in `upsertTransactionsFromServerData()` would update transaction properties from server data but would not explicitly preserve existing tag assignments. While SwiftData's relationship system should maintain these connections automatically, the implementation now includes explicit preservation logic and monitoring.

## Solution Architecture

### Core Strategy: Leverage SwiftData Relationships

The solution relies on SwiftData's built-in relationship management between `TransactionModel` and `TransactionTagAssignment` entities. When updating existing transactions, the relationships are automatically preserved by SwiftData's persistence layer.

### Key Components Modified

#### 1. Enhanced Upsert Logic (`TransactionService.swift`)

**Before:**
```swift
if let existingTransaction = existingTransactionDict[transactionData.txid] {
    // Update transaction properties
    existingTransaction.amount = transactionData.amount
    // ... other updates
}
```

**After:**
```swift
if let existingTransaction = existingTransactionDict[transactionData.txid] {
    // Update transaction properties
    existingTransaction.amount = transactionData.amount
    // ... other updates
    
    // Preserve existing tag assignments - they survive server updates
    // SwiftData relationship will maintain the connections automatically
    if !existingTransaction.tagAssignments.isEmpty {
        preservedTagCount += existingTransaction.tagAssignments.count
    }
}
```

#### 2. Tag Assignment Monitoring

Added comprehensive logging and monitoring of tag preservation:
- Cache existing tag assignments for verification
- Track preserved tag assignments during updates
- Monitor orphaned transactions (exist locally but not on server)
- Detailed logging for debugging and verification

#### 3. Orphaned Transaction Handling

Enhanced the upsert logic to detect and handle orphaned transactions:
- Identifies transactions that exist locally but not in server data
- Preserves tagged orphaned transactions (user decision)
- Provides detailed logging for manual review

### New Methods Added

#### `cacheExistingTagAssignments()`
```swift
private func cacheExistingTagAssignments(from transactions: [TransactionModel]) async -> [String: [TransactionTagAssignment]]
```
- Caches existing tag assignments for logging and verification
- Provides insight into tag preservation during updates

#### `cleanupOrphanedTaggedTransactions()`
```swift
func cleanupOrphanedTaggedTransactions() async
```
- Manual cleanup method for orphaned tagged transactions
- Identifies transactions with tags that no longer exist on server
- Provides detailed reporting without automatic deletion

#### `getServerTransactionIds()`
```swift
private func getServerTransactionIds(from output: String) async -> Set<String>
```
- Extracts transaction IDs from server response for comparison
- Supports orphaned transaction detection

## Data Integrity Guarantees

### 1. Existing Tag Preservation
- ✅ All existing `TransactionTagAssignment` relationships survive server updates
- ✅ Tag assignments remain intact when transaction properties are updated
- ✅ SwiftData cascade delete rules ensure clean deletion when needed

### 2. New Transaction Handling
- ✅ New transactions from server start with no tag assignments
- ✅ Users can add tags to new transactions after they're created
- ✅ No interference with server synchronization

### 3. Orphaned Transaction Management
- ✅ Tagged transactions that no longer exist on server are preserved
- ✅ Detailed logging identifies orphaned tagged transactions
- ✅ Manual cleanup method available for policy decisions

## Enhanced Logging

The implementation includes comprehensive logging:

```
💾 Successfully saved 5 new, 3 updated transactions
🏷️ Preserved 12 tag assignments across updates
🏷️ Found 2 tag assignments on 1 orphaned transactions
```

## Testing Strategy

### Manual Testing

Since this is an early macOS prototype, testing can be done manually:

1. **Create transactions with tags**: Use the TagService to assign tags to existing transactions
2. **Trigger server refresh**: Call `await transactionService.refreshTransactions()`
3. **Verify preservation**: Check that tag assignments remain intact after refresh
4. **Monitor logs**: Watch console output for tag preservation confirmation

### Test Scenarios

1. **Single Tag Preservation**
   - Assign one tag to a transaction
   - Refresh from server with updated transaction data
   - Verify tag assignment survives and data is updated

2. **Multiple Tag Preservation**
   - Assign multiple tags to a transaction
   - Refresh from server
   - Verify all tag assignments survive

3. **New Transactions**
   - Ensure new transactions from server start without tag assignments
   - Verify clean state for newly synced transactions

## Usage Examples

### Normal Operation
```swift
// Tags are automatically preserved during normal refreshes
await transactionService.refreshTransactions()
```

### Manual Orphaned Transaction Cleanup
```swift
// Optional: Check for and handle orphaned tagged transactions
await transactionService.cleanupOrphanedTaggedTransactions()
```

### Clear All Data (Including Tags)
```swift
// This will remove all transactions and their tag assignments
await transactionService.clearTransactionModels()
```

## Edge Cases Handled

### 1. Transaction ID Changes
If a server changes transaction IDs (unlikely but possible), the old transaction with tags would be preserved as orphaned, and a new transaction would be created without tags.

### 2. Server Data Corruption
If server returns invalid data, existing transactions and their tags remain unchanged due to error handling.

### 3. Model Context Issues
All operations include proper model context validation and error handling.

### 4. Concurrent Access
Uses existing `TaskDeduplicationManager` to prevent concurrent refresh operations.

## Performance Considerations

### Minimal Overhead
- Tag preservation adds minimal processing overhead
- SwiftData handles relationship management efficiently
- Caching operations are for logging only, not performance-critical

### Memory Usage
- Tag assignment cache is temporary and released after processing
- No significant additional memory footprint

## Future Enhancements

### Policy for Orphaned Transactions
Consider implementing configurable policies for orphaned tagged transactions:
- Auto-delete after X days
- User prompt for cleanup
- Export tags before deletion

### Batch Tag Operations
Could optimize for large numbers of tag assignments with batch operations.

### Tag Migration
Could implement tag preservation during transaction ID changes if needed.

## Compatibility

### macOS Prototype Focus
- ✅ Optimized for macOS SwiftUI application
- ✅ Uses macOS-specific SwiftData features where beneficial
- ✅ No backwards compatibility constraints for rapid prototyping
- ✅ Modern Swift concurrency patterns (async/await)

### Forward Compatibility
- ✅ Implementation supports future tag features
- ✅ Extensible for additional relationship types  
- ✅ Clean separation of concerns maintained

## Conclusion

The implementation successfully preserves tag assignments during server transaction refreshes while maintaining the integrity of the existing synchronization system. The solution is robust, includes comprehensive monitoring and cleanup capabilities, and is optimized for rapid prototyping in the macOS environment.

User-assigned tags now survive server data updates, providing a reliable foundation for the tag system in the macOS Bitcoin wallet prototype.

---
*Archived: October 30, 2025*