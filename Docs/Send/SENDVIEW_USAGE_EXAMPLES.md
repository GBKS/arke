# SendView Usage Examples

## Overview

This document provides code examples and usage patterns for the refactored SendView components.

## Basic Usage

### 1. Navigate to SendView (Empty State)

```swift
NavigationLink(destination: SendView()) {
    Text("Send Bitcoin")
}
```

**Result:**
- Opens in `.manualEntry` mode
- Checks clipboard for payment requests
- Shows clipboard banner if valid payment request found
- Otherwise shows empty `RecipientInputSection`

---

### 2. Navigate with Pre-filled Address

```swift
NavigationLink(destination: SendView(prefilledRecipient: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh")) {
    Text("Send to this address")
}
```

**Result:**
- Parses the pre-filled address
- Immediately locks in payment request
- Opens in `.confirmedDestination` mode
- Shows `ConfirmedDestinationCard` with the address

---

### 3. Navigate with Contact

```swift
let contact = ContactModel(cachedName: "Alice", arkAddress: "ark1abc123...")

NavigationLink(destination: SendView(
    prefilledRecipient: contact.arkAddress,
    prefilledContact: contact
)) {
    Text("Send to \(contact.displayName)")
}
```

**Result:**
- Shows contact info banner at top
- Pre-fills the Ark address
- Opens in `.confirmedDestination` mode
- User can clear to start over

---

## Component Usage Examples

### RecipientInputSection

```swift
import SwiftUI

struct MyView: View {
    @State private var input = ""
    @State private var confirmedRequest: PaymentRequest?
    
    var body: some View {
        VStack {
            if confirmedRequest == nil {
                RecipientInputSection(
                    input: $input,
                    onValidPaymentRequest: { request in
                        confirmedRequest = request
                    },
                    onShowAddressFormats: {
                        // Show help sheet
                    }
                )
            } else {
                Text("Payment request confirmed!")
            }
        }
    }
}
```

**Features:**
- Real-time validation
- Shows validation state (idle/valid/invalid)
- Continue button appears when valid
- Info button for address format help

---

### ConfirmedDestinationCard

```swift
import SwiftUI

struct MyView: View {
    @State private var selectedDestination: PaymentDestination?
    let paymentRequest: PaymentRequest
    let rankedDestinations: [PaymentDestinationSelector.RankedDestination]
    
    var body: some View {
        ConfirmedDestinationCard(
            paymentRequest: paymentRequest,
            selectedDestination: $selectedDestination,
            rankedDestinations: rankedDestinations,
            onClear: {
                // Reset to input mode
                selectedDestination = nil
            },
            onChangeDestination: {
                // Show destination picker
            }
        )
    }
}
```

**Features:**
- Read-only display of selected destination
- Shows short address (not full BIP-21 URI)
- Displays metadata (label, message)
- Change button (only when alternatives available)
- Clear button to reset

---

### AmountInputSection

```swift
import SwiftUI

struct MyView: View {
    @State private var amount = ""
    
    var body: some View {
        AmountInputSection(
            amount: $amount,
            maxSpendableAmount: 100000,
            availableBalanceText: "Available: 0.001 BTC (Ark balance) · Est. fee: 100 sats",
            isAmountLocked: false,
            lockedAmountReason: nil
        )
    }
}
```

**Features:**
- Editable or locked (for invoices with amounts)
- Shows minimum amount requirement
- Shows available balance with tap to fill
- Displays fee estimation

---

## Advanced Scenarios

### Handling BIP-21 with Multiple Destinations

```swift
// Example BIP-21 URI
let bip21 = """
bitcoin:tb1pxks6xl9e05xc3atcewg2tyyzgqm5n6mj6aduss3f0pau27206stsax872h?\
amount=0.001&\
label=Coffee%20Shop&\
ark=tark1pm6sr0fpzqqpu4k5llkn6wdswx48fwjjujgu4gm679lqwudrzghz7a2rx7wuup9cpqq6ssw20&\
lightning=lnbc1000n1...
"""

// In SendView, this is handled automatically:
// 1. Parse BIP-21 → PaymentRequest with 3 destinations
// 2. Rank destinations by viability (Ark, Lightning, Bitcoin)
// 3. Select optimal (e.g., Ark)
// 4. Display only: "tark1pm6sr0fpz..."
// 5. User can switch to Lightning or Bitcoin via "Change"
```

---

### Clipboard Detection Flow

```swift
// User copies this to clipboard:
let clipboardContent = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"

// When SendView appears:
// 1. checkClipboardForAddress() runs
// 2. Parses clipboard → valid Bitcoin address
// 3. Creates PaymentRequest
// 4. Shows ClipboardAddressBanner
// 5. User clicks "Use Payment Request"
// 6. lockInPaymentRequest() → mode = .confirmedDestination
// 7. Shows ConfirmedDestinationCard with address
```

---

### Lightning Invoice with Amount

```swift
// User pastes Lightning invoice with embedded amount
let invoice = "lnbc1000n1..." // 100,000 sats

// In SendView:
// 1. Parse invoice → PaymentRequest with amount = 100000
// 2. lockInPaymentRequest() pre-fills amount
// 3. AmountInputSection shows amount as locked
// 4. User cannot edit amount
// 5. Send button enabled immediately
```

---

## State Transitions

### Manual Entry → Confirmed Destination

```swift
// Initial state
mode = .manualEntry
currentPaymentRequest = nil
selectedDestination = nil

// User enters valid address and clicks Continue
lockInPaymentRequest(parsedRequest)

// New state
mode = .confirmedDestination
currentPaymentRequest = parsedRequest
selectedDestination = optimalDestination
rankedDestinations = [...] // ranked list
```

---

### Confirmed Destination → Manual Entry

```swift
// Current state
mode = .confirmedDestination
currentPaymentRequest = some_request
selectedDestination = some_destination
amount = "100000"

// User clicks Clear
clearAll()

// New state
mode = .manualEntry
currentPaymentRequest = nil
selectedDestination = nil
amount = ""
manualInput = ""
```

---

### Changing Payment Method

```swift
// Current state
mode = .confirmedDestination
currentPaymentRequest = bip21_request // Bitcoin + Ark + Lightning
selectedDestination = arkDestination

// User clicks Change → selects Lightning
selectedDestination = lightningDestination

// State after change
mode = .confirmedDestination // stays the same
currentPaymentRequest = bip21_request // stays the same (preserves context)
selectedDestination = lightningDestination // updated
// ConfirmedDestinationCard automatically updates to show Lightning address
```

---

## Error Handling

### Invalid Pre-filled Address

```swift
SendView(prefilledRecipient: "invalid_xyz_123")

// Results in:
// - mode = .manualEntry
// - manualInput = "invalid_xyz_123"
// - error = "Invalid pre-filled address"
// - Shows error banner in RecipientInputSection
```

---

### No Viable Destinations

```swift
// BIP-21 with destinations that require more balance than available
let bip21 = "bitcoin:bc1q...?amount=10000000" // 0.1 BTC
// User only has 0.001 BTC

// lockInPaymentRequest() results in:
// - selectedDestination = nil
// - error = "Cannot send payment. Bitcoin: Insufficient balance"
// - mode stays .manualEntry (doesn't switch to confirmed)
// - Shows error in SendView
```

---

### Network Mismatch

```swift
// User on Signet network
// Clipboard has mainnet address
let mainnetAddress = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"

// ClipboardAddressBanner shows:
// - Warning icon
// - "Incompatible payment request in clipboard"
// - "This address is for mainnet, but you're on signet"
// - "Use Payment Request" button is disabled
```

---

## Testing Patterns

### Unit Test: lockInPaymentRequest

```swift
import Testing

@Suite("SendView Payment Request Locking")
struct SendViewTests {
    
    @Test("Locks in single destination payment request")
    func lockInSingleDestination() async throws {
        let view = SendView()
        let address = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        let request = try #require(AddressValidator.parsePaymentRequest(address))
        
        view.lockInPaymentRequest(request)
        
        #expect(view.mode == .confirmedDestination)
        #expect(view.currentPaymentRequest != nil)
        #expect(view.selectedDestination != nil)
        #expect(view.selectedDestination?.format == .bitcoin)
    }
    
    @Test("Pre-fills amount from payment request")
    func prefilledAmount() async throws {
        let view = SendView()
        let bip21 = "bitcoin:bc1q...?amount=0.001"
        let request = try #require(AddressValidator.parsePaymentRequest(bip21))
        
        view.lockInPaymentRequest(request)
        
        #expect(view.amount == "100000") // 0.001 BTC = 100,000 sats
    }
    
    @Test("Selects optimal destination from multiple options")
    func optimalDestinationSelection() async throws {
        let view = SendView()
        let bip21 = "bitcoin:bc1q...?ark=tark1...&lightning=lnbc1..."
        let request = try #require(AddressValidator.parsePaymentRequest(bip21))
        
        view.lockInPaymentRequest(request)
        
        // Assuming Ark is optimal (lowest fees, instant)
        #expect(view.selectedDestination?.format == .ark)
    }
}
```

---

### UI Test: Complete Send Flow

```swift
import Testing
import SwiftUI

@Suite("SendView UI Flow")
struct SendViewUITests {
    
    @Test("Complete manual entry flow")
    func manualEntryFlow() async throws {
        // 1. Open SendView
        let view = SendView()
        #expect(view.mode == .manualEntry)
        
        // 2. Enter address
        view.manualInput = "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        
        // 3. Validation passes, user clicks Continue
        let request = try #require(AddressValidator.parsePaymentRequest(view.manualInput))
        view.lockInPaymentRequest(request)
        #expect(view.mode == .confirmedDestination)
        
        // 4. Enter amount
        view.amount = "50000"
        
        // 5. Send payment
        // (Would need to mock WalletManager for actual send)
    }
    
    @Test("Clear and start over flow")
    func clearFlow() async throws {
        let view = SendView(prefilledRecipient: "bc1q...")
        #expect(view.mode == .confirmedDestination)
        
        // User clicks Clear
        view.clearAll()
        
        #expect(view.mode == .manualEntry)
        #expect(view.manualInput.isEmpty)
        #expect(view.amount.isEmpty)
        #expect(view.currentPaymentRequest == nil)
        #expect(view.selectedDestination == nil)
    }
}
```

---

## Integration Examples

### From Transaction History

```swift
struct TransactionRow: View {
    let transaction: Transaction
    
    var body: some View {
        HStack {
            // Transaction details...
            
            Button("Send to same address") {
                // Navigate to SendView with pre-filled recipient
                NavigationLink(destination: SendView(
                    prefilledRecipient: transaction.recipientAddress
                )) {
                    EmptyView()
                }
            }
        }
    }
}
```

---

### From Contact List

```swift
struct ContactRow: View {
    let contact: ContactModel
    
    var body: some View {
        HStack {
            Text(contact.displayName)
            Spacer()
            NavigationLink(destination: SendView(
                prefilledRecipient: contact.preferredAddress,
                prefilledContact: contact
            )) {
                Image(systemName: "paperplane")
            }
        }
    }
}
```

---

### QR Code Scanner Integration (Future)

```swift
struct SendView: View {
    // ... existing code ...
    
    @State private var showQRScanner = false
    
    var body: some View {
        // ... existing UI ...
        
        .sheet(isPresented: $showQRScanner) {
            QRCodeScannerView { scannedString in
                if let request = AddressValidator.parsePaymentRequest(scannedString) {
                    lockInPaymentRequest(request)
                    showQRScanner = false
                }
            }
        }
    }
}

// In RecipientInputSection, add QR button:
Button(action: { 
    // Signal parent to show QR scanner
}) {
    Image(systemName: "qrcode.viewfinder")
}
```

---

## Common Patterns

### Pattern 1: Pre-fill and Lock

```swift
// When you want to send to a specific address immediately
SendView(prefilledRecipient: address)

// Opens in .confirmedDestination mode
// User just needs to enter amount and send
```

---

### Pattern 2: Open Empty with Clipboard

```swift
// When you want to check clipboard but let user choose
SendView()

// Opens in .manualEntry mode
// Shows clipboard banner if valid payment request found
// User can accept or dismiss
```

---

### Pattern 3: Contact Flow

```swift
// When sending to a known contact
SendView(
    prefilledRecipient: contact.address,
    prefilledContact: contact
)

// Shows contact info banner
// Pre-fills address
// User can clear to send to different address
```

---

## Best Practices

1. **Always use lockInPaymentRequest() for programmatic address setting**
   ```swift
   // Good
   if let request = AddressValidator.parsePaymentRequest(address) {
       lockInPaymentRequest(request)
   }
   
   // Bad
   manualInput = address // Won't trigger mode change
   ```

2. **Use clearAll() to reset state**
   ```swift
   // Good
   clearAll()
   
   // Bad
   mode = .manualEntry
   manualInput = ""
   amount = ""
   // ... (easy to miss state)
   ```

3. **Check mode before accessing destination-specific state**
   ```swift
   // Good
   if mode == .confirmedDestination, let destination = selectedDestination {
       // Use destination
   }
   
   // Bad
   let destination = selectedDestination! // May crash in .manualEntry mode
   ```

4. **Preserve PaymentRequest context when changing destinations**
   ```swift
   // Good (as implemented)
   // selectedDestination changes, currentPaymentRequest stays the same
   
   // Bad
   // Re-parsing would lose BIP-21 alternatives
   ```
