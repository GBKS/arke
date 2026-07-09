# Wallet Backup Implementation Plan

> **📦 Archived 2026-07-09.** Implementation shipped 2026-05-07: `Shared/Services/WalletBackupService.swift` + `BarkWalletFFI+Backup.swift`, wired into `WalletManager`. Note: the wallet DB file is `bark.sqlite`, not `db.sqlite` as written below (fixed in the 2026-05-07 "Fixed bark db backup file name" commit).

## Overview
Implement automatic backup of the `db.sqlite` file to iCloud Drive for disaster recovery purposes.

## Background
- When creating a wallet with `Wallet.createWithOnchain()`, the Rust FFI creates a `db.sqlite` file in the data directory
- This file contains critical wallet state (VTXOs, round history, etc.) that cannot be reconstructed from mnemonic alone
- The mnemonic is already backed up in Keychain (which syncs via iCloud Keychain)
- We need to back up `db.sqlite` to iCloud for disaster recovery

## Goals
1. Automatic backup of `db.sqlite` to iCloud Drive
2. Restore capability when importing wallet on new device
3. Minimal changes to existing code
4. Works on both iOS and macOS

## Non-Goals
- Live sync between devices (secondary devices are read-only)
- Real-time backup (periodic is sufficient)
- Backup of BDK database (can be reconstructed from blockchain)

## Architecture

### Component 1: WalletBackupService
**Location**: `Arke/Shared/Services/WalletBackupService.swift`

**Responsibilities**:
- Copy `db.sqlite` to iCloud Drive (ubiquity container)
- Restore `db.sqlite` from iCloud Drive
- Maintain timestamped backups (keep last 5)
- Check backup availability

**Key Methods**:
```swift
class WalletBackupService {
    func performBackup() async -> Bool
    func restoreFromBackup(overwriteExisting: Bool) async -> Bool
    func hasBackupAvailable() -> Bool
    func getBackupInfo() async -> BackupInfo?
}
```

### Component 2: BarkWalletFFI Integration
**Location**: `Arke/Shared/Data/BarkWalletFFI/BarkWalletFFI+Backup.swift`

**Responsibilities**:
- Provide backup/restore methods on BarkWalletFFI
- Ensure wallet is shut down before restore
- Trigger backup after wallet operations

**Key Methods**:
```swift
extension BarkWalletFFI {
    func backupWallet() async -> Bool
    func restoreWalletFromBackup() async throws -> Bool
    func hasBackupAvailable() -> Bool
}
```

### Component 3: Automatic Backup Triggers
**Trigger Points**:
1. **After wallet creation** - Initial backup
2. **After wallet import** - Initial backup  
3. **On wallet shutdown** - Final state backup
4. **On app background** (iOS) - Periodic backup
5. **On app becoming inactive** (macOS) - Periodic backup

## Implementation Steps

### Step 1: Create WalletBackupService
- Create service that uses `FileManager.url(forUbiquityContainerIdentifier:)` 
- Implement copy operations to/from iCloud
- Handle backup directory creation
- Implement cleanup of old backups

### Step 2: Add Backup Extension to BarkWalletFFI
- Create `BarkWalletFFI+Backup.swift`
- Add methods that delegate to WalletBackupService
- Use existing `walletDir` property to locate `db.sqlite`

### Step 3: Trigger Backup After Wallet Creation
**File**: `BarkWalletFFI+WalletCreation.swift`
- Add `await backupWallet()` after successful wallet creation
- Add `await backupWallet()` after successful wallet import

### Step 4: Trigger Backup on Shutdown
**File**: `BarkWalletFFI+WalletLifecycle.swift`
- Add `await backupWallet()` in `shutdownWallet()` method
- Place after sync but before clearing wallet reference

### Step 5: Add Scene Phase Observers
**Files**: `ArkeMobile.swift` and `ArkeDesktop.swift`
- Add `@Environment(\.scenePhase)` observer
- Call backup when app goes to background/inactive
- Keep minimal - just trigger the backup

### Step 6: Add Restore Option to Import Flow
**File**: `BarkWalletFFI+WalletCreation.swift`
- Check for backup availability before creating new database
- Log availability but don't auto-restore (user decision)
- Future: Add UI option to restore during import

### Step 7: Update Entitlements
**Files**: 
- `ArkeDesktop/ArkeDesktop.entitlements`
- `ArkeMobile/ArkeMobile.entitlements`

Add CloudDocuments to iCloud services:
```xml
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
    <string>CloudDocuments</string>
</array>
```

## File Changes Summary

### New Files
1. `Arke/Shared/Services/WalletBackupService.swift` - Core backup logic
2. `Arke/Shared/Data/BarkWalletFFI/BarkWalletFFI+Backup.swift` - FFI integration

### Modified Files
1. `Arke/Shared/Data/BarkWalletFFI/BarkWalletFFI+WalletCreation.swift` - Trigger backup after create/import
2. `Arke/Shared/Data/BarkWalletFFI/BarkWalletFFI+WalletLifecycle.swift` - Trigger backup on shutdown
3. `Arke/ArkeMobile/ArkeMobile.swift` - Scene phase observer (iOS)
4. `Arke/ArkeDesktop/ArkeDesktop.swift` - Scene phase observer (macOS)
5. `Arke/ArkeDesktop/ArkeDesktop.entitlements` - Add CloudDocuments
6. `Arke/ArkeMobile/ArkeMobile.entitlements` - Add CloudDocuments

### NOT Modified
- No protocol changes needed
- No WalletManager changes needed (for now)
- No UI changes needed (for now)
- No changes to mock implementations

## Testing Plan

### Manual Testing
1. **Create wallet** → Check iCloud for backup file
2. **Import wallet** → Check iCloud for backup file
3. **Background app** → Check backup timestamp updates
4. **Delete local db** → Restore from backup
5. **Check multiple devices** → Verify iCloud sync

### What to Verify
- Backup file appears in iCloud Drive
- File size is reasonable (should be small DB)
- Timestamped backups are created
- Old backups are cleaned up (keep 5)
- Restore creates working database

## Rollback Plan
If issues arise:
1. All backup code is isolated in new files
2. No existing functionality is modified (only additions)
3. Can disable by commenting out backup calls
4. Backup failures are logged but don't block wallet operations

## Future Enhancements
1. UI to view backup status in Settings
2. Manual backup/restore buttons
3. Backup encryption (currently relies on iCloud encryption)
4. Backup to other cloud providers
5. Smart restore prompt when importing wallet

## Risk Mitigation

### Risk: iCloud not available
**Mitigation**: All backup operations are non-blocking. Wallet works normally if iCloud unavailable.

### Risk: Backup corrupted
**Mitigation**: Keep 5 timestamped backups. Always have fallback.

### Risk: Performance impact
**Mitigation**: Backups are async and triggered at appropriate times (shutdown, background).

### Risk: Restore overwrites good data
**Mitigation**: Restore requires explicit flag. Never auto-restore without user action.
