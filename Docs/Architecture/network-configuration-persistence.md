# Network Configuration Persistence

## Overview

This document describes how the app persists and restores network configuration (mainnet, signet, testnet) across app sessions to ensure the wallet always connects to the correct servers.

## Problem Statement

Prior to this implementation, the app would:
1. Create a wallet on mainnet with mainnet servers
2. Store wallet data with mainnet configuration
3. On next app launch, initialize `BarkWalletFFI` with **default signet config**
4. Attempt to open mainnet wallet with signet servers ❌

This caused the wallet to print incorrect server URLs on startup and potentially connect to the wrong network.

## Solution

We implemented a UserDefaults-based persistence layer that:
1. Saves the network config ID when creating/importing a wallet
2. Loads the saved config on app launch
3. Clears the config when deleting the wallet

## Architecture

### Files Modified/Created

1. **Shared/Data/NetworkConfigPersistence.swift** (NEW)
   - Utility class for saving/loading network configuration
   - Uses centralized UserDefaults key
   - Provides: `save()`, `load()`, `clearLocal()`, `clearEverywhere()`,
     `savedConfigId()`, `syncFromiCloud()`, `reconciliation()`

2. **Shared/Helpers/UserSettings.swift** (MODIFIED)
   - Added `networkConfigKey` constant for centralized key management

3. **Shared/Data/WalletManager/WalletManager.swift** (MODIFIED)
   - Updated `init()` to load saved network config with priority:
     1. Explicit parameter (for testing/overrides)
     2. Saved config from UserDefaults
     3. Default to mainnet (`load()`'s fallback — deliberately not signet)

4. **Shared/Data/WalletManager/WalletManager+Wallet.swift** (MODIFIED)
   - `createWallet()`: Saves network config after creation
   - `importWallet()`: Saves network config after import
   - `deleteWallet()`: Clears network config on deletion

5. **Shared/Views/Settings/WalletDataCleanupService.swift** (MODIFIED)
   - `clearUserDefaults()`: Also clears network config
   - Provides redundancy in case deleteWallet() isn't called

## Flow Diagrams

### Wallet Creation Flow

```
User creates mainnet wallet
    ↓
WalletManager.createWallet(networkConfig: .mainnet)
    ↓
wallet.updateNetworkConfig(.mainnet)
    ↓
NetworkConfigPersistence.save(.mainnet) ← NEW
    ↓
UserDefaults["com.arke.wallet.networkConfigId"] = "mainnet"
    ↓
Wallet files created with mainnet servers
```

### App Launch Flow

```
App launches
    ↓
WalletManager.init()
    ↓
NetworkConfigPersistence.load()
    ↓
Reads UserDefaults["com.arke.wallet.networkConfigId"] → "mainnet"
    ↓
BarkWalletFFI(networkConfig: .mainnet)   ← may be stale or absent
    ↓
performInitialization() step 0-pre:
reconcileNetworkConfigBeforeWalletOpen()
    ↓
skip if already open  ·  else syncFromiCloud() + reconciliation()
    ↓
wallet.updateNetworkConfig(.signet) when the account disagrees
    ↓
tryOpenExistingWallet() uses the account's network ✅
```

The cache is only a launch-time guess: it is written by create/import and can
be absent or stale. Step 0-pre makes the account's value authoritative in the
window before an open, and only there — see Launch_Sequence_Contract rule 22
for why reconciling *after* an open is forbidden.

### Wallet Deletion Flow

```
User deletes wallet
    ↓
WalletDataCleanupService (strategy-aware)
    ↓
clearUserDefaults() → NetworkConfigPersistence.clearLocal()   (every deletion)
clearEverywhere() — the iCloud KVS copy too                   (full wipe ONLY:
    on a local-only deletion the KVS copy is the remaining
    devices' network identity — contract rule 21)
    ↓
Removes UserDefaults["com.arke.wallet.networkConfigId"]
    ↓
Next launch: load() defaults to mainnet; onboarding sets the network
```

## Implementation Details

### NetworkConfigPersistence.swift (shape as of 2026-09-25 — see source for full doc comments)

```swift
class NetworkConfigPersistence {
    /// Saves locally and mirrors to iCloud KVS via a detached task
    static func save(_ networkConfig: NetworkConfig) { ... }

    /// NON-optional: unresolvable or missing ids fall back to .mainnet.
    /// The reconciliation path deliberately does NOT use this fallback —
    /// `reconciliation()` returns `.noUsableConfig` instead, because a
    /// mainnet fallback would re-point a running signet wallet (rule 22).
    static func load() -> NetworkConfig { ... }

    static func savedConfigId() -> String? { ... }
    static func syncFromiCloud() async { ... }
    static func reconciliation(walletNetworkId:cachedConfigId:) -> Reconciliation { ... }

    /// This device's cache only
    static func clearLocal() { ... }
    /// Local + the account's iCloud KVS copy — full wipe only (rule 21)
    static func clearEverywhere() { ... }
}
```

### UserSettings.swift

```swift
extension UserDefaults {
    static let balancePrivacyKey = "balancePrivacyEnabled"
    static let networkConfigKey = "com.arke.wallet.networkConfigId"  // ← NEW
}
```

### WalletManager.init()

```swift
init(useMock: Bool = false, networkConfig: NetworkConfig? = nil) {
    let config: NetworkConfig
    if let explicitConfig = networkConfig {
        config = explicitConfig              // Priority 1: Explicit parameter
    } else {
        config = NetworkConfigPersistence.load()  // Priority 2: saved, else mainnet
    }

    setupWallet(useMock: shouldUseMock, networkConfig: config)
    initializeServices()
}
```

## Benefits

1. **Correctness**: Wallet always uses the network it was created on
2. **User Experience**: No unexpected behavior when switching between networks
3. **Debugging**: Clear logging shows which network was loaded
4. **Simplicity**: UserDefaults is simple, reliable, and survives app restarts
5. **Integration**: Works with existing WalletDataCleanupService
6. **Defense in Depth**: Network config cleared in multiple places

## Edge Cases Handled

1. **No saved config**: `load()` falls back to mainnet at init time;
   reconciliation answers `.noUsableConfig` (never a silent fallback) and
   onboarding sets the network
2. **Invalid saved ID** (e.g. a `custom_<UUID>` id): same split — `load()`
   falls back to mainnet, `reconciliation()` reports `.noUsableConfig`
3. **Wallet deletion**: strategy-aware — `clearLocal()` on every deletion,
   `clearEverywhere()` only on the last-device full wipe (rule 21)
4. **Testing**: Can override config with explicit parameter

## Implemented Since (formerly "future enhancements")

1. **iCloud Sync**: implemented and load-bearing — `save()` mirrors to
   NSUbiquitousKeyValueStore, `syncFromiCloud()` +
   `reconcileNetworkConfigBeforeWalletOpen()` make the account's value
   authoritative in the window before a wallet open (rule 22)

## Still Open

1. **Custom Network Support**: `custom_<UUID>` ids can't be resolved by
   `findConfig`; no UI constructs one today, so latent only
2. **Validation**: Validate loaded config against actual wallet data on open —
   there is still no recovery path when the ACCOUNT's value is the stale one
   (the open fails with a mismatch every launch and no user-facing escape)

## Testing Checklist

- [x] Reconciliation decision matrix: `NetworkConfigReconciliationTests`
- [ ] Create mainnet wallet, restart app, verify mainnet config loaded
- [ ] Create signet wallet, restart app, verify signet config loaded
- [ ] Delete wallet, verify network config cleared per strategy
- [ ] Fresh install (no saved config): onboarding sets the network

## Related Files

- BarkWalletFFI.swift - Wallet initialization with network config
- BarkWalletFFI+WalletLifecycle.swift - tryOpenExistingWallet() logs config
- NetworkConfig.swift - Network configuration models
- WalletManager.swift - Orchestrates wallet lifecycle

## Revision History

- 2026-04-30: Initial implementation (UserDefaults-based persistence)
- 2026-09-25: Claims audit — corrected the stale signet-fallback claims
  (actual fallback is mainnet), the pre-KVS code samples, and the "iCloud sync
  is future work" listing (implemented and load-bearing since rule 22)
