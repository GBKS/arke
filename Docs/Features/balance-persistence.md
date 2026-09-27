# Balance Model Persistence Implementation

## Overview
This implementation adds persistent storage for both `ArkBalanceModel` and `OnchainBalanceModel` using SwiftData, following a consistent pattern throughout the application. The implementation provides fast app startup times and offline capability by caching balance data locally.

## Files Modified/Created

### New Files
- **PersistedArkBalance.swift**: SwiftData model for persisting ArkBalanceModel data
- **PersistedOnchainBalance.swift**: SwiftData model for persisting OnchainBalanceModel data
- Enhanced test coverage in **Ark_wallet_prototypeTests.swift**

### Modified Files
- **Ark_wallet_prototypeApp.swift**: Added both persistence models to ModelContainer
- **BalanceService.swift**: Added persistence methods and ModelContext support for both balance types
- **WalletManager.swift**: Updated to pass ModelContext to BalanceService

## Implementation Details

### 1. Persistence Models

#### PersistedArkBalance
```swift
@Model
class PersistedArkBalance {
    var id: String = "ark_balance"  // Singleton approach
    var spendableSat: Int
    var pendingLightningSendSat: Int
    var pendingInRoundSat: Int
    var pendingExitSat: Int
    var pendingBoardSat: Int
    var lastUpdated: Date
}
```

#### PersistedOnchainBalance
```swift
@Model
class PersistedOnchainBalance {
    var id: String = "onchain_balance"  // Singleton approach
    var totalSat: Int
    var trustedSpendableSat: Int
    var immatureSat: Int
    var trustedPendingSat: Int
    var untrustedPendingSat: Int
    var confirmedSat: Int
    var lastUpdated: Date
}
```

**Key Features:**
- Singleton pattern using fixed IDs ("ark_balance" and "onchain_balance")
- 5-minute cache validity window
- Bidirectional conversion with their respective UI models
- Built-in update methods for efficient data refresh

### 2. BalanceService Persistence Integration

**New Methods:**
- `setModelContext(_:)`: Initialize persistence and load cached data for both balance types
- `loadPersistedArkBalance()`: Load cached Ark balance on app startup
- `loadPersistedOnchainBalance()`: Load cached Onchain balance on app startup
- `saveArkBalanceToSwiftData(_:)`: Save Ark balance data to persistence
- `saveOnchainBalanceToSwiftData(_:)`: Save Onchain balance data to persistence
- `clearPersistedArkBalance()`: Clear cached Ark balance during reset
- `clearPersistedOnchainBalance()`: Clear cached Onchain balance during reset

**Enhanced Methods:**
- `refreshArkBalance()`: Now saves to persistence after successful fetch
- `refreshOnchainBalance()`: Now saves to persistence after successful fetch
- `refreshAllBalances()`: Now saves both balance types to persistence
- `resetBalances()`: Now clears both persisted balance types

### 3. Cache Strategy

**Validity Period:** 5 minutes for both balance types
- Fresh data: Used immediately from cache
- Stale data: Triggers fresh fetch from wallet
- No data: Falls back to wallet fetch

**Storage Pattern:**
- Single record per balance type per wallet (replaces existing data)
- Automatic timestamp management
- Graceful degradation if persistence fails
- Independent caching for each balance type

## Benefits

### User Experience
- **Instant Balance Display**: App shows last known balances immediately on startup
- **Offline Capability**: Both balance types available when network is unavailable
- **Reduced Loading Times**: Eliminates wait time for balance data during app launch
- **Consistent Performance**: Both Ark and Onchain balances benefit equally

### Performance
- **Reduced API Calls**: Intelligent caching prevents unnecessary network requests for both balance types
- **Background Updates**: Fresh data fetched in background while showing cached data
- **Efficient Memory Usage**: Singleton pattern minimizes storage overhead
- **Parallel Operations**: Both balances can be cached and retrieved independently

### Reliability
- **Graceful Degradation**: App functions normally even if persistence fails for either balance type
- **Data Consistency**: Automatic cleanup and validation of cached data
- **Error Handling**: Comprehensive error logging and fallback mechanisms
- **Independent Failures**: One balance type can fail without affecting the other

## Testing
Comprehensive test suite covering both balance types:
- Model conversion and data integrity
- Cache validity logic
- Update functionality
- Round-trip data conversion
- Computed property validation

## Architecture Consistency
This implementation maintains perfect consistency across both balance types:
- Identical SwiftData patterns and conventions
- Same error handling approaches
- Consistent method naming and structure
- Seamless integration with existing services
- Parallel processing capabilities

## Usage
The persistence system is completely transparent to the UI layer. Existing code continues to work without changes, but now benefits from:
- Faster initial data loading for both balance types
- Better offline experience with full balance information
- Reduced network dependency
- Improved perceived performance across the entire balance system

The implementation follows Apple's recommended patterns for SwiftData usage and maintains the clean separation of concerns established in the existing codebase, now covering the complete balance ecosystem.