# Theme System

**Status:** Shipped 2026-08-20/21 (4 themes, all surfaces, both platforms). Written 2026-09-27 against the code; supersedes the archived colour-first plan (`../Archive/Implementations/theme-system-implementation.md`, never built).

A theme is a bundle of background images plus one text colour. Themes do **not** change the colour palette — that is a deferred, separate item (Open_Follow_Ups → Themes). Everything lives in two files:

- `Shared/Helpers/AppTheme.swift` — the `AppTheme` enum and the `ThemeImages` struct. The only place that names theme assets.
- `Shared/Views/Settings/ThemeSettingView.swift` — the picker (two-column grid of card thumbnails), embedded by both `SettingsView_iOS` and the desktop `SettingsView` (`SettingsDetailItem.theme`). There is no platform-specific picker.

## The themes

| Case | Display name key | Hidden-card text colour |
|---|---|---|
| `classic` (default) | `theme_name_classic` | Arké gold (no override) |
| `ginkgo` | `theme_name_ginkgo` | `F3F4F2` |
| `purpleLines` | `theme_name_purple_lines` | `FBE8EF` |
| `floralPattern` | `theme_name_floral_pattern` | `FFFFCD` |

Names are localized with `defaultValue:` and have de/ja/zh-Hant entries (needs_review like the rest of the catalog).

## Themed surfaces (`ThemeImages`)

| Field | Where it shows |
|---|---|
| `card`, `cardMask` | Balance card on the activity screen (`Shared/UI/BalanceCard.swift`); the mask drives the holographic effect |
| `hiddenCard`, `hiddenCardMask` | The card while the balance is hidden (privacy mode). `nil` mask = flat, no holo; classic is flat, the other three have masks. The cornfield/unicorn format easter eggs deliberately override the hidden image |
| `tiltBackground` | Full-screen background of the tilt-to-share overlay (`TiltShareOverlay_iOS`) |
| `keypadTexture` | Texture behind the numeric keypad in the receive flow (`LightningInvoiceFormView_iOS`) |
| `qrBackground` | Background behind the receive QR (`LightningInvoiceSheet_iOS`) |
| `balanceBackground` | Full-screen background of `BalanceView_iOS` |

`AppTheme.textColor` colours the "Arké" wordmark on the hidden card; the holo sheen itself stays hard-coded gold by decision.

## Persistence and observation

- Stored in `UserDefaults` under `UserDefaults.appThemeKey` as the enum's raw value.
- Views read it with `@AppStorage(UserDefaults.appThemeKey)` so they update live when the picker changes; non-view code uses `AppTheme.current` (falls back to `.classic` on a missing or unknown value).
- The setting is device-local — it is not synced through iCloud.

## Assets

All theme imagesets live in `Shared/Media.xcassets`, which both app targets own (asset dedup of 2026-08-21; per-target catalogs hold only icons and colours). Asset name pattern: `<theme>-card`, `<theme>-card-mask`, `<theme>-card-hidden`, `<theme>-card-hidden-mask`, `<theme>-tilt-back`, `<theme>-keypad`, `<theme>-invoice-back`, `<theme>-balance-back`. Classic keeps its historical names (`card`, `card-mask`, `tuscan-villa`, `tuscan-villa-portrait`, `black-marble`, `card-big`).

## Adding a theme

1. Add the eight imagesets to `Shared/Media.xcassets` following the name pattern (thumbnail in the picker is the `card` image, 3:2).
2. Add a case to `AppTheme` with its `ThemeImages`, a `theme_name_<x>` display name, and an optional `textColorHex` for the hidden wordmark.
3. Build once so the string catalog extracts the new key; then run the translation scripts (`Scripts/apply_translations.py`) for de/ja/zh-Hant.
4. Verify on device: activity card (shown + hidden), balance view, tilt overlay, receive keypad, receive QR.

## Open

- Per-theme colour palettes (deferred by design).
- Visual pass of the picker on macOS.
- `arke-qr-background` in `Media.xcassets` is referenced nowhere; delete if there are no plans for it.
