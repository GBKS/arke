# Bitcoin Formatter Locale Integration Guide

## Overview

The `BitcoinFormatter` respects macOS system locale settings for number formatting. This means that the same Bitcoin amount will be displayed differently depending on the user's region and language preferences.

## Locale-Aware Features

### 1. Decimal Separator

The decimal separator varies by locale:

| Locale | Example (0.1 BTC) |
|--------|-------------------|
| US (en_US) | ₿ 0.1 |
| Germany (de_DE) | ₿ 0,1 |
| France (fr_FR) | ₿ 0,1 |

**In BitcoinFormatter:**
```swift
formatter.locale = .autoupdatingCurrent
formatter.numberStyle = .decimal
```

The formatter automatically uses the correct decimal separator for the current locale.

### 2. Grouping Separator (Thousands)

Different locales use different grouping separators:

| Locale | Example (1,000,000 sats) |
|--------|--------------------------|
| US (en_US) | 1,000,000 sats |
| Germany (de_DE) | 1.000.000 sats |
| France (fr_FR) | 1 000 000 sats |
| Switzerland (de_CH) | 1'000'000 sats |

**In BitcoinFormatter:**
```swift
formatter.usesGroupingSeparator = true
```

This automatically uses the appropriate grouping separator and size for the locale.

### 3. Currency Symbol Placement

Currency symbols are placed differently in different regions:

| Locale | Example (1 BTC) |
|--------|-----------------|
| US (en_US) | ₿1 |
| UK (en_GB) | ₿1 |
| Germany (de_DE) | 1 ₿ |
| France (fr_FR) | 1 ₿ |

**In BitcoinFormatter:**
```swift
private func symbolPlacement(for locale: Locale = .autoupdatingCurrent) -> SymbolPlacement {
    let testFormatter = NumberFormatter()
    testFormatter.locale = locale
    testFormatter.numberStyle = .currency
    testFormatter.currencySymbol = "¤"
    
    let formatted = testFormatter.string(from: 1) ?? "¤1"
    
    if formatted.hasPrefix("¤") {
        return .prefix
    } else {
        return .suffix
    }
}
```

This automatically detects the locale's currency placement convention.

### 4. Special Case: Satoshis

For the "satoshis" format, the "sats" suffix is always placed after the number, regardless of locale conventions, as this is the community standard:

```
✅ Correct: 1,000,000 sats (all locales)
❌ Incorrect: sats 1,000,000
```

## Format-Specific Locale Behavior

### Full Bitcoin (Decimal)

| Locale | 0.10000000 BTC |
|--------|----------------|
| US | ₿ 0.1 |
| Germany | ₿ 0,1 |
| France | ₿ 0,1 |

- Up to 8 decimal places
- Grouping separator for integer part (if needed)
- Locale-specific decimal separator
- Symbol placement per locale

### Satoshis (Integer)

| Locale | 10,000,000 sats |
|--------|-----------------|
| US | 10,000,000 sats |
| Germany | 10.000.000 sats |
| France | 10 000 000 sats |

- No decimal places
- Grouping separator per locale
- "sats" suffix (always at end)

### BIP-177 (Satoshis with ₿)

| Locale | 10,000,000 satoshis |
|--------|---------------------|
| US | ₿ 10,000,000 |
| Germany | 10.000.000 ₿ |
| France | 10 000 000 ₿ |

- No decimal places
- Grouping separator per locale
- Bitcoin symbol (₿) placement per locale

### Fun Emoji

| Locale | 0.10000000 BTC |
|--------|----------------|
| US | 🌽 0.1 |
| Germany | 🌽 0,1 |
| France | 🌽 0,1 |

- Same as Full Bitcoin but with corn emoji
- Emoji always placed at start (looks better visually)

## How to Test Locale Behavior

### Testing on macOS

1. **Change System Locale:**
   - Open System Settings
   - Go to General → Language & Region
   - Add a new preferred language or change the region
   
2. **Test Format Variations:**
   - Run your app
   - Check how amounts are displayed
   - Try different format preferences in Settings

3. **Common Test Locales:**
   - `en_US` - Period decimal, comma grouping
   - `de_DE` - Comma decimal, period grouping
   - `fr_FR` - Comma decimal, space grouping
   - `en_GB` - Period decimal, comma grouping
   - `ja_JP` - Period decimal, comma grouping

### Programmatic Testing

```swift
// Test with specific locale
let usLocale = Locale(identifier: "en_US")
let deLocale = Locale(identifier: "de_DE")

// The formatter will automatically use Locale.autoupdatingCurrent
// To test specific locales, you would need to temporarily change
// the system locale or create a test variant of the formatter
```

## Implementation Details

### Locale Usage in BitcoinFormatter

```swift
// In makeFormatter()
let formatter = NumberFormatter()
formatter.locale = .autoupdatingCurrent  // ← Key line for locale support

// This means:
// 1. Always uses current system locale
// 2. Automatically updates if user changes locale
// 3. No caching issues with locale changes
```

### Why `.autoupdatingCurrent`?

- **Static Locale**: `Locale.current` - Captures locale at time of access
- **Auto-updating**: `Locale.autoupdatingCurrent` - Always uses current locale

We use `.autoupdatingCurrent` because:
1. User might change locale while app is running
2. No need to recreate formatters on locale change
3. Always shows correct formatting for current system settings

## Edge Cases and Considerations

### 1. Right-to-Left Languages

Currently not specifically handled, but NumberFormatter will respect RTL layout. Bitcoin symbols should remain in logical order.

### 2. Locales with Different Grouping Sizes

Some locales group digits differently (e.g., Indian numbering: 1,00,000). NumberFormatter handles this automatically:

```swift
formatter.usesGroupingSeparator = true
// Automatically uses locale's grouping size and separator
```

### 3. Very Large Numbers

For amounts > 21M BTC (beyond max supply), formatting still works correctly with locale-specific separators:

| Locale | 21,000,000 BTC |
|--------|----------------|
| US | ₿ 21,000,000 |
| Germany | 21.000.000 ₿ |
| France | 21 000 000 ₿ |

### 4. Very Small Amounts (1 satoshi)

In decimal Bitcoin format:

| Locale | 0.00000001 BTC |
|--------|----------------|
| US | ₿ 0.00000001 |
| Germany | ₿ 0,00000001 |

## Best Practices

### ✅ Do:
- Use the shared formatter: `BitcoinFormatter.shared`
- Trust the formatter to handle locale
- Test with multiple locales during development
- Let users choose their preferred Bitcoin format

### ❌ Don't:
- Hardcode separators (`,` or `.`)
- Force specific locale formatting
- Override system locale preferences
- Assume US-style formatting

## Real-World Examples

### Transaction List (US Locale)

```
+₿ 0.5         Received
-1,234,567 sats   Sent
+₿ 10,000,000     Received
```

### Transaction List (German Locale)

```
+0,5 ₿         Received
-1.234.567 sats   Sent
+10.000.000 ₿     Received
```

### Balance Display (French Locale)

```
Total: 21 000 000 sats
      (or 0,21 ₿ depending on format preference)
```

## Summary

The `BitcoinFormatter` provides complete locale integration:

1. **Automatic** - No manual locale handling required
2. **Standard** - Uses Apple's NumberFormatter best practices  
3. **Flexible** - Works with any macOS supported locale
4. **User-friendly** - Shows amounts in familiar format for user's region
5. **Consistent** - Same behavior across the app

This ensures your Bitcoin wallet feels native to users worldwide while respecting Bitcoin community conventions (like "sats" suffix placement).
