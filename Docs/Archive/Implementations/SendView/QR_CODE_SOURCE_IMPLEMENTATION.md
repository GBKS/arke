# QR Code Source Tracking Implementation

## Problem Summary

Previously, when a payment request was created from scanning a QR code, there was no way to track that it came from a QR code. The `SendMode.quick` enum case only stored the `PaymentRequest` but not the source, so when `QuickPaymentView` was rendered, it couldn't display the correct title like "Payment request scanned" with a QR code icon.

This caused fragility because:
1. The source information was lost when setting `sendMode = .quick(paymentRequest)`
2. The view builder had no way to know the original source
3. Attempts to hardcode `.qrCode` in view builders broke clipboard flows

## Solution

Added source tracking to the `SendMode.quick` enum case.

### Changes Made

#### 1. SendViewModel.swift

**Updated SendMode enum:**
```swift
enum SendMode {
    case manual
    case contact(ContactModel)
    case quick(PaymentRequest, source: PaymentRequestSource)  // Added source parameter
}
```

**Updated all places that set quick mode:**

- **Clipboard detection** (line ~364):
  ```swift
  sendMode = .quick(paymentRequest, source: .clipboard)
  ```

- **Pre-filled recipient** (line ~216):
  ```swift
  sendMode = .quick(paymentRequest, source: .manual)
  ```

#### 2. SendView_iOS.swift

**QR code scanning** (line ~221):
```swift
// Rich payment request with metadata - use quick mode for better UX
viewModel.sendMode = .quick(paymentRequest, source: .qrCode)
```

**Pattern matching in modeSpecificContent** (line ~479):
```swift
case .quick(let paymentRequest, let source):
    quickModeView(viewModel: viewModel, paymentRequest: paymentRequest, source: source)
```

**Updated quickModeView function** (line ~530):
```swift
private func quickModeView(
    viewModel: SendViewModel, 
    paymentRequest: PaymentRequest, 
    source: PaymentRequestSource  // Added parameter
) -> some View {
    QuickPaymentView(
        // ... other parameters
        source: source  // Now passes through
    )
}
```

#### 3. SendView.swift (macOS)

Made identical changes to the macOS version:

**Pattern matching in modeSpecificContent** (line ~121):
```swift
case .quick(let paymentRequest, let source):
    quickModeView(viewModel: viewModel, paymentRequest: paymentRequest, source: source)
```

**Updated quickModeView function** (line ~180):
```swift
private func quickModeView(
    viewModel: SendViewModel, 
    paymentRequest: PaymentRequest, 
    source: PaymentRequestSource
) -> some View {
    QuickPaymentView(
        // ... other parameters
        source: source
    )
}
```

## Result

Now when a QR code is scanned:
1. ✅ `sendMode` is set to `.quick(paymentRequest, source: .qrCode)`
2. ✅ View builder extracts both `paymentRequest` and `source`
3. ✅ `QuickPaymentView` receives `source: .qrCode`
4. ✅ Title displays: "Payment request scanned" with QR code icon 🎉

The same logic works correctly for:
- **Clipboard**: Shows "Payment request found in clipboard" with clipboard icon
- **Manual**: Shows "Payment request entered" with text cursor icon
- **Deep Link**: Shows "Payment request from link" with link icon (when implemented)

## Why This Works

The source information now **travels with the payment request** through the entire flow:

```
QR Scan → SendViewModel (stores source in enum) → View Builder (extracts source) → QuickPaymentView (displays with correct UI)
```

Previously, the information was lost at step 1, making step 3 impossible.

## Future Enhancements

If you implement deep link handling (bitcoin: or lightning: URL schemes), you can use:

```swift
.onOpenURL { url in
    if let paymentRequest = AddressValidator.parsePaymentRequest(url.absoluteString) {
        viewModel.sendMode = .quick(paymentRequest, source: .deepLink)
    }
}
```

## Testing

The existing preview "Source: QR Code" in `QuickPaymentView.swift` will now be testable in the actual flow by:
1. Opening the Send view
2. Tapping camera mode
3. Scanning a BIP-21 URI QR code with metadata
4. Verifying the title shows "Payment request scanned" with QR icon
