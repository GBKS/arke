# Address History Implementation Guide

## ✅ Phase 1: Models Created

I've created all the necessary data models:

1. **AddressType.swift** - Enum for address types (ark/onchain)
2. **AddressGenerationStrategy.swift** - Enum for tracking how addresses were generated
3. **PersistentAddress.swift** - SwiftData model for address history
4. **AddressErrors.swift** - Error types for address operations
5. **Updated Arke_mobile.swift** - Added PersistentAddress to ModelContainer

## ✅ Phase 2: AddressService Rewritten

The AddressService has been completely rewritten with:

- Address history tracking instead of always generating new addresses
- Gap limit enforcement (max 20 unused onchain addresses)
- Internal transfer detection support (`isOwnAddress()`)
- Derivation index tracking for onchain addresses
- Smart address reuse (Ark can reuse, onchain generates new after use)

## 🔧 Phase 2 Remaining: Update AddressService Initialization

### Where AddressService needs ModelContext

The AddressService now requires a `ModelContext` parameter in its initializer:

```swift
init(wallet: BarkWalletProtocol, taskManager: TaskDeduplicationManager, modelContext: ModelContext)
```

### Files that likely need updates:

1. **WalletManager** (or wherever AddressService is instantiated)
   - Pass `modelContext` from the environment
   - Example:
   ```swift
   // Old:
   addressService = AddressService(wallet: wallet, taskManager: taskManager)
   
   // New:
   addressService = AddressService(
       wallet: wallet, 
       taskManager: taskManager, 
       modelContext: modelContext
   )
   ```

2. **Any preview or test code** that creates AddressService

### How to get ModelContext:

In views that need to pass it:
```swift
@Environment(\.modelContext) private var modelContext
```

Then pass it when creating/initializing WalletManager or services.

---

## 📋 Phase 3: Transaction Integration (TODO)

### Step 3.1: Update PersistentTransaction

Add the receiving address relationship:

```swift
// In PersistentTransaction.swift, add:

// MARK: - Address Relationship

/// The address that received this transaction (if applicable)
@Relationship(deleteRule: .nullify)
var receivingAddress: PersistentAddress?

// MARK: - Internal Transfer Detection

/// Check if this transaction is an internal transfer (to our own address)
var isInternalTransfer: Bool {
    guard type == "sent", let _ = receivingAddress else { return false }
    return true
}

/// Get effective type (considering internal transfers)
var effectiveType: String {
    if isInternalTransfer {
        return "internal_transfer"
    }
    return type
}
```

### Step 3.2: Update Transaction Processing

Wherever transactions are created/processed, add address linking:

```swift
// When processing received transaction:
if transaction.type == "received", let recipientAddress = movementData.address {
    await addressService.markAddressAsUsed(
        address: recipientAddress,
        transaction: transaction
    )
    
    // Link the address to the transaction
    if let persistentAddr = await addressService.getAddressByString(recipientAddress) {
        transaction.receivingAddress = persistentAddr
    }
}

// When processing sent transaction (check if internal):
if transaction.type == "sent", let sendAddress = transaction.address {
    let isInternal = await addressService.isOwnAddress(sendAddress)
    if isInternal {
        transaction.subsystemCategory = "internal_transfer"
        
        // Link to receiving address if it exists
        if let persistentAddr = await addressService.getAddressByString(sendAddress) {
            transaction.receivingAddress = persistentAddr
        }
    }
}
```

### Step 3.3: Make helper method public

Add this to AddressService:

```swift
/// Get address object by string (for transaction linking)
func getAddressByString(_ address: String) async -> PersistentAddress? {
    return getAddressByString(address)
}
```

---

## 📋 Phase 4: UI Updates (TODO)

### Step 4.1: Update Receive View

The receive view should now use `getCurrentReceiveAddress()`:

```swift
// Instead of:
await addressService.loadAddresses()
let address = addressService.arkAddress  // or onchainAddress

// Use:
let persistentAddress = try await addressService.getCurrentReceiveAddress(type: .ark)
let address = persistentAddress.address
```

### Step 4.2: Add "Generate New Address" Button

For user-requested address generation:

```swift
Button("Generate New Address") {
    Task {
        do {
            let newAddress = try await addressService.generateNewAddress(
                type: .ark,  // or .onchain
                strategy: .userRequested
            )
            // Update UI with new address
        } catch AddressError.gapLimitExceeded(let count) {
            // Show gap limit warning
            showGapLimitAlert = true
        }
    }
}
```

### Step 4.3: Add Gap Limit Warning Alert

```swift
.alert("Address Limit Reached", isPresented: $showGapLimitAlert) {
    Button("OK", role: .cancel) { }
} message: {
    Text("You have 20 unused Bitcoin addresses. To ensure you can recover your wallet, please use an existing address or wait until an address receives funds before generating more.")
}
```

### Step 4.4: (Optional) Address History in Settings

Simple list view:

```swift
struct AddressHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var addresses: [PersistentAddress] = []
    
    var body: some View {
        List(addresses) { address in
            VStack(alignment: .leading) {
                Text(address.address)
                    .font(.caption)
                    .lineLimit(1)
                
                HStack {
                    Text(address.type.displayName)
                    Spacer()
                    Text(address.isUsed ? "Used" : "Unused")
                        .foregroundColor(address.isUsed ? .green : .gray)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Address History")
        .task {
            await loadAddresses()
        }
    }
    
    func loadAddresses() async {
        let descriptor = FetchDescriptor<PersistentAddress>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        addresses = (try? modelContext.fetch(descriptor)) ?? []
    }
}
```

---

## 📋 Phase 5: Testing (TODO)

### Test Cases

1. **Gap Limit Enforcement**
   - Generate 20 onchain addresses without using them
   - Attempt to generate 21st should throw error
   - Use one address, then should be able to generate new one

2. **Address Reuse**
   - Ark address should reuse same address
   - Onchain should generate new after use

3. **Internal Transfer Detection**
   - Send to own address
   - Verify `isInternalTransfer` is true
   - Verify `effectiveType` shows "internal_transfer"

4. **Derivation Index Tracking**
   - Generate multiple onchain addresses
   - Verify indices are sequential (0, 1, 2, 3...)
   - Verify stored correctly in database

5. **Address Discovery**
   - Wallet sync discovers used address not in database
   - Verify added with `generatedBy: "discovered"`
   - Verify marked as used

---

## 🔍 Next Immediate Steps

### 1. Find WalletManager and update AddressService initialization

Search for where `AddressService` is created and add `modelContext` parameter.

Example locations to check:
- `WalletManager.swift`
- Any service container or dependency injection code
- Test files or preview helpers

### 2. Test basic functionality

Once AddressService is initialized correctly:
- Run the app
- Check that addresses load from history
- Verify no crashes

### 3. Then proceed to Phase 3

Add transaction integration once basic address history is working.

---

## 📚 Key Benefits of This Implementation

1. **Gap Limit Compliance** ✅
   - Never exceeds 20 unused onchain addresses
   - Proper BIP44 recovery support

2. **Internal Transfer Detection** ✅
   - Can detect when sending to own address
   - Prevents confusion in transaction list

3. **Address-Transaction Linking** ✅
   - Know which transactions used which addresses
   - Enables address-based analytics

4. **Smart Reuse** ✅
   - Ark addresses reused (efficient)
   - Onchain addresses follow best practices

5. **Derivation Index Tracking** ✅
   - Critical for wallet recovery
   - Enables proper BIP44 compliance

---

## 🐛 Potential Issues to Watch For

1. **Migration**: Existing users may have transactions but no address history
   - Solution: Addresses will be created lazily as needed
   - Old transactions won't have `receivingAddress` linked (acceptable)

2. **Performance**: Querying database for every `isOwnAddress()` check
   - Solution: Consider caching address strings in memory Set
   - Only needed if performance becomes issue

3. **Sync Conflicts**: Two devices generate addresses simultaneously
   - Solution: CloudKit will sync, may have some duplicates
   - `isActive` flag can deactivate duplicates if needed

4. **Wallet Restore**: Need to rebuild address history
   - Solution: Implement address scanning up to gap limit
   - Can be added later as enhancement

---

## 📝 Summary

**Completed:**
- ✅ All data models created
- ✅ AddressService rewritten with history support
- ✅ ModelContainer updated
- ✅ Gap limit enforcement implemented
- ✅ Internal transfer detection support added

**Remaining:**
- 🔧 Update AddressService initialization to pass ModelContext
- 📋 Add transaction-address linking (Phase 3)
- 📋 Update receive UI (Phase 4)
- 📋 Add testing (Phase 5)

The foundation is solid and follows your existing patterns (similar to Tags/Contacts). Once you update the initialization, the basic system will work!
