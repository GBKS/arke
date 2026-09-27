# PaymentRequestInfoBanner Implementation Summary

## Date: November 18, 2025

## What Was Implemented

Created a new `PaymentRequestInfoBanner` component that displays contextual information about payment requests with metadata (labels, messages, multiple destinations).

## Files Created

1. **`PaymentRequestInfoBanner.swift`** - New banner component
2. **`PAYMENT_REQUEST_INFO_BANNER_GUIDE.md`** - Comprehensive usage guide
3. **`SENDVIEW_BANNER_COMPARISON.md`** - Comparison of all three banner types

## Files Modified

**`SendView.swift`** - Integrated the new banner:
- Added `@State private var showPaymentRequestBanner = true`
- Added computed property `shouldShowPaymentRequestBanner`
- Updated `body` to show PaymentRequestInfoBanner when appropriate
- Updated `clearAll()` to reset banner state

## Key Features

### Display Logic

Shows "Payment to [Label]" when:
- ✅ BIP-21 URI includes `label` parameter (merchant name, recipient)
- ✅ Payment request includes `message` (order details, memo)
- ✅ Payment has multiple destinations (unified payment options)

Shows "Payment via [Format]" when:
- ✅ No label provided (generic address)
- ✅ Displays the format type (Bitcoin, Ark, Lightning, etc.)

### Visual Design

- **Icon**: Format-specific icon with color (Bitcoin=orange, Ark=purple, Lightning=yellow, etc.)
- **Header**: "Payment to" (with label) or "Payment via" (without label)
- **Title**: Label name or format display name
- **Subtitle**: Message text (if provided)
- **Action**: Clear button to return to manual entry

### Banner Priority

1. **ContactInfoBanner** (highest) - Saved contacts
2. **PaymentRequestInfoBanner** (medium) - BIP-21 with metadata
3. **ClipboardAddressBanner** (different purpose) - Clipboard prompt

## Example Scenarios

### Scenario 1: Merchant Payment
```
Input: bitcoin:bc1q...?label=Coffee%20Shop&message=Order%20%2342

Display:
┌────────────────────────────────────────┐
│  ₿   Payment to                   [×]  │
│      Coffee Shop                       │
│      Order #42                         │
└────────────────────────────────────────┘
```

### Scenario 2: Generic Ark Address
```
Input: tark1pm6sr0fpzqqpu4k5llkn6wdswx48...

Display:
┌────────────────────────────────────────┐
│  🟣  Payment via                  [×]  │
│      Ark Address                       │
└────────────────────────────────────────┘
```

### Scenario 3: Contact (Different Banner)
```
Input: User selected "Alice" from contacts

Display:
┌────────────────────────────────────────┐
│  [👤] Sending to                  [×]  │
│       Alice Johnson                    │
└────────────────────────────────────────┘
```

## Integration Points

### When Banner Shows
```swift
private var shouldShowPaymentRequestBanner: Bool {
    guard mode == .confirmedDestination else { return false }
    guard prefilledContact == nil || !showContactBanner else { return false }
    
    if let request = currentPaymentRequest {
        return (request.label != nil || 
                request.message != nil || 
                request.hasAlternatives) && 
               showPaymentRequestBanner
    }
    return false
}
```

### In Body
```swift
// Contact banner (highest priority)
if let contact = prefilledContact, showContactBanner {
    ContactInfoBanner(contact: contact, onClear: clearAll)
}

// Payment request banner (medium priority)
if shouldShowPaymentRequestBanner, let request = currentPaymentRequest {
    PaymentRequestInfoBanner(paymentRequest: request, onClear: clearAll)
}

// Clipboard banner (different purpose)
if let clipboardRequest = clipboardPaymentRequest {
    ClipboardAddressBanner(...)
}
```

## User Benefits

1. **Context Clarity** - User knows who/what they're paying
2. **Merchant Identification** - Shows merchant name from BIP-21 label
3. **Transaction Details** - Displays order numbers, memos, etc.
4. **Visual Consistency** - Matches ContactInfoBanner design pattern
5. **Easy Cancellation** - Clear button returns to manual entry

## Technical Details

### Component Architecture
- **Pure view component** - No side effects
- **Stateless** - All data passed via parameters
- **Callback-based** - Uses closure for clear action
- **Reusable** - Can be used anywhere PaymentRequest is available

### Format Icons
| Format | Icon | Color |
|--------|------|-------|
| Bitcoin | `bitcoinsign.circle.fill` | Orange |
| Ark | `cube.fill` | Purple |
| Lightning | `bolt.fill` | Yellow |
| Silent Payments | `eye.slash.fill` | Blue |
| BIP-353 | `at.circle.fill` | Green |

### Text Priority
1. **Label** (if present) - "Coffee Shop", "Alice", etc.
2. **Format** (fallback) - "Ark Address", "Lightning Invoice"
3. **Message** (optional subtitle) - "Order #42", "Thanks!"

## Testing Checklist

- [ ] BIP-21 with label and message
- [ ] BIP-21 with label only
- [ ] BIP-21 without label (shows format)
- [ ] Contact payment (ContactInfoBanner shown instead)
- [ ] Plain address paste (no banner shown)
- [ ] Multiple destinations (banner shown)
- [ ] Clear button returns to manual entry
- [ ] Long merchant names (truncation)
- [ ] Long messages (1-line truncation)
- [ ] All format icons display correctly

## Future Enhancements

Potential additions (not implemented):

1. **Domain Verification** - Show verified domain badge
2. **Amount Preview** - Display requested amount in banner
3. **Expiration Timer** - Countdown for Lightning invoices
4. **Alternative Count** - "3 payment options available"
5. **Trust Indicators** - Show if merchant is recognized/verified

## Migration Notes

### No Breaking Changes
- Existing functionality preserved
- New banner is additive
- Contact banner still works as before
- Clipboard banner unchanged

### Backward Compatible
- If no label/message/alternatives, no banner shows (same as before)
- Plain address pastes work as before
- Contact flow unchanged

## Documentation

All documentation created:
1. **PAYMENT_REQUEST_INFO_BANNER_GUIDE.md** - Complete usage guide with examples
2. **SENDVIEW_BANNER_COMPARISON.md** - Comparison of all three banner types
3. Component includes comprehensive #Preview examples

## Code Quality

- ✅ Follows existing design patterns (ContactInfoBanner)
- ✅ Consistent naming conventions
- ✅ Proper code organization (MARK sections)
- ✅ Comprehensive previews for different scenarios
- ✅ Clear comments and documentation
- ✅ SwiftUI best practices

## Summary

The `PaymentRequestInfoBanner` successfully provides contextual payment information that was previously missing from the SendView flow. It answers the user's question "What am I paying for?" or "Who am I paying?" when using BIP-21 URIs with metadata, while maintaining a consistent design language with the existing `ContactInfoBanner`.

The implementation is clean, reusable, and well-documented, with clear examples showing when and how the banner should appear in different scenarios.
