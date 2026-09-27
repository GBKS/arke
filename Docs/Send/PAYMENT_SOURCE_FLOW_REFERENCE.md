# Payment Request Source Flow - Quick Reference

## Overview

The `PaymentRequestSource` now travels through the entire payment flow, from detection to display.

## Current Source Assignments

### 1. QR Code Scans → `.qrCode`
**File:** `SendView_iOS.swift` (line ~221)
```swift
viewModel.sendMode = .quick(paymentRequest, source: .qrCode)
```
**Displays:** "Payment request scanned" with QR code icon

---

### 2. Clipboard Detection → `.clipboard`
**File:** `SendViewModel.swift` (line ~365)
```swift
sendMode = .quick(paymentRequest, source: .clipboard)
```
**Displays:** "Payment request found in clipboard" with clipboard icon

---

### 3. Pre-filled Recipients → `.manual`
**File:** `SendViewModel.swift` (line ~217)
```swift
sendMode = .quick(paymentRequest, source: .manual)
```
**Displays:** "Payment request entered" with text cursor icon

**Note:** Pre-filled recipients are treated as `.manual` because they can come from various sources (deep links, app navigation, etc.) and don't have specific attribution.

---

## Data Flow

```
┌─────────────────┐
│   User Action   │
│  (Scan/Paste)   │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────┐
│     SendViewModel.swift         │
│  sendMode = .quick(request,     │
│    source: .qrCode/.clipboard)  │
└────────┬────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│   SendView / SendView_iOS       │
│  case .quick(let request,       │
│              let source):       │
│    quickModeView(..., source)   │
└────────┬────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│      QuickPaymentView           │
│  Displays title with correct    │
│  icon and text based on source  │
└─────────────────────────────────┘
```

## Adding New Sources

If you want to add deep link support:

### Step 1: Update URL Handler
```swift
.onOpenURL { url in
    if let paymentRequest = AddressValidator.parsePaymentRequest(url.absoluteString) {
        // Use .deepLink source for bitcoin: or lightning: URLs
        viewModel.sendMode = .quick(paymentRequest, source: .deepLink)
    }
}
```

### Step 2: It Just Works™
No other changes needed! The source will automatically:
- Flow through SendViewModel
- Get extracted by view builders
- Display in QuickPaymentView with link icon

## Available Sources

From `PaymentRequestSource` enum in `QuickPaymentView.swift`:

| Source | Icon | Display Text | Use Case |
|--------|------|--------------|----------|
| `.clipboard` | `doc.on.clipboard` | "clipboard" | Pasting from clipboard |
| `.qrCode` | `qrcode` | "QR code" | Camera QR scanning |
| `.deepLink` | `link` | "link" | bitcoin:/lightning: URLs |
| `.manual` | `text.cursor` | "input" | Manual typing, pre-filled |

## Testing

### QR Code Flow
1. Open Send view → Camera mode
2. Scan a BIP-21 QR code with metadata (amount, label, etc.)
3. Should display: "**Payment request scanned**" with QR icon

### Clipboard Flow  
1. Copy a BIP-21 URI or payment address
2. Open Send view
3. Tap paste button
4. Should display: "**Payment request found in clipboard**" with clipboard icon

### Pre-filled Flow
1. Navigate to SendView with `prefilledRecipient` parameter
2. Should display: "**Payment request entered**" with text cursor icon

## Why This Approach Works

**Problem Before:**
```swift
// Source information was lost
sendMode = .quick(paymentRequest)  // 😢 No source!
```

**Solution Now:**
```swift
// Source travels with the payment request
sendMode = .quick(paymentRequest, source: .qrCode)  // 🎉 Source preserved!
```

The `SendMode` enum now stores **both** the payment request **and** its source, ensuring the UI always has the context it needs to display the correct title and icon.
