# Transaction Fee Display Fix

## Problem
Onchain fees (like the 155 sats boarding fee) were not displaying in the transaction detail view because:

1. The `TransactionModel` didn't have an `onchainFeeSat` field, even though `PersistentTransaction` stored it
2. The UI only showed fees for `.sent` transactions, not `.transfer` transactions (which includes boarding)
3. The fee calculation only considered offchain fees, not onchain fees

## Solution

### 1. Updated `TransactionModel.swift`

Added `onchainFeeSat` field and comprehensive fee handling:

```swift
let fees: Int?  // Offchain transaction fees
let onchainFeeSat: Int?  // Bitcoin network fees (for onchain operations)
```

Added computed properties:
- `formattedOnchainFee: String?` - Formats onchain fee for display
- `totalFees: Int` - Sum of both fee types
- `formattedTotalFees: String?` - Formats total fees for display
- `hasBothFeeTypes: Bool` - Checks if transaction has both offchain and onchain fees

Updated all initializers to accept and pass through `onchainFeeSat`.

### 2. Updated `TransactionDetailView_iOS.swift`

Changed fee display logic:
- Now shows fees for both `.sent` and `.transfer` transactions
- If only one fee type exists, shows single "Fee" row with total
- If both fee types exist, shows separate rows:
  - "Offchain Fee" 
  - "Onchain Fee"
  - "Total Fee"

### 3. Updated `TransactionDetailView.swift` (macOS)

Added the same fee display logic (previously had no fee display at all!).

### 4. Added Preview Cases

Added two new preview cases to visualize the changes:
- "Boarding Transaction with Onchain Fee" - Shows a boarding operation with 155 sat onchain fee
- "Transaction with Both Fee Types" - Shows a transaction with both offchain and onchain fees

## Result

Now when viewing a boarding transaction (or any transaction with onchain fees), the fees will display correctly:

**Before:** No fee shown (0 sats displayed)
**After:** "Fee: 155 sats" displayed

For transactions with both fee types (e.g., Lightning send that also has onchain settlement):
- Offchain Fee: 500 sats
- Onchain Fee: 300 sats  
- Total Fee: 800 sats

## Data Flow

The `onchainFeeSat` is extracted from the movement's `metadata_json`:
1. `MovementMetadataParser` parses JSON → `BoardMetadata.onchainFeeSat`
2. `TransactionService.createTransactionData()` copies to `TransactionData.onchainFeeSat`
3. Stored in `PersistentTransaction.onchainFeeSat`
4. Loaded into `TransactionModel.onchainFeeSat`
5. Displayed via `formattedTotalFees` in UI

## Testing

Run the preview "Boarding Transaction with Onchain Fee" to verify the fee displays correctly at 155 sats.
