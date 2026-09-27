# Testing Checklist: Security/Device Separation

> ⚠️ **DEPRECATION NOTICE**: This document references `LinkWalletView` test cases which are no longer applicable. LinkWalletView was removed in June 2026 in favor of automatic iCloud Keychain sync. Device linking test cases should focus on the Device Registry system instead.

## Quick Test Guide

After implementing the separation of security operations from device management, follow this checklist to verify everything works correctly.

---

## 🔍 What Changed?

- `SecurityService` no longer calls `DeviceRegistrationService`
- `MainView` now coordinates device registration
- Device registration happens AFTER `ServiceContainer.configureServices()`

---

## ✅ Pre-Test Verification

### 1. Code Compilation
- [ ] Project builds without errors
- [ ] No compiler warnings about `DeviceRegistrationService` ambiguity
- [ ] No SwiftData-related errors in SecurityService

### 2. Quick Code Review
- [ ] `SecurityService.swift` has no `deviceRegistrationService` references
- [ ] `MainView_iOS.swift` has `registerDeviceIfNeeded()` method
- [ ] `DeviceRegistrationService.swift` has lazy registration pattern

---

## 🧪 Flow Testing

### Flow 1: New Wallet Creation ✨

**Purpose:** Verify wallet creation from scratch works and device gets registered

**Steps:**
1. Delete app from device completely (long press → delete)
2. Reinstall and launch app
3. Tap "Create new wallet"
4. Complete wallet creation flow
5. Verify wallet view appears

**Expected Logs (in order):**
```
🔍 [SecurityService.static] Keychain mnemonic check: ⚠️ Not found
⏭️ [MainView] No wallet hash available for device registration
✅ [SecurityService] Mnemonic saved to keychain and hash saved to ubiquitous store
   ℹ️  Coordinator should call DeviceRegistrationService.registerCurrentDevice() next
✅ [MainView] Device registered with hasSeed=true
✅ [DeviceRegistrationService] Registered current device
```

**Verification:**
- [ ] Wallet view appears
- [ ] No crashes or errors
- [ ] Device registration log appears AFTER mnemonic saved
- [ ] Device appears in device list (if UI available)

**Common Issues:**
- ❌ If "No wallet hash available": Check that hash is saved to ubiquitous store
- ❌ If device registration fails: Check that ModelContext was configured first

---

### Flow 2: Device Linking 🔗

**Purpose:** Verify linking wallet from another device works

**Prerequisites:**
- Device A has existing wallet with recovery phrase

**Steps on Device B:**
1. Delete app completely
2. Reinstall and launch app
3. Wait for "Link existing wallet" option to appear (may take 10-30 seconds for iCloud sync)
4. Tap "Link existing wallet"
5. Scan QR code from Device A
6. Complete linking flow
7. Verify wallet view appears with synced data

**Expected Logs (Device B, in order):**
```
🔍 [SecurityService.static] Keychain mnemonic check: ⚠️ Not found
✅ [SecurityService] Retrieved hash from NSUbiquitousKeyValueStore
⚠️ Wallet found on another device, but no seed locally
✅ [MainView] Device registered with hasSeed=false
✅ [SecurityService] Seed imported - coordinator should update device registration
✅ [MainView] Device registered with hasSeed=true
✅ [DeviceRegistrationService] Updated existing device registration
```

**Verification:**
- [ ] "Link wallet" option appears (may take time for iCloud sync)
- [ ] QR scan works
- [ ] Wallet view appears
- [ ] Device registered TWICE (first hasSeed=false, then hasSeed=true)
- [ ] Transactions sync from Device A
- [ ] Both devices appear in device list

**Common Issues:**
- ❌ If link option doesn't appear: Wait longer for iCloud KVS sync (can take minutes)
- ❌ If second registration doesn't happen: Check onWalletReady callback

---

### Flow 3: Existing Wallet (Fast Path) ⚡

**Purpose:** Verify returning user experience is still fast

**Prerequisites:**
- Device already has wallet

**Steps:**
1. Force quit app
2. Launch app
3. Observe startup time
4. Verify wallet view appears quickly

**Expected Logs (in order):**
```
🔍 [SecurityService.static] Keychain mnemonic check: ✅ Found
✅ Using cached wallet detection result: wallet exists
✅ [MainView] Device registered with hasSeed=true
🔧 [MainView_iOS] Initializing wallet in detached background task...
✅ [MainView_iOS] Wallet initialization complete
```

**Verification:**
- [ ] Wallet view appears in < 500ms
- [ ] No redundant wallet detection
- [ ] Device registration happens quickly
- [ ] Heartbeat updates (check device list timestamp)

**Performance Target:**
- App launch to UI: < 300ms
- Total initialization: < 3s

**Common Issues:**
- ❌ If slow: Check if detectWalletState is being called (shouldn't be)
- ❌ If device not registered: Check fast path code in checkForExistingWallet

---

## 🔍 Log Monitoring Guide

### Logs You SHOULD See

**SecurityService (no registration):**
```
✅ [SecurityService] Mnemonic saved to keychain and hash saved to ubiquitous store
   ℹ️  Coordinator should call DeviceRegistrationService.registerCurrentDevice() next
```

**MainView (handles registration):**
```
✅ [MainView] Device registered with hasSeed=true
```
or
```
✅ [MainView] Device registered with hasSeed=false
```

**DeviceRegistrationService (confirms registration):**
```
✅ [DeviceRegistrationService] Registered current device
```
or
```
✅ [DeviceRegistrationService] Updated existing device registration
```

### Logs You Should NOT See

**❌ In SecurityService:**
```
✅ [SecurityService] Device registered with hasSeed=true
⚠️ [SecurityService] Failed to register device
```

If you see these, the old code is still running!

---

## 🐛 Troubleshooting

### Issue: Compiler Error about DeviceRegistrationService

**Symptoms:**
- Build fails with "DeviceRegistrationService is ambiguous for type lookup"

**Solution:**
- Clean build folder (Cmd+Shift+K)
- Restart Xcode
- Verify SecurityService.swift has no `deviceRegistrationService` references

---

### Issue: Device Not Registered

**Symptoms:**
- Wallet works but device doesn't appear in registry
- Logs show: `⏭️ [MainView] No wallet hash available for device registration`

**Possible Causes:**
1. Hash not saved to ubiquitous store
2. ModelContext not configured before registration
3. Registration call not happening in coordinator

**Debug Steps:**
1. Check if `saveHashToUbiquitousStore()` was called
2. Verify `ServiceContainer.configureServices()` before `registerDeviceIfNeeded()`
3. Check if `registerDeviceIfNeeded()` is actually called
4. Look for errors in DeviceRegistrationService

---

### Issue: Registration Happens Too Early

**Symptoms:**
- Logs show: `⚠️ [DeviceRegistrationService] No model context available`
- Device registration fails silently

**Solution:**
- Verify registration happens AFTER `ServiceContainer.configureServices()`
- Check initialization sequence in MainView
- Use lazy registration pattern if timing uncertain

---

### Issue: Slow Startup After Changes

**Symptoms:**
- Wallet view takes > 1 second to appear
- More operations happening than before

**Possible Causes:**
1. Registration happening on main thread
2. Not using fast path for existing wallet
3. Redundant wallet detection

**Debug Steps:**
1. Check if `initialWalletDetected` is being used
2. Verify registration is async (shouldn't block UI)
3. Profile app launch time

---

## 📊 Success Metrics

After testing all three flows:

### Must Pass ✅
- [ ] All three flows work without crashes
- [ ] Device registration happens in all flows
- [ ] No compiler errors or warnings
- [ ] No SwiftData errors in SecurityService

### Performance ⚡
- [ ] Flow 3 (existing wallet) still fast (< 500ms to UI)
- [ ] Device registration doesn't block UI
- [ ] Background initialization still works

### Code Quality 🎨
- [ ] SecurityService has no DeviceRegistrationService references
- [ ] Clear separation between security and device management
- [ ] Proper coordinator pattern in MainView

---

## 📝 Test Results Template

Copy and fill out after testing:

```
## Test Results - [Date]

### Flow 1: New Wallet Creation
- Status: ⬜ Pass ⬜ Fail
- Issues: 
- Notes:

### Flow 2: Device Linking
- Status: ⬜ Pass ⬜ Fail
- Issues:
- Notes:

### Flow 3: Existing Wallet
- Status: ⬜ Pass ⬜ Fail
- Issues:
- Performance (ms to UI):
- Notes:

### Overall Assessment
- All flows work: ⬜ Yes ⬜ No
- Performance acceptable: ⬜ Yes ⬜ No
- Ready for production: ⬜ Yes ⬜ No

### Recommendations
-
-
```

---

## 🚀 Post-Testing

After successful testing:

1. **Document Results**
   - Fill out test results template
   - Note any issues or edge cases
   - Record performance metrics

2. **Update Related Code**
   - Check if any other views call SecurityService methods
   - Update deletion flows if needed
   - Review QR code scanning flow

3. **Consider Follow-ups**
   - Add integration tests for flows
   - Add health check for registration status
   - Consider migration logic for existing users

---

**Testing Guide Version:** 1.0  
**Last Updated:** December 11, 2024
