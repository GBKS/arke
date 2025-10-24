# Data Flow Architecture

## Overview
This document describes how data moves through the application, from external wallet operations to UI display. The architecture emphasizes reactive patterns, intelligent caching, and clean separation between data sources and presentation.

## Core Data Flow Patterns

### 1. User-Initiated Actions
The most common flow starts with user interaction and propagates through the system:

```
SwiftUI View
    ↓ (user tap/action)
WalletManager (coordinator method)
    ↓ (delegates to appropriate service)
SpecializedService (BalanceService, TransactionService, etc.)
    ↓ (calls with task deduplication)
BarkWallet (via BarkWalletProtocol)
    ↓ (executes external command)
Bark Binary (external process)
    ↓ (returns JSON/text data)
BarkWallet (parses response)
    ↓ (converts to UI models)
SpecializedService (updates @Observable properties)
    ↓ (automatic SwiftUI observation)
SwiftUI View (re-renders automatically)
```

### 2. Background Data Refresh
Proactive data updates happen in the background while showing cached data:

```
App Startup/Timer
    ↓
WalletManager.refreshAllData()
    ↓ (parallel execution)
[BalanceService.refresh(), TransactionService.refresh(), ...]
    ↓ (each service independently)
Check Cache Validity
    ↓ (if stale or missing)
Fetch from Wallet
    ↓ (update both memory and persistent cache)
Update @Observable Properties
    ↓ (automatic UI updates)
SwiftUI Views Re-render
```

### 3. Cache-First Loading
On app launch, data is served immediately from cache while fresh data loads:

```
App Launch
    ↓
WalletManager.initialize()
    ↓
Services.setModelContext() 
    ↓ (loads from SwiftData immediately)
Services Load Cached Data → UI Shows Immediately
    ↓ (simultaneously in background)
Services.refresh() → Fresh Data → UI Updates Reactively
```

## Service-Specific Data Flows

### Balance Data Flow

#### Cache Strategy
- **Memory Cache**: 5-minute validity via `WalletCacheManager`
- **Persistent Cache**: Unlimited validity via SwiftData
- **Refresh Logic**: Stale cache triggers background refresh

#### Flow Sequence
```
BalanceService.refreshArkBalance()
    ↓
Check Memory Cache (5min validity)
    ↓ (if valid)
Return Cached → Update UI
    ↓ (if stale/missing)
Call BarkWallet.getArkBalance()
    ↓
Parse JSON Response → ArkBalanceModel
    ↓
Update Memory Cache
    ↓
Save to SwiftData (PersistedArkBalance)
    ↓
Update @Observable arkBalance property
    ↓
UI Auto-updates via SwiftUI Observation
```

### Transaction Data Flow

#### Unique Characteristics
- **Complex Parsing**: Raw movement data requires significant transformation
- **Historical Data**: Large datasets that benefit from caching
- **Incremental Updates**: New transactions append to existing list

#### Flow Sequence
```
TransactionService.refreshTransactions()
    ↓
BarkWallet.getMovements() → Raw JSON
    ↓
Parse MovementData structures
    ↓
Transform to TransactionModel objects
    ↓
Update @Observable transactions array
    ↓
UI List Updates Automatically
```

### Address Data Flow

#### Simple Fetch Pattern
- **Rarely Changes**: Addresses are relatively static
- **Quick Operations**: Simple string responses
- **Task Deduplication**: Prevents redundant calls

#### Flow Sequence
```
AddressService.loadAddresses()
    ↓
TaskDeduplicationManager.execute("addresses")
    ↓
[BarkWallet.getArkAddress(), BarkWallet.getOnchainAddress()]
    ↓
Update @Observable properties [arkAddress, onchainAddress]
    ↓
UI Updates Automatically
```

## Caching Architecture

### Two-Tier Caching System

#### Tier 1: Memory Cache (WalletCacheManager)
- **Purpose**: Short-term performance optimization
- **Lifetime**: 5 minutes (configurable per data type)
- **Benefits**: Eliminates redundant API calls during active use
- **Scope**: Per-app-session only

#### Tier 2: Persistent Cache (SwiftData)
- **Purpose**: Long-term storage and offline capability
- **Lifetime**: Persists across app launches
- **Benefits**: Instant app startup, offline functionality
- **Scope**: Device-permanent until explicitly cleared

### Cache Invalidation Strategy

#### Time-Based Invalidation
```swift
// Memory cache check
if cacheManager.isValid {
    return cacheManager.value
}

// Persistent cache check (5-minute validity)
if let persisted = getPersistedData(),
   Date().timeIntervalSince(persisted.lastUpdated) < 300 {
    return persisted.toUIModel()
}

// Fall back to fresh fetch
return try await fetchFromWallet()
```

#### Manual Invalidation
- **User Refresh**: Explicit refresh bypasses all caches
- **Wallet Reset**: Clears both memory and persistent caches
- **Error Recovery**: Failed operations may trigger cache clearing

## Error Handling and Fallbacks

### Graceful Degradation Pattern
```
Try Fresh Data Fetch
    ↓ (if fails)
Try Memory Cache
    ↓ (if empty/stale)
Try Persistent Cache
    ↓ (if empty)
Show Empty State with Error Message
    ↓ (user can retry)
Fresh Fetch Attempt
```

### Error Propagation
- **Service Level**: Capture and log errors, update error properties
- **UI Level**: Show user-friendly messages, provide retry options
- **Data Integrity**: Never corrupt existing good data with failed operations

## Concurrency and State Management

### Task Deduplication
Prevents multiple simultaneous operations on the same data:

```swift
// Multiple UI requests for same data result in single API call
let balance1 = balanceService.getArkBalance() // Starts API call
let balance2 = balanceService.getArkBalance() // Waits for existing call
let balance3 = balanceService.getArkBalance() // Waits for existing call

// All three receive the same result from single API operation
```

### Thread Safety
- **@MainActor Services**: All UI-updating services run on main thread
- **Background Tasks**: Heavy operations (parsing, network) use background threads
- **SwiftUI Integration**: Automatic main thread dispatch for UI updates

## Data Transformation Pipeline

### Raw Data → UI Models
Each data type follows a consistent transformation pattern:

```
External JSON/Text
    ↓ (BarkWallet parsing)
Intermediate Structures (MovementData, etc.)
    ↓ (Service layer transformation)
UI Models (ArkBalanceModel, TransactionModel, etc.)
    ↓ (SwiftUI consumption)
Formatted Display Data
```

### Model Conversion Examples

#### Balance Data
```
Bark JSON → ArkBalanceModel → PersistedArkBalance → UI Display
         ↑                                      ↓
    (parse JSON)                        (format for display)
```

#### Transaction Data
```
Bark JSON → MovementData[] → TransactionModel[] → UI List Items
         ↑                                     ↓
   (complex parsing)                   (formatted display)
```

## Performance Optimizations

### Lazy Loading
- **Initial Load**: Show cached data immediately
- **Background Refresh**: Update with fresh data asynchronously
- **Progressive Enhancement**: Users see data instantly, then fresh updates

### Batch Operations
- **Parallel Fetching**: Balance and transaction data load simultaneously
- **Coordinated Updates**: UI updates once when all data is ready
- **Efficient Rendering**: SwiftUI optimizes multiple property changes

### Memory Management
- **Weak References**: Services don't retain each other
- **Cache Limits**: Prevent unbounded memory growth
- **Cleanup Patterns**: Clear resources on wallet reset

## Integration Benefits

### Developer Benefits
- **Predictable Flow**: Consistent patterns across all data types
- **Debuggable**: Clear data transformation steps
- **Testable**: Each step can be mocked and verified

### User Benefits
- **Fast Startup**: Cached data displays immediately
- **Offline Capability**: App works without network connection
- **Real-time Updates**: Fresh data appears automatically
- **Reliable Experience**: Graceful handling of network issues

This data flow architecture ensures that users always see the most recent data available while providing excellent performance and offline capability.