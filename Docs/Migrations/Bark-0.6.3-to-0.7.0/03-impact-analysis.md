# Bark API Migration: Holistic Impact Analysis

**Migration:** Bark v0.2.1 → v0.2.2, Bark FFI Bindings v0.6.3 → v0.7.0

This document provides a comprehensive analysis of how the Lightning send API changes affect the entire user experience, transaction flows, and UI states throughout the Arke application.

## Executive Summary

**Good News:** The API changes have **minimal impact** on user experience and transaction visibility. The changes are mostly internal to how we handle payment returns, not how transactions appear in the UI.

**Key Finding:** Transactions are created by the Bark SDK via `Movement` events, which are **independent** of the `LightningSendStatus` return type. Whether a payment returns `.paid`, `.inProgress`, or is polled later, the transaction always appears in the activity list through the notification stream.

---

## 1. Transaction Flow Architecture

### Current Flow (How Transactions Appear)

```
User initiates payment
    ↓
payLightningInvoice/Offer/Address(wait: true)  ← New API: returns LightningSendStatus
    ↓
Bark SDK locks VTXOs and processes payment
    ↓
SDK emits Movement event via notification stream
    ↓
WalletNotificationService receives Movement
    ↓
TransactionService.processMovement() converts to TransactionModel
    ↓
SwiftData persists PersistentTransaction
    ↓
UI automatically updates via @Query/Observable
    ↓
Transaction appears in activity list
```

**Critical Insight:** The transaction appearing in the UI is **decoupled** from the payment method's return value. The `LightningSendStatus` return tells us about payment settlement status, but transactions are created independently by the SDK's movement system.

### What the API Change Affects

**Before (Old API):**
```swift
let send = try await wallet.payLightningInvoice(invoice: invoice, amountSats: amount)
// send.preimage is String? - available immediately if payment settled
// send.amountSats, send.htlcVtxoCount available
// No feeSats field
```

**After (New API):**
```swift
let status = try await wallet.payLightningInvoice(invoice: invoice, amountSats: amount, wait: true)
// status is LightningSendStatus enum with three cases:
switch status {
case .paid(let paymentHash, let preimage):
    // Payment confirmed and settled - preimage proves payment
case .inProgress(let send):
    // Payment locked but not settled - send.feeSats now available
case .unknown:
    // Payment not found (shouldn't happen after just paying)
}
```

**What Changes:**
- How we access the preimage (pattern matching instead of optional property)
- We get typed status information instead of implicit status
- We get a `feeSats` field on `LightningSend` for better fee tracking
- We add a `wait: Bool` parameter to control blocking behavior

**What Doesn't Change:**
- Transaction creation (still via Movement events)
- Transaction persistence (still via SwiftData)
- Transaction display in activity list (still immediate via reactive bindings)
- Balance updates (still via balance refresh after payment)

---

## 2. Impact on User Flows

### 2.1 Send Flow (Primary Payment Experience)

**File:** `SendViewModel+PaymentExecution.swift`

**Current Behavior:**
1. User enters amount and destination
2. User taps "Send"
3. SendModalState changes to `.sending` (shows progress indicator)
4. Payment executes via `payLightningInvoice`/`payLightningOffer`/`payLightningAddress`
5. On success: Modal shows `.success` state
6. On error: Modal shows `.error(message)` state
7. Transaction appears in activity list (via Movement notification)

**After Migration:**

Same flow, with enhanced status handling:

```swift
// In executeSend() method
let status = try await walletManager.payLightningInvoice(invoice: ..., amountSats: ..., wait: true)

// Enhanced status handling
switch status {
case .paid(let paymentHash, let preimage):
    // Payment fully settled - guaranteed success
    sendModalState = .success
    print("✅ Payment settled with preimage: \(preimage.prefix(16))...")
    
case .inProgress(let send):
    // Payment locked but settling - treat as success
    // User's VTXOs are committed, payment will complete
    sendModalState = .success
    print("⏳ Payment in progress, fee: \(send.feeSats) sats")
    
case .unknown:
    // Payment not found - shouldn't happen but handle gracefully
    sendModalState = .error("Payment status unknown")
}
```

**User Experience Impact:**
- **No visible change** - success/error states work the same
- **Better logging** - we can log payment status for debugging
- **Future enhancement opportunity** - could distinguish between settled (.paid) and settling (.inProgress) if we want

**Decision:** For v1 migration, treat both `.paid` and `.inProgress` as success. This matches current behavior where we consider the payment successful once VTXOs are locked.

---

### 2.2 Transaction List (Activity View)

**Files:** 
- `TransactionListModel.swift` - List state management
- `TransactionModel.swift` - Transaction data model
- `TransactionService.swift` - Movement processing

**Current Behavior:**
- Transactions loaded from SwiftData `PersistentTransaction` entities
- List updates reactively via `@Query` (SwiftUI) or manual fetch
- Each transaction shows: amount, date, status, type, address, fees
- Lightning transactions include `paymentHash` and `paymentPreimage` fields

**Impact of API Changes:**

**None.** Transaction list is completely unaffected because:

1. **Transactions come from Movement events**, not payment return values
2. **TransactionModel structure unchanged** - still has `paymentHash` and `paymentPreimage` fields
3. **Movement JSON unchanged** - server still sends same data structure
4. **Persistence unchanged** - SwiftData entities identical

**Lightning Payment Transaction Fields:**
```swift
struct TransactionModel {
    let paymentHash: String?        // Still populated from Movement
    let paymentPreimage: String?    // Still populated from Movement  
    let paymentMethodType: String?  // "invoice", "offer", "lightning_address"
    // ... other fields unchanged
}
```

**Where Preimages Come From:**

The preimage in `TransactionModel` comes from the **Movement event**, not from the `payLightningInvoice` return value. Here's the flow:

```
Payment initiated
    ↓
SDK processes payment (locks VTXOs, routes to Lightning network)
    ↓
Payment settles (preimage revealed)
    ↓
SDK emits Movement with payment metadata INCLUDING preimage
    ↓
TransactionService receives Movement JSON:
{
  "txid": "...",
  "payment_hash": "...",
  "payment_preimage": "...",  ← This is where UI gets preimage
  ...
}
    ↓
TransactionModel populated with preimage from Movement
    ↓
UI can display preimage in transaction details
```

**Conclusion:** Transaction list visibility and transaction details are **completely unaffected** by the API changes.

---

### 2.3 Transaction Status & Pending States

**Question:** Do Lightning payments show as "pending" in the transaction list while settling?

**Answer:** Yes, but this is **unrelated to the API changes**.

**How Status Works:**

Transactions have a `status: TransactionStatusEnum` field that comes from the Movement event:

```swift
enum TransactionStatusEnum: String, Codable {
    case pending = "pending"
    case completed = "completed"
    case failed = "failed"
}
```

The Bark SDK determines transaction status based on its internal state:
- **Pending:** VTXOs locked but round not finalized, or Lightning payment routing
- **Completed:** Round finalized and VTXOs confirmed, or Lightning payment settled
- **Failed:** Round failed or payment failed

**API Migration Impact on Status:**

**None.** The status field comes from Movement events, not from `LightningSendStatus`. 

However, there's an interesting relationship:

```
When payLightningInvoice() returns:
  - .paid → Movement will have status="completed" (settled)
  - .inProgress → Movement may have status="pending" (still routing)
  - .unknown → No movement exists (error case)
```

But since we use `wait: true`, the payment method typically blocks until settled, so most payments return `.paid` and immediately create a "completed" Movement.

**Edge Case:** If we later change to `wait: false` for non-blocking payments, we might see:
1. Payment returns immediately with `.inProgress` 
2. Movement created with `status="pending"`
3. Transaction appears in list as "pending"
4. Later, Movement updates to `status="completed"`
5. Transaction updates to "completed" in UI

This already works today - the API changes don't affect it.

---

### 2.4 Payment Polling & Status Checking

**Current Code:** `BarkWalletFFI+Lightning.swift` has a `pollLightningPaymentStatus` method (lines 349-378)

**What It Does:**
```swift
private func pollLightningPaymentStatus(paymentHash: String, ...) async {
    for attempt in 1...maxAttempts {
        let preimage = try await checkLightningPayment(paymentHash: paymentHash, wait: false)
        if let preimage = preimage {
            // Payment settled!
            return
        }
        // Wait and try again
    }
}
```

**Migration Impact:**

Need to update for new `checkLightningPayment` return type:

```swift
// Old
let preimage: String? = try await checkLightningPayment(paymentHash: hash, wait: false)

// New
let status: LightningSendStatus = try await checkLightningPayment(paymentHash: hash, wait: false)
```

**Updated Polling Logic:**
```swift
private func pollLightningPaymentStatus(paymentHash: String, ...) async {
    for attempt in 1...maxAttempts {
        let status = try await checkLightningPayment(paymentHash: paymentHash, wait: false)
        
        switch status {
        case .paid(_, let preimage):
            Self.logger.info("Payment settled: \(preimage.prefix(16))...")
            return
        case .inProgress:
            Self.logger.debug("Payment still in progress, attempt \(attempt)")
            // Continue polling
        case .unknown:
            Self.logger.warning("Payment not found")
            return
        }
        
        if attempt < maxAttempts {
            try await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
        }
    }
}
```

**Impact:** Improved status differentiation - we can now distinguish between "still processing" vs "not found".

---

### 2.5 Fee Display & Estimation

**Current Behavior:**

Fees are estimated before sending:
- `estimateLightningSendFee(amountSats:)` returns `FeeEstimate`
- Fee shown to user before confirming send
- After sending, actual fee stored in `TransactionModel.fees` (from Movement)

**New Opportunity:**

The new `LightningSend.feeSats` field provides the **actual fee charged** at payment time:

```swift
case .inProgress(let send):
    print("Actual fee charged: \(send.feeSats) sats")
    // Could compare to estimate, log differences, etc.
```

**Migration Plan:**

**v1 (Minimal Change):** Don't surface this in UI yet. Just log it for debugging.

**Future Enhancement:** Could show actual vs estimated fees:
```
Estimated fee: 50 sats
Actual fee: 48 sats (saved 2 sats!)
```

**Why Not v1:** Requires UI changes to fee summary views, out of scope for API migration.

---

## 3. Error Handling & Edge Cases

### 3.1 Payment Failures

**Current Behavior:**
```swift
do {
    let send = try await wallet.payLightningInvoice(...)
    // Success
} catch {
    // Show error to user
    sendModalState = .error(error.localizedDescription)
}
```

**After Migration:**
```swift
do {
    let status = try await wallet.payLightningInvoice(..., wait: true)
    switch status {
    case .paid, .inProgress:
        // Success
        sendModalState = .success
    case .unknown:
        // Shouldn't happen after just paying, but handle it
        sendModalState = .error("Payment status unknown")
    }
} catch {
    // Same as before - payment failed to execute
    sendModalState = .error(error.localizedDescription)
}
```

**Impact:** Better error handling granularity. We can distinguish:
- **Payment failed to execute** (caught exception) - routing failure, insufficient balance, etc.
- **Payment executed but status unknown** (.unknown case) - rare edge case
- **Payment executing but not settled** (.inProgress) - normal for slow routes

---

### 3.2 Insufficient Balance Errors

**Files:** `SendViewModel+PaymentExecution.swift` lines 154-173

**Current Logic:**
```swift
// Check if amount + fee exceeds available balance
let totalRequired = amountInt + (ranked.estimatedFee ?? 0)
if let availableBalance = ranked.availableBalance, totalRequired > availableBalance {
    throw SendError.insufficientBalance(required: totalRequired, available: availableBalance)
}
```

**Impact of Migration:** None. Balance checking happens **before** calling the payment method.

---

### 3.3 Network Timeout / Slow Payments

**Scenario:** User pays a Lightning invoice but the route is slow (30+ seconds to settle)

**Current Behavior with `wait` implied:**
- `payLightningInvoice` blocks until settled or timeout
- User sees "Sending..." modal the entire time
- On success, shows success modal
- Transaction appears in list once Movement received

**After Migration with `wait: true`:**
- Same behavior - blocks until settled
- Returns `.paid` when settled, `.inProgress` if timeout before settlement
- Could handle `.inProgress` by showing "Payment processing..." state

**Alternative with `wait: false` (not v1):**
- Returns `.inProgress` immediately
- Could show "Payment submitted" and poll status
- Better UX for slow routes but requires more complex state management

**Decision for v1:** Use `wait: true` everywhere for simplicity. Future enhancement: use `wait: false` for better UX.

---

## 4. Preview Mode & Testing

### 4.1 Preview Mode (BarkWalletFFI)

**Current Preview Returns:**
```swift
if isPreview {
    return LightningSend(invoice: invoice, amountSats: amountSats ?? 0, htlcVtxoCount: 1, preimage: nil)
}
```

**After Migration:**
```swift
if isPreview {
    // Return in-progress status for preview
    let send = LightningSend(
        invoice: invoice, 
        amountSats: amountSats ?? 0, 
        htlcVtxoCount: 1,
        feeSats: 50  // New field - mock 50 sat fee
    )
    return .inProgress(send: send)
}
```

**Note:** `LightningSend` no longer has `preimage` field, so we remove it from mock.

---

### 4.2 Mock Wallet (MockBarkWallet)

**Current Mock Returns:**
```swift
func payLightningInvoice(...) async throws -> LightningSend {
    return LightningSend(invoice: invoice, amountSats: amountSats ?? 0, htlcVtxoCount: 1, preimage: nil)
}
```

**After Migration:**
```swift
func payLightningInvoice(..., wait: Bool) async throws -> LightningSendStatus {
    let send = LightningSend(
        invoice: invoice, 
        amountSats: amountSats ?? 0, 
        htlcVtxoCount: 1,
        feeSats: 50  // Mock fee
    )
    // Return inProgress for mock payments
    return .inProgress(send: send)
}
```

**Impact:** Preview mode continues to work, shows realistic payment flow.

---

## 5. Performance & Responsiveness

### 5.1 Transaction Appearance Latency

**Question:** Does the API change affect how quickly transactions appear in the activity list?

**Answer:** No impact on latency. Timeline:

```
Time 0:    User taps "Send"
Time 0:    SendModalState = .sending (shows spinner)
Time 0-5s: payLightningInvoice executes, blocks on wait: true
Time 5s:   Payment method returns .paid or .inProgress
Time 5s:   SendModalState = .success (shows checkmark)
Time 5s:   Bark SDK emits Movement event
Time 5s:   WalletNotificationService receives Movement
Time 5s:   TransactionService processes Movement → SwiftData
Time 5s:   UI updates via reactive binding
Time 5s:   Transaction visible in activity list
```

The time from "Send" tap to transaction visibility is **unchanged**.

---

### 5.2 Balance Update Timing

**Current Flow:**
```
Payment completes
    ↓
WalletOperationsService.onTransactionCompleted() callback
    ↓
Triggers balance refresh
    ↓
Balance updates in UI
```

**After Migration:** Same flow, no changes to balance refresh logic.

---

## 6. New Methods (Optional)

The new API provides two additional methods:

### 6.1 `isInvoicePaid(paymentHash:) -> Bool`

**Use Case:** Quick boolean check if a payment settled.

**Potential Usage:**
```swift
// In transaction detail view
if let paymentHash = transaction.paymentHash {
    let isPaid = try await wallet.isInvoicePaid(paymentHash: paymentHash)
    // Show "Settled ✓" or "Pending..." badge
}
```

**v1 Decision:** Don't implement yet. Transaction status already comes from Movement events.

**Future Enhancement:** Could use for real-time status checking without full refresh.

---

### 6.2 `lightningSendState(paymentHash:) -> LightningSendStatus`

**Use Case:** Non-blocking status check for a specific payment.

**Potential Usage:**
```swift
// In transaction detail view for pending Lightning payment
let status = try await wallet.lightningSendState(paymentHash: hash)
switch status {
case .paid(_, let preimage):
    // Update UI to show settled
case .inProgress(let send):
    // Show "Routing..." with fee info
case .unknown:
    // Payment not found or pruned
}
```

**v1 Decision:** Don't implement yet. Not needed for basic migration.

**Future Enhancement:** Could add "Check Status" button to transaction details for pending payments.

---

## 7. Migration Risk Assessment

### 7.1 Breaking Changes

**High Risk Areas:**
1. ✅ Protocol signature changes (compile-time enforced, can't miss)
2. ✅ `.preimage` access removal (compile-time error, easy to find)
3. ⚠️ Return type handling (need to update all call sites)

**Low Risk Areas:**
1. Transaction list display (unchanged, uses Movement events)
2. Transaction persistence (unchanged, SwiftData models identical)
3. Balance updates (unchanged, refresh logic identical)
4. UI state management (unchanged, SendModalState enum identical)

---

### 7.2 Testing Strategy

**Critical Test Paths:**

1. **Send Lightning Invoice (with amount)**
   - User enters amount
   - Payment executes successfully
   - Transaction appears in activity list
   - Balance updates correctly

2. **Send Lightning Invoice (amount in invoice)**
   - User sends invoice with embedded amount
   - Payment executes without user entering amount
   - Transaction appears correctly

3. **Send Lightning Address**
   - User sends to user@domain.com
   - Payment executes successfully
   - Transaction appears with correct metadata

4. **Send LNURL-pay**
   - User pastes LNURL
   - Invoice fetched from callback
   - Payment executes
   - Transaction appears

5. **Send BOLT12 Offer**
   - User sends to lno1... offer
   - Payment executes successfully
   - Transaction appears

6. **Payment Failure**
   - User attempts payment with insufficient balance
   - Error shown to user
   - No transaction created
   - Balance unchanged

7. **Preview Mode**
   - Send flows work in Xcode previews
   - Mock payments return realistic data
   - UI renders correctly

**Validation Checklist:**
- [ ] All Lightning payment types execute successfully
- [ ] Transactions appear in activity list immediately
- [ ] Transaction details show correct amounts and fees
- [ ] Preimages visible in transaction details (from Movement)
- [ ] Balance updates after payment
- [ ] Error messages displayed correctly on failure
- [ ] Preview mode works for all send types
- [ ] No compiler warnings related to API changes

---

## 8. Recommendations & Action Items

### 8.1 Implementation Approach

**Recommended Order:**
1. ✅ Update protocol (BarkWalletProtocol.swift)
2. ✅ Update FFI implementation (BarkWalletFFI+Lightning.swift)
3. ✅ Update mock implementation (MockBarkWallet.swift)
4. ✅ Update service layer (WalletManager, WalletOperationsService)
5. ✅ Update UI layer (SendViewModel+PaymentExecution.swift)
6. ✅ Update polling logic (BarkWalletFFI+Lightning.swift)
7. ✅ Test all payment flows
8. ✅ Verify preview mode

**Time Estimate:** 2-3 hours (as per migration plan)

---

### 8.2 Future Enhancements (Post-Migration)

**Quick Wins:**
1. **Log actual fees** - Compare `send.feeSats` to estimated fees for accuracy monitoring
2. **Add isInvoicePaid method** - Quick status checks without full status polling
3. **Add lightningSendState method** - Enable transaction detail status refresh

**Larger Projects:**
1. **Non-blocking payments** - Use `wait: false` with status polling for better UX
2. **Show actual vs estimated fees** - Display fee accuracy to users
3. **Real-time payment status** - Show "Routing..." → "Settling..." → "Complete" progression
4. **Payment status badges** - Visual indicators in transaction list for pending payments

**Priority:** All post-migration. Don't scope creep the API migration.

---

## 9. Conclusion

### Key Takeaways

1. **Minimal User Impact:** The API changes are internal. Users won't notice any difference in v1.

2. **Transaction Display Unchanged:** Activity list and transaction details work exactly as before because they're driven by Movement events, not payment return values.

3. **Better Type Safety:** `LightningSendStatus` enum provides clearer payment state than optional strings.

4. **Fee Data Available:** New `feeSats` field enables better fee tracking and display in future.

5. **Straightforward Migration:** Most changes are mechanical (add `wait` parameter, pattern match status instead of accessing `.preimage`).

6. **Low Risk:** Compile-time enforcement catches breaking changes. Transaction display logic completely unaffected.

### Success Criteria

Migration is successful when:
- ✅ All Lightning payment types work (invoice, address, offer, LNURL)
- ✅ Transactions appear in activity list immediately after payment
- ✅ Transaction details show preimages (from Movement events)
- ✅ Balance updates correctly after payment
- ✅ Error handling works for failed payments
- ✅ Preview mode works correctly
- ✅ No compiler errors or warnings
- ✅ All existing tests pass

### Next Steps

1. Review this analysis with team
2. Confirm `wait: true` strategy for v1
3. Execute migration plan (Phases 1-7)
4. Test thoroughly on testnet/signet
5. Consider future enhancements for v2
