# Common Development Tasks

This guide provides step-by-step instructions for frequently needed development workflows in the Arké Wallet prototype.

## Service Development

### Adding a New Service

**1. Create the Service Class**
```swift
import Foundation
import SwiftData

@MainActor
@Observable
class NewService {
    // Observable state properties
    var data: [DataModel] = []
    var error: String?
    var isLoading: Bool = false
    
    // Dependencies
    private let wallet: BarkWalletProtocol
    private let taskManager: TaskDeduplicationManager
    private var modelContext: ModelContext?
    
    init(wallet: BarkWalletProtocol, taskManager: TaskDeduplicationManager) {
        self.wallet = wallet
        self.taskManager = taskManager
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadPersistedData()
    }
    
    func refreshData() async {
        await taskManager.execute(key: "newservice_data") {
            await performDataRefresh()
        }
    }
    
    private func performDataRefresh() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let freshData = try await wallet.getNewData()
            self.data = freshData
            self.error = nil
        } catch {
            print("❌ NewService refresh failed: \(error)")
            self.error = error.localizedDescription
        }
    }
}
```

**2. Add Service to WalletManager**
```swift
// In WalletManager.swift
class WalletManager {
    // Add property
    let newService: NewService
    
    // Update initializer
    init(wallet: BarkWalletProtocol = BarkWallet()) {
        // ... existing services
        self.newService = NewService(wallet: wallet, taskManager: taskManager)
    }
    
    // Update setModelContext
    func setModelContext(_ context: ModelContext) {
        // ... existing services
        newService.setModelContext(context)
    }
    
    // Update refreshAllData if appropriate
    func refreshAllData() async {
        // ... existing refreshes
        await newService.refreshData()
    }
}
```

**3. Create Tests**
```swift
import Testing
@testable import Ark_wallet_prototype

@Suite("New Service Tests")
struct NewServiceTests {
    
    @Test("Service loads data successfully")
    func serviceLoadsDataSuccessfully() async throws {
        let mockWallet = MockBarkWallet()
        let service = NewService(wallet: mockWallet, taskManager: TaskDeduplicationManager())
        
        await service.refreshData()
        
        #expect(service.data.count > 0)
        #expect(service.error == nil)
    }
}
```

### Adding Persistence to Existing Service

**1. Create Persistence Model**
```swift
import SwiftData
import Foundation

@Model
class PersistedNewData {
    var id: String = "new_data"
    var value: String
    var lastUpdated: Date
    
    init(value: String) {
        self.value = value
        self.lastUpdated = Date()
    }
    
    func toUIModel() -> DataModel {
        return DataModel(value: self.value)
    }
    
    func update(from model: DataModel) {
        self.value = model.value
        self.lastUpdated = Date()
    }
    
    var isValid: Bool {
        Date().timeIntervalSince(lastUpdated) < 300 // 5 minutes
    }
}
```

**2. Update App Model Container**
```swift
// In Ark_wallet_prototypeApp.swift
var body: some Scene {
    WindowGroup {
        ContentView()
    }
    .modelContainer(for: [
        PersistedArkBalance.self,
        PersistedOnchainBalance.self,
        PersistedNewData.self  // Add new model
    ])
}
```

**3. Add Persistence Methods to Service**
```swift
// Add to existing service
private func loadPersistedData() {
    guard let context = modelContext else { return }
    
    let descriptor = FetchDescriptor<PersistedNewData>()
    do {
        if let persisted = try context.fetch(descriptor).first,
           persisted.isValid {
            self.data = [persisted.toUIModel()]
        }
    } catch {
        print("❌ Failed to load persisted data: \(error)")
    }
}

private func saveToSwiftData(_ data: DataModel) {
    guard let context = modelContext else { return }
    
    do {
        let descriptor = FetchDescriptor<PersistedNewData>()
        let existing = try context.fetch(descriptor).first
        
        if let existing = existing {
            existing.update(from: data)
        } else {
            let newPersisted = PersistedNewData(value: data.value)
            context.insert(newPersisted)
        }
        
        try context.save()
    } catch {
        print("❌ Failed to save data: \(error)")
    }
}
```

## UI Development

### Creating a New View with Service Integration

**1. Create the View**
```swift
import SwiftUI

struct NewDataView: View {
    @Environment(WalletManager.self) private var walletManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeaderView()
            DataListView()
            ErrorView()
        }
        .padding()
        .task {
            await walletManager.newService.refreshData()
        }
    }
    
    @ViewBuilder
    private func HeaderView() -> some View {
        HStack {
            Text("New Data")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            if walletManager.newService.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }
    
    @ViewBuilder
    private func DataListView() -> some View {
        if walletManager.newService.data.isEmpty {
            Text("No data available")
                .foregroundStyle(.secondary)
        } else {
            ForEach(walletManager.newService.data) { item in
                DataRowView(item: item)
            }
        }
    }
    
    @ViewBuilder
    private func ErrorView() -> some View {
        if let error = walletManager.newService.error {
            Text(error)
                .foregroundColor(.red)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
        }
    }
}

#Preview {
    NewDataView()
        .environment(WalletManager.preview)
}
```

**2. Add Preview Support**
```swift
// In WalletManager.swift, update preview
extension WalletManager {
    static let preview: WalletManager = {
        let manager = WalletManager(wallet: MockBarkWallet())
        // Add sample data for new service
        manager.newService.data = [DataModel.createSample()]
        return manager
    }()
}
```

### Adding Navigation and Menu Items

**1. Update Sidebar Navigation**
```swift
// In ContentView.swift or similar
NavigationLink(destination: NewDataView()) {
    Label("New Data", systemImage: "doc.text")
}
```

**2. Add Menu Commands**
```swift
// In App file or CommandsView
CommandGroup(after: .newItem) {
    Button("Refresh New Data") {
        Task {
            await WalletManager.shared.newService.refreshData()
        }
    }
    .keyboardShortcut("r", modifiers: [.command, .shift])
}
```

## Model Development

### Creating New Data Models

**1. UI Model**
```swift
import Foundation

struct NewDataModel: Identifiable, Codable {
    let id: String
    let value: String
    let timestamp: Date
    let amount: Int
    
    // Computed properties for display
    var formattedValue: String {
        return value.capitalized
    }
    
    var formattedAmount: String {
        return BitcoinFormatter.format(satoshis: amount)
    }
    
    var relativeTimestamp: String {
        return RelativeDateTimeFormatter().localizedString(for: timestamp, relativeTo: Date())
    }
}

extension NewDataModel {
    static func createSample() -> NewDataModel {
        return NewDataModel(
            id: UUID().uuidString,
            value: "Sample Data",
            timestamp: Date(),
            amount: 100_000
        )
    }
}
```

**2. Add Parsing from Raw Data**
```swift
// Extend the model with parsing capability
extension NewDataModel {
    init(from rawData: RawDataStruct) throws {
        guard !rawData.id.isEmpty else {
            throw ParsingError.missingRequiredField("id")
        }
        
        self.id = rawData.id
        self.value = rawData.value
        self.timestamp = try parseTimestamp(rawData.timestamp)
        self.amount = rawData.amount
    }
    
    private func parseTimestamp(_ string: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: string) else {
            throw ParsingError.invalidTimestamp(string)
        }
        return date
    }
}
```

### Adding Formatters and Utilities

**1. Create Specialized Formatter**
```swift
import Foundation

struct NewDataFormatter {
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    
    static func format(_ value: Double) -> String {
        return numberFormatter.string(from: NSNumber(value: value)) ?? "0"
    }
    
    static func formatPercentage(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "0%"
    }
}
```

**2. Add Validation Utilities**
```swift
struct NewDataValidator {
    static func isValid(_ data: NewDataModel) -> Bool {
        return !data.value.isEmpty && 
               data.amount >= 0 && 
               data.timestamp <= Date()
    }
    
    static func validateAmount(_ amount: Int) throws {
        guard amount >= 0 else {
            throw ValidationError.negativeAmount
        }
        guard amount <= 21_000_000 * 100_000_000 else {
            throw ValidationError.amountTooLarge
        }
    }
}

enum ValidationError: Error {
    case negativeAmount
    case amountTooLarge
    case invalidValue
}
```

## Testing Workflows

### Adding Tests for New Features

**1. Create Test File**
```swift
import Testing
@testable import Ark_wallet_prototype

@Suite("New Data Model Tests")
struct NewDataModelTests {
    
    @Test("Model creation with valid data")
    func modelCreationWithValidData() throws {
        let data = NewDataModel.createSample()
        
        #expect(!data.id.isEmpty)
        #expect(!data.value.isEmpty)
        #expect(data.amount >= 0)
    }
    
    @Test("Model parsing from raw data")
    func modelParsingFromRawData() throws {
        let rawData = RawDataStruct(
            id: "test-123",
            value: "test value",
            timestamp: "2024-10-24T10:00:00Z",
            amount: 50000
        )
        
        let model = try NewDataModel(from: rawData)
        
        #expect(model.id == "test-123")
        #expect(model.value == "test value")
        #expect(model.amount == 50000)
    }
}
```

**2. Run Tests**
```bash
# From Xcode: Cmd+U
# From command line:
xcodebuild test -scheme Ark-wallet-prototype -destination 'platform=macOS'
```

### Performance Testing

**1. Measure Performance**
```swift
@Test("Large data set performance")
func largeDataSetPerformance() async throws {
    let startTime = Date()
    
    // Perform operation
    let largeDataSet = Array(0..<10000).map { _ in NewDataModel.createSample() }
    let processedData = largeDataSet.map { $0.formattedValue }
    
    let duration = Date().timeIntervalSince(startTime)
    
    #expect(processedData.count == 10000)
    #expect(duration < 1.0) // Should complete in under 1 second
}
```

## Debugging Common Issues

### Service Not Updating UI

**Problem**: UI doesn't update when service data changes
**Solution**:
1. Ensure service uses `@Observable` macro
2. Verify service is `@MainActor`
3. Check UI uses proper environment injection
4. Confirm properties are `var`, not `let`

```swift
// Correct pattern
@MainActor
@Observable
class MyService {
    var data: [Model] = [] // var, not let
    
    func updateData() {
        // This will trigger UI updates
        self.data = newData
    }
}
```

### SwiftData Persistence Issues

**Problem**: Data not persisting between app launches
**Solution**:
1. Verify model uses `@Model` macro
2. Check ModelContainer includes all models
3. Ensure `try context.save()` is called
4. Clear corrupt data if necessary

```bash
# Clear app data (for development)
rm -rf ~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/Library/Application\ Support/default.store*
```

### Async Operations Not Completing

**Problem**: Async operations hang or don't complete
**Solution**:
1. Check for proper error handling
2. Verify network connectivity
3. Add timeout handling
4. Use proper async/await patterns

```swift
// Add timeout handling
func refreshWithTimeout() async throws {
    try await withTimeout(seconds: 30) {
        await performRefresh()
    }
}
```

### Memory Leaks and Retain Cycles

**Problem**: App memory usage grows over time
**Solution**:
1. Use weak references for delegates
2. Properly clean up closures
3. Check for retain cycles in services
4. Use Instruments to profile memory usage

```swift
// Avoid retain cycles
service.onComplete = { [weak self] result in
    self?.handleResult(result)
}
```

## Release Preparation

### Pre-Release Checklist

**1. Code Quality**
- [ ] All tests pass
- [ ] No compiler warnings
- [ ] Code follows project conventions
- [ ] Documentation updated

**2. Testing**
- [ ] Manual testing with real Bark CLI
- [ ] Test error scenarios
- [ ] Verify UI in different window sizes
- [ ] Test with empty/large data sets

**3. Build Configuration**
- [ ] Update version number
- [ ] Verify signing configuration
- [ ] Check deployment target
- [ ] Remove debug logging

### Creating Builds

**Development Build**:
```bash
xcodebuild -scheme Ark-wallet-prototype -configuration Debug -archivePath build/Debug.xcarchive archive
```

**Release Build**:
```bash
xcodebuild -scheme Ark-wallet-prototype -configuration Release -archivePath build/Release.xcarchive archive
```

---

*Note: This task guide should be updated as new common workflows emerge.*