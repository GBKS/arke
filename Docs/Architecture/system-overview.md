# System Overview

## Architecture Summary

This is an iOS application built with SwiftUI that provides a user interface for managing Ark and Bitcoin wallets. The application follows a clean service-oriented architecture with clear separation of concerns, dependency injection, and comprehensive caching strategies.

## Core Architecture Pattern

The application uses a **Service-Oriented Architecture** with:
- **Central Coordinator**: `WalletManager` coordinates all services
- **Specialized Services**: Each service handles a specific domain (balances, transactions, addresses, operations)
- **Protocol-Based Abstraction**: Core wallet functionality abstracted behind `BarkWalletProtocol`
- **Reactive UI**: SwiftUI views observe services using `@Observable`
- **Persistent Caching**: SwiftData provides local storage with intelligent cache invalidation

## Major Components

### 1. WalletManager (Central Coordinator)
**File**: `WalletManager.swift`
**Role**: Central coordinator that orchestrates all wallet operations and maintains application state.

**Responsibilities**:
- Initializes and manages all specialized services
- Provides computed properties for UI consumption
- Handles application lifecycle (initialization, refresh, reset)
- Manages export/import functionality
- Coordinates data flow between services

**Key Dependencies**:
- All specialized services (BalanceService, TransactionService, etc.)
- BarkWalletProtocol implementation
- SwiftData ModelContext for persistence

### 2. Specialized Services Layer

#### BalanceService
**File**: `BalanceService.swift`
**Domain**: All balance-related operations (Ark, Onchain, and combined totals)

**Responsibilities**:
- Fetch and cache Ark and Onchain balances
- Calculate combined balance totals
- Manage balance persistence with SwiftData
- Provide formatted balance data for UI

#### TransactionService
**File**: `TransactionService.swift`
**Domain**: Transaction history and movement tracking

**Responsibilities**:
- Fetch and parse transaction data from wallet
- Convert raw movement data to UI-friendly models
- Cache transaction history
- Provide transaction filtering and organization

#### AddressService
**File**: `AddressService.swift`
**Domain**: Wallet address management

**Responsibilities**:
- Manage Ark and Onchain addresses
- Provide address refresh capabilities
- Handle address-related errors

#### WalletOperationsService
**File**: `WalletOperationsService.swift`
**Domain**: Wallet operations (send, receive, boarding, etc.)

**Responsibilities**:
- Handle sending transactions (Ark and Onchain)
- Manage boarding operations
- Process Lightning invoice operations
- Coordinate complex wallet operations

### 3. Wallet Abstraction Layer

#### BarkWalletProtocol
**File**: `BarkWalletProtocol.swift`
**Role**: Protocol defining all wallet operations

**Benefits**:
- Enables mock implementations for testing and previews
- Provides clean abstraction over external wallet library
- Allows for future wallet backend changes

#### BarkWallet (Implementation)
**File**: `BarkWallet.swift`
**Role**: Concrete implementation using external `bark` binary

**Responsibilities**:
- Execute wallet commands via external process
- Handle process communication and error handling
- Provide preview/mock mode for development

### 4. Data Models Layer

#### UI Models
- **ArkBalanceModel**: Ark-specific balance data with computed properties
- **OnchainBalanceModel**: Bitcoin onchain balance data
- **TransactionModel**: Transaction history representation
- **VTXOModel**, **UTXOModel**: UTXO management models

#### Persistence Models
- **PersistedArkBalance**: SwiftData model for caching Ark balances
- **PersistedOnchainBalance**: SwiftData model for caching Onchain balances

### 5. Infrastructure Layer

#### TaskDeduplicationManager
**File**: `TaskDeduplicationManager.swift`
**Purpose**: Prevents duplicate API calls and ensures consistent state

**Benefits**:
- Prevents race conditions
- Reduces unnecessary network calls
- Improves performance and reliability

#### WalletCacheManager
**File**: `CacheManager.swift`
**Purpose**: Generic caching system with configurable timeouts

**Features**:
- Time-based cache invalidation
- Type-safe generic implementation
- Configurable cache timeouts per data type

## Data Flow Architecture

### 1. User Interaction Flow
```
UI (SwiftUI Views) 
    ↓ (user actions)
WalletManager 
    ↓ (delegates to appropriate service)
Service Layer (BalanceService, TransactionService, etc.)
    ↓ (calls wallet operations)
BarkWallet (via BarkWalletProtocol)
    ↓ (executes commands)
External Bark Binary
```

### 2. Data Update Flow
```
External Bark Binary
    ↓ (returns data)
BarkWallet 
    ↓ (parses and converts to models)
Service Layer
    ↓ (updates @Observable properties & caches to SwiftData)
UI (automatically updates via SwiftUI observation)
```

### 3. Caching Strategy
**Two-Tier Caching System**:
- **Memory Cache**: `WalletCacheManager` for short-term caching (5 minutes)
- **Persistent Cache**: SwiftData for long-term storage and offline capability

## Key Design Principles

### 1. Separation of Concerns
- Each service handles exactly one domain
- Clear boundaries between UI, business logic, and data access
- Protocol-based abstraction separates interface from implementation

### 2. Reactive Architecture
- Services are `@Observable` classes
- UI automatically updates when data changes
- Minimal manual state management required

### 3. Error Resilience
- Graceful degradation when services fail
- Cached data provides offline functionality
- Comprehensive error logging and user feedback

### 4. Performance Optimization
- Task deduplication prevents redundant operations
- Intelligent caching reduces API calls
- Background data loading with immediate cached data display

### 5. Testability
- Protocol-based architecture enables easy mocking
- Service isolation makes unit testing straightforward
- SwiftData provides consistent test data patterns

## Integration Points

### External Dependencies
- **Bark Binary**: External wallet implementation
- **SwiftData**: Apple's persistence framework
- **Foundation**: Network requests and system integration

### Apple Platform Integration
- **SwiftUI**: Reactive UI framework
- **Swift Concurrency**: async/await throughout the stack
- **Observation Framework**: Modern SwiftUI state management

## Benefits of This Architecture

### Developer Experience
- **Clear Structure**: Easy to understand component relationships
- **Maintainable**: Changes isolated to specific services
- **Testable**: Protocol-based design enables comprehensive testing
- **Extensible**: New features can be added as new services

### User Experience
- **Fast Loading**: Cached data provides instant app startup
- **Offline Capable**: Persistent cache works without network
- **Reliable**: Error handling and graceful degradation
- **Responsive**: Reactive UI updates automatically

### Technical Benefits
- **Performance**: Intelligent caching and task deduplication
- **Consistency**: Centralized state management
- **Scalability**: Service-oriented design supports feature growth
- **Maintainability**: Clear separation of concerns and consistent patterns