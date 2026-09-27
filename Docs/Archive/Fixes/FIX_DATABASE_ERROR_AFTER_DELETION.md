# Fix: Database Error After Wallet Deletion

## Problem
When deleting a wallet and immediately creating a new one, the app would fail with:
```
Failed to create wallet: Configuration error: Failed to create wallet: 
Bark.BarkError.Database (errorMessage: "no such table: bark_properties: 
Error code 1: SQL error or missing database")
```

This issue only occurred when creating a wallet immediately after deletion. Restarting the app would resolve the issue.

## Root Cause
The `BarkWalletFFI` Rust layer maintains internal database connections that weren't being properly released when the wallet was deleted. The sequence was:

1. User deletes wallet
2. Swift sets `wallet = nil` 
3. Wallet directory is immediately deleted
4. **BUT**: Rust FFI still had open database handles
5. User creates new wallet
6. FFI tries to access database that was deleted with handles still open
7. **Result**: Database corruption / "table not found" error

## Solution

### Multi-Layer State Reset Strategy

The fix implements a comprehensive cleanup process:

1. **Explicit Shutdown** - New `shutdownWallet()` method that:
   - Syncs any pending state
   - Waits 500ms for database writes to flush
   - Clears all wallet references
   - Waits additional 500ms for SQLite to close connections

2. **Enhanced Deletion** - Updated `deleteWallet()` to:
   - Call explicit shutdown before file deletion
   - Verify directory is completely removed
   - Provide better error messages

3. **Pre-Creation Checks** - Updated `createWallet()` to:
   - Check for existing wallet instance and shutdown if found
   - Remove stale wallet directories before creation
   - Add delays for filesystem operations
   - Enhanced error handling with retry suggestions
   - Better logging for database errors

4. **Manager Coordination** - Updated `WalletManager.deleteWallet()` to:
   - Reset manager state BEFORE deletion
   - Add 500ms settling time for services
   - Prevent concurrent operations during deletion

5. **UI-Level Retry** - Updated `CreateWalletView_iOS` to:
   - Automatically retry on database errors (up to 3 attempts)
   - Add 1-second delay between retries
   - Provide clear error messages to users

## Files Changed

### 1. `BarkWalletFFI.swift`
- **Added**: `shutdownWallet()` method for explicit cleanup
- **Updated**: `deleteWallet()` with shutdown and verification
- **Updated**: `createWallet()` with pre-checks and error recovery

### 2. `WalletManager.swift`
- **Updated**: `deleteWallet()` to reset state first and add settling time

### 3. `CreateWalletView_iOS.swift`
- **Updated**: `startWalletCreation()` with retry logic for database errors

## Key Improvements

### Timing Guarantees
- **500ms** after sync for database flush
- **500ms** after clearing references for SQLite cleanup
- **200ms** after directory deletion for filesystem
- **1 second** between retry attempts

### Error Detection
Automatically detects database-related errors by checking for:
- "bark_properties"
- "database" 
- "SQL"

### Retry Strategy
- Maximum 3 attempts (initial + 2 retries)
- 1-second delay between attempts
- Automatic cleanup before retry
- Clear user feedback on persistent failures

## Testing Scenarios

### ✅ Should Work Now
1. Delete wallet → Immediately create new wallet
2. Delete wallet → Wait 5 seconds → Create wallet
3. Create → Delete → Create (rapid cycle)
4. Delete wallet → Restart app → Create wallet

### Expected Behavior
- **First attempt**: May succeed or fail with database error
- **Automatic retry**: Should succeed after cleanup
- **User experience**: Brief pause (1-2 seconds), then success
- **Persistent failure**: Clear error message suggesting restart

## Technical Details

### Database Handle Management
The Rust FFI maintains SQLite connections internally. When Swift sets `wallet = nil`, the Rust `Drop` trait is called, but:
- SQLite may have pending writes
- OS may buffer filesystem operations
- Database WAL (Write-Ahead Log) needs to be checkpointed

The 500ms delays ensure all these operations complete before directory deletion.

### Filesystem Race Conditions
macOS and iOS filesystems are asynchronous. Deleting a directory doesn't guarantee immediate removal. The checks and delays ensure:
- All file handles are closed
- Directory is fully deleted
- New directory creation starts clean

### Retry Logic Rationale
- **First attempt**: May fail if timing is tight
- **First retry** (after 1s): Usually succeeds after cleanup
- **Second retry** (after 2s): Handles edge cases
- **Give up**: Suggest restart for persistent issues

## Monitoring

### Success Indicators
Look for these log messages:
```
✅ Wallet shutdown complete
✅ Old directory removed
✅ Wallet created successfully
```

### Failure Indicators
```
❌ Failed to remove old directory
💡 Database error detected
⚠️ Warning: Directory still exists after deletion
```

## Future Improvements

1. **Rust FFI Enhancement**: Add explicit `shutdown()` method in Rust
2. **State Machine**: Implement formal state machine for wallet lifecycle
3. **Telemetry**: Track retry rates and failure patterns
4. **User Guidance**: Add visual feedback during cleanup/retry

## Related Issues

This fix also improves:
- Wallet import after deletion
- App stability during rapid wallet operations
- Error messages for users
- Debugging information in logs

## Version
- **Fixed**: January 26, 2026
- **Impact**: High (resolves critical UX issue)
- **Risk**: Low (adds safety delays and retries)
