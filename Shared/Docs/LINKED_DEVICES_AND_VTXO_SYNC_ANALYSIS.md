# Linked Devices & VTXO Synchronization Architecture Analysis

**Original Date**: 2026-05-06  
**Updated**: 2026-05-08  
**Status**: ✅ **IMPLEMENTATION COMPLETE**  
**Context**: Analysis of device linking and implementation of single active device model  

---

## What Changed (2026-05-08 Update)

This document has been updated to reflect the **completed implementation** of the single active device model with read-only mode:

**Implementation Complete**:
- ✅ Primary/secondary device model fully working
- ✅ Secondary devices operate in read-only mode (no wallet file opened)
- ✅ Only primary device connects to Ark server
- ✅ CloudKit syncs metadata (transactions, contacts, tags, balances) to all devices
- ✅ UI conditionally hides wallet operations on secondary devices
- ✅ Device migration working via Settings → Linked Devices

**Key Files Implemented**:
- `WalletManager.swift`: `initializePrimaryMode()` vs `initializeReadOnlyMode()`
- `ReadOnlyBalanceService.swift` and `ReadOnlyAddressService.swift`
- UI conditional rendering in `BalanceView`, `WalletView`, `SettingsView`

**Result**: Users can safely open the app on multiple devices without risk of database corruption. Secondary devices show synced data in a clean, read-only interface.

---

## Executive Summary

**✅ IMPLEMENTATION COMPLETE (2026-05-07)**: The single active device model is now fully implemented. Secondary devices operate in read-only mode, displaying CloudKit-synced data without opening the wallet or connecting to the Ark server.

---

Arké has a **production-ready linked devices system** with full primary/secondary device support:

1. **Primary device**: Full wallet access with ASP connection
2. **Secondary devices**: Read-only access via CloudKit sync
3. **Clean separation**: Secondary devices never open the Bark wallet or connect to ASP
4. **Migration support**: Users can switch which device is primary

**🎯 ARCHITECTURAL SOLUTION**: Only ONE device (the primary) connects to the Ark server at a time. Secondary devices display synced metadata (transactions, contacts, tags, balances, addresses) without wallet operations. This prevents database divergence while enabling seamless multi-device viewing.

**Previous Critical Issue (Now Resolved)**: Two devices syncing independently with the Ark server would cause database divergence and inconsistency. The current implementation prevents this by only allowing the primary device to open the wallet.

---

## 1. Current Linked Devices Architecture

### Core Components

**DeviceRegistration Model** (`Shared/Models/DeviceRegistration.swift`)
- Tracks all devices with wallet access
- Syncs via CloudKit for cross-device visibility
- **Key Properties**:
  - `deviceId`: Stable identifier (Keychain, `ThisDeviceOnly`)
  - `walletHash`: Links device to wallet via mnemonic hash
  - `hasSeed`: Boolean indicating if device has seed phrase
  - `platform`: iOS or macOS
  - `isActive`: Manual unlink flag
  - `lastSeenAt`: Heartbeat timestamp (30-day staleness threshold)

**Two Device Types** (Legacy - Now Obsolete with iCloud Keychain):
1. **Full Wallet Devices** (`hasSeed=true`)
   - Has seed phrase in local Keychain (now syncs via iCloud Keychain)
   - Can sign transactions independently
   - Can generate new addresses

2. **Metadata-Only Devices** (`hasSeed=false`)
   - ~~Can view wallet data via iCloud sync~~
   - ~~Cannot sign transactions alone~~
   - ~~Must link with primary device via QR code~~
   - **NOW OBSOLETE**: All devices get seed automatically via iCloud Keychain

**Note**: With iCloud Keychain sync enabled, the `hasSeed` flag tracks seed possession but `isPrimaryDevice` controls which device can actually use the wallet. Secondary devices have the seed (for recovery/migration) but cannot open the wallet file.

### Device Registration Flow (Current - Will Change)

```
User Creates Wallet (Device A)
  ↓
Device A auto-registers (hasSeed=true, isPrimaryDevice=true)
  ↓
Hash + Seed both sync to iCloud automatically
  ↓
User installs on Device B
  ↓
Device B detects hash AND gets seed via iCloud Keychain
  ↓
Device B auto-registers (hasSeed=true, isPrimaryDevice=false)
  ↓
User sees "Your wallet is available" (no QR scan needed!)
  ↓
Device B is secondary device (has seed but blocked from ASP sync)
```

**New Flow Benefits**:
- ✅ No QR code scanning required for seed transfer
- ✅ Seamless device addition
- ✅ Secondary devices can be promoted to primary if needed
- ⚠️ Must prevent secondary from independently syncing with ASP

### Heartbeat System

- 24-hour interval
- `updateHeartbeatIfNeeded()` keeps device fresh
- Prevents false "stale" detection
- Triggered on app launch and foreground
- Devices older than 30 days shown as potentially stale

---

## 2. Data Synchronization Model

### What Syncs via CloudKit ✅

**Metadata (Safe to Sync)**:
- Transaction metadata (notes, amounts, dates, timestamps)
- Tags (`PersistentTag`)
- Contacts (`PersistentContact`)
- Device registrations
- Balance cache (`ArkBalanceModel`, `OnchainBalanceModel`)
- Wallet configuration
- UI preferences

**Real-Time Sync Mechanism**:
- `CloudKitObserver` watches `NSPersistentStoreRemoteChange` notifications
- Posts custom `.cloudKitDataDidChange` notification
- Services (TagService, ContactService) observe and reload
- SwiftUI views update automatically via `@Query` and `@Observable`

### What Does NOT Sync ❌

**Sensitive Data**:
- ~~Private keys~~ (derived from seed, so effectively sync via seed sync)
- ~~Seed phrases~~ ✅ **NOW SYNCS via iCloud Keychain** (as of today's change)
- Device IDs (Keychain `ThisDeviceOnly`, never syncs)

**Note**: With seed phrases syncing, all devices can derive the same private keys, meaning they all have full signing capability. This is why blocking secondary devices from syncing with ASP is critical - they have the cryptographic capability but shouldn't use it.

**Critical Gap: VTXO Data**:
- VTXOs stored in Bark wallet (Rust FFI)
- Retrieved via `sync()` from ASP (Ark Service Provider)
- **NO persistence to iCloud/CloudKit**
- **NO cross-device synchronization**

---

## 3. The VTXO Synchronization Problem

### Current Behavior

```
Device A (iPhone, has seed + VTXOs)
  └─ VTXOs stored in Bark wallet (local only)

Device B (iPad, has seed via iCloud Keychain)
  └─ Can see transaction metadata via CloudKit
  └─ Must call sync() to fetch VTXOs from ASP
  └─ May get different VTXO state if ASP doesn't have full history
```

### The Critical Gap

When a user switches to a new device:
1. Seed phrase syncs automatically via iCloud Keychain ✅
2. Transaction metadata syncs via CloudKit ✅
3. **VTXOs must be re-synced from ASP server** ⚠️
4. Server doesn't currently provide full VTXO recovery ❌

### Why This Matters

- VTXOs represent **actual spendable funds**
- If ASP doesn't have complete history, funds may appear lost
- User must manually trigger sync on each device
- No way to "transfer" VTXO state between devices directly

### 🚨 THE CRITICAL CONSTRAINT: Database Consistency

**The fundamental problem that changes everything:**

If Device A and Device B both independently call `sync()` on the Ark server:
- Each device maintains its own local Bark wallet database
- Bark wallet tracks VTXO state, pending rounds, exits, etc.
- **These databases WILL diverge** if both devices sync independently
- Result: Inconsistent balances, missing transactions, corrupted state

**Example Failure Scenario:**
```
T0: Device A syncs → sees 5 VTXOs worth 100k sats
T1: Device A sends 50k sats → creates new VTXOs (40k + 10k)
T2: Device B syncs independently → still sees original 5 VTXOs (100k)
T3: Device B tries to spend → uses already-spent VTXOs → FAILURE
```

**This means:**
- ❌ Peer-to-peer multi-device is **architecturally impossible**
- ❌ Cannot have multiple devices independently sync with server
- ✅ **MUST** have hub-and-spoke with ONE primary device
- ✅ Secondary devices receive state from primary via iCloud

This is not a feature limitation - it's a **fundamental requirement** of the Ark protocol's client-side state management.

---

## 4. Hub-and-Spoke Pattern Analysis

### Is It Implemented? **✅ YES - FULLY IMPLEMENTED (2026-05-07)**

**✅ COMPLETED**:
- `isPrimaryDevice` flag added to `DeviceRegistration` model
- First device automatically becomes primary on registration
- Helper methods added: `getPrimaryDevice()`, `isCurrentDevicePrimary()`, `migrateToThisDevice()`
- CloudKit sync ready (property syncs across devices automatically)
- **Wallet initialization blocking**: Secondary devices never open BarkWalletFFI
- **Read-only mode**: `WalletManager.isReadOnlyMode` flag controls device behavior
- **Separate initialization paths**: `initializePrimaryMode()` vs `initializeReadOnlyMode()`
- **UI conditional rendering**: Send/receive/data/console hidden on secondary devices
- **No ASP connection on secondary devices**: Only primary device calls `sync()`

**Current Behavior (WORKING CORRECTLY)**:
```
User has iPhone (primary) + iPad (secondary), both with seed
iPhone: Opens wallet, syncs with ASP → local DB state X
iPad: Does NOT open wallet, never calls sync()
       Shows CloudKit-synced metadata (transactions, contacts, balances)
Result: Single source of truth, no database divergence
```

### Implementation Details

The hub-and-spoke architecture is now fully implemented:

**Required Design (Simplified - Single Active Device)**:
```
Primary Device (iPhone) - ONLY device with active wallet
  ├─ Has seed phrase (synced via iCloud Keychain)
  ├─ ONLY device allowed to open/sync wallet with ASP
  ├─ Maintains authoritative VTXO state
  ├─ Full wallet functionality
  └─ Can be migrated to another device

Secondary Devices (iPad, Mac) - WALLET CLOSED
  ├─ Have seed phrase (auto-synced via iCloud Keychain ✅)
  ├─ Seed available for emergency recovery/migration
  ├─ Can see transaction metadata via CloudKit (view-only)
  ├─ Show "Wallet is active on [Primary Device]"
  ├─ Button: "Switch to This Device" (makes this primary)
  └─ NEVER open Bark wallet or sync with ASP
```

**✅ IMPLEMENTED**: Secondary devices **don't open the wallet at all**. They show transaction history from CloudKit metadata, but the actual Bark wallet remains closed. This is similar to hardware wallet model - you can only use the wallet on one device at a time.

**How It Works**:
1. `WalletManager.checkReadOnlyMode()` checks `DeviceRegistration.isPrimaryDevice`
2. Primary device: `initializePrimaryMode()` → opens `BarkWalletFFI`, connects to ASP
3. Secondary device: `initializeReadOnlyMode()` → uses `ReadOnlyBalanceService` and `ReadOnlyAddressService`, loads from CloudKit
4. UI conditionally renders based on `walletManager.isReadOnlyMode` flag

**Note on Seed Sync**: As of the latest change, seed phrases now sync via iCloud Keychain automatically. This means:
- ✅ New devices get the seed automatically (no QR code scan needed!)
- ✅ Device registration happens automatically via CloudKit sync
- ✅ Secondary devices can be promoted to primary (migration flow)
- ⚠️ **CRITICAL**: Secondary devices MUST NOT open the Bark wallet
- ⚠️ Secondary devices only show CloudKit metadata, never sync with ASP
- ⚠️ This is a "single active device" model, like hardware wallets

**Benefits Achieved**:
- ✅ Single source of truth for VTXO state (only primary has it)
- ✅ Database consistency guaranteed (no divergence)
- ✅ Reduced ASP server load (only one device syncs)
- ✅ Simple mental model (like hardware wallet)
- ✅ No complex state synchronization needed

**✅ Implementation Complete (2026-05-07)**:
1. ✅ `isPrimaryDevice` flag added to `DeviceRegistration`
2. ✅ Secondary devices blocked from opening Bark wallet (`initializeReadOnlyMode()`)
3. ✅ Read-only mode shows CloudKit-synced data (no "blocking" screen)
4. ✅ CloudKit transaction metadata displayed (via `ReadOnlyBalanceService`, `ReadOnlyAddressService`)
5. ✅ Migration flow available (via `migrateToThisDevice()` in Linked Devices settings)
6. ✅ UI conditionally renders features based on `isReadOnlyMode`
7. ✅ No wallet state serialization (wallet never opens on secondary)
8. ✅ CloudKit metadata sync sufficient for viewing

---

## 5. Similar App Patterns

### WhatsApp Multi-Device
- Phone is primary device ("hub")
- Desktop/web are secondary ("spokes")
- Message history syncs from phone initially
- After sync, all devices are peers for new messages
- If phone offline for >14 days, secondary devices stop working

### Signal Linked Devices
- Phone is primary device (required)
- Desktop/iPad are linked devices
- All messages flow through primary device
- Secondary devices cannot add new linked devices
- Primary device can unlink secondary devices

### Arké's Implemented Model ✅ (Single Active Device - Like Hardware Wallet)
- **Primary device only**: One device has wallet open at a time
- **Secondary devices**: Show CloudKit-synced data in read-only mode
- **No blocking screen**: Secondary devices show full UI with limited features
- **Hidden features**: Send, Data, Console, wallet operations hidden on secondary
- **Visible features**: Activity history, contacts, tags, receive addresses (all synced via CloudKit)
- **Migration support**: User can switch primary via Settings → Linked Devices
- **Safe by design**: No database synchronization complexity, no divergence possible

---

## 6. Risk Assessment - RESOLVED ✅

### Previous Risk: Accidental Multi-Device Usage

**The Problem (Before Implementation)**:
With iCloud Keychain syncing seed phrases automatically, users could open the app on multiple devices and both would attempt to sync with the Ark server independently, causing database corruption.

**The Solution (Now Implemented)**:
1. ✅ `isPrimaryDevice` flag in device registration
2. ✅ Primary device: Full wallet access with ASP connection
3. ✅ Secondary devices: Read-only mode with CloudKit-synced data only
4. ✅ No wallet file opened on secondary devices
5. ✅ UI automatically hides wallet operations (send, data, console) on secondary devices

### Current User Experience

**Primary Device (iPhone)**:
- Full wallet functionality
- Sends/receives transactions
- Syncs with Ark server
- All features available

**Secondary Device (iPad)**:
- Opens app seamlessly (no blocking screen)
- Views transaction history (CloudKit-synced)
- Views contacts, tags, balances
- Receive addresses visible
- Send/wallet operations not visible
- Can switch to primary via Settings → Linked Devices

**Result**: Safe multi-device access with clean UX - no risk of database corruption.

---

## 7. Implementation Approach - COMPLETED ✅

### Single Active Device (Read-Only Mode) ✅ **IMPLEMENTED (2026-05-07)**

**Implemented Solution**:
- ✅ Only ONE device has wallet open at a time
- ✅ **Primary device calls `sync()` on ASP**
- ✅ **Secondary devices never open wallet** (BarkWalletFFI never initialized)
- ✅ Secondary devices show CloudKit-synced metadata in read-only mode
- ✅ User can migrate wallet to different device via Settings

**Implementation Details**:
1. ✅ `isPrimaryDevice` flag in `DeviceRegistration` model
2. ✅ Wallet initialization blocked on secondary devices (`initializeReadOnlyMode()`)
3. ✅ Read-only mode shows full UI with conditional feature visibility
4. ✅ CloudKit metadata displayed via `ReadOnlyBalanceService` and `ReadOnlyAddressService`
5. ✅ Migration via `migrateToThisDevice()` in Linked Devices settings
6. ✅ UI features conditionally rendered based on `walletManager.isReadOnlyMode`
7. ✅ No wallet state serialization needed
8. ✅ CloudKit handles all metadata sync

**Achieved Benefits**:
- ✅ Architecturally correct (no database divergence possible)
- ✅ Single source of truth (only one wallet open)
- ✅ Reduced server load (only one device syncs)
- ✅ Clean implementation (conditional rendering, no blocking screens)
- ✅ Familiar UX (like hardware wallets)
- ✅ No complex state synchronization

**User Experience**:
- Secondary devices work seamlessly (no jarring "blocked" screen)
- Features that require wallet just don't appear
- Migration is one tap in settings
- CloudKit keeps transaction history in sync

---

## 8. Implementation Status ✅ COMPLETE

### **Phase 1: Single Active Device ✅ COMPLETE (2026-05-07)**
1. ✅ `isPrimaryDevice` flag in `DeviceRegistration`
2. ✅ First device to create/import wallet becomes primary automatically
3. ✅ Wallet initialization blocked on secondary (`initializeReadOnlyMode()`)
4. ✅ Read-only mode shows CloudKit-synced data (no blocking screen)
5. ✅ CloudKit transaction metadata displayed via `ReadOnlyBalanceService`, `ReadOnlyAddressService`
6. ✅ Migration via `migrateToThisDevice()` available in Settings → Linked Devices
7. ✅ Migration updates `isPrimaryDevice` flags via CloudKit
8. ✅ After migration, new primary initializes wallet, old primary switches to read-only

### **Phase 2: Server Recovery (Future - When Available)**
1. Use server VTXO recovery for initial wallet restore
2. Still maintain single active device model
3. Server provides fallback if primary device lost
4. Recovery: Any device can become primary with server state

### **Phase 3: Enhanced UX (Future - Optional)**
1. Show sync status indicator ("Syncing on iPhone...")
2. "Last synced X minutes ago" indicator on secondary devices
3. Push notifications for transactions (from CloudKit metadata sync)
4. Smoother migration flow with progress indicators

---

## 8. Technical Implementation Details ✅

### Read-Only Mode Architecture

**Primary Device**:
- `WalletManager.initializePrimaryMode()` → opens `BarkWalletFFI`
- Initializes: `BalanceService`, `AddressService`, `TransactionService`, etc.
- Connects to ASP and syncs VTXO state
- Writes metadata to SwiftData/CloudKit

**Secondary Device**:
- `WalletManager.initializeReadOnlyMode()` → never opens `BarkWalletFFI`
- Initializes: `ReadOnlyBalanceService`, `ReadOnlyAddressService`
- Loads metadata from SwiftData (CloudKit-synced)
- No ASP connection, no VTXO state access

### Service Branching

```swift
// WalletManager conditionally uses read-only services
var arkAddress: String {
    if isReadOnlyMode {
        return readOnlyAddressService?.arkAddress ?? ""
    } else {
        return addressService?.arkAddress ?? ""
    }
}

var arkBalance: ArkBalanceModel? {
    isReadOnlyMode ? readOnlyBalanceService?.arkBalance : balanceService?.arkBalance
}
```

### UI Conditional Rendering

```swift
// Features hidden on secondary devices
if !manager.isReadOnlyMode {
    // Send tab/button
    // Data view
    // Console view
    // Board/Offboard buttons
    // Manual refresh controls
}
```

---

## 9. Key Implementation Files

**Device System**:
- `Shared/Models/DeviceRegistration.swift` - Device tracking with `isPrimaryDevice`
- `Shared/Services/DeviceRegistrationService.swift` - Registration and migration logic
- `Shared/Helpers/CloudKitObserver.swift` - Real-time sync notifications

**Wallet Manager**:
- `Shared/Data/WalletManager/WalletManager.swift` - Main coordinator with read-only mode logic
  - `checkReadOnlyMode()` - Detects device role
  - `initializePrimaryMode()` - Full wallet initialization
  - `initializeReadOnlyMode()` - CloudKit-only initialization

**Read-Only Services**:
- `Shared/Services/ReadOnlyBalanceService.swift` - Balance loading from CloudKit
- `Shared/Services/ReadOnlyAddressService.swift` - Address loading from CloudKit

**UI Implementation**:
- `ArkeMobile/Views/MainView_iOS.swift` - Handles `walletActiveElsewhere` state
- `ArkeMobile/Views/WalletView_iOS.swift` - Conditional tab rendering
- `ArkeMobile/Views/Balance/BalanceView_iOS.swift` - Hides operations in read-only mode
- `ArkeMobile/Views/Settings/SettingsView_iOS.swift` - Hides danger zone in read-only mode
- `ArkeDesktop/Views/MainView.swift` - macOS equivalent
- `ArkeDesktop/Views/WalletSidebar.swift` - Conditional sidebar items

---

## 10. Design Decisions & Rationale

### Why Read-Only Mode Instead of Blocking Screen?
**Decision**: Show full UI with conditionally hidden features instead of blocking screen.

**Rationale**:
- Better UX - users can still view transaction history, contacts, balances
- Natural migration flow - "Make This Device Primary" button in settings
- Familiar pattern - like viewing bank account on multiple devices
- Reduces support burden - users understand they're viewing data, not blocked

### Why Secondary Devices Have Seed Phrase?
**Decision**: iCloud Keychain syncs seed to all devices, even secondary.

**Rationale**:
- **Recovery**: If primary device is lost, any device can become primary
- **Migration**: Instant device switching without QR code scanning
- **Simplicity**: No separate "seed transfer" flow needed
- **Safety**: `isPrimaryDevice` flag prevents wallet file opening, not seed access

### Why Not Sync VTXO State via CloudKit?
**Decision**: Only primary device accesses VTXOs; secondary devices show metadata only.

**Rationale**:
- **Database Consistency**: Two devices with independent Bark wallet DBs would diverge
- **No Conflict Resolution**: VTXO state isn't mergeable like documents
- **Server Authority**: ASP is source of truth for VTXO state
- **Simplicity**: Metadata sync (transactions, balances) is sufficient for viewing

---

## 11. Summary & Next Steps

### Current State ✅ **FULLY IMPLEMENTED**
- ✅ Robust device tracking via CloudKit
- ✅ Real-time metadata sync across devices
- ✅ Smart device deletion logic
- ✅ Seed phrase auto-sync via iCloud Keychain
- ✅ `isPrimaryDevice` flag in `DeviceRegistration`
- ✅ Primary device auto-assignment on first registration
- ✅ Migration API (`migrateToThisDevice()`)
- ✅ **Read-only mode for secondary devices**
- ✅ **Hub-and-spoke pattern fully implemented**
- ✅ **Only primary device opens wallet and syncs with ASP**
- ✅ **Secondary devices show CloudKit-synced metadata**
- ✅ **Safe multi-device viewing without database corruption**

### Implementation Complete ✅ (2026-05-07)

**Core Functionality**:
1. ✅ `isPrimaryDevice` flag in `DeviceRegistration` model
   - First device automatically becomes primary
   - Helper methods: `getPrimaryDevice()`, `isCurrentDevicePrimary()`, `migrateToThisDevice()`
2. ✅ Wallet initialization branching
   - Primary: `initializePrimaryMode()` opens BarkWalletFFI, connects to ASP
   - Secondary: `initializeReadOnlyMode()` uses CloudKit-only services
3. ✅ Read-only mode implementation
   - `ReadOnlyBalanceService` and `ReadOnlyAddressService` for secondary devices
   - UI conditionally hides wallet operations based on `isReadOnlyMode`
   - Clean UX without blocking screens
4. ✅ Migration flow
   - Available in Settings → Linked Devices
   - Updates device roles via CloudKit
   - Seamless device switching

**Status**: ✅ **PRODUCTION READY** - Users can safely use the app on multiple devices without risk of database corruption.

### Optional Enhancements (Future)

**Short-Term Polish**:
1. Show sync status indicator ("Syncing on iPhone...")
2. "Last synced X minutes ago" on secondary devices
3. Improved migration UX (loading states, success confirmation)
4. "Active" badge in Linked Devices list

**Medium-Term Features**:
1. **Payment request relay** (optional convenience)
   - Tap "Pay" on secondary device → notification to primary
   - Primary device approves/completes transaction
   - Status updates via CloudKit
2. Push notifications for new transactions on secondary devices
3. More detailed transaction metadata on secondary devices

**Long-Term** (Server-Dependent):
1. Server VTXO recovery endpoint for wallet restoration
2. Server provides fallback if primary device lost
3. Still maintain single active device model for consistency

---

## Related Documentation

- `Features/Read_Only_Mode.md` - Read-only mode behavior (plan archived in Archive/Implementations/)
- `DEVICE_REGISTRY_ALL_PHASES_COMPLETE.md` - Device system implementation
- `Device_Registry_Reference.md` - Device API reference
- `CloudKitSyncImplementation.md` - Sync architecture
- `CloudKit/CloudKitSyncGuidelines.md` - Sync best practices
- `PASSKEY_INTEGRATION_PLAN.md` - Future server recovery plans

---

**Author**: Claude (AI Assistant)  
**Last Updated**: 2026-05-08  
**Status**: ✅ Implementation Complete - Production Ready
