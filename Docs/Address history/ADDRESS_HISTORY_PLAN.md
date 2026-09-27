# Address History Management Plan (Simplified)

## Problem Statement

Currently, `AddressService` calls `wallet.getArkAddress()` and `wallet.getOnchainAddress()` which generate **new addresses** on every call. This creates several issues:

1. **No address history**: The app cannot track which addresses have been generated
2. **Bitcoin gap limit violations**: Creating many unused onchain addresses can exceed the standard BIP44 gap limit (typically 20), making funds harder to recover
3. **Unnecessary Ark address generation**: While Ark addresses can be reused, we keep generating new ones unnecessarily
4. **No address-transaction linking**: Cannot associate received transactions with specific addresses
5. **Cannot detect internal transfers**: When a transaction is sent to an address owned by the wallet, it appears as external send/receive instead of internal transfer

## Solution Overview

Implement a **persistent address history system** using SwiftData models that:
- Tracks all generated Ark and onchain addresses (internal system use)
- Marks addresses as "used" when they receive funds
- Implements intelligent address generation policies
- Respects Bitcoin's gap limit for onchain addresses
- Allows address reuse for Ark (user-initiated generation only)
- Enables detection of internal transfers (wallet-to-wallet transactions)

## Data Models

### 1. PersistentAddress (@Model)

Primary model for tracking address history across both Ark and onchain systems. This is an **internal system model**, not a primary user-facing feature.

```swift
@Model
final class PersistentAddress {
    // Identity
    var id: UUID = UUID()
    var address: String = ""  // The actual address string
    var addressType: String = "ark"  // "ark" or "onchain"
    
    // Generation metadata
    var generatedAt: Date = Date()
    var derivationIndex: Int?  // BIP44 index for onchain addresses (critical for recovery)
    var generatedBy: String = "auto"  // "auto" or "user_request"
    
    // Usage tracking (internal)
    var isUsed: Bool = false  // Has received funds
    var firstUsedAt: Date?  // When first transaction was received
    var lastUsedAt: Date?  // Most recent transaction received
    var receivedTransactionCount: Int = 0
    var totalReceivedSats: Int = 0
    
    // Status
    var isActive: Bool = true  // Can be deactivated (e.g., after wallet restore)
    
    // Relationship to transactions that received to this address
    @Relationship(deleteRule: .nullify, inverse: \PersistentTransaction.receivingAddress)
    var receivedTransactions: [PersistentTransaction]? = []
    
    init(
        id: UUID = UUID(),
        address: String,
        addressType: AddressType,
        generatedAt: Date = Date(),
        derivationIndex: Int? = nil,
        generatedBy: AddressGenerationStrategy = .auto
    ) {
        self.id = id
        self.address = address
        self.addressType = addressType.rawValue
        self.generatedAt = generatedAt
        self.derivationIndex = derivationIndex
        self.generatedBy = generatedBy.rawValue
    }
}
```

### 2. AddressType (enum)

```swift
enum AddressType: String, Codable, CaseIterable {
    case ark = "ark"
    case onchain = "onchain"
    
    var displayName: String {
        switch self {
        case .ark: return "Ark Address"
        case .onchain: return "Bitcoin Address"
        }
    }
    
    var canReuse: Bool {
        switch self {
        case .ark: return true
        case .onchain: return false  // Best practice: one-time use
        }
    }
}
```

### 3. AddressGenerationStrategy (enum)

```swift
enum AddressGenerationStrategy {
    case auto  // System-generated
    case userRequested  // User explicitly requested new address
    
    var rawValue: String {
        switch self {
        case .auto: return "auto"
        case .userRequested: return "user_request"
        }
    }
}
```

## Service Architecture Updates

### AddressService Responsibilities

**Current:**
- Load current addresses from wallet

**New:**
- Manage address history (query, create, update)
- Generate new addresses with policy enforcement
- Mark addresses as used when transactions are detected
- Provide current/active address for receiving
- Handle address labeling and notes

### AddressService New Methods

```swift
// MARK: - Address Retrieval (Replaces direct wallet calls)

/// Get the current address to show for receiving funds
func getCurrentReceiveAddress(type: AddressType) async throws -> PersistentAddress

/// Generate a new address (user explicitly requested)
func generateNewAddress(type: AddressType) async throws -> PersistentAddress

// MARK: - Internal Address Management

/// Mark address as used when transaction is detected
func markAddressAsUsed(address: String, transaction: PersistentTransaction?) async

/// Check if an address belongs to this wallet
func isOwnAddress(_ address: String) async -> Bool

/// Get all addresses (for internal use or settings display)
func getAllAddresses(type: AddressType?) async -> [PersistentAddress]

/// Get unused address count (for gap limit monitoring)
func getUnusedAddressCount(type: AddressType) async -> Int

/// Validate we haven't exceeded gap limit
func validateGapLimit() async throws
```

### Address Policy Engine

New internal component within `AddressService`:

```swift
private struct AddressPolicyEngine {
    // Gap limit for onchain addresses (BIP44 standard)
    static let maxUnusedOnchainAddresses = 20
    
    // Should generate new address based on type and context
    static func shouldGenerateNew(
        type: AddressType,
        unusedCount: Int,
        strategy: AddressGenerationStrategy
    ) -> Bool {
        switch type {
        case .ark:
            // Only generate new Ark address if user explicitly requests
            return strategy == .userRequested
            
        case .onchain:
            // Generate new onchain if:
            // 1. User explicitly requested, OR
            // 2. Current address was used AND we're under gap limit
            return strategy == .userRequested || 
                   (unusedCount == 0 && unusedCount < maxUnusedOnchainAddresses)
        }
    }
    
    // Check if we're approaching gap limit
    static func isApproachingGapLimit(unusedCount: Int) -> Bool {
        return unusedCount >= (maxUnusedOnchainAddresses - 5)
    }
}
```

## Address Generation Flow

### Onchain Address Flow

```
User opens receive screen
    ↓
getCurrentReceiveAddress(.onchain)
    ↓
Query: Get most recent unused onchain address
    ↓
If found: Return existing unused address
If not found:
    ↓
    Check gap limit (unused count < 20)
        ↓
        If OK: Generate new from wallet.getOnchainAddress()
               Save to SwiftData with derivationIndex
               Return new address
        ↓
        If exceeded: Throw GapLimitError
                     Show user warning about address reuse
```

### Ark Address Flow

```
User opens receive screen
    ↓
getCurrentReceiveAddress(.ark)
    ↓
Query: Get most recent Ark address (used or unused)
    ↓
If found: Return existing address (Ark addresses can be reused)
If not found: Generate from wallet.getArkAddress()
              Save to SwiftData
              Return new address
    ↓
User explicitly taps "Generate New Ark Address"
    ↓
generateNewAddress(.ark, .userRequested, label: nil)
    ↓
Call wallet.getArkAddress()
Save to SwiftData
Return new address
```

## Transaction Integration

### PersistentTransaction Updates

Add relationship to receiving address:

```swift
@Model
final class PersistentTransaction {
    // ... existing properties ...
    
    // NEW: Link to the address that received this transaction
    @Relationship(deleteRule: .nullify)
    var receivingAddress: PersistentAddress?
    
    // ... rest of model ...
}
```

### Internal Transfer Detection

With address history, we can now detect when a transaction is an internal transfer:

```swift
extension PersistentTransaction {
    /// Check if this transaction is an internal transfer (to our own address)
    var isInternalTransfer: Bool {
        guard let address = address else { return false }
        // If we're sending to an address we own, it's internal
        return receivingAddress != nil && type == "sent"
    }
    
    /// Get effective type (considering internal transfers)
    var effectiveType: String {
        if isInternalTransfer {
            return "internal_transfer"
        }
        return type
    }
}
```

### Transaction Processing Updates

When processing new transactions from the wallet:

```swift
// In TransactionService or similar
func processNewTransaction(_ movementData: MovementData) async {
    // 1. Create/update PersistentTransaction
    let transaction = // ... create transaction
    
    // 2. If this is a received transaction, find matching address
    if transaction.type == "received", let recipientAddress = movementData.address {
        await addressService.markAddressAsUsed(
            address: recipientAddress,
            transaction: transaction
        )
    }
    
    // 3. If this is a sent transaction, check if it's to our own address
    if transaction.type == "sent", let sendAddress = movementData.address {
        let isInternal = await addressService.isOwnAddress(sendAddress)
        if isInternal {
            // This is an internal transfer, could mark differently
            transaction.subsystemCategory = "internal_transfer"
        }
    }
    
    // 4. Save transaction
}
```

## UI Components

### 1. Receive View Updates

Update existing receive view to use address history:
- Show current address from `getCurrentReceiveAddress()` instead of generating new one
- Display QR code for address
- Show "Generate New Address" button:
  - For Ark: Always available (generates new Ark address on user request)
  - For onchain: Only if current address has been used (prevents gap limit issues)
- Show subtle indicator: "Unused" or "Used X times" (optional, informational only)

### 2. Settings: Address History (Optional)

Simple list in Settings > Advanced showing address history:
- List of all generated addresses
- Each row shows:
  - Address (truncated, tap to copy)
  - Type (Ark / Bitcoin)
  - Status (Used / Unused)
  - Received count (if used)
  - Generated date
- Primarily for debugging and support purposes
- No filtering, searching, or advanced features needed

### 3. Gap Limit Warning

Alert shown when approaching/exceeding gap limit:
```
⚠️ Address Limit Reached

You have 20 unused Bitcoin addresses. To ensure you can recover your wallet, please use an existing address or wait until an address receives funds before generating more.

[OK]
```

## Migration Strategy

### Phase 1: Create Models
1. Add `PersistentAddress` model
2. Add to ModelContainer configuration
3. Create enums and supporting types

### Phase 2: Update AddressService
1. Add SwiftData model context to AddressService
2. Implement address history query methods
3. Implement policy engine for address generation
4. Update `loadAddresses()` to use address history instead of always generating new
5. Add `getCurrentReceiveAddress()` and `generateNewAddress()` methods
6. Add `isOwnAddress()` for internal transfer detection

### Phase 3: Transaction Integration
1. Add `receivingAddress` relationship to `PersistentTransaction`
2. Update transaction processing to link addresses
3. Add internal transfer detection logic
4. Add computed properties for `isInternalTransfer` and `effectiveType`

### Phase 4: UI Updates (Minimal)
1. Update receive view to use `getCurrentReceiveAddress()`
2. Add "Generate New Address" button with proper disabling logic
3. Add gap limit warning alert
4. (Optional) Add simple address list in Settings for debugging

### Phase 5: Testing & Validation
1. Test gap limit enforcement
2. Test address reuse policies (Ark vs onchain)
3. Test internal transfer detection
4. Test wallet restoration (address history rebuild)
5. Performance testing with many addresses

## Edge Cases & Considerations

### 1. Wallet Restoration
When restoring a wallet from seed:
- Clear existing address history (belongs to old wallet)
- Perform address scanning up to gap limit
- Rebuild address history from discovered transactions
- Mark discovered addresses as used

### 2. CloudKit Sync
Address history should sync across devices:
- User may generate address on iPhone, receive on different device
- Both devices need same address history for internal transfer detection
- Use SwiftData's CloudKit integration
- Handle merge conflicts (prefer earliest generation date)

### 3. Address Validation
Before saving address:
- Validate address format (Bitcoin/Ark)
- Check for duplicates in database
- Store derivation index for onchain addresses (critical for recovery)

### 4. Performance
With hundreds of addresses:
- Index frequently queried fields (address, addressType, isUsed)
- Cache current receive addresses in AddressService
- Use efficient queries for `isOwnAddress()` checks
- Lazy load transaction relationships

### 5. Internal Transfer Detection
When checking if address is owned by wallet:
- Query `PersistentAddress` table first (fast)
- If not found, address is external
- Use this for transaction categorization
- Consider caching frequently checked addresses

### 6. Derivation Index Tracking
For onchain addresses:
- **Critical**: Store BIP44 derivation index
- Enables proper wallet recovery
- Must be sequential (0, 1, 2, 3...)
- Track highest used index for gap limit calculation

### 7. Address Discovery on Sync
When wallet syncs with blockchain:
- May discover receives to addresses not yet in database
- Add these as `generatedBy: "discovered"`
- Still respect gap limit for future generation
- Update usage statistics

## Database Schema

### ModelContainer Updates

```swift
.modelContainer(for: [
    // Existing models
    PersistentTransaction.self,
    ArkBalanceModel.self,
    OnchainBalanceModel.self,
    PersistentTag.self,
    TransactionTagAssignment.self,
    PersistentContact.self,
    TransactionContactAssignment.self,
    PersistentContactAddress.self,
    WalletConfiguration.self,
    DeviceRegistration.self,
    
    // NEW: Address management
    PersistentAddress.self
])
```

### SwiftData Queries

Common queries to implement in AddressService:

```swift
// Get current unused onchain address
func getUnusedOnchainAddress(context: ModelContext) -> PersistentAddress? {
    let descriptor = FetchDescriptor<PersistentAddress>(
        predicate: #Predicate<PersistentAddress> { address in
            address.addressType == "onchain" && !address.isUsed && address.isActive
        },
        sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
    )
    return try? context.fetch(descriptor).first
}

// Get most recent Ark address (can be used or unused)
func getMostRecentArkAddress(context: ModelContext) -> PersistentAddress? {
    let descriptor = FetchDescriptor<PersistentAddress>(
        predicate: #Predicate<PersistentAddress> { address in
            address.addressType == "ark" && address.isActive
        },
        sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
    )
    return try? context.fetch(descriptor).first
}

// Check if address is owned by wallet
func isOwnAddress(_ address: String, context: ModelContext) -> Bool {
    let descriptor = FetchDescriptor<PersistentAddress>(
        predicate: #Predicate<PersistentAddress> { addr in
            addr.address == address && addr.isActive
        }
    )
    let results = try? context.fetch(descriptor)
    return !(results?.isEmpty ?? true)
}

// Count unused addresses for gap limit
func countUnusedAddresses(type: AddressType, context: ModelContext) -> Int {
    let descriptor = FetchDescriptor<PersistentAddress>(
        predicate: #Predicate<PersistentAddress> { address in
            address.addressType == type.rawValue && !address.isUsed && address.isActive
        }
    )
    return (try? context.fetchCount(descriptor)) ?? 0
}
```

## Success Metrics

### Technical Goals
- ✅ Zero gap limit violations
- ✅ All received transactions linked to addresses
- ✅ Address history persists across app launches
- ✅ Internal transfers correctly detected
- ✅ Sync works across devices
- ✅ Efficient `isOwnAddress()` lookups

### Functional Goals
- ✅ Ark addresses reused unless user requests new one
- ✅ Onchain addresses follow best practices (one per use)
- ✅ Gap limit respected (max 20 unused onchain addresses)
- ✅ Derivation indices properly tracked for recovery

### Performance Goals
- ✅ Address lookup < 50ms
- ✅ New address generation < 200ms
- ✅ Internal transfer check < 100ms
- ✅ Handles 1000+ addresses efficiently

## Future Enhancements (Post-MVP)

### Potential Additions
1. **Advanced Settings UI**: More detailed address history view for power users
2. **Address Labeling**: Allow users to label specific addresses
3. **Address Analytics**: Show which addresses received most funds
4. **Export Address List**: For external monitoring/accounting
5. **Watch-Only Addresses**: Import external addresses for tracking
6. **Address QR Codes**: Generate and save QR codes for each address
7. **Payment Request URIs**: BIP21 URIs with amounts and messages

---

## Summary

This plan establishes a **simplified, internal-focused address management system** that:

1. **Solves core technical problems**: Gap limit compliance, address history tracking, internal transfer detection
2. **Follows Bitcoin best practices**: BIP44 compliance, gap limit respect, derivation index tracking
3. **Minimal UI impact**: Primary changes are backend/service layer, with simple receive view updates
4. **Enables key features**: Internal transfer detection, address-transaction linking, proper recovery
5. **Future-proof**: Foundation for advanced features if needed later

The focus is on **internal system functionality** rather than user-facing features. Address history is primarily used by the app itself to:
- Respect gap limits
- Detect internal transfers  
- Link transactions to addresses
- Enable proper wallet recovery

---

**Next Steps**: Review this simplified plan, then proceed with Phase 1 implementation (creating the `PersistentAddress` model).
