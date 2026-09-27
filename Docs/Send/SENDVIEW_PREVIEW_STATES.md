# SendView Preview States Guide

## Overview

SendView now includes 9 comprehensive preview configurations that demonstrate different entry scenarios and UI states. Each preview shows a specific use case to help with development and testing.

## Preview Catalog

### 1. Empty State - Manual Entry
**File:** `#Preview("Empty State - Manual Entry")`

**Configuration:**
```swift
SendView()
```

**What it shows:**
- Clean slate, no pre-filled data
- Checks clipboard for payment requests
- Shows clipboard banner if valid payment found
- Otherwise shows empty `RecipientInputSection`

**Use case:** Testing the default app entry flow

---

### 2. Pre-filled Bitcoin Address
**File:** `#Preview("Pre-filled Bitcoin Address")`

**Configuration:**
```swift
SendView(
    prefilledRecipient: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
)
```

**What it shows:**
- Mode: `.confirmedDestination`
- `ConfirmedDestinationCard` showing Bitcoin address
- No banner (plain address, no metadata)
- Amount input section
- Send button

**Use case:** Testing simple Bitcoin address payment flow

---

### 3. Pre-filled Contact
**File:** `#Preview("Pre-filled Contact")`

**Configuration:**
```swift
SendView(
    prefilledRecipient: "ark1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
    prefilledContact: ContactModel(
        cachedName: "Alice Johnson",
        notes: "Friend from work"
    )
)
```

**What it shows:**
- Mode: `.confirmedDestination`
- **ContactInfoBanner** at top with name and avatar
- `ConfirmedDestinationCard` showing Ark address
- Amount input section
- Send button

**Use case:** Testing contact payment flow with banner priority

---

### 4. BIP-21 with Label and Message
**File:** `#Preview("BIP-21 with Label and Message")`

**Configuration:**
```swift
SendView(
    prefilledRecipient: "bitcoin:bc1qxy2k...?amount=0.001&label=Coffee%20Shop&message=Order%20%2342"
)
```

**What it shows:**
- Mode: `.confirmedDestination`
- **PaymentRequestInfoBanner** showing:
  - "Payment to"
  - "Coffee Shop"
  - "Order #42"
  - Bitcoin icon (orange)
- `ConfirmedDestinationCard`
- Amount pre-filled to 100,000 sats (0.001 BTC)
- **Amount locked** (from BIP-21)
- Send button enabled

**Use case:** Testing merchant payment with full metadata

**Visual:**
```
┌────────────────────────────────────────┐
│ ₿   Payment to                    [×]  │
│     Coffee Shop                        │
│     Order #42                          │
└────────────────────────────────────────┘
```

---

### 5. BIP-21 with Label Only
**File:** `#Preview("BIP-21 with Label Only")`

**Configuration:**
```swift
SendView(
    prefilledRecipient: "bitcoin:bc1qxy2k...?label=Alice"
)
```

**What it shows:**
- Mode: `.confirmedDestination`
- **PaymentRequestInfoBanner** showing:
  - "Payment to"
  - "Alice"
  - No message
  - Bitcoin icon (orange)
- `ConfirmedDestinationCard`
- Amount input (editable, not pre-filled)
- Send button

**Use case:** Testing labeled payment without amount or message

**Visual:**
```
┌────────────────────────────────────────┐
│ ₿   Payment to                    [×]  │
│     Alice                              │
└────────────────────────────────────────┘
```

---

### 6. BIP-21 Multi-Destination
**File:** `#Preview("BIP-21 Multi-Destination")`

**Configuration:**
```swift
SendView(
    prefilledRecipient: "bitcoin:tb1p...?amount=0.001&label=Multi-Payment&ark=tark1..."
)
```

**What it shows:**
- Mode: `.confirmedDestination`
- **PaymentRequestInfoBanner** showing:
  - "Payment to"
  - "Multi-Payment"
  - Bitcoin icon
- `ConfirmedDestinationCard` with:
  - Selected destination (optimal)
  - **"Change" button** (multiple viable options)
  - Alternative count indicator
- Amount pre-filled
- Send button

**Use case:** Testing unified payment with multiple destinations (Bitcoin + Ark)

**Visual:**
```
┌────────────────────────────────────────┐
│ ₿   Payment to                    [×]  │
│     Multi-Payment                      │
└────────────────────────────────────────┘

┌────────────────────────────────────────┐
│ Payment Destination              [Clear]│
│ 🟣 Ark Address                         │
│ tark1pm6sr0fpz...                      │
│                                        │
│ 2 payment options      [Change] →     │
└────────────────────────────────────────┘
```

---

### 7. Ark Address (No Label)
**File:** `#Preview("Ark Address (No Label)")`

**Configuration:**
```swift
SendView(
    prefilledRecipient: "tark1pm6sr0fpzqqpu4k5llkn6wdswx48fwjjujgu4..."
)
```

**What it shows:**
- Mode: `.confirmedDestination`
- **PaymentRequestInfoBanner** showing:
  - "Payment via" (no label)
  - "Ark Address"
  - Purple icon
- `ConfirmedDestinationCard`
- Amount input (editable)
- Send button

**Use case:** Testing generic Ark payment without metadata

**Visual:**
```
┌────────────────────────────────────────┐
│ 🟣  Payment via                   [×]  │
│     Ark Address                        │
└────────────────────────────────────────┘
```

---

### 8. Lightning Invoice
**File:** `#Preview("Lightning Invoice")`

**Configuration:**
```swift
SendView(
    prefilledRecipient: "lnbc1000n1pj9x7zmpp5qqqsyqcyq5rqwz..."
)
```

**What it shows:**
- Mode: `.confirmedDestination`
- **PaymentRequestInfoBanner** showing:
  - "Payment via"
  - "Lightning Invoice"
  - Lightning icon (yellow)
- `ConfirmedDestinationCard`
- Amount may be locked (if invoice has embedded amount)
- Send button

**Use case:** Testing Lightning payment flow

**Visual:**
```
┌────────────────────────────────────────┐
│ ⚡  Payment via                   [×]  │
│     Lightning Invoice                  │
└────────────────────────────────────────┘
```

---

### 9. Silent Payment Address
**File:** `#Preview("Silent Payment Address")`

**Configuration:**
```swift
SendView(
    prefilledRecipient: "sp1qqgste7k9hx0qftg6qmwlkqtwuy6cycya..."
)
```

**What it shows:**
- Mode: `.confirmedDestination`
- **PaymentRequestInfoBanner** showing:
  - "Payment via"
  - "Silent Payment"
  - Eye-slash icon (blue)
- `ConfirmedDestinationCard`
- Amount input (editable)
- Send button

**Use case:** Testing Silent Payments (BIP-352) support

**Visual:**
```
┌────────────────────────────────────────┐
│ 👁️‍🗨️ Payment via                   [×]  │
│     Silent Payment                     │
└────────────────────────────────────────┘
```

---

## Preview Testing Matrix

| Preview | Mode | Banner Type | Destination Card | Amount | Multiple Options |
|---------|------|-------------|------------------|--------|------------------|
| Empty State | `.manualEntry` | None (or Clipboard) | No | No | - |
| Bitcoin Address | `.confirmedDestination` | None | Yes | Editable | No |
| Contact | `.confirmedDestination` | Contact | Yes | Editable | No |
| BIP-21 Label+Message | `.confirmedDestination` | Payment Request | Yes | Pre-filled | No |
| BIP-21 Label Only | `.confirmedDestination` | Payment Request | Yes | Editable | No |
| Multi-Destination | `.confirmedDestination` | Payment Request | Yes | Pre-filled | Yes |
| Ark Address | `.confirmedDestination` | Payment Request | Yes | Editable | No |
| Lightning | `.confirmedDestination` | Payment Request | Yes | May be locked | No |
| Silent Payments | `.confirmedDestination` | Payment Request | Yes | Editable | No |

---

## Using Previews in Xcode

### Viewing All Previews
1. Open `SendView.swift` in Xcode
2. Show Canvas (⌥⌘↵ or Editor → Canvas)
3. Click preview selector dropdown
4. Choose any preview to see that state

### Live Preview
Each preview is interactive:
- ✅ Type in text fields
- ✅ Click buttons
- ✅ Interact with pickers
- ⚠️ Network calls won't work (needs real environment)

### Comparing States
Use Xcode's "Pin Preview" feature:
1. View first preview
2. Click pin icon
3. Select different preview
4. Both show side-by-side for comparison

---

## Banner Behavior by Preview

### Shows ContactInfoBanner
- ✅ Preview 3: Pre-filled Contact

### Shows PaymentRequestInfoBanner
- ✅ Preview 4: BIP-21 with Label and Message
- ✅ Preview 5: BIP-21 with Label Only
- ✅ Preview 6: Multi-Destination (has label)
- ✅ Preview 7: Ark Address (no label, shows format)
- ✅ Preview 8: Lightning Invoice (no label, shows format)
- ✅ Preview 9: Silent Payments (no label, shows format)

### Shows No Info Banner
- ✅ Preview 1: Empty State (may show clipboard banner)
- ✅ Preview 2: Bitcoin Address (plain address, no metadata)

---

## Testing Scenarios by Preview

### User Flow Testing

**Merchant Payment Flow:**
- Use Preview 4 (BIP-21 with Label and Message)
- Verify banner shows merchant name
- Verify amount is pre-filled
- Verify send button is enabled

**Contact Payment Flow:**
- Use Preview 3 (Pre-filled Contact)
- Verify ContactInfoBanner shows name/avatar
- Verify destination card shows address
- Verify clear button returns to manual entry

**Multi-Payment Flow:**
- Use Preview 6 (Multi-Destination)
- Verify "Change" button appears
- Click "Change" to see alternative options
- Verify switching destinations works

**Generic Payment Flow:**
- Use Preview 2 (Bitcoin Address)
- Verify no banner appears (no metadata)
- Verify destination card shows address
- Verify amount is editable

---

## Adding New Previews

To add a new preview state:

```swift
#Preview("Your Description") {
    NavigationStack {
        SendView(
            prefilledRecipient: "your_address_or_uri",
            prefilledContact: optional_contact
        )
            .environment(WalletManager())
    }
}
```

### Useful Test Cases to Add:

1. **Invalid Address:**
```swift
#Preview("Invalid Address Error") {
    NavigationStack {
        SendView(prefilledRecipient: "invalid_xyz_123")
            .environment(WalletManager())
    }
}
```

2. **Network Mismatch:**
```swift
#Preview("Network Mismatch Warning") {
    NavigationStack {
        SendView(prefilledRecipient: "bc1q...") // mainnet address
            .environment(WalletManager()) // configured for signet
    }
}
```

3. **Insufficient Balance:**
```swift
#Preview("Insufficient Balance") {
    NavigationStack {
        SendView(prefilledRecipient: "bitcoin:bc1q...?amount=10") // 10 BTC
            .environment(WalletManager()) // has 0.001 BTC
    }
}
```

---

## Preview Limitations

### What Works:
- ✅ UI layout and appearance
- ✅ State management (mode switching, etc.)
- ✅ User interactions (typing, clicking)
- ✅ Address parsing and validation
- ✅ Banner display logic

### What Doesn't Work:
- ❌ Actual payments (needs real wallet backend)
- ❌ Balance checking (mock data)
- ❌ Network calls (no Ark server)
- ❌ Clipboard detection (preview environment)

### Workarounds:
For testing features that need real data:
1. Use simulators instead of previews
2. Create mock WalletManager for previews
3. Test integration in full app context

---

## Best Practices

### When Building UI:
1. **Start with previews** - Build UI using live preview
2. **Test all states** - Check each preview for layout issues
3. **Compare side-by-side** - Pin previews to compare states
4. **Use descriptive names** - Make it clear what each preview tests

### When Debugging:
1. **Isolate the state** - Create preview for specific scenario
2. **Add console logs** - Check print statements in preview
3. **Test interactions** - Click buttons to see state changes
4. **Verify logic paths** - Ensure conditions work as expected

### When Reviewing:
1. **Visual inspection** - Check all previews for consistency
2. **Layout verification** - Ensure no overlaps or truncation
3. **Color accuracy** - Verify icon colors match format
4. **Text clarity** - Ensure labels are readable

---

## Summary

The 9 SendView previews cover:

1. ✅ **Empty state** - Clean slate
2. ✅ **Simple payment** - Plain Bitcoin address
3. ✅ **Contact payment** - With ContactInfoBanner
4. ✅ **Merchant payment** - Full metadata (label + message + amount)
5. ✅ **Labeled payment** - Just label
6. ✅ **Unified payment** - Multiple destinations
7. ✅ **Ark payment** - No label
8. ✅ **Lightning payment** - Invoice format
9. ✅ **Silent payment** - Privacy-preserving format

Together, these previews provide comprehensive coverage of SendView's UI states and enable rapid development and testing without running the full app.
