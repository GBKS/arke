# LNURL-pay Support Implementation Plan

## Overview
Add LNURL-pay support to the send view, enabling users to scan/paste LNURL strings (bech32-encoded `lnurl1...` format) and pay them. Since Bark only supports Lightning Addresses (not raw LNURL strings), we need to handle the full LNURL-pay protocol flow: decode → fetch parameters → request invoice → pay invoice.

## Architecture Context

The codebase already has similar patterns:
- **Lightning Address resolution**: `LightningAddressResolver` converts `user@domain.com` → LNURL endpoint → payment parameters
- **BIP-353 resolution**: `BIP353Resolver` does DNS lookup → BIP-21 URI
- **Bech32 decoding**: `LightningInvoiceParser` has bech32 utilities we can reuse
- **LNURL invoice fetching**: `SendViewModel+PaymentExecution.requestLightningInvoice()` already exists (currently unused)

The pattern: **Detect → Resolve → Execute**

## Implementation Steps

### 1. Create LNURLResolver Service
**New file:** `Arke/Shared/Helpers/LNURLResolver.swift`

Similar to `LightningAddressResolver.swift`, create a service that:

```swift
class LNURLResolver {
    struct ResolvedLNURL {
        let originalLNURL: String
        let callback: String              // Invoice request URL
        let minSendable: Int              // Millisatoshis
        let maxSendable: Int              // Millisatoshis
        let metadata: String?             // LNURL metadata JSON
        let commentAllowed: Int?          // Max comment length
        let tag: String                   // "payRequest"
        let resolvedAt: Date

        var minSendableSats: Int { minSendable / 1000 }
        var maxSendableSats: Int { maxSendable / 1000 }
    }

    enum LNURLError: LocalizedError {
        case invalidFormat
        case decodingFailed
        case networkError(Error)
        case invalidResponse
        case notLNURLPay
        case serverError(String)
    }

    // Public API
    static func isLNURL(_ string: String) -> Bool
    static func decode(_ lnurl: String) throws -> URL
    static func resolve(_ lnurl: String) async throws -> ResolvedLNURL

    // Cache (10 min TTL, same as LightningAddressResolver)
    private static var cache: [String: ResolvedLNURL] = [:]
    private static let cacheDuration: TimeInterval = 600
    private static let cacheQueue = DispatchQueue(label: "com.ark.lnurlcache")
}
```

**Implementation details:**

1. **Bech32 decoding** (reuse from `LightningInvoiceParser.swift:112-153`):
   - Check prefix is "lnurl1" (case insensitive)
   - Use existing `bech32Decode()` and `convertBits()` helpers
   - Decode to UTF-8 string (should be HTTPS URL)
   - Validate URL scheme is HTTPS only

2. **LNURL-pay endpoint fetch**:
   - HTTP GET with 10-second timeout
   - Parse JSON response
   - Validate `tag == "payRequest"`
   - Extract: callback, minSendable, maxSendable, metadata, commentAllowed
   - Cache result with 10-minute TTL

3. **Caching strategy**: Same pattern as `LightningAddressResolver`

### 2. Add LNURL Address Format
**File:** `Arke/Shared/Helpers/AddressFormat.swift`

Add new case to enum:

```swift
enum AddressFormat: String, CaseIterable, Codable {
    // ... existing cases ...
    case lnurl = "LNURL"
}
```

Update computed properties:

```swift
var displayName: String {
    // ... existing cases ...
    case .lnurl:
        return "LNURL-pay"
}

var simplifiedDisplayName: String {
    // ... existing cases ...
    case .lnurl:
        return "Payments (LNURL)"
}

var supportsBitcoinNetworks: Bool {
    // ... existing cases ...
    case .lnurl:
        return false  // Network-agnostic like Lightning
}
```

### 3. Add LNURL Detection in AddressValidator
**File:** `Arke/Shared/Helpers/AddressValidator.swift`

Add detection in `parseSingleFormatRequest()` method (after line 32):

```swift
// Check LNURL format
if LNURLResolver.isLNURL(input) {
    let destination = PaymentDestination(
        format: .lnurl,
        network: nil,  // Network-agnostic
        address: input
    )
    return PaymentRequest(destination: destination)
}
```

Place this **before** Lightning Address check to avoid ambiguity (LNURL is more specific).

### 4. Update PaymentDestinationSelector
**File:** `Arke/Shared/Helpers/PaymentDestinationSelector.swift`

Add LNURL handling:

```swift
static func balanceSource(for destination: PaymentDestination) -> BalanceSource {
    switch destination.format {
    // ... existing cases ...
    case .lnurl:
        return .arkViaServer  // Resolves to Lightning invoice
    }
}

static func estimateFee(for destination: PaymentDestination) -> Int {
    switch destination.format {
    // ... existing cases ...
    case .lnurl:
        return 100  // Same as Lightning
    }
}

// Add to defaultPriority array (around line 50-60)
static let defaultPriority: [AddressFormat] = [
    .ark,
    .lightning,
    .lightningInvoice,
    .lnurl,  // Add after Lightning invoice
    .bolt12,
    // ... rest ...
]
```

### 5. Add LNURL Resolution to Clipboard Flow
**File:** `Arke/Shared/Views/Send/SendViewModel/SendViewModel+Clipboard.swift`

Add LNURL detection in `checkClipboardForAddress()` (after line 85, before line 87):

```swift
// Check for LNURL format
if LNURLResolver.isLNURL(trimmedString) {
    print("🔍 [SendViewModel] Detected LNURL: \(trimmedString)")

    do {
        let resolved = try await LNURLResolver.resolve(trimmedString)
        print("✅ [SendViewModel] LNURL resolved successfully!")
        print("   → Min: \(resolved.minSendableSats) sats, Max: \(resolved.maxSendableSats) sats")
        print("   → Callback: \(resolved.callback)")

        // Store resolved LNURL for later use during payment
        await MainActor.run {
            self.resolvedLNURL = resolved
        }

        return await processClipboardPaymentRequest(trimmedString)
    } catch {
        print("❌ [SendViewModel] LNURL resolution failed: \(error.localizedDescription)")
        self.error = "Failed to resolve LNURL: \(error.localizedDescription)"
        return false
    }
}
```

### 6. Add LNURL State to SendViewModel
**File:** `Arke/Shared/Views/Send/SendViewModel/SendViewModel.swift`

Add property to store resolved LNURL data:

```swift
@Observable
class SendViewModel {
    // ... existing properties ...

    // LNURL-pay state
    var resolvedLNURL: LNURLResolver.ResolvedLNURL?
}
```

Also update in `SendViewModel+StateManagement.swift` `clearAll()` method:

```swift
func clearAll() {
    // ... existing clears ...
    resolvedLNURL = nil
}
```

### 7. Integrate LNURL Payment Execution
**File:** `Arke/Shared/Views/Send/SendViewModel/SendViewModel+PaymentExecution.swift`

Add LNURL case to `executeSend()` switch statement (around line 198):

```swift
case .lnurl:
    print("   → Paying LNURL: \(destination.address)")

    // Get resolved LNURL data (should be cached from clipboard/QR resolution)
    guard let resolved = resolvedLNURL else {
        // Fallback: resolve now if not cached
        print("   → LNURL not cached, resolving now...")
        let freshResolved = try await LNURLResolver.resolve(destination.address)
        resolvedLNURL = freshResolved
    }

    guard let lnurlData = resolvedLNURL else {
        throw SendError.invalidFormat("LNURL resolution failed")
    }

    // Validate amount is within LNURL limits
    if amountInt < lnurlData.minSendableSats || amountInt > lnurlData.maxSendableSats {
        throw SendError.invalidAmount("Amount must be between \(lnurlData.minSendableSats) and \(lnurlData.maxSendableSats) sats")
    }

    // Request invoice from LNURL callback
    print("   → Requesting invoice from LNURL callback...")
    let amountMillisats = amountInt * 1000
    let invoice = try await requestLightningInvoice(
        callback: lnurlData.callback,
        amountMillisats: amountMillisats,
        comment: nil  // No comment support in v1
    )

    print("   → Got invoice: \(invoice)")

    // Verify invoice amount matches requested amount
    if let parsedInvoice = try? LightningInvoiceParser.parse(invoice),
       let invoiceAmount = parsedInvoice.amountSatoshis,
       invoiceAmount != UInt64(amountInt) {
        throw SendError.invalidAmount("Invoice amount (\(invoiceAmount) sats) doesn't match requested amount (\(amountInt) sats)")
    }

    // Pay the invoice via Bark (existing flow)
    print("   → Paying invoice via Bark...")
    _ = try await walletManager.payLightningInvoice(
        invoice: invoice,
        amountSats: nil  // Amount is embedded in invoice
    )
```

### 8. Update UI Components
**Files to update:**

1. **PaymentDestinationRow.swift** - Add LNURL icon and color:
   ```swift
   private var iconName: String {
       switch ranked.destination.format {
       // ... existing cases ...
       case .lnurl:
           return "link.circle"  // Or "qrcode" for QR-style icon
       }
   }

   private var iconColor: Color {
       // ... existing cases ...
       case .lnurl:
           return .Arke.orange  // Same as Lightning
       }
   }
   ```

2. **RecipientInputSection.swift** - LNURL validates as a Lightning payment:
   - No changes needed, handled by AddressValidator

**Note:** Min/max amounts and comments are validated during payment execution, not shown in UI for v1. This keeps the initial implementation simple.

### 9. Add Tests
**New file:** `Arke/Tests/Shared/LNURLResolverTests.swift`

Test cases:
1. `testLNURLDetection()` - Valid lnurl1... strings
2. `testLNURLDecoding()` - Bech32 decode to HTTPS URL
3. `testInvalidLNURLFormats()` - Invalid prefixes, non-HTTPS, etc.
4. `testLNURLResolution()` - Mock HTTP response parsing
5. `testCacheExpiration()` - 10-minute TTL validation

Example test:
```swift
func testLNURLDecoding() throws {
    let lnurl = "lnurl1dp68gurn8ghj7um9wfmxjcm99e3k7mf0v9cxj0m385ekvcenxc6r2c35xvukxefcv5mkvv34x5ekzd3ev56nyd3hxqurzepexejxxepnxscrvwfnv9nxzcn9xq6xyefhvgcxxcmyxymnserxfq5fns"

    let decoded = try LNURLResolver.decode(lnurl)
    XCTAssertEqual(decoded.scheme, "https")
    XCTAssertTrue(decoded.absoluteString.hasPrefix("https://"))
}
```

### 10. Handle Edge Cases

**Amount validation:**
- Before showing amount input, check if LNURL has been resolved
- Display min/max sendable amounts to user
- Validate amount before requesting invoice

**Error handling:**
- LNURL endpoint timeout (10s)
- Invalid LNURL response (not payRequest tag)
- Server error responses
- Invoice amount mismatch
- Network errors

**QR Code & NFC:**
- `SendView_iOS.swift` QR scanner already calls `AddressValidator.parsePaymentRequest()`
- NFC handler (`handleNFCResult()`) also uses `AddressValidator.parsePaymentRequest()`
- No changes needed - LNURL will be detected automatically

## Critical Files

| File | Purpose | Lines to Modify |
|------|---------|----------------|
| **NEW:** `Arke/Shared/Helpers/LNURLResolver.swift` | LNURL decode & resolve | ~220 lines (new) |
| `Arke/Shared/Helpers/AddressFormat.swift` | Add .lnurl case | Lines 11, 20-38, 41-59, 62-68 |
| `Arke/Shared/Helpers/AddressValidator.swift` | Add LNURL detection | After line 32 (~8 lines) |
| `Arke/Shared/Helpers/PaymentDestinationSelector.swift` | LNURL routing logic | Lines ~40, ~80, ~105 |
| `Arke/Shared/Views/Send/SendViewModel/SendViewModel.swift` | Add resolvedLNURL state | Add 1 property |
| `Arke/Shared/Views/Send/SendViewModel/SendViewModel+Clipboard.swift` | LNURL clipboard detection | After line 85 (~20 lines) |
| `Arke/Shared/Views/Send/SendViewModel/SendViewModel+PaymentExecution.swift` | LNURL payment execution | After line 205 (~40 lines) |
| `Arke/Shared/Views/Send/SendViewModel/SendViewModel+StateManagement.swift` | Clear LNURL state | Add to clearAll() |
| `Arke/Shared/Views/Send/Payment destination/PaymentDestinationRow.swift` | LNURL icon/color | Lines ~200, ~220 |
| **NEW:** `Arke/Tests/Shared/LNURLResolverTests.swift` | Unit tests | ~150 lines (new) |

## Verification Steps

### 1. Unit Tests
```bash
# Run LNURL resolver tests
xcodebuild test -scheme Arke -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:ArkeTests/LNURLResolverTests
```

### 2. Manual Testing

**Test LNURL detection:**
1. Copy a valid LNURL-pay string: `lnurl1dp68gurn8ghj7...`
2. Open Send view
3. Verify paste button appears
4. Tap paste
5. Verify LNURL is detected and resolved
6. Verify min/max amounts are shown (future enhancement)

**Test LNURL payment:**
1. Paste LNURL string
2. Enter amount within min/max range
3. Tap Send
4. Verify invoice is requested from callback
5. Verify invoice amount matches
6. Verify payment completes via Bark

**Test QR code:**
1. Generate QR code with LNURL-pay string
2. Scan with camera in Send view
3. Verify automatic detection and resolution

**Test error cases:**
1. Invalid LNURL string → Show error
2. Amount below minimum → Show validation error
3. Amount above maximum → Show validation error
4. Offline/timeout → Show network error
5. Server returns error → Show server error message

### 3. Integration Testing

**With existing flows:**
- Verify other payment formats still work (Bitcoin, Ark, Lightning Address)
- Verify clipboard detection doesn't break
- Verify QR scanning still works for all formats
- Verify contact payments unaffected

## Future Enhancements (Not in Scope)

1. **Comment support** - Add comment field in UI when `commentAllowed > 0`
2. **Min/max amount UI hints** - Show "Amount must be between X and Y sats" in UI (currently only validated on send)
3. **Success actions** - Handle LNURL success action responses (message, URL, AES)
4. **Amount suggestions** - Show recommended amounts from LNURL metadata
5. **LNURL-withdraw** - Separate feature for receiving via LNURL
6. **Metadata parsing** - Display merchant name/description from LNURL metadata JSON
7. **Disposable validation** - Check if LNURL can be reused

## Risk Assessment

**Low Risk:**
- LNURL detection is explicit (lnurl1 prefix)
- Bech32 decoding is well-tested in LightningInvoiceParser
- HTTP request pattern matches LightningAddressResolver
- Invoice request method already exists (requestLightningInvoice)

**Medium Risk:**
- Amount validation needs careful testing (min/max in millisats)
- Invoice amount verification critical for security
- Cache invalidation must match resolution timing

**Mitigation:**
- Comprehensive unit tests for edge cases
- Manual testing with real LNURL-pay services
- Fallback to error display if any step fails
- Clear logging at each step for debugging

## Timeline Estimate

- **LNURLResolver creation**: Core implementation
- **AddressFormat updates**: Straightforward enum additions
- **Integration into flows**: Following existing patterns
- **UI updates**: Minimal changes
- **Testing**: Critical for validation

All changes follow established patterns in the codebase.

## Implementation Status

**✅ COMPLETED** - All implementation steps have been completed successfully:

1. ✅ Created LNURLResolver.swift (283 lines) with bech32 decoding, HTTPS validation, and caching
2. ✅ Added .lnurl case to AddressFormat enum
3. ✅ Added LNURL detection in AddressValidator
4. ✅ Updated PaymentDestinationSelector for LNURL routing
5. ✅ Added LNURL state to SendViewModel
6. ✅ Added LNURL clipboard detection flow
7. ✅ Integrated LNURL payment execution
8. ✅ Updated UI components (PaymentDestinationRow icon/color)
9. ✅ Created LNURLResolverTests.swift (146 lines)
10. ✅ Fixed all exhaustive switch statements across 5 files
11. ✅ Project builds successfully

**⚠️ Manual Step Required:**
- Add `LNURLResolverTests.swift` to the ArkeMobileTests target in Xcode (File Inspector → Target Membership)

**📋 Ready for Testing:**
- Unit tests ready to run once test file is added to target
- Manual testing with QR codes and clipboard paste can begin
