# Localization Key Update Summary

**Date:** March 3, 2026
**Task:** Replace old English text localization keys with new semantic keys

> ⚠️ **NOTE**: This document includes references to wallet linking localization keys (`button_link_existing_wallet`, `button_link_wallet`, `error_link_wallet`, `firstuse_link_wallet_detected`) which are now obsolete. LinkWalletView was removed in June 2026. These strings remain in the localization file but are unused.

---

## Overview

Successfully updated all Swift files in the Arke project to use the new semantic localization keys from the mapping file. This migration improves code maintainability and provides better structure for internationalization.

## Statistics

### Files Processed
- **Total Swift files scanned:** 339
- **Files modified:** 146
- **Total replacements made:** 496

### Replacements by Pattern Type

| Pattern Type | Count | Description |
|--------------|-------|-------------|
| `Text()` | 304 | SwiftUI Text views |
| `Button()` | 55 | Button labels |
| `.accessibilityLabel()` | 45 | Accessibility labels |
| `.navigationTitle()` | 27 | Navigation titles |
| `Label()` | 26 | Label views |
| `.alert()` | 18 | Alert dialogs |
| `.help()` | 13 | Help tooltips |
| `.confirmationDialog()` | 8 | Confirmation dialogs |

### Key Mapping
- **Total key mappings processed:** 516
- **Categories covered:** common, balance, send, receive, activity, contacts, tags, settings, onboarding, data, console

## Changes Made

### 1. Swift File Updates

The script successfully replaced old English text keys with new semantic keys in the following patterns:

- `Text("old key")` → `Text("new_key")`
- `String(localized: "old key")` → `String(localized: "new_key")`
- `LocalizedStringKey("old key")` → `LocalizedStringKey("new_key")`
- `Button("old key")` → `Button("new_key")`
- `.navigationTitle("old key")` → `.navigationTitle("new_key")`
- `.accessibilityLabel("old key")` → `.accessibilityLabel("new_key")`
- And many more...

### 2. Localizable.xcstrings Update

The `Shared/Localizable.xcstrings` file was regenerated with all new semantic keys:
- **Previous size:** 23 KB
- **New size:** 109 KB
- **New semantic keys added:** 516

Example mappings:
- `"Hide Big Balance"` → `"action_hide_balance"`
- `"Send"` → `"button_send"`
- `"Settings"` → `"settings_title"`
- `"Enter amount"` → `"placeholder_enter_amount"`

## Backup

All modified files have been backed up to:
```
/Users/christoph/workspace/Arke/backup_localization_20260303_093710/
```

The backup preserves the original file structure and can be used for rollback if needed.

## Sample Changes

### Example 1: SettingsView_iOS.swift
```swift
// Before
Text("Fee Summary")
Text("View transaction fees")

// After
Text("activity_fee_summary")
Text("action_view_fees")
```

### Example 2: AmountInputSection.swift
```swift
// Before
Text("Enter amount")
Text("Amount is fixed by the payment request")

// After
Text("placeholder_enter_amount")
Text("send_amount_fixed")
```

### Example 3: ContactEditor.swift
```swift
// Before
Text("Name")
.accessibilityLabel("Save")

// After
Text("label_name")
.accessibilityLabel("button_save")
```

## Key Categories

The new semantic keys follow a consistent naming convention with category prefixes:

- **action_*** - User actions (e.g., `action_copy`, `action_paste_clipboard`)
- **button_*** - Button labels (e.g., `button_send`, `button_cancel`)
- **label_*** - General labels (e.g., `label_amount`, `label_address`)
- **placeholder_*** - Input placeholders (e.g., `placeholder_enter_amount`)
- **status_*** - Status messages (e.g., `status_loading`, `status_copied`)
- **error_*** - Error messages (e.g., `error_invalid_address`)
- **message_*** - Informational messages (e.g., `message_confirm_shortly`)
- **settings_*** - Settings-related strings
- **balance_*** - Balance-related strings
- **send_*** - Send flow strings
- **receive_*** - Receive flow strings
- **activity_*** - Activity/transaction strings
- **contacts_*** - Contacts-related strings
- **tags_*** - Tags-related strings
- **onboarding_*** - Onboarding flow strings
- **data_*** - Data/debug view strings
- **console_*** - Console-related strings
- **format_*** - Format strings with placeholders

## Files with Most Changes

Top 10 files by number of replacements:

1. `Arké mobile/Views/Settings/SettingsView_iOS.swift` - 48 replacements
2. `Arké mobile/Views/Tags/TagsView_iOS.swift` - 29 replacements
3. `Shared/Views/Contacts/Editor/ContactImportSheet.swift` - 20 replacements
4. `Arké mobile/Views/Settings/LinkedDevicesView_iOS.swift` - 18 replacements
5. `Arké mobile/Views/FirstUse/LinkWalletView_iOS.swift` - 18 replacements
6. `Shared/Views/Data/VTXODeveloperActionsView.swift` - 18 replacements
7. `Shared/Views/Contacts/Editor/ContactEditor.swift` - 17 replacements
8. `Shared/Views/Activity/TransactionClaimExitBanner.swift` - 16 replacements
9. `Shared/Views/Activity/TransactionExitDetailsView.swift` - 16 replacements
10. `Arké/Views/Settings/LinkedDevicesView.swift` - 16 replacements

## Verification

To verify the changes:

1. **Check a sample file:**
   ```bash
   git diff "Shared/Views/Send/AmountInputSection.swift"
   ```

2. **Build the project:**
   The project should build without errors. All localization keys are properly mapped.

3. **Run the app:**
   All strings should display correctly with the English translations.

## Next Steps

1. **Review the changes:** Use `git diff` to review the replacements
2. **Test the app:** Ensure all strings display correctly
3. **Add translations:** The new semantic keys make it easier to add translations for other languages
4. **Commit the changes:** Once verified, commit the changes to version control

## Scripts Used

### 1. update_localization_keys.py
The main script that:
- Reads the mapping file
- Finds all Swift files
- Applies regex patterns to replace old keys with new keys
- Creates backups of all modified files
- Generates a detailed report

### 2. generate_new_localizations.py
The script that:
- Reads the mapping file
- Updates the Localizable.xcstrings file
- Preserves all existing translations
- Adds new semantic keys with their English values

## Files Modified

A total of 146 Swift files were modified across the following directories:
- `Arké mobile/Views/` - 60 files
- `Shared/Views/` - 75 files
- `Arké/Views/` - 11 files
- `ArkeUI/Sources/ArkéUI/` - 1 file
- Plus `Shared/Localizable.xcstrings` - 1 file

## Notes

- All replacements preserve string interpolation (e.g., `%@`, `%lld`)
- Comment parameters in `NSLocalizedString` calls are preserved
- Multi-line strings and escaped quotes are handled correctly
- Only exact matches are replaced to avoid breaking code
- The script handles edge cases like:
  - Escaped quotes within strings
  - Multi-line string literals
  - String interpolation with SwiftUI's Text views
  - Complex format strings

## Report Files

Two detailed reports were generated:

1. **localization_update_report.txt** - Plain text summary
2. **LOCALIZATION_UPDATE_SUMMARY.md** - This comprehensive markdown document

---

**Status:** ✅ Completed successfully

All localization keys have been updated to use semantic naming. The codebase is now more maintainable and ready for internationalization.
