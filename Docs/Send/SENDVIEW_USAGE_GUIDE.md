# SendView Usage Guide

## Basic Usage

### macOS
```swift
import SwiftUI

// In your macOS app
NavigationStack {
    SendView()
        .environment(walletManager)
}
```

### iOS
```swift
import SwiftUI

// In your iOS app
NavigationStack {
    SendView_iOS()
        .environment(walletManager)
}
```

## Advanced Usage

### Pre-filled Recipient
```swift
// macOS
SendView(prefilledRecipient: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
    .environment(walletManager)

// iOS
SendView_iOS(prefilledRecipient: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
    .environment(walletManager)
```

### Pre-filled Contact
```swift
let contact = ContactModel(cachedName: "Alice", notes: "Friend")
let address = "ark1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"

// macOS
SendView(
    prefilledRecipient: address,
    prefilledContact: contact,
    onNavigateToContact: { contact in
        // Navigate to contact detail view
        navigationPath.append(contact)
    }
)
.environment(walletManager)

// iOS
SendView_iOS(
    prefilledRecipient: address,
    prefilledContact: contact,
    onNavigateToContact: { contact in
        // Navigate to contact detail view
        navigationPath.append(contact)
    }
)
.environment(walletManager)
```

## Supported Payment Formats

The SendView automatically detects and handles:

### Bitcoin Addresses
```swift
SendView(prefilledRecipient: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
```

### BIP-21 URIs
```swift
// Simple BIP-21
SendView(prefilledRecipient: "bitcoin:bc1q...?amount=0.001")

// With label and message
SendView(prefilledRecipient: "bitcoin:bc1q...?amount=0.001&label=Coffee&message=Order%2042")

// Multi-destination (Bitcoin + Ark)
SendView(prefilledRecipient: "bitcoin:bc1q...?amount=0.001&ark=ark1q...")
```

### Lightning Invoices
```swift
// BOLT11 invoice
SendView(prefilledRecipient: "lnbc1000n1pj9x7zmpp5...")

// BOLT12 offer
SendView(prefilledRecipient: "lno1zrxq8pjw7qjlm68mtp7e3yvxee4y5...")
```

### Ark Addresses
```swift
SendView(prefilledRecipient: "ark1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
```

### Silent Payments
```swift
SendView(prefilledRecipient: "sp1qqgste7k9hx0qftg6qmwlkqtwuy6cycyavzmzj85c6qdfhjdpdjtdgq...")
```

### BIP-353 (Human-Readable Names)
```swift
// With bitcoin symbol
SendView(prefilledRecipient: "₿alice@example.com")

// Without symbol (tries BIP-353 first, falls back to Lightning Address)
SendView(prefilledRecipient: "alice@example.com")
```

### Lightning Addresses
```swift
SendView(prefilledRecipient: "satoshi@strike.me")
```

## Clipboard Detection Behavior

### macOS
- ✅ Checks clipboard when SendView first appears
- ✅ Checks clipboard when window becomes key
- 🎯 No permission dialogs required

### iOS
- ✅ Checks clipboard when SendView first appears
- ❌ Does NOT check on app focus (avoids permission spam)
- 🎯 Shows system permission banner on first clipboard access

## State Management

### ViewModel Access
```swift
// The ViewModel is internal to SendView, but you can observe its effects through:

struct ParentView: View {
    @State private var showSendView = false
    
    var body: some View {
        Button("Send") {
            showSendView = true
        }
        .sheet(isPresented: $showSendView) {
            NavigationStack {
                SendView_iOS()
                    .environment(walletManager)
            }
        }
    }
}
```

## Testing

### Mock Wallet Manager
```swift
#Preview {
    NavigationStack {
        SendView()
            .environment(WalletManager(useMock: true))
    }
}
```

### Custom Test Scenarios
```swift
#Preview("Lightning Invoice") {
    NavigationStack {
        SendView(
            prefilledRecipient: "lnbc1000n1pj9x7zmpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu"
        )
        .environment(WalletManager(useMock: true))
    }
}
```

## Error Handling

The SendView automatically handles errors and displays them to the user:

```swift
// Errors are displayed inline with retry option
// No additional error handling needed by parent view
```

## Payment Flow

### Manual Entry
1. User enters address manually
2. Address is validated
3. Payment destinations are ranked
4. Optimal destination is selected
5. User enters amount
6. User taps "Send"
7. Payment executes
8. View dismisses on success

### Contact Payment
1. Contact and address are pre-filled
2. Address is validated
3. Contact banner is shown
4. User enters amount
5. User taps "Send"
6. Payment executes
7. View dismisses on success

### Quick Payment (Clipboard)
1. Address detected in clipboard
2. Quick payment card appears
3. User can accept or dismiss
4. If accepted, payment destinations are ranked
5. User enters amount (if not embedded)
6. User taps "Send"
7. Payment executes
8. View dismisses on success

## Customization

### Minimum Ark Send Amount
The minimum send amount for Ark addresses is configured in SendViewModel:
```swift
let minimumSendArk: Int = 330 // sats
```

### Payment Context Configuration
Payment routing is determined automatically based on:
- Available Ark balance
- Available Bitcoin balance
- Network configuration
- User preferences
- Ark server connection status
- Lightning capability

## Integration Examples

### From Transaction List
```swift
Button("Resend") {
    navigationPath.append(
        SendDestination(
            recipient: transaction.address,
            contact: nil
        )
    )
}
.navigationDestination(for: SendDestination.self) { destination in
    SendView(
        prefilledRecipient: destination.recipient,
        prefilledContact: destination.contact
    )
}
```

### From Contact Detail
```swift
Button("Send") {
    navigationPath.append(
        SendDestination(
            recipient: contact.primaryAddress,
            contact: contact
        )
    )
}
```

### From QR Code Scanner
```swift
CodeScannerView { result in
    if case .success(let scannedCode) = result {
        navigationPath.append(
            SendDestination(
                recipient: scannedCode.string,
                contact: nil
            )
        )
    }
}
```

## Best Practices

### ✅ Do
- Always provide WalletManager environment
- Use NavigationStack as parent
- Handle navigation via navigationPath
- Test with various payment formats

### ❌ Don't
- Don't wrap in multiple NavigationStacks
- Don't manage ViewModel externally
- Don't override clipboard behavior
- Don't modify SendViewModel state directly from parent

---

**Note**: For iOS, clipboard access will show a system permission banner on first access. This is expected behavior and complies with iOS 16+ privacy requirements.
