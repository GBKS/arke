# Enhanced Initialization Logging

## Overview
Added clear, visual logging to track wallet initialization and refresh calls throughout the app lifecycle. This makes it easy to understand what's happening without tracing through code.

## Logging Convention

All initialization-related logs now use the **📍** pin emoji to mark important lifecycle events:

- **📍 CALL #N**: Marks a call to `walletManager.initialize()`
- **📍 REFRESH**: Marks a call to `walletManager.refresh()`
- **📍 SKIP**: Marks when a refresh is intentionally skipped

Each log includes:
1. The action being taken
2. The location in code where it's called from
3. Relevant state information (e.g., `hasLoadedOnce`)

---

## Initialization Call Points

### CALL #1: Cached Wallet Detection
**Location:** `MainView_iOS.swift` - Cached detection path (line ~145)

**When:** App startup with existing wallet (fast path using cached detection)

**Log Output:**
```txt
🔧 [MainView_iOS] 📍 CALL #1: Initializing wallet in detached background task... at 2025-12-11 14:27:02 +0000
   └─ Location: MainView_iOS cached detection path
🔧 [WalletManager] initialize at 2025-12-11 14:27:02 +0000
🔧 [WalletManager] initialize execute at 2025-12-11 14:27:02 +0000
[... wallet initialization happens ...]
✅ [MainView_iOS] 📍 CALL #1: Wallet initialization complete at 2025-12-11 14:27:03 +0000
```

---

### CALL #2: Deep Wallet Detection
**Location:** `MainView_iOS.swift` - Deep detection path (line ~242)

**When:** Wallet found during deeper detection (edge case for wallets on other devices)

**Log Output:**
```txt
🔧 [MainView_iOS] 📍 CALL #2: Initializing wallet in detached background task... at 2025-12-11 14:27:02 +0000
   └─ Location: MainView_iOS deep detection path (walletWithSeed)
🔧 [WalletManager] initialize at 2025-12-11 14:27:02 +0000
[... wallet initialization happens ...]
✅ [MainView_iOS] 📍 CALL #2: Wallet initialization complete
```

---

### CALL #3: New Wallet Creation
**Location:** `MainView_iOS.swift` - OnboardingFlow completion (line ~100)

**When:** User just created or imported a new wallet

**Log Output:**
```txt
🔧 [MainView_iOS] 📍 CALL #3: Initializing newly created wallet...
   └─ Location: MainView_iOS onWalletReady callback (OnboardingFlow_iOS)
🔧 [WalletManager] initialize at 2025-12-11 14:27:02 +0000
[... wallet initialization happens ...]
✅ [MainView_iOS] 📍 CALL #3: New wallet initialization complete
```

---

## Refresh Call Points

### REFRESH: WalletView Appearance (Active)
**Location:** `WalletView_iOS.swift` - .task block (line ~290)

**When:** 
- Returning from background
- View reappears after being off-screen
- User switches back to app

**Condition:** Only when `hasAppearedBefore == true`

**Log Output:**
```txt
🔄 [WalletView_iOS] 📍 REFRESH: Calling refresh() (hasAppearedBefore=true)
   └─ Location: WalletView_iOS .task block (subsequent appearance)
WalletManager.performRefresh
[... refresh operations ...]
✅ [WalletView_iOS] 📍 REFRESH: Complete
```

---

### SKIP: WalletView First Appearance
**Location:** `WalletView_iOS.swift` - .task block (line ~290)

**When:** WalletView appears for the first time after initialization

**Condition:** When `hasAppearedBefore == false`

**Log Output:**
```txt
⏭️ [WalletView_iOS] 📍 SKIP: Skipping refresh (hasAppearedBefore=false)
   └─ Data already loaded by MainView_iOS initialization
```

---

## Expected Log Sequences

### Scenario 1: Fresh Wallet Creation

```txt
[User creates wallet in onboarding]

✅ Wallet created: tree invest nature enact usage lake...
✅ ServiceContainer activated - services will load and sync data

[MainView_iOS transitions to WalletView_iOS]

🔧 [MainView_iOS] 📍 CALL #3: Initializing newly created wallet...
   └─ Location: MainView_iOS onWalletReady callback (OnboardingFlow_iOS)
🔧 [WalletManager] initialize at 2025-12-11 14:27:02 +0000
🔧 [WalletManager] initialize execute at 2025-12-11 14:27:02 +0000
🔧 [WalletManager] Starting initialization...
ℹ️ Wallet already open
✅ Wallet opened successfully
WalletManager.performRefresh
[... addresses, balances, transactions loaded ...]
✅ All wallet data refreshed successfully
🔧 [WalletManager] initialize execute done at 2025-12-11 14:27:03 +0000
✅ [MainView_iOS] 📍 CALL #3: New wallet initialization complete

[WalletView_iOS appears]

⏭️ [WalletView_iOS] 📍 SKIP: Skipping refresh (hasLoadedOnce=false)
   └─ Data already loaded by MainView_iOS initialization
```

**Key Points:**
- ✅ Single initialization (CALL #3)
- ✅ WalletView skips redundant refresh
- ✅ Clean, efficient startup

---

### Scenario 2: Existing Wallet Startup (Cached Detection)

```txt
[App launches with existing wallet]

🔍 [SecurityService.static] Keychain mnemonic check: ✅ Found
✅ [App Init] Wallet detected - services will be activated
✅ ServiceContainer activated - services will load and sync data

[MainView_iOS detects cached wallet]

✅ Using cached wallet detection result: wallet exists
🔍 [MainView_iOS] UI transition complete - wallet will initialize in true background

[MainView_iOS initializes in background]

🔧 [MainView_iOS] 📍 CALL #1: Initializing wallet in detached background task... at 2025-12-11 14:27:02 +0000
   └─ Location: MainView_iOS cached detection path
🔧 [WalletManager] initialize at 2025-12-11 14:27:02 +0000
🔧 [WalletManager] initialize execute at 2025-12-11 14:27:02 +0000
[... initialization happens ...]
✅ [MainView_iOS] 📍 CALL #1: Wallet initialization complete at 2025-12-11 14:27:03 +0000

[WalletView_iOS appears]

⏭️ [WalletView_iOS] 📍 SKIP: Skipping refresh (hasLoadedOnce=false)
   └─ Data already loaded by MainView_iOS initialization
```

**Key Points:**
- ✅ Single initialization (CALL #1)
- ✅ Fast path using cached detection
- ✅ WalletView correctly skips refresh

---

### Scenario 3: Return from Background

```txt
[App returns to foreground]

[WalletView_iOS .task fires]

🔄 [WalletView_iOS] 📍 REFRESH: Calling refresh() (hasLoadedOnce=true)
   └─ Location: WalletView_iOS .task block
WalletManager.performRefresh
🔧 Generating new address via FFI...
🔧 Fetching balance via FFI...
[... latest data loaded ...]
✅ All wallet data refreshed successfully
✅ [WalletView_iOS] 📍 REFRESH: Complete
```

**Key Points:**
- ✅ Refresh happens (hasLoadedOnce=true)
- ✅ Gets latest data from network
- ✅ Updates UI with fresh information

---

## Benefits

### For Debugging
- ✅ **Instantly identify** which code path triggered initialization
- ✅ **See at a glance** if refresh was called or skipped
- ✅ **Track timing** of initialization vs UI transitions
- ✅ **Verify fixes** for double initialization are working

### For Development
- ✅ **Understand flow** without reading code
- ✅ **Catch regressions** immediately in logs
- ✅ **Document behavior** through log output
- ✅ **Easier onboarding** for new developers

### For Testing
- ✅ **Clear test output** showing what happened
- ✅ **Easy verification** of expected behavior
- ✅ **Regression detection** if extra calls appear
- ✅ **Performance tracking** through timestamps

---

## Log Pattern Recognition

### ✅ Good: Single Initialization
```txt
📍 CALL #1 or CALL #3 (but not both)
   └─ [initialization happens]
📍 SKIP: Skipping refresh
```

### ❌ Bad: Double Initialization (Bug)
```txt
📍 CALL #1 or CALL #3
   └─ [initialization happens]
📍 REFRESH: Calling refresh()  ← Should be SKIP on first appearance!
   └─ [unnecessary refresh]
```

### ✅ Good: Refresh After Background
```txt
[App in foreground already]
📍 REFRESH: Calling refresh() (hasLoadedOnce=true)
   └─ [gets latest data]
```

---

## Testing Checklist

Use these log patterns to verify correct behavior:

### ✅ Fresh Wallet Creation
- [ ] See exactly one "📍 CALL #3" during creation
- [ ] See "📍 SKIP" when WalletView appears
- [ ] No "📍 REFRESH" on first appearance

### ✅ Existing Wallet Startup  
- [ ] See exactly one "📍 CALL #1" during startup
- [ ] See "📍 SKIP" when WalletView appears
- [ ] No "📍 REFRESH" on first appearance

### ✅ Background/Foreground
- [ ] See "📍 REFRESH" when returning from background
- [ ] See "(hasLoadedOnce=true)" in the log
- [ ] Refresh completes successfully

### ✅ Wallet Linking
- [ ] See exactly one "📍 CALL #2" after linking
- [ ] See "📍 SKIP" when WalletView appears
- [ ] No duplicate initialization

---

## Files Changed
- `MainView_iOS.swift` - Added CALL #1, CALL #2, CALL #3 logging
- `WalletView_iOS.swift` - Added REFRESH and SKIP logging

## Date
December 11, 2025

## Status
✅ **IMPLEMENTED** - Ready for testing
