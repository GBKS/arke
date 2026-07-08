# Fix: Invalid Redeclaration Errors in PersistentTransaction

## 🐛 The Problem

You're seeing these errors:
```
error: Invalid redeclaration of 'isInternalTransfer'
error: Invalid redeclaration of 'effectiveType'
error: Invalid redeclaration of 'effectiveTypeDisplayName'
error: Invalid redeclaration of 'effectiveTypeIcon'
```

## 🔍 Root Cause

There's a duplicate extension file that was created earlier: **`PersistentTransaction+AddressRelationship.swift`**

This file contains the same methods that are now in `PersistentTransaction.swift`, causing duplicate declarations.

## ✅ Solution: Remove the Extension File

### In Xcode:

1. **Open Project Navigator** (⌘+1)

2. **Search for**: `PersistentTransaction+AddressRelationship`

3. **If found**, select the file and:
   - Right-click → **Delete**
   - Choose **Move to Trash** (not just remove reference)

4. **Clean Build** (⌘+Shift+K)

5. **Build** (⌘+B)

The errors should be gone!

---

## 📝 What Happened

When I initially created the address history system, I created an extension file `PersistentTransaction+AddressRelationship.swift` that contained:

```swift
extension PersistentTransaction {
    var isInternalTransfer: Bool { ... }
    var effectiveType: String { ... }
    var effectiveTypeDisplayName: String { ... }
    var effectiveTypeIcon: String { ... }
}
```

But then you added these same methods directly to `PersistentTransaction.swift`, which is the correct approach. Now both exist, causing the duplicate declarations.

---

## ✅ Verify Fix

After deleting the extension file, check that `PersistentTransaction.swift` has these methods (lines 207-256):

```swift
// MARK: - Internal Transfer Detection

var isInternalTransfer: Bool {
    guard type == "sent" else { return false }
    return receivingAddress != nil
}

var effectiveType: String {
    if isInternalTransfer {
        return "internal_transfer"
    }
    return type
}

var effectiveTypeDisplayName: String {
    switch effectiveType {
    case "internal_transfer":
        return "Internal Transfer"
    // ... etc
    }
}

var effectiveTypeIcon: String {
    switch effectiveType {
    case "internal_transfer":
        return "arrow.left.arrow.right"
    // ... etc
    }
}
```

If these are in `PersistentTransaction.swift`, you're good!

---

## 🔍 If You Can't Find the Extension File

If the extension file doesn't appear in Project Navigator:

1. **Check for orphaned files**:
   - Select your project in Navigator
   - File → Add Files to [Project]
   - Look for any `PersistentTransaction+` files

2. **Check build phases**:
   - Select your target
   - Build Phases → Compile Sources
   - Look for `PersistentTransaction+AddressRelationship.swift`
   - Remove it if found

3. **Search filesystem**:
   - In Finder, navigate to your project folder
   - Search for `PersistentTransaction+`
   - Delete any extension files you find

---

## 🚨 Alternative: Comment Out Extension

If you need to keep the file for some reason but want to fix the errors immediately, you can comment out the entire extension:

```swift
// TEMPORARILY DISABLED - Duplicate of methods in main PersistentTransaction class
/*
extension PersistentTransaction {
    var isInternalTransfer: Bool { ... }
    // ... rest of extension
}
*/
```

But **deleting the file** is the proper solution.

---

## ✅ Expected Result

After removing the duplicate extension file:
- ✅ No compilation errors
- ✅ `isInternalTransfer` works correctly
- ✅ Internal transfers detected
- ✅ All Phase 3 functionality intact

The methods are properly defined once in `PersistentTransaction.swift` and that's all you need!
