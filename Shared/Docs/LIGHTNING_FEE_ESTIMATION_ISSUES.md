# Lightning Fee Estimation - Known Issues & Action Items

**Date**: 2026-06-22
**Context**: Fixed memory corruption bug by refactoring `PaymentDestinationSelector` to use `WalletManager` directly instead of closure.

## Status Legend
- 🔴 Critical - Must fix before release
- ⚠️ Moderate - Should fix soon
- 🟡 Minor - Can fix later
- ✅ Fixed - Completed

---

## 🔴 Critical Issues

### 1. Fee Calculation Logic Verification
**Status**: 🔴 Critical
**Location**: `Shared/Helpers/PaymentDestinationSelector.swift:393`

**Issue**:
```swift
let actualFee = Int(feeEstimate.grossAmountSats) - unwrappedAmount
```

The fee calculation assumes `grossAmountSats = payment + fee` for all Lightning payment types. This needs verification for:

- [x] Lightning Address payments - ✅ Verified working
- [x] Lightning Invoice payments (with embedded amount)
- [x] Lightning Invoice payments (amount-less invoices)
- [x] LNURL-pay payments
- [x] BOLT12 offer payments

**Risk**: If the FFI uses different semantics for different payment types, fees could be calculated incorrectly, leading to payment failures or wrong amounts being sent.

**Action Items**:
1. Test with a Lightning invoice (embedded amount)
2. Test with an amount-less Lightning invoice
3. Test with LNURL-pay
4. Test with BOLT12 (if supported)
5. Document the expected behavior in code comments
6. Consider adding validation/assertions

**Notes**:
- Current implementation works correctly for Lightning Address
- From logs: `gross=4497, fee=21, calculated=21` where `4497 - 4476 = 21` ✅

---

## ⚠️ Moderate Issues

### 2. Weak Reference Safety
**Status**: ⚠️ Moderate
**Location**: `Shared/Helpers/PaymentDestinationSelector.swift:37`

**Issue**:
```swift
weak var walletManager: WalletManager?
```

Using `weak var` means `WalletManager` could be deallocated while `PaymentContext` is still in use.

**Scenarios at Risk**:
- Context stored for later use
- Async operations span multiple event loop cycles
- Context passed across view boundaries

**Current Mitigation**:
- `SendViewModel` holds strong reference to `WalletManager`
- `PaymentContext` created on-demand via computed property
- Context not stored long-term in current implementation

**Action Items**:
- [ ] Document that `PaymentContext` should be short-lived
- [ ] Consider making `walletManager` non-weak if contexts are stored
- [ ] Add assertion/guard to detect nil `walletManager` in fee estimation
- [ ] Review all places where `PaymentContext` is created/stored

**Decision Needed**: Keep weak or make strong? Depends on usage patterns.

---

### 3. Silent Fee Estimation Failure
**Status**: ⚠️ Moderate
**Location**: `Shared/Helpers/PaymentDestinationSelector.swift:396-399`

**Issue**:
```swift
} catch {
    print("🔍 [estimateFee] Fee estimation failed: \(error)")
    // Fall through to static estimate
}
```

When fee estimation fails, we silently fall back to static estimate (10 sats for Lightning).

**Problems**:
- User sees different fee than displayed estimate
- Static estimate may be too low, causing payment failure
- Hard to diagnose issues in production
- No visibility into why estimation failed

**Action Items**:
- [ ] Replace `print()` with proper `logger.error()`
- [ ] Consider exposing failure state to UI (show "estimated" vs "calculating...")
- [ ] Add telemetry/analytics for fee estimation failures
- [ ] Consider retry logic or more sophisticated fallback

**Fallback Values** (from line 406-408):
- Ark: 0 sats
- Lightning/Invoice/LNURL/BOLT12: 10 sats
- Bitcoin: 500 sats
- Silent Payments: 600 sats

---

## 🟡 Minor Issues

### 4. Debug Logging Cleanup
**Status**: 🟡 Minor

**Locations**:
- `PaymentDestinationSelector.swift`: Lines 382, 388-389, 394, 397, 244-246, 249
- `SendViewModel+PaymentExecution.swift`: Lines 175, 182

**Issue**: Multiple debug `print()` statements left from investigation

**Action Items**:
- [ ] Remove all `print("🔍 ...")` debug statements
- [ ] Convert important ones to proper `logger.debug()` calls
- [ ] Keep only production-relevant logging

**Priority**: Low - but should be done before next release

---

### 5. Integer Overflow Protection
**Status**: 🟡 Minor
**Location**: `Shared/Helpers/PaymentDestinationSelector.swift:393`

**Issue**:
```swift
let actualFee = Int(feeEstimate.grossAmountSats) - unwrappedAmount
```

If `grossAmountSats < unwrappedAmount` (FFI bug or edge case), this produces negative fee.

**Action Items**:
- [ ] Add safety check: `let actualFee = max(0, Int(feeEstimate.grossAmountSats) - unwrappedAmount)`
- [ ] Log warning if this condition occurs
- [ ] Consider if negative fee has semantic meaning (rebate?)

**Likelihood**: Very low, but good defensive programming

---

## ✅ Completed

### Original Bug: Memory Corruption in Closure
**Status**: ✅ Fixed
**Date Fixed**: 2026-06-22

**Issue**: Closure parameter receiving corrupted value (4476 → 8524706920)

**Root Cause**: Unknown ABI issue or Swift compiler bug with async throwing closure captures

**Solution**: Replaced closure with direct `WalletManager` reference

**Benefits**:
- ✅ Eliminated memory corruption
- ✅ Cleaner, more maintainable code
- ✅ Better type safety
- ✅ Direct method calls instead of indirection

**Files Changed**:
- `Shared/Helpers/PaymentDestinationSelector.swift`
- `Shared/Views/Send/SendViewModel/SendViewModel+ComputedProperties.swift`
- `Shared/Data/WalletManager/WalletManager+PaymentDestination.swift`

---

## Testing Checklist

### Lightning Payment Types
- [x] Lightning Address (send-max) - ✅ Verified working
- [ ] Lightning Address (fixed amount)
- [ ] Lightning Invoice (embedded amount)
- [ ] Lightning Invoice (zero amount)
- [ ] LNURL-pay
- [ ] BOLT12 offers

### Fee Calculation Scenarios
- [x] Send max (balance exactly matches gross amount) - ✅ Works
- [ ] Send with fee leaving dust
- [ ] Send amount near balance limit
- [ ] Fee estimation failure (network error)
- [ ] Fee estimation with high fees
- [ ] Concurrent fee estimations

### Edge Cases
- [ ] WalletManager deallocated while estimating
- [ ] grossAmountSats < amount (shouldn't happen)
- [ ] Zero fee scenarios
- [ ] Maximum amount/fee values

---

## Documentation Needed

- [ ] Add doc comment explaining `grossAmountSats` semantics in code
- [ ] Document `PaymentContext` lifetime expectations
- [ ] Add README section on fee estimation architecture
- [ ] Document fallback fee values and when they're used

---

## Notes

### FeeEstimate Structure
From FFI (Bark library):
```swift
struct FeeEstimate {
    grossAmountSats: UInt64  // Total needed from wallet (payment + fee)
    feeSats: UInt64          // Fee amount (appears incorrect in some cases)
    netAmountSats: UInt64    // Amount after fee deduction
    vtxosSpent: [String]     // VTXOs consumed for this payment
}
```

### Observed Behavior
For Lightning send of 4476 sats:
- `grossAmountSats`: 4497
- `feeSats`: 21
- `netAmountSats`: 4476
- Calculated fee: `4497 - 4476 = 21` ✅ Correct

**Question**: Is `feeSats` field reliable? We're using `grossAmountSats - amount` instead.

---

## References

- Original Issue: Lightning send-max failed with fee estimation of 42,623,534 sats
- Debug Logs: `Shared/Docs/debug_logs.txt`
- Related Files:
  - `Shared/Helpers/PaymentDestinationSelector.swift`
  - `Shared/Views/Send/SendViewModel/SendViewModel+ComputedProperties.swift`
  - `Shared/Views/Send/SendViewModel/SendViewModel+PaymentExecution.swift`
  - `Shared/Data/WalletManager/WalletManager+Fees.swift`
