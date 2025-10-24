# Service Interfaces Reference

This document provides a comprehensive reference of all public interfaces for the application's core services.

## Service Overview

### BalanceService
**Purpose**: Manages Ark and onchain balance data with caching and persistence.

**Public Interface**:
```swift
@MainActor @Observable
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

### TransactionService
**Purpose**: Manages transaction history and movement data.

**Public Interface**:
```swift
@MainActor @Observable
class TransactionService {
    // Observable State
    var transactions: [TransactionModel]
    var error: String?
    var hasLoadedTransactions: Bool
    
    // Primary Methods
    func setModelContext(_: ModelContext)
    func refreshTransactions() async
    func resetTransactions()
}
```

### AddressService
**Purpose**: Manages wallet addresses for Ark and onchain operations.

**Public Interface**:
```swift
@MainActor @Observable
class AddressService {
    // Observable State
    var arkAddress: String
    var onchainAddress: String
    var error: String?
    
    // Primary Methods
    func loadAddresses() async
    func refreshAddresses() async
}
```

### WalletOperationsService
**Purpose**: Handles active wallet operations like sending, boarding, and Lightning operations.

**Public Interface**:
```swift
@MainActor @Observable
class WalletOperationsService {
    // Observable State
    var isProcessing: Bool
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

## Core Protocols

### BarkWalletProtocol
**Purpose**: Abstract interface for wallet operations, enabling testing and mock implementations.

**Key Methods**:
```swift
protocol BarkWalletProtocol {
    func getArkBalance() async throws -> ArkBalanceModel
    func getOnchainBalance() async throws -> OnchainBalanceModel
    func getMovements() async throws -> [TransactionModel]
    func getArkAddress() async throws -> String
    func getOnchainAddress() async throws -> String
    func sendArk(to: String, amount: Int) async throws
    func sendOnchain(to: String, amount: Int) async throws
    // ... additional methods
}
```

## Infrastructure Services

### TaskDeduplicationManager
**Purpose**: Prevents duplicate concurrent operations.

**Public Interface**:
```swift
class TaskDeduplicationManager {
    func execute<T>(key: String, operation: @escaping () async throws -> T) async throws -> T
}
```

### WalletCacheManager
**Purpose**: Generic short-term caching with configurable timeouts.

**Public Interface**:
```swift
class WalletCacheManager {
    func getValue<T>(for key: String) -> T?
    func setValue<T>(_: T, for key: String, timeout: TimeInterval)
    func isValid(for key: String) -> Bool
    func clear()
}
```

## Usage Patterns

### Service Initialization
All services follow dependency injection pattern:
```swift
let service = BalanceService(
    wallet: walletImplementation,
    taskManager: taskDeduplicationManager,
    cacheManager: cacheManager
)
```

### Error Handling
All services provide error information via observable properties:
```swift
if let error = balanceService.error {
    // Display error to user
}
```

### Async Operations
All data-fetching methods are async and should be called from async contexts:
```swift
Task {
    await balanceService.refreshAllBalances()
}
```

---

*Note: This is a living document that should be updated as service interfaces evolve.*