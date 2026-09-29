# Fiat Rates

Fiat values next to sats, from one public static file that holds every
currency. Sats are the real amount; fiat is display only.

**Status: Phases 1 and 2 DONE 2026-09-28 (f2f002e, 881efc5); Phase 3 UI
fit IN PROGRESS — steps 1 (balance card, cfacba4) and 2 (send amount field,
2a34ef5) approved on device.** Client, cache, triggers and X-Ray section
shipped; 24/24 unit tests green on iOS; live server check passed (200 → 30
currencies + ETag, then 304). The Settings → Currency picker carries the
required credit in its footer, so no About screen is needed (Christoph's
call 2026-09-28). Remaining Phase 3 surfaces in §7; fiat *input* comes
only after display is complete.

## 1. Source

Rates are published by `arke-rates`, a scheduled job separate from the APNs
relay. It is not an API; it is one static file, refreshed about every 5
minutes:

    GET https://rates.arke.cash/v1/rates.json

The server sends `Cache-Control: public, max-age=60`, an `ETag`, and
answers `If-None-Match` with `304`. Observed 2026-09-28: 30 ISO 4217
codes, `sources: mempool, kraken, coinbase, bitstamp`.

**Privacy property: every client makes the identical request.** No auth,
no query parameters, no cookies, no custom headers except `If-None-Match`,
no per-currency requests. The currency choice never leaves the device. Do
not add anything that makes requests distinguishable. (URLSession's own
default headers, including a User-Agent naming the app and OS version,
identify the app, not the user.)

Credit required by the upstream data provider's free tier (Phase 2 item):
"Rates By Exchange Rate API" → https://www.exchangerate-api.com

## 2. File contract (v1)

```json
{
  "version": 1,
  "updated_at": 1790006660,
  "base": "BTC",
  "rates": { "USD": 85841.88, "EUR": 74863.91, "JPY": 13480254.5 },
  "sources": ["mempool", "kraken", "coinbase", "bitstamp"]
}
```

- `rates[code]` is fiat units per 1 BTC.
- `updated_at` is Unix seconds when the server produced the file. **Every
  staleness decision is based on this, never on download time.**
- A currency can be absent from a file when its sources disagreed. Not an
  error — the cache keeps the previous value (§4).
- Unknown top-level fields (a future `signature`) and unknown currency codes
  are ignored. A breaking change gets a new URL (`/v2/`); this client only
  accepts `version == 1`.

### Validation — reject the whole file on failure, keep the cache

1. HTTP 200 and the body decodes.
2. `version == 1` and `base == "BTC"`.
3. `updated_at` at most 10 minutes in the future (clock skew).
4. `updated_at ≥` the newest cached timestamp. Never go backwards; equal is
   fine (the same file seen again).
5. Per entry: finite, `> 0`, and a code the system knows
   (`Locale.Currency.isoCurrencies`). Bad entries are dropped individually,
   the rest kept.

## 3. Code map

All in `Shared/`, so it compiles into both apps (desktop has no UI yet).

| File | Role |
|------|------|
| `Services/Rates/RatesFileV1.swift` | Decodable model. Tolerant: unknown fields ignored, non-numeric rate entries dropped. Rates decode Double → shortest string → `Decimal`, so `85841.88` stays exactly that. |
| `Services/Rates/RatesCache.swift` | `RateSnapshot { value: Decimal, updatedAt }`, `RateFreshness` (fresh / stale / unavailable), `RatesCache` (etag, lastChecked, per-currency rates), `RatesFileRejection`, and `RatesFileProcessor.validate/merge` — pure, `nonisolated`, unit-tested. |
| `Services/Rates/RatesService.swift` | `@MainActor @Observable`, modelled on `FeeRateService`. `refresh()` never throws; `refreshIfDue()` gates to one attempt per 60 s; `startPeriodicRefresh()/stopPeriodicRefresh()` run the 5-minute loop. Injected `RatesFetcher` closure and clock for tests. Persists to `Application Support/Rates/rates-cache.json`. |
| `Helpers/FiatConversion.swift` | Decimal-only arithmetic and `Decimal.FormatStyle.Currency` formatting. `fiatAmount(sats:rate:)`, `sats(fiatAmount:rate:)` (rounded to the nearest sat), `formatted(_:currency:locale:)`. |
| `Helpers/FiatRatesRefreshTriggers.swift` | View modifier: gated refresh on appear and on every `.active`, periodic loop while active, cancelled on `.background`. Attached to `WalletView_iOS`. |
| `Views/Data/FiatRatesSectionView.swift` | X-Ray section ("Exchange Rates"): currency count, 1 BTC in USD, file time (coloured by freshness), last checked, last result, ETag. The toolbar reload forces a fetch past the 60 s gate. |
| `ServiceContainer.ratesService` + `\.ratesService` environment key | Wallet-independent, so it lives in the container, not `WalletManager`. |
| `Tests/Shared/RatesServiceTests.swift` | The spec's cases 1–11 plus boundaries (equal timestamp, future skew, bad entries, 60 s gate after failure, non-2xx). |
| `Helpers/FiatCurrencyPreference.swift` | Phase 2. `UserDefaults.fiatCurrencyKey` resolution (stored → locale currency if cached → USD), localized names, picker ordering. Pure, tested in `FiatCurrencyPreferenceTests`. |
| `Views/Settings/CurrencySettingView.swift` | Phase 2. Settings sub-page modelled on `ThemeSettingView`: a single right-aligned "1 BTC ≈" caption heading the whole list, then a "None — Show bitcoin amounts only" row, then one row per cached code with localized name and the value of 1 BTC in that currency's own formatting (the caption replaced a per-row "1 BTC ≈" prefix Christoph found repetitive, 2026-09-28); locale currency pinned first; "rates not loaded yet" note on an empty cache; footer with the file time and the required "Rates by Exchange Rate API" link. Reached from a "Currency — Currently: USD" (or "None") row in `SettingsView_iOS`'s General section, visible in read-only mode too. |

## 4. Behaviour

**Networking.** A dedicated `URLSession(configuration: .ephemeral)` with
`httpCookieStorage = nil`, `httpShouldSetCookies = false`, `urlCache = nil`,
15 s timeout. Requests use `.reloadIgnoringLocalCacheData`; revalidation is
done by hand with the stored ETag so the ETag is only ever written together
with a file that passed validation. On `304` only `lastChecked` moves.

**Triggers.** All foreground, all gated on a wallet existing (the modifier
sits on the wallet root, so onboarding makes no request and the launch
contract is untouched):

- appearance of the wallet UI and every return to `.active`, if the last
  attempt was more than 60 s ago;
- a repeating task every 5 minutes while active, cancelled on `.background`;
- pull-to-refresh on the Activity screen (which hosts the total
  `BalanceCard`) and the Balance screen, fire-and-forget so the spinner
  tracks the wallet refresh alone, gated to 60 s, and **also in read-only
  mode** (rates need no Ark server).
- **No** background fetch, no push-triggered fetch, no per-currency requests.
  On a network error nothing is visible; wait for the next trigger.

The 60 s gate counts *attempts*, including failures, so an outage cannot be
hammered by repeated pulls. The persisted `lastChecked` only records
completed checks (200 or 304) — a failed attempt is not a check.

**Persistence.** One JSON file in Application Support (not the Keychain;
this data is not secret and not wallet data). Merged per currency: a new
file overwrites the codes it contains; codes it lacks keep their previous
value **and timestamp**, so a currency that fell out of a file goes stale
on its own clock. An unreadable file (torn write, future schema) starts an
empty cache, never fatal.

**Staleness**, per selected currency, `age = now − snapshot.updatedAt`:

| Age | Freshness | Display (Phase 3) |
|-----|-----------|-------------------|
| `< 15 min` | fresh | fiat shown normally |
| `15 min ≤ age < 24 h` | stale | fiat shown with a subtle indicator ("as of 14:05" or dimmed). No alert, no banner. |
| `≥ 24 h`, or no snapshot | unavailable | fiat hidden, sats only; a short "Price unavailable" where fiat would appear is fine |

**Conversion.** `Decimal` only, never `Double`, for money:

- `fiat = Decimal(sats) × rate ÷ 100_000_000`
- Formatting through `Decimal.FormatStyle.Currency(code:)` so each currency
  gets its own fraction digits (JPY 0, most others 2).
- Typed fiat: `sats = fiat × 100_000_000 ÷ rate`, rounded to the nearest
  whole sat. **From then on the sats value is the source of truth**; never
  recompute it from fiat after a rates refresh.

**Money safety** (binding on Phase 3):

- Send, receive and invoice amounts are always sats. A confirmation screen
  shows sats first and fiat as a secondary "≈".
- A rates refresh while a send is being confirmed must not change the
  amount being sent.
- Never block a payment because rates are missing or stale.

**Currency selection** (Phase 2): default `Locale.current.currency?.identifier`
if present in `availableCurrencies`, else `USD`. Persisted on device. A
chosen code missing from the cache is treated as "no snapshot" → fiat hidden.
**"None"** (stored sentinel `FiatCurrencyPreference.none`, added
2026-09-28 at Christoph's request) is a first-class choice that hides fiat
on every surface; `FiatAmountText` checks it before looking up a rate.

## 5. Decisions and proposals

Decided with the Phase 1 approval (2026-09-28):

- Three deliberate phases: load properly → settings → see how it fits the UI.
- Rates start only once a wallet exists (modifier on the wallet root).
- Pull-to-refresh hooks into both the Activity and Balance screens and runs
  in read-only mode too.
- Fiat conversion is a separate `Decimal` helper, not bolted onto
  `BitcoinFormatter` (which works in `Double` and formats bitcoin units).
- Currency symbols stay locale-aware (standard presentation): US devices
  show "$", the UK/Canada/Australia show "US$"/"USD" for USD because a
  bare "$" is ambiguous there. Decided 2026-09-28 against forcing the
  narrow symbol everywhere; `.presentation(.narrow)` is the one-line
  switch if that ever changes.
- Fiat *entry* (typing a fiat amount) is deferred past Phase 3 and decided
  after display-only fiat has been seen in the UI.

- Credits live in the currency picker's footer, not on a separate About
  screen (decided 2026-09-28 when Phase 2 was narrowed to the picker).

Proposals still awaiting a call (not decisions):

- **Wallet deletion**: `WalletDataCleanupService` removes balance privacy,
  notifications, address icons and proximity keys but leaves theme and unit
  format alone. Proposal: treat `fiatCurrencyKey` like theme and unit format
  — leave it, and leave the rates cache (not wallet data, not secret). Built
  that way for now.
- **`BalanceDetailCard` bypasses `BitcoinFormatter`** (hardcodes
  `formatted() ₿`). Out of scope here; the moment fiat is added to those
  cards is the moment to fix it.

## 6. Verification record

- 2026-09-28: `RatesServiceTests` + `FiatRatesLogicTests` 19/19 on iPhone 17
  Pro simulator (xcodebuild). Full mobile suite: see Open_Follow_Ups for the
  run result.
- 2026-09-28: live check — the real `RatesService` compiled into a macOS
  command-line binary against `rates.arke.cash`: first `refresh()` →
  `.updated(currencies: 30)`, ETag stored, USD `83384.43` exact in Decimal,
  100 000 sats → `$83.38`; second `refresh()` → `.notModified`, `lastChecked`
  advanced. Cache file written as pretty-printed JSON with ISO-8601 dates.
- Owed: on-device look at the X-Ray "Exchange Rates" section on a wallet
  install (the simulator has no wallet, so the trigger never fires there).

## 7. Phases

1. **Loads properly — DONE.** Everything in §3. Visible only in X-Ray.
2. **Settings — BUILT 2026-09-28.** `CurrencySettingView` +
   `FiatCurrencyPreference` + the General-section row; credit in the
   picker footer. Owed: on-device look, translations of the six new
   `settings_currency*` keys.
3. **UI fit, exploratory — IN PROGRESS.** One surface at a time, each
   judged on device before the next.
   - `Shared/UI/FiatAmountText.swift` (built 2026-09-28) is the single
     component for fiat next to sats: resolves the currency, renders
     "≈ $83.38" when fresh, a dimmed "≈ $83.38 · 2 hr. ago" when stale,
     nothing when unavailable. A 60 s `TimelineView` re-evaluates freshness
     so a rate can go stale while the screen sits open. Callers style it.
   - Step 1 — DONE, approved on device 2026-09-28: secondary line directly
     under the big amount on `BalanceCard` (inner stack, zero spacing),
     17 pt rounded, plain white with the amount's shadow; stale dims to 60 %.
   - Step 2 (built 2026-09-28, awaiting Christoph's look): the send amount
     field. `AmountInputSection` (ArkéUI) gained an optional `Accessory`
     slot under the field — the package cannot see the rates service, so
     the app fills it; sats entry capped at 10 digits (was 20).
     `SendAmountFiatLine` (Shared/Views/Send) renders
     `FiatAmountText` in body size on the field's baseline, right-aligned
     in an HStack beside the field, wired into all three flows (manual,
     contact, quick). Present from the start whenever a rate exists: an
     empty/zero field shows "≈ $0.00" in tertiary (placeholder) style so
     nothing pops in on the first keystroke (Christoph's review
     2026-09-28). There is no separate confirmation screen — Send fires from
     this view — so this line *is* the pre-send "≈". Display only; the
     amount string stays the source of truth, so a rates refresh cannot
     change what is sent.
   - Step 3 — DONE, approved on device 2026-09-28: receive.
     `LightningInvoiceFormView_iOS` shows the fiat line 20 pt rounded,
     secondary, directly under the big gold amount, dimmed to 50 % like
     the amount while nothing is typed (present from the start).
     `LightningInvoiceSheet_iOS` shows it 17 pt rounded white under the
     amount in both the owner view and the flipped recipient view. Both
     parse the typed amount with `BitcoinFormatter.parseUserInput`, the
     same parser the view model uses, because the receive field follows
     the unit format (it can hold decimal BTC). The address list
     (`AddressDisplayView`) only encodes the amount, never shows it.
   - Step 4 — DONE, approved on device 2026-09-28: the Balance
     screen's Payments and Savings cards (`BalanceDetailCard`). The fiat
     line sits under the Total amount, right-aligned, body size, white at
     75 % like the row labels (Christoph: secondary, not full white), and
     hidden for a zero total via `FiatAmountText(hidesZero:)` — a static
     "≈ $0.00" adds noise without information;
     Available and Pending rows stay sats-only to keep the card quiet. All
     five amounts in the card now go through `BitcoinFormatter` instead of
     the hardcoded "N ₿" — a visible change on its own: the default format
     puts the symbol in front ("₿ 1,000"), and the Satoshis format now
     reads "1,000 sats" here too.
   - Step 5 — DONE, approved on device 2026-09-29: VoiceOver.
     `FiatAmountText.display(...)` is now the single decision function
     (view + plain string) and every fiat line carries a spoken
     accessibility label — "approximately $85.84", stale: "…, as of 2 hours
     ago" — instead of VoiceOver reading "≈" as a symbol. The Activity
     screen's balance card container value reads "₿ 1,000, approximately
     $85.84" (sats only when no fiat shows, "Hidden" in privacy mode).
   - Next candidates: transaction detail (needs the "today's rate" wording
     decision), transaction rows.
4. **Fiat input — IN PROGRESS (started 2026-09-29, receive first).**
   Transaction detail/rows parked (the "today's rate" question). Decisions
   taken with Christoph 2026-09-29: fiat big and gold in fiat mode with
   bitcoin as the secondary line beneath (receive spends nothing); input
   mode is per-session, not remembered; the German bitcoin partial-display
   glitch gets fixed in passing.

   **Step 1 — groundwork, DONE 2026-09-29 (no visible change except two
   fixes):**
   - `ReceiveViewModel.amountSats: Int?` is the single source of truth for
     the invoice, the QR sheet and every payment link; `amount` (bitcoin
     unit-format string) is now only an editing buffer.
   - `BIP21URIHelper.createBIP21URI(amountSats: Int?)` (was `String?`),
     `ReceiveQRContentHelper`, `AddressDisplayView`, and
     `LightningInvoiceSheet_iOS` all take sats. **Fixes the pre-existing
     bug** where the unit-format string ("0.001") was passed as a sats
     string, failed `Int(...)`, and the amount was silently dropped from
     every BIP-21 link (and shown raw on the sheet) under a decimal unit
     format. Desktop `ReceiveView` updated to match.
   - `CustomNumericKeypad_iOS` (ArkéUI) takes `decimalPlaces: Int?` (8 for
     bitcoin, a currency's minor units for fiat, nil/0 hides the key) and
     shows the **device locale's decimal separator** on the key (","
     in Germany) while still writing "." into the bound string, so one
     parser serves everything. The `showPeriod` inits remain and map to 8.
   - `BitcoinFormatter.formatPartialDecimalInput` (ArkéUI) now groups the
     integer part and uses the locale's separator — a German device sees
     "₿ 0,5" while typing, not "₿ 0.5" (**second fix**).
   - `FiatConversion` gains the entry helpers: `fractionDigits(for:)`
     (USD 2, JPY 0, KWD 3 via the system currency formatter),
     `parseInput` (machine form → Decimal), `formatPartialInput` (typed
     digits only, locale separator/placement, trailing separator kept:
     "12." → "$12.", de_DE "12.5" → "12,5 $"), `inputString(for:currency:)`
     (back-fill a buffer, trimmed to minor units). `FiatInputTests` 6/6.

   **Step 2 — fiat mode on the receive form, DONE, approved on device
   2026-09-29:**
   - `AmountEntryState` (Shared/Helpers, pure, 8 tests): mode, the two
     machine-form buffers, and `fiatSats` captured at the last fiat
     keystroke. `setFiatInput` recomputes sats once at the given rate;
     `switchToFiat` / `switchToBitcoin` carry the exact sats over and
     back-fill the incoming buffer (fiat trimmed to minor units via
     `FiatConversion.inputString`, bitcoin via the new
     `BitcoinFormatter.inputString(forSatoshis:)`); `reset()` returns to
     bitcoin mode. A rates refresh never touches `fiatSats`.
   - `ReceiveViewModel.entry` holds it; `amount` became a computed
     property over the bitcoin buffer so the bitcoin-only desktop views
     bind unchanged; `amountSats` reads the entry state.
   - `LightningInvoiceFormView_iOS` takes the view model. The secondary
     line under the big gold number is a button: in bitcoin mode it is the
     fiat "≈" line (only when a rate exists) and tapping it makes fiat the
     field; in fiat mode it is the bitcoin amount and tapping swaps back.
     The keypad binds to the active buffer, allows the currency's minor
     units in fiat mode (JPY hides the separator key), caps at 1 BTC on
     the resulting sats in both modes, and the form falls back to bitcoin
     mode when the rate becomes unavailable or the currency is set to
     "None". Fiat entry uses the same availability decision as every fiat
     line (`FiatAmountText.display`), so entry and display agree.
   - Review round 2026-09-29 (Christoph): both numbers tap to swap, not
     just the small one; the QR sheet leads with fiat (bitcoin beneath)
     when the amount was typed in fiat and a fiat value can be shown —
     the invoice itself is unchanged sats; the small line rolls its digits
     in step with the big one.
   - Correction: the groundwork commit (c6896d0) *claimed* the German
     partial-display fix in `BitcoinFormatter`, but that edit had not
     persisted to disk; it lands with step 2.
   - **Invoice ceiling (Christoph's question 2026-09-29, "why can I only
     type 5–6 euro digits?")**: it was the keypad's hard-coded 1 BTC cap
     (≈ 73,500 € at the time), and the view model had a second, unrelated
     0.1 BTC cap. Neither was technical: `git log -S` traces them to the
     2025-12-03 receive port ("reasonable limits") and the 2026-05-29
     decimal-input change. The real ceiling is the Ark server's
     `max_vtxo_amount` — `server/src/ln/mod.rs` refuses larger Lightning
     receives with "Requested amount exceeds limit", the same setting
     bounds boards and refreshes, it is optional per server (the default
     config ships it commented out at 0.01 BTC as an example), and the
     server advertises it in `ArkInfo` (X-Ray shows it as "Max VTXO
     Amount"). **Decided:** both caps now derive from
     `ReceiveViewModel.maxInvoiceSats = arkInfo?.maxVtxoAmount`; nil means
     only the keypad's 10-digit cap applies and the server judges. The
     view model's late error names the server's limit. The keypad fires a
     warning haptic whenever a key is refused (digit cap, fraction cap, or
     the ceiling) instead of dropping it silently.

   **Step 3 — port to the send field** (system text field with a decimal
   pad rather than the keypad, so separator handling differs). Desktop
   receive/send stay bitcoin-only until then.
