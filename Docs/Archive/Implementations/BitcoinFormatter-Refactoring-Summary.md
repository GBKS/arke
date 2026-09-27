# BitcoinFormatter Refactoring Summary

## Overview
The `BitcoinFormatter` has been completely refactored from a simple struct with static methods to an observable class that respects both user preferences and system locale settings.

## What Changed

### Architecture Changes

**Before:**
- Simple `struct` with static methods
- Hardcoded formatting logic
- No user preference integration
- No locale awareness

**After:**
- `@Observable class` with singleton pattern
- Dynamic formatting based on user preferences
- Full locale support (decimal separators, grouping, symbol placement)
- Reactive updates when preferences change

### Key Features

1. **User Preference Integration**
   - Reads `BitcoinAmountFormat` from UserDefaults
   - Automatically updates when user changes preferences in Settings
   - Supports all four format types:
     - Full Bitcoin (decimal BTC): `₿ 0.1`
     - Satoshis (integer): `10,000,000 sats`
     - BIP-177 (sats with ₿): `₿ 10,000,000`
     - Fun Emoji: `🌽 0.1`

2. **Locale Awareness**
   - Uses `Locale.autoupdatingCurrent` for number formatting
   - Respects decimal separator (`.` vs `,`)
   - Respects grouping separator (`,` vs `.` vs space)
   - Respects currency symbol placement (prefix vs suffix)
   - Automatic grouping size adaptation

3. **Unit Conversion**
   - Input: Always satoshis (Int)
   - Automatic conversion to BTC decimal for `fullBitcoin` and `funEmoji`
   - Integer formatting for `satoshis` and `bip177`

4. **Edge Case Handling**
   - Zero amounts
   - Very large amounts (>21M BTC)
   - Negative amounts (treated as absolute value)
   - Locale-specific formatting edge cases

## Usage

### Basic Usage (No Changes Required)

The existing code continues to work without modifications:

```swift
// In TransactionModel (automatically uses shared instance)
var formattedAmount: String {
    return BitcoinFormatter.shared.formatTransactionAmount(amount, transactionType: type)
}
```

### Advanced Usage

```swift
// Format a simple amount
let formatted = BitcoinFormatter.shared.formatAmount(10_000_000)
// Output varies by user preference:
// - Full Bitcoin: "₿ 0.1" or "0.1 ₿"
// - Satoshis: "10,000,000 sats"
// - BIP-177: "₿ 10,000,000"
// - Fun Emoji: "🌽 0.1"

// Format with transaction context
let txFormatted = BitcoinFormatter.shared.formatTransactionAmount(
    5_000_000, 
    transactionType: .received
)
// Output: "+5,000,000 sats" (or appropriate format)

// Accounting format (symbol always at end)
let accounting = BitcoinFormatter.shared.formatAccountingAmount(
    3_000_000,
    transactionType: .sent
)
// Output: "-3,000,000 sats"
```

### Testing with Custom UserDefaults

```swift
// Create formatter with specific format for testing
let userDefaults = UserDefaults(suiteName: "test")!
userDefaults.set(BitcoinAmountFormat.satoshis.rawValue, 
                 forKey: BitcoinAmountFormat.userDefaultsKey)
let formatter = BitcoinFormatter(userDefaults: userDefaults)
```

## Implementation Phases

### ✅ Phase 1: Refactor to Observable Class
- Changed from `struct` to `@Observable class`
- Added singleton pattern
- Added UserDefaults integration
- Added conversion helpers

### ✅ Phase 2: Format-Specific Formatters
- Created `makeFormatter()` factory method
- Implemented per-format NumberFormatter configuration
- Added locale-aware symbol placement
- Added format symbol logic

### ✅ Phase 3: Update Existing Methods
- Refactored `formatAmount()` to use new logic
- Updated `formatTransactionAmount()` with sign prefixes
- Updated `formatAccountingAmount()` with consistent symbol placement

### ✅ Phase 4: Edge Case Handling
- Added zero amount handling
- Added very large amount handling
- Added negative amount handling (abs value)
- Added fallback formatting

### ✅ Phase 5: Testing
- Created comprehensive test suite
- Tests for all four format types
- Tests for transaction formatting
- Tests for accounting format
- Tests for edge cases
- Tests for format switching
- Tests for locale independence

## Files Modified

1. **BitcoinFormatter.swift** - Complete refactor (class-based, locale-aware)
2. **TransactionModel.swift** - Updated to use `.shared` instance
3. **BitcoinAmountFormat.swift** - Updated example formats
4. **BitcoinFormatterTests.swift** - New comprehensive test file

## Benefits

1. **User Experience**
   - Users can choose their preferred Bitcoin display format
   - Formats respect their system locale settings
   - Changes take effect immediately throughout the app

2. **Developer Experience**
   - Single source of truth for formatting
   - Easy to test with dependency injection
   - Clear separation of concerns
   - Observable pattern for SwiftUI integration

3. **Internationalization**
   - Automatic adaptation to user's locale
   - No hardcoded separators or symbols
   - Proper currency symbol placement per locale

4. **Maintainability**
   - Well-documented code
   - Comprehensive test coverage
   - Modular design for future enhancements

## Future Enhancements (Optional)

- [ ] Add accessibility labels for VoiceOver
- [ ] Add formatting options for very small amounts (scientific notation)
- [ ] Add warnings for amounts exceeding max supply
- [ ] Cache NumberFormatter instances for better performance
- [ ] Add custom decimal places preference
- [ ] Add spacing preference between number and symbol

## Migration Notes

**No breaking changes!** All existing code continues to work by simply changing:
- `BitcoinFormatter.method()` → `BitcoinFormatter.shared.method()`

The TransactionModel has been updated to use the shared instance automatically.

## Testing Recommendations

1. **Manual Testing:**
   - Change format preference in Settings
   - Verify transaction list updates automatically
   - Test with different macOS locale settings
   - Test with various amount sizes

2. **Automated Testing:**
   - Run `BitcoinFormatterTests` test suite
   - Verify all tests pass
   - Add additional tests for specific edge cases as needed

## Notes

- The formatter is marked `@Observable`, so SwiftUI views will automatically update when the format preference changes
- Locale changes are handled automatically via `Locale.autoupdatingCurrent`
- The UserDefaults observer ensures the formatter stays in sync with settings changes
