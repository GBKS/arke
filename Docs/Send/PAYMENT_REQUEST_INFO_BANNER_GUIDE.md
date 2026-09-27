# Payment Request Info Banner - Usage Guide

## Overview

The `PaymentRequestInfoBanner` displays contextual information about the payment destination when sending via BIP-21 URIs or other payment requests that include metadata. It provides a visual summary of who or what the user is paying.

## When to Show the Banner

The banner appears when:
1. ✅ Payment request has a **label** (merchant name, recipient name, etc.)
2. ✅ Payment request has a **message** (order details, memo, etc.)
3. ✅ Payment request has **multiple destinations** (unified payment options)
4. ❌ User has already selected a **contact** (contact banner takes precedence)
5. ❌ In **manual entry mode** (only shows in confirmed destination mode)

## Visual Examples

### 1. Merchant Payment (Label + Message)

**Input:**
```
bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh?
amount=0.001&
label=Coffee%20Shop&
message=Order%20%2342
```

**Display:**
```
┌────────────────────────────────────────────────────────┐
│  ₿         Payment to                             [×]   │
│  (orange)  Coffee Shop                                  │
│            Order #42                                    │
└────────────────────────────────────────────────────────┘
```

---

### 2. Labeled Payment (Label Only)

**Input:**
```
bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh?label=Alice
```

**Display:**
```
┌────────────────────────────────────────────────────────┐
│  ₿         Payment to                             [×]   │
│  (orange)  Alice                                        │
└────────────────────────────────────────────────────────┘
```

---

### 3. Ark Payment (No Label)

**Input:**
```
bitcoin:tb1p...?ark=tark1pm6sr0fpzqqpu4k5llkn6wdswx48fwjj...
```

**Display:**
```
┌────────────────────────────────────────────────────────┐
│  🟣        Payment via                            [×]   │
│  (purple)  Ark Address                                  │
└────────────────────────────────────────────────────────┘
```

**Note:** Shows "Payment via [Format]" instead of "Payment to [Label]"

---

### 4. Lightning Invoice (No Label)

**Input:**
```
lnbc1000n1pj9x7zmpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwz...
```

**Display:**
```
┌────────────────────────────────────────────────────────┐
│  ⚡        Payment via                            [×]   │
│  (yellow)  Lightning Invoice                            │
└────────────────────────────────────────────────────────┘
```

---

### 5. Multi-Destination Payment

**Input:**
```
bitcoin:bc1q...?
amount=0.001&
label=Multi-Payment&
ark=tark1test&
lightning=lnbc1
```

**Display:**
```
┌────────────────────────────────────────────────────────┐
│  ₿         Payment to                             [×]   │
│  (orange)  Multi-Payment                                │
└────────────────────────────────────────────────────────┘
```

**Note:** Shows even without message because it has multiple destinations

---

### 6. Silent Payments (No Label)

**Input:**
```
sp1qqgste7k9hx0qftg6qmwlkqtwuy6cycyavzmzj85c6qdfh...
```

**Display:**
```
┌────────────────────────────────────────────────────────┐
│  👁️‍🗨️       Payment via                            [×]   │
│  (blue)    Silent Payment                               │
└────────────────────────────────────────────────────────┘
```

---

## Banner Priority Logic

When multiple banners could be shown, the following priority applies:

1. **ContactInfoBanner** (highest priority)
   - Shows when: Contact was selected from contacts list
   - Displays: Contact avatar + name
   - Use case: Personal payments to saved contacts

2. **PaymentRequestInfoBanner**
   - Shows when: BIP-21 with metadata OR multiple destinations
   - Displays: Format icon + label/format name + optional message
   - Use case: Merchant payments, labeled requests, unified payments

3. **ClipboardAddressBanner** (lowest priority, different purpose)
   - Shows when: Valid payment request found in clipboard
   - Displays: Payment preview with "Use Payment Request" button
   - Use case: Prompting user to use clipboard content

## Display Rules

### Header Text

| Condition | Header Text |
|-----------|-------------|
| Has label | "Payment to" |
| No label  | "Payment via" |

### Primary Text

| Priority | Source | Example |
|----------|--------|---------|
| 1st | `label` parameter | "Coffee Shop" |
| 2nd | Primary destination format | "Ark Address" |
| 3rd | Fallback | "Payment Request" |

### Secondary Text

| Condition | Shows |
|-----------|-------|
| Has message | Message text (truncated to 1 line) |
| No message  | Nothing |

### Icon and Color

| Format | Icon | Color |
|--------|------|-------|
| Bitcoin | ₿ `bitcoinsign.circle.fill` | Orange |
| Ark | 🟣 `cube.fill` | Purple |
| Lightning | ⚡ `bolt.fill` | Yellow |
| Silent Payments | 👁️‍🗨️ `eye.slash.fill` | Blue |
| BIP-353 | @ `at.circle.fill` | Green |
| BIP-21 | 📱 `qrcode` | Gray |

---

## Integration Flow

### Scenario A: User Clicks BIP-21 Link with Label

```
1. App receives: bitcoin:bc1q...?label=Coffee%20Shop&amount=0.001
2. SendView opens with prefilledRecipient
3. handleInitialSetup() parses → PaymentRequest
4. lockInPaymentRequest() sets mode = .confirmedDestination
5. shouldShowPaymentRequestBanner = true (has label)
6. PaymentRequestInfoBanner displays "Payment to Coffee Shop"
```

---

### Scenario B: User Pastes BIP-21 from Clipboard

```
1. User opens SendView
2. checkClipboardForAddress() finds: bitcoin:bc1q...?label=Alice
3. ClipboardAddressBanner displays
4. User clicks "Use Payment Request"
5. lockInPaymentRequest() sets mode = .confirmedDestination
6. ClipboardAddressBanner dismisses
7. PaymentRequestInfoBanner appears "Payment to Alice"
```

---

### Scenario C: User Pastes Plain Bitcoin Address

```
1. User opens SendView
2. checkClipboardForAddress() finds: bc1q...
3. ClipboardAddressBanner displays (no label)
4. User clicks "Use Payment Request"
5. lockInPaymentRequest() sets mode = .confirmedDestination
6. ClipboardAddressBanner dismisses
7. PaymentRequestInfoBanner DOES NOT appear (no label/message/alternatives)
8. Only ConfirmedDestinationCard shows
```

---

### Scenario D: User Selects Contact

```
1. User selects contact "Bob" from contacts
2. SendView opens with prefilledContact
3. ContactInfoBanner displays "Sending to Bob"
4. shouldShowPaymentRequestBanner = false (contact banner has priority)
5. Only ContactInfoBanner shows, not PaymentRequestInfoBanner
```

---

## Code Examples

### Basic Usage

```swift
if shouldShowPaymentRequestBanner, let paymentRequest = currentPaymentRequest {
    PaymentRequestInfoBanner(
        paymentRequest: paymentRequest,
        onClear: {
            clearAll()
        }
    )
}
```

---

### Custom PaymentRequest Creation

```swift
// Merchant payment with metadata
let merchantRequest = PaymentRequest(
    destinations: [bitcoinDestination],
    amount: 100000,
    label: "Coffee Shop",
    message: "Order #42",
    originalString: bip21Uri
)

PaymentRequestInfoBanner(
    paymentRequest: merchantRequest,
    onClear: { /* handle clear */ }
)
```

---

### Testing Different Scenarios

```swift
// Test 1: Labeled payment
let labeled = PaymentRequest(
    destination: btcDestination,
    label: "Alice",
    message: nil
)
// Shows: "Payment to Alice"

// Test 2: Unlabeled Ark payment
let unlabeled = PaymentRequest(
    destination: arkDestination,
    label: nil,
    message: nil
)
// Shows: "Payment via Ark Address"

// Test 3: With message
let withMessage = PaymentRequest(
    destination: btcDestination,
    label: "Coffee Shop",
    message: "Thanks for your order!"
)
// Shows: "Payment to Coffee Shop" + "Thanks for your order!"
```

---

## Accessibility

The banner includes:
- ✅ Clear visual hierarchy (icon, title, message)
- ✅ Semantic colors (format-specific)
- ✅ Help text on clear button
- ✅ Truncation for long messages (prevents layout issues)
- ✅ Sufficient contrast ratios

---

## Design Guidelines

### When to Use

✅ **DO use** when:
- Payment request includes merchant/recipient name
- Payment request includes order/transaction details
- Payment has multiple destination options
- Context helps user confirm they're paying the right entity

❌ **DON'T use** when:
- Plain address paste (no metadata)
- User selected contact (use ContactInfoBanner instead)
- In manual entry mode (premature context)

### Text Guidelines

- **Labels**: Keep concise, user-recognizable names
- **Messages**: Brief transaction details, order numbers, memos
- **Length**: Message auto-truncates to 1 line to prevent layout issues

---

## Future Enhancements

Potential additions:

1. **Domain verification** - Show verified domain for BIP-353/LNURL
   ```
   Payment to
   Coffee Shop
   ✓ Verified: coffeeshop.com
   ```

2. **Amount preview** - Show requested amount in banner
   ```
   Payment to
   Coffee Shop · 0.001 BTC
   Order #42
   ```

3. **Alternative count** - Show number of payment options
   ```
   Payment to
   Multi-Merchant · 3 options
   ```

4. **Expiration warning** - For time-sensitive invoices
   ```
   Payment via
   Lightning Invoice · Expires in 5m
   ```

---

## Summary

The `PaymentRequestInfoBanner` provides crucial context for BIP-21 payments by:

1. Showing **who** the user is paying (label)
2. Showing **why** they're paying (message)
3. Using **visual cues** (format-specific icons/colors)
4. Enabling **easy cancellation** (clear button)

It complements `ContactInfoBanner` (for personal contacts) and `ClipboardAddressBanner` (for clipboard prompts) to create a cohesive payment flow with clear user feedback.
