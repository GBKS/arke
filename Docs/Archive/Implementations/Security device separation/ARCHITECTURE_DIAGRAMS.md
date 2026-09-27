# Architecture Diagram: Before & After

## 🏗️ System Architecture Changes

---

## BEFORE: Problematic Architecture ❌

```
┌─────────────────────────────────────────────────────────────┐
│                        App Launch                            │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Arke_mobile.swift                                      │  │
│  │  - Early wallet detection                              │  │
│  │  - ServiceContainer creation                           │  │
│  └────────────────────────────────────────────────────────┘  │
│                            ↓                                 │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ MainView_iOS                                           │  │
│  │  - checkForExistingWallet()                            │  │
│  │  - onWalletReady()                                     │  │
│  └────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↓
        ┌───────────────────┴───────────────────┐
        ↓                                       ↓
┌─────────────────────┐              ┌──────────────────────┐
│  SecurityService    │              │  ServiceContainer    │
│                     │              │                      │
│  ❌ Has reference to│              │  - setActive()       │
│     DeviceReg       │              │  - configure()       │
│                     │              │                      │
│  Methods:           │              └──────────────────────┘
│  - saveMnemonic()   │──────┐                    │
│  - detectState()    │──────┼────────────────────┤
│  - handleImport()   │──────┤                    │
│  - getDeletion()    │──────┤                    │
│  - deleteWallet()   │──────┤                    ↓
│                     │      │       ┌──────────────────────┐
└─────────────────────┘      │       │ DeviceRegistration   │
                             │       │ Service              │
                             │       │                      │
                             └──────→│  ❌ Called BEFORE    │
                                     │     ModelContext     │
                                     │     ready!           │
                                     │                      │
                                     │  ❌ Timing issues    │
                                     │  ❌ Race conditions  │
                                     └──────────────────────┘
                                              ↓
                                     ⚠️  Requires ModelContext
                                     ⚠️  Not always available
                                     ❌  AMBIGUITY ERROR
```

### Problems:
1. ❌ `SecurityService` directly calls `DeviceRegistrationService`
2. ❌ `DeviceRegistrationService` requires `ModelContext`
3. ❌ `ModelContext` not guaranteed to be ready when called
4. ❌ Hidden timing dependencies
5. ❌ Mixed responsibilities (security + device management)
6. ❌ Tight coupling between services

---

## AFTER: Clean Architecture ✅

```
┌─────────────────────────────────────────────────────────────┐
│                        App Launch                            │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Arke_mobile.swift                                      │  │
│  │  - Early wallet detection                              │  │
│  │  - ServiceContainer creation                           │  │
│  └────────────────────────────────────────────────────────┘  │
│                            ↓                                 │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ MainView_iOS (COORDINATOR) 🎭                          │  │
│  │                                                         │  │
│  │  ✅ Orchestrates initialization sequence               │  │
│  │  ✅ Guarantees proper timing                           │  │
│  │                                                         │  │
│  │  Methods:                                              │  │
│  │  - checkForExistingWallet()                            │  │
│  │  - onWalletReady()                                     │  │
│  │  - registerDeviceIfNeeded() ← NEW COORDINATOR          │  │
│  │                                                         │  │
│  │  Sequence:                                             │  │
│  │  1. Configure services (ModelContext ready)            │  │
│  │  2. Register device (NOW safe to call)                 │  │
│  │  3. Initialize wallet                                  │  │
│  └────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
         ↓                    ↓                    ↓
         │                    │                    │
    ┌────┴─────┐         ┌───┴────┐          ┌────┴─────┐
    ↓          ↓         ↓        ↓          ↓          ↓

┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Security     │    │ Service      │    │ Device       │
│ Service      │    │ Container    │    │ Registration │
│              │    │              │    │ Service      │
│ ✅ PURE      │    │ ✅ Provides  │    │              │
│    Security  │    │    Context   │    │ ✅ Receives  │
│              │    │              │    │    Context   │
│ Methods:     │    │ Methods:     │    │    FIRST     │
│ - keychain   │    │ - setActive()│    │              │
│ - crypto     │    │ - configure()│    │ Methods:     │
│ - detection  │    │              │    │ - register() │
│ - biometric  │    └──────────────┘    │ - heartbeat()│
│              │                        │ - unlink()   │
│ ✅ NO device │                        │              │
│    reg calls │                        │ ✅ ONLY      │
│              │                        │    Device    │
│ Helper:      │                        │    Lifecycle │
│ - getHash()  │                        │              │
│              │                        └──────────────┘
└──────────────┘                              ↓
                                     ✅  ModelContext
                                     ✅  Always ready
                                     ✅  No timing issues
```

### Improvements:
1. ✅ Clear separation: Security vs Device Management
2. ✅ Coordinator pattern: MainView orchestrates
3. ✅ Guaranteed sequencing: Configure → Register → Initialize
4. ✅ No direct service-to-service calls
5. ✅ Single responsibility per service
6. ✅ Explicit dependencies

---

## 📊 Sequence Diagrams

### Flow 1: New Wallet Creation

#### BEFORE ❌
```
User → CreateWallet → SecurityService.saveMnemonic()
                            ↓
                    ❌ Calls DeviceRegistrationService
                            ↓
                    ❌ No ModelContext yet!
                            ↓
                    ❌ Silent failure or crash
```

#### AFTER ✅
```
User → CreateWallet → SecurityService.saveMnemonic()
                            ↓
                    ✅ Only saves to keychain
                            ↓
       MainView.onWalletReady()
                ↓
       ServiceContainer.configureServices() ← ModelContext ready!
                ↓
       MainView.registerDeviceIfNeeded()
                ↓
       DeviceRegistrationService.register()
                ↓
       ✅ Success! Device registered
```

---

### Flow 2: Wallet Detection (Existing Wallet)

#### BEFORE ❌
```
MainView → SecurityService.detectWalletState()
                    ↓
            ❌ Calls DeviceRegistrationService
                    ↓
            ❌ Might fail if context not ready
                    ↓
            ❌ Unpredictable behavior
```

#### AFTER ✅
```
MainView → SecurityService.detectWalletState()
                    ↓
            ✅ Returns WalletState only
                    ↓
       MainView.registerDeviceIfNeeded()
                    ↓
       Gets hash from SecurityService
                    ↓
       DeviceRegistrationService.register()
                    ↓
       ✅ Success! Device registered
```

---

## 🔄 Data Flow

### BEFORE: Hidden Dependencies ❌

```
┌────────────┐       ┌──────────────┐       ┌──────────────┐
│            │───1───│              │───2───│              │
│ Security   │       │   Device     │       │ ModelContext │
│ Service    │       │   Reg        │       │              │
│            │◄──X───│              │◄──?───│              │
└────────────┘       └──────────────┘       └──────────────┘

1. SecurityService calls DeviceReg
2. DeviceReg needs ModelContext
X. Might not be ready → ERROR!
```

### AFTER: Explicit Flow ✅

```
┌────────────┐       ┌──────────────┐       ┌──────────────┐
│            │       │              │       │              │
│ Security   │       │  Coordinator │       │   Device     │
│ Service    │       │  (MainView)  │       │   Reg        │
│            │       │              │       │              │
└────────────┘       └──────────────┘       └──────────────┘
      │                     │                      │
      │ getHash()           │                      │
      │─────────────────────▶                      │
      │                     │                      │
      │                     │ configure()          │
      │                     │─────────────────────▶│
      │                     │                      │
      │                     │ register(hash)       │
      │                     │─────────────────────▶│
      │                     │                      │
      │                     │         ✅ Success   │
      │                     │◄─────────────────────│
      │                     │                      │

✅ Coordinator ensures proper sequence
✅ ModelContext ready before registration
✅ Clean separation of concerns
```

---

## 🎯 Responsibility Matrix

| Operation | BEFORE | AFTER |
|-----------|--------|-------|
| **Keychain Operations** | SecurityService | SecurityService ✅ |
| **Wallet Detection** | SecurityService | SecurityService ✅ |
| **Device Registration** | SecurityService ❌ | MainView ✅ |
| **Registration Timing** | Implicit ❌ | Explicit ✅ |
| **ModelContext Guarantee** | None ❌ | Coordinator ✅ |
| **Service Coordination** | Services call each other ❌ | Coordinator orchestrates ✅ |

---

## 📐 Dependency Graph

### BEFORE: Circular ❌
```
┌─────────────┐
│ Security    │───┐
└─────────────┘   │
       ▲          │
       │          ▼
       │   ┌──────────────┐
       │   │ DeviceReg    │
       │   └──────────────┘
       │          │
       │          ▼
       │   ┌──────────────┐
       └───│ ModelContext │
           └──────────────┘

❌ Circular dependency
❌ Hidden timing issues
```

### AFTER: Tree ✅
```
           ┌──────────────┐
           │ MainView     │
           │ (Coordinator)│
           └──────────────┘
                  │
        ┌─────────┼─────────┐
        ▼         ▼         ▼
┌─────────┐ ┌─────────┐ ┌─────────┐
│Security │ │Service  │ │DeviceReg│
│Service  │ │Container│ │Service  │
└─────────┘ └─────────┘ └─────────┘

✅ Tree structure
✅ No cycles
✅ Clear dependencies
```

---

## 🔧 Implementation Pattern

### Service Interface Pattern

**Security Service (Provider):**
```swift
// Provides data, doesn't make decisions
func getWalletHashForRegistration() -> String? {
    return getUbiquitousHash() ?? getLocalHash()
}
```

**Coordinator (Consumer):**
```swift
// Makes decisions, orchestrates operations
private func registerDeviceIfNeeded() async {
    guard let hash = securityService.getWalletHashForRegistration() else {
        return
    }
    
    let hasSeed = securityService.hasMnemonic()
    
    try await deviceRegistrationService.registerCurrentDevice(
        walletHash: hash,
        hasSeed: hasSeed
    )
}
```

### Benefits:
- ✅ Services don't call each other
- ✅ Coordinator controls flow
- ✅ Easy to test
- ✅ Easy to reason about
- ✅ No hidden dependencies

---

## 🎓 Design Principles Applied

1. **Single Responsibility Principle**
   - SecurityService → Security only
   - DeviceRegistrationService → Device lifecycle only
   - MainView → Coordination only

2. **Separation of Concerns**
   - Security ≠ Device Management
   - Clear domain boundaries

3. **Dependency Inversion**
   - Services expose helpers
   - Coordinators compose operations
   - No tight coupling

4. **Explicit Over Implicit**
   - Initialization sequence visible
   - Timing guarantees explicit
   - No magic happening behind the scenes

---

## ✅ Verification Checklist

After reviewing this diagram, you should be able to answer:

- [ ] Why was `SecurityService` calling `DeviceRegistrationService`?
- [ ] What problems did this cause?
- [ ] How does the coordinator pattern solve this?
- [ ] What is the correct sequence now?
- [ ] Why is this better for testing?
- [ ] Why is this better for maintenance?

---

**Diagram Version:** 1.0  
**Last Updated:** December 11, 2024  
**Related Docs:** 
- SEPARATION_OF_CONCERNS_IMPLEMENTATION.md
- IMPLEMENTATION_SUMMARY.md
- TESTING_CHECKLIST_SEPARATION.md
