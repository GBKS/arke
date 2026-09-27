# QuickPaymentView Source Parameter Guide

## Overview

`QuickPaymentView` now supports configurable titles based on where the payment request originated from. This makes the UI more contextually accurate for users.

## The PaymentRequestSource Enum

```swift
enum PaymentRequestSource {
    case clipboard  // Payment request came from clipboard detection
    case qrCode     // Payment request came from QR code scan
    case deepLink   // Payment request came from a tapped bitcoin:/lightning: link
    case manual     // Payment request came from manual user input
}
```

### Display Properties

Each source has associated display properties:

- **Display Name**: The text shown in the title (e.g., "clipboard", "QR code", "link", "input")
- **Icon Name**: The SF Symbol icon shown next to the title
- **Icon Color**: Automatically adjusts based on network compatibility

## How It Works

### Before
```
"Payment request found in clipboard"  // Always said "clipboard"
```

### After
```
"Payment request found in QR code"     // source: .qrCode
"Payment request found in link"        // source: .deepLink
"Address found in clipboard"           // source: .clipboard
```

The title automatically adapts based on:
1. **Source**: Where the payment request came from
2. **Content Type**: Whether it's a simple address or full payment request
3. **Compatibility**: Whether it matches the current network

## Implementation Guide

### Default Behavior

The `source` parameter defaults to `.clipboard` for backward compatibility:

```swift
QuickPaymentView(
    paymentRequest: request,
    onDismiss: { dismiss() }
    // source defaults to .clipboard
)
```

### Implementing Different Sources

#### 1. QR Code Scans

In `SendView_iOS.swift`, around line 240 where QR codes are handled:

```swift
QRScannerView_iOS { scannedCode in
    if let paymentRequest = AddressValidator.parsePaymentRequest(scannedCode) {
        viewModel.sendMode = .quick(paymentRequest)
        // When you update the quickModeView builder, add:
        source: .qrCode
    }
}
```

#### 2. Clipboard Detection

When pasting from clipboard (already the default):

```swift
QuickPaymentView(
    paymentRequest: request,
    onDismiss: { dismiss() },
    source: .clipboard  // Explicit or let default
)
```

#### 3. Deep Links

When handling bitcoin: or lightning: URL schemes:

```swift
func handleURL(_ url: URL) {
    if let paymentRequest = AddressValidator.parsePaymentRequest(url.absoluteString) {
        QuickPaymentView(
            paymentRequest: paymentRequest,
            onDismiss: { dismiss() },
            source: .deepLink
        )
    }
}
```

#### 4. Manual Input

When user types or pastes into a text field:

```swift
QuickPaymentView(
    paymentRequest: request,
    onDismiss: { dismiss() },
    source: .manual
)
```

## Key Locations to Update

When you're ready to implement this throughout the app, look for these locations:

### 1. SendView_iOS.swift

**QR Code Handler** (line ~240):
```swift
QRScannerView_iOS { scannedCode in
    // ...
    viewModel.sendMode = .quick(paymentRequest)
    // Add source: .qrCode to quickModeView
}
```

**Clipboard Handler** (line ~420):
```swift
private func handlePasteFromClipboard() {
    // Already using .clipboard by default
}
```

**Quick Mode View Builder** (line ~530):
```swift
@ViewBuilder
private func quickModeView(viewModel: SendViewModel, paymentRequest: PaymentRequest) -> some View {
    QuickPaymentView(
        paymentRequest: paymentRequest,
        // ... other parameters
        source: .qrCode  // or .clipboard, depending on the flow
    )
}
```

### 2. App URL Handling

Look for URL scheme handlers that might handle `bitcoin:` or `lightning:` URIs:

```swift
.onOpenURL { url in
    if let paymentRequest = AddressValidator.parsePaymentRequest(url.absoluteString) {
        QuickPaymentView(
            paymentRequest: paymentRequest,
            source: .deepLink
        )
    }
}
```

## Testing

Use the new previews to see how each source looks:

- `#Preview("Source: Clipboard")`
- `#Preview("Source: QR Code")`
- `#Preview("Source: Deep Link")`
- `#Preview("Source: Manual")`

## Visual Differences

### Clipboard
- Icon: `doc.on.clipboard`
- Title: "Payment request found in clipboard"

### QR Code
- Icon: `qrcode`
- Title: "Payment request found in QR code"

### Deep Link
- Icon: `link`
- Title: "Payment request found in link"

### Manual
- Icon: `text.cursor`
- Title: "Payment request found in input"

## Migration Strategy

Since `source` has a default value of `.clipboard`, existing code will continue to work without changes. You can:

1. Start by adding `.qrCode` source to QR scan flows (most obvious win)
2. Add `.deepLink` to URL handlers when you implement them
3. Use `.manual` for text field inputs if needed
4. Leave `.clipboard` as the default for backward compatibility

## Notes

- The icon also changes based on source (e.g., QR code icon for scanned codes)
- Network incompatibility always shows an orange warning triangle, regardless of source
- Simple addresses vs. full payment requests are automatically detected and labeled
- The help text on the dismiss button still says "Clear contact" (might want to update this separately)

## Future Enhancements

Possible additions:
- `.nfc` - For NFC tag scans
- `.contact` - For selecting from contacts
- `.share` - For receiving via Share Sheet
- Custom source with configurable display name and icon
