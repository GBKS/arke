# ClipboardAddressBanner Enhancement: PaymentDestinationSelector Integration

## Overview

The `ClipboardAddressBanner` has been enhanced to use the `PaymentDestinationSelector` to preview the optimal payment method **before** the user clicks "Use Payment Request". This eliminates confusion where the banner showed one thing (e.g., Bitcoin) but the app selected something else (e.g., Ark).

## Problem Statement

### Before Enhancement

When a BIP-21 URI with multiple payment destinations was in the clipboard:

```
bitcoin:tb1q...?amount=0.001&ark=tark1q...
```

The banner would display:
- **Primary**: Bitcoin (Signet) - `tb1q...`
- **Alternative**: Ark - `tark1q...`

But when the user clicked "Use Payment Request", the app would:
1. Parse all destinations
2. Rank them using `PaymentDestinationSelector`
3. **Auto-select Ark** (optimal: lower priority number, no fees)

This created a disconnect:
- 🤔 User sees: "Bitcoin is primary, Ark is alternative"
- ✨ App selects: Ark (optimal)
- 😕 User thinks: "Why did it pick Ark when Bitcoin was shown first?"

### Root Cause

The banner was displaying the **BIP-21 primary destination** (which is just the order in the URI), not the **optimal destination** based on balances, fees, and network compatibility.

## Solution

### Enhancement Details

The `ClipboardAddressBanner` now:

1. **Accepts a `PaymentContext`** parameter (optional for backward compatibility)
2. **Uses `PaymentDestinationSelector`** to rank destinations
3. **Shows the optimal destination prominently** with a ⭐ star icon
4. **Displays accurate fee and balance information**
5. **Lists other viable alternatives** below the optimal one

### New Display Format

#### With PaymentContext (recommended)

```
┌─────────────────────────────────────────────┐
│ ⭐ Payment request found in clipboard       │
│                                             │
│ ⭐ Will pay via Ark                         │
│    tark1qxy...example                       │
│    Ark Balance · No fees                    │
│                                             │
│    Amount: 100000 sats                      │
│    Label: Coffee Shop                       │
│                                             │
│    Alternative payment methods:             │
│    ₿ Bitcoin: tb1qw50...pjzsx (~500 sats)  │
│                                             │
│    [Use Payment Request]                    │
└─────────────────────────────────────────────┘
```

#### Without PaymentContext (fallback)

If no context is provided, the banner falls back to showing the primary destination and alternatives without ranking (same as before):

```
┌─────────────────────────────────────────────┐
│ 📋 Payment request found in clipboard       │
│                                             │
│    Bitcoin (Signet)                         │
│    tb1qw508d6qejxtdg4y5r3zarvary0c5xw7k... │
│                                             │
│    Alternative payment options:             │
│    🟣 Ark: tark1qxy...example               │
│                                             │
│    [Use Payment Request]                    │
└─────────────────────────────────────────────┘
```

## Implementation Changes

### ClipboardAddressBanner.swift

#### Added Properties

```swift
let paymentContext: PaymentDestinationSelector.PaymentContext?

private var rankedDestinations: [PaymentDestinationSelector.RankedDestination] {
    guard let context = paymentContext else { return [] }
    return paymentRequest.rankedDestinations(context: context)
}

private var optimalDestination: PaymentDestinationSelector.RankedDestination? {
    rankedDestinations.first(where: { $0.viable })
}

private var otherViableDestinations: [PaymentDestinationSelector.RankedDestination] {
    guard let optimal = optimalDestination else { return [] }
    return rankedDestinations.filter { $0.viable && $0.destination.id != optimal.destination.id }
}
```

#### Updated Display Logic

```swift
// Show optimal destination if context is available
if let optimal = optimalDestination {
    HStack(spacing: 4) {
        Image(systemName: "star.fill")
            .font(.caption2)
            .foregroundColor(.yellow)
        Text("Will pay via \(optimal.destination.format.displayName)")
            .font(.caption)
            .foregroundColor(.primary)
            .fontWeight(.semibold)
    }
    
    Text(optimal.destination.shortAddress)
        .font(.caption2)
        .foregroundColor(.secondary)
    
    HStack(spacing: 8) {
        Text(optimal.balanceSource.displayName)
        if let fee = optimal.estimatedFee {
            Text("·")
            Text(fee > 0 ? "~\(fee) sats fee" : "No fees")
        }
    }
}
```

### SendView.swift

#### Pass PaymentContext to Banner

```swift
ClipboardAddressBanner(
    paymentRequest: paymentRequest,
    onUseAddress: { ... },
    onDismiss: { ... },
    currentNetwork: currentNetworkConfig,
    paymentContext: paymentContext  // ← New parameter
)
```

## Benefits

### 1. **Accurate Preview**
Users see exactly what will happen when they click "Use Payment Request":
- ✅ Same destination that will be auto-selected
- ✅ Accurate fee estimate
- ✅ Correct balance source

### 2. **Better User Confidence**
No more surprises:
- 🎯 "I know Ark will be selected because the banner shows it"
- 💰 "I can see it's fee-free before I click"
- ⚡ "I can see other options available if I want to change later"

### 3. **Consistent UX**
The banner and the main SendView use the **same selection logic**:
- Same `PaymentDestinationSelector`
- Same `PaymentContext`
- Same ranking algorithm

### 4. **Educational**
Users learn about payment priorities:
- "Oh, Ark is recommended because it's free"
- "Bitcoin costs ~500 sats, that's why it's alternative"
- "Lightning is available too with ~100 sats fee"

### 5. **Backward Compatible**
The `paymentContext` parameter is optional:
- ✅ Existing code without context still works
- ✅ New code can provide context for enhanced UX
- ✅ Gradual migration path

## Testing

### Scenario 1: BIP-21 with Ark Optimal

**Input:**
```
bitcoin:tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx?amount=0.001&ark=tark1qxyz
```

**Expected Banner Display:**
```
⭐ Will pay via Ark
   tark1qxy...z
   Ark Balance · No fees
   
   Amount: 100000 sats
   
   Alternative payment methods:
   ₿ Bitcoin: tb1qw50...pjzsx (~500 sats)
```

**After "Use Payment Request":**
- Recipient filled with full BIP-21 URI
- Ark auto-selected
- Indicator shows: "Paying via Ark · Change"

✅ **Banner preview matches actual selection**

### Scenario 2: Insufficient Ark Balance

**Setup:**
- Ark Balance: 50,000 sats
- Bitcoin Balance: 1,000,000 sats

**Input:**
```
bitcoin:tb1q...?amount=0.005&ark=tark1q...
```
(500,000 sats requested)

**Expected Banner Display:**
```
⭐ Will pay via Bitcoin
   tb1qw50...pjzsx
   Bitcoin Balance · ~500 sats fee
   
   Amount: 500000 sats
```

**Note:** No alternative methods shown because Ark is not viable

**After "Use Payment Request":**
- Bitcoin auto-selected
- No "Change" button (only 1 viable destination)

✅ **Banner correctly shows Bitcoin as optimal when Ark insufficient**

### Scenario 3: Network Mismatch

**Input:** Mainnet address on Signet wallet
```
bitcoin:bc1q...?ark=ark1q...
```

**Expected Banner Display:**
```
⚠️ Incompatible payment request in clipboard
   This address is for Mainnet, but you're on Signet
```

**After "Use Payment Request":**
- (Not clickable - network mismatch prevents usage)

✅ **Banner warns about network incompatibility**

### Scenario 4: No Context Provided (Fallback)

**Code:**
```swift
ClipboardAddressBanner(
    paymentRequest: paymentRequest,
    onUseAddress: { ... },
    onDismiss: { ... }
    // No paymentContext parameter
)
```

**Expected Banner Display:**
```
📋 Payment request found in clipboard
   Bitcoin (Signet)
   tb1qw508d6qejxtdg4y5r3zarvary0c5xw7k...
   
   Alternative payment options:
   🟣 Ark: tark1qxy...example
```

✅ **Fallback to old display format without ranking**

## Related Files

- `ClipboardAddressBanner.swift` - Main changes to display optimal destination
- `SendView.swift` - Pass `paymentContext` to banner
- `PaymentDestinationSelector.swift` - Used by banner for ranking
- `../Archive/Fixes/CLIPBOARD_BANNER_BUG_FIX.md` - Related fix for preserving alternatives

## Future Enhancements

### 1. Show Why a Destination is Optimal

```
⭐ Will pay via Ark (Recommended)
   tark1qxy...z
   ✓ No fees
   ✓ Instant confirmation
   ✓ Same Ark server
```

### 2. Show Non-Viable Alternatives with Reasons

```
Alternative payment methods:
   ₿ Bitcoin: tb1qw50...pjzsx (~500 sats)

Unavailable:
   ⚡ Lightning: Ark server not connected
```

### 3. Interactive Preview

Allow tapping on alternative methods in the banner to preview what would happen:
- Tap Bitcoin → Preview shows "Would use Bitcoin Balance, ~500 sats fee"
- Tap Ark → Preview shows "Would use Ark Balance, no fees"

### 4. Dynamic Updates

If balances change while banner is visible, update the optimal destination:
- User's Ark balance runs low → Switch preview to Bitcoin
- Ark server reconnects → Switch preview back to Ark

## Conclusion

This enhancement ensures the `ClipboardAddressBanner` provides an **accurate preview** of what will happen when the user accepts the payment request. By integrating with `PaymentDestinationSelector`, we:

- ✅ Eliminate user confusion
- ✅ Show accurate fee estimates
- ✅ Display the same selection logic as the main view
- ✅ Maintain backward compatibility
- ✅ Provide a better overall UX

The banner now serves as a **smart preview** that helps users make informed decisions before committing to use a payment request.
