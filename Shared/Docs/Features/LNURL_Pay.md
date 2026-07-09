# LNURL-pay Support

**Status:** ✅ Shipped (2026-05-30; fixed-amount handling 2026-06-12, note pre-population 2026-06-26)
**Distilled from:** `Archive/Implementations/LNURL_PAY_IMPLEMENTATION_PLAN.md` (full implementation history there)

---

## Overview

The send view accepts LNURL-pay strings (LUD-06, bech32-encoded `lnurl1...`) from clipboard, QR scan, and NFC. The flow is **Detect → Resolve → Execute**, matching the existing Lightning Address and BIP-353 patterns.

**Important divergence from the original plan:** the app does not request and pay the invoice itself. Since Bark 0.11, **Bark performs the full LNURL-pay flow natively** — `walletManager.payLnurl(lnurl:amountSats:comment:)` handles callback fetch → invoice request → payment in one call. The app-side resolver still runs, but only for pre-send UX: amount-limit validation, fixed-amount pre-fill, and note pre-population from metadata.

## Detection

- `LNURLResolver.isLNURL()` — case-insensitive `lnurl1` prefix check.
- `AddressValidator` produces a `PaymentDestination` with `AddressFormat.lnurl` (enum lives in the ArkéUI package: `ArkeUI/Sources/ArkéUI/Models/AddressFormat.swift`). LNURL is checked before Lightning Address since it's more specific; a `lightning:` URI prefix is also recognized and stripped.
- QR and NFC need no special handling — both funnel through `AddressValidator.parsePaymentRequest()`.

## Resolution — `LNURLResolver` (`Shared/Helpers/LNURLResolver.swift`)

- **Decode:** bech32 (same helpers as `LightningInvoiceParser`) → UTF-8 URL, **HTTPS only** (security requirement, `LNURLError.notHTTPS`).
- **Fetch:** GET with 10 s timeout; validates `tag == "payRequest"`; surfaces `status: ERROR` responses as `serverError`.
- **Result:** `ResolvedLNURL` with callback, min/max sendable (millisats, with sats accessors), metadata, `commentAllowed`.
- **Fixed-amount LNURLs:** `isFixedAmount` / `fixedAmountSats` (min == max, common for point-of-sale) — the clipboard flow pre-fills the amount.
- **Metadata:** `descriptionText` parses LUD-06 metadata JSON, preferring `text/plain` over `text/long-desc`.
- **Cache:** 10-minute TTL, same pattern as `LightningAddressResolver`.

## Send-flow integration

- `SendViewModel.resolvedLNURL` holds the resolution (cleared in `clearAll()`).
- **Clipboard** (`SendViewModel+Clipboard.swift`): detects, resolves, stores, pre-fills fixed amounts.
- **Note pre-population** (`SendViewModel+PendingMetadata.swift`): the LNURL metadata description is one of the note sources.
- **Execution** (`SendViewModel+PaymentExecution.swift`, `case .lnurl`): resolves if not cached (re-triggering note pre-population), validates amount against min/max, then calls `walletManager.payLnurl`. Send-max uses the shared retry logic (3 attempts). Payment hash is extracted from the returned status for metadata matching.

## Testing

`Tests/Shared/LNURLResolverTests.swift` — detection, bech32 decode, invalid formats, response parsing, cache TTL.

## Not implemented (deliberately out of scope)

Comment field (`commentAllowed` is parsed but unused, `comment: nil` is passed), min/max hints in the amount UI (validated only on send), LNURL success actions, amount suggestions from metadata, and LNURL-withdraw.
