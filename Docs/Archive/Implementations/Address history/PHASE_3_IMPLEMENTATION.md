# Phase 3: Transaction-Address Integration - Implementation Guide

## ✅ What's Already Done

1. **PersistentAddress model** - Created and added to ModelContainer ✅
2. **AddressService** - Fully implemented with address history ✅
3. **PersistentTransaction** - Already has `receivingAddress` relationship ✅
4. **Internal transfer detection** - Methods already in PersistentTransaction ✅

## 🔧 What Needs to Be Done

### Step 1: Add Helper Method to AddressService

Make `getAddressByString` public so transaction processing can link addresses:

```swift
// Add to AddressService.swift in the "Public Methods" section

/// Get address object by string (for transaction linking)
func getAddressByString(_ address: String) async -> PersistentAddress? {
    return getAddressByString(address)  // Calls private method
}
```

**Location**: Add this around line 225 in AddressService.swift, after `validateGapLimit()`.

---

### Step 2: Find TransactionService

You need to locate the `TransactionService` class (or wherever transactions are created/updated).

Look for:
- File named `TransactionService.swift`
- Method called `refreshTransactions()` or `loadTransactions()`
- Where `PersistentTransaction` objects are created
- The code that processes wallet movements/transactions

---

### Step 3: Add Address Linking in Transaction Processing

Once you find where transactions are created, add this logic:

```swift
// After creating/updating a PersistentTransaction object:

// 1. Link received transactions to addresses
if transaction.type == "received" {
    if let recipientAddress = transaction.address {
        // Mark address as used
        await addressService.markAddressAsUsed(
            address: recipientAddress,
            transaction: transaction
        )
        
        // Link the address to transaction
        if let persistentAddr = await addressService.getAddressByString(recipientAddress) {
            transaction.receivingAddress = persistentAddr
        }
    }
}

// 2. Detect internal transfers (sends to own addresses)
if transaction.type == "sent" {
    if let sendAddress = transaction.address {
        let isOwn = await addressService.isOwnAddress(sendAddress)
        if isOwn {
            // This is an internal transfer!
            transaction.subsystemCategory = "internal_transfer"
            
            // Link to receiving address
            if let persistentAddr = await addressService.getAddressByString(sendAddress) {
                transaction.receivingAddress = persistentAddr
            }
        }
    }
}

// 3. Save the transaction
try modelContext.save()
```

---

### Step 4: Pass AddressService to TransactionService

TransactionService likely needs access to AddressService. 

**In WalletManager.swift** around line 454 where services are initialized:

```swift
private func initializeServices() {
    guard let wallet = wallet else { return }
    
    // Initialize all services with shared task manager and cache manager
    transactionService = TransactionService(
        wallet: wallet, 
        taskManager: taskManager,
        addressService: addressService  // ← Add this parameter
    )
    // ... rest of initialization
}
```

**However**, AddressService isn't initialized yet at this point (it needs ModelContext).

**Better approach**: Pass AddressService later in `setModelContext()`:

```swift
func setModelContext(_ context: ModelContext, ...) {
    // ... existing code ...
    
    // Initialize AddressService now that we have a ModelContext
    if let wallet = wallet, addressService == nil {
        addressService = AddressService(wallet: wallet, taskManager: taskManager, modelContext: context)
    }
    
    transactionService?.setModelContext(context)
    transactionService?.setAddressService(addressService)  // ← Add this
    // ... rest
}
```

---

### Step 5: Update TransactionService

Add a method to set the address service:

```swift
// In TransactionService.swift

private var addressService: AddressService?

func setAddressService(_ service: AddressService?) {
    self.addressService = service
}
```

Then use it in transaction processing (Step 3 code above).

---

## 🎯 Expected Behavior After Implementation

### For Received Transactions:
```
Transaction received → Address marked as used
                   → receivingAddress linked
                   → Usage stats updated (count, total sats)
```

### For Sent Transactions (Internal):
```
Send to own address → isOwnAddress() returns true
                    → subsystemCategory = "internal_transfer"
                    → receivingAddress linked
                    → isInternalTransfer = true
```

### For Sent Transactions (External):
```
Send to external → isOwnAddress() returns false
                → No receivingAddress link
                → Normal "sent" transaction
```

---

## 🧪 Testing

### Test 1: Receive Funds
1. Get a receive address
2. Receive funds to that address
3. Check database: Address should be marked `isUsed = true`
4. Transaction should have `receivingAddress` linked

### Test 2: Internal Transfer
1. Get your current address (e.g., Ark address)
2. Send funds to that same address
3. Check: `transaction.isInternalTransfer` should be `true`
4. Check: `transaction.effectiveType` should be `"internal_transfer"`
5. UI should show "Internal Transfer" icon/label

### Test 3: External Send
1. Send to external address
2. Check: `transaction.isInternalTransfer` should be `false`
3. Check: No `receivingAddress` linked

---

## 🔍 Debugging

### Check if address linking is working:

```swift
// In transaction list or detail view
if let transaction = transaction {
    print("Transaction: \(transaction.txid)")
    print("  Type: \(transaction.type)")
    print("  Address: \(transaction.address ?? "none")")
    print("  Receiving Address: \(transaction.receivingAddress?.address ?? "none")")
    print("  Is Internal: \(transaction.isInternalTransfer)")
    print("  Effective Type: \(transaction.effectiveType)")
}
```

### Check address usage:

```swift
let addresses = await addressService.getAllAddresses()
for addr in addresses {
    print("\(addr.type.displayName): \(addr.address)")
    print("  Used: \(addr.isUsed)")
    print("  Received: \(addr.receivedTransactionCount) transactions")
    print("  Total: \(addr.totalReceivedSats) sats")
}
```

---

## 📋 Checklist

- [ ] Add public `getAddressByString()` to AddressService
- [ ] Find TransactionService (or transaction processing code)
- [ ] Add address linking logic for received transactions
- [ ] Add internal transfer detection for sent transactions
- [ ] Pass AddressService to TransactionService
- [ ] Test receiving funds (address marked as used)
- [ ] Test internal transfer (detected correctly)
- [ ] Test external send (not detected as internal)
- [ ] Update UI to show internal transfer icon/label (optional)

---

## 🎨 UI Enhancement (Optional)

If you want to show internal transfers differently in the UI:

```swift
// In transaction list row:
HStack {
    Image(systemName: transaction.effectiveTypeIcon)
        .foregroundColor(transaction.isInternalTransfer ? .orange : .primary)
    
    Text(transaction.effectiveTypeDisplayName)
}
```

This will show a different icon and color for internal transfers.

---

## 🚀 Next Steps After Phase 3

Once transaction-address linking is working:

1. **Phase 4: UI Updates**
   - Update receive view to show current address (not generate new)
   - Add "Generate New Address" button
   - Show address usage stats
   - Add gap limit warning

2. **Phase 5: Testing**
   - Comprehensive testing of all scenarios
   - Edge case handling
   - Performance testing with many addresses

---

That's it for Phase 3! The hard part is finding where transactions are processed and adding the linking logic there.
