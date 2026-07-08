# Device Registry Quick Reference

Quick reference for using the Device Registry system.

---

## 🎯 Common Operations

### Register Current Device
```swift
let service = ServiceContainer.shared.deviceRegistrationService

// After wallet creation
try await service.registerCurrentDevice(
    walletHash: "abc123...",
    hasSeed: true
)

// After detecting wallet on another device (before QR scan)
try await service.registerCurrentDevice(
    walletHash: "abc123...",
    hasSeed: false
)
```

### Update Device After Seed Import
```swift
// After successfully scanning QR code and saving seed
try await service.updateCurrentDeviceHasSeed(true)
```

### Update Heartbeat
```swift
// Smart update - only if >24h since last
await service.updateHeartbeatIfNeeded()

// Force update
try await service.updateHeartbeat()
```

### Query Devices
```swift
// Get all devices
await service.loadRegisteredDevices()
let all = service.registeredDevices

// Get current device
let current = try await service.getCurrentDevice()

// Get other devices (excluding current)
let others = try await service.getOtherDevices()

// Check if other devices exist
let hasOthers = try await service.hasOtherActiveDevices()

// Get stale devices (>30 days)
let stale = try await service.getStaleDevices(olderThan: 30)

// Get only active devices
let active = try await service.getActiveDevices()
```

### Unlink Devices
```swift
// Unlink specific device
try await service.unlinkDevice("device-id-string")

// Unlink all other devices (keep current)
try await service.unlinkAllOtherDevices()

// Cleanup stale devices
try await service.cleanupStaleDevices(olderThan: 30)
```

### Unregister Current Device
```swift
// Remove current device from registry
try await service.unregisterCurrentDevice()
```

---

## 🔍 Device Properties

### DeviceRegistration
```swift
device.id                      // UUID - SwiftData identifier
device.deviceId               // String - stable Keychain ID
device.deviceName             // String - "John's iPhone"
device.platform               // String - "iOS" or "macOS"
device.walletHash             // String - links to wallet
device.hasSeed                // Bool - full wallet?
device.registeredAt           // Date - first registration
device.lastSeenAt             // Date - last heartbeat
device.lastAppVersion         // String - "1.0.0"
device.isActive               // Bool - manually unlinked?
device.deviceModelIdentifier  // String? - "iPhone15,3"

// Computed properties
device.devicePlatform         // DevicePlatform enum
device.lastSeenRelative       // "2 hours ago"
device.isStale                // true if >30 days
device.platformDisplayName    // "iOS" or "macOS"
device.platformIcon           // "📱" or "💻"
device.statusSummary          // "Full Wallet" / "Stale" etc
```

---

## 🎨 SwiftUI Integration

### Access Service in Views
```swift
struct MyView: View {
    @Environment(\.deviceRegistrationService) var service
    
    var body: some View {
        // Use service.registeredDevices
    }
}
```

### Display Devices List
```swift
List(service.registeredDevices) { device in
    HStack {
        Text(device.platformIcon)
        VStack(alignment: .leading) {
            Text(device.deviceName)
            Text(device.lastSeenRelative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        Spacer()
        if device.hasSeed {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
        if device.isStale {
            Text("Stale")
                .font(.caption)
                .foregroundColor(.red)
        }
    }
}
```

### Update on Appear
```swift
.task {
    await service.loadRegisteredDevices()
}
```

### Heartbeat on Foreground
```swift
.onAppear {
    Task {
        await service.updateHeartbeatIfNeeded()
    }
}
.onReceive(NotificationCenter.default.publisher(
    for: UIApplication.willEnterForegroundNotification
)) { _ in
    Task {
        await service.updateHeartbeatIfNeeded()
    }
}
```

---

## 🛠️ Deletion Logic Integration

### Before Deleting Wallet
```swift
func deleteWallet() async throws {
    let service = ServiceContainer.shared.deviceRegistrationService
    
    // Check if other devices exist
    let hasOthers = try await service.hasOtherActiveDevices()
    
    if hasOthers {
        // Show alert: "Other devices have this wallet"
        // Options:
        //   - Delete from this device only (recommended)
        //   - Delete from all devices
        
        // If user chooses "this device only":
        try SecurityService.deleteMnemonic()  // Local only
        try await service.unregisterCurrentDevice()
        // Keep hash in iCloud for other devices
        
    } else {
        // Show alert: "This is the last device"
        // Options:
        //   - Delete wallet and iCloud data
        //   - Delete wallet, keep iCloud for recovery
        
        // If user chooses "delete all":
        try SecurityService.deleteMnemonic()
        // Delete hash, WalletConfiguration, all devices, etc.
    }
}
```

---

## ⚙️ Configuration

### Heartbeat Interval
Default: 24 hours (86400 seconds)

Location: `DeviceRegistrationService.heartbeatInterval`

### Staleness Threshold
Default: 30 days

Configurable per query:
```swift
let stale = try await service.getStaleDevices(olderThan: 45)
```

### Keychain Configuration
```
Service:       "com.arke.device"
Account:       "deviceId"
Accessibility: ThisDeviceOnly
Synchronizable: false
```

---

## 🐛 Error Handling

### DeviceRegistrationError Cases
```swift
do {
    try await service.registerCurrentDevice(...)
} catch DeviceRegistrationError.noModelContext {
    // ModelContext not set
} catch DeviceRegistrationError.keychainError(let status) {
    // Keychain operation failed
} catch DeviceRegistrationError.encodingFailed {
    // Device ID encoding failed
} catch DeviceRegistrationError.deviceNotRegistered {
    // Device not found in registry
} catch DeviceRegistrationError.deviceNotFound {
    // Specific device not found
}
```

---

## 🧪 Testing Helpers

### Simulate Stale Device
```swift
// Manually set lastSeenAt to old date
if let device = try await service.getCurrentDevice() {
    device.lastSeenAt = Date().addingTimeInterval(-31 * 24 * 60 * 60)
    try modelContext.save()
}
```

### Check Device ID
```swift
let deviceId = try service.getOrCreateDeviceId()
print("Device ID: \(deviceId)")
```

### Verify Heartbeat
```swift
let lastHeartbeat = UserDefaults.standard.double(forKey: "com.arke.device.lastHeartbeat")
let date = Date(timeIntervalSince1970: lastHeartbeat)
print("Last heartbeat: \(date)")
```

---

## 📋 Debug Logging

Enable debug output by building in Debug configuration. Look for:

```
✅ [DeviceRegistrationService] Created new device ID: ABC123...
✅ [DeviceRegistrationService] Loaded existing device ID: ABC123...
✅ [DeviceRegistrationService] Created new device registration
✅ [DeviceRegistrationService] Updated existing device registration
💓 [DeviceRegistrationService] Heartbeat updated
⏭️ [DeviceRegistrationService] Skipping heartbeat (next in 12.5 hours)
📱 [DeviceRegistrationService] Loaded 3 registered devices
🗑️ [DeviceRegistrationService] Unlinked device: ABC123...
🗑️ [DeviceRegistrationService] Unlinked 2 other devices
```

---

## 🔗 Related Services

- **SecurityService** - Manages seed storage and hashing
- **WalletManager** - Coordinates wallet operations
- **CloudKitObserver** - Handles sync notifications
- **ServiceContainer** - Manages service lifecycle

---

**Version**: 1.0  
**Last Updated**: December 4, 2025
