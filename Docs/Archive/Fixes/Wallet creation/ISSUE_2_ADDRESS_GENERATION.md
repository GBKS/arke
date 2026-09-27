# Issue 2: Address Generation Fails - Server Connection Required

**Date:** December 10, 2024  
**Status:** ✅ Root Cause Identified  
**Priority:** Critical (User-Facing)

---

## Executive Summary

**Problem:** After wallet creation, address generation fails with "no server connection" error. User sees this error immediately in the wallet view.

**Root Cause:** 
- Ark addresses require the ASP (Ark Service Provider) public key from the server
- Server connection is not established when address generation is attempted
- This is NOT a bug - Ark protocol requires server connection for address derivation

**Why Ark Addresses Need Server:**
- Unlike standard Bitcoin addresses (BIP32/BIP44), Ark addresses are NOT purely local
- Ark address = Derived from user's private key + ASP's public key
- The ASP public key must be retrieved from the server
- This is expected Ark protocol behavior

**Impact:** High
- User cannot see their addresses after creating wallet
- Error shown prominently in UI
- Bad first-time user experience
- Wallet is functional but appears broken

**Fix:** Ensure server connection is established before/during address generation, with retry logic and better UX

---

## Visual Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ CURRENT FLOW (FAILING)                                          │
└─────────────────────────────────────────────────────────────────┘

1. WalletManager.createWallet()
   └─ BarkWalletFFI.createWallet()
       └─ Wallet.create() (Rust FFI)
           └─ self.wallet = newWallet ✓
           └─ Server connection: ❓ (unknown state)

2. MainView.onWalletReady()
   └─ WalletManager.initialize()
       └─ BarkWalletFFI.openWalletIfNeeded()
           └─ wallet != nil → return true ✓
       └─ AddressService.loadAddresses()
           └─ BarkWalletFFI.getArkAddress()
               └─ wallet.newAddressWithIndex() (Rust FFI)
                   └─ ❌ ERROR: "no server connection"
                   └─ ✅ ERROR SHOWN TO USER


┌─────────────────────────────────────────────────────────────────┐
│ DESIRED FLOW                                                     │
└─────────────────────────────────────────────────────────────────┘

1. WalletManager.createWallet()
   └─ Create wallet ✓

2. MainView.onWalletReady()
   └─ WalletManager.initialize()
       └─ BarkWalletFFI.openWalletIfNeeded() ✓
       └─ BarkWalletFFI.ensureServerConnection() ✓
           └─ Show "Connecting to server..."
           └─ Establish connection with retry
       └─ AddressService.loadAddresses()
           └─ BarkWalletFFI.getArkAddress()
               └─ ✅ SUCCESS - addresses generated
```

---

## Technical Details

### Current Code (Failing)

**File: BarkWalletFFI.swift (lines 724-753)**
```swift
func getArkAddress() async throws -> String {
    guard let wallet = wallet else {
        throw BarkWalletFFIError.walletNotInitialized
    }
    
    print("🔧 Generating new address via FFI...")
    
    do {
        // This calls Rust FFI method that needs server connection
        let addressWithIndex = try wallet.newAddressWithIndex()
        return addressWithIndex.address
    } catch let error as BarkError {
        // Error comes from Rust layer: "no server connection"
        throw BarkWalletFFIError.configurationError("Failed to generate address: \(error.localizedDescription)")
    }
}
```

**File: AddressService.swift (lines 60-82)**
```swift
private func performLoadAddresses() async {
    do {
        arkAddress = try await wallet.getArkAddress()
        print("✅ Ark address loaded: \(arkAddress)")
    } catch {
        print("❌ Failed to get Ark address: \(error)")
        self.error = "Failed to get Ark address: \(error)"  // ❌ Generic error shown to user
    }
}
```

---

## Implementation Options

### Option A: Retry Logic with Exponential Backoff (Immediate Fix)

Add robust retry mechanism for connection failures with better UX.

**File: BarkWalletFFI.swift**
```swift
func getArkAddress() async throws -> String {
    guard let wallet = wallet else {
        throw BarkWalletFFIError.walletNotInitialized
    }
    
    // Try to generate address with retry logic
    var attempts = 0
    let maxAttempts = 3
    var lastError: Error?
    
    while attempts < maxAttempts {
        do {
            let addressWithIndex = try wallet.newAddressWithIndex()
            print("✅ Ark address generated: \(addressWithIndex.address)")
            return addressWithIndex.address
        } catch let error as BarkError {
            lastError = error
            
            if error.localizedDescription.contains("no server connection") {
                attempts += 1
                print("⚠️ Server connection failed (attempt \(attempts)/\(maxAttempts))")
                
                if attempts < maxAttempts {
                    // Wait before retry (exponential backoff)
                    let delay = Double(attempts) * 1.0
                    print("   Retrying in \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    
                    // Try to re-establish connection by reopening wallet
                    print("   Attempting to re-establish server connection...")
                    self.wallet = nil
                    let reopened = await openWalletIfNeeded()
                    
                    if !reopened {
                        throw BarkWalletFFIError.configurationError("Failed to reopen wallet for connection retry")
                    }
                    
                    guard let wallet = wallet else {
                        throw BarkWalletFFIError.walletNotInitialized
                    }
                    
                    continue
                }
            }
            
            throw BarkWalletFFIError.configurationError("Failed to generate address: \(error.localizedDescription)")
        } catch {
            throw error
        }
    }
    
    throw BarkWalletFFIError.configurationError("Failed to connect to server after \(maxAttempts) attempts: \(lastError?.localizedDescription ?? "Unknown error")")
}
```

---

### Option B: Explicit Connection Management (Best Long-term)

Add explicit method to ensure server connection before operations.

**File: BarkWalletFFI.swift**
```swift
/// Ensures the wallet has an active server connection
/// This should be called before operations that require server access (like address generation)
func ensureServerConnection() async throws {
    guard let wallet = wallet else {
        throw BarkWalletFFIError.walletNotInitialized
    }
    
    print("🔌 Ensuring server connection for Ark operations...")
    
    // TODO: Check if Rust bark library has a method to verify/establish connection
    // This might be:
    // - wallet.connect()
    // - wallet.refreshServerInfo()
    // - wallet.ping()
    // Or we might need to attempt an operation to verify connection
    
    // For now, attempt a test operation
    do {
        _ = try wallet.newAddressWithIndex()
        print("✅ Server connection verified")
    } catch let error as BarkError {
        if error.localizedDescription.contains("no server connection") {
            throw BarkWalletFFIError.configurationError("Unable to establish server connection")
        }
        // Other errors might be okay (address already exists, etc.)
    }
}

func getArkAddress() async throws -> String {
    // Ensure connection before address generation
    try await ensureServerConnection()
    
    guard let wallet = wallet else {
        throw BarkWalletFFIError.walletNotInitialized
    }
    
    let addressWithIndex = try wallet.newAddressWithIndex()
    return addressWithIndex.address
}
```

**File: WalletManager.swift**
```swift
private func performInitialization() async {
    guard let wallet = wallet else {
        error = "Wallet not available"
        return
    }
    
    print("🔧 [WalletManager] Starting initialization...")
    
    // Step 1: Open the wallet
    if let ffiWallet = wallet as? BarkWalletFFI {
        let opened = await ffiWallet.openWalletIfNeeded()
        if !opened {
            print("ℹ️ No existing wallet to open")
            isInitialized = false
            return
        }
        print("✅ Wallet opened successfully")
        
        // Step 2: Explicitly ensure server connection BEFORE address generation
        do {
            print("🔌 Establishing server connection...")
            try await ffiWallet.ensureServerConnection()
            print("✅ Server connection established")
        } catch {
            print("❌ Failed to establish server connection: \(error)")
            self.error = "Unable to connect to Ark server. Please check your connection."
            // Don't fail initialization - allow retry
        }
    }
    
    // Step 3: Check wallet existence
    let walletExists = securityService.hasMnemonic()
    
    if walletExists {
        print("✅ Wallet mnemonic found in Keychain")
        isInitialized = true
        await refresh()
        await createDefaultTagsIfNeeded()
    } else {
        print("⚠️ No mnemonic found in Keychain")
        isInitialized = false
    }
}
```

---

### Option C: Better Error Messages and UI

Improve user experience with helpful messages and retry button.

**File: AddressService.swift**
```swift
private func performLoadAddresses() async {
    isLoading = true
    error = nil
    
    do {
        print("🔌 Generating Ark address (requires server connection)...")
        arkAddress = try await wallet.getArkAddress()
        print("✅ Ark address loaded: \(arkAddress)")
    } catch {
        print("❌ Failed to get Ark address: \(error)")
        
        // Provide helpful, specific error messages
        if error.localizedDescription.contains("no server connection") {
            self.error = """
            Unable to connect to Ark server.
            
            Ark addresses require connection to retrieve the service provider's public key.
            
            Please check your internet connection and try again.
            """
        } else if error.localizedDescription.contains("timed out") {
            self.error = "Connection to Ark server timed out. Please try again."
        } else {
            self.error = "Failed to generate address: \(error.localizedDescription)"
        }
    }
    
    // Try onchain address
    do {
        onchainAddress = try await wallet.getOnchainAddress()
        print("✅ Onchain address loaded: \(onchainAddress)")
    } catch {
        print("❌ Failed to get onchain address: \(error)")
        if self.error == nil {
            self.error = "Failed to get onchain address: \(error)"
        }
    }
    
    isLoading = false
}

// Add manual retry capability
func retry() async {
    await loadAddresses()
}
```

**UI Component (wherever addresses are displayed):**
```swift
if let error = addressService.error {
    VStack(spacing: 16) {
        // Icon
        Image(systemName: "wifi.exclamationmark")
            .font(.system(size: 48))
            .foregroundStyle(.red.opacity(0.8))
        
        // Error message
        Text(error)
            .foregroundStyle(.white.opacity(0.9))
            .font(.system(size: 16))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        
        // Retry button
        Button("Retry Connection") {
            Task {
                await addressService.retry()
            }
        }
        .buttonStyle(ArkeButtonStyle(size: .medium))
    }
    .padding(24)
}

// Show loading state during connection
if addressService.isLoading {
    VStack(spacing: 12) {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .Arke.gold))
        
        Text("Connecting to Ark server...")
            .foregroundStyle(.white.opacity(0.7))
            .font(.system(size: 14))
    }
}
```

---

## Recommended Implementation Plan

### Phase 1: Quick Fix (Today)
1. Implement Option A (Retry Logic) in `BarkWalletFFI.swift`
2. Implement Option C (Better Errors) in `AddressService.swift`
3. Add retry button to UI
4. Test with network delays/interruptions

### Phase 2: Better Connection Management (This Week)
1. Implement Option B (`ensureServerConnection()`)
2. Call during initialization in `WalletManager.swift`
3. Add loading state "Connecting to server..."
4. Test connection timing and reliability

### Phase 3: Long-term Improvements (Future)
1. Investigate Rust bark library for explicit connection APIs
2. Add connection status monitoring
3. Consider caching ASP public key (if protocol allows)
4. Add health check/ping for server availability

---

## Files Requiring Changes

| File | Change | Priority |
|------|--------|----------|
| `BarkWalletFFI.swift` | Add retry logic to `getArkAddress()` | High |
| `BarkWalletFFI.swift` | Add `ensureServerConnection()` method | Medium |
| `AddressService.swift` | Better error messages | High |
| `AddressService.swift` | Add `retry()` method | High |
| `WalletManager.swift` | Call `ensureServerConnection()` in init | Medium |
| `WalletView.swift` or similar | Add retry button and loading state | High |

---

## Questions for Investigation

1. **When does Rust wallet establish server connection?**
   - During `Wallet.create()`?
   - During `Wallet.open()`?
   - Lazily on first operation?
   - Explicitly via connection method?

2. **Is there a way to check connection status?**
   - Can we query Rust wallet for connection state?
   - Should we add `wallet.isConnected()` to FFI?
   - Would help with proactive error handling

3. **Why might connection fail after wallet creation?**
   - Does connection timeout between creation and init?
   - Race condition?
   - Network connectivity?
   - ASP server availability?

4. **Can ASP public key be cached?**
   - Does it change frequently?
   - Could reduce server dependency
   - Need to verify with Ark protocol spec

---

## Testing Checklist

- [ ] Create wallet with good network connection - addresses should generate
- [ ] Create wallet with no network - should show helpful error
- [ ] Test retry button - should eventually succeed when network restored
- [ ] Test with slow/flaky network - retry logic should handle it
- [ ] Verify loading state shows during connection attempt
- [ ] Check error messages are clear and actionable
- [ ] Test wallet restart after failed connection - should recover

---

## Related Documents

- `ISSUE_1_DEVICE_REGISTRATION.md` - Device registration timing issue
- `INITIALIZATION_FLOWS.md` - Full initialization architecture
- `WALLET_CREATION_ISSUES.md` - Original combined analysis

---

**Status:** Ready for implementation - Start with Phase 1
