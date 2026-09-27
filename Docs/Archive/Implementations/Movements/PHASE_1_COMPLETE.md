# Phase 1 Complete: FFI Layer Enhancement for exitedVtxoIds

## ✅ Completed Tasks

### Task 1.1: Add exitedVtxoIds to FFI Serialization
**File:** `BarkWalletFFI.swift` (line ~2823)

**Changes made:**
- Added `"exited_vtxo_ids": movement.exitedVtxoIds` to the movement dictionary serialization
- Added diagnostic logging to detect and report movements with exited VTXOs

**Impact:**
- The application can now track when VTXOs are forced into unilateral exit
- Critical for Lightning payment tracking (expired HTLCs)
- Helps users understand when funds are being claimed onchain

---

### Task 1.2: Update MovementData Parsing
**File:** `TransactionService.swift` (lines 59-120)

**Changes made:**

1. **Updated property declaration:**
   ```swift
   let exitedVtxoIds: [String]  // Non-optional, empty array by default
   ```

2. **Updated CodingKeys:**
   ```swift
   case exitedVtxoIds = "exited_vtxo_ids"  // Correct snake_case key
   ```

3. **Added custom decoder for backward compatibility:**
   ```swift
   init(from decoder: Decoder) throws {
       // ... other fields ...
       
       // Handle exited_vtxo_ids with backward compatibility
       exitedVtxoIds = try container.decodeIfPresent([String].self, forKey: .exitedVtxoIds) ?? []
       
       // ... remaining fields ...
   }
   ```

4. **Added computed property:**
   ```swift
   var hasExitedVtxos: Bool {
       !exitedVtxoIds.isEmpty
   }
   ```

5. **Updated migration notes:**
   - Marked the exited VTXOs tracking as "NOW TRACKED"
   - Added timestamp to migration notes (January 2026)

---

## What This Enables

### For Lightning Payments
According to the movements documentation:

**bark.lightning_send:**
- HTLC VTXOs that cannot be swapped/revoked and are near expiry will be marked for exit
- These exited VTXOs indicate a payment that required fallback to onchain claim

**bark.lightning_receive:**
- If HTLC VTXOs cannot be swapped/revoked, are near expiry, and preimage was revealed, they'll be marked for exit
- These exited VTXOs indicate a receive that required fallback to onchain claim

### For Users
- **Transparency:** Users can see when payments required onchain fallback
- **Debugging:** Developers can track when Lightning payments fail to settle offchain
- **Status:** UI can show warnings/badges for transactions with exited VTXOs

---

## Testing Checklist

- [ ] Verify FFI compiles without errors
- [ ] Test with wallet data that has no exited VTXOs (should work as before)
- [ ] Test with Lightning payment that has exited VTXOs (if available)
- [ ] Verify logging output when movements with exited VTXOs are detected
- [ ] Test backward compatibility with old cached data (before this change)
- [ ] Verify `hasExitedVtxos` computed property returns correct boolean

---

## Example Log Output

When movements with exited VTXOs are detected, you'll see:

```
✅ Retrieved 42 movements
⚠️ Found 2 movement(s) with exited VTXOs:
   • Movement 123 (bark.lightning_send): 1 exited VTXO(s)
   • Movement 156 (bark.lightning_receive): 2 exited VTXO(s)
```

---

## Next Steps

Phase 1 is complete! The foundation is now in place to:

1. **Phase 2:** Create rich Swift models (PaymentMethod, MovementDestination, Metadata parsers)
2. **Phase 3:** Implement subsystem-aware transaction parsing
3. **Phase 4:** Store enhanced metadata in database
4. **Phase 5:** Display exited VTXO warnings in UI

The `exitedVtxoIds` field is now available throughout the application and can be used in:
- Transaction detail views (show warning badge)
- Transaction list filtering (filter by "has issues")
- Analytics/debugging (track failure rates)
- User notifications (alert when payment required onchain fallback)

---

## Code Quality

✅ **Backward compatible:** Old data without `exited_vtxo_ids` will decode with empty array  
✅ **Type safe:** Non-optional property with default empty array  
✅ **Well documented:** Comments explain purpose and usage  
✅ **Diagnostic friendly:** Logging helps identify when this field is populated  
✅ **Computed helper:** `hasExitedVtxos` provides convenient boolean check

---

**Estimated time spent:** ~15 minutes  
**Status:** ✅ Complete and ready for testing
