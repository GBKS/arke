# Device Migration Implementation Plan

> ⚠️ **SUPERSEDED** (archived 2026-07-08): Replaced by [DEVICE_MIGRATION_IMPLEMENTATION_PLAN_REVISED.md](../DEVICE_MIGRATION_IMPLEMENTATION_PLAN_REVISED.md). Kept for historical context.

**Created:** 2026-05-08  
**Status:** Planning  
**Priority:** High (Critical for safe multi-device use)

---

## Executive Summary

This document outlines the implementation of **safe device migration** with two distinct paths:

1. **Controlled Handoff**: Safe migration when both devices are available
2. **Emergency Takeover**: Risky migration when primary device is lost/unavailable

The goal is to enable users to switch which device is their primary wallet device while minimizing the risk of database corruption from race conditions.

---

## The Problem

### Current State
- ✅ Basic `migrateToThisDevice()` API exists
- ✅ CloudKit syncs `isPrimaryDevice` flag across devices
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

## Solution: Two Migration Paths

### Path 1: Controlled Handoff (SAFE) ⭐
**When to use**: Both devices are available and online

**Key safety feature**: Current primary device initiates and closes wallet BEFORE new primary opens it.

**Flow**:
```
iPhone (current primary) → Settings → Linked Devices
  ↓
Select "iPad" → "Make iPad Primary"
  ↓
Confirmation dialog (low-friction, no scary warnings)
  ↓
iPhone:
  1. Updates CloudKit (iPhone.isPrimaryDevice = false, iPad.isPrimaryDevice = true)
  2. Waits for CloudKit confirmation
  3. CLOSES wallet immediately
  4. Switches to read-only mode
  ↓
iPad:
  1. Detects isPrimaryDevice = true via CloudKit sync
  2. Opens wallet
  3. Switches to primary mode
  ↓
Success! Very small race condition window.
```

### Path 2: Emergency Takeover (RISKY) ⚠️
**When to use**: Primary device is lost, stolen, broken, or permanently unavailable

**Key risk**: Old primary device might open wallet before receiving CloudKit update.

**Flow**:
```
iPad (current secondary) → Settings → Linked Devices
  ↓
"Make This Device Primary" button
  ↓
Warning dialog #1: "Only do this if iPhone is permanently gone"
  ↓
Type confirmation: "I UNDERSTAND"
  ↓
Final warning dialog #2: "Small risk if iPhone comes back online"
  ↓
iPad:
  1. Updates CloudKit (iPad.isPrimaryDevice = true, iPhone.forciblyDemoted = true)
  2. Does NOT wait for confirmation (device might never come online)
  3. Opens wallet immediately
  4. Shows persistent warning banner for 7 days
  ↓
iPhone (when/if it comes online):
  1. Detects forciblyDemoted = true
  2. Shows full-screen blocker alert
  3. Refuses to open wallet until user acknowledges
  4. Switches to read-only mode
```

---

## Data Model Changes

### DeviceRegistration Model Extensions

```swift
// New properties for safe migration
var handoffInitiatedAt: Date?        // Set when controlled handoff starts
var handoffCompletedAt: Date?        // Set when handoff completes
var emergencyTakeover: Bool          // True if forced migration (Path 2)
var becamePrimaryAt: Date?           // When device became primary
var lastActiveAt: Date?              // Heartbeat for active primary detection
var pushToken: String?               // APNs device token for push notifications
```

**Note**: Several properties from earlier drafts were removed as redundant:
- `demotedAt` - Can be derived from state transitions
- `canBeDemotedAt` - Calculate on-demand as `becamePrimaryAt + 1 hour`
- `forciblyDemoted` - Redundant with `emergencyTakeover` flag on new primary

### Migration Type Enum

```swift
enum MigrationType {
    case controlledHandoff    // Path 1: Safe, both devices available
    case emergencyTakeover    // Path 2: Risky, old primary unavailable
}
```

### Local Storage (UserDefaults)

```swift
// Local flag set by push notification handler or explicit demotion
// Checked BEFORE CloudKit on app launch for fast detection
UserDefaults.standard.bool(forKey: "device_\(deviceId)_wasDemoted")
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

We use **four independent mechanisms** to detect demotion, checked in order of speed:

#### Layer 1: UserDefaults (Instant, Local-Only)
- **Speed**: <1ms
- **Reliability**: Survives app restarts, NOT factory resets
- Set by push notification handler or explicit demotion
- Checked first on every app launch

#### Layer 2: NSUbiquitousKeyValueStore (Fast, 1-10 seconds)
- **Speed**: 1-5ms to read, syncs in 1-10 seconds typically
- **Reliability**: Faster than CloudKit, but still eventual consistency
- Limited to 1MB total storage (fine for just isPrimary flags)
- Provides redundancy if push notifications fail

#### Layer 3: Push Notifications (Fast, but requires permissions)
- **Speed**: Typically 1-5 seconds delivery
- **Reliability**: Best-effort delivery, requires notification permissions
- New primary sends APNs push to old primary's device token
- Push received even when app is closed/backgrounded
- Sets UserDefaults flag when received

#### Layer 4: CloudKit (Slow, but most reliable long-term)
- **Speed**: Seconds to minutes
- **Reliability**: Eventually consistent, persists indefinitely
- Full device registration records with all metadata
- Final source of truth for device state

### Startup Check Flow

```swift
func shouldBlockWalletAccess() async -> Bool {
    let deviceId = getCurrentDeviceId()
    
    // Layer 1: Check local UserDefaults (instant)
    if UserDefaults.standard.bool(forKey: "device_\(deviceId)_wasDemoted") {
        return true
    }
    
    // Layer 2: Check iCloud KV store (fast, local cache)
    let kvStore = NSUbiquitousKeyValueStore.default
    if !kvStore.bool(forKey: "device_\(deviceId)_isPrimary") {
        return true
    }
    
    // Layer 3: Check CloudKit local cache (no network call)
    if let device = getCurrentDeviceFromLocalCache(),
       !device.isPrimaryDevice {
        return true
    }
    
    // All checks passed - allow wallet access
    // CloudKit sync happens asynchronously in background
    return false
}
```

**Performance Impact**: Total startup delay is ~1-5ms (all local checks, no network calls)

### Emergency Takeover Notification Flow

```swift
// On new primary (iPad)
func emergencyTakeoverAsPrimary() async throws {
    // ... existing CloudKit updates ...
    
    // Send push notification to old primary
    if let oldPrimaryToken = oldPrimary.pushToken {
        try await sendDemotionPush(to: oldPrimaryToken, payload: [
            "type": "device_demoted",
            "deviceId": oldPrimary.deviceId,
            "timestamp": Date().timeIntervalSince1970
        ])
    }
    
    // Update iCloud KV store for faster sync
    let kvStore = NSUbiquitousKeyValueStore.default
    kvStore.set(false, forKey: "device_\(oldPrimary.deviceId)_isPrimary")
    kvStore.set(true, forKey: "device_\(currentDevice.deviceId)_isPrimary")
    kvStore.synchronize()
}

// On old primary (iPhone) - push notification handler
func handleDemotionPush(userInfo: [AnyHashable: Any]) {
    guard let deviceId = userInfo["deviceId"] as? String else { return }
    
    // Set local flag immediately
    UserDefaults.standard.set(true, forKey: "device_\(deviceId)_wasDemoted")
    
    // If app is running, close wallet immediately
    NotificationCenter.default.post(name: .deviceDemotedFromPrimary, object: nil)
}
```

### Known Limitations

⚠️ **There is no 100% foolproof solution** without a centralized coordination server. Edge cases remain:

1. **Extended offline period**: Device offline for weeks won't receive any updates
2. **Notification permissions denied**: Layer 3 protection unavailable
3. **Factory reset**: UserDefaults flag lost (but CloudKit will eventually sync)
4. **Network failure during emergency**: All sync mechanisms delayed

**Mitigation**: Heavy warnings in emergency takeover UI, instructing users not to use old device for 24-48 hours.

---

## Implementation Phases

### Phase 1: Data Model & Core Logic ✅ (Already Partially Complete)

**What exists**:
- ✅ `DeviceRegistration.isPrimaryDevice` flag
- ✅ Basic `migrateToThisDevice()` method
- ✅ CloudKit sync of device registrations

**What needs to be added**:
1. Add new properties to `DeviceRegistration` model (`handoffInitiatedAt`, `handoffCompletedAt`, `emergencyTakeover`, `becamePrimaryAt`, `lastActiveAt`, `pushToken`)
2. Add `controlledHandoffToPrimary(targetDeviceId:)` method
3. Add `emergencyTakeoverAsPrimary()` method with push notification and iCloud KV store updates
4. Add `sendDemotionPush(to:payload:)` helper method
5. Add `shouldBlockWalletAccess()` multi-layered check in WalletManager
6. Add `closeWalletForMigration()` method in WalletManager
7. Add push notification handler for device demotion
8. Register device for push notifications and store token in CloudKit

**Files to modify**:
- `Shared/Models/DeviceRegistration.swift`
- `Shared/Services/DeviceRegistrationService.swift`
- `Shared/Data/WalletManager/WalletManager.swift`
- App delegate or main app file (for push notification registration and handling)

---

### Phase 2: Safe Controlled Handoff (Path 1)

**Goal**: Implement the safe migration path where current primary initiates handoff.

#### 2.1 Service Layer

**DeviceRegistrationService.swift**:
```swift
/// Safe handoff from current primary to another device
func controlledHandoffToPrimary(targetDeviceId: String) async throws {
    // 1. Verify we are currently primary
    guard try await isCurrentDevicePrimary() else {
        throw MigrationError.notPrimaryDevice
    }
    
    // 2. Verify target device exists and is secondary
    guard let targetDevice = try await getDevice(byId: targetDeviceId),
          !targetDevice.isPrimaryDevice else {
        throw MigrationError.invalidTargetDevice
    }
    
    // 3. Update CloudKit
    guard let currentDevice = try await getCurrentDevice() else {
        throw MigrationError.deviceNotFound
    }
    
    // Mark handoff in progress
    currentDevice.handoffInitiatedAt = Date()
    targetDevice.isPrimaryDevice = true
    targetDevice.becamePrimaryAt = Date()
    targetDevice.canBeDemotedAt = Date().addingTimeInterval(3600) // 1 hour cooldown
    
    try modelContext?.save()
    
    // 4. Wait for CloudKit confirmation (timeout 30 seconds)
    try await waitForCloudKitSync(timeout: 30)
    
    // 5. Now safe to update local device
    currentDevice.isPrimaryDevice = false
    currentDevice.demotedAt = Date()
    currentDevice.handoffCompletedAt = Date()
    
    try modelContext?.save()
    
    // 6. Signal to WalletManager to close wallet
    NotificationCenter.default.post(name: .deviceDemotedFromPrimary, object: nil)
}
```

#### 2.2 WalletManager Integration

**WalletManager.swift**:
```swift
/// Close wallet gracefully for migration
func closeWalletForMigration() async {
    print("🔄 [WalletManager] Closing wallet for migration...")
    
    // 1. Stop all background services
    exitProgressionService?.stop()
    roundProgressionService?.stop()
    vtxoRefreshService?.stop()
    walletNotificationService?.stop()
    
    // 2. Cancel pending operations
    taskManager.cancelAll()
    
    // 3. Close wallet file
    if let ffiWallet = wallet as? BarkWalletFFI {
        await ffiWallet.closeWallet()
    }
    
    // 4. Clear state
    isInitialized = false
    
    // 5. Switch to read-only mode
    isReadOnlyMode = true
    
    print("✅ [WalletManager] Wallet closed for migration")
}

/// Observe migration notifications
private func observeMigrationNotifications() {
    NotificationCenter.default.addObserver(
        forName: .deviceDemotedFromPrimary,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        Task {
            await self?.closeWalletForMigration()
            await self?.reinitialize() // Will initialize as read-only
        }
    }
}
```

#### 2.3 UI Implementation (iOS)

**LinkedDevicesView_iOS.swift**:
- Show list of devices with clear "Primary" indicator
- For secondary devices, show "Make Primary" button
- Tapping opens confirmation sheet

**New file: DeviceMigrationSheet_iOS.swift**:
```swift
struct ControlledHandoffSheet: View {
    let targetDevice: DeviceRegistration
    @Binding var isPresented: Bool
    @Environment(\.serviceContainer) var services
    @State private var isMigrating = false
    @State private var error: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Icon/illustration
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                
                // Title
                Text("Switch Primary Device?")
                    .font(.title2.bold())
                
                // Explanation
                Text("\(targetDevice.deviceName) will become your active wallet device. This device will switch to view-only mode.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                // Info box
                GroupBox {
                    Label("Both devices will remain linked and synced", 
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
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
                    Button(action: performMigration) {
                        if isMigrating {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Switch to \(targetDevice.deviceName)")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isMigrating)
                    
                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("Switch Primary Device")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func performMigration() {
        Task {
            isMigrating = true
            error = nil
            
            do {
                try await services.deviceRegistrationService
                    .controlledHandoffToPrimary(targetDeviceId: targetDevice.deviceId)
                
                // Success - dismiss sheet
                await MainActor.run {
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isMigrating = false
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

**DeviceRegistrationService.swift**:
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
    
    currentDevice.isPrimaryDevice = true
    currentDevice.becamePrimaryAt = Date()
    currentDevice.emergencyTakeover = true
    
    try modelContext?.save()
    
    // 4. Send push notification to old primary (Layer 3 protection)
    if let oldPrimaryToken = oldPrimary.pushToken {
        try? await sendDemotionPush(
            to: oldPrimaryToken,
            payload: [
                "type": "device_demoted",
                "deviceId": oldPrimary.deviceId,
                "timestamp": Date().timeIntervalSince1970
            ]
        )
    }
    
    // 5. Update iCloud KV store for faster sync (Layer 2 protection)
    let kvStore = NSUbiquitousKeyValueStore.default
    kvStore.set(false, forKey: "device_\(oldPrimary.deviceId)_isPrimary")
    kvStore.set(true, forKey: "device_\(currentDevice.deviceId)_isPrimary")
    kvStore.synchronize()
    
    // 6. Don't wait for sync - proceed immediately
    // Old primary will detect demotion via push/KV store/CloudKit when it comes online
}

/// Send APNs push notification for demotion
private func sendDemotionPush(to deviceToken: String, payload: [String: Any]) async throws {
    // Implementation depends on your APNs setup
    // Could use URLSession to call your backend, or a service like Firebase
    // This is a best-effort notification - don't throw if it fails
}
```

#### 3.2 Detection on Old Primary

**WalletManager.swift** - Check BEFORE initializing wallet:
```swift
/// Multi-layered check if device has been demoted
/// This runs BEFORE wallet initialization to prevent race conditions
func shouldBlockWalletAccess() async -> Bool {
    let deviceId = getCurrentDeviceId()
    
    // Layer 1: Check local UserDefaults (instant, <1ms)
    // Set by push notification handler or explicit demotion
    if UserDefaults.standard.bool(forKey: "device_\(deviceId)_wasDemoted") {
        print("🛑 [WalletManager] Blocked: UserDefaults indicates demotion")
        return true
    }
    
    // Layer 2: Check iCloud KV store (fast, ~1-5ms, local cache)
    let kvStore = NSUbiquitousKeyValueStore.default
    let isPrimaryInKVStore = kvStore.bool(forKey: "device_\(deviceId)_isPrimary")
    if !isPrimaryInKVStore && kvStore.object(forKey: "device_\(deviceId)_isPrimary") != nil {
        print("🛑 [WalletManager] Blocked: iCloud KV store indicates demotion")
        return true
    }
    
    // Layer 3: Check CloudKit local cache (no network call)
    if let device = try? await deviceService.getCurrentDeviceFromCache(),
       !device.isPrimaryDevice {
        print("🛑 [WalletManager] Blocked: CloudKit cache indicates demotion")
        return true
    }
    
    // All checks passed - allow wallet access
    return false
}

/// Initialize wallet with demotion check
func initialize() async throws {
    // CRITICAL: Check demotion status BEFORE opening wallet
    if await shouldBlockWalletAccess() {
        print("⚠️ [WalletManager] Device has been demoted - switching to read-only mode")
        isReadOnlyMode = true
        
        // Show informational banner (non-blocking)
        NotificationCenter.default.post(name: .deviceWasDemoted, object: nil)
        
        return // Don't initialize wallet for write access
    }
    
    // Safe to proceed with normal initialization
    // ... existing initialization code ...
}
```

**Push Notification Handler** (AppDelegate/App):
```swift
/// Handle remote notification for device demotion
func handleDemotionPush(userInfo: [AnyHashable: Any]) {
    guard let deviceId = userInfo["deviceId"] as? String else { return }
    
    print("📱 [Push] Received demotion notification for device \(deviceId)")
    
    // Set local flag immediately (Layer 1 protection)
    UserDefaults.standard.set(true, forKey: "device_\(deviceId)_wasDemoted")
    
    // If wallet is currently open, close it immediately
    NotificationCenter.default.post(name: .deviceDemotedFromPrimary, object: nil)
}
```

#### 3.3 UI Implementation (iOS)

**New file: EmergencyTakeoverSheet_iOS.swift**:
```swift
struct EmergencyTakeoverSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.serviceContainer) var services
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
                    
                    Text("If you proceed and later turn on your old device, **do not use it for at least 24-48 hours** to allow sync to complete. The app will automatically prevent wallet access if it receives the demotion notification.")
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
                Text("This device will become your primary wallet.\n\nYour old device will receive a push notification and automatically switch to view-only mode when it comes online. Multiple layers of protection are in place, but **do not use your old device for 24-48 hours** to ensure sync completes.\n\nNever use both devices for sending transactions simultaneously.")
            }
        }
    }
    
    private func performEmergencyTakeover() {
        Task {
            isMigrating = true
            error = nil
            
            do {
                try await services.deviceRegistrationService.emergencyTakeoverAsPrimary()
                
                // Success - reinitialize as primary
                await MainActor.run {
                    isPresented = false
                }
                
                // Show persistent warning banner
                NotificationCenter.default.post(name: .showEmergencyTakeoverBanner, object: nil)
                
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

**New file: DeviceDemotedBanner_iOS.swift** (Optional - informational only):
```swift
/// Non-blocking banner shown when device detects it was demoted
/// The actual safety is provided by shouldBlockWalletAccess() check BEFORE wallet initialization
struct DeviceDemotedBanner: View {
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device Mode Changed")
                        .font(.headline)
                    
                    Text("Another device is now the primary wallet. This device is in view-only mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: { isVisible = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}
```

**Note**: The banner is informational only. The real protection happens in `WalletManager.shouldBlockWalletAccess()` which prevents wallet initialization before any UI is shown.

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

Show cooldown message in linked devices view:
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
    let dismissDate: Date
    @Binding var isDismissed: Bool
    
    var body: some View {
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
4. Verify iPhone closes wallet and switches to read-only
5. Verify iPad opens wallet and becomes primary
Expected: Clean handoff, no errors
```

#### 2. Controlled Handoff - Network Failure
```
Setup: iPhone (primary) + iPad (secondary)
Steps:
1. Start migration from iPhone
2. Disable network mid-migration
Expected: Migration fails gracefully, iPhone stays primary
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
Expected: Multi-layered check blocks wallet initialization, app switches to read-only mode, optional banner shown
```

#### 5. Race Condition - Simultaneous Launch
```
Setup: Migration just completed, both devices online
Steps:
1. Migrate iPad to primary
2. Immediately launch wallet on iPhone (< 5 seconds)
Expected: Pre-flight check catches stale state, refuses to open
```

#### 6. Cooldown Period
```
Setup: iPhone (primary)
Steps:
1. Migrate to iPad
2. Immediately try to migrate back to iPhone
Expected: Error message "Please wait X minutes"
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
    case walletOpenFailure
    
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
        case .walletOpenFailure:
            return "Failed to open wallet on new primary device"
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
3. Shows optional informational banner
4. No wasted work opening/closing wallet files

### Push Notification Overhead

- **Registration**: One-time APNs token registration on first launch
- **Receiving**: Push handled by system, ~0ms app overhead
- **Processing**: Sets UserDefaults flag in <1ms

### iCloud KV Store Sync

- **Write on migration**: ~10-50ms to queue sync
- **Background sync**: Happens automatically, no app intervention needed
- **Storage used**: <1KB per device (negligible vs 1MB limit)

**Conclusion**: The multi-layered approach adds virtually no overhead to normal app usage while significantly improving safety during emergency migrations.

---

## Open Questions & Future Enhancements

### Questions
1. **Cooldown duration**: 1 hour sufficient? Should it be configurable?
2. **Warning banner duration**: 7 days enough? Too long?
3. **Authentication**: Should migration require Face ID/Touch ID?
4. **Pending operations**: How to handle active exits/sends during migration?

### Future Enhancements
1. **Migration history**: Track all migrations in database for audit trail
2. **Undo migration**: Allow quick rollback within first minute
3. **Scheduled migration**: "Switch primary at 9am tomorrow"
4. **Multi-device notification**: Push notification to all devices when primary changes
5. **Server-side session tokens**: Require ASP to issue session token to primary

---

## Implementation Checklist

### Phase 1: Data Model ⬜
- [ ] Add new properties to `DeviceRegistration` model
- [ ] Add `MigrationType` enum
- [ ] Add migration-related errors to `MigrationError`
- [ ] Update CloudKit schema if needed

### Phase 2: Controlled Handoff ⬜
- [ ] Implement `controlledHandoffToPrimary()` in DeviceRegistrationService
- [ ] Implement `closeWalletForMigration()` in WalletManager
- [ ] Add migration notifications
- [ ] Create `ControlledHandoffSheet_iOS` UI
- [ ] Integrate into `LinkedDevicesView_iOS`
- [ ] Test happy path
- [ ] Test error cases

### Phase 3: Emergency Takeover ⬜
- [ ] Implement `emergencyTakeoverAsPrimary()` in DeviceRegistrationService
- [ ] Implement `checkForciblyDemoted()` detection
- [ ] Create `EmergencyTakeoverSheet_iOS` UI
- [ ] Create `ForciblyDemotedAlert_iOS` UI
- [ ] Integrate warnings into main flow
- [ ] Test emergency scenarios

### Phase 4: Cooldown & Safety ⬜
- [ ] Implement cooldown logic
- [ ] Add cooldown UI
- [ ] Test cooldown enforcement

### Phase 5: Persistent Warnings ⬜
- [ ] Create `EmergencyTakeoverBanner` component
- [ ] Add banner to main view
- [ ] Persist banner state
- [ ] Test banner dismissal

### Phase 6: macOS Implementation ⬜
- [ ] Port iOS UI to macOS
- [ ] Test on macOS
- [ ] Test cross-platform migrations (iPhone ↔ Mac)

### Phase 7: Testing & Polish ⬜
- [ ] Write unit tests for migration logic
- [ ] Perform all test scenarios
- [ ] Add analytics/logging
- [ ] Document user-facing behavior
- [ ] Create help articles

---

## Related Documentation
- `LINKED_DEVICES_AND_VTXO_SYNC_ANALYSIS.md` - Overview of device system
- `READ_ONLY_MODE_IMPLEMENTATION_PLAN.md` - Read-only mode details
- `DEVICE_REGISTRY_QUICK_REFERENCE.md` - Device API reference

---

**Status**: Ready for implementation  
**Next Step**: Begin Phase 1 (Data Model changes)
