# Payment Destination Selector

## Overview

The `PaymentDestinationSelector` is a helper class that intelligently selects the optimal payment destination from a BIP-21 payment request based on available balances, fees, user preferences, and network conditions.

## Key Features

### 1. **Balance-Aware Selection**
- Understands that **Ark balance is shared** between Ark and Lightning payments
- Tracks Bitcoin balance separately for on-chain payments
- Automatically falls back to alternative payment methods when primary balance is insufficient

### 2. **Fee Optimization**
Default priority order (lowest fees first):
1. **Ark** - Same server transfers (typically free)
2. **Lightning** - Via Ark server (low fees, uses Ark balance)
3. **Silent Payments** - On-chain with privacy
4. **Bitcoin** - Standard on-chain

### 3. **Smart Context Awareness**
- Checks Ark server connectivity before suggesting Lightning
- Validates Lightning capability availability
- Respects user-defined minimum reserve balances
- Network-compatible destination filtering

### 4. **Customizable Preferences**
Users can configure:
- Custom priority order
- Large amount threshold (prefer on-chain for big payments)
- Minimum Ark reserve to maintain
- On-chain preference for final settlement

## Architecture

```
┌─────────────────────────────────────────┐
│      PaymentDestinationSelector         │
├─────────────────────────────────────────┤
│                                         │
│  ┌───────────────────────────────────┐ │
│  │   PaymentContext                  │ │
│  │   - arkBalance                    │ │
│  │   - bitcoinBalance                │ │
│  │   - networkConfig                 │ │
│  │   - userPreferences               │ │
│  │   - arkServerConnected            │ │
│  │   - hasLightningCapability        │ │
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │   PaymentPreferences              │ │
│  │   - priorityOrder                 │ │
│  │   - preferOnChainForLargeAmounts  │ │
│  │   - largeAmountThreshold          │ │
│  │   - minimumArkReserve             │ │
│  └───────────────────────────────────┘ │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │   RankedDestination               │ │
│  │   - destination                   │ │
│  │   - balanceSource                 │ │
│  │   - availableBalance              │ │
│  │   - estimatedFee                  │ │
│  │   - viable                        │ │
│  │   - reason                        │ │
│  │   - priority                      │ │
│  └───────────────────────────────────┘ │
│                                         │
└─────────────────────────────────────────┘
```

## Balance Sources

The selector understands three balance sources:

| Balance Source   | Used For                    | Deducts From    |
|------------------|----------------------------|-----------------|
| `.ark`           | Ark-to-Ark transfers       | `arkBalance`    |
| `.arkViaServer`  | Lightning payments         | `arkBalance`    |
| `.bitcoin`       | On-chain BTC & Silent Pay  | `bitcoinBalance`|

## Usage

### Basic Selection

```swift
// Parse payment request
let paymentRequest = AddressValidator.parsePaymentRequest(bip21URI)

// Create context
let context = PaymentDestinationSelector.PaymentContext(
    arkBalance: walletManager.arkBalance,
    bitcoinBalance: walletManager.bitcoinBalance,
    networkConfig: walletManager.currentNetwork
)

// Get optimal destination
if let optimal = paymentRequest.selectOptimalDestination(context: context) {
    // Use this destination for payment
    print("Using: \(optimal.format.displayName)")
}
```

### Getting All Ranked Options

```swift
let ranked = paymentRequest.rankedDestinations(context: context)

for option in ranked where option.viable {
    print("\(option.destination.format.displayName)")
    print("  Fee: ~\(option.estimatedFee ?? 0) sats")
    print("  Source: \(option.balanceSource.displayName)")
}
```

### Custom Preferences

```swift
let preferences = PaymentDestinationSelector.PaymentPreferences(
    priorityOrder: [.bitcoin, .ark, .lightning], // Prefer on-chain
    preferOnChainForLargeAmounts: true,
    largeAmountThreshold: 1_000_000, // 1M sats
    minimumArkReserve: 50_000        // Keep 50k sats
)

let context = PaymentDestinationSelector.PaymentContext(
    arkBalance: arkBalance,
    bitcoinBalance: bitcoinBalance,
    networkConfig: currentNetwork,
    userPreferences: preferences
)
```

## Examples

### Example 1: Automatic Fallback

```
Payment amount: 600,000 sats
Destinations: [Ark, Lightning, Bitcoin]
Ark balance: 500,000 sats (insufficient)
Bitcoin balance: 1,000,000 sats (sufficient)

Result: Selects Bitcoin (automatic fallback)
```

### Example 2: Reserve Protection

```
Payment amount: 495,000 sats
Destinations: [Ark, Bitcoin]
Ark balance: 500,000 sats
Minimum reserve: 10,000 sats
Bitcoin balance: 1,000,000 sats

Result: Selects Bitcoin (to preserve reserve)
```

### Example 3: Server Offline

```
Payment amount: 100,000 sats
Destinations: [Ark, Lightning, Bitcoin]
Ark server: OFFLINE
Balances: All sufficient

Result: Selects Bitcoin (Ark/Lightning unavailable)
```

## Testing

Comprehensive test suite included in `PaymentDestinationSelectorTests.swift` covering:
- Balance source detection
- Optimal destination selection
- Insufficient balance fallback
- Server connectivity handling
- Reserve balance protection
- Custom preferences
- Edge cases

Run tests with:
```bash
swift test
```

## Integration Points

### With AddressValidator
The selector works seamlessly with `AddressValidator.parsePaymentRequest()` output.

### With WalletManager
Get context directly from wallet state:
```swift
let context = PaymentDestinationSelector.PaymentContext(
    arkBalance: walletManager.arkBalance,
    bitcoinBalance: walletManager.bitcoinBalance,
    networkConfig: walletManager.currentNetwork
)
```

### With SendView
Use to automatically select or present payment options to users.

## Best Practices

1. **Always check viability** before attempting payment
2. **Show user the balance source** so they understand what's being spent
3. **Respect user preferences** - allow customization
4. **Handle server connectivity** - don't assume Ark server is always online
5. **Protect reserves** - don't drain accounts to zero
6. **Consider amount size** - large payments may benefit from on-chain settlement

## Future Enhancements

Potential additions:
- Dynamic fee estimation from mempool
- Lightning channel capacity checking
- Time-based preferences (fast vs cheap)
- Multi-hop routing optimization
- Historical fee analysis
- User payment history learning

## Files

- `PaymentDestinationSelector.swift` - Main implementation
- `PaymentDestinationSelectorTests.swift` - Comprehensive test suite
- `PaymentDestinationSelectorExamples.swift` - Usage examples
- `AddressValidator.swift` - Payment request parsing (existing)
- `PaymentRequest.swift` - Data model (existing)
- `PaymentDestination.swift` - Data model (existing)

## Summary

The `PaymentDestinationSelector` provides intelligent, balance-aware payment destination selection with the key understanding that **Lightning and Ark payments share the same balance** (arkBalance). This enables smart fallback logic, fee optimization, and reserve protection while giving users full control over payment preferences.
