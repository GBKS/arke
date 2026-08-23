# Localization Guidelines - Arké

This document is the single source of truth for localization in the Arké project: where strings live, how keys are named, and the rules that keep `Localizable.xcstrings` healthy. Accessibility-specific guidance (VoiceOver labels, hints, values) lives in `Shared/Docs/Features/Accessibility.md`, which follows the key conventions defined here.

---

## Where Strings Live

| Location | Used by | Notes |
|----------|---------|-------|
| `Shared/Localizable.xcstrings` | ArkeMobile, ArkeDesktop, widgets | The main string catalog. Source language is English (`en`). |
| `ArkeUI/Sources/.../Localizable.xcstrings` | ArkéUI package views | Package strings **must** be looked up with `bundle: .module`, otherwise raw keys render. When a key exists in both catalogs, copy the canonical English value from the Shared catalog. |

---

## Key Naming Convention

All keys are **semantic snake_case identifiers**, not English sentences. The codebase was migrated to this scheme in March 2026 (see `LOCALIZATION_MIGRATION_SUMMARY.md` and `LOCALIZATION_UPDATE_SUMMARY.md` in this folder). Plain-English keys are a leftover anti-pattern and should be migrated to semantic keys when touched.

**Pattern:** `{prefix}_{descriptor}` — e.g. `button_cancel`, `balance_move_to_savings`.

### Generic Prefixes (cross-feature)

Use these when the string could appear in more than one feature:

| Prefix | Use for | Example |
|--------|---------|---------|
| `button_` | Common button labels | `button_cancel` → "Cancel" |
| `action_` | Context-specific actions (`action_{verb}_{object}`) | `action_copy_address` → "Copy address" |
| `label_` | Field and section labels | `label_amount` → "Amount" |
| `nav_title_` | Navigation titles | `nav_title_receive` → "Receive Bitcoin" |
| `placeholder_` | Text field placeholders | `placeholder_enter_amount` → "Enter amount" |
| `status_` | Status and progress messages | `status_copied_exclaim` → "Copied!" |
| `progress_` | Loading/progress text | `progress_loading` → "Loading..." |
| `error_` | Error messages | `error_invalid_address` |
| `alert_` | Alert titles and bodies | `alert_delete_item` |
| `message_` | Informational messages | `message_cannot_undo` |
| `help_` | Tooltips (`.help()`) | `help_clear_filter` |
| `desc_` | Longer descriptions | `desc_maintenance_task` |
| `section_` | Section headers | `section_device_role` |
| `network_` | Network names | `network_lightning` → "Lightning" |
| `notification_` | Push notification content | `notification_vtxo_refresh_title` |
| `format_` | Reusable format strings with placeholders | `format_address_number` → "Address #%lld" |
| `symbol_` | Standalone symbols | `symbol_bullet` → "•" |
| `suffix_` | Text fragments appended to values | `suffix_minimum` |
| `app_name` | The app name (single key) | "Arké" |

### Accessibility Prefixes

Defined in detail in `Accessibility.md`:

| Prefix | Use for |
|--------|---------|
| `accessibility_` | VoiceOver labels for non-action elements |
| `accessibility_hint_` | Hints explaining what an action does |
| `accessibility_value_` | State values (toggles, selections) |

### Feature Prefixes

Use these when the string belongs to one feature area:

`activity_`, `backup_`, `balance_`, `console_`, `contacts_`, `data_`, `debug_logs_`, `fee_`, `firstuse_`, `linked_devices_`, `maintenance_`, `onboarding_`, `profile_`, `receive_`, `send_`, `settings_`, `tags_`, `testing_`, `transaction_list_`

**Choosing a prefix:** prefer a generic prefix if the string is (or could be) reused across features; use a feature prefix for feature-specific copy. Before adding any key, search the catalog for an existing key with the same value — reuse it instead of creating a duplicate.

### Exception: Interpolated Strings

SwiftUI string interpolation auto-generates format keys, which are natural-language by design:

```swift
Text("Change tags: \(tags.count) tags selected")
// catalog key: "Change tags: %lld tags selected"
```

This is the **only** sanctioned use of plain-English keys. Keep them rare; if the same format string is needed in several places, promote it to a semantic `format_` key and use `String(format: String(localized: "format_..."), value)`.

You can keep semantic naming even with interpolation by starting the string with the key — the pattern used in ArkéUI:

```swift
Text("status_last_synced \(date)", bundle: .module)
// catalog key: "status_last_synced %@"
```

---

## Rules

### 1. Every key must have an explicit English value

A key referenced in code but lacking an `en` value renders as the raw key in the UI (e.g. users literally see "button_go_back"). Call sites using `defaultValue:` (see Usage in Code) satisfy this rule automatically — extraction fills the `en` value from the code.

```json
// ❌ WRONG — renders the key itself
"action_assign_contact" : {

}

// ✅ CORRECT
"action_assign_contact" : {
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Assign contact"
      }
    }
  }
}
```

### 2. No duplicate values under different keys

One meaning, one key. "Cancel" is `button_cancel` — do not add a second key (or a literal `"Cancel"` key) with the same value. Exception: identical values with genuinely different meanings or grammatical contexts in other languages may stay separate.

### 3. Count-bearing strings need plural variations

Any string containing `%lld`/`%u`/`%llu` that describes a quantity must use plural variations, otherwise English shows "1 transactions":

```json
"tags_transaction_count" : {
  "localizations" : {
    "en" : {
      "variations" : {
        "plural" : {
          "one" : { "stringUnit" : { "state" : "translated", "value" : "%lld transaction" } },
          "other" : { "stringUnit" : { "state" : "translated", "value" : "%lld transactions" } }
        }
      }
    }
  }
}
```

Strings where the number is an identifier, not a quantity ("Block %u", "Invoice #%lld"), do not need variations.

### 4. Mark non-translatable strings

Set `"shouldTranslate" : false` on entries that must never be translated: `app_name`, `symbol_*` keys, and pure format strings like `"%@"` or `"~%@"`. This prevents wasted translator effort once other languages are added.

### 5. No sentence assembly by concatenation

Never build user-facing text by joining fragments in code — word order differs across languages. Keys with leading/trailing whitespace (e.g. `" per month"`) are a symptom of this. Use a full sentence with placeholders instead:

```swift
// ❌ WRONG
Text(amount) + Text(" per month")

// ✅ CORRECT
Text("format_amount_per_month")   // "%@ per month"
```

### 6. Add translator comments for ambiguous strings

Short strings like "Change", "State", or "Input" are ambiguous without context. Add a `comment` in the catalog (or via the `comment:` parameter) describing where the string appears and what it refers to.

---

## Usage in Code

### Mandatory: `defaultValue:` (or an `L10n` accessor)

The August 2026 migration (see `Default_Value_Migration_Plan.md`) moved the English
copy for every call site into code. All strings use `String(localized:defaultValue:)`,
keeping the English copy in code next to the key:

```swift
Text(String(localized: "settings_address_patterns_toggle",
            defaultValue: "Show address patterns"))

// Interpolation works inside defaultValue
Text(String(localized: "settings_devices_connected",
            defaultValue: "\(deviceCount) devices connected"))

// ArkéUI package views — bundle is still required
String(localized: "key_name", defaultValue: "Value", bundle: .module)
```

Why this is preferred:

- **Survives catalog rewrites.** Xcode regenerates the catalog on every build (see Catalog Maintenance); with `defaultValue:` the English copy lives in code and re-extraction repopulates the catalog instead of potentially emptying it.
- **No raw-key failure mode.** A missing catalog entry falls back to correct English instead of rendering the key (Rule 1 becomes impossible to violate for `en`).
- **Readable call sites.** Reviewers see the actual copy without cross-referencing the catalog.

The trade-off: **English copy edits must be made in code.** Hand-editing the `en` value in the catalog editor for a `defaultValue:`-backed key gets overwritten by the next build's extraction.

**Rules (post-migration, August 2026):**

1. **Every string carries its English in code** — `defaultValue:` at the call site,
   or an `L10n` accessor. Bare keys are a regression; do not add new ones.
2. **Keys used at 3+ call sites** get one static accessor in the module's `L10n`
   enum (`Shared/Helpers/L10n.swift` for app targets, `ArkeUI/.../Helpers/L10n.swift`
   package-internal) instead of duplicating the `defaultValue:` — one definition
   point prevents copy drift. 1–2 sites: inline, with identical copy.
3. **Custom view parameters take localized `String`, never `LocalizedStringKey`.**
   `LocalizedStringKey` params silently resolve against `Bundle.main` regardless of
   which module renders them, and a call site passing a literal key to a `String`
   param renders the raw key. Callers pass `String(localized:defaultValue:)`.
4. **Ternaries** localize each branch: `cond ? String(localized:...) : String(localized:...)`.
   (The pre-migration advice to wrap branches in `LocalizedStringKey(...)` is obsolete.)
5. Key naming rules above apply unchanged; `defaultValue:` does not excuse
   plain-English keys.

```swift
// ArkéUI package views — bundle is still required
String(localized: "key_name", defaultValue: "Value", bundle: .module)
```

### Exceptions: keys that stay catalog-managed

- **Plural-variation keys** (and substitution keys like
  `balance_vtxos_expired_and_expiring %lld %lld`): variations cannot be expressed in
  a `defaultValue:`, so their English lives in the catalog's `variations` dictionary.
  Call sites may still pass `defaultValue:` for the base form; never hand-edit the
  variations expecting code to restore them.
- **Sanctioned plain-English interpolation keys** (`"%lld transactions"`, `"%@ ago"`)
  per the Interpolated Strings exception above.

---

## Catalog Maintenance

**Xcode rewrites `Localizable.xcstrings` on every IDE build** (command-line
`xcodebuild` compiles but does not merge extraction back into the source catalog,
and extraction is per-scheme — desktop-only keys need a desktop build).
Re-extraction re-sorts the file, marks keys it no longer finds in code as
`"extractionState" : "stale"`, and can empty hand-added values for keys it cannot
match to a call site. Consequences:

- After hand-editing the catalog, **build and re-verify** that your values survived.
- Prefer fixing the code side (pointing call sites at existing keys, or adding `defaultValue:`) over hand-adding values.
- For `defaultValue:`-backed keys, code is the source of truth for `en` — edit the copy in code, never in the catalog editor. **Caveat (verified 2026-08-18):** entries that predate the migration (state `translated`, no `extractionState`) do NOT auto-follow code edits. When changing such a key's English, also delete its catalog entry — the next IDE build re-adds it as `extracted_with_value`, after which code edits propagate. Entries born from extraction (`extracted_with_value`) follow code automatically.
- Periodically purge stale entries in Xcode's catalog editor (filter by "Stale", then delete). Confirm a key is not constructed dynamically before deleting it.

### Audit Checklist

Run occasionally, and before starting translation work:

- [ ] No active key referenced in code lacks an `en` value (renders raw keys — see Rule 1)
- [ ] No duplicate values across active keys (see Rule 2)
- [ ] Count strings have plural variations (see Rule 3)
- [ ] Stale entries purged
- [ ] No keys with leading/trailing whitespace or empty keys
- [ ] `shouldTranslate` set on symbols, format-only strings, and the app name
- [ ] Keys present in both the Shared and ArkéUI catalogs have identical English values (Shared is canonical) — if values drift, the same key shows different text depending on whether a package view or an app view renders it

---

## Translations (de, ja — August 2026; zh-Hant — August 2026)

German, Japanese, and Traditional Chinese values exist for every translatable
key (state `needs_review` until natively reviewed). Rules:

- **Translations live in the catalogs and are edited there** (Xcode's catalog
  editor) — the code-is-source-of-truth rule applies to English only.
- Terminology is governed by `Translation_Glossary.md` — one meaning, one term.
  German uses **du**; Japanese uses です・ます; zh-Hant uses plain 你 and
  Taiwan conventions (Apple's zh-Hant flavor; covers Hong Kong via fallback).
- **New strings ship English-only** (they fall back correctly via
  `defaultValue:`); add translations via `Scripts/apply_translations.py`
  (JSON in, any language codes → all catalogs, `needs_review`) or in the
  catalog editor during the next review cycle.
- `Scripts/translation_lint.py` prints guard violations (empty values,
  format-specifier mismatches vs English) with exact keys — the same invariants
  `LocalizationCatalogTests` enforces in CI.
- Japanese and Chinese have no plural forms; `^[…](inflect: true)` in English
  values is English-only, so German needs explicit plural variations for those
  keys while ja/zh-Hant collapse to a single form (measure words: 件 in ja,
  筆/部/個 in zh-Hant).

## Tooling

- `Scripts/localization_audit.py` — cross-references both catalogs against all call
  sites; reports missing English, drift, unreferenced keys, hardcoded-English
  candidates. Rerun before translation work or after large string changes.
- `Tests/Shared/LocalizationCatalogTests.swift` — permanent guard: every active
  snake_case key has English; no cross-catalog drift; no whitespace keys.
- `Scripts/migrate_defaultvalue.py` — the mechanical migration passes (kept for
  reference / future sweeps).

## History

- **March 2026:** Migration from English-text keys to semantic snake_case keys (516 keys, 146 files). See `LOCALIZATION_MIGRATION_SUMMARY.md` and `LOCALIZATION_UPDATE_SUMMARY.md`.
- **August 2026:** defaultValue migration — English copy moved into code at 1,252
  call sites (93%; the rest are plural-variation and sanctioned plain-English keys),
  per-module `L10n` accessors added, 51 dead keys purged, guard test added. See
  `Default_Value_Migration_Plan.md`.
