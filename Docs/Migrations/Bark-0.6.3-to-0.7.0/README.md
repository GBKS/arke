# Bark FFI Bindings Migration: v0.6.3 → v0.7.0

**Date:** 2026-06-05  
**Status:** ✅ Completed  
**Bark Version:** v0.2.1 → v0.2.2  
**FFI Bindings Version:** v0.6.3 → v0.7.0

## Overview

This migration updated the Arke codebase to use the new Bark Swift bindings API, specifically the Lightning send operations that now use `LightningSendStatus` enum instead of returning `LightningSend` directly.

## Key Changes

- **New type:** `LightningSendStatus` enum with `.paid`, `.inProgress`, `.unknown` cases
- **Breaking changes:** All Lightning send methods now return `LightningSendStatus`
- **Removed field:** `LightningSend.preimage` (moved to `.paid` status case)
- **New field:** `LightningSend.feeSats` for actual fee tracking
- **New methods:** `isInvoicePaid()` and `lightningSendState()`

## Impact

- **User experience:** No visible changes
- **Transaction display:** Completely unaffected (driven by Movement events)
- **Code changes:** 7 files modified across protocol, FFI, mocks, services, and UI layers
- **Build result:** ✅ Passing

## Documents

This folder contains the complete migration documentation:

1. **[01-api-changes.md](01-api-changes.md)** - Complete API diff between old and new versions
2. **[02-migration-plan.md](02-migration-plan.md)** - Step-by-step implementation plan (7 phases)
3. **[03-impact-analysis.md](03-impact-analysis.md)** - Holistic analysis of user experience impact
4. **[04-completion-report.md](04-completion-report.md)** - Final completion report with all changes

## Files Modified

1. `Shared/Data/BarkWalletProtocol.swift` - Protocol signatures
2. `Shared/Data/BarkWalletFFI/BarkWalletFFI+Lightning.swift` - FFI implementation
3. `Shared/Data/MockBarkWallet.swift` - Mock implementation
4. `Shared/Data/WalletManager/WalletManager+Lightning.swift` - Manager wrapper
5. `Shared/Services/WalletOperationsService.swift` - Operations service
6. `Shared/Views/Send/SendViewModel/SendViewModel+PaymentExecution.swift` - Payment execution
7. `ArkeMobile/Views/Settings/Testing/IncrementalPaymentTestView_iOS.swift` - Test view

## Quick Reference

### Old API
```swift
let send = try await wallet.payLightningInvoice(invoice: inv, amountSats: nil)
let preimage = send.preimage  // Optional String
```

### New API
```swift
let status = try await wallet.payLightningInvoice(invoice: inv, amountSats: nil, wait: true)
switch status {
case .paid(let paymentHash, let preimage):
    // Payment confirmed
case .inProgress(let send):
    // Payment locked (fee available: send.feeSats)
case .unknown:
    // Payment not found
}
```

## Future Enhancements

- Non-blocking payments with `wait: false` and status polling UI
- Display actual vs estimated fees in UI
- Real-time payment status progression
- Payment status badges in transaction list
