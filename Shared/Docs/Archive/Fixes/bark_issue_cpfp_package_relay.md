# CPFP Package Broadcast Issue with Esplora Backend

> **📦 Archived 2026-07-09.** This Esplora package-relay limitation was mooted by the Bark 0.11 bindings update: the app now uses Bark's built-in BDK onchain wallet (`OnchainWallet.default()` in `BarkWalletFFI+WalletLifecycle.swift`), whose internal chain source handles CPFP package broadcast. The custom `BDKOnchainWallet`/`BDKCpfpHelper` path this doc describes is no longer wired in. See `cpfp_package_relay_solution.md` (same folder) for the follow-up plan that was never needed, and `../../BDK/CPFP-Implementation-Plan.md` for the superseded custom implementation.

## Summary

Exit transactions are failing because CPFP (Child Pays For Parent) transactions with P2A (Pay-to-Anchor) outputs require **package relay** to broadcast, but the current implementation attempts to broadcast them individually via Esplora, which doesn't support package relay.

## Environment

- **Network**: Bitcoin Signet
- **Backend**: Esplora (esplora.signet.2nd.dev)
- **Wallet**: Custom Swift implementation using Bark FFI + BDK for onchain operations
- **Bark Version**: [Latest from main branch]

## The Problem

### What's Happening

When `progressExits()` is called, the Bark library:

1. ✅ Successfully creates CPFP transactions with correct fee calculations
2. ✅ Creates P2A outputs with empty witness (as expected for anyone-can-spend)
3. ❌ Attempts to broadcast parent and child transactions
4. ❌ Both transactions are rejected:

**Parent transaction error:**
```
tx 777966ab1600f635a33df8ae40a677492159c326d2dc809570f044ed9ca41023: min relay fee not met, 0 < 17
```

**CPFP child transaction error:**
```
tx 93ff39a58001f754e282d38fb3fedd677cfec17f00f1ce63d2e052bbae1c0da2: mandatory-script-verify-flag-failed (Witness program was passed an empty witness), input 1 of 93ff39a58001f754e282d38fb3fedd677cfec17f00f1ce63d2e052bbae1c0da2 (wtxid 93ff39a58001f754e282d38fb3fedd677cfec17f00f1ce63d2e052bbae1c0da2), spending 118afe84b11eb8ccf39b349018f7164b0645093d6c08021d59d30053476ed77e:0
```

### Full Error Context

From logs during `progressExits()`:

```
🔧 [CPFP] Creating P2A CPFP transaction...
   Fee type: Effective
   Target effective fee rate: 7 sat/vB
   Parent txid: 777966ab1600f635a33df8ae40a677492159c326d2dc809570f044ed9ca41023
   Found P2A output: 777966ab1600f635a33df8ae40a677492159c326d2dc809570f044ed9ca41023:2
   Change address: tb1phh4e8jegzfzphlsvjdw8epxh7vxhe6eg2d4jxw7wyvay5pywyl6sn9a33z
   Parent weight: 872 WU
   Starting iterative fee calculation...
   Initial fee needed: 6104 sats
   Iteration 1: fee = 6104 sats
   CPFP tx weight: 540 WU, total package: 1412 WU
   Weight changed, recalculating fee: 2471 sats
   Iteration 2: fee = 2471 sats
   CPFP tx weight: 540 WU, total package: 1412 WU
   ✓ Weight stabilized, CPFP transaction ready
✅ [CPFP] Transaction created: 93ff39a58001f754e282d38fb3fedd677cfec17f00f1ce63d2e052bbae1c0da2

[Later during broadcast...]
Error: Exit Package Broadcast Failure: Unable to broadcast exit transaction package 777966ab1600f635a33df8ae40a677492159c326d2dc809570f044ed9ca41023: msg: 'transaction failed', errors: ["tx 777966ab1600f635a33df8ae40a677492159c326d2dc809570f044ed9ca41023: min relay fee not met, 0 < 17", "tx 93ff39a58001f754e282d38fb3fedd677cfec17f00f1ce63d2e052bbae1c0da2: mandatory-script-verify-flag-failed (Witness program was passed an empty witness)..."]
```

## Root Cause Analysis

The error message says **"Unable to broadcast exit transaction package"** which suggests Bark is aware these need package broadcast, but:

### Current Broadcast Method

Our `CustomOnchainWalletCallbacks` implementation uses:

```swift
func broadcastTransaction(txHex: String) throws -> String {
    let tx = try Transaction(transactionBytes: Data(hexToBytes(txHex)))
    try esploraClient.broadcast(transaction: tx)  // ← Single tx broadcast
    return txid
}
```

This broadcasts **one transaction at a time** via Esplora's REST API.

### Why This Fails

1. **Parent transaction** has 0 fees (relying on CPFP child to pay)
   - Esplora rejects: "min relay fee not met"
   
2. **CPFP child** has empty witness for P2A input (correct for anyone-can-spend)
   - Esplora rejects as invalid when broadcast alone
   
3. **Package relay** (Bitcoin Core's `submitpackage` RPC) would accept both together
   - But Esplora doesn't support this

## Questions

### 1. Does Bark expect package relay support?

When `progressExits()` creates CPFP transactions with `NeedsBroadcasting { child_txid: ... }` status, does it expect the `CustomOnchainWalletCallbacks` to:

- A) Have a `broadcastPackage(parentHex: String, childHex: String)` method?
- B) Automatically detect and package transactions when broadcasting?
- C) Use a different broadcast strategy?

**Our current interface only has:**
```rust
fn broadcast_transaction(&self, tx_hex: String) -> Result<String>;
```

### 2. Should parent transactions have minimum relay fees?

Is it expected that parent exit transactions have **zero fees**, or should they have at least minimum relay fees and use CPFP only for additional boosting?

Current behavior:
- Parent: 0 sats fee (rejected by Esplora)
- Child: 2471 sats to achieve 7 sat/vB effective rate for package

Alternative approach:
- Parent: 17 sats (minimum relay fee)
- Child: 2454 sats (still achieves target rate)
- Both can be broadcast individually

### 3. What's the intended broadcast flow for CPFP?

Looking at the Bark source, how should wallets handle the `NeedsBroadcasting` state with a `child_txid`?

From our logs, the exit status shows:
```rust
ExitTx { 
    txid: 777966ab..., 
    status: NeedsBroadcasting { 
        child_txid: 93ff39a5..., 
        origin: Wallet { confirmed_in: None } 
    } 
}
```

Should we:
1. Broadcast parent first, then child?
2. Broadcast both together as a package?
3. Expect the Bark library to handle this internally?

### 4. Is there a missing callback interface?

Should `CustomOnchainWalletCallbacks` have an additional method like:

```rust
fn broadcast_tx_package(&self, tx_hexes: Vec<String>) -> Result<Vec<String>>;
```

Or is the current single-transaction interface expected to work?

## Potential Solutions We're Considering

### Option 1: Add Bitcoin Core RPC for Package Relay
- Add optional Bitcoin Core node connection alongside Esplora
- Detect CPFP packages and route to `submitpackage` RPC
- Fallback to Esplora for single transactions
- **Complexity**: High (requires Bitcoin Core node)

### Option 2: Modify Parent to Have Minimum Fees
- Change CPFP params to ensure parent has minimum relay fee
- Child still boosts to target rate
- Both transactions can be broadcast individually via Esplora
- **Complexity**: Low (may require Bark changes)

### Option 3: Check if Esplora Now Supports Package Relay
- Some Esplora implementations may have added package relay support
- Need to verify if API supports it
- **Complexity**: Low if supported, N/A if not

## Request for Guidance

1. **What's the intended way to broadcast CPFP transactions?** Should wallets implement package relay, or should parents have minimum fees?

2. **Is package relay support required** for wallets using Bark with unilateral exits?

3. **Should we modify the parent fee calculation** in CPFP to ensure minimum relay fees, or is there a better solution within Bark?

4. **Are there existing wallet implementations** we can reference that successfully handle CPFP with Esplora backends?

## Additional Context

- Our Swift/BDK implementation successfully creates CPFP transactions
- Fee calculations are correct (verified against Esplora fee estimates)
- The only issue is the broadcast mechanism
- We can implement Bitcoin Core RPC if that's the expected approach

Thank you for any guidance on the correct way to handle this!
