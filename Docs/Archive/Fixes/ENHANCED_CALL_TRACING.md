# Enhanced Call Tracing for Initialization

## Overview
Added detailed call tracing to track the source of all initialization-related calls. This makes it trivial to see the complete call chain for debugging double initialization issues.

## Functions with Enhanced Tracing

### 1. `WalletManager.initialize()`
**Parameters added:**
- `caller: String = #function` - The calling function name
- `file: String = #file` - The file path where it was called
- `line: Int = #line` - The line number where it was called

**Log Output:**
```txt
🔧 [WalletManager] 📞 initialize() CALLED
   ├─ Time: 2025-12-11 14:41:55 +0000
   ├─ From: MainView_iOS.swift:102
   └─ Function: onWalletReady
```

---

### 2. `WalletManager.refresh()`
**Parameters added:**
- `caller: String = #function` - The calling function name
- `file: String = #file` - The file path where it was called
- `line: Int = #line` - The line number where it was called

**Log Output:**
```txt
🔄 [WalletManager] 📞 refresh() CALLED
   ├─ From: WalletView_iOS.swift:295
   └─ Function: task()
```

---

### 3. `WalletManager.setModelContext()`
**Parameters added:**
- `caller: String = #function` - The calling function name
- `file: String = #file` - The file path where it was called
- `line: Int = #line` - The line number where it was called

**Log Output:**
```txt
🔧 [WalletManager] 📞 setModelContext() CALLED
   ├─ From: MainView_iOS.swift:126
   └─ Function: task()
```

---

### 4. `ServiceContainer.configureServices()`
**Parameters added:**
- `caller: String = #function` - The calling function name
- `file: String = #file` - The file path where it was called
- `line: Int = #line` - The line number where it was called

**Log Output:**
```txt
🔧 [ServiceContainer] 📞 configureServices() CALLED
   ├─ From: WalletManager.swift:313
   └─ Function: setModelContext(caller:file:line:)
```

---

## Call Chain Examples

### Expected Flow: Fresh Wallet Creation

```txt
[User creates wallet]

🔧 [MainView_iOS] 📞 Calling serviceContainer.configureServices()...
🔧 [ServiceContainer] 📞 configureServices() CALLED
   ├─ From: MainView_iOS.swift:86
   └─ Function: onWalletReady

[Services configured]

🔧 [MainView_iOS] 📍 CALL #3: Initializing newly created wallet...
   └─ Location: MainView_iOS onWalletReady callback (OnboardingFlow_iOS)

🔧 [WalletManager] 📞 initialize() CALLED
   ├─ Time: 2025-12-11 14:41:55 +0000
   ├─ From: MainView_iOS.swift:102
   └─ Function: onWalletReady

[... initialization happens ...]

✅ [MainView_iOS] 📍 CALL #3: New wallet initialization complete

[WalletView appears]

⏭️ [WalletView_iOS] 📍 SKIP: Skipping refresh (hasAppearedBefore=false)
   └─ Data already loaded by MainView_iOS initialization
```

---

### Debugging: Finding Double Initialization

**Scenario:** If we see two `initialize()` calls, the logs will now show exactly where each came from:

```txt
🔧 [WalletManager] 📞 initialize() CALLED  ← First call
   ├─ Time: 2025-12-11 14:41:55 +0000
   ├─ From: MainView_iOS.swift:102
   └─ Function: onWalletReady
[... first initialization ...]

🔧 [WalletManager] 📞 initialize() CALLED  ← Second call (unexpected!)
   ├─ Time: 2025-12-11 14:41:59 +0000
   ├─ From: SomeOtherFile.swift:XYZ  ← This tells us the culprit!
   └─ Function: suspiciousFunction
```

---

### Tracking configureServices() Duplicates

If services are configured twice, we can now see both call sites:

```txt
🔧 [ServiceContainer] 📞 configureServices() CALLED  ← First call
   ├─ From: MainView_iOS.swift:86
   └─ Function: onWalletReady
[... services configured ...]

🔧 [ServiceContainer] 📞 configureServices() CALLED  ← Second call (duplicate!)
   ├─ From: WalletManager.swift:313
   └─ Function: setModelContext(caller:file:line:)
```

**This reveals:** `setModelContext` is calling `configureServices` again!

---

## How to Use the Tracing

### Step 1: Identify the Problem
Look for duplicate calls with the **📞** emoji:
```txt
🔧 [WalletManager] 📞 initialize() CALLED
🔧 [WalletManager] 📞 initialize() CALLED  ← Duplicate!
```

### Step 2: Compare the Call Sites
Check the `From:` line to see where each call originated:
```txt
First:  From: MainView_iOS.swift:102
Second: From: WalletView_iOS.swift:295
```

### Step 3: Check the Function Context
The `Function:` line shows the calling function:
```txt
First:  Function: onWalletReady
Second: Function: task()
```

### Step 4: Fix the Root Cause
Now you know:
- **Which file** made the call
- **Which line** in that file
- **Which function** was executing
- **When** it happened (timestamp)

---

## Benefits

### For Debugging
- ✅ **Instant identification** of call origin
- ✅ **See call ordering** with timestamps
- ✅ **Compare duplicate calls** side-by-side
- ✅ **No manual code tracing** needed

### For Testing
- ✅ **Verify expected call sites** match actual
- ✅ **Detect unexpected callers** immediately
- ✅ **Track regression** if new call sites appear
- ✅ **Document actual behavior** through logs

### For Code Review
- ✅ **Show initialization flow** to reviewers
- ✅ **Prove fix effectiveness** with before/after logs
- ✅ **Identify architectural issues** (wrong layers calling each other)

---

## Expected Log Output After Adding Tracing

### Fresh Wallet Creation (Complete Flow)

```txt
[App Launch - No Wallet]

🔍 [MainView_iOS] 📞 Calling walletManager.setModelContext()...
🔧 [WalletManager] 📞 setModelContext() CALLED
   ├─ From: MainView_iOS.swift:126
   └─ Function: task()
⏭️ Skipping service configuration - container is passive
🔍 [MainView_iOS] Model context set at 2025-12-11 14:40:16 +0000

[User Creates Wallet]

✅ ServiceContainer activated - services will load and sync data

🔧 [MainView_iOS] 📞 Calling serviceContainer.configureServices()...
🔧 [ServiceContainer] 📞 configureServices() CALLED
   ├─ From: MainView_iOS.swift:86
   └─ Function: onWalletReady
📋 [TagService] Started observing CloudKit changes (debounced)
👥 [ContactService] Started observing CloudKit changes (debounced)

🔧 [MainView_iOS] 📍 CALL #3: Initializing newly created wallet...
   └─ Location: MainView_iOS onWalletReady callback (OnboardingFlow_iOS)

🔧 [WalletManager] 📞 initialize() CALLED
   ├─ Time: 2025-12-11 14:41:55 +0000
   ├─ From: MainView_iOS.swift:102
   └─ Function: onWalletReady

🔧 [WalletManager] initialize execute at 2025-12-11 14:41:55 +0000
[... initialization ...]
✅ [MainView_iOS] 📍 CALL #3: New wallet initialization complete

[WalletView Appears]

⏭️ [WalletView_iOS] 📍 SKIP: Skipping refresh (hasAppearedBefore=false)
   └─ Data already loaded by MainView_iOS initialization
```

**If a second initialize appears:**
```txt
[4 seconds later...]

🔧 [ServiceContainer] 📞 configureServices() CALLED  ← Unexpected!
   ├─ From: WalletManager.swift:313
   └─ Function: setModelContext(caller:file:line:)

🔧 [WalletManager] 📞 initialize() CALLED  ← Second init!
   ├─ Time: 2025-12-11 14:41:59 +0000
   ├─ From: SomeView.swift:XYZ  ← This is the culprit!
   └─ Function: mysteryFunction
```

Now we can **instantly** see that `SomeView.swift` line `XYZ` is calling something that triggers initialization!

---

## Tracing Implementation Details

### Using Swift's Compiler Literals

The tracing uses Swift's built-in compiler literals:
- `#function` - Captures the calling function name
- `#file` - Captures the file path
- `#line` - Captures the line number

**Key advantage:** These are evaluated at the **call site**, not inside the function, so they show the caller's information.

### Default Parameters

All tracing parameters have default values, so existing code doesn't need to change:

```swift
// Old call (still works):
await walletManager.initialize()

// Behind the scenes, Swift expands this to:
await walletManager.initialize(
    caller: "onWalletReady",
    file: "/path/to/MainView_iOS.swift",
    line: 102
)
```

### Filename Extraction

```swift
let fileName = (file as NSString).lastPathComponent
```

This converts `/path/to/MainView_iOS.swift` → `MainView_iOS.swift` for cleaner logs.

---

## Files Changed
- `WalletManager.swift`
  - Added tracing to `initialize()`
  - Added tracing to `refresh()`
  - Added tracing to `setModelContext()`
- `ServiceContainer.swift`
  - Added tracing to `configureServices()`
- `MainView_iOS.swift`
  - Added logging before `setModelContext()` call
  - Added logging before `configureServices()` call

## Date
December 11, 2025

## Status
✅ **IMPLEMENTED** - Ready for testing
