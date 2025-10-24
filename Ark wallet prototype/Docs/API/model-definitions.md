# Model Definitions Reference

This document provides comprehensive reference information for all data models used throughout the application.

## UI Models

### Balance Models

#### ArkBalanceModel
Represents Ark protocol balance information with computed properties for display.

**Properties**:
```swift
struct ArkBalanceModel {
    let spendableSat: Int
    let pendingLightningSendSat: Int
    let pendingInRoundSat: Int
    let pendingExitSat: Int
    let pendingBoardSat: Int
    
    // Computed Properties
    var totalPendingSat: Int { ... }
    var totalBalanceSat: Int { ... }
    var spendableFormatted: String { ... }
    var totalPendingFormatted: String { ... }
    var totalBalanceFormatted: String { ... }
}
```

#### OnchainBalanceModel
Represents Bitcoin onchain balance information.

**Properties**:
```swift
struct OnchainBalanceModel {
    let totalSat: Int
    let trustedSpendableSat: Int
    let immatureSat: Int
    let trustedPendingSat: Int
    let untrustedPendingSat: Int
    let confirmedSat: Int
    
    // Computed Properties
    var totalFormatted: String { ... }
    var trustedSpendableFormatted: String { ... }
    var confirmedFormatted: String { ... }
}
```

#### TotalBalanceModel
Aggregates Ark and onchain balances for unified display.

**Properties**:
```swift
struct TotalBalanceModel {
    let arkBalance: ArkBalanceModel
    let onchainBalance: OnchainBalanceModel
    
    // Computed Properties
    var totalSpendableSat: Int { ... }
    var totalBalanceSat: Int { ... }
    var totalSpendableFormatted: String { ... }
    var totalBalanceFormatted: String { ... }
}
```

### Transaction Models

#### TransactionModel
Represents a wallet transaction or movement.

**Properties**:
```swift
struct TransactionModel: Identifiable {
    let id: String
    let type: TransactionType
    let amount: Int
    let direction: TransactionDirection
    let timestamp: Date
    let status: TransactionStatus
    let description: String?
    
    // Computed Properties
    var amountFormatted: String { ... }
    var displayDescription: String { ... }
}
```

**Enums**:
```swift
enum TransactionType {
    case ark
    case onchain
    case lightning
    case board
    case offboard
}

enum TransactionDirection {
    case incoming
    case outgoing
}

enum TransactionStatus {
    case pending
    case confirmed
    case failed
}
```

### VTXO and UTXO Models

#### VTXOModel
Represents Ark protocol Virtual Transaction Outputs.

**Properties**:
```swift
struct VTXOModel: Identifiable {
    let id: String
    let amount: Int
    let expiry: Date
    let isExpired: Bool
    let round: Int
    
    // Computed Properties
    var amountFormatted: String { ... }
    var expiryFormatted: String { ... }
}
```

#### UTXOModel
Represents Bitcoin Unspent Transaction Outputs.

**Properties**:
```swift
struct UTXOModel: Identifiable {
    let id: String
    let amount: Int
    let confirmations: Int
    let isConfirmed: Bool
    let txid: String
    let vout: Int
    
    // Computed Properties
    var amountFormatted: String { ... }
}
```

## Persistence Models

### PersistedArkBalance
SwiftData model for caching Ark balance information.

**Properties**:
```swift
@Model
class PersistedArkBalance {
    var id: String = "ark_balance"
    var spendableSat: Int
    var pendingLightningSendSat: Int
    var pendingInRoundSat: Int
    var pendingExitSat: Int
    var pendingBoardSat: Int
    var lastUpdated: Date
    
    // Methods
    func toArkBalanceModel() -> ArkBalanceModel
    func update(from model: ArkBalanceModel)
    var isValid: Bool { ... }
}
```

### PersistedOnchainBalance
SwiftData model for caching onchain balance information.

**Properties**:
```swift
@Model
class PersistedOnchainBalance {
    var id: String = "onchain_balance"
    var totalSat: Int
    var trustedSpendableSat: Int
    var immatureSat: Int
    var trustedPendingSat: Int
    var untrustedPendingSat: Int
    var confirmedSat: Int
    var lastUpdated: Date
    
    // Methods
    func toOnchainBalanceModel() -> OnchainBalanceModel
    func update(from model: OnchainBalanceModel)
    var isValid: Bool { ... }
}
```

## Intermediate Data Models

### MovementData
Raw data structure from wallet for transaction parsing.

**Properties**:
```swift
struct MovementData {
    let txid: String
    let amount: Int
    let direction: String
    let timestamp: String
    let kind: String
    // Additional raw fields from wallet response
}
```

### ArkInfoModel
Information about the connected Ark server.

**Properties**:
```swift
struct ArkInfoModel {
    let serverUrl: String
    let currentRound: Int
    let nextRoundTime: Date?
    let networkFee: Int
    let coordinatorFee: Int
    
    // Computed Properties
    var nextRoundFormatted: String { ... }
    var networkFeeFormatted: String { ... }
}
```

## Model Relationships

### Data Flow Transformations
```
Raw Wallet Data → Intermediate Models → UI Models → Persistence Models
                                    ↓
                              SwiftUI Display
```

### Conversion Patterns

#### UI Model ↔ Persistence Model
All UI models have corresponding persistence models with bidirectional conversion:
```swift
// UI to Persistence
let persisted = PersistedArkBalance(from: arkBalanceModel)

// Persistence to UI  
let uiModel = persistedBalance.toArkBalanceModel()
```

#### Raw Data → UI Model
Raw wallet responses are transformed into UI-friendly models:
```swift
// Example transformation
func parseMovements(_ rawData: [MovementData]) -> [TransactionModel] {
    return rawData.map { movement in
        TransactionModel(
            id: movement.txid,
            type: parseTransactionType(movement.kind),
            amount: movement.amount,
            // ... additional transformations
        )
    }
}
```

## Model Validation

### Required Properties
All models include validation for required properties:
- Amount values must be non-negative
- Dates must be valid and reasonable
- IDs must be non-empty strings

### Computed Property Patterns
Models use consistent patterns for computed properties:
- Formatted strings use appropriate formatters (BitcoinFormatter, DateFormatter)
- Boolean flags provide clear semantic meaning
- Aggregated values are calculated from base properties

## Extension Points

### Adding New Models
When adding new models, follow these patterns:
1. Define core properties with appropriate types
2. Add computed properties for display formatting
3. Implement persistence model if caching is needed
4. Add bidirectional conversion methods
5. Include validation logic

### Model Evolution
Models support evolution through:
- Optional properties for backward compatibility
- Migration helpers for persistence models
- Versioning for breaking changes

---

*Note: This reference should be updated whenever model structures change.*