# Read-Only Mode (Secondary Devices)

**Status:** ✅ Shipped (read-only mode 2026-05-07, manual role switching 2026-05-12)
**Distilled from:** `Archive/Implementations/READ_ONLY_MODE_IMPLEMENTATION_PLAN.md` and `Archive/Implementations/MANUAL_PRIMARY_DEVICE_ASSIGNMENT.md` (full implementation history and code review there)

---

## Overview

Only one device (the **primary**) runs the actual Bark wallet and talks to the ASP. All other devices registered to the same wallet run in **read-only mode**: they display data synced via CloudKit but never touch the wallet file or the ASP. This enables multi-device support without wallet corruption.

### Core Principle

Features that require the primary device **simply don't appear** in read-only mode — no disabled buttons, no tooltips, no status banner. The UI is just smaller.

## How Mode Is Determined

`WalletManager.isReadOnlyMode` is set during initialization based on the device's `DeviceRegistration.isPrimaryDevice` flag. `performInitialization()` branches:

- **`initializePrimaryMode()`** — full path: BarkWalletFFI, ASP connection, all background services.
- **`initializeReadOnlyMode()`** — skips BarkWalletFFI and ASP entirely; only CloudKit/SwiftData-backed services run.

Demotion is detected **before** wallet access via `WalletManager.shouldBlockWalletAccess()`, a three-layer check (fastest first): local UserDefaults flag → iCloud KV Store → CloudKit `DeviceRegistration` cache.

## What Works vs. What's Hidden

| Available in read-only mode | Hidden in read-only mode |
|-----------------------------|--------------------------|
| Balance view (CloudKit snapshot) | Send operations |
| Transaction history (Activity) | Lightning invoice generation (needs ASP) |
| Receive addresses (synced; via `ReadOnlyAddressService`) | Board/Offboard, manual refresh, pull-to-refresh |
| Contacts & Tags (full read/write, syncs back) | Data & Console views (data doesn't exist without ASP) |
| Settings: display prefs, recovery phrase, linked devices | Notifications, Fee Schedule, Danger Zone, developer tools |
| Help & Learning | Exit operations, Delete wallet |

**When adding new UI:** anything that calls the wallet FFI or ASP must be wrapped in `if !walletManager.isReadOnlyMode`. Affected views so far: `BalanceView(_iOS)`, `WalletView_iOS` tabs, `WalletSidebar` (macOS), `SettingsView_iOS`, `ReceiveView(_iOS)` (Lightning toggle), `ActivityView_iOS`.

### Read-only service stand-ins

- `ReadOnlyAddressService` (in `AddressService.swift`) — serves CloudKit-synced addresses; cannot generate new ones.
- `ReadOnlyBalanceService` (in `BalanceService.swift`) — loads balance snapshots from SwiftData.
- TagService, ContactService, TransactionAnnotationService, DeviceRegistrationService, SecurityService work unchanged (pure CloudKit/SwiftData).

## Switching the Primary Device

Manual two-step migration via Settings → Linked Devices (`LinkedDevicesView_iOS`, sheets in `DeviceAssignmentSheets_iOS.swift`):

1. **Demote** (on current primary): `DeviceRegistrationService.demoteThisDevice()` backs up the wallet to iCloud (via `closeWallet()` shutdown), sets `isPrimaryDevice = false`, updates the iCloud KV Store and a local UserDefaults flag, and posts `.deviceDemotedFromPrimary` so WalletManager closes the wallet and drops to read-only. Safe intermediate state: *no* device is primary.
2. **Promote** (on the new device): `promoteThisDeviceToPrimary()` flips the flags and posts `.devicePromotedToPrimary`; WalletManager re-initializes as primary, restoring the wallet from the iCloud backup if the local file is missing or older (`restoreWalletIfNeeded()` compares timestamps and always keeps the newest state).

`checkForNoPrimaryDevice()` drives a "No Active Wallet" banner prompting promotion. Remote demotion is picked up by `MainView_iOS.handleUbiquitousStoreChange()` watching the KV Store key.

**Migration preserves SwiftData:** demotion uses `resetManagerStateForMigration()` (keeps transactions/tags/contacts for read-only display), not the full `resetManagerState()` used by wallet deletion.

## Known Limitations

- Balance/data on secondary devices is a snapshot from the primary's last sync; no manual force-refresh exists.
- Emergency takeover (primary device lost) is not implemented — see `DEVICE_MIGRATION_IMPLEMENTATION_PLAN_REVISED.md`.
- Mock wallet can't exercise backup/restore (methods aren't on `BarkWalletProtocol`), so migration flows lack automated tests.

## Related Documentation

- `DEVICE_MIGRATION_IMPLEMENTATION_PLAN_REVISED.md` — emergency takeover and hardening (planned)
- `Device_Registry_Reference.md` — device registration API
- `LINKED_DEVICES_AND_VTXO_SYNC_ANALYSIS.md` — original multi-device analysis
