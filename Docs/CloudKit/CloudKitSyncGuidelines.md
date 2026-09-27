//
//  CloudKitSyncGuidelines.md
//  Important considerations for CloudKit sync in a Bitcoin wallet app
//

# CloudKit Sync Guidelines for Ark Wallet

## ⚠️ Security & Privacy Considerations

### What Should Sync
✅ **Safe to sync:**
- Transaction metadata (notes, tags, contacts)
- UI preferences
- Contact information
- Tag definitions
- Display settings

### What Should NOT Sync
❌ **Never sync to CloudKit:**
- Private keys or seed phrases
- Wallet mnemonics
- Authentication tokens
- API keys or secrets
- Sensitive user credentials

## Recommended Architecture

### Split Your Models

Consider creating two separate model containers:

1. **Local-only container** (no CloudKit):
   - Sensitive wallet data
   - Private keys (if stored locally)
   - Session tokens

2. **CloudKit-synced container**:
   - Transaction metadata (your PersistentTransaction)
   - Tags (PersistentTag)
   - Contacts (PersistentContact)
   - User preferences

### Example: Two Container Setup

```swift
@main
struct ArkWalletApp: App {
    
    // Container for CloudKit-synced data (tags, notes, contacts)
    let syncedContainer: ModelContainer = {
        SwiftDataHelper.createModelContainer(
            for: PersistentTransaction.self,
                 PersistentTag.self,
                 TransactionTagAssignment.self,
                 PersistentContact.self,
                 TransactionContactAssignment.self,
            cloudKitEnabled: true
        )
    }()
    
    // Container for local-only sensitive data
    let localContainer: ModelContainer = {
        SwiftDataHelper.createModelContainer(
            for: WalletKeyStore.self,  // Example: your sensitive model
                 UserSession.self,       // Example: session data
            cloudKitEnabled: false  // Never sync sensitive data!
        )
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(syncedContainer)
                // For accessing local data, use .environment or pass localContainer
        }
    }
}
```

## Network & Sync Status

### Handle Sync Conflicts

CloudKit may create conflicts when data is modified on multiple devices. SwiftData handles this automatically, but you can monitor status:

```swift
import SwiftData
import CloudKit

@Observable
class CloudKitStatusMonitor {
    var isAvailable = false
    var accountStatus: CKAccountStatus = .couldNotDetermine
    
    func checkStatus() async {
        let container = CKContainer.default()
        
        do {
            accountStatus = try await container.accountStatus()
            isAvailable = (accountStatus == .available)
        } catch {
            print("CloudKit status check failed: \(error)")
            isAvailable = false
        }
    }
}
```

### Provide User Control

Give users the option to:
- Enable/disable sync
- View sync status
- Manually trigger sync
- Clear CloudKit data if needed

## Testing CloudKit Sync

### Development
1. Sign in with an iCloud account in the simulator
2. Run your app on multiple simulators/devices
3. Verify data syncs across devices
4. Test offline behavior

### Production Considerations
- CloudKit has quota limits (requests, storage, bandwidth)
- Monitor usage in CloudKit Dashboard
- Consider implementing:
  - Sync indicators in UI
  - Error handling for quota exceeded
  - Graceful degradation when CloudKit unavailable

## Privacy & User Trust

### Be Transparent
- Clearly inform users what data syncs to iCloud
- Provide privacy policy
- Allow users to opt out
- Show sync status in settings

### Best Practices
- Encrypt sensitive data even in local storage
- Never rely solely on CloudKit for backups
- Provide local export options
- Test data recovery scenarios

## Useful Settings View Example

```swift
struct CloudKitSettingsView: View {
    @State private var syncEnabled = true
    @State private var statusMonitor = CloudKitStatusMonitor()
    
    var body: some View {
        Form {
            Section("iCloud Sync") {
                Toggle("Sync with iCloud", isOn: $syncEnabled)
                
                HStack {
                    Text("Status")
                    Spacer()
                    if statusMonitor.isAvailable {
                        Label("Available", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Unavailable", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                
                Text("Synced data includes: transaction notes, tags, and contacts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section {
                Text("Private keys and wallet data never leave your device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await statusMonitor.checkStatus()
        }
    }
}
```

## Migration Strategy

If you're adding CloudKit to an existing app:

1. **Ensure backward compatibility**: Existing users shouldn't lose data
2. **Gradual rollout**: Consider making it opt-in initially
3. **Test thoroughly**: Migration bugs in wallet apps are critical
4. **Provide clear communication**: Tell users about the new feature

## Additional Resources

- Apple's CloudKit documentation
- SwiftData CloudKit integration guide
- Privacy best practices for financial apps
- CKContainer and CKDatabase APIs for advanced control
