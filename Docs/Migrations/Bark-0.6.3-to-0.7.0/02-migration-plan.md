# Bark API Migration Implementation Plan

**Migration:** Bark v0.2.1 → v0.2.2, Bark FFI Bindings v0.6.3 → v0.7.0

This document outlines the step-by-step plan for migrating the Arke codebase to use the new Bark Swift bindings API, specifically the Lightning send operations that now use `LightningSendStatus` enum instead of returning `LightningSend` directly.

## Overview

The new Bark API introduces a typed status enum (`LightningSendStatus`) that replaces bare `String?` and `LightningSend` returns for all Lightning send operations. This provides better type safety and clearer payment status handling.

**Key Changes:**
- `LightningSend.preimage` field removed → moved to `LightningSendStatus.paid(paymentHash:preimage:)`
- `LightningSend` gains new `feeSats: UInt64` field
- All `pay*` methods gain `wait: Bool` parameter and return `LightningSendStatus`
- `checkLightningPayment` returns `LightningSendStatus` instead of `String?`
- Two new optional methods: `isInvoicePaid()` and `lightningSendState()`

---

## Migration Steps

### Phase 1: Protocol Layer Updates

**Files to update:**
- `Shared/Data/BarkWalletProtocol.swift`

**Tasks:**

1. **Update method signatures (lines 152, 160-162)**
   ```swift
   // Add wait parameter and change return type
   func payLightningInvoice(invoice: String, amountSats: UInt64?, wait: Bool) async throws -> LightningSendStatus
   func payLightningOffer(offer: String, amountSats: UInt64?, wait: Bool) async throws -> LightningSendStatus
   func payLightningAddress(lightningAddress: String, amountSats: UInt64, comment: String?, wait: Bool) async throws -> LightningSendStatus
   ```

2. **Update checkLightningPayment return type (line 162)**
   ```swift
   func checkLightningPayment(paymentHash: String, wait: Bool) async throws -> LightningSendStatus
   ```

3. **Add new optional methods (after line 162)**
   ```swift
   func isInvoicePaid(paymentHash: String) async throws -> Bool
   func lightningSendState(paymentHash: String) async throws -> LightningSendStatus
   ```

**Validation:** Build will fail until all conforming types are updated (expected).

---

### Phase 2: FFI Implementation Layer

**Files to update:**
- `Shared/Data/BarkWalletFFI/BarkWalletFFI+Lightning.swift`

**Tasks:**

1. **Update `payLightningInvoice` (lines 19-81)**
   - Add `wait: Bool` parameter to method signature
   - Change return type from `LightningSend` to `LightningSendStatus`
   - Update FFI call to pass `wait` parameter
   - Remove `.preimage` access at lines 55-58
   - Pattern match on returned `LightningSendStatus` to extract payment hash for polling
   - Update logging to handle status cases
   - Update preview mode mock return

2. **Update `payLightningOffer` (lines 264-299)**
   - Add `wait: Bool` parameter to method signature
   - Change return type to `LightningSendStatus`
   - Update FFI call to pass `wait` parameter
   - Update preview mode mock return
   - Update logging

3. **Update `payLightningAddress` (lines 301-340)**
   - Add `wait: Bool` parameter to method signature
   - Change return type to `LightningSendStatus`
   - Update FFI call to pass `wait` parameter
   - Update preview mode mock return
   - Update logging

4. **Update `checkLightningPayment` (lines 382-402)**
   - Change return type from `String?` to `LightningSendStatus`
   - Update preview mode mock return
   - Return status directly from FFI (no transformation needed)
   - Update logging

5. **Update `pollLightningPaymentStatus` (lines 349-378)**
   - Update to work with `LightningSendStatus` instead of `String?`
   - Pattern match on status to check for `.paid` case
   - Extract preimage from `.paid(paymentHash, preimage)` case
   - Update logging

6. **Add new methods (if FFI supports them)**
   ```swift
   func isInvoicePaid(paymentHash: String) async throws -> Bool
   func lightningSendState(paymentHash: String) async throws -> LightningSendStatus
   ```

**Validation:** 
- Ensure preview mode still works
- Check that payment hash extraction logic works with new status type
- Verify logging statements compile

---

### Phase 3: Mock Implementation Layer

**Files to update:**
- `Shared/Data/MockBarkWallet.swift`

**Tasks:**

1. **Update `payLightningInvoice` (around line 649)**
   - Add `wait: Bool` parameter
   - Change return type to `LightningSendStatus`
   - Return mock status: `.inProgress(send: LightningSend(...))`
   - Remove `preimage: nil` from LightningSend (field no longer exists)
   - Add `feeSats: 50` to LightningSend (new required field)

2. **Update `payLightningOffer` (around line 649)**
   - Add `wait: Bool` parameter
   - Change return type to `LightningSendStatus`
   - Return mock status with new LightningSend structure

3. **Update `payLightningAddress` (around line 661)**
   - Add `wait: Bool` parameter
   - Change return type to `LightningSendStatus`
   - Return mock status with new LightningSend structure

4. **Update `checkLightningPayment` (around line 676)**
   - Change return type to `LightningSendStatus`
   - Return mock status: `.unknown` or `.inProgress(...)`

5. **Add new methods**
   ```swift
   func isInvoicePaid(paymentHash: String) async throws -> Bool {
       return false  // Mock implementation
   }
   
   func lightningSendState(paymentHash: String) async throws -> LightningSendStatus {
       return .unknown  // Mock implementation
   }
   ```

**Validation:** Preview mode and unit tests should work with mock wallet.

---

### Phase 4: Service Layer Updates

**Files to update:**
- `Shared/Data/WalletManager/WalletManager+Lightning.swift`
- `Shared/Services/WalletOperationsService.swift`

**Tasks:**

1. **Update WalletManager+Lightning.swift (lines 27-48)**
   - `payLightningInvoice`: Update return type to `LightningSendStatus`
   - `payLightningAddress`: Update return type to `LightningSendStatus`, change `_ =` to `return`
   - `payLightningOffer`: Update return type to `LightningSendStatus`, change `_ =` to `return`
   - All methods: Pass `wait: true` to wallet calls (blocking behavior for better UX)

2. **Update WalletOperationsService.swift (lines 163-169)**
   - `payLightningInvoice`: Update return type to `LightningSendStatus`
   - Update task manager key if needed
   - Update logging to reflect new status type

**Validation:** Service layer compiles and type-checks correctly.

---

### Phase 5: UI/ViewModel Layer Updates

**Files to update:**
- `Shared/Views/Send/SendViewModel/SendViewModel+PaymentExecution.swift`

**Tasks:**

1. **Update Lightning invoice payment (lines 141, 189-196)**
   - Add `wait: true` parameter to `payLightningInvoice` calls
   - Handle `LightningSendStatus` return value
   - Pattern match to check payment status:
     ```swift
     let status = try await walletManager.payLightningInvoice(invoice: ..., amountSats: ..., wait: true)
     switch status {
     case .paid(let paymentHash, let preimage):
         // Payment confirmed - success!
     case .inProgress(let send):
         // Payment in flight - could show fee: send.feeSats
     case .unknown:
         // Payment not found - error?
     }
     ```
   - For now, treat `.paid` as success, `.inProgress` as success (will settle), `.unknown` as potential error
   - Consider logging payment status for debugging

2. **Update Lightning address payment (lines 201-205)**
   - Add `wait: true` parameter
   - Handle `LightningSendStatus` return (same pattern as above)
   - Update to capture return value instead of discarding with `_`

3. **Update LNURL invoice payment (lines 246-249)**
   - Add `wait: true` parameter
   - Handle `LightningSendStatus` return

4. **Update BOLT12 offer payment (line 255)**
   - Add `wait: true` parameter
   - Handle `LightningSendStatus` return

**Design Decision:** For v1 migration, use `wait: true` for simplicity. This blocks until payment settles or fails, providing clear success/failure feedback. Future enhancement: use `wait: false` with status polling for better UX during long payments.

**Validation:** 
- Test send flow with Lightning invoices (with/without amounts)
- Test Lightning address payments
- Test LNURL payments
- Test BOLT12 offer payments

---

### Phase 6: Testing & Edge Cases

**Files to check:**
- `Arke/ArkeMobile/Views/Settings/Testing/IncrementalPaymentTestView_iOS.swift`
- Any other test files that use Lightning payment methods

**Tasks:**

1. **Update test views/utilities**
   - Search for direct calls to `payLightningInvoice`, etc.
   - Update to handle new signatures and return types
   - Add `wait` parameter as appropriate for test scenarios

2. **Test edge cases**
   - Lightning invoice with embedded amount
   - Lightning invoice with zero amount (user-specified)
   - Lightning address payments
   - LNURL-pay flows
   - BOLT12 offers
   - Failed payments (insufficient balance, routing failures)
   - Payment status polling

3. **Verify preimage handling**
   - Ensure no code tries to access `LightningSend.preimage` directly
   - All preimage access goes through `LightningSendStatus.paid` case
   - Update any logging/debugging code that displayed preimages

**Validation:** All test scenarios pass with new API.

---

### Phase 7: Build & Final Validation

**Tasks:**

1. **Clean build**
   - Clean Xcode build folder
   - Build all targets (iOS, macOS)
   - Verify no compiler errors or warnings related to API changes

2. **Runtime testing**
   - Test Lightning send flows in simulator/device
   - Test Lightning receive flows (should be unaffected)
   - Verify balance updates correctly after payments
   - Check transaction history displays correctly
   - Test error handling and user feedback

3. **Review logging**
   - Check that logging statements are informative
   - Verify payment hashes, amounts, and statuses are logged
   - Ensure no sensitive data (full preimages) in production logs

**Validation:** All functionality works as expected with new API.

---

## Decision Log

### 1. Wait Parameter Strategy
**Decision:** Use `wait: true` for all Lightning payments in v1 migration
**Rationale:** 
- Simplifies migration - no need to build status polling UI yet
- Provides clear success/failure feedback
- Matches existing UX expectations (blocking payment operations)
- Can optimize later with `wait: false` + polling for better UX

### 2. Status Handling Strategy
**Decision:** Treat both `.paid` and `.inProgress` as success cases initially
**Rationale:**
- `.paid` = confirmed success with preimage
- `.inProgress` = payment locked, will settle (99% success rate)
- `.unknown` = payment not found or pruned (error case)
- Simplifies v1 migration while maintaining correct behavior

### 3. New Methods
**Decision:** Implement `isInvoicePaid` and `lightningSendState` as optional additions
**Rationale:**
- Not required for migration
- Useful for future features (payment status checking UI)
- Low implementation cost
- Improves API completeness

### 4. Fee Display
**Decision:** Don't surface `LightningSend.feeSats` in UI for v1
**Rationale:**
- Requires UI changes to fee estimation/display flow
- Out of scope for API migration
- Can be added in future enhancement
- Value is available for future use

---

## Rollback Plan

If critical issues are discovered during migration:

1. **Keep old Bark library version pinned** until migration is complete
2. **Use feature flags** if deploying incrementally (not applicable for library changes)
3. **Git branches**: Perform migration in feature branch, merge only when fully tested
4. **Fallback**: Can revert to old Bark library version if showstopper bugs found

---

## Success Criteria

Migration is complete when:

- ✅ All compiler errors resolved
- ✅ All 4 protocol methods updated with correct signatures
- ✅ All implementations (FFI, Mock) conform to new protocol
- ✅ All call sites updated to handle new return types
- ✅ No references to `LightningSend.preimage` remain
- ✅ All Lightning payment flows work correctly in testing
- ✅ Build succeeds for both iOS and macOS targets
- ✅ Preview mode works correctly
- ✅ Unit tests pass (if applicable)

---

## Notes

- **No changes needed** to Lightning receive operations (`LightningReceive`, claiming, etc.)
- **No changes needed** to balance, VTXO, exit, or onchain operations
- **No changes needed** to fee estimation methods
- The new `feeSats` field in `LightningSend` is available but not required for v1 migration
- Consider adding payment status tracking in future for better UX (show payment progress)

---

## Timeline Estimate

- Phase 1 (Protocol): 15 minutes
- Phase 2 (FFI): 45 minutes  
- Phase 3 (Mock): 20 minutes
- Phase 4 (Services): 15 minutes
- Phase 5 (UI/ViewModels): 30 minutes
- Phase 6 (Testing): 30 minutes
- Phase 7 (Validation): 30 minutes

**Total: ~3 hours** (assuming no major issues)

---

## References

- `Docs/bark-api-changes.md` - Complete API diff documentation
- Bark library source code - For LightningSendStatus enum definition and behavior
