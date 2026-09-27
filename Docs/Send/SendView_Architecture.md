# SendView Architecture

**Status:** Current
**Last Updated:** 2026-07-09
**Consolidated from:** `SENDVIEW_OVERVIEW.md`, `SENDVIEW_REFACTORING.md`, `SENDVIEW_REFACTORING_SUMMARY.md` (verified against the code 2026-07-09)

The Send feature follows the shared-ViewModel pattern (like TagsView/TagsViewModel): thin platform-specific UI shells on macOS and iOS, with all business logic in a shared, platform-agnostic `SendViewModel`.

---

## Layer Overview

```
┌─────────────────────────────────────────────────────┐
│                  Platform UI Shells                  │
├──────────────────────────┬──────────────────────────┤
│  SendView (macOS)        │  SendView_iOS (iOS)      │
│  ArkeDesktop/Views/Send  │  ArkeMobile/Views/Send   │
│  - window-focus          │  - QR camera scanning +  │
│    clipboard check       │    manual input modes    │
│  - macOS sheets/toolbar  │  - presentationDetents,  │
│                          │    paste button          │
└──────────────────────────┴──────────────────────────┘
                          │
                          ▼
         ┌───────────────────────────────────┐
         │   SendViewModel  (@Observable,    │
         │   @MainActor, Shared/Views/Send/) │
         │   split into 11 extension files   │
         └───────────────────────────────────┘
              │                    │
              ▼                    ▼
   ┌─────────────────────┐   ┌──────────────────────┐
   │ ClipboardService    │   │ WalletManager,       │
   │ (protocol + per-    │   │ ModelContext,        │
   │  platform impls)    │   │ resolvers/validators │
   └─────────────────────┘   └──────────────────────┘
                          │
                          ▼
         ┌───────────────────────────────────┐
         │  Shared child views               │
         │  Shared/Views/Send/ + Flows/      │
         │  (+ AmountInputSection in ArkéUI) │
         └───────────────────────────────────┘
```

## File Map

### Platform shells
- `ArkeDesktop/Views/Send/SendView.swift` — macOS orchestration. Checks the clipboard automatically on `NSWindow.didBecomeKeyNotification`.
- `ArkeMobile/Views/Send/SendView_iOS.swift` — iOS orchestration. Larger than the macOS shell because it also hosts the QR **camera scanning mode**: an `inputMethod` state switches between `.camera` and `.input`, with a sliding transition and floating controls.

### Shared ViewModel — `Shared/Views/Send/SendViewModel/`
`SendViewModel.swift` holds the state and dependencies; behavior is split into focused extensions:

| File | Responsibility |
|------|----------------|
| `SendViewModel.swift` | State, `SendMode`, dependencies (WalletManager, ClipboardServiceProtocol, ModelContext), fee caches |
| `+Initialization.swift` | Setup for the three entry contexts (manual / contact / pre-filled payment request) |
| `+StateManagement.swift` | Mode transitions, `clearAll()` reset |
| `+Clipboard.swift` | Clipboard detection, parsing, and resolution (BIP-353 / Lightning Address parallel resolution, LNURL, BIP-21, invoices) |
| `+PaymentExecution.swift` | Executing Ark / onchain / Lightning / LNURL payments |
| `+FeeEstimation.swift` / `+FeeCalculation.swift` | Per-rail fee estimates with amount-keyed caches; onchain fee priority tiers |
| `+MaxSendable.swift` | "Send max" computation, incl. retry logic for Lightning routing fees (`isSendingMax`) |
| `+PendingMetadata.swift` | Creates `PendingPaymentMetadata` at send time, matched to the transaction when the movement arrives (see `Features/send-metadata-enhancement.md`) |
| `+ComputedProperties.swift` | Derived UI state |
| `+Helpers.swift` | Small utilities |

### Shared views — `Shared/Views/Send/`
- `Flows/` — one view per send mode: `ManualSendView`, `ContactPaymentView`, `QuickPaymentView`
- `RecipientInputSection.swift` + `RecipientState.swift` — manual-entry input with live validation
- `ConfirmedDestinationCard.swift` — locked-in destination display (see UX model below)
- `SendMetadataSection.swift` — contact/tag/note assignment during send
- `SendModalView.swift` + `SendModalState/Content/Sending/Success` — the send-confirmation modal family
- `FeeSelectionSheet.swift` — onchain fee-priority picker
- `BitcoinAddressField.swift`, `DisplayDestination.swift`, `SheetDestinationDisplayView.swift`, `ValidationFeedbackView.swift`, banners, etc.
- `AmountInputSection` lives in the **ArkéUI package** (`ArkeUI/Sources/ArkéUI/Views/Send/`), not in this folder; it handles locked amounts (e.g. invoices with embedded amounts).

### Clipboard abstraction
- `Shared/Helpers/ClipboardServiceProtocol.swift`, implemented by `ArkeDesktop/Helpers/ClipboardService_macOS.swift` (NSPasteboard) and `ArkeMobile/Helpers/ClipboardService_iOS.swift` (UIPasteboard). Keeps the ViewModel platform-free and mockable.

---

## Send Modes

```swift
enum SendMode {
    case manual                                       // manual entry (entering or confirmed)
    case contact(ContactModel)                        // sending to a saved contact
    case quick(PaymentRequest, source: PaymentRequestSource)  // detected payment request, with source tracking
}
```

- Mode is selected once at initialization based on context (blank open, contact tap, detected payment request).
- Quick mode can transition to Manual (confirmed) when the user accepts a bare address.
- `clearAll()` resets any mode back to Manual (entering).

## Manual-Entry UX Model: Input vs. Confirmed

The manual flow deliberately separates two stages, so users never see a raw BIP-21 URI in an editable field:

1. **`RecipientInputSection`** — clean input for typing/pasting, with live validation surfaced through `RecipientState`:
   `idle / typing / valid / validBIP353Format / resolvingBIP353 / bip353Resolved(original) / invalid(message)`
2. **`ConfirmedDestinationCard`** — once a payment request is locked in, a non-editable card shows only the *selected* destination (e.g. the Ark address picked out of a multi-option BIP-21), its metadata, and affordances to switch payment method or clear back to manual entry.

Destination choice among a request's alternatives is ranked by `PaymentDestinationSelector` (see `Payment destination selection/PAYMENT_DESTINATION_SELECTOR.md`).

## Clipboard Behavior

Two distinct operations, chosen to respect iOS's paste-permission dialogs:

- **`checkClipboardAvailability()`** — asks only *whether* the clipboard has strings (no permission dialog); drives paste-button visibility. iOS calls this on `UIApplication.didBecomeActiveNotification` and on appear.
- **`checkClipboardForAddress()`** — actually reads and parses the clipboard. macOS runs it automatically on window focus; iOS runs it only when the user explicitly taps the paste button (this replaced the original "check once on first appear" behavior).

Parsing handles the ambiguous `user@domain` case by resolving BIP-353 and Lightning Address **in parallel**, strips `lightning:` prefixes before LNURL detection, and falls through to BIP-21/invoice/address parsing.

## Supported Payment Formats

Bitcoin addresses, Ark addresses, Lightning invoices (BOLT11), Lightning offers (BOLT12), Lightning Addresses (`user@domain`), LNURL-pay, BIP-21 URIs (single and multi-destination), BIP-353 human-readable names, and Silent Payments — see `AddressFormat` in ArkéUI for the canonical list. Since Bark 0.11, LNURL-pay runs natively via `payLnurl` (see `Features/LNURL_Pay.md`).

---

## History

Two refactorings shaped this architecture (details in git history):

- **2025-11-18** — split the single overloaded `recipient` TextField into the input/confirmed two-stage model (`RecipientInputSection` + `ConfirmedDestinationCard` + extracted `AmountInputSection`).
- **2025-12-08** — iOS port: extracted all business logic from the macOS view into the shared `SendViewModel` (~80% code reuse), added the `ClipboardServiceProtocol` abstraction and `SendView_iOS`.

Since then the ViewModel has been decomposed into per-concern extension files, iOS gained QR camera scanning, send metadata (contacts/tags/notes) and fee selection were added, and `AmountInputSection` moved into ArkéUI.

## Related Docs

- `SENDVIEW_USAGE_GUIDE.md`, `SENDVIEW_USAGE_EXAMPLES.md` — integration and usage
- `SENDVIEW_PREVIEW_STATES.md`, `SENDVIEW_BANNER_COMPARISON.md`, `SENDVIEW_MIGRATION_CHECKLIST.md`
- `PAYMENT_SOURCE_FLOW_REFERENCE.md`, `QR_CODE_SOURCE_IMPLEMENTATION.md`
- `../Payment destination selection/PAYMENT_DESTINATION_SELECTOR.md` — destination ranking
- `../Features/send-metadata-enhancement.md` — active metadata feature plan
- `../Features/LNURL_Pay.md` — LNURL-pay behavior
