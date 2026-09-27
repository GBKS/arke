# Before & After: AddressValidator Refactoring

## Problem Statement

The original `ParsedAddress` model treated all addresses as single entities with a "primary" address and optional metadata. This design couldn't properly represent BIP-21 URIs that contain multiple payment destinations (e.g., Bitcoin + Ark + Lightning).

---

## Before: ParsedAddress Model

### Old Structure
```swift
struct ParsedAddress {
    let format: AddressFormat
    let network: BitcoinNetwork?
    let originalString: String
    let address: String              // Only ONE address
    let amount: Int?
    let label: String?
    let message: String?
    let scanPublicKey: Data?
    let spendPublicKey: Data?
}
```

### Problems
1. **Can't represent multiple destinations**: BIP-21 URIs with `ark=...` or `lightning=...` parameters lost alternative payment methods
2. **Conceptual mismatch**: Treated payment metadata and destination as the same thing
3. **No way to query alternatives**: Users couldn't choose between payment methods
4. **Confusing for BIP-21**: Was the "address" the URI or the extracted address?

### Example Problem
```swift
// Input: BIP-21 with Ark alternative
let uri = "bitcoin:bc1q...?ark=ark1..."

// Old behavior: Lost the Ark address!
let parsed = AddressValidator.parseAddress(uri)
print(parsed.address)  // "bc1q..." - Ark address is gone!
```

---

## After: PaymentRequest + PaymentDestination Model

### New Structure
```swift
struct PaymentDestination {
    let format: AddressFormat
    let network: BitcoinNetwork?
    let address: String
    let scanPublicKey: Data?
    let spendPublicKey: Data?
}

struct PaymentRequest {
    let destinations: [PaymentDestination]  // Multiple destinations!
    let amount: Int?
    let label: String?
    let message: String?
    let originalString: String
}
```

### Solutions
1. ✅ **Represents multiple destinations**: Array of `PaymentDestination` objects
2. ✅ **Clear separation**: Payment metadata (what) vs destinations (where)
3. ✅ **Rich querying**: Filter by format, network, or priority
4. ✅ **Flexible**: Easy to add new destination types

### Example Solution
```swift
// Input: Same BIP-21 with Ark alternative
let uri = "bitcoin:bc1q...?ark=ark1..."

// New behavior: Preserves all payment options!
let request = AddressValidator.parsePaymentRequest(uri)
print(request.destinations.count)  // 2

// Primary (Bitcoin address from path)
print(request.primaryDestination?.address)  // "bc1q..."

// Alternative (Ark from query param)
print(request.firstDestination(for: .ark)?.address)  // "ark1..."
```

---

## Usage Comparison

### Parsing a Simple Address

#### Before
```swift
if let parsed = AddressValidator.parseAddress("bc1q...") {
    print(parsed.format.displayName)
    print(parsed.address)
    print(parsed.network?.displayName ?? "N/A")
}
```

#### After
```swift
if let request = AddressValidator.parsePaymentRequest("bc1q...") {
    print(request.primaryFormat?.displayName ?? "N/A")
    print(request.primaryAddress ?? "")
    print(request.primaryNetwork?.displayName ?? "N/A")
}
```

---

### Parsing a BIP-21 URI with Alternatives

#### Before (Lost Information!)
```swift
let uri = "bitcoin:bc1q...?amount=0.001&ark=ark1...&lightning=lnbc..."

if let parsed = AddressValidator.parseAddress(uri) {
    print(parsed.address)  // "bc1q..."
    print(parsed.amount)   // 100000 sats
    // ❌ Ark and Lightning addresses are LOST!
}
```

#### After (Preserves Everything!)
```swift
let uri = "bitcoin:bc1q...?amount=0.001&ark=ark1...&lightning=lnbc..."

if let request = AddressValidator.parsePaymentRequest(uri) {
    print(request.primaryAddress ?? "")  // "bc1q..."
    print(request.amount ?? 0)           // 100000 sats
    
    // ✅ All alternatives are preserved!
    print("Has alternatives: \(request.hasAlternatives)")  // true
    
    // Access specific payment methods
    if let arkDest = request.firstDestination(for: .ark) {
        print("Ark: \(arkDest.address)")
    }
    
    if let lnDest = request.firstDestination(for: .lightningInvoice) {
        print("Lightning: \(lnDest.address)")
    }
}
```

---

### Querying and Filtering

#### Before (Not Possible)
```swift
// ❌ Can't query alternatives - they don't exist!
// ❌ Can't filter by multiple criteria
// ❌ Can't check what payment methods are available
```

#### After (Rich API)
```swift
if let request = AddressValidator.parsePaymentRequest(uri) {
    // Check support
    if request.supports(.ark) {
        print("Supports Ark payments")
    }
    
    // Filter by format
    let bitcoinDests = request.destinations(for: .bitcoin)
    let arkDests = request.destinations(for: .ark)
    
    // Filter by network
    let mainnetConfig = NetworkConfig(networkType: .mainnet)
    let mainnetDests = request.destinations(for: mainnetConfig)
    
    // Or create a filtered copy
    if let mainnetOnly = request.filtered(for: mainnetConfig) {
        // New PaymentRequest with only mainnet-compatible destinations
    }
}
```

---

### Creating BIP-21 URIs

#### Before
```swift
let uri = BIP21URIHelper.createBIP21URI(
    arkAddress: "ark1...",
    onchainAddress: "bc1q...",
    amount: "0.001",
    label: "Payment"
)
// ❌ No support for Lightning
// ❌ No support for Silent Payments
```

#### After
```swift
let uri = BIP21URIHelper.createBIP21URI(
    arkAddress: "ark1...",
    onchainAddress: "bc1q...",
    lightningInvoice: "lnbc...",      // ✅ Now supported!
    silentPaymentsAddress: "sp1...",   // ✅ Now supported!
    amount: "0.001",
    label: "Payment"
)

// Or create from a PaymentRequest object
let newURI = BIP21URIHelper.createBIP21URI(from: request)
```

---

### UI Integration

#### Before
```swift
struct ClipboardAddressBanner: View {
    let parsedAddress: ParsedAddress  // Single address only
    
    var body: some View {
        VStack {
            Text(parsedAddress.format.displayName)
            Text(parsedAddress.address)
            // ❌ Can't show alternatives
        }
    }
}
```

#### After
```swift
struct ClipboardAddressBanner: View {
    let paymentRequest: PaymentRequest  // Multiple destinations!
    
    var body: some View {
        VStack {
            // Show primary
            if let primary = paymentRequest.primaryDestination {
                Text(primary.format.displayName)
                Text(primary.address)
            }
            
            // ✅ Show alternatives!
            if paymentRequest.hasAlternatives {
                Text("Alternative payment options:")
                ForEach(paymentRequest.alternativeDestinations) { dest in
                    HStack {
                        Image(systemName: iconFor(dest.format))
                        Text(dest.format.displayName)
                        Text(dest.shortAddress)
                    }
                }
            }
        }
    }
}
```

---

## Real-World Use Case

### Scenario: Coffee Shop Payment

A coffee shop wants to accept payment via:
- Bitcoin (on-chain for large orders)
- Ark (instant settlement for small purchases)
- Lightning (lowest fees)

#### Before: Had to choose ONE
```swift
// Could only generate one QR code
let bitcoinQR = generateQR(for: "bc1q...")
// OR
let arkQR = generateQR(for: "ark1...")
// OR  
let lightningQR = generateQR(for: "lnbc...")

// Customer has to scan the right one for their wallet
```

#### After: ONE QR with ALL options
```swift
// Generate a unified BIP-21 URI
let unifiedURI = BIP21URIHelper.createBIP21URI(
    arkAddress: "ark1...",
    onchainAddress: "bc1q...",
    lightningInvoice: "lnbc...",
    amount: "0.001",
    label: "Coffee Shop - Order #123"
)

// One QR code for everything!
let qrCode = generateQR(for: unifiedURI)

// Customer's wallet automatically chooses the best option
if let request = AddressValidator.parsePaymentRequest(unifiedURI) {
    if wallet.supportsLightning && request.supports(.lightningInvoice) {
        // Use Lightning for instant, cheap payment
    } else if wallet.supportsArk && request.supports(.ark) {
        // Use Ark for instant settlement
    } else {
        // Fall back to on-chain Bitcoin
    }
}
```

---

## Migration Benefits

### For Users
- ✅ More payment options in a single QR code
- ✅ Wallet can automatically choose best payment method
- ✅ Better UX with fallback options
- ✅ See all available payment methods before choosing

### For Developers
- ✅ Cleaner, more maintainable code
- ✅ Easier to add new payment methods
- ✅ Better separation of concerns
- ✅ More flexible querying and filtering
- ✅ Future-proof architecture

### For the Protocol
- ✅ Proper support for BIP-21 multi-destination URIs
- ✅ Enables unified payment requests
- ✅ Better interoperability with other wallets
- ✅ Follows industry best practices

---

## Summary

| Aspect | Before | After |
|--------|--------|-------|
| **Model** | Single `ParsedAddress` | `PaymentRequest` + `PaymentDestination` |
| **Destinations** | 1 only | Multiple (array) |
| **BIP-21 Alternatives** | ❌ Lost | ✅ Preserved |
| **Querying** | ❌ Not possible | ✅ Rich API |
| **Filtering** | ❌ Limited | ✅ By format & network |
| **UI Display** | Shows one option | Shows all options |
| **Flexibility** | Rigid | Extensible |
| **Separation of Concerns** | Mixed | Clear |

The refactoring transforms AddressValidator from a simple address parser into a powerful payment request system that properly handles the complexity of modern Bitcoin payment standards.
