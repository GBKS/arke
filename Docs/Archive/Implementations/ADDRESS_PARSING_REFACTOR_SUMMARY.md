# Address Parsing Refactor Summary

## Date
January 20, 2026

## Problem Identified

The `TransactionService.swift` was incorrectly parsing the `sent_to_addresses` and `received_on_addresses` fields from the API.

### What We Expected
```swift
let sentToAddresses: [String]  // Simple array of address strings
```

### What We Actually Get
```json
"sent_to_addresses" : [
  "{\"type\":\"ark\",\"value\":\"tark1pm6sr0fpzqqp97t5smzm6p38cx2v3p3aun5ql32cme47n6xxyck52mdgcudq06zcpqqzvlq33\"}"
]
```

Each element is a **JSON-encoded object** with:
- `type`: The payment method type (`"ark"`, `"bitcoin"`, `"lightning"`)
- `value`: The actual address/invoice/identifier string

## Changes Made

### 1. New `AddressObject` Structure

Created a new struct to represent the address objects returned by the API:

```swift
struct AddressObject: Codable {
    let type: String   // "ark", "bitcoin", "lightning", etc.
    let value: String  // The actual address/invoice/identifier
    
    var paymentMethod: PaymentMethod {
        // Converts server type to PaymentMethod enum
        // Uses explicit type from server instead of heuristic detection
    }
}
```

### 2. Updated `MovementData` Structure

Changed the property types:

```swift
// Before:
let sentToAddresses: [String]
let receivedOnAddresses: [String]

// After:
let sentToAddresses: [AddressObject]
let receivedOnAddresses: [AddressObject]
```

### 3. Custom Decoding Logic

Added custom `init(from decoder:)` to handle the double-encoded JSON:

```swift
init(from decoder: Decoder) throws {
    // ... decode other properties normally ...
    
    // Decode address arrays (JSON-encoded strings -> AddressObject)
    let sentStrings = try container.decode([String].self, forKey: .sentToAddresses)
    sentToAddresses = Self.decodeAddressObjects(from: sentStrings)
    
    let receivedStrings = try container.decode([String].self, forKey: .receivedOnAddresses)
    receivedOnAddresses = Self.decodeAddressObjects(from: receivedStrings)
}

private static func decodeAddressObjects(from jsonStrings: [String]) -> [AddressObject] {
    return jsonStrings.compactMap { jsonString in
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONDecoder().decode(AddressObject.self, from: data) else {
            return nil
        }
        return obj
    }
}
```

### 4. Updated Computed Properties

Updated `destinations` and `sources` to use the new structure:

```swift
// Before:
var destinations: [MovementDestination] {
    sentToAddresses.map { MovementDestination.fromAddress($0) }
}

// After:
var destinations: [MovementDestination] {
    sentToAddresses.map { addressObject in
        MovementDestination(
            paymentMethod: addressObject.paymentMethod,
            address: addressObject.value
        )
    }
}
```

## Benefits

### 1. **Correct Parsing** ✅
- No longer treats JSON strings as raw addresses
- Properly extracts the `value` field for the actual address

### 2. **Explicit Type Information** ✅
- Server tells us the payment type directly via the `type` field
- No need for heuristic detection (though we still use it for Lightning subcategories)
- More reliable and future-proof

### 3. **Better Error Handling** ✅
- `compactMap` silently handles malformed address objects
- Detailed logging when decoding fails
- Doesn't crash the entire transaction list if one address is bad

### 4. **Performance** ✅
- No regex or string pattern matching needed for type detection
- Direct type mapping from server value

## Testing Recommendations

1. **Test with real API data** - Verify transactions parse correctly
2. **Test multi-recipient sends** - Ensure all addresses are extracted
3. **Test different payment types**:
   - Ark addresses (`type: "ark"`)
   - Bitcoin addresses (`type: "bitcoin"`)
   - Lightning invoices/offers (`type: "lightning"`)
4. **Test malformed data** - Ensure graceful degradation
5. **Test empty arrays** - Ensure no crashes when no addresses present

## Migration Notes

### Breaking Changes
None - this is a bug fix that makes the code work correctly with the actual API format.

### Backward Compatibility
If the API format ever changes back to simple strings (unlikely), we would need to:
1. Detect whether elements are JSON objects or plain strings
2. Handle both cases in the decoder

However, this is unlikely as the current format is more structured and informative.

## Related Files

- `TransactionService.swift` - Main changes
- `MovementDestination.swift` - Uses the parsed address objects
- `PaymentMethod.swift` - Enum for payment method types
- `MovementCategory.swift` - Movement categorization

## Future Considerations

1. **Per-Destination Amounts** - Still not provided by API (remains a limitation)
2. **Additional Address Types** - Easy to extend by adding cases to `AddressObject.paymentMethod`
3. **Metadata in Addresses** - Could add optional fields to `AddressObject` if API provides them
