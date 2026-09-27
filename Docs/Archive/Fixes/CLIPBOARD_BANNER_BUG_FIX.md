# Clipboard Banner Bug Fix

## Issue Description

When copying a BIP-21 URI with multiple payment destinations to the clipboard:
```
bitcoin:tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx?amount=0.001&ark=tark1qxyz
```

The ClipboardAddressBanner would appear correctly showing the payment request, but when clicking "Use Payment Request", it would **only use the Bitcoin address** instead of the full BIP-21 URI, causing the Ark alternative to be lost.

### Expected Behavior (per Scenario 8)
1. ✅ Clipboard banner appears
2. ✅ Shows Bitcoin as primary, Ark as alternative
3. ✅ User taps "Use Payment Request"
4. ✅ Full BIP-21 URI fills recipient field
5. ✅ **Ark is auto-selected** (optimal: lowest priority, zero fees)
6. ✅ Amount pre-filled: 100000 sats
7. ✅ Indicator shows: "Paying via Ark · Change"

### Actual Behavior (before fix)
1. ✅ Clipboard banner appears correctly
2. ✅ Shows Bitcoin as primary, Ark as alternative
3. ✅ User taps "Use Payment Request"
4. ❌ **Only Bitcoin address** fills recipient field: `tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx`
5. ❌ **Bitcoin is selected** (only destination available)
6. ✅ Amount pre-filled: 100000 sats
7. ❌ Indicator shows: "Paying via Bitcoin" (no Change button)

## Root Cause

In `SendView.swift`, the `ClipboardAddressBanner` callback was using:

```swift
recipient = paymentRequest.primaryAddress ?? ""
```

This extracted **only the primary address** from the parsed `PaymentRequest`, discarding all alternative destinations.

When `handleRecipientChange(_:)` would then parse this recipient string, it would only see a simple Bitcoin address with no alternatives, so the destination selector could only choose Bitcoin.

## The Fix

The fix involved two changes:

### 1. Store the Original Clipboard String

Added a new state variable to preserve the raw clipboard content:

```swift
@State private var clipboardRawString: String?
```

### 2. Use Original String in Banner Callback

Modified `checkClipboardForAddress()` to store both the parsed request and the original string:

```swift
clipboardPaymentRequest = paymentRequest
clipboardRawString = trimmedString  // Preserve the original BIP-21 URI
```

### 3. Use Raw String When Filling Recipient Field

Updated the `ClipboardAddressBanner` callback:

```swift
onUseAddress: {
    // Use the original raw clipboard string to preserve all payment alternatives
    recipient = clipboardRawString ?? paymentRequest.primaryAddress ?? ""
    // Note: amount pre-filling is handled by handleRecipientChange
    clipboardPaymentRequest = nil
    clipboardRawString = nil
}
```

Now when the recipient field is filled, it contains the **complete BIP-21 URI**, allowing `handleRecipientChange(_:)` to:
1. Parse all destinations (Bitcoin, Ark, Lightning, etc.)
2. Rank them by priority and fees
3. Auto-select the optimal one (Ark in this case)

## Testing

To verify the fix:

1. Copy this to clipboard:
   ```
   bitcoin:tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx?amount=0.001&ark=tark1qxyzexample
   ```

2. Navigate to SendView

3. Click "Use Payment Request"

4. Check console output:
   ```
   🔍 [SendView] Parsed payment request details:
      Destinations: 2
      Primary format: bitcoin (Bitcoin)
      ...
      Has alternatives: true
      Alternative destinations:
        [1] Ark: tark1qxy...example
   
   🎯 [SendView] Ranked destinations:
      ✓ [1] Ark
         Balance: Ark Balance
         Available: 1000000 sats
         Fee: ~0 sats
         Reason: Sufficient balance
      ✓ [2] Bitcoin
         Balance: Bitcoin Balance
         Available: 2000000 sats
         Fee: ~500 sats
         Reason: Sufficient balance
   
   ✨ [SendView] Auto-selected optimal destination: Ark
   ```

5. Verify UI shows:
   - ✅ "Paying via Ark · Change"
   - ✅ "Available: 1,000,000 sats (Ark Balance) · No fees"
   - ✅ Amount pre-filled: "100000"
   - ✅ "Change" button visible

## Why This Matters

BIP-21 URIs with multiple payment destinations are designed to give the **payer flexibility** to choose the most efficient payment method. By losing the alternatives when filling the recipient field, we were:

1. **Forcing higher fees** - Bitcoin on-chain (~500 sats) instead of Ark (0 sats)
2. **Breaking user expectations** - The banner showed alternatives, but they weren't actually available
3. **Violating the BIP-21 spec** - Alternative payment methods should be preserved and considered

The fix ensures that the **payment destination selector** can properly analyze all options and choose the optimal one based on:
- Balance availability
- Network compatibility
- Fee estimates
- User preferences
- Priority order (Ark > Lightning > Bitcoin)

## Related Files

- `SendView.swift` - Main fix location
- `ClipboardAddressBanner.swift` - Banner display (unchanged, but shows why the issue was confusing)
- `PaymentDestinationSelector.swift` - Ranking logic (working correctly, was just receiving incomplete data)
- `AddressValidator.swift` - Parsing logic (working correctly)

## Impact

This fix ensures that **Scenario 8** from `SENDVIEW_TEST_SCENARIOS.md` now works correctly, and users will benefit from:
- ✅ Automatic selection of the lowest-fee payment method
- ✅ Full preservation of BIP-21 payment alternatives
- ✅ Correct destination ranking and fee estimation
- ✅ Ability to manually switch between viable alternatives using the "Change" button
