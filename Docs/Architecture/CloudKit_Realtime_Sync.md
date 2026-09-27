# CloudKit Real-Time Sync Implementation

## Overview
This document explains how real-time CloudKit sync is implemented across the app, enabling UI updates when data changes on other devices.

## The Problem
Previously, when CloudKit pushed changes from another device:
- ✅ `CloudKitObserver` detected the changes
- ✅ SwiftData's persistent store was updated
- ❌ **Services with cached data** (like `TagService` and `ContactService`) did not refresh
- ❌ **UI did not update** because it was showing stale cached data

## The Solution: NotificationCenter Pattern

### Architecture
We use a two-tier notification system:

1. **System Level**: `NSPersistentStoreRemoteChange` (from Core Data/CloudKit)
2. **App Level**: `cloudKitDataDidChange` (custom notification)

### Data Flow

```
CloudKit Change
    ↓
CloudKitObserver receives NSPersistentStoreRemoteChange
    ↓
CloudKitObserver saves ModelContext to merge changes
    ↓
CloudKitObserver posts .cloudKitDataDidChange notification
    ↓
Services observe .cloudKitDataDidChange
    ↓
Services reload their cached data
    ↓
@Observable properties update
    ↓
SwiftUI views refresh automatically
```

## Implementation Details

### 1. CloudKitObserver (Updated)
**File**: `CloudKitObserver.swift`

**Changes**:
- Added custom notification: `.cloudKitDataDidChange`
- Posts this notification after successfully merging CloudKit changes
- Services can observe this without coupling to CloudKit internals

```swift
// After saving context
NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)
```

### 2. TagService (Updated)
**File**: `TagService.swift`

**Changes**:
- Added `Combine` import
- Added `cancellables` property for managing subscriptions
- Observes `.cloudKitDataDidChange` in initializer
- Calls `loadTags()` when notification is received
- Cleans up in `deinit`

```swift
private func startObservingCloudKitChanges() {
    NotificationCenter.default
        .publisher(for: .cloudKitDataDidChange)
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleCloudKitChange()
            }
        }
        .store(in: &cancellables)
}

private func handleCloudKitChange() async {
    print("📋 [TagService] CloudKit change detected - reloading tags")
    await loadTags()
}
```

## Services That Need This Pattern

Any service that **caches SwiftData models in memory** needs to observe CloudKit changes:

### ✅ Already Implemented
- `TagService` - caches `tags: [TagModel]`

### 🔲 TODO: Needs Implementation
- `ContactService` - likely caches `contacts: [ContactModel]`
- Any other service that maintains in-memory caches of SwiftData entities

## How to Add CloudKit Sync to Other Services

Follow this checklist for each service:

### 1. Import Combine
```swift
import Combine
```

### 2. Add Cancellables Property
```swift
private var cancellables = Set<AnyCancellable>()
```

### 3. Start Observing in Init
```swift
init(taskManager: TaskDeduplicationManager) {
    self.taskManager = taskManager
    startObservingCloudKitChanges()
}

private func startObservingCloudKitChanges() {
    NotificationCenter.default
        .publisher(for: .cloudKitDataDidChange)
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleCloudKitChange()
            }
        }
        .store(in: &cancellables)
    
    print("📋 [YourService] Started observing CloudKit changes")
}
```

### 4. Handle Changes
```swift
private func handleCloudKitChange() async {
    print("📋 [YourService] CloudKit change detected - reloading data")
    await loadYourData() // Call your existing load method
}
```

### 5. Clean Up
```swift
deinit {
    cancellables.removeAll()
}
```

## Testing CloudKit Sync

### Prerequisites
- Two devices (or simulator + device) signed into the same iCloud account
- CloudKit container properly configured
- App installed on both devices

### Test Procedure
1. **Device A**: Create/update/delete a tag
2. **Watch Device A logs**: Should see "Posted cloudKitDataDidChange notification"
3. **Watch Device B logs**: Should see:
   - "🌥️ [CloudKit] Remote change detected"
   - "✅ [CloudKit] Data refreshed from remote changes"
   - "📢 [CloudKit] Posted cloudKitDataDidChange notification"
   - "📋 [TagService] CloudKit change detected - reloading tags"
   - "📋 Loaded X tags from SwiftData"
4. **Device B UI**: Should update immediately showing the new/changed/deleted tag

### Debug Logs to Watch For
```
// On device that made the change:
✅ Created tag: [Name]
📢 [CloudKit] Posted cloudKitDataDidChange notification

// On remote device receiving the change:
🌥️ [CloudKit] Remote change detected - refreshing data
✅ [CloudKit] Data refreshed from remote changes
📢 [CloudKit] Posted cloudKitDataDidChange notification
📋 [TagService] CloudKit change detected - reloading tags
📋 Loaded X tags from SwiftData
```

## Benefits of This Approach

1. **Decoupled**: Services don't need to know about CloudKit
2. **Scalable**: Easy to add to new services
3. **Maintainable**: Clear separation of concerns
4. **Testable**: Can post notification manually for testing
5. **Efficient**: Only refreshes data when CloudKit actually has changes

## Performance Considerations

- The notification is only posted when CloudKit **actually pushes changes**
- Each service's `loadData()` method is called once per CloudKit change
- For large datasets, consider:
  - Implementing incremental/differential updates
  - Debouncing if multiple rapid changes occur
  - Only fetching changed entities (requires change tracking)

## Alternative Approaches (Not Used)

### Why Not Direct @Query in Views?
- ❌ Would require significant architectural changes
- ❌ Less flexible for computed properties and business logic
- ❌ Harder to manage loading states and errors
- ✅ Our current approach works with existing architecture

### Why Not Pass Services to CloudKitObserver?
- ❌ Creates tight coupling
- ❌ CloudKitObserver would need to know about all services
- ❌ Hard to extend as new services are added

### Why Not Polling?
- ❌ Inefficient - wastes battery and CPU
- ❌ Creates unnecessary database load
- ❌ Adds latency between change and UI update

## Related Files

- `CloudKitObserver.swift` - Observes CloudKit and posts notifications
- `TagService.swift` - Example implementation for tags
- `ServiceContainer.swift` - Manages all services
- `WalletManager.swift` - Exposes service data to views
- `TagsViewModel.swift` - View model that uses tag data

## Next Steps

1. ✅ TagService implemented
2. 🔲 Implement for ContactService
3. 🔲 Test on multiple devices
4. 🔲 Monitor performance with real usage
5. 🔲 Consider adding change tracking for optimization

---

**Created**: December 3, 2025
**Last Updated**: December 3, 2025
