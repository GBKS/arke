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
     3. Default to signet (fallback)

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
WalletManager.deleteWallet()
    ↓
NetworkConfigPersistence.clear() ← NEW (Step 5)
    ↓
WalletDataCleanupService.clearUserDefaults()
    ↓
Removes UserDefaults["com.arke.wallet.networkConfigId"]
    ↓
Next launch defaults to signet (for new wallet)
```

## Implementation Details

### NetworkConfigPersistence.swift

```swift
class NetworkConfigPersistence {
    static func save(_ networkConfig: NetworkConfig) {
        UserDefaults.standard.set(networkConfig.id, forKey: UserDefaults.networkConfigKey)
        UserDefaults.standard.synchronize()
    }
    
    static func load() -> NetworkConfig? {
        guard let savedId = UserDefaults.standard.string(forKey: UserDefaults.networkConfigKey) else {
            return nil
        }
        
        // Match against predefined networks
        let predefinedNetworks: [NetworkConfig] = [.mainnet, .signet, .testnet]
        return predefinedNetworks.first(where: { $0.id == savedId })
    }
    
    static func clear() {
        UserDefaults.standard.removeObject(forKey: UserDefaults.networkConfigKey)
        UserDefaults.standard.synchronize()
    }
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
        config = explicitConfig  // Priority 1: Explicit parameter
    } else if let savedConfig = NetworkConfigPersistence.load() {
        config = savedConfig  // Priority 2: Saved config ← NEW
    } else {
        config = NetworkConfig.signet  // Priority 3: Default
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

1. **No saved config**: Falls back to signet (default behavior)
2. **Invalid saved ID**: Returns nil, falls back to default
3. **Wallet deletion**: Config cleared in both WalletManager and WalletDataCleanupService
4. **Testing**: Can override config with explicit parameter
5. **Custom networks**: Currently warns and returns nil (future enhancement)

## Future Enhancements

1. **Custom Network Support**: Persist full custom network details (not just ID)
2. **iCloud Sync**: Use NSUbiquitousKeyValueStore for cross-device sync
3. **Validation**: Validate loaded config against actual wallet data on open
4. **Migration**: Detect and migrate wallets created before this feature

## Testing Checklist

- [x] Build succeeds with no errors
- [ ] Create mainnet wallet, restart app, verify mainnet config loaded
- [ ] Create signet wallet, restart app, verify signet config loaded
- [ ] Delete wallet, verify network config cleared
- [ ] Fresh install (no saved config), verify defaults to signet

## Related Files

- BarkWalletFFI.swift - Wallet initialization with network config
- BarkWalletFFI+WalletLifecycle.swift - tryOpenExistingWallet() logs config
- NetworkConfig.swift - Network configuration models
- WalletManager.swift - Orchestrates wallet lifecycle

## Revision History

- 2026-04-30: Initial implementation (UserDefaults-based persistence)
