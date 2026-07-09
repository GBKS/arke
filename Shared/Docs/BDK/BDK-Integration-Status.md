# BDK Integration Status

## Overview

This document tracks the integration of Bitcoin Development Kit (BDK) to provide onchain transaction history and full Bitcoin wallet functionality.

## What Was Done

### 1. Created BDK Wallet Wrapper
**File**: `Arke/Shared/Data/BDKOnchainWallet.swift`

- Created a class that implements `CustomOnchainWalletCallbacks` protocol
- This allows BDK to be used as the onchain wallet backend for Bark
- **Status**: Placeholder implementation created ⚠️

### 2. Created Transaction Model
**File**: `Arke/Shared/Models/OnchainTransactionModel.swift`

- Model for onchain Bitcoin transactions
- Includes confirmation details, amounts, timestamps
- Provides mock data for previews
- **Status**: Complete ✅

### 3. Updated Protocol
**File**: `Arke/Shared/Data/BarkWalletProtocol.swift`

- Added `getOnchainTransactions()` method to protocol
- **Status**: Complete ✅

### 4. Integrated with BarkWalletFFI
**File**: `Arke/Shared/Data/BarkWalletFFI.swift`

- Modified wallet creation to use BDK instead of `OnchainWallet.default()`
- Added `bdkWallet` property to store BDK instance
- Implemented `getOnchainTransactions()` method
- Updated `tryOpenExistingWallet()`, `createWallet()`, and `importWallet()`
- **Status**: Structure complete, awaiting BDK implementation ⚠️

### 5. Updated Mock Implementations
**Files**: 
- `Arke/Shared/Data/MockBarkWallet.swift`
- `Arke/Arké/Data/BarkWallet.swift`

- Added `getOnchainTransactions()` to both implementations
- **Status**: Complete ✅

## Current Status

### ✅ What Works
- Project compiles successfully
- Integration structure is in place
- Protocol methods are defined
- Mock data available for UI development
- BDK dependency added (version 2.3.0)

### ⚠️ What's Not Implemented
The `BDKOnchainWallet` class is currently a **placeholder**. It needs implementation for:

1. **Wallet Initialization** - Create BDK wallet from mnemonic
2. **Balance Retrieval** - Get confirmed/pending balance
3. **Address Generation** - Generate new receiving addresses
4. **Transaction Building** - Create and sign transactions
5. **PSBT Handling** - Prepare, sign, and finalize PSBTs
6. **Transaction History** - **THIS IS THE KEY FEATURE** ⭐
7. **Blockchain Sync** - Sync with Esplora server
8. **Send/Receive** - Send Bitcoin and track receives

## Why BDK Integration is Challenging

The BDK Swift API changed significantly between versions:
- BDK 0.x had a different API structure
- BDK 1.x introduced major changes
- BDK 2.x (current: 2.3.0) has evolved further

The placeholder code was written for an older API and needs updating.

## Research Findings

I've researched the BDK 2.3.0 API and found these key resources:

### Official Examples
- **BDKSwiftExampleWallet**: https://github.com/bitcoindevkit/BDKSwiftExampleWallet
- **BDKManager**: https://github.com/bdgwallet/bdkmanager-swift  
- **Book of BDK**: https://bookofbdk.com/cookbook/bindings/starter-example/

### Key API Patterns Discovered

From the research, BDK 2.x uses:
- `Connection` for database (but may be different in 2.3.0)
- `EsploraClient` for blockchain sync
- `TxBuilder` for creating transactions
- `Psbt` for signing
- `wallet.transactions()` for transaction history
- `Amount.fromSat(satoshi:)` instead of `fromSat(fromSat:)`
- `FeeRate.fromSatPerVb(satVb:)` with different parameter name

### API Differences from Documentation

The actual BDK 2.3.0 API differs from online examples:
- Parameter names have changed (`satoshi:` vs `fromSat:`)
- Transaction structure is `CanonicalTx` not `TransactionDetails`
- Chain position structure is different
- Some methods may have been renamed

## Next Steps

### Option 1: Complete BDK Integration (Recommended)
Implement the `BDKOnchainWallet` class using BDK 2.3.0 API:

1. **Study BDK Swift 2.3.0 API**
   - Repository: https://github.com/bitcoindevkit/bdk-swift
   - Look at example projects
   - Review test files for API usage

2. **Implement Core Methods**
   ```swift
   // Priority order:
   1. init() - Wallet initialization
   2. sync() - Blockchain synchronization  
   3. getBalance() - Balance retrieval
   4. newAddress() - Address generation
   5. listTransactions() - ⭐ THE KEY FEATURE
   6. prepareTx() / finishTx() - Transaction building
   ```

3. **Test Integration**
   - Test wallet creation/import
   - Test syncing
   - Test transaction history
   - Test sending/receiving

### Option 2: Alternative Approaches

If BDK integration proves too complex:

**A. Use Esplora API Directly**
- Query transaction history via Esplora HTTP API
- Keep using `OnchainWallet.default()` for wallet operations
- Pros: Simpler, fewer dependencies
- Cons: Less integrated, no UTXO control

**B. Wait for Bark Updates**
- The Bark library may add transaction history support
- Pros: Native integration
- Cons: Unknown timeline

**C. Use OnchainWallet.default() for Now**
- Revert to simple implementation
- Add transaction history later
- Pros: Working wallet immediately
- Cons: No transaction history

## Impact on Features

### With BDK (When Implemented)
✅ Full transaction history  
✅ See all onchain deposits  
✅ Track withdrawals  
✅ UTXO control  
✅ Advanced fee management  
✅ Replace-by-fee (RBF)  
✅ Coin control  

### Without BDK (Current State)
✅ Basic wallet operations  
✅ Balance checking  
✅ Address generation  
✅ Sending Bitcoin  
❌ Transaction history  
❌ UTXO visibility  
❌ Advanced features  

## Resources

- **BDK Swift**: https://github.com/bitcoindevkit/bdk-swift
- **BDK Docs**: https://docs.rs/bdk/latest/bdk/
- **BDK Book**: https://bitcoindevkit.org/
- **Bark Docs**: `Arke/Shared/Docs/API/Bark_Types.md`

## Files Modified

```
Created:
- Arke/Shared/Data/BDKOnchainWallet.swift
- Arke/Shared/Models/OnchainTransactionModel.swift
- Arke/Shared/Docs/BDK-Integration-Status.md

Modified:
- Arke/Shared/Data/BarkWalletFFI.swift
- Arke/Shared/Data/BarkWalletProtocol.swift
- Arke/Shared/Data/MockBarkWallet.swift
- Arke/Arké/Data/BarkWallet.swift
```

## Conclusion

The **infrastructure is in place** for BDK integration. The main remaining work is implementing the actual BDK wallet operations in `BDKOnchainWallet.swift` using the BDK 2.3.0 API.

This will unlock **transaction history** - the key feature missing from `OnchainWallet.default()`.

---

**Last Updated**: 2026-02-26  
**BDK Version**: 2.3.0  
**Build Status**: ✅ Compiles successfully
