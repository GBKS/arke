# Device Migration Implementation Plan (REVISED)

**Created:** 2026-05-08
**Last Revised:** 2026-05-12
**Status:** Planning
**Priority:** High (Critical for safe multi-device use)

---

## Revision Summary

**Changes from original plan:**
- ✅ Removed push notification layer (not needed for MVP)
- ✅ Simplified from 4-layer to 3-layer defense strategy
- ✅ Leveraged existing NSUbiquitousKeyValueStore infrastructure in MainView_iOS.swift
- ✅ Added missing data model properties (`demotedAt`, `becamePrimaryAt`, `emergencyTakeover`)
- ✅ Replaced `closeWallet()` with Swift ARC-based deallocation (FFI doesn't provide close method)
- ✅ Referenced existing AppDelegate_iOS for future notification expansion
- ✅ Clarified integration with existing LinkedDevicesView_iOS
- ✅ Removed redundant iCloud KV Store setup (already exists)
- ✅ **CRITICAL ADDITION**: Documented wallet state backup/restore requirement
  - Added explicit backup before demotion
  - Added restore check on new primary initialization
  - Leveraged existing WalletBackupService infrastructure
  - Added edge case handling for stale/missing backups
- ✅ **SECURITY ENHANCEMENT (2026-05-12)**: Changed Path 1 from single-step "Controlled Handoff" to two-step migration
  - **Step 1**: Primary device demotes itself
  - **Step 2**: Secondary device promotes itself
  - **Security benefit**: Requires physical access to both devices, prevents remote hijacking
  - **Safe intermediate state**: "No primary device" mode is read-only everywhere (safe, just temporarily inconvenient)
  - **Easy recovery**: Any secondary can promote itself with simple confirmation if step 2 is forgotten

---

## Executive Summary

This document outlines the implementation of **safe device migration** with two distinct paths:

1. **Two-Step Migration**: Safe migration requiring physical access to both devices (prevents remote hijacking)
2. **Emergency Takeover**: Risky migration when primary device is lost/unavailable

The goal is to enable users to switch which device is their primary wallet device while minimizing the risk of database corruption from race conditions. The two-step migration approach provides strong security guarantees by requiring the user to explicitly perform actions on both devices, preventing attacks where a malicious actor gains access to only one device.

---

## The Problem

### Current State
- ✅ Basic `migrateToThisDevice()` API exists (DeviceRegistrationService.swift:554)
- ✅ CloudKit syncs `isPrimaryDevice` flag across devices
- ✅ Read-only mode fully implemented (WalletManager.isReadOnlyMode)
- ✅ NSUbiquitousKeyValueStore infrastructure exists (MainView_iOS.swift:155-290)
- ❌ No protection against race conditions
- ❌ No distinction between safe and risky migrations
- ❌ No UI for initiating migration

### The Race Condition Risk
```
T0: User migrates iPad to primary
T1: iPad updates CloudKit (isPrimaryDevice = true)
T2: iPhone hasn't synced CloudKit yet
T3: User opens iPhone
T4: iPhone thinks it's still primary, opens wallet
T5: 💥 Both devices have wallet open → database divergence
```

---

## Critical Requirement: Wallet State Backup/Restore

### The Wallet State Problem

The wallet database (`bark.sqlite`) contains **critical state that cannot be reconstructed from the mnemonic**:
- **VTXOs**: Virtual UTXOs managed by the ASP
- **Round history**: Past ASP rounds and confirmations
- **Transaction metadata**: Notes, contacts, tags
- **ASP connection state**: Session info, pending operations

**Without this file, the new primary device would start with a blank wallet** despite having the mnemonic.

### Backup/Restore During Migration

#### Controlled Handoff Flow (Path 1)
```
1. Old primary: Creates final backup of bark.sqlite to iCloud Drive
2. Old primary: Updates device registry (isPrimaryDevice = false)
3. Old primary: Closes wallet
4. New primary: Detects promotion (isPrimaryDevice = true)
5. New primary: Checks for local bark.sqlite file
6. New primary: If missing, restores from iCloud backup
7. New primary: Opens wallet with restored state
```

#### Emergency Takeover Flow (Path 2)
```
1. New primary: Updates device registry (isPrimaryDevice = true)
2. New primary: Checks for local bark.sqlite file
3. New primary: If missing, restores from MOST RECENT backup in iCloud
   ⚠️ Warning: Backup might be stale if old device was offline/lost
4. New primary: Opens wallet with potentially stale state
5. New primary: Syncs with ASP to catch up on any missed rounds
```

### Existing Infrastructure

✅ **WalletBackupService already implemented** (Arke/Shared/Services/WalletBackupService.swift):
- `performBackup()` - Copies bark.sqlite to iCloud Drive
- `restoreFromBackup(overwriteExisting:)` - Restores bark.sqlite from iCloud
- `hasBackupAvailable()` - Checks if backup exists
- Uses iCloud Drive ubiquity container (not CloudKit)
- Maintains timestamped backups (keeps last 5)

✅ **BarkWalletFFI+Backup.swift** provides wallet-level API:
- `wallet.backupWallet()` - Delegates to WalletBackupService
- `wallet.restoreWalletFromBackup()` - Delegates to WalletBackupService
- `wallet.hasBackupAvailable()` - Delegates to WalletBackupService

### What Needs to Be Added

❌ **Missing API**: Check if local wallet file exists
- Need `wallet.hasLocalWalletFile() async -> Bool`
- Checks if `bark.sqlite` exists in wallet directory
- Used to determine if restore is needed

### Backup Timing

**Automatic backups already happen**:
- After wallet creation
- After wallet import
- On app background/inactive
- On wallet shutdown

**Migration adds**:
- **Explicit backup before demotion** (controlled handoff only)
- **Restore check on primary device initialization**

### Edge Cases

1. **No backup exists** (new wallet, never backed up):
   - New primary starts with empty wallet
   - Will sync with ASP to discover VTXOs
   - May miss historical round data

2. **Backup is stale** (emergency takeover):
   - New primary warns user
   - Shows "restored from backup X days old"
   - Syncs with ASP to catch up

3. **iCloud unavailable**:
   - Migration still proceeds
   - No backup/restore possible
   - User warned about potential data loss

4. **Both devices online during emergency takeover**:
   - Old primary's backup is most recent
   - New primary restores and continues
   - Old primary detects demotion and stops

---

## Solution: Two Migration Paths

### Path 1: Two-Step Migration (SAFE) ⭐
**When to use**: Both devices are available and you want to switch primary devices

**Key safety features**: 
- Requires physical access to both devices
- Prevents remote hijacking attacks
- Creates safe intermediate state (read-only everywhere)

**Flow**:
```
Step 1: Demote Current Primary
iPhone (current primary) → Settings → Device Management
  ↓
"Make This Device Secondary" button
  ↓
Confirmation: "Make sure you have your other device ready. 
              After this, you'll need to open that device and make it primary."
  ↓
iPhone:
  1. Creates backup of wallet state to iCloud Drive
  2. Updates CloudKit (iPhone.isPrimaryDevice = false)
  3. Updates iCloud KV Store for fast sync
  4. Sets local UserDefaults flag
  5. Closes wallet immediately (deallocates BarkWalletFFI)
  6. Switches to read-only mode
  ↓
Intermediate State: No device is primary
  - All devices in read-only mode (safe!)
  - User can view balance/transactions
  - User cannot send/receive until step 2 completes
  ↓

Step 2: Promote New Primary
iPad (currently secondary) → Settings → Device Management
  ↓
"Make This Device Primary" button
  ↓
Simple confirmation: "Make this your active wallet device?"
  ↓
iPad:
  1. Detects no current primary device exists
  2. Updates CloudKit (iPad.isPrimaryDevice = true)
  3. Updates iCloud KV Store for fast sync
  4. Checks for local wallet file
  5. Restores from iCloud backup if needed
  6. Opens wallet
  7. Switches to primary mode
  ↓
Success! Migration complete with strong security guarantees.
```

**Security Benefits**:
- **Requires physical possession of both devices** - attacker with just one device cannot complete migration
- **No remote control** - each device only modifies its own state
- **Safe intermediate state** - if step 2 is forgotten, wallet is read-only everywhere (safe, just inconvenient)
- **Easy recovery** - any secondary device can promote itself with a simple button tap

**Recovery from Incomplete Migration**:
If user demotes iPhone but forgets to promote iPad:
- All devices show banner: "No active wallet - make this device your primary wallet to send and receive"
- Any device can promote itself with a simple confirmation
- No data loss, no corruption risk - just temporarily unable to transact

### Path 2: Emergency Takeover (RISKY) ⚠️
**When to use**: Primary device is lost, stolen, broken, or permanently unavailable

**Key risk**: Old primary device might open wallet before receiving CloudKit/KV Store update.

**Flow**:
```
iPad (current secondary) → Settings → Device Management
  ↓
"Emergency Recovery" button
  ↓
Warning dialog #1: "Only do this if iPhone is permanently gone"
  ↓
Type confirmation: "I UNDERSTAND"
  ↓
Final warning dialog #2: "Small risk if iPhone comes back online"
  ↓
iPad:
  1. Updates CloudKit (iPad.isPrimaryDevice = true, iPhone.isPrimaryDevice = false)
  2. Updates iCloud KV Store immediately
  3. Sets local UserDefaults flag on old device ID
  4. Does NOT wait for confirmation (device might never come online)
  5. Checks for local wallet file
  6. Restores from most recent iCloud backup if needed
  7. Opens wallet immediately
  8. Shows persistent warning banner for 7 days
  ↓
iPhone (when/if it comes online):
  1. Detects demotion via multi-layered check
  2. Blocks wallet initialization
  3. Switches to read-only mode
  4. Shows informational banner
```

---

## Data Model Changes

### DeviceRegistration Model Extensions

**Add to Arke/Shared/Models/DeviceRegistration.swift:**

```swift
// New properties for safe migration
var handoffInitiatedAt: Date?        // Set when controlled handoff starts
var handoffCompletedAt: Date?        // Set when handoff completes
var emergencyTakeover: Bool = false  // True if forced migration (Path 2)
var becamePrimaryAt: Date?           // When device became primary
var canBeDemotedAt: Date?            // When device can be demoted (cooldown period)
var demotedAt: Date?                 // When device was demoted from primary
```

**Update init() method to include new parameters:**

```swift
init(
    id: UUID = UUID(),
    deviceId: String,
    deviceName: String,
    platform: DevicePlatform,
    walletHash: String,
    hasSeed: Bool,
    isPrimaryDevice: Bool = false,
    registeredAt: Date = Date(),
    lastSeenAt: Date = Date(),
    lastAppVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
    isActive: Bool = true,
    deviceModelIdentifier: String? = nil,
    handoffInitiatedAt: Date? = nil,
    handoffCompletedAt: Date? = nil,
    emergencyTakeover: Bool = false,
    becamePrimaryAt: Date? = nil,
    canBeDemotedAt: Date? = nil,
    demotedAt: Date? = nil
) {
    self.id = id
    self.deviceId = deviceId
    self.deviceName = deviceName
    self.platform = platform.rawValue
    self.walletHash = walletHash
    self.hasSeed = hasSeed
    self.isPrimaryDevice = isPrimaryDevice
    self.registeredAt = registeredAt
    self.lastSeenAt = lastSeenAt
    self.lastAppVersion = lastAppVersion
    self.isActive = isActive
    self.deviceModelIdentifier = deviceModelIdentifier
    self.handoffInitiatedAt = handoffInitiatedAt
    self.handoffCompletedAt = handoffCompletedAt
    self.emergencyTakeover = emergencyTakeover
    self.becamePrimaryAt = becamePrimaryAt
    self.canBeDemotedAt = canBeDemotedAt
    self.demotedAt = demotedAt
}
```

### Migration Type Enum

**Add to DeviceRegistrationService.swift:**

```swift
enum MigrationType {
    case twoStepMigration     // Path 1: Safe two-step process, requires both devices
    case emergencyTakeover    // Path 2: Risky, old primary unavailable
}
```

### Local Storage Keys

```swift
// Local flag set during demotion or detected from remote changes
// Checked BEFORE CloudKit on app launch for fast detection
UserDefaults.standard.bool(forKey: "device_\(deviceId)_wasDemoted")

// iCloud KV Store keys (already set up in MainView_iOS.swift:155-290)
// Just need to add migration-specific keys:
NSUbiquitousKeyValueStore.default.bool(forKey: "device_\(deviceId)_isPrimary")
```

---

## Race Condition Mitigation Strategy

### The Core Problem

CloudKit sync is **eventually consistent** but **not instantaneous**. If an old primary device comes online after emergency takeover but before CloudKit sync completes, it might open the wallet for write access, causing database corruption.

**Timeline of the race condition:**
```
T0: iPad does emergency takeover (updates CloudKit)
T1: User finds "lost" iPhone days later
T2: iPhone comes online but hasn't synced CloudKit yet
T3: User opens app on iPhone
T4: 💥 iPhone thinks it's still primary, opens wallet
T5: Both devices have wallet open → corruption
```

### Multi-Layered Defense Approach

We use **three independent mechanisms** to detect demotion, checked in order of speed:

#### Layer 1: UserDefaults (Instant, Local-Only)
- **Speed**: <1ms
- **Reliability**: Survives app restarts, NOT factory resets
- Set explicitly during migration
- Checked first on every app launch

#### Layer 2: NSUbiquitousKeyValueStore (Fast, 1-10 seconds) ✅ ALREADY EXISTS
- **Speed**: 1-5ms to read, syncs in 1-10 seconds typically
- **Reliability**: Faster than CloudKit, but still eventual consistency
- **Already implemented**: MainView_iOS.swift:155-290 handles KV store changes
- **What we need**: Extend existing `handleUbiquitousStoreChange()` to check for `device_{id}_isPrimary` keys
- Limited to 1MB total storage (plenty for just isPrimary flags)

#### Layer 3: CloudKit (Slow, but most reliable long-term)
- **Speed**: Seconds to minutes
- **Reliability**: Eventually consistent, persists indefinitely
- Full device registration records with all metadata
- Final source of truth for device state

### Startup Check Flow

**Add to WalletManager.swift:**

```swift
/// Multi-layered check if device has been demoted
/// This runs BEFORE wallet initialization to prevent race conditions
func shouldBlockWalletAccess() async -> Bool {
    guard let deviceId = try? ServiceContainer.shared.deviceRegistrationService.getOrCreateDeviceId() else {
        return false
    }

    // Layer 1: Check local UserDefaults (instant, <1ms)
    if UserDefaults.standard.bool(forKey: "device_\(deviceId)_wasDemoted") {
        Self.logger.info("🛑 [WalletManager] Blocked: UserDefaults indicates demotion")
        return true
    }

    // Layer 2: Check iCloud KV store (fast, ~1-5ms, local cache)
    let kvStore = NSUbiquitousKeyValueStore.default
    let isPrimaryInKVStore = kvStore.bool(forKey: "device_\(deviceId)_isPrimary")
    // Check if key exists (bool returns false for both "false" and "doesn't exist")
    if kvStore.object(forKey: "device_\(deviceId)_isPrimary") != nil && !isPrimaryInKVStore {
        Self.logger.info("🛑 [WalletManager] Blocked: iCloud KV store indicates demotion")
        return true
    }

    // Layer 3: Check CloudKit via device registration (no network call, uses local cache)
    if let device = try? await ServiceContainer.shared.deviceRegistrationService.getCurrentDevice(),
       !device.isPrimaryDevice {
        Self.logger.info("🛑 [WalletManager] Blocked: CloudKit cache indicates demotion")
        return true
    }

    // All checks passed - allow wallet access
    return false
}
```

**Performance Impact**: Total startup delay is ~2-10ms (all local checks, no network calls)

### Emergency Takeover Sync Flow

**Add to DeviceRegistrationService.swift:**

```swift
/// Emergency takeover when primary device is unavailable
func emergencyTakeoverAsPrimary() async throws {
    // 1. Verify we are NOT currently primary
    guard let currentDevice = try await getCurrentDevice(),
          !currentDevice.isPrimaryDevice else {
        throw MigrationError.alreadyPrimary
    }

    // 2. Find current primary device
    guard let oldPrimary = try await getPrimaryDevice() else {
        throw MigrationError.noPrimaryDeviceFound
    }

    // 3. Update CloudKit (don't wait for confirmation - device might be offline)
    oldPrimary.isPrimaryDevice = false
    oldPrimary.demotedAt = Date()

    currentDevice.isPrimaryDevice = true
    currentDevice.becamePrimaryAt = Date()
    currentDevice.canBeDemotedAt = Date().addingTimeInterval(3600) // 1 hour cooldown
    currentDevice.emergencyTakeover = true

    try modelContext?.save()

    // 4. Update iCloud KV store for faster sync (Layer 2 protection)
    // This leverages the EXISTING infrastructure in MainView_iOS.swift:155-290
    let kvStore = NSUbiquitousKeyValueStore.default
    kvStore.set(false, forKey: "device_\(oldPrimary.deviceId)_isPrimary")
    kvStore.set(true, forKey: "device_\(currentDevice.deviceId)_isPrimary")
    kvStore.synchronize()

    // 5. Set local UserDefaults flag on old device (will be read on next launch)
    // Note: This only works if THIS device is the old primary, which it's not in emergency takeover
    // But we set it anyway for consistency
    UserDefaults.standard.set(false, forKey: "device_\(oldPrimary.deviceId)_wasDemoted")

    // 6. Don't wait for sync - proceed immediately
    // Old primary will detect demotion via KV store/CloudKit when it comes online

    // 7. IMPORTANT: Check if wallet backup exists in iCloud
    // If not, warn user that wallet state might be stale
    // Emergency takeover can't force a backup from the lost device
    print("⚠️ [DeviceRegistrationService] Emergency takeover - will restore from most recent backup")

    print("✅ [DeviceRegistrationService] Emergency takeover complete")
}
```

### Known Limitations

⚠️ **There is no 100% foolproof solution** without a centralized coordination server. Edge cases remain:

1. **Extended offline period**: Device offline for weeks won't receive any updates
2. **Factory reset**: UserDefaults flag lost (but CloudKit will eventually sync)
3. **Network failure during emergency**: All sync mechanisms delayed
4. **Simultaneous emergency takeover**: If two devices both do emergency takeover simultaneously, last-write-wins in CloudKit

**Mitigation**: Heavy warnings in emergency takeover UI, instructing users not to use old device for 24-48 hours.

---

## Implementation Phases

### Phase 1: Data Model & Core Logic

**What exists**:
- ✅ `DeviceRegistration.isPrimaryDevice` flag
- ✅ Basic `migrateToThisDevice()` method (DeviceRegistrationService.swift:554)
- ✅ CloudKit sync of device registrations
- ✅ NSUbiquitousKeyValueStore infrastructure (MainView_iOS.swift:155-290)
- ✅ Read-only mode (WalletManager.isReadOnlyMode, Features/Read_Only_Mode.md)

**What needs to be added**:

1. **Add new properties to `DeviceRegistration` model:**
   - `demotedAt: Date?` - When device was demoted from primary
   - `emergencyTakeover: Bool` - True if became primary via emergency takeover
   - `becamePrimaryAt: Date?` - When device became primary
   - Update `init()` method with all new parameters

2. **Add `MigrationType` enum**

3. **Extend `DeviceRegistrationError` with migration errors:**
   ```swift
   enum MigrationError: LocalizedError {
       case alreadyPrimary
       case deviceNotFound
       case noPrimaryDeviceFound
       case primaryDeviceExists
       case cloudKitSyncTimeout
   }
   ```

4. **Define notification names** (new file or extension):
   ```swift
   extension Notification.Name {
       static let deviceDemotedFromPrimary = Notification.Name("deviceDemotedFromPrimary")
       static let devicePromotedToPrimary = Notification.Name("devicePromotedToPrimary")
       static let showEmergencyTakeoverBanner = Notification.Name("showEmergencyTakeoverBanner")
       static let showNoPrimaryDeviceBanner = Notification.Name("showNoPrimaryDeviceBanner")
   }
   ```

5. **Extend MainView_iOS to handle migration keys**
   - Update `handleUbiquitousStoreChange()` (line 239) to check for `device_{id}_isPrimary` keys
   - When detected, trigger wallet re-initialization or demotion

6. **Add `demoteThisDevice()` method to DeviceRegistrationService** (Step 1 of two-step migration)

7. **Add `promoteThisDeviceToPrimary()` method to DeviceRegistrationService** (Step 2 of two-step migration)

8. **Add `emergencyTakeoverAsPrimary()` method to DeviceRegistrationService** (Emergency path)

9. **Add `shouldBlockWalletAccess()` to WalletManager** (called before initialization)

10. **Add `closeWalletForMigration()` to WalletManager**

11. **Add `observeMigrationNotifications()` to WalletManager**

12. **Add `checkForNoPrimaryDevice()` to DeviceRegistrationService** (detects intermediate state)

**Files to modify**:
- `Arke/Shared/Models/DeviceRegistration.swift`
- `Arke/Shared/Services/DeviceRegistrationService.swift`
- `Arke/Shared/Data/WalletManager/WalletManager.swift`
- `Arke/ArkeMobile/Views/MainView_iOS.swift` (extend existing KV store handler)
- Create `Arke/Shared/Helpers/NotificationNames.swift` (new file for notification definitions)

11. **Add wallet file existence check to BarkWalletProtocol**
    ```swift
    func hasLocalWalletFile() async -> Bool
    ```

**Critical Dependency**: WalletBackupService (already implemented at Arke/Shared/Services/WalletBackupService.swift)
- Provides `performBackup()`, `restoreFromBackup()`, `hasBackupAvailable()`
- Uses iCloud Drive ubiquity container
- See WALLET_BACKUP_PLAN.md for details

---

### Phase 2: Safe Two-Step Migration (Path 1)

**Goal**: Implement the safe two-step migration path that requires physical access to both devices.

#### 2.1 Service Layer

**DeviceRegistrationService.swift**:

```swift
/// Step 1: Demote this device from primary (requires user has both devices)
func demoteThisDevice() async throws {
    // 1. Verify we are currently primary
    guard try await isCurrentDevicePrimary() else {
        throw MigrationError.notPrimaryDevice
    }

    // 2. Get current device
    guard let currentDevice = try await getCurrentDevice() else {
        throw MigrationError.deviceNotFound
    }

    // 3. CRITICAL: Backup wallet state to iCloud BEFORE demotion
    // This ensures the new primary has the latest wallet state
    let backupSuccess = await ServiceContainer.shared.walletManager.wallet?.backupWallet() ?? false
    if !backupSuccess {
        print("⚠️ [DeviceRegistrationService] Wallet backup failed during demotion")
        // Continue anyway - backup might already exist from previous operations
    } else {
        print("✅ [DeviceRegistrationService] Wallet backup completed")
    }

    // 4. Update current device to be secondary
    currentDevice.isPrimaryDevice = false
    currentDevice.demotedAt = Date()

    // 5. Save to CloudKit
    try modelContext?.save()

    // 6. Update iCloud KV Store for faster sync (Layer 2)
    let kvStore = NSUbiquitousKeyValueStore.default
    kvStore.set(false, forKey: "device_\(currentDevice.deviceId)_isPrimary")
    kvStore.synchronize()

    // 7. Set local UserDefaults flag
    UserDefaults.standard.set(true, forKey: "device_\(currentDevice.deviceId)_wasDemoted")

    // 8. Signal to WalletManager to close wallet immediately
    NotificationCenter.default.post(name: .deviceDemotedFromPrimary, object: nil)

    print("✅ [DeviceRegistrationService] Device demoted - no primary device exists")
    
    // 9. Notify other devices that there's no primary
    NotificationCenter.default.post(name: .showNoPrimaryDeviceBanner, object: nil)
}

/// Step 2: Promote this device to primary (after another device was demoted)
func promoteThisDeviceToPrimary() async throws {
    // 1. Verify we are NOT currently primary
    guard let currentDevice = try await getCurrentDevice(),
          !currentDevice.isPrimaryDevice else {
        throw MigrationError.alreadyPrimary
    }

    // 2. Update current device to be primary
    currentDevice.isPrimaryDevice = true
    currentDevice.becamePrimaryAt = Date()

    // 3. Save to CloudKit
    try modelContext?.save()

    // 4. Update iCloud KV Store for faster sync (Layer 2)
    let kvStore = NSUbiquitousKeyValueStore.default
    kvStore.set(true, forKey: "device_\(currentDevice.deviceId)_isPrimary")
    kvStore.synchronize()

    // 5. Clear any demotion flags
    UserDefaults.standard.removeObject(forKey: "device_\(currentDevice.deviceId)_wasDemoted")

    // 6. Signal to WalletManager to initialize as primary
    NotificationCenter.default.post(name: .devicePromotedToPrimary, object: nil)

    print("✅ [DeviceRegistrationService] Device promoted to primary")
}

/// Check if there is no primary device (intermediate state during two-step migration)
func checkForNoPrimaryDevice() async throws -> Bool {
    guard let modelContext = modelContext else {
        throw DeviceRegistrationError.noModelContext
    }

    let descriptor = FetchDescriptor<DeviceRegistration>(
        predicate: #Predicate { $0.isPrimaryDevice == true && $0.isActive == true }
    )

    let primaryDevices = try modelContext.fetch(descriptor)
    return primaryDevices.isEmpty
}
```

#### 2.2 WalletManager Integration

**WalletManager.swift**:
```swift
/// Close wallet gracefully for migration
/// Uses Swift ARC to deallocate resources since Bark FFI doesn't provide closeWallet()
func closeWalletForMigration() async {
    Self.logger.info("🔄 [WalletManager] Closing wallet for migration...")

    // 1. Stop all background services
    exitProgressionService?.stop()
    roundProgressionService?.stop()
    vtxoRefreshService?.stop()
    walletNotificationService?.stop()

    // 2. Give services 200ms to finish current operations
    try? await Task.sleep(for: .milliseconds(200))

    // 3. Cancel any remaining pending operations
    taskManager.cancelAll()

    // 4. Deallocate wallet to release file handles and resources
    // Swift's ARC will call deinit on BarkWalletFFI, which should clean up Rust resources
    wallet = nil

    // 5. Deallocate all wallet-dependent services
    transactionService = nil
    balanceService = nil
    addressService = nil
    walletOperationsService = nil
    exitProgressionService = nil
    roundProgressionService = nil
    vtxoRefreshService = nil
    lightningClaimService = nil
    onchainTransactionService = nil
    unifiedTransactionService = nil
    transactionLinkingService = nil
    relayRegistrationService = nil
    walletNotificationService = nil

    // 6. Clear state
    isInitialized = false

    // 7. Switch to read-only mode
    isReadOnlyMode = true

    Self.logger.info("✅ [WalletManager] Wallet closed for migration")
}

/// Observe migration notifications
private func observeMigrationNotifications() {
    NotificationCenter.default.addObserver(
        forName: .deviceDemotedFromPrimary,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        Task { @MainActor in
            await self?.closeWalletForMigration()
            // Don't auto-reinitialize - let MainView handle it based on state detection
        }
    }
}
```

**Update `initialize()` method to add demotion check and wallet restore:**

```swift
func initialize(forceReadOnly: Bool? = nil, caller: String = #function, file: String = #file, line: Int = #line) async {
    // ... existing initialization code ...

    // CRITICAL: Check demotion status BEFORE opening wallet
    if await shouldBlockWalletAccess() {
        Self.logger.warning("⚠️ [WalletManager] Device has been demoted - switching to read-only mode")
        isReadOnlyMode = true

        // Initialize in read-only mode instead
        await initializeReadOnlyMode()
        return
    }

    // CRITICAL: For primary devices, check if wallet backup needs to be restored
    // This happens when:
    // 1. Device becomes primary after migration
    // 2. No local wallet file exists yet
    // 3. Backup is available in iCloud
    if !isReadOnlyMode {
        await restoreWalletIfNeeded()
    }

    // ... rest of existing initialization ...
}

/// Restores wallet from iCloud backup if needed
/// Called when device becomes primary and has no local wallet state
private func restoreWalletIfNeeded() async {
    guard let wallet = wallet else { return }

    // Check if wallet file already exists locally
    let walletFileExists = await wallet.hasLocalWalletFile()

    if !walletFileExists {
        Self.logger.info("📥 [WalletManager] No local wallet file - checking for backup")

        let hasBackup = await wallet.hasBackupAvailable()
        if hasBackup {
            Self.logger.info("📦 [WalletManager] Backup found - restoring wallet state")

            let restored = await wallet.restoreWalletFromBackup()
            if restored {
                Self.logger.info("✅ [WalletManager] Wallet state restored from backup")
            } else {
                Self.logger.warning("⚠️ [WalletManager] Failed to restore wallet from backup")
            }
        } else {
            Self.logger.info("ℹ️ [WalletManager] No backup available - wallet will start fresh")
        }
    }
}
```

#### 2.3 UI Implementation (iOS)

**Extend LinkedDevicesView_iOS.swift (already exists at Arke/ArkeMobile/Views/Settings/LinkedDevicesView_iOS.swift):**

Current file has stubs for:
- `makeDevicePrimary(_ device: DeviceRegistration)` (line 50)
- Device rows with primary/secondary distinction

**Add new UI elements:**

```swift
// Add state variables for two-step migration
@State private var showDemoteSheet = false
@State private var showPromoteSheet = false
@State private var showEmergencySheet = false
@State private var noPrimaryDeviceDetected = false

// Add buttons based on device state
var body: some View {
    // ... existing code ...
    
    // Show "Make This Device Secondary" button if this is primary
    if currentDevice?.isPrimaryDevice == true {
        Button(action: { showDemoteSheet = true }) {
            Label("Make This Device Secondary", systemImage: "arrow.down.circle")
        }
    }
    
    // Show "Make This Device Primary" button if this is secondary
    if currentDevice?.isPrimaryDevice == false {
        Button(action: { showPromoteSheet = true }) {
            Label("Make This Device Primary", systemImage: "arrow.up.circle")
        }
    }
    
    // Show banner if no primary device exists
    if noPrimaryDeviceDetected {
        GroupBox {
            Label("No active wallet - make this device your primary wallet to send and receive",
                  systemImage: "exclamationmark.triangle")
                .font(.subheadline)
        }
        .padding()
    }
}
```

**New file: DeviceMigrationSheets_iOS.swift:**

```swift
import SwiftUI

/// Step 1: Demote this device from primary
struct DemoteDeviceSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.deviceRegistrationService) private var deviceService
    @State private var isProcessing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                // Title
                Text("Make This Device Secondary?")
                    .font(.title2.bold())

                // Explanation
                Text("This device will switch to view-only mode. Make sure you have your other device ready to make it primary.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                // Info box
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("After confirming:", systemImage: "info.circle")
                            .font(.headline)
                        Text("1. This device becomes view-only")
                        Text("2. Open your other device")
                        Text("3. Make that device primary")
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Error message
                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Buttons
                VStack(spacing: 12) {
                    Button(action: performDemotion) {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Make Secondary")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing)

                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("Switch to Secondary")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func performDemotion() {
        Task {
            isProcessing = true
            error = nil

            do {
                try await deviceService.demoteThisDevice()

                // Success - dismiss sheet
                await MainActor.run {
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}

/// Step 2: Promote this device to primary
struct PromoteDeviceSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.deviceRegistrationService) private var deviceService
    @State private var isProcessing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)

                // Title
                Text("Make This Device Primary?")
                    .font(.title2.bold())

                // Explanation
                Text("This device will become your active wallet, able to send and receive payments.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer()

                // Error message
                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Buttons
                VStack(spacing: 12) {
                    Button(action: performPromotion) {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Make Primary")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing)

                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("Switch to Primary")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func performPromotion() {
        Task {
            isProcessing = true
            error = nil

            do {
                try await deviceService.promoteThisDeviceToPrimary()

                // Success - dismiss sheet
                await MainActor.run {
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}
```

---

### Phase 3: Emergency Takeover (Path 2)

**Goal**: Implement the risky migration path with heavy warnings.

#### 3.1 Service Layer

Already shown above in "Emergency Takeover Sync Flow" section.

#### 3.2 Detection on Old Primary

Already shown above in "Startup Check Flow" section.

**Integrate with MainView_iOS.swift:**

Update the existing `handleUbiquitousStoreChange()` method (line 239):

```swift
private func handleUbiquitousStoreChange(_ notification: Notification) async {
    guard let userInfo = notification.userInfo else { return }

    Self.logger.debug("handleUbiquitousStoreChange called")

    // ... existing change reason logging ...

    // Check if migration-related keys changed
    if let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
        let ubiquitousHashKey = "com.arke.wallet.mnemonicHash"

        // Check for device primary status changes
        let deviceId = try? serviceContainer.deviceRegistrationService.getOrCreateDeviceId()
        if let deviceId = deviceId,
           changedKeys.contains("device_\(deviceId)_isPrimary") {

            let kvStore = NSUbiquitousKeyValueStore.default
            let isPrimary = kvStore.bool(forKey: "device_\(deviceId)_isPrimary")

            if !isPrimary && kvStore.object(forKey: "device_\(deviceId)_isPrimary") != nil {
                Self.logger.warning("⚠️ Device has been demoted from primary")

                // Set local UserDefaults flag
                UserDefaults.standard.set(true, forKey: "device_\(deviceId)_wasDemoted")

                // Trigger wallet closure if currently running
                NotificationCenter.default.post(name: .deviceDemotedFromPrimary, object: nil)

                // Trigger re-initialization in read-only mode
                Task { @MainActor in
                    await walletManager.closeWalletForMigration()
                    await walletManager.initialize(forceReadOnly: true)
                }
            }
        }

        // ... existing hash change handling ...
    }
}
```

#### 3.3 UI Implementation (iOS)

**New file: EmergencyTakeoverSheet_iOS.swift:**

```swift
import SwiftUI

struct EmergencyTakeoverSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.deviceRegistrationService) private var deviceService
    @Environment(WalletManager.self) private var walletManager
    @State private var confirmationText = ""
    @State private var showFinalWarning = false
    @State private var isMigrating = false
    @State private var error: String?

    private let requiredConfirmation = "I UNDERSTAND"

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Warning icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)

                // Title
                Text("Recover Wallet to This Device?")
                    .font(.title2.bold())

                // Warning text
                VStack(alignment: .leading, spacing: 12) {
                    Label("Only proceed if your primary device is:",
                          systemImage: "exclamationmark.circle.fill")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        BulletPoint("Lost or stolen")
                        BulletPoint("Permanently broken")
                        BulletPoint("Factory reset and gone")
                        BulletPoint("Will never be turned on again")
                    }
                    .padding(.leading)

                    Divider()

                    Text("⚠️ If your primary device is just offline temporarily, **DO NOT** proceed.")
                        .font(.callout.bold())
                        .foregroundStyle(.red)

                    Text("If you proceed and later turn on your old device, **do not use it for at least 24-48 hours** to allow sync to complete.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)

                // Confirmation text field
                VStack(alignment: .leading, spacing: 8) {
                    Text("To proceed, type: **\(requiredConfirmation)**")
                        .font(.subheadline)

                    TextField("Type here", text: $confirmationText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                .padding(.horizontal)

                Spacer()

                // Error message
                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Buttons
                VStack(spacing: 12) {
                    Button(action: { showFinalWarning = true }) {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(confirmationText != requiredConfirmation)

                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("Emergency Takeover")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Final Confirmation", isPresented: $showFinalWarning) {
                Button("Cancel", role: .cancel) { }
                Button("Make This Device Primary", role: .destructive) {
                    performEmergencyTakeover()
                }
            } message: {
                Text("This device will become your primary wallet.\n\nYour old device will automatically switch to view-only mode when it comes online.\n\nNever use both devices for sending transactions simultaneously.")
            }
        }
    }

    private func performEmergencyTakeover() {
        Task {
            isMigrating = true
            error = nil

            do {
                try await deviceService.emergencyTakeoverAsPrimary()

                // Success - reinitialize as primary
                await MainActor.run {
                    isPresented = false
                }

                // Show persistent warning banner
                NotificationCenter.default.post(name: .showEmergencyTakeoverBanner, object: nil)

                // Reinitialize wallet as primary
                await walletManager.initialize()

            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isMigrating = false
                }
            }
        }
    }
}

struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
        .font(.subheadline)
    }
}
```

---

### Phase 4: Cooldown Period & Safety Features

#### 4.1 Cooldown Logic

**DeviceRegistrationService.swift**:
```swift
/// Check if primary device can be demoted (respects cooldown period)
func canDemotePrimaryDevice() async throws -> (canDemote: Bool, timeRemaining: TimeInterval?) {
    guard let primary = try await getPrimaryDevice() else {
        return (true, nil) // No primary found
    }

    guard let canBeDemotedAt = primary.canBeDemotedAt else {
        return (true, nil) // No cooldown set (old data)
    }

    let now = Date()
    if now >= canBeDemotedAt {
        return (true, nil) // Cooldown expired
    } else {
        let remaining = canBeDemotedAt.timeIntervalSince(now)
        return (false, remaining) // Still in cooldown
    }
}
```

#### 4.2 UI Integration

Show cooldown message in LinkedDevicesView_iOS:
```swift
if let timeRemaining = cooldownTimeRemaining {
    Text("Primary device was recently changed. Please wait \(formatTime(timeRemaining)) before switching again.")
        .font(.caption)
        .foregroundStyle(.orange)
}
```

---

### Phase 5: Persistent Warning Banners

#### 5.1 Emergency Takeover Banner

Show for 7 days after emergency takeover:

```swift
struct EmergencyTakeoverBanner: View {
    @Binding var isDismissed: Bool
    let showUntil: Date

    var body: some View {
        if Date() < showUntil && !isDismissed {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Device Recovery")
                        .font(.caption.bold())

                    Text("Do not use your old device for wallet operations")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { isDismissed = true }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
        }
    }
}
```

Store banner state in UserDefaults:
```swift
// When emergency takeover completes
UserDefaults.standard.set(Date().addingTimeInterval(7 * 24 * 60 * 60), forKey: "emergencyTakeoverBannerShowUntil")
```

---

## Testing Plan

### Test Scenarios

#### 1. Controlled Handoff - Happy Path
```
Setup: iPhone (primary) + iPad (secondary), both online
Steps:
1. Open iPhone → Settings → Linked Devices
2. Tap iPad → "Make iPad Primary"
3. Confirm migration
4. Verify iPhone backs up wallet to iCloud
5. Verify iPhone closes wallet and switches to read-only
6. Verify iPad detects promotion
7. Verify iPad restores wallet from iCloud backup
8. Verify iPad opens wallet with all VTXOs/history intact
Expected: Clean handoff, no errors, no data loss
```

#### 2. Controlled Handoff - Network Failure
```
Setup: iPhone (primary) + iPad (secondary)
Steps:
1. Start migration from iPhone
2. Disable network mid-migration
Expected: Migration completes locally, syncs when network returns
```

#### 3. Emergency Takeover - Lost Device
```
Setup: iPhone (primary, offline/lost) + iPad (secondary, online)
Steps:
1. Open iPad → Settings → Linked Devices
2. Tap "Make This Device Primary" (emergency)
3. Read warnings, type confirmation
4. Complete emergency takeover
Expected: iPad becomes primary immediately
```

#### 4. Emergency Takeover - Old Device Returns
```
Setup: iPad (new primary via emergency) + iPhone (old primary, comes back online)
Steps:
1. Turn on iPhone after emergency takeover
2. Open wallet app
Expected: Multi-layered check blocks wallet initialization, switches to read-only mode
```

#### 5. Race Condition - Simultaneous Launch
```
Setup: Migration just completed, both devices online
Steps:
1. Migrate iPad to primary
2. Immediately launch wallet on iPhone (< 5 seconds)
Expected: shouldBlockWalletAccess() catches stale state, refuses to open
```

#### 6. Cooldown Period
```
Setup: iPhone (primary)
Steps:
1. Migrate to iPad
2. Immediately try to migrate back to iPhone
Expected: Error message "Please wait X minutes"
```

#### 7. iCloud KV Store Sync
```
Setup: iPhone (primary) + iPad (secondary), both online
Steps:
1. Perform migration on iPhone
2. Monitor MainView_iOS.handleUbiquitousStoreChange() logs on iPad
3. Verify Layer 2 detection triggers within 10 seconds
Expected: iPad detects demotion via KV store before CloudKit
```

#### 8. Wallet Backup/Restore During Migration
```
Setup: iPhone (primary with VTXOs/history) + iPad (secondary, no local wallet file)
Steps:
1. Perform controlled handoff from iPhone to iPad
2. Check iCloud Drive for bark.sqlite backup
3. Verify backup timestamp is recent
4. On iPad, verify bark.sqlite was restored from iCloud
5. On iPad, open wallet and verify all VTXOs present
6. On iPad, check transaction history is complete
Expected: All wallet state preserved during migration
```

#### 9. Emergency Takeover with Stale Backup
```
Setup: iPhone (primary, offline) + iPad (secondary), last backup 2 days old
Steps:
1. Perform emergency takeover on iPad
2. Verify warning about potentially stale backup
3. Verify iPad restores from 2-day-old backup
4. Verify iPad syncs with ASP to catch up
5. Verify VTXOs are reconciled after sync
Expected: iPad catches up, possible minor data loss for offline period
```

---

## Error Handling

### Error Types
```swift
enum MigrationError: LocalizedError {
    case notPrimaryDevice
    case alreadyPrimary
    case invalidTargetDevice
    case noPrimaryDeviceFound
    case deviceNotFound
    case cooldownActive(remainingSeconds: TimeInterval)
    case cloudKitSyncTimeout
    case pendingOperationsExist(message: String)

    var errorDescription: String? {
        switch self {
        case .notPrimaryDevice:
            return "This device is not the primary device"
        case .alreadyPrimary:
            return "This device is already primary"
        case .invalidTargetDevice:
            return "Target device is invalid or already primary"
        case .noPrimaryDeviceFound:
            return "No primary device found in device list"
        case .deviceNotFound:
            return "Current device registration not found"
        case .cooldownActive(let seconds):
            return "Primary device was recently changed. Please wait \(Int(seconds / 60)) minutes."
        case .cloudKitSyncTimeout:
            return "CloudKit sync timed out. Please try again."
        case .pendingOperationsExist(let message):
            return message
        }
    }
}
```

---

## Performance Impact

### App Startup Performance

The multi-layered demotion check runs on **every app launch** but has minimal performance impact:

**Breakdown of checks:**
1. **UserDefaults read**: ~0.001ms (nanoseconds)
2. **NSUbiquitousKeyValueStore read**: ~1-5ms (local cache only, no network)
3. **CloudKit cache read**: ~1-2ms (local database query, no network)

**Total overhead: ~2-10ms** - completely imperceptible to users.

**Network calls**: None during the demotion check. CloudKit sync happens asynchronously in the background after the check completes.

### When Demotion is Detected

If a device has been demoted, the app:
1. Blocks wallet initialization immediately (before any file I/O)
2. Switches to read-only mode
3. No wasted work opening/closing wallet files

### iCloud KV Store Sync

- **Write on migration**: ~10-50ms to queue sync
- **Background sync**: Happens automatically, no app intervention needed (handled by MainView_iOS.swift:155-290)
- **Storage used**: <1KB per device (negligible vs 1MB limit)

**Conclusion**: The multi-layered approach adds virtually no overhead to normal app usage while significantly improving safety during emergency migrations.

---

## Open Questions & Future Enhancements

### Questions
1. **Cooldown duration**: 1 hour sufficient? Should it be configurable?
2. **Warning banner duration**: 7 days enough? Too long?
3. **Authentication**: Should migration require Face ID/Touch ID?

### Future Enhancements
1. **Migration history**: Track all migrations in database for audit trail
2. **Undo migration**: Allow quick rollback within first minute
3. **Scheduled migration**: "Switch primary at 9am tomorrow"
4. **Multi-device notification**: If push notifications are added in future
5. **Server-side coordination**: Require ASP to issue session token to primary (eliminates race conditions entirely)

---

## Implementation Checklist

### Phase 1: Data Model ⬜
- [ ] Add new properties to `DeviceRegistration` model
- [ ] Update `DeviceRegistration.init()` to include new parameters
- [ ] Add `MigrationType` enum
- [ ] Add migration errors to `MigrationError` enum
- [ ] Create notification names extension file
- [ ] Add `hasLocalWalletFile()` to BarkWalletProtocol
- [ ] Implement `hasLocalWalletFile()` in BarkWalletFFI
- [ ] Test CloudKit sync with new properties
- [ ] Verify WalletBackupService is accessible from DeviceRegistrationService

### Phase 2: Core Logic ⬜
- [ ] Implement `shouldBlockWalletAccess()` in WalletManager
- [ ] Implement `closeWalletForMigration()` in WalletManager
- [ ] Implement `restoreWalletIfNeeded()` in WalletManager
- [ ] Add migration check to `WalletManager.initialize()`
- [ ] Add backup restore check to `WalletManager.initialize()`
- [ ] Implement `observeMigrationNotifications()` in WalletManager
- [ ] Extend `MainView_iOS.handleUbiquitousStoreChange()` for migration keys
- [ ] Test multi-layered demotion detection
- [ ] Test wallet backup before controlled handoff
- [ ] Test wallet restore on new primary device
- [ ] Test emergency takeover with stale backup

### Phase 3: Controlled Handoff ⬜
- [ ] Implement `controlledHandoffToPrimary()` in DeviceRegistrationService
- [ ] Implement `getDeviceById()` helper method
- [ ] Create `ControlledHandoffSheet_iOS` UI
- [ ] Update `LinkedDevicesView_iOS.makeDevicePrimary()` method
- [ ] Test happy path with two devices
- [ ] Test error cases

### Phase 4: Emergency Takeover ⬜
- [ ] Implement `emergencyTakeoverAsPrimary()` in DeviceRegistrationService
- [ ] Create `EmergencyTakeoverSheet_iOS` UI
- [ ] Add runtime demotion detection to MainView_iOS
- [ ] Test emergency scenarios
- [ ] Test old device detection when it comes back online

### Phase 5: Cooldown & Safety ⬜
- [ ] Implement `canDemotePrimaryDevice()` cooldown logic
- [ ] Add cooldown UI to LinkedDevicesView_iOS
- [ ] Test cooldown enforcement

### Phase 6: Persistent Warnings ⬜
- [ ] Create `EmergencyTakeoverBanner` component
- [ ] Add banner to WalletView_iOS
- [ ] Persist banner state in UserDefaults
- [ ] Test banner dismissal and 7-day expiry

### Phase 7: macOS Implementation ⬜
- [ ] Check if MainView.swift (macOS) has NSUbiquitousKeyValueStore support
- [ ] Port iOS UI to macOS equivalents
- [ ] Test on macOS
- [ ] Test cross-platform migrations (iPhone ↔ Mac)

### Phase 8: Testing & Polish ⬜
- [ ] Write unit tests for migration logic
- [ ] Perform all test scenarios
- [ ] Add analytics/logging
- [ ] Document user-facing behavior
- [ ] Create help articles

---

## Related Documentation
- `LINKED_DEVICES_AND_VTXO_SYNC_ANALYSIS.md` - Overview of device system
- `Features/Read_Only_Mode.md` - Read-only mode + device role switching (✅ shipped; plan archived)
- `Device_Registry_Reference.md` - Device API reference

---

**Status**: Ready for implementation
**Next Step**: Begin Phase 1 (Data Model changes)
