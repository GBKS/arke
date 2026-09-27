# SendView Banner Comparison

## Three Banner Types in SendView

### 1. ContactInfoBanner
**Purpose:** Shows when sending to a saved contact

**Visual:**
```
┌────────────────────────────────────────────────────────┐
│  [Avatar]  Sending to                             [×]   │
│            Alice Johnson                                │
└────────────────────────────────────────────────────────┘
```

**Triggers:**
- User selected contact from contacts list
- `prefilledContact != nil`

**Priority:** Highest (overrides PaymentRequestInfoBanner)

---

### 2. PaymentRequestInfoBanner
**Purpose:** Shows metadata from BIP-21 payment requests

**Visual (with label):**
```
┌────────────────────────────────────────────────────────┐
│  ₿         Payment to                             [×]   │
│  (icon)    Coffee Shop                                  │
│            Order #42                                    │
└────────────────────────────────────────────────────────┘
```

**Visual (without label):**
```
┌────────────────────────────────────────────────────────┐
│  🟣        Payment via                            [×]   │
│  (icon)    Ark Address                                  │
└────────────────────────────────────────────────────────┘
```

**Triggers:**
- Payment request has `label` OR
- Payment request has `message` OR
- Payment request has multiple destinations

**Priority:** Medium (below contact, above clipboard)

---

### 3. ClipboardAddressBanner
**Purpose:** Prompts user to use address from clipboard

**Visual:**
```
┌────────────────────────────────────────────────────────┐
│  Payment request found in clipboard                [×] │
│  ⭐ Will pay via Ark                                   │
│  tark1pm6sr0fpz...                                     │
│  Amount: 100000 sats                                    │
│  Alternative payment methods: Bitcoin, Lightning        │
│                                                         │
│  [Use Payment Request]                                  │
└────────────────────────────────────────────────────────┘
```

**Triggers:**
- Valid payment request detected in clipboard
- User hasn't accepted or dismissed it yet

**Priority:** Lowest (shows before acceptance, different purpose)

---

## Banner Display Matrix

| Scenario | Contact Banner | Payment Request Banner | Clipboard Banner | Destination Card |
|----------|----------------|------------------------|------------------|------------------|
| **Manual entry** | No | No | Yes (if found) | No |
| **Contact selected** | Yes | No | No | Yes |
| **BIP-21 with label** | No | Yes | No | Yes |
| **BIP-21 no label** | No | No | No | Yes |
| **Plain address paste** | No | No | No | Yes |
| **Clipboard prompt** | No | No | Yes | No |

---

## User Flow Examples

### Flow 1: Contact Payment
```
1. User clicks "Send to Alice" in contacts
   → ContactInfoBanner: "Sending to Alice Johnson"
   → ConfirmedDestinationCard: "Ark Address: ark1abc..."
   
2. User clears banner
   → Returns to manual entry
```

---

### Flow 2: Merchant BIP-21 (External Link)
```
1. User clicks bitcoin: link from website
   → App opens SendView with BIP-21 URI
   
2. PaymentRequest parsed: label = "Coffee Shop"
   → PaymentRequestInfoBanner: "Payment to Coffee Shop"
   → ConfirmedDestinationCard: "Bitcoin Address: bc1q..."
   
3. User clears banner
   → Returns to manual entry
```

---

### Flow 3: Clipboard BIP-21
```
1. User copies: bitcoin:bc1q...?label=Donation
   → Opens SendView
   → ClipboardAddressBanner: "Payment request found..."
   
2. User clicks "Use Payment Request"
   → ClipboardAddressBanner disappears
   → PaymentRequestInfoBanner appears: "Payment to Donation"
   → ConfirmedDestinationCard: "Bitcoin Address: bc1q..."
   
3. User clears banner
   → Returns to manual entry
```

---

### Flow 4: Plain Address Paste
```
1. User copies: bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh
   → Opens SendView
   → ClipboardAddressBanner: "Payment request found..."
   
2. User clicks "Use Payment Request"
   → ClipboardAddressBanner disappears
   → NO PaymentRequestInfoBanner (no label/message)
   → ConfirmedDestinationCard: "Bitcoin Address: bc1q..."
```

---

## Banner Selection Logic

```swift
// In SendView.body
var body: some View {
    VStack {
        // 1. Contact banner (highest priority)
        if let contact = prefilledContact, showContactBanner {
            ContactInfoBanner(contact: contact, onClear: clearAll)
        }
        
        // 2. Payment request banner (medium priority)
        else if shouldShowPaymentRequestBanner, let request = currentPaymentRequest {
            PaymentRequestInfoBanner(paymentRequest: request, onClear: clearAll)
        }
        
        // 3. Clipboard banner (different purpose, shown in manual entry)
        if let clipboardRequest = clipboardPaymentRequest {
            ClipboardAddressBanner(
                paymentRequest: clipboardRequest,
                onUseAddress: { /* lock in */ },
                onDismiss: { /* dismiss */ }
            )
        }
    }
}
```

---

## Design Consistency

All three banners share:
- ✅ Similar height (~60-80pt)
- ✅ Icon on left (48x48pt circle)
- ✅ Title + subtitle text layout
- ✅ Clear/dismiss button on right
- ✅ Consistent spacing and padding

Differences:
- **ContactInfoBanner**: Avatar photo, "Sending to"
- **PaymentRequestInfoBanner**: Format icon, "Payment to/via"
- **ClipboardAddressBanner**: Detailed info, action button

---

## When User Clears Banner

All banners call `clearAll()` which:
1. Returns to `.manualEntry` mode
2. Clears destination selection
3. Clears amount
4. Hides all banners
5. Allows fresh start

---

## Visual Comparison Table

| Banner | Icon | Header | Title | Subtitle | Action |
|--------|------|--------|-------|----------|--------|
| **Contact** | Avatar | "Sending to" | Name | None | Clear |
| **Payment Request** | Format | "Payment to/via" | Label/Format | Message | Clear |
| **Clipboard** | Format | "Found in clipboard" | Details | Options | Use/Dismiss |

---

## Summary

The three banner types serve different purposes:

1. **ContactInfoBanner** → "Who am I sending to?" (personal context)
2. **PaymentRequestInfoBanner** → "What am I paying for?" (transaction context)
3. **ClipboardAddressBanner** → "Want to use this?" (input prompt)

Together, they provide comprehensive context throughout the payment flow while maintaining clear visual hierarchy and user control.
