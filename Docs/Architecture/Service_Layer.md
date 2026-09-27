# Service Layer Architecture

## Overview
The service layer implements a clean separation of concerns where each service manages a specific domain of wallet functionality. Services are designed as `@Observable` classes that provide reactive data to SwiftUI views while abstracting complex wallet operations and caching logic.

## Service Design Principles

### 1. Single Responsibility
Each service handles exactly one domain:
- **BalanceService**: All balance-related operations and calculations
- **TransactionService**: Transaction history and movement tracking  
- **AddressService**: Wallet address management
- **WalletOperationsService**: Active wallet operations (send, receive, etc.)

### 2. Observable State
All services use Swift's `@Observable` macro for reactive UI integration:
```swift
@MainActor
@Observable
class BalanceService {
    var arkBalance: ArkBalanceModel?
    var onchainBalance: OnchainBalanceModel?
    var error: String?
    // UI automatically updates when these change
}
```

### 3. Dependency Injection
Services receive their dependencies through initializers:
```swift
init(wallet: BarkWalletProtocol, 
     taskManager: TaskDeduplicationManager, 
     cacheManager: WalletCacheManager) {
    self.wallet = wallet
    self.taskManager = taskManager
    self.cacheManager = cacheManager
}
```

### 4. Error Handling
Consistent error handling pattern across services:
- Capture errors at service level
- Update error properties for UI display
- Log detailed information for debugging
- Provide graceful fallbacks

## Individual Service Specifications

### BalanceService

**File**: `BalanceService.swift`  
**Domain**: Balance management for Ark and Onchain wallets

#### Public Interface
```swift
class BalanceService {
    // Observable State
    var arkBalance: ArkBalanceModel?
    var onchainBalance: OnchainBalanceModel?
    var totalBalance: TotalBalanceModel?
    var error: String?
    
    // Computed Properties
    var hasPendingBalance: Bool
    var hasSpendableBalance: Bool
    var arkInfo: ArkInfoModel?
    var estimatedBlockHeight: Int?
    
    // Primary Methods
    func setModelContext(_: ModelContext)
    func refreshArkBalance() async
    func refreshOnchainBalance() async  
    func refreshAllBalances() async
    func resetBalances()
}
```

#### Key Responsibilities
- **Data Fetching**: Get balance data from wallet with task deduplication
- **Cache Management**: Implement two-tier caching (memory + SwiftData persistence)
- **Data Aggregation**: Calculate combined balances across wallet types
- **State Updates**: Maintain reactive properties for UI consumption

#### Caching Strategy
- **Memory Cache**: 5-minute validity for performance
- **Persistent Cache**: SwiftData storage for offline capability
- **Cache Invalidation**: Time-based and manual refresh options
- **Graceful Degradation**: Falls back gracefully if caching fails

### TransactionService

**File**: `TransactionService.swift`  
**Domain**: Transaction history and movement data

#### Public Interface
```swift
class TransactionService {
    // Observable State
    var transactions: [TransactionModel] = []
    var error: String?
    var hasLoadedTransactions: Bool = false
    
    // Primary Methods
    func setModelContext(_: ModelContext)
    func refreshTransactions() async
    func resetTransactions()
}
```

#### Key Responsibilities
- **Data Parsing**: Transform complex movement data into UI-friendly models
- **Historical Data**: Manage large transaction datasets efficiently
- **State Tracking**: Track loading state for UI indicators
- **Data Persistence**: Future enhancement for transaction caching

#### Unique Challenges
- **Complex Data Structure**: Raw movement data requires extensive parsing
- **Large Datasets**: Transaction history can be substantial
- **Real-time Updates**: New transactions must integrate with existing history

### AddressService

**File**: `AddressService.swift`  
**Domain**: Wallet address management

#### Public Interface
```swift
class AddressService {
    // Observable State
    var arkAddress: String = ""
    var onchainAddress: String = ""
    var error: String?
    
    // Primary Methods
    func loadAddresses() async
    func refreshAddresses() async
}
```

#### Key Responsibilities
- **Address Management**: Maintain current Ark and Onchain addresses
- **Task Deduplication**: Prevent redundant address fetching
- **Simple Interface**: Provide clean string properties for UI

#### Design Rationale
- **Stateful**: Addresses rarely change, so caching in properties is efficient
- **Lightweight**: Simple string data doesn't require complex caching
- **Reliable**: Address data is critical for all wallet operations

### WalletOperationsService

**File**: `WalletOperationsService.swift`  
**Domain**: Active wallet operations

#### Public Interface
```swift
class WalletOperationsService {
    // Observable State  
    var isProcessing: Bool = false
    var operationError: String?
    
    // Transaction Operations
    func sendArk(to: String, amount: Int) async throws
    func sendOnchain(to: String, amount: Int) async throws
    
    // Boarding Operations
    func boardFunds(amount: Int) async throws
    func boardAllFunds() async throws
    
    // Lightning Operations
    func payLightningInvoice(invoice: String, amount: Int) async throws
    func createLightningInvoice(amount: Int) async throws -> String
    
    // VTXO Operations
    func refreshVTXOs() async throws
    func exitVTXO(id: String) async throws
}
```

#### Key Responsibilities
- **Transaction Execution**: Handle sending operations with proper error handling
- **Operation Status**: Track processing state for UI feedback
- **Complex Operations**: Coordinate multi-step operations like boarding
- **Error Recovery**: Provide detailed error information for user action

## Service Coordination Patterns

### WalletManager as Coordinator
The `WalletManager` acts as the central coordinator that:
- **Initializes Services**: Creates and configures all services
- **Delegates Operations**: Routes operations to appropriate services
- **Aggregates Data**: Provides unified access to service data
- **Manages Lifecycle**: Handles app-wide operations like reset

### Inter-Service Communication
Services generally operate independently, but coordination happens via:
- **Shared Dependencies**: Common TaskDeduplicationManager and CacheManager
- **WalletManager Mediation**: Complex operations coordinated at manager level
- **Event-Driven Updates**: Operations in one service may trigger updates in others

### Example Coordination Flow
```swift
// User initiates send operation
WalletManager.sendArk(to: address, amount: amount)
    ↓
WalletOperationsService.sendArk() // Executes transaction
    ↓
WalletManager.refreshAllData() // Updates all services
    ↓
[BalanceService.refresh(), TransactionService.refresh()] // Parallel updates
```

## Common Service Patterns

### Task Deduplication Pattern
All services use the same deduplication approach:
```swift
func refreshData() async {
    await taskManager.execute(key: "dataType") {
        await self.performActualRefresh()
    }
}
```

### Error Handling Pattern
Consistent error management across services:
```swift
do {
    let result = try await wallet.operation()
    self.updateState(result)
    self.error = nil
} catch {
    print("❌ Operation failed: \(error)")
    self.error = error.localizedDescription
}
```

### Cache Integration Pattern
Services that use caching follow this pattern:
```swift
func loadCachedData() {
    // Load from SwiftData on startup
    if let cached = loadPersistedData(), cached.isValid {
        self.updateState(cached.toUIModel())
    }
}

func refreshData() async {
    let fresh = try await fetchFreshData()
    saveToPersistence(fresh)
    self.updateState(fresh)
}
```

## Service Dependencies

### Core Dependencies
All services depend on:
- **BarkWalletProtocol**: Abstract wallet interface
- **TaskDeduplicationManager**: Prevents duplicate operations
- **Optional ModelContext**: For SwiftData persistence

### Optional Dependencies
Some services use:
- **WalletCacheManager**: For short-term memory caching
- **Formatters**: For data presentation (BitcoinFormatter, etc.)

### Dependency Injection Flow
```
WalletManager
    ↓ (creates and configures)
Services (with injected dependencies)
    ↓ (uses protocols, not concrete types)
Abstract Interfaces (BarkWalletProtocol, etc.)
```

## Testing Strategy

### Service-Level Testing
Each service can be tested independently:
- **Mock Dependencies**: Use protocol-based mocking
- **Isolated Testing**: Test service logic without external dependencies
- **State Verification**: Verify @Observable property updates

### Integration Testing
Services are tested together:
- **Coordination Logic**: Verify WalletManager orchestration
- **Data Flow**: Test end-to-end data transformations
- **Error Scenarios**: Test failure handling across services

## Performance Characteristics

### Memory Efficiency
- **Lean State**: Services only hold necessary data in memory
- **Weak References**: Services don't create retain cycles
- **Cleanup**: Proper cleanup on wallet reset

### Network Efficiency
- **Task Deduplication**: Prevents redundant API calls
- **Intelligent Caching**: Reduces network requests
- **Background Updates**: Non-blocking data refresh

### UI Responsiveness
- **Main Actor**: UI updates happen on main thread
- **Reactive Properties**: Automatic UI updates via @Observable
- **Async Operations**: Non-blocking service operations

## Evolution and Extensibility

### Adding New Services
New services follow the established patterns:
1. Implement `@MainActor @Observable` class
2. Use dependency injection for external dependencies
3. Follow consistent error handling patterns
4. Integrate with task deduplication and caching where appropriate

### Extending Existing Services
Services can be extended through:
- **New Methods**: Add functionality while maintaining existing interface
- **New Properties**: Add reactive state for new features
- **Enhanced Caching**: Add persistence for new data types

### Migration Patterns
When services need significant changes:
- **Protocol Evolution**: Update interfaces incrementally
- **Backward Compatibility**: Maintain existing functionality during transitions
- **Data Migration**: Handle changes to cached data structures

This service layer architecture provides a solid foundation for wallet functionality while maintaining clean separation of concerns, testability, and performance.