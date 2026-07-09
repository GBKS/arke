# Read-Only Mode Implementation Plan

> **📦 Archived 2026-07-09.** Implementation shipped 2026-05-07. Current behavior is documented in [`../../Features/Read_Only_Mode.md`](../../Features/Read_Only_Mode.md); this plan is preserved for implementation history.

**Created:** 2026-05-07
**Status:** ✅ **COMPLETED** (Phase 1 & 2 Complete)
**Completed:** 2026-05-07
**Priority:** High (Enables multi-device support without wallet corruption)

---

## Implementation Summary

### Phase 1: Foundation ✅ COMPLETE
**Implemented:** 2026-05-07

#### 1.1 WalletManager Read-Only Mode Detection
- ✅ Added `isReadOnlyMode: Bool` property to WalletManager
- ✅ Added `checkReadOnlyMode()` method to detect primary vs secondary device
- ✅ Integrated device detection into initialization flow

#### 1.2 Split Initialization Paths
- ✅ Refactored `performInitialization()` to branch based on mode
- ✅ Created `initializePrimaryMode()` - full wallet with ASP connection
- ✅ Created `initializeReadOnlyMode()` - CloudKit sync only, no wallet file or ASP
- ✅ Read-only mode skips: BarkWalletFFI, ASP connection, all wallet-dependent services

#### 1.3 MainView Updates
- ✅ **iOS**: Modified `MainView_iOS.swift` to show WalletView in read-only mode
- ✅ **macOS**: Modified `MainView.swift` to show WalletView in read-only mode
- ✅ Removed blocking "Wallet Active Elsewhere" screen
- ✅ Updated `SecurityService.detectWalletState()` to check device registration for `.walletWithoutSeed` cases
- ✅ Activated ServiceContainer early to enable device registration checks

### Phase 2: UI Conditional Rendering ✅ COMPLETE
**Implemented:** 2026-05-07

#### 2.1 iOS Changes
**BalanceView_iOS:**
- ✅ Hidden Board/Offboard buttons (move funds between Ark/Onchain)
- ✅ Hidden refresh status widget
- ✅ Disabled pull-to-refresh
- ✅ Disabled sync/balance fetch in `.task`

**WalletView_iOS:**
- ✅ Hidden Send tab (removed from TabView)
- ✅ Receive tab visible (addresses work via CloudKit sync, Lightning invoice generation hidden)
- ✅ Hidden Data view navigation (shows message if accessed)
- ✅ Hidden Console view navigation (shows message if accessed)

**SettingsView_iOS:**
- ✅ Hidden Notifications toggle
- ✅ Hidden "Force Move to Savings" (Exit)
- ✅ Hidden "Delete Wallet"
- ✅ Hidden entire "Danger Zone" section
- ✅ Hidden "Fee Schedule"
- ✅ Hidden "X-Ray" (Data view)
- ✅ Hidden "Transaction Testing"
- ✅ Hidden entire "Behind the Curtain" section

#### 2.2 macOS Changes
**BalanceView:**
- ✅ Hidden Board/Offboard buttons
- ✅ Hidden refresh status widget
- ✅ Disabled pull-to-refresh

**WalletSidebar:**
- ✅ Hidden Send navigation item
- ✅ Receive navigation item visible (addresses work via CloudKit sync, Lightning invoice generation hidden)
- ✅ Hidden Data navigation item
- ✅ Hidden Console navigation item

### What Works in Read-Only Mode
✅ **Available Features:**
- Balance view (synced via CloudKit)
- Transaction history (Activity view)
- Receive addresses (synced via CloudKit)
- Contacts (view, edit, create)
- Tags (view, edit, create)
- Settings (display preferences, recovery phrase, linked devices)
- Help & Learning section

❌ **Hidden Features:**
- Send operations
- Lightning invoice generation (requires ASP)
- Board/Offboard (move funds)
- Manual refresh (ASP-dependent)
- Data/Console views (ASP-dependent)
- Notifications (requires ASP)
- Exit operations
- Delete wallet
- Developer/diagnostic tools

---

## Overview

Replace the current "Wallet Active Elsewhere" blocking screen with a **read-only mode** that allows secondary (non-primary) devices to view wallet data synced via CloudKit, while cleanly hiding features that require ASP connection and primary device access.

### Core Principle
**Features that require primary device access simply don't appear in the UI** - no disabled buttons, no tooltips, just a clean interface showing what's available.

---

## Current State (What We Just Built)

✅ Non-primary devices are completely blocked from accessing wallet
✅ `WalletState.walletActiveElsewhere` case added
✅ `SecurityService.detectWalletState()` checks `isPrimaryDevice`
✅ Shows "Wallet Active Elsewhere" full-screen blocking view

**Problem:** Too restrictive - users can't even view their transaction history on secondary devices.

---

## Target Architecture

### Phase 1: Core Read-Only Mode (Foundation) ✅ COMPLETE

#### 1.1 Add `isReadOnlyMode` to WalletManager ✅ COMPLETE
**Files:** `Shared/Data/WalletManager/WalletManager.swift`

- Add `@Published var isReadOnlyMode: Bool = false` property
- Determine mode during initialization based on `isPrimaryDevice` check
- Add `@Published var primaryDeviceName: String?` for UI display

**Logic:**
```swift
// During initialize()
let deviceService = ServiceContainer.shared.deviceRegistrationService
if let currentDevice = try? await deviceService.getCurrentDevice() {
    isReadOnlyMode = !currentDevice.isPrimaryDevice

    if isReadOnlyMode {
        // Get primary device name
        primaryDeviceName = try? await deviceService.getPrimaryDevice()?.deviceName
    }
}
```

#### 1.2 Modify WalletManager Initialization ✅ COMPLETE
**Files:** `Shared/Data/WalletManager/WalletManager.swift`

**Primary Device (Full Mode):**
- Initialize BarkWalletFFI
- Call `openWalletIfNeeded()`
- Connect to ASP
- Start all background services
- Enable sync, board operations, etc.

**Secondary Device (Read-Only Mode):**
- Skip BarkWalletFFI initialization entirely
- Skip ASP connection
- Only initialize services that work with CloudKit/SwiftData:
  - TagService (works)
  - ContactService (works)
  - TransactionAnnotationService (works)
- Skip or stub services that need ASP:
  - BoardService (skip)
  - AddressService (skip or stub)

**Implementation Approach:**
```swift
func initialize() async {
    // ... existing early detection ...

    // Check if primary device
    let isPrimary = await checkIfPrimaryDevice()
    isReadOnlyMode = !isPrimary

    if isPrimary {
        // Full initialization path
        await initializePrimaryMode()
    } else {
        // Read-only initialization path
        await initializeReadOnlyMode()
    }
}

private func initializePrimaryMode() async {
    // Current initialization logic
}

private func initializeReadOnlyMode() async {
    // Skip BarkWalletFFI
    // Only set up CloudKit-dependent services
    // Set isInitialized = true (for UI to show)
}
```

#### 1.3 Update MainView to Use Read-Only Mode ✅ COMPLETE
**Files:**
- `ArkeMobile/Views/MainView_iOS.swift`
- `ArkeDesktop/Views/MainView.swift`

**Remove:** `WalletActiveElsewhereView` blocking screen
**Keep:** `walletActiveElsewhere` state detection (for now)
**Change:** When `walletActiveElsewhere` is detected, still show `WalletView` but with `isReadOnlyMode = true`

```swift
// Instead of showing WalletActiveElsewhereView
// Just set the mode and show WalletView
if case .walletActiveElsewhere(let deviceName) = walletState {
    walletManager.isReadOnlyMode = true
    walletManager.primaryDeviceName = deviceName
    hasWallet = true  // Show wallet view
}
```

---

### Phase 2: UI Conditional Rendering ✅ COMPLETE

#### 2.1 Add Status Banner to WalletView ⏭️ SKIPPED (User Decision)
**Files:**
- `ArkeMobile/Views/WalletView_iOS.swift` (if exists, or BalanceView_iOS)
- `ArkeDesktop/Views/WalletView.swift`

**Banner Design:**
- Shows at top when `walletManager.isReadOnlyMode == true`
- Text: "Synced from [Primary Device Name]"
- Icon: Info/sync icon
- ~~Button: "Switch to This Device"~~ (Phase 3 - migration)
- Subtle, not intrusive (like iOS banner notifications)

**iOS Implementation:**
```swift
VStack(spacing: 0) {
    if walletManager.isReadOnlyMode {
        ReadOnlyBanner(primaryDeviceName: walletManager.primaryDeviceName ?? "Another Device")
    }

    // Rest of WalletView content
}
```

#### 2.2 Conditionally Hide Send/Receive in Balance View ✅ COMPLETE
**Files:**
- `ArkeMobile/Views/Balance/BalanceView_iOS.swift`
- `ArkeDesktop/Views/Balance/BalanceView.swift`

**Changes:**
- Wrap send button: `if !walletManager.isReadOnlyMode { /* Send button */ }`
- Wrap receive button: `if !walletManager.isReadOnlyMode { /* Receive button */ }`
- Keep refresh button, but modify behavior (Phase 2.4)

#### 2.3 Conditionally Hide Send/Receive in Sidebar/Navigation ✅ COMPLETE
**Files:**
- `ArkeDesktop/Views/WalletSidebar.swift`
- `ArkeMobile/Views/[navigation structure]`

**Changes:**
- Send tab/button: Only render if `!walletManager.isReadOnlyMode`
- Receive tab/button: Only render if `!walletManager.isReadOnlyMode`
- Keep: Balance, Activity, Contacts, Tags, Settings

**macOS Sidebar:**
```swift
List(selection: $selection) {
    Label("Balance", systemImage: "bitcoinsign.circle")
    Label("Activity", systemImage: "list.bullet")

    if !walletManager.isReadOnlyMode {
        Label("Send", systemImage: "arrow.up.circle")
        Label("Receive", systemImage: "arrow.down.circle")
    }

    // ... rest of sidebar
}
```

#### 2.4 Modify Refresh Behavior ✅ COMPLETE
**Files:**
- `ArkeMobile/Views/Balance/BalanceView_iOS.swift`
- `ArkeDesktop/Views/Balance/BalanceView.swift`

**Primary Device:**
- Refresh button triggers ASP sync
- Pull-to-refresh works normally

**Read-Only Device:**
- Refresh button shows "Last synced from [Device]" or is hidden
- Pull-to-refresh either disabled or shows CloudKit sync status
- Data updates automatically via CloudKit push notifications

#### 2.5 Hide Console and Data Tabs ✅ COMPLETE
**Files:**
- `ArkeDesktop/Views/WalletSidebar.swift`
- `ArkeMobile/Views/[navigation]`

**Rationale:** Console and Data tabs show technical information that may not be accurate/available without ASP connection.

**Implementation:**
```swift
if !walletManager.isReadOnlyMode {
    Label("Console", systemImage: "terminal")
    Label("Data", systemImage: "internaldrive")
}
```

**Alternative:** Show them but with limited/stale data disclaimer.

---

### Phase 3: Service Layer Adjustments ✅ COMPLETE

#### 3.1 Services to SKIP in Read-Only Mode
**These require ASP connection or active wallet operations:**

❌ **BarkWalletFFI** - No wallet initialization at all
❌ **BoardService** - Requires ASP connection for round monitoring
❌ **AddressService** - Needs BDK wallet to generate new addresses
❌ **Round Progression Monitoring** - Requires active ASP connection
❌ **Exit Services/Monitoring** - Can't initiate or track exits without wallet
❌ **Payment Operations** - No send/receive without active wallet
❌ **VTXO Refresh Logic** - Needs ASP to query current VTXO set
❌ **Mailbox Polling** - Requires ASP connection for incoming payments
❌ **Push Notification Relay Registration** - Only needed for active wallet

**Implementation:**
```swift
private func initializeReadOnlyMode() async {
    print("🔒 Initializing in read-only mode")

    // DO NOT call:
    // - openWalletIfNeeded()
    // - initializeBoardService()
    // - initializeAddressService()
    // - startExitMonitoring()
    // - registerForPushNotifications()
    // - Any ASP-dependent service

    // Only mark as initialized so UI shows
    isInitialized = true
    isReadOnlyMode = true

    print("✅ Read-only mode initialized (minimal services)")
}
```

#### 3.2 Services That Work in Read-Only Mode
**These only interact with SwiftData/CloudKit and work fully:**

✅ **TagService** - Pure CloudKit/SwiftData operations
✅ **ContactService** - Pure CloudKit/SwiftData operations
✅ **TransactionAnnotationService** - Pure CloudKit/SwiftData operations
✅ **DeviceRegistrationService** - Needed for device status checks
✅ **SecurityService** - Needed for device validation

**Note:** These are already initialized via ServiceContainer and work automatically.

#### 3.3 Data Availability in Read-Only Mode

**Available via CloudKit Sync:**
- ✅ Transaction history (`PersistentTransaction`)
- ✅ Balance snapshots (`ArkBalanceModel`, `OnchainBalanceModel`)
- ✅ Tags and assignments (`PersistentTag`, `TransactionTagAssignment`)
- ✅ Contacts and assignments (`PersistentContact`, `TransactionContactAssignment`)
- ✅ Address history (`PersistentAddress`)
- ✅ Device registrations (`DeviceRegistration`)

**NOT Available (requires ASP/wallet):**
- ❌ Live VTXO list
- ❌ Live UTXO list
- ❌ Current round state
- ❌ Exit status/progress
- ❌ ASP connection logs
- ❌ Real-time balance updates

**Implication:** Console and Data tabs must be hidden in read-only mode since their data doesn't exist.

---

### Phase 4: Testing & Edge Cases ⏭️ IN PROGRESS

#### 4.1 Initial Setup Testing
- [ ] Fresh install on Device A → becomes primary
- [ ] Open on Device B → enters read-only mode
- [ ] Verify CloudKit data appears on Device B
- [ ] Verify Send/Receive hidden on Device B

#### 4.2 Data Sync Testing
- [ ] Create transaction on Device A (primary)
- [ ] Verify appears on Device B (read-only) via CloudKit
- [ ] Add tag on Device B → syncs to Device A
- [ ] Add contact on Device B → syncs to Device A

#### 4.3 Mode Transition Testing (Future - Phase 5)
- [ ] Migrate from Device A to Device B
- [ ] Device B exits read-only mode
- [ ] Device A enters read-only mode
- [ ] Verify data consistency

#### 4.4 Edge Cases
- [ ] No primary device exists (all devices inactive)
- [ ] Primary device offline/deleted
- [ ] Multiple devices try to become primary simultaneously
- [ ] Network failure during mode check

---

## Phase 5: Migration Flow (BLOCKED - Future Work)

**Status:** ⚠️ **CANNOT IMPLEMENT YET**

**Blocker:** VTXO database cannot be transferred between devices. Migration would require:
1. Closing wallet on old primary
2. Copying VTXO state to new primary
3. Reopening wallet on new primary with same VTXO state

**Current Limitation:** No way to export/import VTXO database state.

**Workaround for Alpha:**
- Read-only mode is permanent once set
- To change primary device: Manually unlink/relink wallet (fresh start)
- Or: Accept potential VTXO desync issues (not recommended)

**Future Solution:**
- Implement VTXO state export/import in BarkWallet FFI
- Or: Server-side VTXO recovery endpoint
- Then: Enable "Switch to This Device" button

---

## Implementation Order

### Week 1: Foundation (Phase 1)
**Day 1-2:** WalletManager read-only mode flag and initialization paths
**Day 3-4:** MainView updates to show WalletView in read-only mode
**Day 5:** Testing and bug fixes

### Week 2: UI Updates (Phase 2)
**Day 1-2:** Status banner component (iOS + macOS)
**Day 3:** Conditional rendering in Balance views
**Day 4:** Conditional rendering in sidebar/navigation
**Day 5:** Refresh behavior and polish

### Week 3: Services & Testing (Phase 3-4)
**Day 1-2:** Service layer adjustments
**Day 3-4:** Integration testing
**Day 5:** Edge case handling and bug fixes

### Future: Migration (Phase 5)
**Blocked until:** VTXO export/import or server recovery available

---

## Success Criteria

✅ Secondary devices can view all wallet data (balance, transactions, contacts, tags)
✅ Secondary devices cannot send or receive (buttons hidden, not disabled)
✅ UI clearly indicates read-only status with banner
✅ No wallet corruption when opening on multiple devices
✅ CloudKit sync works bidirectionally for tags/contacts
✅ Clean, uncluttered UI (no disabled features with explanations)

---

## Design Decisions

### Q1: Balance Freshness Indicator
**Decision:** ✅ **Option C** - Trust CloudKit sync is recent enough (no indicator)
- Rationale: CloudKit push notifications keep data fresh
- Simpler UI without timestamp clutter
- If sync is slow, that's a CloudKit issue not a UI problem

### Q2: Settings Availability
**Decision:** ✅ **Option B** - Hide settings that only affect primary (network, server config)
- Keep: Display preferences, Bitcoin format, security settings (biometric)
- Hide: Network selection, server configuration (ASP-related)
- Linked Devices view: Keep (shows all devices and can view status)

### Q3: Pull-to-Refresh Behavior
**Decision:** ✅ **Option A** - Disable entirely in read-only mode
- Rationale: No manual refresh possible without ASP connection
- CloudKit sync is automatic via push notifications
- Clean UX - feature just doesn't exist if it can't work

### Q4: Console/Data Tabs
**Decision:** ✅ **Option A** - Hide completely in read-only mode
- Rationale: No data available without ASP/wallet connection
- Cleaner than showing empty states or stale data warnings
- Console: ASP logs don't exist
- Data: VTXOs/UTXOs/rounds don't exist

---

## Related Documentation

- [LINKED_DEVICES_AND_VTXO_SYNC_ANALYSIS.md](./LINKED_DEVICES_AND_VTXO_SYNC_ANALYSIS.md) - Original analysis
- [DEVICE_REGISTRY_ALL_PHASES_COMPLETE.md](./DEVICE_REGISTRY_ALL_PHASES_COMPLETE.md) - Device registration system
- DeviceRegistration model: `Shared/Models/DeviceRegistration.swift`
- WalletManager: `Shared/Data/WalletManager/WalletManager.swift`

---

## Implementation Notes

### What Was Actually Built (2026-05-07)

**Core Changes:**
1. **WalletManager** (`Shared/Data/WalletManager/WalletManager.swift`)
   - Added `isReadOnlyMode: Bool` property
   - Added `checkReadOnlyMode()` method
   - Split `performInitialization()` into `initializePrimaryMode()` and `initializeReadOnlyMode()`
   - Read-only mode bypasses all ASP-dependent initialization

2. **SecurityService** (`Shared/Services/SecurityService.swift`)
   - Updated `detectWalletState()` to check device registration for `.walletWithoutSeed` cases
   - Returns `.walletActiveElsewhere` for registered secondary devices

3. **MainView** (iOS & macOS)
   - Removed blocking "Wallet Active Elsewhere" screen
   - Shows WalletView in read-only mode with limited functionality
   - Activates ServiceContainer early to enable device registration

4. **UI Hiding** (iOS)
   - `BalanceView_iOS`: Hidden board/offboard, refresh controls
   - `WalletView_iOS`: Hidden Send tab, restored Receive tab (addresses work via CloudKit), hidden Data/Console navigation
   - `ReceiveView_iOS`: Hidden Lightning toggle button (Lightning invoice generation requires ASP)
   - `SettingsView_iOS`: Hidden Notifications, Danger Zone, Behind the Curtain sections

5. **UI Hiding** (macOS)
   - `BalanceView`: Hidden board/offboard, refresh controls
   - `WalletSidebar`: Hidden Send/Data/Console, restored Receive navigation (addresses work via CloudKit)
   - `ReceiveView`: Hidden Lightning balance type menu (Lightning invoice generation requires ASP)

6. **Address Service for Read-Only Mode** (New)
   - `AddressService.swift`: Added `ReadOnlyAddressService` class for secondary devices
   - `ReadOnlyAddressService`: Reads addresses from SwiftData (CloudKit-synced), cannot generate new ones
   - `WalletManager`: Added `readOnlyAddressService` property, updated `arkAddress` and `onchainAddress` computed properties
   - `WalletManager.initializeReadOnlyMode()`: Initializes ReadOnlyAddressService and loads addresses from database
   - Addresses synced from primary device via CloudKit are available on secondary devices

7. **Balance Service for Read-Only Mode** (2026-05-07 Polish)
   - `BalanceService.swift`: Added `ReadOnlyBalanceService` class for secondary devices
   - `ReadOnlyBalanceService`: Loads balances from SwiftData (CloudKit-synced), no wallet operations
   - `WalletManager`: Added `readOnlyBalanceService` property, updated balance computed properties to check `isReadOnlyMode`
   - `WalletManager.initializeReadOnlyMode()` and `setModelContext()`: Initialize and configure ReadOnlyBalanceService
   - Balances synced from primary device via CloudKit now display correctly in read-only mode

8. **ActivityView Polish** (2026-05-07)
   - `ActivityView_iOS`: Hidden faucet/test guide button in read-only mode
   - `ActivityView_iOS`: Disabled pull-to-refresh in read-only mode (prevents "walletNotInitialized" error)
   - Balance card now displays synced balance data from CloudKit in read-only mode

**Design Decisions:**
- ✅ No status banner (user preference - keep UI clean)
- ✅ Features simply don't appear (no disabled buttons with explanations)
- ✅ CloudKit push notifications handle data freshness (no manual refresh needed)
- ✅ Secondary devices have full read/write access to contacts and tags via CloudKit

**Known Limitations:**
- Migration between devices not supported (VTXO state transfer limitation)
- Balance data is snapshot from last primary device sync (not live)
- No way to force-refresh data on secondary device

---

## Original Planning Notes

- Migration is intentionally excluded from this plan due to VTXO state transfer limitations
- Focus is on making read-only mode as clean and functional as possible
- Once VTXO export/import is available, migration can be added as Phase 5
- Current blocker screen code should remain for easy rollback if needed
