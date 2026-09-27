# PaymentRequestInfoBanner - Quick Visual Reference

## Banner Anatomy

```
┌──────────────────────────────────────────────────────────────┐
│  [Icon]     [Header Text]                              [×]   │
│  48x48      Title Text                                        │
│  circle     Subtitle (optional)                               │
└──────────────────────────────────────────────────────────────┘
│   │         │            │                              │
│   │         │            │                              └─ Clear button
│   │         │            └─ Message (if present)
│   │         └─ Label or Format name
│   └─ Format-specific icon with color
```

---

## All Format Icons

### Bitcoin
```
┌──────────────────────────────────────────┐
│  ₿    Payment to                    [×]  │
│  🟠   Alice                               │
└──────────────────────────────────────────┘
Icon: bitcoinsign.circle.fill
Color: Orange (#FF9500)
```

### Ark
```
┌──────────────────────────────────────────┐
│  🟣   Payment via                   [×]  │
│       Ark Address                        │
└──────────────────────────────────────────┘
Icon: cube.fill
Color: Purple (#AF52DE)
```

### Lightning
```
┌──────────────────────────────────────────┐
│  ⚡   Payment via                   [×]  │
│  🟡   Lightning Invoice                  │
└──────────────────────────────────────────┘
Icon: bolt.fill
Color: Yellow (#FFCC00)
```

### Silent Payments
```
┌──────────────────────────────────────────┐
│  👁️‍🗨️  Payment via                   [×]  │
│  🔵   Silent Payment                     │
└──────────────────────────────────────────┘
Icon: eye.slash.fill
Color: Blue (#007AFF)
```

### BIP-353
```
┌──────────────────────────────────────────┐
│  @    Payment to                    [×]  │
│  🟢   alice@example.com                  │
└──────────────────────────────────────────┘
Icon: at.circle.fill
Color: Green (#34C759)
```

---

## Header Text Rules

| Condition | Header | Example |
|-----------|--------|---------|
| Has `label` parameter | "Payment to" | "Payment to Coffee Shop" |
| No `label` parameter | "Payment via" | "Payment via Ark Address" |

---

## Title Text Rules

| Priority | Source | Example |
|----------|--------|---------|
| 1st | `label` | "Coffee Shop" |
| 2nd | Primary format name | "Ark Address" |
| 3rd | Fallback | "Payment Request" |

---

## Complete Examples by Use Case

### 1. Online Merchant
```
Input: bitcoin:bc1q...?label=Amazon&message=Order%20%23123456

┌──────────────────────────────────────────┐
│  ₿    Payment to                    [×]  │
│  🟠   Amazon                              │
│       Order #123456                      │
└──────────────────────────────────────────┘
```

### 2. Coffee Shop
```
Input: bitcoin:bc1q...?label=Coffee%20Shop&message=Latte

┌──────────────────────────────────────────┐
│  ₿    Payment to                    [×]  │
│  🟠   Coffee Shop                         │
│       Latte                              │
└──────────────────────────────────────────┘
```

### 3. Friend (labeled)
```
Input: bitcoin:bc1q...?label=Alice

┌──────────────────────────────────────────┐
│  ₿    Payment to                    [×]  │
│  🟠   Alice                               │
└──────────────────────────────────────────┘
```

### 4. Donation (with message)
```
Input: bitcoin:bc1q...?label=Charity&message=Thank%20you!

┌──────────────────────────────────────────┐
│  ₿    Payment to                    [×]  │
│  🟠   Charity                             │
│       Thank you!                         │
└──────────────────────────────────────────┘
```

### 5. Generic Ark (no label)
```
Input: tark1pm6sr0fpzqqpu4k5llkn6wdswx48fwjjujgu4...

┌──────────────────────────────────────────┐
│  🟣   Payment via                   [×]  │
│       Ark Address                        │
└──────────────────────────────────────────┘
```

### 6. Lightning Invoice (no label)
```
Input: lnbc1000n1pj9x7zmpp5qqqsyqcyq5rqwzqf...

┌──────────────────────────────────────────┐
│  ⚡   Payment via                   [×]  │
│  🟡   Lightning Invoice                  │
└──────────────────────────────────────────┘
```

### 7. Multi-Destination Payment
```
Input: bitcoin:bc1q...?label=Multi&ark=tark1...&lightning=lnbc1...

┌──────────────────────────────────────────┐
│  ₿    Payment to                    [×]  │
│  🟠   Multi                               │
└──────────────────────────────────────────┘
(Shows even without message due to multiple destinations)
```

---

## When Banner Appears

### ✅ Shows When:
- ✓ Has `label` parameter
- ✓ Has `message` parameter  
- ✓ Has multiple destinations
- ✓ In `.confirmedDestination` mode
- ✓ No contact banner showing

### ❌ Doesn't Show When:
- ✗ Plain address (no metadata)
- ✗ In `.manualEntry` mode
- ✗ Contact is selected (ContactInfoBanner takes precedence)
- ✗ User dismissed it (`showPaymentRequestBanner = false`)

---

## State Flow Diagram

```
User Action                Banner State
───────────────────────────────────────────────

Paste BIP-21 (label)   →   ClipboardAddressBanner
                              (shows preview)
         ↓
Click "Use"            →   PaymentRequestInfoBanner
                              (shows label)
         ↓
Click [×]              →   No banner
                              (manual entry mode)
```

---

## Comparison: Contact vs Payment Request Banner

### Contact Banner
```
┌──────────────────────────────────────────┐
│  [Photo]  Sending to                [×]  │
│           Alice Johnson                   │
└──────────────────────────────────────────┘
```
- Avatar photo
- "Sending to"
- Personal name
- Shows for saved contacts

### Payment Request Banner
```
┌──────────────────────────────────────────┐
│  ₿        Payment to                [×]  │
│  🟠       Coffee Shop                     │
│           Order #42                      │
└──────────────────────────────────────────┘
```
- Format icon
- "Payment to/via"
- Label or format name
- Shows for BIP-21 with metadata

---

## CSS-Style Specifications

```css
.payment-request-info-banner {
    layout: HStack;
    spacing: 12px;
    padding: 16px;
    background: default;
}

.banner-icon {
    width: 48px;
    height: 48px;
    shape: circle;
    background-opacity: 0.15;
    border: 0.5px solid rgba(gray, 0.25);
}

.banner-text-stack {
    layout: VStack;
    alignment: leading;
    spacing: 2px;
}

.banner-header {
    font: title3;
    color: secondary;
    text: "Payment to" | "Payment via";
}

.banner-title {
    font: title2;
    font-weight: medium;
    text: label ?? format.displayName;
}

.banner-subtitle {
    font: caption;
    color: secondary;
    line-limit: 1;
    text: message ?? null;
}

.banner-clear-button {
    icon: xmark.circle.fill;
    font: title3;
    color: secondary;
    style: plain;
}
```

---

## Code Snippet

```swift
// Show banner when conditions met
if shouldShowPaymentRequestBanner, 
   let paymentRequest = currentPaymentRequest {
    PaymentRequestInfoBanner(
        paymentRequest: paymentRequest,
        onClear: {
            clearAll()
        }
    )
}
```

---

## Testing Checklist

```
Format Tests:
[ ] Bitcoin address (orange icon)
[ ] Ark address (purple icon)
[ ] Lightning invoice (yellow icon)
[ ] Silent payment (blue icon)
[ ] BIP-353 address (green icon)

Label Tests:
[ ] With label → "Payment to [Label]"
[ ] Without label → "Payment via [Format]"

Message Tests:
[ ] With message → Shows as subtitle
[ ] Without message → No subtitle
[ ] Long message → Truncates to 1 line

Interaction Tests:
[ ] Clear button → Calls onClear
[ ] Clear button → Returns to manual entry
[ ] Banner doesn't show for plain addresses
[ ] Banner doesn't show with contact
```

---

## Quick Decision Tree

```
Is there a PaymentRequest?
│
├─ Yes → Is there a contact?
│        │
│        ├─ Yes → Show ContactInfoBanner
│        │
│        └─ No → Does request have label/message/alternatives?
│                │
│                ├─ Yes → Show PaymentRequestInfoBanner
│                │
│                └─ No → No banner
│
└─ No → No banner
```
