# Issue 1: Device Registration Fails During Wallet Creation

**Date:** December 10, 2024  
**Status:** ✅ Root Cause Identified  
**Priority:** Low (Non-Critical)

---

## Executive Summary

**Problem:** Device registration fails silently during wallet creation because ModelContext is not yet available.

**Root Cause:** 
- DeviceRegistrationService.registerCurrentDevice() needs ModelContext to save to SwiftData
- ModelContext is only provided AFTER wallet creation completes via ServiceContainer.configureServices()
- This is a timing/initialization order issue

**Impact:** Low
- Error is caught and swallowed - user doesn't see it
- Device won't appear in device registry until app restart
- Device heartbeat won't work initially
- Wallet creation still succeeds

**Fix:** Move device registration to after ServiceContainer.configureServices() is called

---

## Visual Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ CURRENT FLOW (BROKEN)                                           │
└─────────────────────────────────────────────────────────────────┘

1. WalletManager.createWallet()
   └─ SecurityService.saveMnemonic()
       └─ DeviceRegistrationService.registerCurrentDevice()
           └─ ❌ THROWS: DeviceRegistrationError.noModelContext
               └─ ✅ ERROR CAUGHT - doesn't propagate to user

2. MainView.onWalletReady()
   └─ ServiceContainer.configureServices(modelContext)
       └─ ✅ NOW ModelContext is available! (too late)


┌─────────────────────────────────────────────────────────────────┐
│ FIXED FLOW                                                       │
└─────────────────────────────────────────────────────────────────┘

1. WalletManager.createWallet()
   └─ SecurityService.saveMnemonic()
       └─ Save to keychain ✓
       └─ (NO device registration here)

2. MainView.onWalletReady()
   └─ ServiceContainer.configureServices(modelContext)
       └─ ✅ ModelContext is available
   └─ DeviceRegistrationService.registerCurrentDevice()
       └─ ✅ SUCCESS - can save to SwiftData
```

---

## Technical Details

### Current Code (Broken)

**File: SecurityService.swift (lines 228-243)**
```swift
func saveMnemonic(_ mnemonic: String, requireBiometric: Bool = false) async throws {
    // ... saves to keychain ...
    
    // This runs BEFORE ModelContext is available
    let hash = hashMnemonic(mnemonic)
    do {
        try await deviceRegistrationService.registerCurrentDevice(
            walletHash: hash,
            hasSeed: true
        )
        print("✅ [SecurityService] Device registered with hasSeed=true")
    } catch {
        // Error is caught and logged, but not re-thrown
        print("⚠️ [SecurityService] Failed to register device: \(error.localizedDescription)")
        // ⚠️ Wallet creation continues anyway
    }
}
```

**File: DeviceRegistrationService.swift (line 171)**
```swift
func registerCurrentDevice(walletHash: String, hasSeed: Bool) async throws {
    return try await taskManager.execute(key: "registerCurrentDevice") {
        guard let modelContext = self.modelContext else {
            throw DeviceRegistrationError.noModelContext  // ❌ THROWS HERE
        }
        
        // ... rest of registration logic ...
    }
}
```

---

## Implementation Fix

### Step 1: Remove Device Registration from SecurityService

**File: SecurityService.swift**
```swift
func saveMnemonic(_ mnemonic: String, requireBiometric: Bool = false) async throws {
    // Save to keychain
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: keychainAccount,
        kSecValueData as String: mnemonic.data(using: .utf8)!,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    
    // Delete old entry if exists
    SecItemDelete(query as CFDictionary)
    
    // Add new entry
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw SecurityServiceError.keychainError("Failed to save mnemonic: \(status)")
    }
    
    // Save hash to iCloud
    let hash = hashMnemonic(mnemonic)
    let store = NSUbiquitousKeyValueStore.default
    store.set(hash, forKey: "com.arke.wallet.mnemonicHash")
    store.synchronize()
    
    // REMOVED: Device registration - now happens later
    // do {
    //     try await deviceRegistrationService.registerCurrentDevice(...)
    // } catch { ... }
}

// Add helper method to get hash
func getMnemonicHash() -> String? {
    guard let mnemonic = try? loadMnemonic() else {
        return nil
    }
    return hashMnemonic(mnemonic)
}
```

---

### Step 2: Add Device Registration to MainView After Configuration

**File: MainView.swift**
```swift
onWalletReady: {
    Task {
        // Activate services now that wallet exists
        serviceContainer.setActive(true)
        
        // Configure services with model context
        serviceContainer.configureServices(with: modelContext)
        
        // ✅ NOW register device with ModelContext available
        if let hash = securityService.getMnemonicHash() {
            do {
                try await serviceContainer.deviceRegistrationService.registerCurrentDevice(
                    walletHash: hash,
                    hasSeed: true
                )
                print("✅ [MainView] Device registered successfully after wallet creation")
            } catch {
                print("⚠️ [MainView] Device registration failed: \(error)")
                // Non-fatal - continue anyway
                // Will retry on next app launch
            }
        }
        
        // Initialize the wallet after creation
        await walletManager.initialize()
        hasWallet = true
    }
}
```

---

## Files Requiring Changes

| File | Change | Lines |
|------|--------|-------|
| `SecurityService.swift` | Remove device registration from `saveMnemonic()` | 228-243 |
| `SecurityService.swift` | Add `getMnemonicHash()` helper method | New |
| `MainView.swift` | Add device registration to `onWalletReady()` callback | ~49 |

---

## Testing Checklist

- [ ] Create new wallet and verify device registration succeeds
- [ ] Check that device appears in device list immediately
- [ ] Verify device heartbeat starts working
- [ ] Test with network issues (registration should fail gracefully)
- [ ] Confirm wallet creation still succeeds if registration fails
- [ ] Verify error logging works correctly

---

## Alignment with Architecture Recommendations

This fix directly implements:
- **INITIALIZATION_FLOWS.md Recommendation #5:** "Make device registration fully asynchronous"
- Moves device registration out of critical wallet creation path
- Allows wallet creation to succeed even if registration fails
- Makes device registration non-blocking

---

## Related Documents

- `INITIALIZATION_FLOWS.md` - Full initialization architecture
- `../Archive/Implementations/DEVICE_REGISTRY_PHASE1_SUMMARY.md` - Device registry implementation
- `ISSUE_2_ADDRESS_GENERATION.md` - Address generation connection issue

---

**Status:** Ready for implementation
