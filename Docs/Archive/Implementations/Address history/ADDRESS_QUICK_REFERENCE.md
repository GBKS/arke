# Address History Quick Reference

## 🎯 What Was Implemented

### Phase 1: ✅ Complete
- `AddressType.swift` - Enum for ark/onchain
- `AddressGenerationStrategy.swift` - How addresses are generated
- `PersistentAddress.swift` - SwiftData model
- `AddressErrors.swift` - Error types
- `PersistentTransaction+AddressRelationship.swift` - Helper extension
- Updated `Arke_mobile.swift` - Added to ModelContainer

### Phase 2: ✅ Complete (but needs wiring)
- `AddressService.swift` - Completely rewritten with:
  - `getCurrentReceiveAddress()` - Get address for receiving
  - `generateNewAddress()` - User-requested new address
  - `isOwnAddress()` - Check if address belongs to wallet
  - `markAddressAsUsed()` - Track address usage
  - Gap limit enforcement
  - Derivation index tracking

## 🔌 What You Need to Wire Up

### 1. AddressService Initialization

**Find where AddressService is created** (likely in WalletManager or similar):

```swift
// OLD:
let addressService = AddressService(
    wallet: wallet,
    taskManager: taskManager
)

// NEW:
let addressService = AddressService(
    wallet: wallet,
    taskManager: taskManager,
    modelContext: modelContext  // ← Add this
)
```

### 2. Transaction Processing (for internal transfer detection)

**In your transaction processing code:**

```swift
// For received transactions:
if transaction.type == "received", let address = transaction.address {
    await addressService.markAddressAsUsed(
        address: address,
        transaction: transaction
    )
}

// For sent transactions (check if internal):
if transaction.type == "sent", let address = transaction.address {
    if await addressService.isOwnAddress(address) {
        // This is an internal transfer!
        transaction.subsystemCategory = "internal_transfer"
    }
}
```

### 3. Update PersistentTransaction Model

**Add this property to PersistentTransaction.swift:**

```swift
/// The address that received this transaction (if applicable)
@Relationship(deleteRule: .nullify)
var receivingAddress: PersistentAddress?
```

Then the extension in `PersistentTransaction+AddressRelationship.swift` will work.

## 📱 UI Changes (Optional but Recommended)

### Receive View

```swift
// Instead of always generating new:
let address = try await addressService.getCurrentReceiveAddress(type: .ark)

// Show QR code for address.address
// Add "Generate New" button that calls:
try await addressService.generateNewAddress(type: .ark)
```

### Gap Limit Alert

```swift
.alert("Address Limit Reached", isPresented: $showGapLimit) {
    Button("OK") { }
} message: {
    Text("You have 20 unused Bitcoin addresses. Please use an existing address before generating more.")
}
```

## 🧪 How to Test

1. **Run the app** - Should load existing address or create first one
2. **Receive funds** - Address should be marked as used
3. **Generate 20 addresses** - 21st should show error
4. **Send to yourself** - Should detect as internal transfer

## 🔍 Debugging

### Check if addresses are being saved:

```swift
let addresses = await addressService.getAllAddresses()
print("Total addresses: \(addresses.count)")
for addr in addresses {
    print("  \(addr.type.displayName): \(addr.address) - Used: \(addr.isUsed)")
}
```

### Check gap limit:

```swift
let unusedCount = await addressService.getUnusedAddressCount(type: .onchain)
print("Unused onchain addresses: \(unusedCount)")
```

### Check internal transfer detection:

```swift
let isOwn = await addressService.isOwnAddress("bc1q...")
print("Is own address: \(isOwn)")
```

## 📊 Key Behaviors

| Address Type | Reuse Policy | Gap Limit | Derivation Index |
|-------------|-------------|-----------|------------------|
| Ark | ✅ Reuses same address | ❌ N/A | ❌ N/A |
| Onchain | ❌ New after use | ✅ Max 20 unused | ✅ Sequential |

## 🎨 Architecture

```
┌─────────────────┐
│ AddressService  │
│                 │
│ - Cache current │
│ - Query history │
│ - Generate new  │
│ - Track usage   │
└────────┬────────┘
         │
         ├─────────────┐
         │             │
         ▼             ▼
┌─────────────┐  ┌──────────────────┐
│ Wallet FFI  │  │ PersistentAddress│
│ (Generates) │  │  (Tracks/Stores) │
└─────────────┘  └──────────────────┘
                          │
                          ▼
                 ┌──────────────────┐
                 │ PersistentTx     │
                 │ - receivingAddr  │
                 │ - isInternal     │
                 └──────────────────┘
```

## ✅ Success Criteria

- [ ] App runs without crashes
- [ ] Addresses load from history (not always new)
- [ ] Ark address reuses same one
- [ ] Onchain generates new after use
- [ ] Gap limit prevents 21+ unused addresses
- [ ] Internal transfers detected correctly
- [ ] Derivation indices sequential

## 🐛 Common Issues

**"Type 'AddressService' has no member 'modelContext'"**
→ You need to pass modelContext in init, not store it wrong

**"Cannot find PersistentAddress in scope"**
→ Make sure file is added to target

**"Gap limit exceeded on first run"**
→ Check if old addresses were migrated incorrectly

**"Internal transfers not detected"**
→ Make sure you added `receivingAddress` property to PersistentTransaction

---

That's it! The hard work is done. Just wire up the initialization and you're good to go! 🚀
