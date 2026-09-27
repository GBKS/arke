# SendView Refactoring - Migration Checklist

## Files Changed

### ✅ New Files Created
- [x] `ClipboardServiceProtocol.swift` - Platform abstraction
- [x] `ClipboardService_macOS.swift` - macOS implementation
- [x] `ClipboardService_iOS.swift` - iOS implementation
- [x] `SendViewModel.swift` - Shared business logic
- [x] `SendView_iOS.swift` - iOS UI implementation

### ✅ Files Modified
- [x] `SendView.swift` - Refactored to use SendViewModel (macOS UI only)

### 📋 Files Unchanged (Zero Impact)
- ManualSendView.swift
- ContactPaymentView.swift
- QuickPaymentView.swift
- RecipientInputSection.swift
- AmountInputSection.swift
- SendModalView.swift
- ErrorView.swift
- AddressValidator.swift
- PaymentDestinationSelector.swift
- BIP353Resolver.swift
- LightningAddressResolver.swift

## Verification Steps

### 1. Compilation
- [ ] Project builds without errors on macOS
- [ ] Project builds without errors on iOS
- [ ] No compiler warnings introduced
- [ ] All previews render correctly

### 2. Functionality - macOS
- [ ] Manual entry works
- [ ] Contact pre-fill works
- [ ] Quick payment (clipboard) works
- [ ] BIP-353 resolution works
- [ ] Lightning Address resolution works
- [ ] Clipboard detection on window focus works
- [ ] Payment execution succeeds
- [ ] Error handling displays correctly
- [ ] Success modal appears and dismisses
- [ ] View dismisses after successful payment

### 3. Functionality - iOS
- [ ] Manual entry works
- [ ] Contact pre-fill works
- [ ] Quick payment (clipboard) works
- [ ] BIP-353 resolution works
- [ ] Lightning Address resolution works
- [ ] Clipboard detection on view appear works
- [ ] Clipboard permission dialog appears (expected)
- [ ] No clipboard check on app focus (Option C)
- [ ] Payment execution succeeds
- [ ] Error handling displays correctly
- [ ] Success modal appears and dismisses
- [ ] View dismisses after successful payment

### 4. Payment Methods - Both Platforms
- [ ] Bitcoin address sends work
- [ ] Ark address sends work
- [ ] Lightning invoices work
- [ ] BOLT12 offers work
- [ ] Silent Payments work
- [ ] BIP-21 URIs work
- [ ] Multi-destination BIP-21 works
- [ ] Amount pre-fill works for invoices
- [ ] Amount locking works for invoices

### 5. Edge Cases
- [ ] Invalid addresses show error
- [ ] Insufficient balance shows error
- [ ] Network errors are handled gracefully
- [ ] Clipboard with non-address content is ignored
- [ ] Empty clipboard is handled
- [ ] Multiple rapid clipboard checks don't crash
- [ ] View dismissal cancels pending operations

### 6. Code Quality
- [ ] No force unwraps introduced
- [ ] All optionals handled safely
- [ ] Async/await used correctly
- [ ] No retain cycles
- [ ] Memory leaks checked
- [ ] Print statements follow logging pattern

### 7. Architecture
- [ ] ViewModel is @Observable and @MainActor
- [ ] ClipboardService uses protocol abstraction
- [ ] Platform-specific code uses #if os() checks
- [ ] Shared components work on both platforms
- [ ] Business logic is in ViewModel
- [ ] UI logic is in Views

## Testing Scenarios

### Scenario 1: Fresh Install
**Steps:**
1. Install app on clean device
2. Open SendView
3. Observe clipboard permission dialog (iOS only)
4. Enter Bitcoin address manually
5. Enter amount
6. Send payment

**Expected:**
- ✅ Permission dialog shows once on iOS
- ✅ Address validates correctly
- ✅ Payment executes successfully
- ✅ View dismisses

### Scenario 2: Clipboard with Address
**Steps:**
1. Copy Bitcoin address to clipboard
2. Open SendView
3. Observe quick payment card
4. Accept payment
5. Enter amount
6. Send

**Expected:**
- ✅ Quick payment card appears
- ✅ Address is pre-filled
- ✅ Amount can be entered
- ✅ Payment succeeds

### Scenario 3: Pre-filled Contact
**Steps:**
1. Open SendView with contact parameter
2. Verify contact banner shows
3. Enter amount
4. Send payment

**Expected:**
- ✅ Contact banner visible
- ✅ Address pre-validated
- ✅ Payment succeeds

### Scenario 4: BIP-353 Resolution
**Steps:**
1. Copy BIP-353 address to clipboard (e.g., "₿user@domain.com")
2. Open SendView
3. Wait for resolution
4. Verify resolved address shows

**Expected:**
- ✅ Loading indicator during resolution
- ✅ Resolved address displays
- ✅ Human-readable name preserved

### Scenario 5: Lightning Invoice with Amount
**Steps:**
1. Open SendView with Lightning invoice
2. Verify amount is locked
3. Tap Send (no amount entry needed)

**Expected:**
- ✅ Amount field shows locked state
- ✅ Amount displays correctly
- ✅ Payment executes without additional input

### Scenario 6: Multi-Destination BIP-21
**Steps:**
1. Open SendView with BIP-21 containing Bitcoin + Ark
2. Verify destination picker available
3. Select preferred destination
4. Enter amount
5. Send

**Expected:**
- ✅ Both destinations detected
- ✅ Optimal destination selected
- ✅ User can change destination
- ✅ Payment succeeds

### Scenario 7: Error Recovery
**Steps:**
1. Enter invalid amount (too large)
2. Tap Send
3. Observe error
4. Correct amount
5. Retry

**Expected:**
- ✅ Error displays inline
- ✅ Retry button works
- ✅ Corrected payment succeeds

## Performance Checks

- [ ] View loads quickly (< 1s)
- [ ] Clipboard checks don't block UI
- [ ] BIP-353 resolution has timeout
- [ ] Lightning Address resolution has timeout
- [ ] Payment execution shows progress
- [ ] No UI freezing during async operations
- [ ] Memory usage is reasonable
- [ ] No excessive allocations

## Accessibility

- [ ] VoiceOver works on iOS
- [ ] Dynamic Type supported
- [ ] Keyboard navigation works on macOS
- [ ] Focus management is correct
- [ ] Labels are descriptive
- [ ] Buttons have proper traits

## Localization Readiness

- [ ] All user-facing strings are ready for localization
- [ ] No hardcoded English-only strings
- [ ] String interpolation is localization-safe
- [ ] Number formatting uses locale

## Documentation

- [x] SENDVIEW_REFACTORING_SUMMARY.md created (since merged into `SendView_Architecture.md`)
- [x] SENDVIEW_USAGE_GUIDE.md created
- [x] Code comments updated
- [x] Architecture documented in file headers
- [x] Migration checklist created (this file)

## Deployment Readiness

### Prerequisites
- [ ] All tests pass
- [ ] Code review completed
- [ ] QA testing completed
- [ ] Performance testing completed
- [ ] Accessibility testing completed

### macOS Deployment
- [ ] Minimum macOS version verified
- [ ] AppKit APIs availability checked
- [ ] Sandbox permissions reviewed
- [ ] Clipboard access tested

### iOS Deployment
- [ ] Minimum iOS version verified
- [ ] UIKit APIs availability checked
- [ ] Clipboard permission info.plist entry exists
- [ ] App Store privacy manifest updated

## Rollback Plan

If issues are discovered:

1. **Immediate rollback:**
   ```
   git revert <commit-hash>
   ```

2. **Selective rollback:**
   - Restore original SendView.swift
   - Remove new files
   - Update imports

3. **Issue tracking:**
   - Document specific failure
   - Create bug report
   - Test fix in isolation

## Known Limitations

1. **iOS Clipboard Permission**
   - System dialog appears on first clipboard access
   - Cannot be suppressed per iOS 16+ requirements
   - Expected behavior, not a bug

2. **BIP-353 Resolution**
   - Requires network connectivity
   - DNS timeout may delay UI
   - Fallback to Lightning Address if DNS fails

3. **Lightning Address Validation**
   - Network call required for validation
   - May fail if server is down
   - Fallback to basic parsing without validation

## Success Criteria

✅ All checklist items completed
✅ Zero regressions on macOS
✅ Full feature parity on iOS
✅ Code review approved
✅ QA sign-off obtained

---

**Date**: December 8, 2025
**Reviewer**: ___________________
**Status**: 🔄 In Review → ✅ Approved → 🚀 Deployed
