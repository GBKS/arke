# Double Initialization Fix - Corrected Implementation

## The Problem Discovered

After adding enhanced logging, we discovered that our first fix attempt **didn't work**. The logs showed:

```txt
🔧 [MainView_iOS] 📍 CALL #3: Initializing newly created wallet...
🔧 [WalletManager] initialize execute at 2025-12-11 14:35:54 +0000
[... initialization completes ...]
✅ [MainView_iOS] 📍 CALL #3: New wallet initialization complete

🔄 [WalletView_iOS] 📍 REFRESH: Calling refresh() (hasLoadedOnce=true)  ← WRONG!
   └─ Location: WalletView_iOS .task block
```

**Expected:** `📍 SKIP: Skipping refresh`  
**Actual:** `📍 REFRESH: Calling refresh()`

## Why the First Fix Failed

**Original approach:** Check `manager.hasLoadedOnce`

```swift
.task {
    if manager.hasLoadedOnce {  // ← Bug here!
        await manager.refresh()
    }
}
```

**The bug:** `hasLoadedOnce` is set **during** initialization, not **after** view appearance

**Timeline:**
```
14:35:54.000 - MainView calls initialize()
14:35:54.001 - initialize() calls refresh() internally
14:35:54.002 - refresh() sets hasLoadedOnce = true  ← Flag is now TRUE
14:35:54.500 - WalletView appears for first time
14:35:54.501 - Checks hasLoadedOnce → TRUE (just set!)
14:35:54.502 - Calls refresh() again ❌ DOUBLE REFRESH!
```

**Root cause:** We were checking the wrong flag. `hasLoadedOnce` tracks **data lifecycle**, but we need to track **view lifecycle**.

---

## The Corrected Fix

**New approach:** Track view appearance state directly

```swift
@State private var hasAppearedBefore = false

.task {
    if hasAppearedBefore {
        // View has appeared before, refresh data
        await manager.refresh()
    } else {
        // First appearance, skip refresh (data already loaded)
        hasAppearedBefore = true
    }
}
```

### Key Changes

1. **Added state variable** to `WalletView_iOS`:
   ```swift
   @State private var hasAppearedBefore = false
   ```

2. **Changed condition** from `hasLoadedOnce` to `hasAppearedBefore`:
   ```swift
   if hasAppearedBefore {  // ← Correct!
       await manager.refresh()
   } else {
       hasAppearedBefore = true
   }
   ```

3. **Updated logging** to show correct flag:
   ```swift
   print("🔄 [WalletView_iOS] 📍 REFRESH: Calling refresh() (hasAppearedBefore=true)")
   // or
   print("⏭️ [WalletView_iOS] 📍 SKIP: Skipping refresh (hasAppearedBefore=false)")
   ```

---

## Why This Fix Works

### Correct Lifecycle Tracking

**hasAppearedBefore tracks view state:**
- Always starts as `false`
- Set to `true` after first `.task` run
- Persists across view updates
- Resets when view is deallocated

**Timeline with fix:**
```
14:35:54.000 - MainView calls initialize()
14:35:54.001 - initialize() calls refresh() internally
14:35:54.002 - refresh() loads all data
14:35:54.500 - WalletView appears for first time
14:35:54.501 - hasAppearedBefore → FALSE (initial state)
14:35:54.502 - Skips refresh, sets flag to TRUE ✅
14:36:00.000 - User backgrounds app and returns
14:36:01.000 - WalletView appears again
14:36:01.001 - hasAppearedBefore → TRUE
14:36:01.002 - Calls refresh() to get latest data ✅
```

### Separation of Concerns

- **`hasLoadedOnce`** = "Has data been loaded?" (WalletManager responsibility)
- **`hasAppearedBefore`** = "Has view appeared?" (View responsibility)

Clear separation makes behavior predictable.

---

## Expected Log Output

### First Wallet Creation
```txt
🔧 [MainView_iOS] 📍 CALL #3: Initializing newly created wallet...
   └─ Location: MainView_iOS onWalletReady callback (OnboardingFlow_iOS)
🔧 [WalletManager] initialize at 2025-12-11 14:35:54 +0000
🔧 [WalletManager] initialize execute at 2025-12-11 14:35:54 +0000
WalletManager.performRefresh
✅ New address generated with index: 0
✅ New address generated with index: 1
✅ All wallet data refreshed successfully
🔧 [WalletManager] initialize execute done at 2025-12-11 14:35:54 +0000
✅ [MainView_iOS] 📍 CALL #3: New wallet initialization complete

⏭️ [WalletView_iOS] 📍 SKIP: Skipping refresh (hasAppearedBefore=false)
   └─ Data already loaded by MainView_iOS initialization
```

**Key indicators of success:**
- ✅ Only one `initialize execute`
- ✅ Addresses generated only at indices 0 and 1 (not 2 and 3)
- ✅ `SKIP` appears after initialization completes
- ✅ No redundant `REFRESH` call

### Returning from Background
```txt
🔄 [WalletView_iOS] 📍 REFRESH: Calling refresh() (hasAppearedBefore=true)
   └─ Location: WalletView_iOS .task block (subsequent appearance)
WalletManager.performRefresh
✅ All wallet data refreshed successfully
✅ [WalletView_iOS] 📍 REFRESH: Complete
```

**Key indicators of success:**
- ✅ `REFRESH` happens (not `SKIP`)
- ✅ Shows `hasAppearedBefore=true`
- ✅ Gets latest data from network

---

## Comparison: Before vs After

### Before Fix (Broken)
```txt
Initialize: Addresses 0, 1
Refresh:    Addresses 2, 3  ← Wasteful!
Total:      4 addresses for 2 needs
```

### After First Attempt (Still Broken)
```txt
Initialize: Addresses 0, 1
Refresh:    Addresses 2, 3  ← Still happening!
Total:      4 addresses for 2 needs
Reason:     Wrong flag (hasLoadedOnce vs hasAppearedBefore)
```

### After Corrected Fix (Working)
```txt
Initialize: Addresses 0, 1
Skip:       (no addresses generated)
Total:      2 addresses for 2 needs  ✅
```

---

## Testing Checklist

### ✅ Fresh Wallet Creation
- [ ] See `📍 CALL #3` during creation
- [ ] See `📍 SKIP (hasAppearedBefore=false)` when WalletView appears
- [ ] Addresses only at indices 0 and 1
- [ ] NO `📍 REFRESH` on first appearance

### ✅ Existing Wallet Startup
- [ ] See `📍 CALL #1` during startup
- [ ] See `📍 SKIP (hasAppearedBefore=false)` when WalletView appears
- [ ] Addresses only at indices 0 and 1
- [ ] NO `📍 REFRESH` on first appearance

### ✅ Return from Background
- [ ] See `📍 REFRESH (hasAppearedBefore=true)` when app returns
- [ ] New addresses generated (indices increment)
- [ ] Data refreshed successfully

### ✅ Tab Switching
- [ ] Switch away from Activity tab
- [ ] Switch back to Activity tab
- [ ] Should see `📍 REFRESH` (view reappeared)

---

## Files Changed
- `WalletView_iOS.swift`
  - Added `@State private var hasAppearedBefore = false`
  - Changed condition from `hasLoadedOnce` to `hasAppearedBefore`
  - Updated logging to show correct flag

## Date
December 11, 2025

## Status
✅ **CORRECTED** - Ready for re-testing
