# Server Connection Diagnostics & Investigation Plan

**Date:** December 11, 2024  
**Issue:** Ark server connection not established after wallet creation/opening  
**Status:** 🔍 Investigation in Progress

---

## Problem Summary

The app successfully creates and opens wallets, but **cannot generate Ark addresses** because the Rust FFI wallet has no server connection:

```
❌ FFI Error generating address: ServerConnection(message: "You should be connected to Ark server to perform this action")
```

This happens consistently:
- Immediately after wallet creation (12:03:00)
- After wallet initialization (12:03:01, 12:03:05)
- Every single time address generation is attempted

---

## Root Cause Analysis

### What We Know

1. **Wallet creation succeeds locally** ✅
   - `Wallet.create()` completes without error
   - Wallet object is created and stored
   - Mnemonic is saved securely

2. **But server connection is NOT established** ❌
   - `wallet.newAddressWithIndex()` fails with `ServerConnection` error
   - `wallet.arkInfo()` also fails (requires server connection)
   - This suggests the Rust FFI doesn't auto-connect

3. **Ark addresses REQUIRE server connection** ℹ️
   - Ark addresses = User private key + ASP public key
   - ASP public key must be fetched from server
   - This is expected Ark protocol behavior (not a bug)

### What We Don't Know (Yet)

1. **Does the Rust wallet have an explicit connect method?**
   - Is there `wallet.connect()` or `wallet.sync()`?
   - Does connection happen lazily on first operation?
   - Is there a timeout or retry mechanism?

2. **When/how should connection be established?**
   - During `Wallet.create()`?
   - During `Wallet.open()`?
   - Via separate call after open?
   - Automatically on first server operation?

3. **Why might connection be failing?**
   - Network not ready on iOS at wallet creation time?
   - Server unreachable (DNS, firewall, SSL)?
   - Configuration issue (wrong server URL)?
   - Missing initialization step in Swift wrapper?

---

## Enhanced Diagnostics Added

I've added comprehensive logging to help diagnose the issue:

### 1. Connection Status Checker

**Location:** `BarkWalletFFI.swift` - New method `ensureServerConnection()`

```swift
func ensureServerConnection() async -> Bool {
    guard let wallet = wallet else { return false }
    
    print("🔌 [ensureServerConnection] Attempting to establish server connection...")
    
    do {
        let arkInfo = try wallet.arkInfo()
        print("✅ Server connection verified!")
        print("   Round interval: \(arkInfo.roundIntervalSeconds)s")
        return true
    } catch {
        print("❌ Cannot fetch ArkInfo: \(error)")
        return false
    }
}
```

**Purpose:** Test if server connection exists by calling `arkInfo()` which requires server

### 2. Post-Creation Connection Check

**Location:** `BarkWalletFFI.swift` - In `createWallet()`

```swift
// After Wallet.create() succeeds
print("🔍 [DIAGNOSTIC] Checking server connection immediately after wallet creation...")
let connected = await ensureServerConnection()
if connected {
    print("✅ Wallet has server connection after creation")
} else {
    print("⚠️ Wallet created but NO server connection")
    print("💡 Possible reasons:")
    print("   1. Connection happens lazily on first server operation")
    print("   2. Network not ready at wallet creation time")
    print("   3. forceRescan parameter doesn't trigger connection")
    print("   4. Server connection requires explicit initialization")
}
```

**Purpose:** Determine if `Wallet.create()` establishes connection or not

### 3. Post-Open Connection Check

**Location:** `BarkWalletFFI.swift` - In `tryOpenExistingWallet()`

```swift
// After Wallet.open() succeeds
print("🔍 [DIAGNOSTIC] Checking server connection after wallet open...")
let connected = await ensureServerConnection()
if connected {
    print("✅ Server connection available after open")
} else {
    print("⚠️ No server connection after wallet open")
    print("💡 May need explicit connection step or network delay")
}
```

**Purpose:** Determine if `Wallet.open()` establishes connection or not

### 4. Enhanced Address Generation Logging

**Location:** `BarkWalletFFI.swift` - In `getArkAddress()`

```swift
print("🔍 [DEBUG] Current wallet state:")
print("   - Wallet object exists: \(self.wallet != nil)")
print("   - Config server: \(config.serverAddress)")
print("   - Config esplora: \(config.esploraAddress ?? "nil")")

// Try to get server info first
print("🔍 [DEBUG] Attempting to fetch server info before address generation...")
do {
    let arkInfo = try wallet.arkInfo()
    print("✅ Server connected! ArkInfo available:")
    print("   - Round interval: \(arkInfo.roundIntervalSeconds)s")
} catch {
    print("⚠️ Cannot fetch ArkInfo (server may not be connected): \(error)")
    print("🔍 This explains why address generation will fail")
}

// Detailed error analysis
catch let error as BarkError {
    print("🔍 [DEBUG] BarkError details:")
    print("   - Error type: \(type(of: error))")
    
    if case .ServerConnection(let message) = error {
        print("🔍 Confirmed: This is a ServerConnection error")
        print("   - Message: \(message)")
        print("💡 The Rust wallet needs an explicit connection step")
    }
}
```

**Purpose:** Understand exactly when/why server connection is missing

---

## Testing Instructions

### Run the App with New Diagnostics

1. **Clean build** the app with updated code
2. **Create a new wallet** (or delete existing to test creation flow)
3. **Watch console for new diagnostic logs**
4. **Look for these key indicators:**

#### ✅ **Good Signs (Connection Working)**
```
✅ [DIAGNOSTIC] Wallet has server connection after creation
✅ [DIAGNOSTIC] Server connection available after open
✅ Server connected! ArkInfo available:
   - Round interval: 60s
   - Round duration: 10s
✅ New address generated with index
```

#### ⚠️ **Problem Indicators (No Connection)**
```
⚠️ [DIAGNOSTIC] Wallet created but NO server connection
⚠️ [DIAGNOSTIC] No server connection after wallet open
⚠️ Cannot fetch ArkInfo (server may not be connected)
❌ FFI Error generating address: ServerConnection
```

### What to Capture

1. **Full console log** from app launch through first address generation attempt
2. **Network configuration**:
   - Server URL: `ark.signet.2nd.dev`
   - Esplora URL: `https://esplora.signet.2nd.dev`
3. **Timing information**:
   - Time between wallet creation and address request
   - Any delays or timeouts
4. **Error details**:
   - Full BarkError descriptions
   - Any network-related errors

---

## Investigation Questions

Based on the new diagnostic output, we'll be able to answer:

### Question 1: When Does Connection Happen?

**If connection exists after `Wallet.create()`:**
- ✅ Auto-connection works
- 🔍 Why does it fail later? (timeout? network change?)

**If NO connection after `Wallet.create()`:**
- ⚠️ Connection is NOT automatic
- 🔍 Need to find explicit connection method

### Question 2: Is It a Timing Issue?

**Check timestamps:**
- Wallet creation: `12:03:00`
- First address attempt: `12:03:01` (1 second later)

**Hypothesis:** Network/connection might need more time to establish

**Test:** Add explicit delay:
```swift
// After wallet creation/opening
print("⏱️ Waiting for network to stabilize...")
try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
let connected = await ensureServerConnection()
```

### Question 3: Is It a Network Availability Issue?

**Test network before wallet operations:**
```swift
// Test server reachability
let url = URL(string: "https://ark.signet.2nd.dev")!
var request = URLRequest(url: url, timeoutInterval: 5.0)
request.httpMethod = "HEAD"

do {
    let (_, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse {
        print("🌐 Server reachable: HTTP \(http.statusCode)")
    }
} catch {
    print("❌ Server NOT reachable: \(error)")
}
```

### Question 4: Does the Rust Wallet Have Connection Methods?

**Look for in Bark FFI:**
- `wallet.connect()` or `wallet.connect(timeout:)`
- `wallet.sync()` or `wallet.syncWithServer()`
- `wallet.refreshServerInfo()`
- `wallet.initialize()` or `wallet.setup()`
- Any method that explicitly establishes connection

**Check generated Swift interface:**
```bash
# In Xcode, navigate to the Wallet type and view its generated interface
# Look for methods that might relate to connection/sync
```

---

## Possible Solutions

Based on what the diagnostics reveal, here are potential fixes:

### Solution A: Explicit Connection Call (If method exists)

```swift
// After wallet creation/opening
func openWalletIfNeeded() async -> Bool {
    // ... existing open logic ...
    
    if wallet != nil {
        print("🔌 Establishing server connection...")
        try? await wallet?.connect() // IF THIS METHOD EXISTS
        
        let connected = await ensureServerConnection()
        if !connected {
            print("⚠️ Server connection could not be established")
        }
    }
    
    return wallet != nil
}
```

### Solution B: Retry with Backoff (If timing issue)

```swift
func getArkAddress() async throws -> String {
    guard let wallet = wallet else {
        throw BarkWalletFFIError.walletNotInitialized
    }
    
    // Retry logic for connection issues
    var attempts = 0
    let maxAttempts = 3
    
    while attempts < maxAttempts {
        do {
            let addressWithIndex = try wallet.newAddressWithIndex()
            return addressWithIndex.address
        } catch let error as BarkError {
            if case .ServerConnection = error {
                attempts += 1
                if attempts < maxAttempts {
                    print("⚠️ Connection failed, retrying (\(attempts)/\(maxAttempts))...")
                    let delay = Double(attempts) * 2.0 // 2s, 4s, 6s
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            }
            throw error
        }
    }
    
    throw BarkWalletFFIError.configurationError("Failed to connect after \(maxAttempts) attempts")
}
```

### Solution C: Lazy Connection (If auto-connect should work)

```swift
// Ensure wallet is opened AND connected before any operation
private func ensureWalletReady() async throws {
    guard let wallet = wallet else {
        throw BarkWalletFFIError.walletNotInitialized
    }
    
    // Test connection
    let connected = await ensureServerConnection()
    
    if !connected {
        // Try to re-establish by closing and reopening
        print("🔄 Attempting to re-establish connection...")
        self.wallet = nil
        
        await openWalletIfNeeded()
        
        // Verify it worked
        let nowConnected = await ensureServerConnection()
        if !nowConnected {
            throw BarkWalletFFIError.configurationError("Unable to establish server connection")
        }
    }
}

func getArkAddress() async throws -> String {
    try await ensureWalletReady()
    
    guard let wallet = wallet else {
        throw BarkWalletFFIError.walletNotInitialized
    }
    
    let addressWithIndex = try wallet.newAddressWithIndex()
    return addressWithIndex.address
}
```

### Solution D: Pre-warm Connection (If network delay)

```swift
// Call this during app launch or after wallet creation
func warmupConnection() async {
    guard let wallet = wallet else { return }
    
    print("🔥 Warming up server connection...")
    
    // Give network time to initialize
    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
    
    // Test various operations that might trigger connection
    let operations: [(String, () async throws -> Void)] = [
        ("arkInfo", { try await { _ = try wallet.arkInfo() }() }),
        ("balance", { try await { _ = try wallet.balance() }() }),
        ("address", { try await { _ = try wallet.newAddressWithIndex() }() })
    ]
    
    for (name, operation) in operations {
        do {
            try await operation()
            print("✅ [\(name)] succeeded - connection established")
            return
        } catch {
            print("⚠️ [\(name)] failed: \(error)")
        }
    }
    
    print("❌ Connection warmup failed - server may be unreachable")
}
```

---

## Next Steps

1. ✅ **Deploy enhanced diagnostics** (already done in code above)
2. 🔄 **Run the app and capture logs**
3. 📊 **Analyze diagnostic output** to answer investigation questions
4. 🔍 **Check Rust Bark FFI documentation** for connection methods
5. 🛠️ **Implement appropriate solution** based on findings
6. ✅ **Verify fix** with thorough testing

---

## Expected Diagnostic Output

### Scenario 1: Auto-Connection Works (Best Case)

```
✅ Wallet created successfully
🔍 [DIAGNOSTIC] Checking server connection immediately after wallet creation...
🔌 [ensureServerConnection] Attempting to establish server connection...
   Target server: ark.signet.2nd.dev
✅ [ensureServerConnection] Server connection verified!
   Round interval: 60s
   Round duration: 10s
✅ [DIAGNOSTIC] Wallet has server connection after creation

[Later when address is generated]
🔧 Generating new address via FFI...
🔍 [DEBUG] Current wallet state:
   - Wallet object exists: true
   - Config server: ark.signet.2nd.dev
🔍 [DEBUG] Attempting to fetch server info before address generation...
✅ [DEBUG] Server connected! ArkInfo available:
   - Round interval: 60s
✅ New address generated with index:
   Address: ark1xxxxx...
   Index: 0
```

### Scenario 2: No Auto-Connection (Current Problem)

```
✅ Wallet created successfully
🔍 [DIAGNOSTIC] Checking server connection immediately after wallet creation...
🔌 [ensureServerConnection] Attempting to establish server connection...
   Target server: ark.signet.2nd.dev
❌ [ensureServerConnection] Cannot fetch ArkInfo: ServerConnection(message: "You should be connected to Ark server to perform this action")
🔍 [ensureServerConnection] Investigating if wallet needs explicit connection...
⚠️ [DIAGNOSTIC] Wallet created but NO server connection
💡 [HINT] Server connection may need to be established separately
   Possible reasons:
   1. Connection happens lazily on first server operation
   2. Network not ready at wallet creation time
   3. forceRescan parameter doesn't trigger connection
   4. Server connection requires explicit initialization

[Later when address is generated]
🔧 Generating new address via FFI...
🔍 [DEBUG] Current wallet state:
   - Wallet object exists: true
   - Config server: ark.signet.2nd.dev
🔍 [DEBUG] Attempting to fetch server info before address generation...
⚠️ [DEBUG] Cannot fetch ArkInfo (server may not be connected): ServerConnection(message: "You should be connected to Ark server to perform this action")
🔍 [DEBUG] This explains why address generation will fail
❌ FFI Error generating address: ServerConnection(message: "You should be connected to Ark server to perform this action")
🔍 [DEBUG] BarkError details:
   - Error type: ServerConnection
🔍 [DEBUG] Confirmed: This is a ServerConnection error
   - Message: You should be connected to Ark server to perform this action
💡 [HINT] The Rust wallet needs an explicit connection step
```

---

## Resources

- **Current logs:** `Debug log dump.txt`
- **Issue documentation:** `ISSUE_2_ADDRESS_GENERATION.md`
- **Bark FFI wrapper:** `BarkWalletFFI.swift`
- **Server config:**
  - ASP: `ark.signet.2nd.dev`
  - Esplora: `https://esplora.signet.2nd.dev`

---

**Status:** 🔍 Waiting for diagnostic output from next test run
