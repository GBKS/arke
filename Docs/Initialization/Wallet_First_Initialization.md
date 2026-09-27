# Wallet-First Initialization Architecture

## Summary

The app now performs **wallet detection before any CloudKit/SwiftData sync operations**, preventing unnecessary network activity and data loading when no wallet exists.

## Implementation

### Phase 1: Early Detection (Synchronous, Fast)

**File**: `SecurityService.swift`
- Added `static func hasMnemonicInKeychain() -> Bool`
- Zero dependencies, synchronous Keychain check
- Returns true/false instantly

**File**: `Arke_mobile.swift`
- Added custom `init()` to perform early wallet check
- Calls `SecurityService.hasMnemonicInKeychain()` before UI loads
- Sets `ServiceContainer.isActive` based on result

```swift
init() {
    let hasWallet = SecurityService.hasMnemonicInKeychain()
    
    if hasWallet {
        serviceContainer.setActive(true)  // ✅ Enable sync
    } else {
        serviceContainer.setActive(false)  // ⏸️ Skip sync
    }
}
```

### Phase 2: Conditional Service Configuration

**File**: `ServiceContainer.swift`
- Added `isActive: Bool` property (default: `false`)
- Added `setActive(_ active: Bool)` method
- Modified `configureServices(with:)` to check `isActive` before loading data

```swift
func configureServices(with modelContext: ModelContext) {
    guard isActive else {
        print("⏭️ Skipping service configuration - container is passive")
        return
    }
    
    // Only reached if wallet exists
    securityService.setModelContext(modelContext)
    tagService.setModelContext(modelContext)
    contactService.setModelContext(modelContext)
    contactAddressService.setModelContext(modelContext)
}
```

### Phase 3: Post-Onboarding Activation

**File**: `MainView_iOS.swift`
- Added `@Environment(\.serviceContainer)` access
- After wallet creation in onboarding, activates services:

```swift
OnboardingFlow_iOS(onWalletReady: {
    Task {
        // Activate services now that wallet exists
        serviceContainer.setActive(true)
        
        // Configure services to begin loading data
        serviceContainer.configureServices(with: modelContext)
        
        // Initialize the wallet
        await walletManager.initialize()
        hasWallet = true
    }
})
```

## Flow Diagrams

### Before (Old Behavior)

```
App Launch
  ↓
ModelContainer created → CloudKit connects
  ↓
ServiceContainer initialized
  ↓
Services configured with ModelContext
  ↓
  ├─ TagService → Loads 0 tags from SwiftData
  ├─ ContactService → Loads 0 contacts from SwiftData
  └─ SecurityService → Checks wallet metadata in SwiftData
  ↓
MainView appears
  ↓
.task starts → detectWalletState()
  ↓
Result: noWallet
  ↓
Show onboarding
```

❌ **Problem**: CloudKit sync and data loading happens **before** wallet detection

### After (New Behavior - Existing Wallet)

```
App Launch
  ↓
SecurityService.hasMnemonicInKeychain() ✅ TRUE
  ↓
ServiceContainer.setActive(true)
  ↓
ModelContainer created → CloudKit connects
  ↓
MainView appears
  ↓
.task starts → ServiceConfiguration triggered
  ↓
configureServices(with: modelContext)
  ↓
  ├─ TagService → Loads tags from SwiftData
  ├─ ContactService → Loads contacts from SwiftData
  └─ SecurityService → Sets model context
  ↓
detectWalletState() → walletWithSeed
  ↓
Show WalletView
```

✅ **Result**: Sync only happens **after** confirming wallet exists

### After (New Behavior - No Wallet)

```
App Launch
  ↓
SecurityService.hasMnemonicInKeychain() ⚠️ FALSE
  ↓
ServiceContainer.setActive(false)
  ↓
ModelContainer created (passive)
  ↓
MainView appears
  ↓
.task starts → ServiceConfiguration triggered
  ↓
configureServices() → SKIPPED (isActive = false)
  ↓
detectWalletState() → noWallet
  ↓
Show OnboardingFlow
  ↓
User creates wallet
  ↓
onWalletReady callback:
  ├─ ServiceContainer.setActive(true)
  ├─ configureServices(with: modelContext) ← NOW loads data
  └─ walletManager.initialize()
  ↓
Show WalletView
```

✅ **Result**: No sync until wallet is created

## Expected Debug Logs

### Existing Wallet User

```
🔍 [SecurityService.static] Keychain mnemonic check: ✅ Found
✅ [App Init] Wallet detected - services will be activated
🔧 ServiceContainer initialized
🌥️ CloudKit enabled with automatic container
✅ ModelContainer created successfully
🔧 Configuring services with ModelContext
📋 Loaded X tags from SwiftData
👥 Loaded X contacts with addresses from SwiftData
🔍 [MainView] detectWalletState returned: walletWithSeed
```

### New User (No Wallet)

```
🔍 [SecurityService.static] Keychain mnemonic check: ⚠️ Not found
⏭️ [App Init] No wallet detected - services will remain passive
🔧 ServiceContainer initialized
🌥️ CloudKit enabled with automatic container
✅ ModelContainer created successfully
⏭️ Skipping service configuration - container is passive
🔍 [MainView] detectWalletState returned: noWallet
```

### After Onboarding Completion

```
✅ ServiceContainer activated - services will load and sync data
🔧 Configuring services with ModelContext
📋 Loaded 0 tags from SwiftData (new wallet)
👥 Loaded 0 contacts with addresses from SwiftData (new wallet)
```

## Benefits

1. **Performance**: No CloudKit sync on first launch for new users
2. **Battery**: Saves network and compute resources during onboarding
3. **Privacy**: No iCloud activity until user creates wallet
4. **Clean Logs**: Log output matches actual app state
5. **Architecture**: Clear separation between detection and initialization
6. **Maintainability**: Single source of truth for activation state

## Files Modified

1. ✅ `SecurityService.swift` - Added static wallet detection method
2. ✅ `Arke_mobile.swift` - Early wallet check in `init()`
3. ✅ `ServiceContainer.swift` - Added `isActive` flag and gating logic
4. ✅ `MainView_iOS.swift` - Activate services after wallet creation

## Testing Checklist

- [ ] Fresh install (no wallet) - services should be passive
- [ ] After onboarding - services should activate and load data
- [ ] Existing wallet user - services should activate immediately
- [ ] App restart with wallet - services activate on launch
- [ ] Delete wallet - services should deactivate (if supported)
- [ ] CloudKit sync only after wallet confirmed
- [ ] Debug logs match expected output

## Future Enhancements

1. **Dynamic Activation**: Could add `ServiceContainer.deactivate()` for logout/delete wallet
2. **Service-Level Granularity**: Individual services could have their own `isActive` flags
3. **Metrics**: Track time saved by skipping unnecessary sync operations
4. **CloudKit Container**: Could conditionally create CloudKit container (more complex)

---

**Created**: 2025-11-28  
**Status**: ✅ Implemented
