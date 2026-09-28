# Fiat Rates

Fiat values next to sats, from one public static file that holds every
currency. Sats are the real amount; fiat is display only.

**Status: Phase 1 DONE 2026-09-28 (committed f2f002e); Phase 2 currency
picker BUILT 2026-09-28, uncommitted** — client, cache, triggers and X-Ray
section shipped; 19/19 unit tests green on iOS; live server check passed
(200 → 30 currencies + ETag, then 304). The Settings → Currency picker
carries the required credit in its footer, so no About screen is needed
(Christoph's call 2026-09-28). 24/24 tests with the preference suite.
Phase 3 open — see §7. Nothing outside the picker shows fiat yet, by design.

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
| `Views/Settings/CurrencySettingView.swift` | Phase 2. Settings sub-page modelled on `ThemeSettingView`: one row per cached code with localized name and "1 BTC ≈ …" in that currency's own formatting; locale currency pinned first; "rates not loaded yet" note on an empty cache; footer with the file time and the required "Rates by Exchange Rate API" link. Reached from a "Currency — Currently: USD" row in `SettingsView_iOS`'s General section, visible in read-only mode too. |

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

## 5. Decisions and proposals

Decided with the Phase 1 approval (2026-09-28):

- Three deliberate phases: load properly → settings → see how it fits the UI.
- Rates start only once a wallet exists (modifier on the wallet root).
- Pull-to-refresh hooks into both the Activity and Balance screens and runs
  in read-only mode too.
- Fiat conversion is a separate `Decimal` helper, not bolted onto
  `BitcoinFormatter` (which works in `Double` and formats bitcoin units).
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
   - Next candidates: `BalanceDetailCard` rows (fix its `BitcoinFormatter`
     bypass while there), transaction detail (needs the "today's rate"
     wording decision), transaction rows, receive/invoice amounts, the
     balance card's accessibility value.
4. **Later, separately decided:** fiat entry in the send flow; desktop UI
   (the service already compiles there — see `Desktop_Parity.md`).
   Christoph's direction 2026-09-28: finish fiat *display* in all the right
   places first, then look at fiat *input*. Sketch for input, from the
   review of step 2: tapping the fiat text swaps roles (fiat becomes the
   field, sats the right-hand line); sats string stays the source of
   truth, recomputed once per fiat keystroke at that moment's rate and
   never on a rates refresh; Max/locked amounts back-fill fiat from sats;
   decimal pad with the currency's fraction digits; fall back to sats mode
   if the rate becomes unavailable; sats line primary/medium in fiat mode
   so the true amount stays prominent. Structurally: pass rate + currency
   into `AmountInputSection` as plain values, move `FiatConversion` into
   ArkéUI, drop the accessory slot.
