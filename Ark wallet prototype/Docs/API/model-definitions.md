# Model Definitions Reference

This document provides comprehensive reference information for all data models used throughout the application, reflecting the current unified architecture after all migrations.

## Core SwiftData Models

### Balance Models

#### ArkBalanceModel (@Model class)
Unified model for Ark protocol balance information with SwiftData persistence and API compatibility.

**Properties**:
```swift
@Model
class ArkBalanceModel {
    // Core balance properties (from API)
    var spendableSat: Int
    var pendingLightningSendSat: Int
    var pendingInRoundSat: Int
    var pendingExitSat: Int
    var pendingBoardSat: Int
    
    // SwiftData persistence properties
    var id: String = "ark_balance"
    var lastUpdated: Date
    
    // Computed Properties
    var totalPendingSat: Int { ... }
    var totalBalanceSat: Int { ... }
    var spendableFormatted: String { ... }
    var totalPendingFormatted: String { ... }
    var totalBalanceFormatted: String { ... }
    
    // Persistence Methods
    var isValid: Bool { ... }
    func update(from other: ArkBalanceModel) { ... }
}
```

**Key Features:**
- Implements `Codable` with custom encoding (excludes persistence properties)
- Singleton pattern using fixed ID for caching
- 5-minute cache validity window
- Direct SwiftData observation support

#### OnchainBalanceModel (@Model class)  
Unified model for Bitcoin onchain balance information with SwiftData persistence and API compatibility.

**Properties**:
```swift
@Model
class OnchainBalanceModel {
    // Core balance properties (from API)
    var totalSat: Int
    var trustedSpendableSat: Int
    var immatureSat: Int
    var trustedPendingSat: Int
    var untrustedPendingSat: Int
    var confirmedSat: Int
    
    // SwiftData persistence properties
    var id: String = "onchain_balance"
    var lastUpdated: Date
    
    // Computed Properties
    var totalFormatted: String { ... }
    var trustedSpendableFormatted: String { ... }
    var confirmedFormatted: String { ... }
    var totalBTC: Double { ... }
    var trustedSpendableBTC: Double { ... }
    var confirmedBTC: Double { ... }
    
    // Persistence Methods
    var isValid: Bool { ... }
    func update(from other: OnchainBalanceModel) { ... }
}
```

**Key Features:**
- Implements `Codable` with custom encoding (excludes persistence properties)
- Singleton pattern using fixed ID for caching
- 5-minute cache validity window
- BTC conversion computed properties

#### TotalBalanceModel (UI Helper)
Aggregates Ark and onchain balances for unified display. This remains a struct for UI convenience.

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

#### TransactionModel (@Model class)
Primary model for wallet transactions with SwiftData persistence and tag relationship support.

**Properties**:
```swift
@Model
class TransactionModel {
    // Core transaction properties (from server)
    var txid: String  // Primary identifier (server-derived, stable)
    var amount: Int
    var transactionType: TransactionType
    var transactionStatus: TransactionStatus
    var direction: TransactionDirection
    var date: Date
    var round: Int?
    var boardTxid: String?
    
    // SwiftData persistence properties
    var lastUpdated: Date
    
    // Tag relationships (junction table approach)
    @Relationship(deleteRule: .cascade)
    var tagAssignments: [TransactionTagAssignment] = []
    
    // Computed Properties
    var formattedAmount: String { ... }
    var formattedDate: String { ... }
    var displayDescription: String { ... }
    
    // Tag convenience methods
    var associatedTags: [PersistentTag] { ... }
    var tagCount: Int { ... }
    var hasTags: Bool { ... }
    func hasTag(_ tag: PersistentTag) -> Bool { ... }
}
```

**Key Features:**
- Stable `txid` from server (no random UUIDs)
- Direct SwiftData observation support
- Junction table relationship with tags
- Automatic UI updates via @Observable services

**Enums**:
```swift
enum TransactionType: String, CaseIterable, Codable {
    case ark = "ark"
    case onchain = "onchain"
    case lightning = "lightning"
    case board = "board"
    case offboard = "offboard"
}

enum TransactionDirection: String, CaseIterable, Codable {
    case incoming = "incoming"
    case outgoing = "outgoing"
}

enum TransactionStatus: String, CaseIterable, Codable {
    case pending = "pending"
    case confirmed = "confirmed"
    case failed = "failed"
}
```

### Tag System Models

#### PersistentTag (@Model class)
SwiftData model for tag storage with relationship management.

**Properties**:
```swift
@Model
class PersistentTag {
    // Core tag properties
    var id: UUID
    var name: String
    var colorHex: String
    var emoji: String
    var isActive: Bool
    var createdAt: Date
    
    // Relationships (junction table approach)
    @Relationship(deleteRule: .cascade, inverse: \TransactionTagAssignment.tag)
    var assignments: [TransactionTagAssignment] = []
    
    // Computed Properties
    var color: Color { ... }
    var displayName: String { ... }
    var transactionCount: Int { ... }
    
    // Convenience Methods
    func getAssociatedTransactions() -> [TransactionModel] { ... }
    func toTagModel() -> TagModel { ... }
}
```

#### TransactionTagAssignment (@Model class)
Junction table for many-to-many tag-transaction relationships.

**Properties**:
```swift
@Model
class TransactionTagAssignment {
    // Relationships
    var tag: PersistentTag?
    var transaction: TransactionModel?
    
    // Metadata (extensible for future features)
    var assignedAt: Date
    var id: UUID
}
```

**Key Benefits:**
- Better control over relationship lifecycle
- Easier preservation during server refreshes
- Extensible for future metadata (notes, user who assigned, etc.)
- Proper cascade deletion behavior

#### TagModel (UI struct)
UI-friendly struct for tag display and API serialization.

**Properties**:
```swift
struct TagModel: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String  
    var emoji: String
    var isActive: Bool = true
    let createdAt: Date
    
    // Computed Properties
    var color: Color { ... }
    var displayName: String { ... }
    
    // Conversion Methods
    func toPersistentTag() -> PersistentTag { ... }
    static func fromPersistentTag(_ persistent: PersistentTag) -> TagModel { ... }
}
```

## Supporting Models

### VTXO and UTXO Models

#### VTXOModel (UI struct)
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

#### UTXOModel (UI struct)
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

### Intermediate Data Models

#### MovementData
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

#### ArkInfoModel
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

## Current Architecture Patterns

### Unified Model Strategy
After architectural migrations, all core data models follow the **unified pattern**:
- **Single @Model class** serves both API and persistence needs
- **Custom Codable implementation** excludes SwiftData properties from API
- **Direct SwiftData observation** enables automatic UI updates
- **Computed properties** provide formatted display values

### Junction Table Relationships
Tag system uses **junction table pattern** for better relationship control:
```
PersistentTag ←→ TransactionTagAssignment ←→ TransactionModel
     ↑                    ↑                        ↑
   1:many             junction table            1:many
```

**Benefits:**
- Explicit relationship lifecycle management
- Easier preservation during server refreshes  
- Extensible metadata support
- Proper cascade deletion behavior

## Model Relationships and Data Flow

### Core Data Flow
```
Server API Response → @Model Class (unified) → SwiftUI Display
                   ↓
            SwiftData Persistence → Automatic UI Updates
```

### Tag Assignment Flow
```
UI Action → TagService → PersistentTag + TransactionTagAssignment
                    ↓
               SwiftData → @Observable → UI Auto-Update
```

### Cache Strategy
Balance models implement **intelligent caching**:
- **Singleton pattern**: Fixed IDs for single records per type
- **5-minute validity**: Fresh data prioritized, stale data triggers refresh
- **Graceful degradation**: App works offline with cached data

## Model Container Configuration

All SwiftData models must be included in the app's ModelContainer:

```swift
// Required for current architecture:
.modelContainer(for: [
    TransactionModel.self,
    ArkBalanceModel.self,
    OnchainBalanceModel.self,
    PersistentTag.self,
    TransactionTagAssignment.self
])
```

## Model Validation and Best Practices

### Required Properties
All models include validation for:
- **Amount values**: Must be non-negative integers (satoshis)
- **Dates**: Must be valid and reasonable timestamps
- **IDs**: Must be non-empty strings or valid UUIDs
- **Relationships**: Proper cascade rules and nullability

### Computed Property Patterns
Models use consistent patterns:
- **Formatted strings**: Use BitcoinFormatter, DateFormatter
- **Boolean flags**: Provide clear semantic meaning (`hasTags`, `isValid`)
- **Aggregated values**: Calculated from base properties (`totalBalance`)
- **UI convenience**: Color from hex, display names with emoji

### Evolution Strategy
Models support safe evolution through:
- **Optional properties**: For backward compatibility
- **Custom Codable**: Exclude internal properties from API
- **Migration helpers**: SwiftData schema evolution support
- **Versioning**: Clear migration paths for breaking changes

## Extension Guidelines

### Adding New Models
When extending the data layer:
1. **Choose pattern**: Unified @Model or UI struct based on persistence needs
2. **Define relationships**: Use junction tables for many-to-many
3. **Implement Codable**: Custom encoding for API compatibility
4. **Add computed properties**: Consistent formatting patterns
5. **Include validation**: Data integrity and business logic
6. **Update container**: Add to ModelContainer configuration

### Tag System Extension
The tag system is designed for extension:
- **TransactionTagAssignment metadata**: Add notes, user info, timestamps
- **Tag categories**: Hierarchical tag organization
- **Bulk operations**: Tag multiple transactions simultaneously
- **Tag templates**: Predefined tag sets for common workflows

---

*This reference reflects the current unified architecture. Updated: October 30, 2025*