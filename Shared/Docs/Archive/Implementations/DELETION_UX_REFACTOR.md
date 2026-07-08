# Wallet Deletion UX Refactor

## Summary

Replaced confirmation dialogs with full-screen immersive deletion views for a more deliberate and user-friendly wallet deletion experience.

## Files Created

### 1. `DeleteLocallyConfirmationView.swift`
Full-screen view for local device deletion.

**Features:**
- Screen-filling background using "delete-wallet" image with gradient overlay
- Back button in top left corner
- Orange device slash icon (iPhone.slash)
- Clear messaging about local deletion
- iCloud status callout when applicable
- Orange-tinted glass button for confirmation
- Real-time deletion progress display
- Error handling with inline error messages

### 2. `DeletePermanentlyConfirmationView.swift`
Full-screen view for permanent deletion.

**Features:**
- Screen-filling background with red-tinted gradient overlay for dramatic effect
- Back button in top left corner
- Red warning triangle icon
- Prominent "cannot be undone" warning
- Detailed list of what will be deleted
- iCloud warning callout when synced
- Red-tinted glass button for confirmation
- Real-time deletion progress display
- Error handling with inline error messages

## Files Modified

### 3. `DeleteWalletSettingView.swift`

**Changes:**
- Added `DeletionType` enum (conforming to `Identifiable`) with `.local` and `.permanent` cases
- Replaced `showLocalDeleteConfirmation` and `showCompleteDeleteConfirmation` states with single `showingDeletionView: DeletionType?`
- Removed both `.confirmationDialog` modifiers
- Added `.fullScreenCover(item:)` modifier that presents appropriate confirmation view
- Simplified button actions to just set `showingDeletionView`
- Deletion logic remains in parent view and is passed as closures to confirmation views

## UX Improvements

1. **More Deliberate Process**: Full-screen views force users to focus on the decision
2. **Better Information Hierarchy**: More space for clear explanations and warnings
3. **Visual Distinction**: Orange vs red theming clearly differentiates severity
4. **Immersive Experience**: Background images create emotional weight appropriate to the action
5. **Consistent Design**: Matches existing onboarding flow patterns
6. **Better Accessibility**: Larger text and clearer labels
7. **Progress Visibility**: Real-time feedback during deletion process

## Design Details

- **Typography**: Large serif titles, body text with line spacing
- **Colors**: Orange for local deletion, red for permanent deletion
- **Icons**: System SF Symbols (iphone.slash, exclamationmark.triangle.fill)
- **Background**: "delete-wallet" image with gradient overlays
- **Buttons**: `.glassProminent` style with appropriate tint colors
- **Layout**: Top back button, centered content, bottom confirmation button

## Technical Notes

- Uses existing `DeletionStrategy` enum from `WalletDataCleanupService`
- Integrates with existing cleanup service for progress tracking
- Maintains all error handling and deletion logic
- Works with both `.localOnly` and `.promptForCloudData` strategies
- Closures pass deletion logic from parent view
- Dismissal happens automatically after successful deletion via `onWalletDeleted()` callback
