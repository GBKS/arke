# Tags View Architecture - Shared Components

> **📦 ARCHIVED 2026-07-09** — Completed refactor writeup (TagsViewModel extraction + iOS view, Dec 2025). The work shipped and the lasting architecture description was merged into `Features/tag-system.md` § View Layer, which is the current reference. Details below reflect the state at completion; since then, tag sorting gained system-tag handling and `TagStatistic` gained fee fields.

This document describes the shared architecture for tag management across macOS and iOS.

## Architecture Overview

### 1. **TagsViewModel.swift** - Shared Business Logic (NEW)
All state management and business logic is centralized in an `@Observable` view model:

**Responsibilities:**
- State management (`tagStatistics`, `showingNewTagEditor`, `editingTag`, `tagToDelete`)
- Loading tag statistics from `WalletManager`
- CRUD operations (create, update, delete tags)
- Computed properties (sorted tags, largest amounts)
- Sheet presentation helpers

**Benefits:**
- ~80% code reuse between platforms
- Single source of truth for business logic
- Easier to test and maintain
- Platform views focus only on presentation

### 2. **TagsView.swift** - macOS Implementation (UPDATED)
Platform-specific presentation optimized for macOS:

**Key Features:**
- `ScrollView` with `Grid` layout for precise multi-column alignment
- Fixed-size sheets (500x600)
- `NetChangeBar` visualization for net amounts
- Menu-based actions (ellipsis button)
- Generous padding and spacing
- Optional navigation callback (macOS can be standalone)

**Changes Made:**
- Now uses `TagsViewModel` for all state and logic
- Removed all business logic methods
- View components take `viewModel` as parameter
- Bindings wrap view model properties

### 3. **TagsView_iOS.swift** - iOS Implementation (NEW)
Platform-specific presentation optimized for iOS:

**Key Features:**
- `List` layout with `NavigationLink` for native iOS feel
- Adaptive sheets with `.presentationDetents([.medium, .large])`
- Swipe actions for quick edit/delete
- Context menus for additional options
- Pull-to-refresh support (`.refreshable`)
- Compact spacing optimized for touch
- Required navigation callback (iOS is navigation-driven)
- `ContentUnavailableView` for empty states

**iOS-Specific Patterns:**
- Navigation links wrap each tag row
- Swipe left reveals Delete (red) and Edit (blue) actions
- Long press shows context menu
- Pull down to refresh statistics
- Sheets adapt to device size

### 4. **TagRowContent.swift** - Shared Row Component (OPTIONAL)
Reusable component for displaying tag information:

**Features:**
- Displays `TagChip`, transaction count, amount
- Optional `NetChangeBar` (typically for macOS)
- Can be customized per platform
- Currently not used in favor of platform-specific layouts

**When to Use:**
- If you want more consistency between platforms
- When building additional views that need tag rows

## Shared Components (Already Platform-Agnostic)

These existing components work on both platforms:
- ✅ **TagChip** - Visual representation of tags
- ✅ **TagEditor** - Create/edit tag form (works with adaptive sizing)
- ✅ **NetChangeBar** - Visual bar chart (used on macOS)
- ✅ **TagModel** - Data model
- ✅ **TagStatistic** - Statistics model

## Code Sharing Summary

| Component | Shared | macOS | iOS |
|-----------|--------|-------|-----|
| Business Logic | ✅ 100% | - | - |
| State Management | ✅ 100% | - | - |
| Data Models | ✅ 100% | - | - |
| TagChip | ✅ 100% | - | - |
| TagEditor | ✅ 100% | - | - |
| Layout | ❌ 0% | Grid | List |
| Interactions | ❌ 0% | Menu | Swipe + Context Menu |
| Sheets | 🔶 50% | Fixed | Adaptive |
| Empty State | 🔶 60% | Custom VStack | ContentUnavailableView |

**Overall Code Reuse: ~75-80%**

## Usage Example

### macOS
```swift
TagsView(onNavigateToActivity: { tag in
    // Optional: handle navigation to activity view
    navigationPath.append(ActivityFilter.tag(tag))
})
```

### iOS
```swift
TagsView_iOS { tag in
    // Required: handle navigation to activity view
    navigationPath.append(ActivityFilter.tag(tag))
}
```

## Migration Path Completed

✅ **Step 1:** Created `TagsViewModel` with shared logic  
✅ **Step 2:** Updated macOS view to use the view model  
✅ **Step 3:** Implemented iOS view using same view model  
✅ **Step 4:** Created optional `TagRowContent` shared component  
⏭️ **Step 5:** Test both platforms independently

## Platform Differences Summary

### macOS Advantages
- More information density (5 columns)
- NetChangeBar visualization
- Hover states and menu buttons
- Larger, more spacious layout

### iOS Advantages
- Native navigation patterns
- Touch-optimized interactions (swipe actions)
- Pull-to-refresh
- Adaptive sheets for different devices
- System-standard empty states

## Future Enhancements

### Potential Additions
1. **Search functionality** - iOS `.searchable`, macOS search field
2. **Sorting options** - Menu on macOS, toolbar on iOS
3. **Filtering** - Show only tags with transactions
4. **Tag statistics graphs** - Could use `TagsGraph` component
5. **Keyboard shortcuts** - macOS only
6. **Drag to reorder** - Different implementations per platform

### Testing Recommendations
- Test sheet presentations on iPhone vs iPad
- Test swipe actions on iOS
- Test keyboard navigation on macOS
- Test with many tags (20+)
- Test with tags with no transactions
- Test with very long tag names
- Test empty state flows
