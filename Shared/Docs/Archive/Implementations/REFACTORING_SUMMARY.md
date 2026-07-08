# AddressValidator Refactoring Summary

## Date: November 17, 2025

## Overview
Refactored `AddressValidator` from using a single `ParsedAddress` struct to a more flexible `PaymentRequest` + `PaymentDestination` model that properly handles BIP-21 URIs with multiple payment options.

---

## Changes Made

### New Files Created

1. **PaymentDestination.swift**
   - Represents a single payment destination (address, format, network)
   - Includes format-specific data (e.g., Silent Payments keys)
   - Provides network compatibility checking
   - Computed properties: `displayName`, `isBitcoin`, `shortAddress`

2. **PaymentRequest.swift**
   - Represents a complete payment request with one or more destinations
   - Includes payment metadata: amount, label, message
   - Convenience properties: `primaryDestination`, `alternativeDestinations`, `hasAlternatives`
   - Query methods: `destinations(for:)`, `supports(_:)`, `isCompatible(with:)`
   - Filtering: `filtered(for:)` to filter by network config

---

### Modified Files

#### AddressValidator.swift
- **Removed**: `ParsedAddress` struct
- **Added**: `parsePaymentRequest(_ input: String) -> PaymentRequest?` - main parsing method
- **Added**: `parseSingleDestination(_ input: String) -> PaymentDestination?` - helper for non-URI formats
- **Updated**: `parseBIP21URI(_ uri: String) -> PaymentRequest?` - now parses multiple destinations
  - Supports `ark` query parameter for Ark addresses
  - Supports `lightning` or `ln` query parameter for Lightning invoices
  - Supports `sp` query parameter for Silent Payments addresses
  - Supports `address` query parameter for additional Bitcoin addresses
- **Updated**: `parseLightningDestination(_ input: String) -> PaymentDestination?` - renamed and refactored
- **Updated**: Network filtering methods to work with `PaymentRequest`

#### ContactAddressModel.swift
- **Updated**: `init(from:contactId:label:isPrimary:)` to accept `PaymentDestination` instead of `ParsedAddress`

#### ContactAddressService.swift
- **Updated**: `validateAndCreateAddress()` to use `parsePaymentRequest()` and extract primary destination
- **Updated**: `parsePaymentRequest()` method (renamed from `parseAddress()`)
- **Updated**: Network validation to use new API

#### SendView.swift
- **Updated**: `clipboardPaymentRequest` state variable (renamed from `clipboardAddress`)
- **Updated**: `handleRecipientChange()` to work with `PaymentRequest`
- **Updated**: `checkClipboardForAddress()` to use `parsePaymentRequest()`
- **Updated**: Debug logging to show payment request details including alternatives
- **Updated**: Banner integration to use new `ClipboardAddressBanner` API

#### ClipboardAddressBanner.swift
- **Completely refactored** to accept `PaymentRequest` instead of `ParsedAddress`
- **Added**: Display of alternative payment destinations
- **Added**: Icons for different address formats
- **Improved**: Layout to show all payment options when multiple are available

#### BIP21URIHelper.swift
- **Updated**: `createBIP21URI()` to support `lightningInvoice` and `silentPaymentsAddress` parameters
- **Added**: `createBIP21URI(from: PaymentRequest)` - creates URI from payment request object

---

## Key Improvements

### 1. Better BIP-21 Support
- Can now parse and handle BIP-21 URIs with multiple payment destinations
- Supports industry-standard query parameters: `ark`, `lightning`/`ln`, `sp`
- Preserves all payment metadata (amount, label, message)

### 2. Cleaner Architecture
- Separation of concerns: `PaymentDestination` (where) vs `PaymentRequest` (what)
- All destinations are peers, not "primary + alternatives"
- More intuitive API for working with payment options

### 3. Enhanced Filtering
- Built-in network filtering at the `PaymentRequest` level
- Easy to query destinations by format or network
- Simple compatibility checking

### 4. Better UX
- UI can now display all payment options to users
- Shows alternative payment methods from BIP-21 URIs
- Clearer presentation of payment request details

---

## BIP-21 Multi-Destination Example

```swift
// Input URI:
let uri = "bitcoin:bc1qxy...?amount=0.001&ark=ark1abc...&lightning=lnbc1..."

// Parse it:
if let request = AddressValidator.parsePaymentRequest(uri) {
    print("Primary: \(request.primaryDestination!.format)")  // .bitcoin
    print("Amount: \(request.amount!) sats")                 // 100000
    print("Alternatives: \(request.alternativeDestinations.count)")  // 2
    
    // Get specific destination types
    let arkDest = request.firstDestination(for: .ark)
    let lightningDest = request.firstDestination(for: .lightningInvoice)
    
    // Filter by network
    let mainnetDestinations = request.destinations(for: .mainnet)
}
```

---

## Migration Notes

### No Backward Compatibility
- `ParsedAddress` has been completely removed
- All code now uses `PaymentRequest` and `PaymentDestination`
- This is acceptable since this is an alpha app

### Testing Recommendations
1. Test BIP-21 URI parsing with multiple destinations
2. Test clipboard banner with multi-destination URIs
3. Test network filtering across different payment types
4. Test amount pre-filling from Lightning invoices in BIP-21
5. Verify address validation still works for all formats

---

## Future Enhancements

### Potential Additions
1. **Destination Priority**: Allow user to specify preferred payment method order
2. **Automatic Fallback**: Try destinations in order until one succeeds
3. **Fee Comparison**: Show estimated fees for each destination type
4. **Unified QR Codes**: Generate QR codes with all available payment methods
5. **Destination Selection UI**: Let users choose which destination to use when multiple are available

### BIP-21 Extensions
- Support for more query parameters (memo, expiry, etc.)
- Custom app-specific parameters
- Better validation of parameter combinations

---

## Files Summary

### New Files (2)
- PaymentDestination.swift
- PaymentRequest.swift

### Modified Files (6)
- AddressValidator.swift
- ContactAddressModel.swift
- ContactAddressService.swift
- SendView.swift
- ClipboardAddressBanner.swift
- BIP21URIHelper.swift

### Total Lines Changed
- New code: ~450 lines
- Modified code: ~350 lines
- Removed code: ~100 lines
