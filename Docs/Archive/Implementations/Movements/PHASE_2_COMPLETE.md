# Phase 2 Complete: Rich Swift Models

## ✅ Completed Tasks

### Task 2.1: PaymentMethod Enum ✅
**File:** `PaymentMethod.swift`

**Features:**
- Strongly-typed enum for all payment method types
- Heuristic detection from address strings
- Rich properties for UI display and logic

**Supported Types:**
- `.ark(address:)` - Ark offchain addresses (ark1...)
- `.bitcoin(address:)` - Bitcoin onchain addresses (bc1, tb1, legacy)
- `.invoice(value:)` - BOLT11 Lightning invoices (lnbc, lntb)
- `.offer(value:)` - BOLT12 Lightning offers (lno1)
- `.lightningAddress(value:)` - Lightning addresses (email format)
- `.outputScript(hex:)` - Hex-encoded Bitcoin scripts
- `.unknown(value:)` - Fallback for unrecognized formats

**Properties:**
```swift
paymentMethod.displayType       // "Lightning Invoice"
paymentMethod.shortDisplayType  // "LN Invoice"
paymentMethod.systemIcon        // "bolt.fill"
paymentMethod.iconColorName     // "yellow"
paymentMethod.isLightning       // true/false
paymentMethod.isOnchain         // true/false
paymentMethod.isArkOffchain     // true/false
```

**Detection Logic:**
- Prefix matching (ark1, bc1, lnbc, etc.)
- Lightning address validation (user@domain)
- Hex script detection
- Fallback to unknown

---

### Task 2.2: MovementDestination Struct ✅
**File:** `MovementDestination.swift`

**Purpose:**
Wraps payment addresses with payment method information and display helpers.

**Properties:**
```swift
destination.paymentMethod      // PaymentMethod enum
destination.address           // Original string
destination.shortAddress      // Truncated for UI
destination.veryShortAddress  // Very compact version
destination.displayText       // "LN Invoice: lnbc...xyz"
destination.fullDisplayText   // Full address with type
```

**Type Checks:**
```swift
destination.isLightning       // Convenience for paymentMethod.isLightning
destination.isOnchain         // Convenience for paymentMethod.isOnchain
destination.isArkOffchain     // Convenience for paymentMethod.isArkOffchain
```

**Factory Method:**
```swift
MovementDestination.fromAddress("ark1pm6...")  // Auto-detects payment method
```

---

### Task 2.3: Movement Metadata Models ✅
**File:** `MovementMetadata.swift`

**Subsystem-Specific Metadata:**

#### BoardMetadata (bark.board)
```swift
metadata.onchainFeeSat  // Bitcoin network fees
metadata.chainAnchor    // Blockchain anchor reference
```

#### LightningMetadata (bark.lightning_send/receive)
```swift
metadata.paymentHash      // Payment hash identifier
metadata.htlcVtxos        // Array of HTLC VTXO IDs
metadata.hasActiveHtlcs   // Bool convenience property
metadata.htlcCount        // Int convenience property
```

#### RoundMetadata (bark.round)
```swift
metadata.fundingTxid  // Round funding transaction ID
```

**Parser:**
```swift
MovementMetadataParser.parse(json: metadataJson, subsystemName: "bark.board")
// Returns: BoardMetadata?
```

**Convenience Extensions:**
```swift
metadata.asBoard      // Cast to BoardMetadata?
metadata.asLightning  // Cast to LightningMetadata?
metadata.asRound      // Cast to RoundMetadata?
```

---

### Task 2.4: Movement Category System ✅
**File:** `MovementCategory.swift`

**Categories:**
- `.offchainTransfer` - bark.arkoor send/receive
- `.boarding` - bark.board
- `.exit` - bark.exit
- `.lightningSend` - bark.lightning_send
- `.lightningReceive` - bark.lightning_receive
- `.offboarding` - bark.round offboard
- `.onchainSend` - bark.round send_onchain
- `.refresh` - bark.round refresh
- `.unknown` - Fallback

**Properties:**
```swift
category.displayName            // "Lightning Send"
category.shortDisplayName       // "LN Send"
category.description           // Full description
category.icon                  // SF Symbol name
category.iconColorName         // Color theme
category.showInHistoryByDefault // Bool for filtering
category.isLightning           // Type checks
category.isOnchain
category.isOffchain
category.isMaintenance
```

**Detection:**
```swift
MovementCategory.from(
    subsystemName: "bark.lightning_send",
    subsystemKind: "send"
)
// Returns: .lightningSend
```

**Filter Groups:**
```swift
MovementCategory.FilterGroup.lightning.matches(category)
// Returns: true if category is Lightning-related
```

Available filter groups:
- `.all` - All movements
- `.offchain` - Ark-to-Ark transfers
- `.lightning` - Lightning Network payments
- `.onchain` - Bitcoin onchain operations
- `.maintenance` - Refresh operations

---

## Key Features

### Type Safety
✅ No more string comparisons - use enums  
✅ Compile-time checking of payment types  
✅ Pattern matching support

### Rich Metadata
✅ Parse subsystem-specific JSON into typed structs  
✅ Convenience properties for common checks  
✅ Extension-based casting for safety

### Display Helpers
✅ Multiple display formats (full, short, icon)  
✅ Color themes for visual consistency  
✅ SF Symbols integration

### Smart Detection
✅ Automatic payment method detection from strings  
✅ Category inference from subsystem names  
✅ Fallback to unknown for unrecognized formats

---

## Usage Examples

### Detect Payment Method
```swift
let method = PaymentMethod.detect(from: "lnbc100u1...")
print(method.displayType)  // "Lightning Invoice"
print(method.systemIcon)   // "bolt.fill"
```

### Create Destination
```swift
let destination = MovementDestination.fromAddress("ark1pm6...")
print(destination.paymentMethod.isArkOffchain)  // true
print(destination.shortAddress)  // "ark1pm6...xyz"
```

### Parse Metadata
```swift
if let metadata = MovementMetadataParser.parse(
    json: movement.metadataJson,
    subsystemName: "bark.lightning_send"
) as? LightningMetadata {
    print("Payment hash: \(metadata.paymentHash)")
    print("HTLC count: \(metadata.htlcCount)")
}
```

### Categorize Movement
```swift
let category = MovementCategory.from(
    subsystemName: "bark.round",
    subsystemKind: "refresh"
)

if category.isMaintenance {
    print("This is a maintenance operation")
}
```

---

## Integration Points

These models are now ready to be integrated into:

1. **TransactionService.swift** - Enhanced MovementData parsing
2. **Transaction UI** - Display payment method icons and types
3. **Filtering** - Category-based transaction filtering
4. **Detail Views** - Show metadata (payment hashes, fees, txids)
5. **Search** - Search by payment method type
6. **Analytics** - Track usage by category

---

## Next Steps: Phase 3

Ready to integrate these models into TransactionService with:
- Enhanced MovementData with computed properties
- Subsystem-aware transaction parsing
- Rich metadata storage

**Estimated time spent:** 30 minutes  
**Status:** ✅ Complete - Models are fully functional and tested

---

## Files Created

1. `PaymentMethod.swift` - Payment method enum with detection
2. `MovementDestination.swift` - Destination wrapper with helpers
3. `MovementMetadata.swift` - Subsystem metadata models + parser
4. `MovementCategory.swift` - Movement categorization system

All models are:
- ✅ Codable
- ✅ Hashable  
- ✅ Sendable (thread-safe)
- ✅ Well-documented
- ✅ Ready for SwiftUI
