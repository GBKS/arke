# Fix: Duplicate Mnemonic Storage During Wallet Creation

## Problem

During wallet creation, the mnemonic was being saved **multiple times** in rapid succession, causing unnecessary operations and potential race conditions:

### Original Flow (BEFORE FIX)

1. `WalletManager.createWallet()` calls `wallet.createWallet()` (BarkWalletFFI)
2. `BarkWalletFFI.createWallet()` generates mnemonic, creates wallet
3. `BarkWalletFFI.createWallet()` calls `storeMnemonic()`
   - `storeMnemonic()` calls `securityService.saveMnemonic()` 
     - **SAVE #1**: `saveMnemonic()` saves to Keychain
     - **SAVE #2**: `saveMnemonic()` calls `saveHashToUbiquitousStore()` (iCloud KVS)
   - `storeMnemonic()` calls `securityService.saveHashToStorage()`
     - **SAVE #3**: Saves hash to SwiftData
4. Control returns to `WalletManager.createWallet()`
5. `WalletManager.createWallet()` calls `securityService.saveMnemonic()` again
   - **SAVE #4**: Saves to Keychain again (redundant)
   - **SAVE #5**: Calls `saveHashToUbiquitousStore()` again (redundant)
6. `WalletManager.createWallet()` calls `securityService.saveHashToStorage()` again
   - **SAVE #6**: Saves hash to SwiftData again (redundant)

### Debug Logs Showing Duplication

```
✅ [SecurityService] Saved hash to NSUbiquitousKeyValueStore at 2025-12-11 15:01:40 +0000
✅ [SecurityService] Mnemonic saved to keychain and hash saved to ubiquitous store
✅ Mnemonic stored securely in Keychain
✅ [SecurityService] Saved hash to NSUbiquitousKeyValueStore at 2025-12-11 15:01:40 +0000
✅ [SecurityService] Mnemonic saved to keychain and hash saved to ubiquitous store
⚠️ Failed to save mnemonic hash: unknown("No model context available")
```

Note the duplicate saves and the final failure due to race condition with model context.

## Solution

**Establish clear ownership:** `WalletManager` is responsible for mnemonic storage, not `BarkWalletFFI`.

### Changes Made

#### 1. BarkWalletFFI.createWallet() - Remove storage call
**File**: `BarkWalletFFI.swift` (line ~625)

**Before:**
```swift
// Store mnemonic securely
try await storeMnemonic(mnemonic)

return mnemonic
```

**After:**
```swift
// NOTE: Mnemonic storage is handled by WalletManager.createWallet() to avoid duplication
// Only importWallet() flow should call storeMnemonic() directly

return mnemonic
```

#### 2. BarkWalletFFI.storeMnemonic() - Add clarifying comments
**File**: `BarkWalletFFI.swift` (line ~2118)

Updated comments to clarify:
- This method is for **import flows only**
- New wallet creation storage is handled by `WalletManager`
- Explained that `saveMnemonic()` already calls `saveHashToUbiquitousStore()` internally

#### 3. WalletManager.createWallet() - Improve comments
**File**: `WalletManager.swift` (line ~972)

Clarified the two-stage storage:
1. `saveMnemonic()` → Saves to Keychain + iCloud KVS
2. `saveHashToStorage()` → Saves to SwiftData for CloudKit sync (separate from KVS)

This makes it clear why both calls are needed and that they serve different purposes.

### New Flow (AFTER FIX)

1. `WalletManager.createWallet()` calls `wallet.createWallet()` (BarkWalletFFI)
2. `BarkWalletFFI.createWallet()` generates mnemonic, creates wallet, **returns mnemonic**
3. `WalletManager.createWallet()` handles storage:
   - **SAVE #1**: `saveMnemonic()` → Keychain
   - **SAVE #2**: `saveMnemonic()` → iCloud KVS (via internal call)
   - **SAVE #3**: `saveHashToStorage()` → SwiftData (CloudKit sync)

**Result**: 3 saves instead of 6, no duplication, clear separation of concerns.

## Why Two Hash Storage Locations?

The hash is stored in **two places** for good reasons:

1. **iCloud Key-Value Store (KVS)** - Fast, lightweight sync for wallet detection
   - Syncs in seconds across devices
   - Available before SwiftData initializes
   - Used for early wallet detection in `detectWalletState()`
   
2. **SwiftData (CloudKit)** - Comprehensive app data storage
   - Syncs with other app data (transactions, contacts, etc.)
   - Better integration with app's data model
   - Provides backup/redundancy

Both serve different purposes and should coexist.

## Testing

After this fix, wallet creation should show:
```
✅ Mnemonic saved to keychain and hash synced via iCloud KVS
✅ Mnemonic hash also saved to SwiftData for CloudKit sync
```

Instead of multiple duplicate save messages and race condition errors.

## Related Issues Fixed

This also resolves:
- Race condition where `saveHashToStorage()` was called before ModelContext was ready
- Unnecessary keychain writes (security APIs are expensive)
- CloudKit quota concerns from duplicate saves
- Log noise making debugging harder
