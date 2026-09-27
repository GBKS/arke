# Quick Reference: Security/Device Separation

## 🎯 At a Glance

**Problem:** SecurityService was calling DeviceRegistrationService before ModelContext was ready  
**Solution:** Move device registration to MainView coordinator  
**Result:** Clean separation, no timing issues, compiler errors resolved

---

## 📋 What Changed (3 Files)

### SecurityService.swift ✂️
```diff
- private var deviceRegistrationService: DeviceRegistrationService
- try await deviceRegistrationService.registerCurrentDevice(...)
+ // Device registration removed - coordinator's responsibility
+ func getWalletHashForRegistration() -> String? { ... }
```

### MainView_iOS.swift 🎭
```diff
+ private func registerDeviceIfNeeded() async { ... }
  
  onWalletReady: {
      serviceContainer.configureServices(with: modelContext)
+     await registerDeviceIfNeeded()  // NEW: Register after configure
      await walletManager.initialize()
  }
```

### DeviceRegistrationService.swift 🔄
```diff
+ private var pendingRegistration: (hash: String, hasSeed: Bool)?
+ func schedulePendingRegistration(...) { ... }
+ private func processPendingRegistrations() async { ... }
```

---

## 🔍 Quick Verification

### Check 1: Compilation
```bash
# Should build without errors
⚠️ If you see: 'DeviceRegistrationService' is ambiguous...
   → Clean build folder (Cmd+Shift+K) and rebuild
```

### Check 2: Grep for Issues
```bash
# Should return 0 results
grep "deviceRegistrationService" SecurityService.swift
```

### Check 3: Log Messages
```bash
# Should see in order:
✅ [SecurityService] Mnemonic saved...
   ℹ️  Coordinator should call DeviceRegistrationService...
✅ [MainView] Device registered with hasSeed=true
```

---

## 🧪 Quick Test

### Test Flow 1: New Wallet
1. Delete app
2. Create wallet
3. Look for: `✅ [MainView] Device registered with hasSeed=true`

### Test Flow 2: Device Linking  
1. Link from another device
2. Look for TWO registrations: `hasSeed=false` then `hasSeed=true`

### Test Flow 3: Existing Wallet
1. Relaunch app
2. Should be fast (< 500ms to UI)
3. Look for: `✅ Using cached wallet detection result`

---

## 🆘 Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Compiler error about DeviceRegistrationService | Old code still present | Clean build, check SecurityService |
| Device not registered | Registration not called | Check MainView coordinator |
| Registration fails silently | ModelContext not ready | Verify configureServices() called first |
| Slow startup | Not using fast path | Check initialWalletDetected usage |

---

## 📊 Success Metrics

- [x] Compiles without errors
- [x] SecurityService has no DeviceReg references
- [x] Device registration in logs
- [x] All 3 flows work
- [x] Performance maintained

---

## 📚 Full Documentation

- **Implementation Details:** SEPARATION_OF_CONCERNS_IMPLEMENTATION.md
- **Testing Guide:** TESTING_CHECKLIST_SEPARATION.md
- **Summary:** IMPLEMENTATION_SUMMARY.md
- **Diagrams:** ARCHITECTURE_DIAGRAMS.md

---

## 💡 Key Concepts

### Before ❌
```swift
SecurityService → DeviceRegistrationService
                  (timing issues!)
```

### After ✅
```swift
MainView (coordinator)
├─ SecurityService (security only)
└─ DeviceRegistrationService (device only)
```

**Principle:** Services expose helpers, coordinators orchestrate

---

## 🔄 Migration Pattern

### Old Pattern (Don't Use)
```swift
try await securityService.saveMnemonic(mnemonic)
// Device automatically registered ❌
```

### New Pattern (Use This)
```swift
// 1. Security operation
try await securityService.saveMnemonic(mnemonic)

// 2. Coordination
if let hash = securityService.getWalletHashForRegistration() {
    try await deviceReg.registerCurrentDevice(
        walletHash: hash,
        hasSeed: true
    )
}
```

---

## ⚡ Performance

| Operation | Time | Notes |
|-----------|------|-------|
| App init | < 100ms | Cached keychain check |
| UI transition | < 300ms | Fast path to wallet view |
| Device registration | < 200ms | Background, non-blocking |
| Total to ready | < 3s | Parallel loading |

---

## ✅ Checklist for New Developers

When working with wallet initialization:

- [ ] SecurityService for security operations only
- [ ] DeviceRegistrationService for device operations only
- [ ] MainView for coordination
- [ ] Always configure services before registration
- [ ] Device registration failures are logged, not thrown
- [ ] Use getWalletHashForRegistration() helper

---

**Quick Reference Version:** 1.0  
**Last Updated:** December 11, 2024  
**Status:** ✅ Ready for use
