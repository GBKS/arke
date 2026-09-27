# CloudKit Quick Start (Alpha)

## 3 Steps to Enable Sync

### Step 1: Add iCloud Capability (30 seconds)
1. Open your Xcode project
2. Select your app target
3. Go to **"Signing & Capabilities"** tab
4. Click **"+ Capability"**
5. Add **"iCloud"**
6. Check **"CloudKit"** checkbox
7. ✅ Done!

### Step 2: Update Your App Code (2 minutes)

Find your app's main file (the one with `@main` and `App`), and update it to use CloudKit:

```swift
import SwiftUI
import SwiftData

@main
struct YourAppName: App {
    
    let modelContainer: ModelContainer = {
        SwiftDataHelper.createModelContainer(
            for: PersistentTransaction.self,
                 PersistentTag.self,
                 TransactionTagAssignment.self,
                 PersistentContact.self,
                 TransactionContactAssignment.self,
                 // ... any other @Model classes
            cloudKitEnabled: true  // 👈 Add this!
        )
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
```

### Step 3: Test It (2 minutes)

1. Make sure you're signed into iCloud:
   - **Mac:** System Settings → Apple ID
   - **iOS:** Settings → [Your Name]

2. Run your app and create some test data:
   - Add a tag
   - Add a contact
   - Add notes to a transaction

3. Verify sync is working:
   - Open https://icloud.developer.apple.com/dashboard
   - Select your container
   - Click "Data" → "Records"
   - You should see your data!

## That's It! 🎉

Your app now syncs across all devices signed into the same iCloud account.

## Troubleshooting

**Not seeing data sync?**
- Wait up to 60 seconds (CloudKit can be slow on first sync)
- Check you're signed into iCloud
- Verify network connection
- Look for errors in Xcode console

**Build errors?**
- Make sure iCloud capability is added correctly
- Clean build (Cmd + Shift + K)
- Restart Xcode if needed

**Need to disable sync temporarily?**
```swift
cloudKitEnabled: false  // 👈 Change true to false
```

## What's Syncing?

Everything in your SwiftData models:
- ✅ Transactions and all their metadata
- ✅ Tags you create
- ✅ Contacts
- ✅ Notes on transactions
- ✅ All relationships between them

Data syncs automatically whenever it changes. No code needed!
