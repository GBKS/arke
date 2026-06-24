# Accessibility Best Practices - Arké

This document outlines the accessibility standards and patterns used in the Arké project. Follow these guidelines when implementing or reviewing UI components.

---

## Core Principles

1. **All user-facing text must be localized** - No hardcoded English strings
2. **Interactive elements must have clear labels** - Users should understand what each button/control does
3. **Provide context through hints** - Explain what happens when an action is taken
4. **Expose state through values** - Show current selections, status, or progress
5. **Use semantic naming** - Follow established key naming conventions

---

## Localization Key Naming Conventions

All accessibility strings must follow these naming patterns:

### 1. Actions (Buttons, Interactive Elements)
Use `action_` prefix for button labels and interactive element labels:
```swift
.accessibilityLabel("action_change_contact")
.accessibilityLabel("action_assign_tags")
.accessibilityLabel("action_send_address")
```

**Pattern:** `action_{verb}_{object}`

**Examples:**
- `action_change_contact` → "Change contact"
- `action_assign_tags` → "Assign tags"
- `action_show_qr` → "Show QR code"

### 2. Generic Buttons
Use `button_` prefix for common button actions:
```swift
.accessibilityLabel("button_cancel")
.accessibilityLabel("button_save")
.accessibilityLabel("button_apply")
```

**Pattern:** `button_{action}`

**Examples:**
- `button_cancel` → "Cancel"
- `button_save` → "Save"
- `button_done` → "Done"

### 3. Accessibility Hints
Use `accessibility_hint_` prefix for hints that explain what happens:
```swift
.accessibilityHint(LocalizedStringKey("accessibility_hint_assign_contact"))
```

**Pattern:** `accessibility_hint_{action}_{object}`

**Examples:**
- `accessibility_hint_assign_contact` → "Opens contact selector"
- `accessibility_hint_assign_tags` → "Opens tag selector"
- `accessibility_balance_hint` → "Tap to view balance details. Long press to toggle balance visibility."

### 4. Accessibility Values
Use `accessibility_value_` prefix for state indicators:
```swift
.accessibilityValue(LocalizedStringKey("accessibility_value_note_present"))
```

**Pattern:** `accessibility_value_{state_description}`

**Examples:**
- `accessibility_value_note_present` → "Note added"
- `accessibility_balance_hidden` → "Balance hidden"

### 5. Accessibility Labels (Non-actions)
Use `accessibility_` prefix for descriptive labels and status:
```swift
.accessibilityLabel("accessibility_balance_label")
```

**Pattern:** `accessibility_{element_description}`

**Examples:**
- `accessibility_balance_label` → "Wallet Balance"
- `accessibility_connection_status_label` → "Connection Status"

### 6. Status Messages
Use `status_` prefix for status indicators:
```swift
.accessibilityLabel(String(localized: "status_copied_exclaim"))
```

**Pattern:** `status_{state}`

**Examples:**
- `status_copied_exclaim` → "Copied!"
- `accessibility_connection_poor` → "Poor connection"

---

## Implementation Patterns

### Basic Button with Label
```swift
Button("Save") {
    // action
}
.accessibilityLabel("button_save")
```

### Action Button (Context-Specific)
```swift
Button {
    showContactSelector = true
} label: {
    Image(systemName: "person.fill")
}
.accessibilityLabel(hasContact ?
    LocalizedStringKey("action_change_contact") :
    LocalizedStringKey("action_assign_contact"))
```

### Button with Hint
```swift
Button("Assign Contact") {
    // action
}
.accessibilityLabel("action_assign_contact")
.accessibilityHint(LocalizedStringKey("accessibility_hint_assign_contact"))
```

### Element with State Value
```swift
Button("Note") {
    showNoteEditor = true
}
.accessibilityLabel(hasNote ?
    LocalizedStringKey("action_change_note") :
    LocalizedStringKey("action_assign_note"))
.accessibilityHint(LocalizedStringKey("accessibility_hint_assign_note"))
.accessibilityValue(hasNote ?
    LocalizedStringKey("accessibility_value_note_present") : "")
```

### Dynamic Labels with String Interpolation
When labels include dynamic content, use `String(localized:)`:

```swift
private var tagsAccessibilityLabel: String {
    let tags = metadata.associatedTags
    if tags.isEmpty {
        return String(localized: "action_assign_tags")
    } else if tags.count == 1 {
        return String(localized: "Change tags: \(tags[0].name)")
    } else {
        return String(localized: "Change tags: \(tags.count) tags selected")
    }
}
```

Corresponding localization entries:
```json
"Change tags: %@" : {
  "value" : "Change tags: %@"
},
"Change tags: %lld tags selected" : {
  "value" : "Change tags: %lld tags selected"
}
```

---

## Localization String Requirements

Every localization key used in code **must** have a value defined in `Localizable.xcstrings`:

```json
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

### ❌ Incorrect (Empty Value):
```json
"action_assign_contact" : {

}
```

### ✅ Correct (With Value):
```json
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

---

## SwiftUI Modifiers

### Essential Modifiers

#### `.accessibilityLabel()`
Provides the primary text read by VoiceOver.

**When to use:**
- All buttons without visible text labels
- Interactive elements with icons
- Custom controls

**Examples:**
```swift
// Simple string key
.accessibilityLabel("button_cancel")

// LocalizedStringKey for dynamic switching
.accessibilityLabel(LocalizedStringKey("action_assign_tags"))

// Conditional label
.accessibilityLabel(isSelected ?
    LocalizedStringKey("action_change_contact") :
    LocalizedStringKey("action_assign_contact"))
```

#### `.accessibilityHint()`
Explains what happens when the user activates the element.

**When to use:**
- Complex interactions that aren't obvious
- Buttons that open sheets/modals
- Actions with non-immediate effects

**Examples:**
```swift
.accessibilityHint(LocalizedStringKey("accessibility_hint_assign_contact"))
// → "Opens contact selector"

.accessibilityHint(LocalizedStringKey("accessibility_balance_hint"))
// → "Tap to view balance details. Long press to toggle balance visibility."
```

**When NOT to use:**
- Simple, obvious actions (e.g., "Close" button)
- Actions where the label fully describes the outcome

#### `.accessibilityValue()`
Shows the current state or value of a control.

**When to use:**
- Toggle states
- Selection indicators
- Status displays

**Examples:**
```swift
// Show when note exists
.accessibilityValue(hasNote ?
    LocalizedStringKey("accessibility_value_note_present") : "")

// Show current selection
.accessibilityValue(currentMode.rawValue)
```

#### `.accessibilityHidden()`
Hides decorative or redundant elements from VoiceOver.

**When to use:**
- Decorative images/videos
- Duplicate information
- Visual spacers

**Examples:**
```swift
// Hide decorative video
LoopingVideoPlayer(videoName: "background")
    .accessibilityHidden(true)

// Hide decorative icon when text label is present
Image(systemName: "checkmark")
    .accessibilityHidden(true)
```

---

## Accessibility Review Checklist

When reviewing or implementing UI for accessibility:

### ✅ Localization
- [ ] All accessibility labels use localization keys (no hardcoded English)
- [ ] Keys follow proper naming conventions (`action_`, `button_`, `accessibility_`)
- [ ] All keys have values defined in `Localizable.xcstrings`
- [ ] Dynamic strings use `String(localized:)` with format strings

### ✅ Labels
- [ ] All interactive elements have `.accessibilityLabel()`
- [ ] Labels use appropriate key prefixes
- [ ] Conditional labels reflect current state

### ✅ Hints
- [ ] Complex interactions have `.accessibilityHint()`
- [ ] Hints explain what happens, not what the control is
- [ ] Hints use `accessibility_hint_` prefix

### ✅ Values
- [ ] Toggle states exposed via `.accessibilityValue()`
- [ ] Current selections are announced
- [ ] Values use `accessibility_value_` prefix

### ✅ Hidden Elements
- [ ] Decorative elements marked `.accessibilityHidden(true)`
- [ ] Redundant information hidden
- [ ] Visual-only spacers hidden

---

## Testing Guidelines

### VoiceOver Testing (iOS)
1. Enable VoiceOver: Settings → Accessibility → VoiceOver
2. Test navigation with swipe gestures
3. Verify all labels are read correctly
4. Confirm hints provide useful context
5. Check that values announce current state

### VoiceOver Testing (macOS)
1. Enable VoiceOver: System Settings → Accessibility → VoiceOver
2. Navigate using VO + arrow keys
3. Verify keyboard navigation works
4. Test that hints and values are announced

### Xcode Accessibility Inspector
1. Open Accessibility Inspector (Xcode → Open Developer Tool → Accessibility Inspector)
2. Select your running app/simulator
3. Click elements to inspect their properties
4. Verify labels, hints, values, and traits are correct

---

## Common Patterns in Arké

### Contact Assignment Button
```swift
Button {
    showContactSelector = true
} label: {
    if let contact = selectedContact {
        ContactAvatarView(contact: contact)
    } else {
        Image(systemName: "person.fill")
    }
}
.accessibilityLabel(selectedContact != nil ?
    LocalizedStringKey("action_change_contact") :
    LocalizedStringKey("action_assign_contact"))
.accessibilityHint(LocalizedStringKey("accessibility_hint_assign_contact"))
```

### Tag Selector with Dynamic Label
```swift
private var tagsAccessibilityLabel: String {
    guard let metadata = pendingMetadata else {
        return String(localized: "action_assign_tags")
    }

    let tags = metadata.associatedTags
    if tags.isEmpty {
        return String(localized: "action_assign_tags")
    } else if tags.count == 1 {
        return String(localized: "Change tags: \(tags[0].name)")
    } else {
        return String(localized: "Change tags: \(tags.count) tags selected")
    }
}

Button {
    showTagSelector = true
} label: {
    TagIconView(tags: selectedTags)
}
.accessibilityLabel(tagsAccessibilityLabel)
.accessibilityHint(LocalizedStringKey("accessibility_hint_assign_tags"))
```

### Note Button with State
```swift
Button {
    showNoteEditor = true
} label: {
    Image(systemName: "text.quote")
        .foregroundStyle(hasNote ? Color.green : .primary)
}
.accessibilityLabel(hasNote ?
    LocalizedStringKey("action_change_note") :
    LocalizedStringKey("action_assign_note"))
.accessibilityHint(LocalizedStringKey("accessibility_hint_assign_note"))
.accessibilityValue(hasNote ?
    LocalizedStringKey("accessibility_value_note_present") : "")
```

---

## Anti-Patterns (Don't Do This)

### ❌ Hardcoded English Strings
```swift
// WRONG
.accessibilityLabel("Change contact")
.accessibilityHint("Opens contact selector")
```

```swift
// CORRECT
.accessibilityLabel(LocalizedStringKey("action_change_contact"))
.accessibilityHint(LocalizedStringKey("accessibility_hint_assign_contact"))
```

### ❌ Using Wrong Key Prefix
```swift
// WRONG - using plain English as key
.accessibilityLabel("Change contact")

// WRONG - using wrong prefix
.accessibilityLabel("label_change_contact")
```

```swift
// CORRECT - using action_ prefix
.accessibilityLabel(LocalizedStringKey("action_change_contact"))
```

### ❌ Missing Values in Localizable.xcstrings
```swift
// Code references this key:
.accessibilityLabel("action_assign_contact")

// But Localizable.xcstrings has:
"action_assign_contact" : {
  // ❌ WRONG - no value!
}

// ✅ CORRECT:
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

### ❌ Not Using LocalizedStringKey for Dynamic Content
```swift
// WRONG - won't update when state changes
.accessibilityLabel(hasContact ? "action_change_contact" : "action_assign_contact")

// CORRECT - wraps in LocalizedStringKey
.accessibilityLabel(hasContact ?
    LocalizedStringKey("action_change_contact") :
    LocalizedStringKey("action_assign_contact"))
```

---

## Quick Reference

| Use Case | Prefix | Example |
|----------|--------|---------|
| Button action | `action_` | `action_assign_contact` |
| Generic button | `button_` | `button_save` |
| Accessibility hint | `accessibility_hint_` | `accessibility_hint_assign_tags` |
| State value | `accessibility_value_` | `accessibility_value_note_present` |
| Status message | `status_` | `status_copied_exclaim` |
| General accessibility | `accessibility_` | `accessibility_balance_label` |

---

## Additional Resources

- [Apple Human Interface Guidelines - Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [SwiftUI Accessibility Documentation](https://developer.apple.com/documentation/swiftui/view-accessibility)
- [VoiceOver Testing Guide](https://developer.apple.com/library/archive/technotes/TestingAccessibilityOfiOSApps/TestAccessibilityonYourDevicewithVoiceOver/TestAccessibilityonYourDevicewithVoiceOver.html)

---

## Questions?

When in doubt:
1. Check existing implementations in the codebase
2. Use Xcode's Accessibility Inspector to verify your implementation
3. Test with VoiceOver enabled
4. Ensure all strings are localized with proper key naming
