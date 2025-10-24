# Testing Patterns and Strategies

This document outlines the testing approaches, patterns, and examples used throughout the Arké Wallet prototype project.

## Testing Philosophy

### Core Principles
- **Protocol-Based Testing**: Use abstract interfaces to enable comprehensive mocking
- **Service Isolation**: Test services independently with mocked dependencies
- **Realistic Test Data**: Use data that mirrors real-world scenarios
- **Error Scenario Coverage**: Test failure modes as thoroughly as success paths

### Testing Pyramid
```
UI Tests (SwiftUI Integration)
    ↑
Integration Tests (Service Coordination)
    ↑
Unit Tests (Individual Services & Models)
```

## Swift Testing Framework

This project uses Swift's modern testing framework with macros for clean, expressive tests.

### Basic Test Structure
```swift
import Testing
@testable import Ark_wallet_prototype

@Suite("Balance Service Tests")
struct BalanceServiceTests {
    
    @Test("Loading cached balance on startup")
    func loadCachedBalance() async throws {
        let mockWallet = MockBarkWallet()
        let service = BalanceService(wallet: mockWallet, ...)
        
        // Test implementation
        #expect(service.arkBalance != nil)
    }
}
```

### Testing Patterns

#### Async Operation Testing
```swift
@Test("Refresh balance updates properties")
func refreshBalanceUpdatesProperties() async throws {
    let mockWallet = MockBarkWallet()
    let service = BalanceService(wallet: mockWallet, ...)
    
    await service.refreshArkBalance()
    
    #expect(service.arkBalance?.spendableSat == 100000)
    #expect(service.error == nil)
}
```

#### Error Scenario Testing
```swift
@Test("Service handles wallet errors gracefully")
func serviceHandlesWalletErrors() async throws {
    let mockWallet = MockBarkWallet()
    mockWallet.shouldFailGetBalance = true
    
    let service = BalanceService(wallet: mockWallet, ...)
    await service.refreshArkBalance()
    
    #expect(service.error != nil)
    #expect(service.arkBalance == nil)
}
```

#### Optional Unwrapping in Tests
```swift
@Test("Balance calculation with valid data")
func balanceCalculationWithValidData() async throws {
    let service = createBalanceService()
    await service.refreshAllBalances()
    
    let arkBalance = try #require(service.arkBalance)
    let totalBalance = try #require(service.totalBalance)
    
    #expect(arkBalance.totalBalanceSat > 0)
    #expect(totalBalance.totalSpendableSat > 0)
}
```

## Service Testing Patterns

### BalanceService Testing
```swift
@Suite("Balance Service")
struct BalanceServiceTests {
    
    func createBalanceService(
        mockWallet: MockBarkWallet = MockBarkWallet(),
        cacheManager: WalletCacheManager = WalletCacheManager()
    ) -> BalanceService {
        return BalanceService(
            wallet: mockWallet,
            taskManager: TaskDeduplicationManager(),
            cacheManager: cacheManager
        )
    }
    
    @Test("Cached data loads immediately")
    func cachedDataLoadsImmediately() async throws {
        let service = createBalanceService()
        
        // Set up cached data
        service.setModelContext(mockModelContext)
        
        #expect(service.arkBalance != nil)
    }
    
    @Test("Fresh data updates cached values")
    func freshDataUpdatesCachedValues() async throws {
        let mockWallet = MockBarkWallet()
        let service = createBalanceService(mockWallet: mockWallet)
        
        await service.refreshArkBalance()
        
        #expect(mockWallet.getArkBalanceCallCount == 1)
        #expect(service.arkBalance?.spendableSat == mockWallet.mockArkBalance.spendableSat)
    }
}
```

### TransactionService Testing
```swift
@Suite("Transaction Service")
struct TransactionServiceTests {
    
    @Test("Transaction parsing handles complex movements")
    func transactionParsingHandlesComplexMovements() async throws {
        let mockWallet = MockBarkWallet()
        mockWallet.mockMovements = createComplexMovementData()
        
        let service = TransactionService(wallet: mockWallet, ...)
        await service.refreshTransactions()
        
        #expect(service.transactions.count > 0)
        #expect(service.transactions.contains { $0.type == .ark })
        #expect(service.transactions.contains { $0.direction == .incoming })
    }
}
```

## Mock Implementation Patterns

### MockBarkWallet Structure
```swift
class MockBarkWallet: BarkWalletProtocol {
    // Control flags for testing different scenarios
    var shouldFailGetBalance = false
    var shouldFailGetMovements = false
    
    // Call tracking
    var getArkBalanceCallCount = 0
    var getMovementsCallCount = 0
    
    // Mock data
    var mockArkBalance = ArkBalanceModel(...)
    var mockMovements: [MovementData] = []
    
    func getArkBalance() async throws -> ArkBalanceModel {
        getArkBalanceCallCount += 1
        
        if shouldFailGetBalance {
            throw WalletError.networkError("Mock network failure")
        }
        
        return mockArkBalance
    }
}
```

### Mock Data Creation
```swift
extension MockBarkWallet {
    static func createRealisticBalance() -> ArkBalanceModel {
        return ArkBalanceModel(
            spendableSat: 100_000,
            pendingLightningSendSat: 5_000,
            pendingInRoundSat: 0,
            pendingExitSat: 0,
            pendingBoardSat: 10_000
        )
    }
    
    static func createMovementHistory() -> [MovementData] {
        return [
            MovementData(
                txid: "abc123",
                amount: 50_000,
                direction: "incoming",
                timestamp: "2024-10-24T10:00:00Z",
                kind: "ark"
            ),
            // ... more realistic test data
        ]
    }
}
```

## SwiftData Testing

### Persistence Testing Patterns
```swift
@Suite("SwiftData Persistence")
struct PersistenceTests {
    
    func createTestModelContext() -> ModelContext {
        let schema = Schema([PersistedArkBalance.self, PersistedOnchainBalance.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        return container.mainContext
    }
    
    @Test("Balance persistence round trip")
    func balancePersistenceRoundTrip() throws {
        let context = createTestModelContext()
        let originalBalance = ArkBalanceModel.createSample()
        
        // Save to persistence
        let persisted = PersistedArkBalance(from: originalBalance)
        context.insert(persisted)
        try context.save()
        
        // Load from persistence
        let loaded = try context.fetch(FetchDescriptor<PersistedArkBalance>()).first
        let roundTripBalance = try #require(loaded).toArkBalanceModel()
        
        #expect(roundTripBalance.spendableSat == originalBalance.spendableSat)
        #expect(roundTripBalance.totalBalanceSat == originalBalance.totalBalanceSat)
    }
}
```

## Integration Testing

### Service Coordination Tests
```swift
@Suite("Service Integration")
struct ServiceIntegrationTests {
    
    @Test("WalletManager coordinates service updates")
    func walletManagerCoordinatesServiceUpdates() async throws {
        let mockWallet = MockBarkWallet()
        let manager = WalletManager(wallet: mockWallet)
        
        await manager.refreshAllData()
        
        #expect(manager.balanceService.arkBalance != nil)
        #expect(manager.transactionService.transactions.count > 0)
        #expect(manager.addressService.arkAddress != "")
    }
    
    @Test("Error in one service doesn't break others")
    func errorInOneServiceDoesntBreakOthers() async throws {
        let mockWallet = MockBarkWallet()
        mockWallet.shouldFailGetBalance = true  // Balance will fail
        
        let manager = WalletManager(wallet: mockWallet)
        await manager.refreshAllData()
        
        // Balance service should have error
        #expect(manager.balanceService.error != nil)
        
        // Other services should still work
        #expect(manager.transactionService.error == nil)
        #expect(manager.addressService.error == nil)
    }
}
```

## UI Testing with SwiftUI

### Preview Testing
```swift
#Preview("Balance View with Data") {
    let manager = WalletManager.preview
    manager.balanceService.arkBalance = ArkBalanceModel.createSample()
    
    return BalanceView()
        .environment(manager)
}

#Preview("Balance View Loading State") {
    let manager = WalletManager.preview
    manager.balanceService.arkBalance = nil
    
    return BalanceView()
        .environment(manager)
}
```

### UI Testing Patterns
```swift
@Suite("UI Integration")
struct UIIntegrationTests {
    
    @Test("Balance view updates when service data changes")
    @MainActor
    func balanceViewUpdatesWhenServiceDataChanges() async throws {
        let manager = WalletManager.preview
        
        // Simulate data loading
        manager.balanceService.arkBalance = ArkBalanceModel.createSample()
        
        // UI should reflect the change (implementation depends on specific UI testing needs)
        // This would typically involve UITest framework for full UI testing
    }
}
```

## Test Data Management

### Realistic Test Data
```swift
extension ArkBalanceModel {
    static func createSample() -> ArkBalanceModel {
        return ArkBalanceModel(
            spendableSat: 150_000,      // 0.0015 BTC
            pendingLightningSendSat: 10_000,
            pendingInRoundSat: 5_000,
            pendingExitSat: 0,
            pendingBoardSat: 25_000
        )
    }
    
    static func createZeroBalance() -> ArkBalanceModel {
        return ArkBalanceModel(
            spendableSat: 0,
            pendingLightningSendSat: 0,
            pendingInRoundSat: 0,
            pendingExitSat: 0,
            pendingBoardSat: 0
        )
    }
}
```

### Edge Case Data
```swift
extension TransactionModel {
    static func createLargeTransaction() -> TransactionModel {
        return TransactionModel(
            id: "large-tx-001",
            type: .ark,
            amount: 100_000_000,  // 1 BTC
            direction: .outgoing,
            timestamp: Date(),
            status: .confirmed
        )
    }
    
    static func createFailedTransaction() -> TransactionModel {
        return TransactionModel(
            id: "failed-tx-001",
            type: .onchain,
            amount: 50_000,
            direction: .outgoing,
            timestamp: Date(),
            status: .failed
        )
    }
}
```

## Performance Testing

### Load Testing Patterns
```swift
@Suite("Performance Tests")
struct PerformanceTests {
    
    @Test("Service handles large transaction history")
    func serviceHandlesLargeTransactionHistory() async throws {
        let mockWallet = MockBarkWallet()
        mockWallet.mockMovements = Array(repeating: MovementData.createSample(), count: 1000)
        
        let service = TransactionService(wallet: mockWallet, ...)
        
        let startTime = Date()
        await service.refreshTransactions()
        let duration = Date().timeIntervalSince(startTime)
        
        #expect(service.transactions.count == 1000)
        #expect(duration < 1.0)  // Should parse 1000 transactions in under 1 second
    }
}
```

## Error Testing Strategies

### Network Error Simulation
```swift
@Test("Services handle network failures gracefully")
func servicesHandleNetworkFailuresGracefully() async throws {
    let mockWallet = MockBarkWallet()
    mockWallet.simulateNetworkError = true
    
    let service = BalanceService(wallet: mockWallet, ...)
    await service.refreshArkBalance()
    
    #expect(service.error != nil)
    #expect(service.error?.contains("network") == true)
}
```

### Data Corruption Testing
```swift
@Test("Service handles malformed data")
func serviceHandlesMalformedData() async throws {
    let mockWallet = MockBarkWallet()
    mockWallet.returnMalformedData = true
    
    let service = TransactionService(wallet: mockWallet, ...)
    await service.refreshTransactions()
    
    // Service should handle gracefully, not crash
    #expect(service.error != nil)
    #expect(service.transactions.isEmpty)
}
```

## Test Organization

### File Structure
```
Tests/
├── ServiceTests/
│   ├── BalanceServiceTests.swift
│   ├── TransactionServiceTests.swift
│   └── AddressServiceTests.swift
├── ModelTests/
│   ├── ArkBalanceModelTests.swift
│   └── PersistenceModelTests.swift
├── IntegrationTests/
│   └── WalletManagerTests.swift
└── UITests/
    └── ContentViewTests.swift
```

### Test Naming Conventions
- Test suites: `[ComponentName]Tests`
- Test methods: Descriptive sentences explaining behavior
- Mock classes: `Mock[ProtocolName]`
- Test data: `create[Scenario][DataType]()`

## Continuous Integration

### Test Running Strategy
- Unit tests run on every commit
- Integration tests run on pull requests
- UI tests run on release branches
- Performance tests run nightly

### Coverage Goals
- Service logic: 90%+ coverage
- Model transformations: 95%+ coverage
- Error handling: 80%+ coverage
- UI components: Focus on critical user paths

---

*Note: This testing guide should evolve as new patterns emerge and testing strategies are refined.*