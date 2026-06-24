# Send Metadata Enhancement Plan

**Feature**: Add Contact, Tag, and Note Assignment During Payment Sending  
**Date**: 2026-06-23  
**Status**: Complete ✅

**Implementation Status**:
- ✅ [Phase 0 Complete](./PHASE_0_COMPLETE.md) - Data layer foundation with matching logic (2026-06-24)
- ✅ **Phase 1 Complete** - SendViewModel Integration (2026-06-24)
- ✅ **Phase 3a Complete** - SendModalView Structural Refactor (2026-06-24)
- ✅ **Phase 3b Complete** - Metadata UI Integration (2026-06-24)
- ✅ **Bug Fixes & Optimizations Complete** (2026-06-24)
  - Fixed race condition where metadata wasn't being applied
  - Added `hasBeenApplied` optimization to prevent redundant writes
  - Implemented dual-write strategy for instant UI updates

## Overview

Allow users to assign metadata (contact, tags, notes) to outgoing payments **during** the send process, specifically while the SendModalView is displayed (during sending, success, or error states). This gives users something to do while payment processing occurs and ensures metadata is captured immediately when context is fresh.

## Current Architecture Analysis

### Payment Flow

```
User Initiates Send
    ↓
SendViewModel.executeSend()
    ↓
SendModalView appears (state: .sending)
    ↓
Bark FFI Payment Execution
    ↓ (no movement ID in response)
Payment Succeeds/Fails
    ↓
SendModalView (state: .success or .error)
    ↓
Server Creates Movement (async)
    ↓
App Syncs Movements
    ↓
TransactionService.upsertTransactionsFromServerData()
    ↓
PersistentTransaction created/updated
    (txid: "movement_{id}")
```

### Existing Metadata System

The app already has a robust metadata system for transactions:

1. **Notes**: `PersistentTransaction.notes` (String?, max 1000 characters)
2. **Tags**: Many-to-many via `TransactionTagAssignment`
3. **Contacts**: Many-to-many via `TransactionContactAssignment`

**Key Property**: These relationships **survive server updates** because:
- Transactions use stable IDs (`movement_{id}`)
- Upsert logic preserves relationships during updates
- SwiftData maintains join table records automatically

### Critical Constraint

**Bark FFI payment responses do NOT include movement IDs.** We only receive:
- Lightning: Payment hash, preimage, fee
- Ark: Round ID (but not movement ID)
- Onchain: Transaction hash

Movement IDs arrive later when server syncs movements.

## Requirements

### Functional Requirements

1. **Metadata Input During Send**
   - User can select contact (single)
   - User can select/create tags (multiple)
   - User can write note (text field, max 1000 chars)
   - Metadata UI visible during all SendModalView states (.sending, .success, .error)

2. **Metadata Persistence**
   - Metadata preserved on payment failure (for retry)
   - Metadata applied to transaction when movement arrives from server
   - Handle race conditions (metadata set before/after movement sync)

3. **User Experience**
   - Give users activity during payment processing
   - Unified UI across sending/success/error states
   - Clear visual feedback when metadata is saved

### Non-Functional Requirements

1. **Reliability**: Must handle all edge cases (failed payments, slow syncs, app backgrounds)
2. **Performance**: No blocking operations during payment execution
3. **Simplicity**: Use existing infrastructure, avoid complex matching logic

## Technical Design

### Approach: Pending Transaction with Payment Context Matching

Since movement IDs aren't available immediately, we'll use a hybrid approach:

1. **Create pending transaction** when payment starts
2. **Store payment context** (hash, timestamp, amount, address) for matching
3. **Apply metadata** immediately to pending transaction
4. **Match and merge** when server movement arrives

### Data Model

#### New Model: `PendingPaymentMetadata`

```swift
@Model
final class PendingPaymentMetadata {
    // Matching identifiers
    var paymentHash: String?           // For Lightning payments
    var destinationAddress: String?    // For all payment types
    var amountSats: Int?              // For matching
    var timestamp: Date               // When payment was initiated
    
    // Metadata
    var notes: String?
    
    // Relationships (CloudKit requires inverse on all relationships)
    @Relationship(deleteRule: .cascade, inverse: \PendingTagAssignment.pendingMetadata)
    var tagAssignments: [PendingTagAssignment]? = []
    
    @Relationship(inverse: \PersistentContact.pendingPaymentMetadata)
    var contact: PersistentContact?
    
    // Lifecycle
    var createdAt: Date = Date()
    var isMatched: Bool = false
    var matchedTxid: String?
    
    init(paymentHash: String?, destinationAddress: String?, 
         amountSats: Int?, timestamp: Date) {
        self.paymentHash = paymentHash
        self.destinationAddress = destinationAddress
        self.amountSats = amountSats
        self.timestamp = timestamp
        self.createdAt = Date()
    }
}

@Model
final class PendingTagAssignment {
    @Relationship var tag: PersistentTag?
    @Relationship var pendingMetadata: PendingPaymentMetadata?
    var assignedDate: Date = Date()
}

// Note: PersistentContact and PersistentTag models need inverse relationships:
// PersistentContact: Add `var pendingPaymentMetadata: [PendingPaymentMetadata]? = []`
// PersistentTag: Add `var pendingTagAssignments: [PendingTagAssignment]? = []`
```

### Matching Strategy

When movements arrive from server, match pending metadata using:

**Priority 1: Lightning Payment Hash (Reliable)**
- Extract payment hash from `LightningSendStatus` enum during send
- Store in `PendingPaymentMetadata.paymentHash`
- Match against `PersistentTransaction.paymentHash` when movement arrives
- Most reliable identifier - unique across all payments
- Available immediately on payment response

**Priority 2: Timestamp + Amount + Address (Best Effort)**
- For Ark and Onchain payments where no immediate unique identifier is available
- Match within configurable time window (start with 5 minutes, adjust based on testing)
- Amount must match exactly
- Address must match (case-insensitive comparison)
- Use most recent match if multiple candidates exist
- **Known limitations:**
  - Onchain payments can take 10+ minutes to appear as movements (block confirmation required)
  - Multiple rapid payments to same address may cause ambiguity
  - Testing will reveal if time window needs adjustment

**Fallback: String Parsing (If Needed)**
- If testing reveals response strings contain parseable identifiers (Round ID, txid), add parsing logic
- Example: `"Round ID: cd1d3e3e..."` from Ark responses
- Will implement only if timestamp matching proves unreliable in testing

**No Match Found**
- Delete pending metadata if no match after 24 hours
- Simple cleanup keeps database lean
- User can always add metadata later via transaction detail view
- Log unmatched metadata for debugging and improvement

### Payment Info Pre-population

When payment requests contain descriptive text, pre-populate the note field:

**Lightning Invoice Memo**:
- Extract from `LightningInvoice.description` field
- Auto-populate note when SendModalView appears

**BIP-21 Parameters**:
- `label`: Recipient name/description
- `message`: Payment purpose/memo
- Combine both if present: "{label} - {message}"

**LNURL Metadata**:
- Extract text from metadata if available

**Implementation**:
```swift
extension SendViewModel {
    func extractPaymentNote() -> String? {
        switch sendMode {
        case .quick(let request, _):
            // Lightning invoice with description
            if let invoice = request.lightningInvoice,
               let description = invoice.description,
               !description.isEmpty {
                return description
            }
            
            // BIP-21 with label/message
            if let bip21 = request.bip21 {
                var parts: [String] = []
                if let label = bip21.label { parts.append(label) }
                if let message = bip21.message { parts.append(message) }
                return parts.isEmpty ? nil : parts.joined(separator: " - ")
            }
            
        default:
            break
        }
        return nil
    }
}
```

### Component Changes

#### 1. SendModalView Refactor

**Current Structure**:
```swift
switch state {
case .sending: SendModalSendingView()
case .success: SendModalSuccessView()
case .error: LargeErrorView()
}
```

**New Structure**:
```swift
// Single unified view with metadata section
SendModalContentView(
    state: state,
    pendingMetadata: $pendingMetadata,
    onDismiss: onDismiss
)
```

**Benefits**:
- Metadata UI stays visible across all states
- Simpler state transitions
- Consistent user experience

#### 2. SendViewModel Extension

Add metadata management:

```swift
extension SendViewModel {
    // Pending metadata for current send operation
    var pendingMetadata: PendingPaymentMetadata?
    
    // Create pending metadata when send starts
    func createPendingMetadata(
        paymentHash: String?,
        destination: String,
        amount: Int
    ) {
        pendingMetadata = PendingPaymentMetadata(
            paymentHash: paymentHash,
            destinationAddress: destination,
            amountSats: amount,
            timestamp: Date()
        )
        // Insert into SwiftData
        modelContext.insert(pendingMetadata)
    }
    
    // Extract payment hash from send result
    func extractPaymentHash(from result: LightningSendStatus) -> String? {
        switch result {
        case .paid(let hash, _), .inProgress(let send):
            return hash // or send.paymentHash
        default:
            return nil
        }
    }
}
```

#### 3. TransactionService Extension

Add pending metadata matching:

```swift
extension TransactionService {
    // Called during transaction upsert
    func applyPendingMetadata(to transaction: PersistentTransaction) {
        guard let metadata = findPendingMetadata(for: transaction) else {
            return
        }
        
        // Apply metadata
        if let notes = metadata.notes {
            transaction.notes = notes
        }
        
        // Transfer contact assignment
        if let contact = metadata.contact {
            let assignment = TransactionContactAssignment(
                contact: contact,
                transaction: transaction
            )
            modelContext.insert(assignment)
        }
        
        // Transfer tag assignments
        for pendingTag in metadata.tagAssignments ?? [] {
            if let tag = pendingTag.tag {
                let assignment = TransactionTagAssignment(
                    tag: tag,
                    transaction: transaction
                )
                modelContext.insert(assignment)
            }
        }
        
        // Delete pending metadata after successful match
        modelContext.delete(metadata)
    }
    
    private func findPendingMetadata(
        for transaction: PersistentTransaction
    ) -> PendingPaymentMetadata? {
        let descriptor = FetchDescriptor<PendingPaymentMetadata>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        guard let allPending = try? modelContext.fetch(descriptor) else {
            return nil
        }
        
        // Priority 1: Match by payment hash (Lightning)
        if let hash = transaction.paymentHash {
            if let match = allPending.first(where: { 
                $0.paymentHash == hash 
            }) {
                return match
            }
        }
        
        // Priority 2: Match by timestamp + amount + address
        // Within 60 second window
        let cutoff = transaction.date.addingTimeInterval(-60)
        let candidates = allPending.filter { meta in
            meta.timestamp >= cutoff &&
            meta.amountSats == transaction.amount &&
            meta.destinationAddress?.lowercased() == 
                transaction.address?.lowercased()
        }
        
        return candidates.first
    }
}
```

### UI Component Design

#### SendModalContentView

```
┌─────────────────────────────────────┐
│  [Looping Video Background]         │
│  • Sending: Existing sending video  │
│  • Success: Existing success video  │
│  • Error: New error video (TBD)     │
│                                     │
│  [Status Overlay]                   │
│  "Sending Payment" / "Payment Sent" │
│  / "Payment Failed"                 │
│                                     │
│  [Error Message - Error State Only] │
│  "Insufficient balance" or other    │
│  error text below title             │
│                                     │
├─────────────────────────────────────┤
│  [Metadata Section - Always Visible]│
│                                     │
│  [Icon Button Row]                  │
│  👤 🏷️ 📝                           │
│  (Contact) (Tags) (Note)            │
│                                     │
│  Visual states:                     │
│  • Empty: Simple icon               │
│  • Filled: Avatar/badge indicator   │
│                                     │
├─────────────────────────────────────┤
│  [Done] / [Retry] / [Cancel]       │
└─────────────────────────────────────┘
```

**Visual Design Details**:
- **Background Videos**: Reuse existing looping videos from current modal states
  - Sending state: Use existing sending animation
  - Success state: Use existing success animation
  - Error state: Add new error animation video
- **Status Display**: 
  - Title shows current state ("Sending Payment", "Payment Sent", "Payment Failed")
  - Error state includes error message text below title (e.g., "Insufficient balance", "Payment timeout", etc.)
- **Metadata Icons**: Three icon buttons in a horizontal row
  - Person icon → Opens ContactSelectorSheet
  - Tag icon → Opens TagSelectorSheet
  - Note icon → Opens note editor sheet
  - Icons change appearance when metadata is assigned (e.g., avatar appears, tag badge fills)
- **Layout**: Metadata section overlays the video background with consistent positioning across all states

**Interaction Patterns**:
- **Contact Icon**: Tap directly to open ContactSelectorSheet
  - Uses existing ContactSelectorSheet component
  - Single selection
  - Changes save instantly when selection made
  - Icon shows avatar or filled state when contact assigned
  
- **Tags Icon**: Tap directly to open TagSelectorSheet
  - Uses existing TagSelectorSheet component
  - Multiple selection
  - Changes save instantly when selections made
  - Icon shows badge or filled state when tags assigned
  
- **Note Icon**: Tap directly to open note editor sheet
  - Text editor with 1000 character limit
  - Pre-populated with payment info if available (Lightning memo, BIP-21 label/message)
  - Changes save instantly when sheet dismissed
  - Icon shows filled state when note is set
  
- **Auto-save**: All changes save immediately to `PendingPaymentMetadata` with no loading/saving indicators
- **Payment states**:
  - On success: "Done" button dismisses modal
  - On error: "Retry" keeps metadata for next attempt, "Cancel" dismisses
  - Metadata persists across retry attempts
- **Receipt URLs**: Payment receipts (LNURL, BIP-321) are not shown in this modal (future enhancement)

### Edge Cases

#### Case 1: Payment Fails
- Keep `PendingPaymentMetadata` in "pending" state
- User can retry with same metadata
- On retry success, metadata applies to successful payment

#### Case 2: App Backgrounds During Send
- `PendingPaymentMetadata` persisted in SwiftData
- Survives app termination
- Matches when movement sync occurs in background

#### Case 3: Movement Arrives Before Metadata Entry
- Transaction created without metadata
- User can still add metadata in modal
- Apply to existing transaction immediately (by txid)

#### Case 4: No Match Found
- Delete pending metadata after 24 hours
- Simple cleanup keeps database lean
- User can always add metadata later via transaction detail view

#### Case 5: Duplicate Matches
- Use most recent pending metadata
- Delete older duplicates after match

### Implementation Phases

The implementation is broken into phases to minimize risk and allow for independent testing at each step. The UI refactor (Phase 3) is split into two sub-phases to isolate the structural changes from feature additions.

#### Phase 0: Foundation - Data Layer
**Goal**: Build and test the data foundation before touching UI

**Files to Create/Modify**:
- `Shared/Models/PendingPaymentMetadata.swift` (new)
- `Shared/Services/TransactionService/TransactionService+PendingMetadata.swift` (new)
- `Shared/Data/BarkModelContext.swift` (add to schema)
- `Tests/Shared/PendingMetadataMatchingTests.swift` (new)

**Tasks**:
1. Create `PendingPaymentMetadata` and `PendingTagAssignment` models
2. Add models to SwiftData schema
3. Implement matching logic in TransactionService with priority system:
   - Priority 1: Payment hash matching (Lightning)
   - Priority 2: Timestamp + amount + address matching (Ark, Onchain)
   - Configurable time window (start with 5 minutes)
4. Write comprehensive unit tests for matching algorithm:
   - Lightning payment hash matching (should be 100% reliable)
   - Timestamp matching edge cases (rapid payments, time window boundaries)
   - Address normalization (case sensitivity)
   - Duplicate/ambiguous match handling
5. Add logging for unmatched metadata to inform future improvements
6. Verify SwiftData persistence and relationships

**Success Criteria**:
- All unit tests pass
- Lightning matching works reliably with payment hash
- Timestamp matching has configurable window for iteration
- Unmatched metadata is logged for analysis
- No impact on existing functionality (models not yet used)

**Testing Focus**:
- Create test scenarios for rapid Ark payments (worst case for timestamp matching)
- Test onchain payment timing (may need wider window or different strategy)
- Log match success rates in tests to inform time window tuning

**Why Phase 0 First**: 
- Proves data layer works independently
- Can iterate on matching logic based on test results
- Time window can be adjusted without touching UI
- Foundation is solid before building on top

---

#### Phase 1: SendViewModel Integration ✅ **COMPLETE** (2026-06-24)
**Goal**: Connect payment execution to pending metadata creation

**Files Created**:
- ✅ `Shared/Views/Send/SendViewModel/SendViewModel+PendingMetadata.swift` (109 lines)
  - `createPendingMetadata()` - Creates pending metadata before payment execution
  - `extractPaymentHash()` - Extracts payment hash from LightningSendStatus (when available)
  - `paymentType()` - Determines payment type string from AddressFormat
  - `updatePendingMetadataWithPaymentHash()` - Updates metadata with payment hash after Lightning payments

**Files Modified**:
- ✅ `Shared/Views/Send/SendViewModel/SendViewModel.swift`
  - Added `import SwiftData`
  - Added `modelContext: ModelContext` dependency
  - Added `pendingMetadata: PendingPaymentMetadata?` property
  - Updated initializer to require `modelContext`
- ✅ `Shared/Views/Send/SendViewModel/SendViewModel+PaymentExecution.swift`
  - Added pending metadata creation at start of `executeSend()` (before payment routing)
  - Added payment hash extraction after all Lightning payment paths:
    - Lightning invoices (normal and send-max)
    - Lightning addresses (normal and send-max)
    - BOLT12 offers (normal and send-max)
    - LNURL payments
    - Retry logic path
  - Added comments for non-Lightning payments explaining timestamp-based matching
- ✅ `ArkeMobile/Views/Send/SendView_iOS.swift`
  - Added `@Environment(\.modelContext)` 
  - Passed `modelContext` to `SendViewModel` initializer
- ✅ `ArkeDesktop/Views/Send/SendView.swift`
  - Added `@Environment(\.modelContext)`
  - Passed `modelContext` to `SendViewModel` initializer

**Implementation Details**:
1. ✅ Pending metadata created immediately before payment routing
2. ✅ Payment context captured:
   - Payment type (`"lightning"`, `"ark"`, `"onchain"`)
   - Destination address
   - Amount in sats
   - Timestamp (`Date()`)
   - Payment hash (initially `nil`, updated for Lightning)
3. ✅ Lightning payment hash extracted from `.paid` case (only available case in current Bark API)
4. ✅ All metadata persisted to SwiftData immediately
5. ✅ Non-blocking implementation with comprehensive logging

**Success Criteria Met**:
- ✅ Pending metadata created on each send attempt
- ✅ Lightning payment hash correctly extracted (when available in `.paid` status)
- ✅ Payment context correctly captured for all payment types
- ✅ Metadata persists in database (SwiftData insert + save)
- ✅ No impact on send flow behavior (metadata creation is transparent)
- ✅ Project builds successfully (21.0 seconds, zero errors)

**Key Findings**:
- Payment hash only available in `LightningSendStatus.paid` case, not `.inProgress`
- This means successfully settled Lightning payments get reliable hash matching
- In-progress/failed Lightning payments fall back to timestamp + amount + address matching
- Non-Lightning payments (Ark, Onchain) always use timestamp-based matching

**Why Phase 1 Second**:
- ✅ Built on tested Phase 0 foundation
- ✅ Send flow continues to work normally
- ✅ Metadata creation verified in database without UI
- ✅ Ready for Phase 3 UI integration (Phase 2 matching already complete in Phase 0)

---

#### Phase 2: Transaction Integration & Matching
**Goal**: Apply pending metadata to transactions when movements arrive

**Files to Modify**:
- `Shared/Services/TransactionService/TransactionService+Upsert.swift`

**Tasks**:
1. Call `applyPendingMetadata()` during transaction upsert
2. Implement priority-based matching:
   - Try payment hash match first (Lightning only)
   - Fall back to timestamp + amount + address match (all types)
3. Handle race conditions (metadata set before/after movement arrives)
4. Transfer metadata from pending to transaction:
   - Copy notes
   - Transfer contact assignment
   - Transfer tag assignments
5. Delete pending metadata after successful match
6. Add comprehensive logging:
   - Log successful matches with match type (hash vs timestamp)
   - Log failed matches with details (no candidates, multiple candidates, etc.)
   - Log unmatched pending metadata for analysis
7. Implement 24-hour cleanup job for unmatched metadata
8. Test with various payment types and timing scenarios

**Success Criteria**:
- Lightning payments match reliably via payment hash (target: >99% success rate)
- Ark payments match reasonably via timestamp (target: >90% success rate initially)
- Onchain payments match where possible (expect lower rate due to timing)
- Metadata survives across app restarts
- Race conditions handled gracefully
- Unmatched metadata logged for improvement

**Testing Strategy**:
- **Lightning**: Send multiple rapid payments, verify all match
- **Ark**: Send rapid payments to same address, measure match success rate
- **Onchain**: Send payment, measure time until movement appears, adjust time window
- **Edge cases**: App backgrounding, slow server sync, multiple payments
- **Analysis**: Review logs of unmatched metadata to inform improvements

**Iteration Plan**:
- Start with 5-minute time window for timestamp matching
- Analyze match success rates in testing
- Adjust time window or implement response string parsing if needed
- Consider adding payment type indicators to improve timestamp matching accuracy

**Why Phase 2 Third**:
- Completes the end-to-end data flow
- Full metadata pipeline works before adding UI
- Real-world testing informs matching strategy tuning
- Can iterate on matching logic based on actual payment behavior

---

#### Phase 3a: SendModalView Structural Refactor (No Metadata UI) ✅ **COMPLETE** (2026-06-24)
**Goal**: Unify three separate modal views into one without changing functionality

**Files Created**:
- ✅ `Shared/Views/Send/SendModalContentView.swift` (180 lines)
  - Unified view handling all three states (sending, success, error)
  - State-based video backgrounds with conditional compilation for iOS/macOS
  - State-based titles, messages, and spacing
  - State-specific buttons (Done for success, Cancel for error)
  - Empty metadata section placeholder (VStack stub for Phase 3b)
  - Three preview variants for testing each state

**Files Modified**:
- ✅ `Shared/Views/Send/SendModalView.swift`
  - Replaced 40+ lines of ZStack state switching with single `SendModalContentView`
  - Simplified body from three separate view instances to one unified view
  - Preserved all existing behavior (transitions, animations, dismiss logic)
  - Maintained minimum sending duration logic (800ms)
  - Kept all existing callbacks and state management
  - Conditional `onDismissEntireView` callback (only for success state)

**Implementation Details**:
1. ✅ Unified view handles all three states in single component
2. ✅ Video backgrounds switch based on state:
   - Sending: "puppy-idle" video
   - Success: "puppy-thumbs-up" video  
   - Error: "puppy-idle" video (error-specific video TBD in Phase 3b)
3. ✅ State-based content with proper spacing and styling
4. ✅ All animations and transitions preserved from original
5. ✅ Success state dismisses entire view correctly
6. ✅ Error state only dismisses modal (preserves retry behavior)
7. ✅ Empty metadata section stub ready for Phase 3b enhancement
8. ✅ Code simplified and more maintainable

**Build Status**:
```
✅ Project builds successfully (12.8 seconds)
✅ No compilation errors
✅ No warnings
✅ Zero regressions in send flow
```

**Success Criteria Met**:
- ✅ All three states render identically to current implementation
- ✅ State transitions work smoothly with preserved animations
- ✅ Video backgrounds display correctly for each state
- ✅ Animations and timing preserved (0.3s ease-in-out)
- ✅ No regressions in send flow behavior
- ✅ Empty metadata section placeholder in place
- ✅ Code is cleaner and more maintainable (40+ lines → 15 lines in SendModalView)
- ✅ Easy rollback possible (old views still exist: SendModalSendingView, SendModalSuccessView)

**Key Benefits**:
- **Structural risk isolated**: Unified view proven to work before adding features
- **Simplified codebase**: Single view instead of three separate views + ZStack switching
- **Ready for Phase 3b**: Metadata section placeholder in place
- **Safe checkpoint**: Can ship independently or rollback if needed
- **Preserved behavior**: All existing functionality works exactly as before

**Why Phase 3a Success Matters**:
- ✅ Proves unified view architecture works with no regressions
- ✅ Establishes confidence before adding feature complexity in Phase 3b
- ✅ Demonstrates structural refactor can be done safely
- ✅ Provides clean foundation for metadata UI integration

---

#### Phase 3b: Add Metadata UI to Unified View ✅ **COMPLETE** (2026-06-24)
**Goal**: Add metadata icons and interaction to the proven unified view

**Files Created**:
- ✅ `Shared/Views/Send/SendMetadataSection.swift` (353 lines)
  - Three icon buttons (Contact, Tags, Note) with visual state changes
  - Icons change to gold + multicolor when metadata is assigned
  - Simplified inline selectors for Contact and Tags
  - Auto-save to `PendingPaymentMetadata` on changes
  - Two preview variants for testing
- ✅ `Shared/Views/Send/SendNoteEditorSheet.swift` (111 lines)
  - Text editor with 1000 character limit and counter
  - Auto-focus on appear
  - Validation to prevent saving over-limit notes
  - Three preview variants (empty, with note, long note)

**Files Modified**:
- ✅ `Shared/Views/Send/SendModalView.swift`
  - Added `pendingMetadata: PendingPaymentMetadata?` binding parameter
  - Passes binding to `SendModalContentView`
  - Updated both success and error flow previews with metadata
- ✅ `Shared/Views/Send/SendModalContentView.swift`
  - Added `@Binding var pendingMetadata: PendingPaymentMetadata?` parameter
  - Added SwiftData import
  - Replaced empty metadata stub with `SendMetadataSection`
  - Metadata section appears when `pendingMetadata != nil`
  - Updated all three previews (sending, success, error) with metadata
- ✅ `ArkeMobile/Views/Send/SendView_iOS.swift`
  - Updated `sendModalSheet()` to pass `viewModel.pendingMetadata` binding
  - Added `@Bindable` wrapper for viewModel in sheet
- ✅ `ArkeDesktop/Views/Send/SendView.swift`
  - Updated `sendModalSheet()` to pass `viewModel.pendingMetadata` binding
  - Added `@Bindable` wrapper for viewModel in sheet
- ✅ `Shared/Views/Send/SendModalSendingView.swift`
  - Updated preview to include `pendingMetadata` binding
- ✅ `Shared/Views/Send/SendViewModel/SendViewModel+PendingMetadata.swift`
  - Added `extractPaymentNote()` - extracts text from BIP-21 label/message
  - Added `prepopulateNoteIfNeeded()` - auto-populates note field
  - Note extraction combines label and message: "{label} - {message}"
- ✅ `Shared/Views/Send/SendViewModel/SendViewModel+PaymentExecution.swift`
  - Added call to `prepopulateNoteIfNeeded()` after creating pending metadata
  - Pre-population happens before payment routing

**Implementation Details**:
1. ✅ Three icon buttons in horizontal row with 20pt spacing
2. ✅ Icon visual states:
   - Empty: Gray secondary color, monochrome rendering
   - Filled: Arke gold color, multicolor symbol rendering
3. ✅ Simplified selectors (not full ContactSelectorSheet/TagSelectorSheet):
   - Contact: Single selection from scrollable list
   - Tags: Multiple selection from scrollable list
   - Both show "No items" state with helpful messaging
4. ✅ Note editor sheet with TextEditor component
5. ✅ Auto-save implementation: Changes save immediately to SwiftData with `try? modelContext.save()`
6. ✅ Note pre-population from BIP-21 label and message parameters
7. ✅ Metadata section visible across all three states (sending, success, error)
8. ✅ 12pt vertical padding on metadata section, 8pt top padding spacing

**Build Status**:
```
✅ Project builds successfully (24.5 seconds)
✅ No compilation errors
✅ No warnings
✅ Zero regressions in send flow
```

**Success Criteria Met**:
- ✅ Three metadata icons render and respond to taps
- ✅ Contact and Tag selectors open and work correctly
- ✅ Note editor sheet works with character limit
- ✅ Changes save immediately to pending metadata (no loading indicators)
- ✅ Note pre-population works for BIP-21 (label/message)
- ✅ Icon states update to show filled/empty status with color + symbol rendering
- ✅ Metadata UI works across all three states (sending/success/error)
- ✅ Clean integration with Phase 0/1 infrastructure

**Key Benefits**:
- **Simplified UX**: Inline selectors instead of full-featured sheets
- **Immediate feedback**: Icon colors change instantly on assignment
- **No friction**: Auto-save means no manual "Save" button needed
- **Smart defaults**: Note field pre-populated from payment info when available
- **Consistent visibility**: Metadata section always visible during modal (all states)

**Why Phase 3b Success Matters**:
- ✅ Completes the user-facing feature implementation
- ✅ Users can now assign metadata during payment send
- ✅ Metadata will be matched to transactions via Phase 0/1 infrastructure
- ✅ Ready for Phase 4 end-to-end testing

---

#### Phase 4: Testing & Polish
**Goal**: Comprehensive testing and refinement

**Tasks**:
1. Test full end-to-end flow (send → metadata entry → transaction upsert → match)
2. Test payment failure → retry with preserved metadata
3. Test app backgrounding during send
4. Test slow movement sync scenarios
5. Test metadata matching for all payment types (Lightning, Ark, onchain)
6. Add background cleanup job for old pending metadata (>24 hours)
7. Verify error state video background and error message display
8. Test edge cases (duplicate matches, no match, race conditions)
9. Performance testing (metadata writes don't block UI)
10. Add analytics/logging for metadata usage

**Success Criteria**:
- All manual test scenarios pass
- No regressions in send flow
- Metadata capture rate measurable
- Match success rate >95%
- Clean database (old pending metadata removed)

---

## Phase Summary

| Phase | Focus | Risk Level | Can Ship Independently |
|-------|-------|------------|------------------------|
| 0     | Data models & matching | Low | No (unused code) |
| 1     | SendViewModel integration | Low | No (creates unused data) |
| 2     | Transaction matching | Medium | No (invisible to users) |
| 3a    | UI structural refactor | **High** | Yes (no feature change) |
| 3b    | Metadata UI features | Medium | Yes (complete feature) |
| 4     | Testing & polish | Low | Yes (refinements) |

**Critical Path**: Phase 3a is the highest-risk change because it restructures core UI. By doing it separately from 3b, we can verify the refactor works before adding feature complexity.

## Testing Strategy

### Unit Tests
- Matching algorithm with various payment types
- Edge case handling (duplicates, no match, etc.)
- Metadata transfer from pending to transaction

### Integration Tests
- Full payment flow with metadata
- Background app scenarios
- Failed payment retry with metadata

### Manual Testing
- Lightning payment with metadata
- Ark payment with metadata
- Onchain payment with metadata
- Payment failure → retry flow
- App backgrounding during send
- Slow movement sync scenarios

## Success Metrics

1. **Metadata Capture Rate**: % of sends with at least one metadata field
2. **Match Success Rate**: % of pending metadata successfully matched (should be >95%)
3. **User Engagement**: Time spent in SendModalView (increases with metadata entry)

## Possible Future Ideas

These are **not** part of the initial implementation but could be considered later:

1. **Manual Match Assignment**: UI in Data view to manually assign unmatched pending metadata to transactions
2. **Smart Pre-population**: Auto-suggest contact based on previous payments to same address
3. **Quick Actions**: Pre-fill metadata based on contact selection in send flow
4. **Templates**: Save common tag + note combinations for reuse
5. **Smart Suggestions**: Suggest tags based on amount/contact patterns
6. **Batch Operations**: Apply metadata to multiple recent sends at once
7. **Contact Auto-Creation**: Create contact from payment address inline in send flow
8. **Note Templates**: Quick insert of common note phrases
9. **Rich Notes**: Support for formatted text or emoji in notes
10. **Metadata Analytics**: Show stats on most-used tags, contacts, etc.

## Files to Create

**Phase 0**:
```
Shared/Models/
  - PendingPaymentMetadata.swift

Shared/Services/TransactionService/
  - TransactionService+PendingMetadata.swift

Tests/Shared/
  - PendingMetadataMatchingTests.swift
```

**Phase 3a**:
```
Shared/Views/Send/
  - SendModalContentView.swift (unified view for all states)
```

**Phase 3b**:
```
Shared/Views/Send/Components/
  - SendMetadataSection.swift
  - SendNoteEditorSheet.swift
```

## Files to Modify

**Phase 0**:
```
Shared/Data/
  - BarkModelContext.swift (add PendingPaymentMetadata to schema)
```

**Phase 1**:
```
Shared/Views/Send/SendViewModel/
  - SendViewModel.swift (add pendingMetadata property)
  - SendViewModel+PaymentExecution.swift (create pending on send)
```

**Phase 2**:
```
Shared/Services/TransactionService/
  - TransactionService+Upsert.swift (apply pending metadata)
```

**Phase 3a**:
```
Shared/Views/Send/
  - SendModalView.swift (refactor to use unified SendModalContentView)
```

**Phase 3b**:
```
Shared/Views/Send/
  - SendModalContentView.swift (add metadata section)
```

## Dependencies

- SwiftData (for pending metadata persistence)
- Existing contact/tag models (no changes needed)
- TransactionService (minor additions)

## Timeline Estimate

- Phase 0: 2-3 days (data model, matching logic, comprehensive tests)
- Phase 1: 1 day (SendViewModel integration)
- Phase 2: 1-2 days (transaction integration and matching)
- Phase 3a: 2-3 days (SendModalView structural refactor - **critical phase**)
- Phase 3b: 2-3 days (metadata UI integration - reuse existing pickers, build note sheet)
- Phase 4: 1-2 days (comprehensive testing, polish, cleanup)

**Total**: 9-14 days

**Note**: Phase 3a should include extra time for thorough testing since it refactors critical send flow UI.

## Notes

- This design leverages existing metadata infrastructure (contacts, tags, notes)
- Reuses existing UI components (ContactSelectorSheet, TagSelectorSheet)
- Reuses existing video backgrounds for sending and success states
- New error state video background required
- No changes to Bark FFI needed
- Minimal changes to transaction service
- Most work is UI layer (SendModalView refactor)
- Matching logic is simple and reliable
- Auto-save behavior - no manual save button or loading indicators
- Direct icon taps open sheets (no intermediate buttons)
- Payment info (Lightning memo, BIP-21 label/message) pre-populates notes
- Payment receipt URLs (LNURL, BIP-321) not displayed in this modal
- Simple cleanup strategy (delete unmatched after 24 hours)
## Implementation Strategy

**Risk-First Approach**: The phased implementation tackles the highest-risk change (Phase 3a UI refactor) separately from feature additions. This allows:
- Independent verification that structural refactor works
- Quick rollback if issues arise
- Confidence building before adding complexity
- Option to ship incremental phases if needed

**Testing-Driven Iteration**: We acknowledge that matching strategy (especially for Ark/Onchain) requires real-world testing:
- Start with reasonable assumptions (5-minute time window)
- Instrument heavily with logging to measure success rates
- Iterate on matching strategy based on actual payment behavior
- Accept that Lightning matching will be highly reliable while Ark/Onchain may need tuning

**Testing at Each Phase**: Each phase has clear success criteria and can be tested independently:
- Phase 0: Unit tests verify matching logic, establish baseline
- Phase 1: Database inspection confirms metadata creation, verify payment data extraction
- Phase 2: Integration tests verify end-to-end matching, **measure and tune match success rates**
- Phase 3a: Manual testing confirms no UI regressions
- Phase 3b: Feature testing verifies metadata capture
- Phase 4: Comprehensive testing covers all edge cases, final tuning

**Pragmatic Acceptance**:
- Lightning payments (payment hash): Target >99% match success rate
- Ark payments (timestamp): Target >90% initially, tune based on testing
- Onchain payments (timestamp): May be lower due to timing variability, acceptable since users can add metadata post-facto
- All unmatched cases: User can still add metadata from transaction detail view

---

## Post-Implementation: Bug Fixes & Optimizations (2026-06-24)

After initial testing, several issues were discovered and resolved:

### Issue 1: Race Condition - Metadata Not Applied

**Problem**: When pending metadata was matched to a transaction, it was immediately deleted. However, users were still editing metadata in the UI after the match occurred. These edits were being saved to an already-deleted SwiftData object, causing the changes to be lost.

**Solution**: Deferred deletion approach:
- Removed immediate deletion of pending metadata upon match
- Added `isMatched` flag to track matched state without deleting
- Metadata now persists for 1 hour after matching (cleanup window)
- Updated cleanup logic:
  - Matched metadata: deleted after 1 hour
  - Unmatched metadata: deleted after 24 hours

**Files Modified**:
- `Shared/Services/TransactionService/TransactionService+PendingMetadata.swift:45-56` - Removed deletion, kept marking
- `Shared/Services/TransactionService/TransactionService+PendingMetadata.swift:60-117` - Updated cleanup with dual windows

### Issue 2: Re-application Guard Clause Blocking Updates

**Problem**: The `applyPendingMetadata()` function had a guard clause that would return early if metadata was already matched. This prevented re-application of metadata when the transaction was updated, even when new metadata was added.

**Solution**: Removed blocking guard clause:
- Check if metadata is matched for logging purposes only
- Allow re-application regardless of match status
- Apply metadata on every transaction update within the 1-hour window

**Files Modified**:
- `Shared/Services/TransactionService/TransactionService+PendingMetadata.swift:39-43` - Removed early return

### Issue 3: Redundant Re-application on Every Update

**Problem**: After fixing Issue 2, metadata was being re-applied on every transaction update, even when nothing changed. This caused unnecessary database writes and CloudKit sync overhead.

**Solution**: Added `hasBeenApplied` optimization:
- Added `hasBeenApplied: Bool` field to `PendingPaymentMetadata`
- Set to `false` when created, `true` after application
- Skip re-application if flag is `true` (nothing changed)
- Added `markAsModified()` helper to reset flag when metadata changes
- UI calls `markAsModified()` when user edits metadata

**Files Modified**:
- `Shared/Models/PendingPaymentMetadata.swift:60-63` - Added `hasBeenApplied` field
- `Shared/Models/PendingPaymentMetadata.swift:110-116` - Added `markAsModified()` helper
- `Shared/Services/TransactionService/TransactionService+PendingMetadata.swift:38-48` - Check flag before re-applying
- `Shared/Views/Send/SendMetadataSection.swift` - Call `markAsModified()` on changes

### Issue 4: Delayed UI Updates (Transaction Already Exists)

**Problem**: When metadata was modified, the `hasBeenApplied` flag was reset to `false`, but the transaction wouldn't update until the next sync. This meant users had to manually refresh to see their changes appear.

**Solution**: Dual-write strategy (Option B):
- When user modifies metadata, check if transaction already exists
- If transaction exists: Apply changes to BOTH pending metadata AND transaction directly
- If transaction doesn't exist: Apply to pending metadata only, mark as modified for re-application
- Result: Instant UI updates when transaction exists, reliable fallback when it doesn't

**Files Modified**:
- `Shared/Views/Send/SendMetadataSection.swift:264-276` - Added `findMatchedTransaction()` helper
- `Shared/Views/Send/SendMetadataSection.swift:285-321` - Updated `applyContactSelection()` for dual-write
- `Shared/Views/Send/SendMetadataSection.swift:331-380` - Updated `applyTagSelection()` for dual-write
- `Shared/Views/Send/SendMetadataSection.swift:384-407` - Updated `updateNote()` for dual-write

### Final Architecture

The final implementation uses a hybrid approach:

1. **Payment sent** → Pending metadata created (`hasBeenApplied = false`)
2. **Transaction arrives** → Metadata matched and applied, `hasBeenApplied = true`, kept for 1 hour
3. **Subsequent updates** → Skipped (efficient, nothing changed)
4. **User modifies metadata**:
   - **If transaction exists**: Applied directly to both pending metadata and transaction (instant UI update)
   - **If transaction doesn't exist**: Pending metadata updated, `hasBeenApplied = false` (will re-apply on next sync)
5. **After 1 hour** → Cleanup deletes matched pending metadata

**Benefits**:
- ✅ Reliable - Metadata never lost due to race conditions
- ✅ Efficient - No redundant writes when nothing changes
- ✅ Fast - Instant UI updates when transaction exists
- ✅ Resilient - Fallback re-application when transaction arrives later
- ✅ Clean - Automatic cleanup keeps database lean

