# Wallet Deletion Implementation

## Overview
This document describes the comprehensive wallet deletion implementation that ensures all user data is properly removed from iCloud/CloudKit when the user chooses to delete their wallet.

## Problem Statement
Previously, when a user deleted their wallet with `deleteCloudData: true`, only the following was deleted:
- ✅ Mnemonic from Keychain
- ✅ Hash from NSUbiquitousKeyValueStore
- ✅ `WalletConfiguration` from SwiftData
- ✅ `DeviceRegistration` records

**Critical data was left behind in CloudKit:**
- ❌ `PersistentTransaction` - All transaction history with notes
- ❌ `PersistentTag` - All user-created tags
- ❌ `TransactionTagAssignment` - All tag assignments
- ❌ `PersistentContact` - All saved contacts
- ❌ `PersistentContactAddress` - All contact addresses
- ❌ `TransactionContactAssignment` - All contact assignments
- ❌ `ArkBalanceModel` - Cached Ark balance
- ❌ `OnchainBalanceModel` - Cached onchain balance

## Solution

### 1. New Service Methods

#### TagService.deleteAllTags()
```swift
func deleteAllTags() async throws
```
- Deletes all `PersistentTag` records from SwiftData/CloudKit
- Cascade deletion automatically handles `TransactionTagAssignment`
- Clears the in-memory tags array
- Includes comprehensive logging

**Location:** `TagService.swift` - New bulk operations section

#### ContactService.deleteAllContacts()
```swift
func deleteAllContacts() async throws
```
- Deletes all `PersistentContact` records from SwiftData/CloudKit
- Cascade deletion automatically handles:
  - `PersistentContactAddress` (contact addresses)
  - `TransactionContactAssignment` (contact assignments)
- Clears the in-memory contacts array
- Includes comprehensive logging with counts

**Location:** `ContactService.swift` - New bulk operations section

### 2. Enhanced SecurityService Deletion

#### SecurityService.deleteMnemonic(deleteCloudData:)
Enhanced to orchestrate comprehensive deletion when `deleteCloudData: true`.

**New private helper method:**
```swift
private func deleteAllWalletDataFromSwiftData(modelContext: ModelContext) async throws
```

**Deletion order (important for referential integrity):**
1. **Transactions** - Deletes all `PersistentTransaction` records
   - Cascade handles `TransactionTagAssignment`
   - Cascade handles `TransactionContactAssignment`

2. **Tags** - Deletes all `PersistentTag` records
   - Cascade handles any remaining `TransactionTagAssignment` (defensive)

3. **Contacts** - Deletes all `PersistentContact` records
   - Cascade handles `PersistentContactAddress`
   - Cascade handles any remaining `TransactionContactAssignment` (defensive)

4. **Balance Cache** - Deletes cached balance records
   - `ArkBalanceModel` (singleton with id="ark_balance")
   - `OnchainBalanceModel` (singleton with id="onchain_balance")

5. **Configuration** - Deletes `WalletConfiguration`

6. **Device Registry** - Deletes all `DeviceRegistration` records

**Location:** `SecurityService.swift` - Enhanced `deleteMnemonic()` method

### 3. Deletion Flow

```
User initiates wallet deletion
    ↓
DeleteWalletSettingView.checkDevicesAndPromptDeletion()
    ↓
WalletDataCleanupService.getDeletionStrategy()
    ├─> .localOnly (if other devices exist)
    └─> .promptForCloudData (if last device)
    ↓
User confirms deletion choice
    ↓
DeleteWalletSettingView.deleteWallet(includeCloudData: Bool)
    ↓
WalletDataCleanupService.deleteWalletData(includeCloudData: Bool)
    ├─> Step 1: deleteKeychainData()
    ├─> Step 2: Unregister device
    └─> If includeCloudData=true:
        ├─> Step 3: Delete hash from NSUbiquitousKeyValueStore
        └─> deleteCloudKitData()
            ├─> deleteTransactions() + progress update
            ├─> deleteTags() + progress update
            ├─> deleteContacts() + progress update
            ├─> deleteBalanceCache() + progress update
            ├─> deleteConfiguration() + progress update
            ├─> deleteDeviceRegistrations() + progress update
            └─> modelContext.save() (atomic)
    ↓
    Returns DeletionSummary with counts
    ↓
WalletManager.deleteWallet()
    ├─> Delete wallet via bark CLI/FFI
    └─> resetManagerState()
        ├─> Clear service state (memory only)
        └─> Note: SwiftData already cleared by WalletDataCleanupService
    ↓
Navigate back to onboarding
```

## Key Design Decisions

### 1. Dedicated WalletDataCleanupService
All comprehensive deletion logic is centralized in a dedicated `WalletDataCleanupService` rather than scattered across services. This ensures:
- **Single Responsibility**: Service only handles deletion operations
- **Progress Reporting**: Real-time progress updates for UI feedback
- **Atomic Transaction**: Single ModelContext save operation
- **Easy to Audit**: All deletion logic in one place
- **Proper Error Handling**: Dedicated error types and recovery
- **Testability**: Isolated service for comprehensive testing
- **Reusability**: Could be used for other cleanup operations (e.g., "Clear Cache")

### 2. Separation from SecurityService
`SecurityService` focuses on security operations (mnemonic management, biometric authentication), while `WalletDataCleanupService` handles data deletion:
- **Clear boundaries**: Each service has a single, well-defined responsibility
- **Better maintainability**: Changes to deletion logic don't affect security code
- **Improved discoverability**: Developers know where to find deletion code
- **Easier testing**: Can test deletion independently of security features

### 2. Separation from SecurityService
`SecurityService` focuses on security operations (mnemonic management, biometric authentication), while `WalletDataCleanupService` handles data deletion:
- **Clear boundaries**: Each service has a single, well-defined responsibility
- **Better maintainability**: Changes to deletion logic don't affect security code
- **Improved discoverability**: Developers know where to find deletion code
- **Easier testing**: Can test deletion independently of security features

### 3. Cascade Deletion Strategy
SwiftData's cascade deletion rules handle relationships automatically:
- `PersistentTransaction` cascade deletes:
  - `TransactionTagAssignment`
  - `TransactionContactAssignment`
- `PersistentTag` cascade deletes:
  - Remaining `TransactionTagAssignment`
- `PersistentContact` cascade deletes:
  - `PersistentContactAddress`
  - Remaining `TransactionContactAssignment`

This prevents orphaned records and ensures data integrity.

### 4. Deletion Order
Deletion follows a "leaves to root" pattern:
1. Delete keychain data (local)
2. Unregister device (CloudKit)
3. Delete transactions first (they reference tags/contacts)
4. Delete tags (defensive, cascade should have handled assignments)
5. Delete contacts (defensive, cascade should have handled addresses/assignments)
6. Delete balance cache (independent)
7. Delete configuration (independent)
8. Delete device registrations (independent)

### 5. Progress Reporting
Real-time progress updates enhance user experience:
- **DeletionProgress struct**: Contains current step, message, and percentage
- **Observable property**: UI automatically updates as deletion progresses
- **Step-by-step feedback**: User sees "Deleting transactions...", "Deleting tags...", etc.
- **Progress bar**: Visual indicator of deletion progress
- **No blocking**: UI remains responsive during deletion

### 6. Deletion Summary
Comprehensive feedback on what was deleted:
- **DeletionSummary struct**: Detailed counts for every entity type
- **Returned to caller**: Enables logging and verification
- **Human-readable description**: "Deleted: 42 transactions, 5 tags, 3 contacts"
- **Audit trail**: Can be logged for debugging or support
- **Verification**: Ensures all data was properly deleted

### 7. Error Handling
Robust error handling with dedicated error types:
- **WalletCleanupError enum**: Specific error cases with helpful messages
- **Individual try/catch**: Each deletion step catches errors separately
- **Continue on non-fatal errors**: Device unregistration failure doesn't stop deletion
- **Final save throws**: If save fails, entire operation fails (transaction-like)
- **Comprehensive logging**: All errors logged for debugging
- **User-friendly messages**: Errors shown in UI with actionable guidance

### 8. Service Methods Available But Not Used
`TagService.deleteAllTags()` and `ContactService.deleteAllContacts()` were implemented but are **not called** by the deletion flow. Instead, `WalletDataCleanupService` directly deletes from SwiftData.

**Rationale:**
- Avoids service layer overhead during deletion
- Ensures atomic transaction (single ModelContext save)
- Simpler orchestration within cleanup service
- Service methods available for future use (e.g., manual cleanup, admin actions)
- Could be used for selective deletion features

## Related Files

- `WalletDataCleanupService.swift` - **Main deletion orchestration service**
- `SecurityService.swift` - Security operations (renamed `deleteWalletData` method)
- `TagService.swift` - Tag bulk deletion method (available but not used)
- `ContactService.swift` - Contact bulk deletion method (available but not used)
- `DeleteWalletSettingView.swift` - UI and deletion flow with progress
- `ServiceContainer.swift` - Service registration and dependency injection
- `WalletManager.swift` - Wallet deletion and state reset
- `Model_Definitions.md` - Data model relationships and cascade rules

## Testing Considerations

### Test Scenarios

1. **Delete on Last Device**
   - Verify all data removed from CloudKit
   - Verify hash removed from NSUbiquitousKeyValueStore
   - Verify keychain cleared
   - Verify navigation to onboarding

2. **Delete on Non-Last Device**
   - Verify local keychain cleared
   - Verify device unregistered
   - Verify iCloud data remains intact
   - Other devices should still function

3. **Multi-Tagged/Multi-Contact Transactions**
   - Create transactions with multiple tags
   - Create transactions with multiple contacts
   - Delete wallet with deleteCloudData=true
   - Verify all relationships properly deleted

4. **Offline Deletion**
   - Attempt deletion without internet
   - Verify graceful handling
   - Verify sync when online

### Verification Queries

After deletion with `deleteCloudData=true`, these queries should return empty:

```swift
// Check transactions
let txDescriptor = FetchDescriptor<PersistentTransaction>()
let transactions = try modelContext.fetch(txDescriptor)
assert(transactions.isEmpty)

// Check tags
let tagDescriptor = FetchDescriptor<PersistentTag>()
let tags = try modelContext.fetch(tagDescriptor)
assert(tags.isEmpty)

// Check contacts
let contactDescriptor = FetchDescriptor<PersistentContact>()
let contacts = try modelContext.fetch(contactDescriptor)
assert(contacts.isEmpty)

// Check balances
let arkBalanceDescriptor = FetchDescriptor<ArkBalanceModel>()
let arkBalances = try modelContext.fetch(arkBalanceDescriptor)
assert(arkBalances.isEmpty)

// Check configuration
let configDescriptor = FetchDescriptor<WalletConfiguration>()
let configs = try modelContext.fetch(configDescriptor)
assert(configs.isEmpty)

// Check devices
let deviceDescriptor = FetchDescriptor<DeviceRegistration>()
let devices = try modelContext.fetch(deviceDescriptor)
assert(devices.isEmpty)
```

## Performance Characteristics

### Time Complexity
- O(n) where n is total number of records across all entity types
- Single ModelContext save operation (atomic)
- Typical deletion time: < 1 second for normal usage

### Memory Usage
- All entities fetched into memory before deletion
- For large datasets (thousands of transactions), this could use significant memory
- Could be optimized with batch deletion if needed

### Network Usage
- CloudKit sync triggered after ModelContext save
- Deletions propagated to all synced devices
- Network activity proportional to number of deleted records

## Future Enhancements

### Potential Optimizations

1. **Batch Deletion**
   - For very large datasets, implement batch deletion to reduce memory pressure
   - Use `modelContext.delete(batch:)` if available in future SwiftData versions

2. ~~**Progress Reporting**~~ ✅ **Implemented**
   - ~~Add deletion progress callback for UI feedback~~
   - ~~Useful for large datasets~~

3. **Selective Deletion**
   - Allow user to keep certain data (e.g., transaction history for taxes)
   - Implement data export before deletion
   - "Delete wallet but export history" option

4. **Soft Delete**
   - Mark records as deleted instead of hard delete
   - Allow recovery within grace period (e.g., 30 days)
   - Implement background cleanup job for expired soft-deleted records

5. **Audit Trail**
   - Log deletion events to separate audit log
   - Track what was deleted and when
   - Useful for debugging and support
   - Could be stored locally or synced to analytics

### Code Improvements

1. ~~**Extract Deletion Logic**~~ ✅ **Implemented**
   - ~~Create dedicated `WalletDataCleanupService`~~
   - ~~Move deletion logic out of SecurityService~~
   - ~~Better separation of concerns~~

2. **Add Unit Tests**
   - Test each deletion step independently
   - Test cascade behavior
   - Test error handling and recovery
   - Mock ModelContext for isolated testing

3. **Transaction Safety**
   - Wrap entire deletion in explicit transaction
   - Rollback on any failure
   - All-or-nothing guarantee (currently relying on single save)

## Related Files

- `SecurityService.swift` - Main deletion orchestration
- `TagService.swift` - Tag bulk deletion method
- `ContactService.swift` - Contact bulk deletion method
- `DeleteWalletSettingView.swift` - UI and deletion flow
- `WalletManager.swift` - Wallet deletion and state reset
- `Model_Definitions.md` - Data model relationships and cascade rules

## Change Log

### December 9, 2024 - Initial Implementation
- ✅ Added `TagService.deleteAllTags()`
- ✅ Added `ContactService.deleteAllContacts()`
- ✅ Enhanced `SecurityService.deleteWalletData()` (renamed from `deleteMnemonic`) with comprehensive deletion
- ✅ Added `SecurityService.deleteAllWalletDataFromSwiftData()` helper
- ✅ Implemented proper deletion order with cascade handling
- ✅ Added comprehensive logging and error handling
- ✅ Created this documentation

### December 9, 2024 - WalletDataCleanupService Refactor
- ✅ Created dedicated `WalletDataCleanupService` for wallet data cleanup
- ✅ Moved deletion orchestration from `SecurityService` to `WalletDataCleanupService`
- ✅ Added `DeletionSummary` struct with detailed deletion counts
- ✅ Added `DeletionProgress` struct for real-time progress tracking
- ✅ Implemented step-by-step deletion with progress reporting
- ✅ Enhanced error handling with `WalletCleanupError` enum
- ✅ Updated `ServiceContainer` to include `WalletDataCleanupService`
- ✅ Updated `DeleteWalletSettingView` to use new service with progress UI
- ✅ Renamed `SecurityService.deleteMnemonic()` → `deleteWalletData()` for clarity
- ✅ Added environment key for easy injection of cleanup service

---

**Status:** ✅ Fully Implemented with Dedicated Service
**Last Updated:** December 9, 2024
