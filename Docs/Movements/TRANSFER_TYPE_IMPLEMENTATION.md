# Transfer Transaction Type Implementation

## Summary

Added a new `.transfer` transaction type to properly represent self-transfer operations like boarding (onchain → Ark), exit (Ark → onchain), and offboarding. This provides clearer semantics and better user experience for operations where the user is moving funds between their own accounts.

## Changes Made

### 1. **TransactionTypeEnum.swift**
- Added new `.transfer` case to the enum
- Set icon to `"arrow.left.arrow.right"` to represent bidirectional movement
- Set color to `.blue` for neutral representation (neither incoming green nor outgoing primary)
- Display name: "Transfer"

### 2. **TransactionService.swift**

#### Updated `parseMovementWithCategory()`
- Added routing logic to detect self-transfer operations (boarding, exit, offboarding)
- Routes these operations to new `parseTransferOperation()` method
- Removed offboarding from send operations list

#### Added `parseTransferOperation()`
- New method specifically for handling self-transfer operations
- Sets transaction type to `.transfer`
- Handles destination addresses (nil for boarding, present for exit/offboarding)

#### Updated `stringValue(for:)` helper
- Added case for `.transfer` → `"transfer"`

### 3. **PersistentTransaction.swift**

#### Updated enum conversion methods
- `stringValue(for:)`: Added `.transfer` → `"transfer"`
- `transactionType(from:)`: Added `"transfer"` → `.transfer`

### 4. **TransactionModel.swift**

#### Added `category` field
- New optional `MovementCategory?` property
- Passed through from `PersistentTransaction.category`
- Enables category-aware display logic

#### Updated initializers
- Added `category` parameter to init
- Added `category` field in `init(from:)` for PersistentTransaction conversion

### 5. **TransactionListItem.swift**

#### Enhanced `transactionDisplayText` property
- Now checks `transaction.category` first before falling back to type/contact logic
- Category-specific display text:
  - `.boarding`: "Boarding to Ark"
  - `.exit`: "Exit to Onchain"  
  - `.offboarding`: "Offboarding to Onchain"
  - `.refresh`: "VTXO Refresh"
  - `.lightningSend`: "Lightning Payment" or "Lightning to [Contact]"
  - `.lightningReceive`: "Lightning Received" or "Lightning from [Contact]"
  - `.onchainSend`: "Onchain Payment" or "Onchain to [Contact]"
- Added `.transfer` case to contact-based display logic

### 6. **BitcoinFormatter.swift**

#### Updated `formatTransactionAmount()`
- Added special handling for `.transfer` type
- Transfers show amount without +/- prefix (neutral self-transfer)
- Received: `+amount`
- Sent: `-amount`
- Transfer: `amount` (no prefix)

#### Updated `formatAccountingAmount()`
- Added `.transfer` case
- Returns amount without sign prefix for transfers

## Behavior Changes

### Before
- Boarding: Displayed as "Received" with "Pending" badge → confusing
- Exit/Offboarding: Displayed as "Sent" → unclear that it's a self-transfer
- Amount formatting: Always showed +/- based on balance direction

### After
- Boarding: Displays as "Boarding to Ark" with "Pending" badge (if pending) → clear intent
- Exit: Displays as "Exit to Onchain" → clear it's moving your own funds
- Offboarding: Displays as "Offboarding to Onchain" → clear it's moving your own funds
- Transfer amounts: Show without +/- prefix (neutral)
- Status badge: Still shows when transaction is pending/failed → user knows funds are in-flight

## Category-Aware Display

The new system leverages the rich `MovementCategory` metadata:

| Category | Display Text | Icon | Color |
|----------|-------------|------|-------|
| boarding | "Boarding to Ark" | arrow.left.arrow.right | blue |
| exit | "Exit to Onchain" | arrow.left.arrow.right | blue |
| offboarding | "Offboarding to Onchain" | arrow.left.arrow.right | blue |
| refresh | "VTXO Refresh" | arrow.left.arrow.right | blue |
| lightningSend | "Lightning Payment" | bolt.fill | yellow |
| lightningReceive | "Lightning Received" | bolt.fill | yellow |
| onchainSend | "Onchain Payment" | link | blue |
| offchainTransfer | Uses contact logic | arrow.up/down | green/primary |

## Example: Boarding Movement

**Movement Data:**
```json
{
  "subsystem_name": "bark.board",
  "subsystem_kind": "board",
  "status": "pending",
  "effective_balance_sats": 50000
}
```

**Before:**
- Type: `.received`
- Display: "Received"
- Badge: "Pending" (orange)
- Amount: "+50,000 sats"

**After:**
- Type: `.transfer`
- Display: "Boarding to Ark"
- Badge: "Pending" (orange)
- Amount: "50,000 sats"

## User Benefits

1. **Clarity**: "Boarding to Ark" is much clearer than "Received (Pending)"
2. **Visibility**: Transfer operations remain visible (important for fee tracking and locked funds)
3. **Consistency**: All self-transfers use the same type and visual treatment
4. **Context**: Category-aware display provides operation-specific text
5. **Status awareness**: Pending badge still shows for in-flight transfers

## Testing Recommendations

- Test boarding with pending status
- Test exit operations
- Test offboarding operations
- Verify status badges still appear correctly
- Verify amount formatting (no +/- prefix)
- Verify icon and color display
- Test with and without contacts assigned
- Test with notes (should still take priority)

## Migration Notes

- Existing transactions with old types will continue to work
- New transactions from movements will use the `.transfer` type automatically
- SwiftData will handle the string storage conversion
- No data migration required (categories are already stored)
