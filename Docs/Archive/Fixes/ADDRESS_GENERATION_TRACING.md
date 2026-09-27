# Address Generation Tracing

## Summary

Added comprehensive call stack tracing to understand when and why addresses are being generated during wallet initialization.

## Logging Added

### 1. **BarkWalletFFI.swift** - `getArkAddress()`
- Added call stack trace at the FFI level
- Shows the full call stack when an address generation is requested
- Includes first 6 frames of the call stack

### 2. **AddressService.swift** - `loadAddresses()`
- Added call stack trace at the service level
- Shows who is calling the address service
- Includes first 6 frames of the call stack

### 3. **WalletManager.swift** - `performRefresh()`
- Added trace showing when refresh starts address loading
- Shows the caller of performRefresh
- Added trace in the task group that calls addressService

### 4. **WalletManager.swift** - `performInitialization()`
- Added trace before calling refresh()
- Clarifies that initialization triggers address generation

## Expected Output

When addresses are generated during initialization, you should see:

```
📍 [ADDRESS TRACE] performInitialization() about to call refresh()
   This will trigger address generation
🔄 [WalletManager] 📞 refresh() CALLED
   ├─ From: WalletManager.swift:XXX
   └─ Function: performInitialization()
📍 [ADDRESS TRACE] WalletManager.performRefresh() starting address load
   📞 Called from:
      0: <call stack frame>
      1: <call stack frame>
      ...
📍 [ADDRESS TRACE] Task group calling addressService.loadAddresses()
📍 [ADDRESS TRACE] AddressService.loadAddresses() CALLED
   📞 Call stack:
      0: <call stack frame>
      1: <call stack frame>
      ...
🔧 [ADDRESS TRACE] getArkAddress() CALLED
   📞 Call stack:
      0: <call stack frame>
      1: <call stack frame>
      ...
🔧 Generating new address via FFI...
✅ New address generated with index: X
```

## Purpose

This will help us understand:
1. **Who** is calling address generation (initialization, refresh, UI, etc.)
2. **When** it happens in the app lifecycle
3. **Why** it's being triggered multiple times (if it is)
4. Whether we can defer address generation until actually needed

## Next Steps

After reviewing the logs:
- Determine if address generation can be lazy-loaded
- Check if addresses are being generated multiple times unnecessarily
- Consider caching addresses to avoid regeneration
- Evaluate if we can defer until the user navigates to a receive screen
