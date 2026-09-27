# Network Mismatch UX Improvements

## Overview
Enhanced the clipboard address banner to show incompatible payment requests with clear warnings instead of silently hiding them.

## Changes Made

### 1. ClipboardAddressBanner.swift
**New Features:**
- Added optional `currentNetwork: NetworkConfig?` parameter
- Shows warning UI when payment request network doesn't match current network
- Displays orange warning icon and "Incompatible payment request" heading
- Shows specific network mismatch message (e.g., "This address is for Bitcoin Mainnet, but you're on Bitcoin Signet")
- Replaces "Use Payment Request" button with informative text when incompatible
- Maintains backward compatibility with `nil` network (shows all addresses as compatible)

**UI Behavior:**
- **Compatible addresses**: Normal banner with blue "Use Payment Request" button
- **Incompatible addresses**: Orange warning banner with explanatory text instead of button
- **Network-agnostic addresses** (Lightning, BIP-353): Always shown as compatible

### 2. SendView.swift
**Integration:**
- Updated `ClipboardAddressBanner` instantiation to pass `manager.currentNetworkConfig`
- Now respects the user's current network configuration when showing clipboard banners

## User Experience

### Before
- Incompatible addresses were silently ignored (no banner shown)
- User had no feedback about why clipboard content wasn't recognized
- Potential confusion when valid addresses didn't appear

### After
- Incompatible addresses are clearly shown with warning UI
- User understands the address is valid but for a different network
- "Use" button is hidden to prevent accidental cross-network sends
- User can still dismiss the banner or copy address details if needed

## Preview Examples

The updated preview demonstrates:

1. **Compatible scenarios** (no network filter):
   - Standard Bitcoin, Lightning, BIP-21, BIP-353 addresses
   - Multi-destination BIP-21 URIs
   - All show with normal UI and "Use" button

2. **Network mismatch scenarios**:
   - Mainnet address on Signet (incompatible)
   - Testnet address on Signet (incompatible)
   - Testnet address on Testnet (compatible)
   - Mixed-network BIP-21 URIs
   - Network-agnostic addresses on any network (compatible)

## Technical Details

### Compatibility Check
```swift
private var isCompatibleWithNetwork: Bool {
    guard let network = currentNetwork else { return true }
    return paymentRequest.isCompatible(with: network)
}
```

### Network Mismatch Detection
```swift
private var networkMismatchMessage: String? {
    guard let network = currentNetwork,
          !isCompatibleWithNetwork,
          let primaryNetwork = paymentRequest.primaryNetwork else {
        return nil
    }
    return "This address is for \(primaryNetwork.displayName), but you're on \(network.name)"
}
```

## Edge Cases Handled

1. **Lightning & BIP-353 addresses**: Network-agnostic, always compatible
2. **Mixed-network BIP-21 URIs**: Shows as incompatible based on primary destination
3. **No network context**: When `currentNetwork` is `nil`, all addresses are compatible
4. **Multiple alternatives**: All shown, but "Use" button disabled if primary is incompatible

## Future Enhancements

Potential improvements:
1. For mixed-network BIP-21 URIs, could filter to show only compatible alternatives
2. Add "Use anyway" override for advanced users (with additional confirmation)
3. Show compatible alternatives prominently when primary is incompatible
4. Add network switching suggestion ("Switch to Mainnet to use this address")

## Testing Recommendations

1. Test with clipboard containing mainnet address while on signet
2. Test with testnet address while on testnet (should work)
3. Test with Lightning/BIP-353 addresses on any network (should work)
4. Test mixed-network BIP-21 URIs
5. Verify backward compatibility when network context not available
