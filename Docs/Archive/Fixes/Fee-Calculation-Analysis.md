# Fee Calculation Analysis

**Date**: 2026-04-07  
**Updated**: 2026-04-07 (Unit mismatch identified)  
**Context**: Investigation into exit fee calculation issues revealed in debug logs  
**Status**: ✅ RESOLVED - Issue was unit display confusion, not excessive fees

---

## Executive Summary

**Initial Finding**: Exit errors showed "fee rate of 2092" which appeared to be 2092 sat/vB  
**Actual Issue**: The value is in **sat/kwu** (satoshis per 1000 weight units), not sat/vB  
**Real Fee Rate**: 2092 ÷ 250 = **8.368 sat/vB** (reasonable for Signet)  
**Root Cause**: Unit display mismatch in error messages + insufficient onchain balance for complex exit transactions

---

## Problem Summary

From the debug logs (temp_logs.txt), we initially observed what appeared to be extremely high fees:

1. **Apparent High Fee Rates**: Exit errors showing "fee rate of 2092" 
2. **Insufficient Balance Errors**: Multiple exits failing because 10,000 sats onchain balance is insufficient for exits requiring 11,096 to 44,490 sats
3. **No Fee Rate Control**: `progressExits()` is called with `feeRateSatPerVb: nil`, delegating fee calculation entirely to the Bark Rust library

### Example Error (Line 1041-1048 in logs):
```
VTXO f5e9270fa551d1c1aedde89f87d9cf4fc6df597e08f3711d47f6258cd7ffcd8f:0: Start(ExitStartState { tip_height: 298996 })
  Error: Insufficient Fee Error: Your balance is 0.00010000 BTC but an estimated 0.00011096 BTC (fee rate of 2092) is required to exit the VTXO
```

### The Real Story: Unit Mismatch

**Verification with Bark Developers**:
- Bark's internal fee rates use **sat/kwu** (satoshis per 1000 weight units)
- Error messages display the raw internal value without unit conversion
- Actual Signet fee estimate: 2092 sat/kwu = **8.368 sat/vB**

**Confirmation via Esplora**:
- Queried: `https://esplora.signet.2nd.dev/fee-estimates`
- Current estimate: ~8.369 sat/vB (1-block target)
- **Perfect match**: 8.369 ≈ 2092 ÷ 250

---

## Current Implementation

### 1. **Exit Progression Service** (ExitProgressionService.swift:138)
```swift
let statuses = try await wallet.progressExits(feeRateSatPerVb: nil)
```
- Passes `nil` for fee rate
- No user control over fees
- No environment-aware fee selection

### 2. **BarkWalletFFI** (BarkWalletFFI.swift:1849)
```swift
let statuses = try await wallet.progressExits(
    onchainWallet: onchainWallet, 
    feeRateSatPerVb: feeRateSatPerVb
)
```
- Simply forwards the `nil` to Rust FFI
- No default fee rate handling
- No environment detection

### 3. **Bark Rust Library** (FFI)
When `feeRateSatPerVb` is `nil`:
- ✅ Uses **network-specific fee estimation** via configured Esplora endpoint
- ✅ Queries correct network (validates genesis hash)
- ✅ Returns appropriate Signet fees (~8.368 sat/vB)
- ⚠️ Displays fees in **sat/kwu** in error messages (not sat/vB)

---

## Root Cause Analysis

### ✅ Fee Estimation Working Correctly

**Bark's Fee Estimation Process** (when `feeRateSatPerVb` is `nil`):
1. Queries configured Esplora endpoint for fee estimates
2. Uses "fast" target (1-block confirmation)
3. Correctly retrieves network-appropriate fees
4. Internal storage: **sat/kwu** (satoshis per 1000 weight units)
5. Error display: Shows raw sat/kwu value **without unit conversion**

**From Bark Repository Investigation**:
- Fee source: `ChainSource::update_fee_rates()` at `chain.rs:225-258`
- For Esplora: `get_fee_estimates()` with targets 1/3/6 blocks
- Network validation: Checks genesis hash to ensure correct network
- **Result**: Bark IS using correct Signet-specific fee estimates

### Why Exits Still Fail

**The Real Issue**: Insufficient onchain balance for complex exit transactions

**Exit Transaction Complexity**:
1. **Parent Transaction**: Initial exit transaction
2. **CPFP Transaction**: Child that bumps parent fee via P2A output
3. **Multiple VTXOs**: Each requires its own transaction chain

**Fee Multipliers**:
- Base transaction: ~8.368 sat/vB (correct for Signet)
- CPFP weight factor: **2x multiplier** (see `util.rs:43` in Bark)
- Multiple transactions in exit chain
- **Total**: 10,000-50,000+ sats depending on exit complexity

**Why 10,000 sats is Insufficient**:
```
Small VTXO (750 sats) exit estimate:
  Base tx: 2000 WU × 8.368 sat/vB ÷ 4 = 4,184 sats
  CPFP (2x): 4,184 × 2 = 8,368 sats
  Additional txs: ~3,000-5,000 sats
  Total: ~11,000-13,000 sats needed
  
Balance: 10,000 sats ❌ Insufficient
```

**This is Expected Behavior**: Unilateral exits are emergency operations requiring substantial onchain funds

---

## How Fee Calculation Currently Works

### Exit Transaction Structure

Each unilateral exit involves multiple transactions:
1. **Parent Transaction**: Initial exit transaction (may have low/zero fees)
2. **CPFP Transaction**: Child transaction that bumps parent fee via P2A output
3. **Claim Transaction**: Final transaction to claim exited funds

### Fee Calculation Flow (✅ CORRECTED)

```
User calls startExit()
  ↓
Bark creates exit transactions
  ↓
ExitProgressionService.progressExits(feeRateSatPerVb: nil)
  ↓
BarkWalletFFI.progressExits(feeRateSatPerVb: nil)
  ↓
Bark Rust Library (FFI)
  ├─ Checks if fee rate provided
  ├─ If nil: Uses wallet.chain.fee_rates().fast (vtxo.rs:165)
  │   └─ Queries Esplora fee estimation API
  │       └─ Gets network-specific estimates (validates genesis)
  │       └─ Returns ~8.368 sat/vB for Signet ✅
  ├─ Calculates exit transaction package costs
  │   ├─ Applies 2x CPFP weight multiplier (util.rs:43)
  │   └─ Accounts for multiple chained transactions
  └─ Returns total package cost in sats
      └─ Error messages display internal sat/kwu value (2092)
          └─ User sees: 2092 (confusing, should be 8.368 sat/vB)
```

### Config Fallback (BarkWalletFFI.swift:144)
```swift
self.config = Config(
    // ...
    fallbackFeeRate: nil,  // Use default fee rate
    // ...
)
```
- Config has `fallbackFeeRate` option, but set to `nil`
- Could be used to set reasonable defaults

---

## Issues with Current Approach

### 1. ~~**No Network-Aware Fee Logic**~~ ✅ RESOLVED
- ~~Same fee estimation logic for mainnet and signet~~
- ✅ Bark correctly queries network-specific fee estimates
- ✅ Validates network via genesis hash check
- ✅ Signet fees are appropriate (~8 sat/vB)

### 2. **Unit Display Confusion** ⚠️ NEEDS FIX
- Error messages show raw sat/kwu values (e.g., "2092")
- Users expect sat/vB (standard Bitcoin unit)
- **Fix needed**: Convert sat/kwu → sat/vB in error display
  - Formula: `satPerVb = satPerKwu ÷ 250`

### 3. **No Pre-Flight Balance Validation** ⚠️ NEEDS FIX
- Exits start without checking if onchain balance is sufficient
- Users encounter cryptic "Insufficient Fee" errors during progression
- **Fix needed**: Estimate total exit cost before starting
  - Show user: "Exit requires ~15,000 sats onchain, you have 10,000"

### 4. **No User Control Over Fees**
- Users can't specify fee priority (low/medium/high)
- No way to override automatic estimation
- All exits use "fast" (1-block) target
- **Enhancement**: Add fee priority selection

### 5. **Complex Exit Cost Not Communicated**
- Users don't understand unilateral exits require significant fees
- Multiple chained transactions + CPFP multipliers not explained
- **Enhancement**: Better education about exit costs

### 6. **Config Fallback Unused** (Low Priority)
- `fallbackFeeRate` only used when fee estimation fails
- Currently set to `nil`
- Could provide safety net for estimation outages

---

## Comparison: Expected vs Actual

### ✅ Signet Behavior Analysis (CORRECTED)

| Component | Initial Interpretation | Actual Reality | Status |
|-----------|----------------------|----------------|---------|
| Fee Rate Display | "2092 sat/vB" | 2092 sat/kwu = 8.368 sat/vB | ✅ Reasonable |
| Fee Estimation | Mainnet rates on Signet | Network-specific via Esplora | ✅ Correct |
| Network Detection | No validation | Genesis hash validation | ✅ Working |
| Base Transaction Fee | 1,046,000 sats | ~4,000-8,000 sats | ✅ Appropriate |

### Why Exits Still Require 11,000-44,000 Sats

**Exit Package Breakdown** (750 sat VTXO example):
```
Component                          Cost
────────────────────────────────────────────
Parent transaction (2000 WU)      4,184 sats   (8.368 sat/vB)
CPFP child (2x multiplier)        8,368 sats   (weight factor)
Additional transactions           3,000 sats   (claim, etc.)
────────────────────────────────────────────
Total package cost               ~15,500 sats

User balance:                     10,000 sats  ❌ Insufficient
```

**Conclusion**: 
- ✅ Fee rates are correct (~8 sat/vB)
- ✅ Network detection working properly
- ❌ User balance too low for exit complexity
- ⚠️ Error message confusing (shows sat/kwu not sat/vB)

---

## Recommended Solutions

### ~~Solution 1: Network-Aware Default Fees~~ ❌ NOT NEEDED

**Status**: Bark already implements network-specific fee estimation correctly.

**Original Assumption**: Bark was using mainnet fees on Signet  
**Reality**: Bark queries correct network endpoints and validates via genesis hash  
**Result**: No changes needed to fee estimation logic

### Solution 1: Fix Unit Display in Error Messages (HIGH PRIORITY)

**Problem**: Errors show "fee rate of 2092" (sat/kwu) instead of "8.37 sat/vB"

**Implementation**: Convert units when displaying fee rates

```swift
extension BarkWalletFFI {
    /// Convert Bark's internal fee rate (sat/kwu) to user-friendly sat/vB
    private func convertFeeRateToSatPerVb(_ satPerKwu: UInt64) -> Double {
        return Double(satPerKwu) / 250.0
    }
    
    /// Parse error messages and convert fee rate units
    private func formatErrorMessage(_ error: String) -> String {
        // Look for pattern: "fee rate of XXXX"
        if let range = error.range(of: #"fee rate of (\d+)"#, options: .regularExpression),
           let rateString = error[range].split(separator: " ").last,
           let satPerKwu = UInt64(rateString) {
            let satPerVb = convertFeeRateToSatPerVb(satPerKwu)
            return error.replacingOccurrences(
                of: "fee rate of \(satPerKwu)",
                with: String(format: "fee rate of %.2f sat/vB", satPerVb)
            )
        }
        return error
    }
}
```

**Benefits**:
- ✅ Users see correct, understandable fee rates
- ✅ No confusion about excessive fees
- ✅ Simple, localized change
- ✅ No Bark library changes needed

**Impact**: "fee rate of 2092" → "fee rate of 8.37 sat/vB"

---

### Solution 2: Pre-Flight Exit Cost Estimation (HIGH PRIORITY)

**Problem**: Users start exits without knowing if they have sufficient balance

**Implementation**: Estimate and display total exit cost before starting

```swift
extension WalletOperationsService {
    /// Estimate total cost for exiting specific VTXOs
    func estimateExitCost(vtxoIds: [String]) async throws -> ExitCostEstimate {
        // Query current fee rate
        let feeRate = try await wallet.getCurrentFeeRate()
        
        // Estimate transaction sizes
        let estimatedWeight = estimateExitPackageWeight(vtxoCount: vtxoIds.count)
        
        // Apply CPFP multiplier (2x)
        let cpfpMultiplier: Double = 2.0
        
        // Calculate total
        let baseCost = (estimatedWeight / 4) * feeRate
        let totalCost = UInt64(Double(baseCost) * cpfpMultiplier)
        
        return ExitCostEstimate(
            totalCost: totalCost,
            feeRate: feeRate,
            canAfford: onchainBalance >= totalCost
        )
    }
}

struct ExitCostEstimate {
    let totalCost: UInt64      // Total sats needed
    let feeRate: UInt64        // Current fee rate (sat/vB)
    let canAfford: Bool        // Can user afford this exit?
}
```

**UI Implementation**:
```swift
// Before starting exit, show confirmation
"Exit will require approximately 15,000 sats"
"Your onchain balance: 10,000 sats"
"⚠️ Insufficient balance. Please board more funds."

[Cancel] [Board Funds]
```

**Benefits**:
- ✅ Users know cost upfront
- ✅ No failed exit attempts
- ✅ Better user experience
- ✅ Guides users to board more funds

---

### Solution 3: Improve Exit Cost Documentation (MEDIUM PRIORITY)

**Problem**: Users don't understand why exits are expensive

**Implementation**: Add educational UI explaining exit costs

```swift
struct ExitExplainerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About Unilateral Exits")
                .font(.headline)
            
            Text("Unilateral exits are emergency operations that require:")
                .font(.subheadline)
            
            VStack(alignment: .leading, spacing: 8) {
                ExplainerRow(
                    icon: "link",
                    text: "Multiple on-chain transactions"
                )
                ExplainerRow(
                    icon: "speedometer",
                    text: "CPFP fee bumping (2x multiplier)"
                )
                ExplainerRow(
                    icon: "bitcoinsign.circle",
                    text: "Substantial onchain balance (20,000+ sats)"
                )
            }
            
            Text("💡 Tip: For normal operations, use cooperative exits which are much cheaper.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
```

**Benefits**:
- ✅ Sets proper expectations
- ✅ Reduces support burden
- ✅ Educates users about Ark architecture

---

## Recommended Immediate Actions

### Action 1: Fix Error Message Display (PRIORITY 1)

**File**: `Shared/Data/BarkWalletFFI.swift` (error handling in `progressExits`)

**Add fee rate unit conversion** when displaying errors:

```swift
func progressExits(feeRateSatPerVb: UInt64?) async throws -> [ExitProgressStatus] {
    // ... existing code ...
    
    do {
        let statuses = try await wallet.progressExits(...)
        
        // Convert error messages to user-friendly format
        return statuses.map { status in
            var modifiedStatus = status
            if let error = status.error {
                modifiedStatus.error = formatFeeRateInError(error)
            }
            return modifiedStatus
        }
        
    } catch {
        // ... error handling ...
    }
}

private func formatFeeRateInError(_ error: String) -> String {
    // Convert "fee rate of 2092" to "fee rate of 8.37 sat/vB"
    let pattern = #"fee rate of (\d+)"#
    if let match = error.range(of: pattern, options: .regularExpression) {
        let rateString = String(error[match]).split(separator: " ").last ?? ""
        if let satPerKwu = UInt64(rateString) {
            let satPerVb = Double(satPerKwu) / 250.0
            return error.replacingOccurrences(
                of: "fee rate of \(satPerKwu)",
                with: String(format: "fee rate of %.2f sat/vB", satPerVb)
            )
        }
    }
    return error
}
```

**Impact**: Immediately clarifies error messages for users

---

### Action 2: Document Exit Balance Requirements (PRIORITY 2)

**File**: Create `Docs/Exit-Requirements.md`

**Content**: Document minimum balance requirements:
- Small VTXO (< 1,000 sats): 15,000 sats onchain minimum
- Medium VTXO (1,000-10,000 sats): 25,000 sats onchain minimum  
- Large VTXO (> 10,000 sats): 50,000+ sats onchain minimum

**Purpose**: Set developer and user expectations

---

## Long-Term Improvements

### Phase 1: User Experience (Week 1-2)
1. ✅ Fix fee rate display in error messages (sat/kwu → sat/vB)
2. ✅ Add pre-flight exit cost estimation
3. ✅ Show balance requirements before exit
4. Add "Can't afford exit" error with guidance

### Phase 2: Education & Documentation (Week 2-3)
1. Create exit cost explainer UI
2. Document minimum balance requirements
3. Add tips about cooperative vs unilateral exits
4. Explain CPFP fee multipliers to users

### Phase 3: Advanced Features (Month 2)
1. Add fee priority selection (low/medium/high)
2. Allow custom fee rates for advanced users
3. Show detailed fee breakdown in exit preview
4. Add "board more funds" quick action

### Phase 4: Optimization (Month 3+)
1. Batch multiple VTXOs in single exit (if possible)
2. Intelligent exit timing recommendations
3. Fee prediction based on mempool state
4. Cost comparison: unilateral vs cooperative exit

---

## Testing Plan

### Test Scenarios (UPDATED)

1. **Signet Small Exit** (750 sats VTXO)
   - ✅ Fee rate: ~8.37 sat/vB (correct)
   - ⚠️ Total cost: ~15,500 sats (includes CPFP 2x multiplier)
   - ❌ Current user balance: 10,000 sats (insufficient)
   - **Action needed**: Board 10,000+ more sats to test

2. **Signet Large Exit** (63,000 sats VTXO)
   - ✅ Fee rate: ~8.37 sat/vB (correct)
   - ⚠️ Total cost: ~35,000-45,000 sats
   - ❌ Current user balance: 10,000 sats (insufficient)
   - **Action needed**: Board 40,000+ more sats to test

3. **Error Message Display**
   - ❌ Currently shows: "fee rate of 2092"
   - ✅ Should show: "fee rate of 8.37 sat/vB"
   - **Action needed**: Implement unit conversion

### Validation Criteria (UPDATED)

- ✅ **Fee estimation working correctly** - Bark uses network-specific rates
- ✅ **Network detection working** - Genesis hash validation in place
- ⚠️ **Error messages need fixing** - Display sat/vB not sat/kwu
- ⚠️ **Balance validation needed** - Warn before starting unaffordable exits
- ℹ️ **Exit costs are high by design** - Unilateral exits are emergency operations

---

## Related Files

- `Shared/Services/ExitProgressionService.swift` - Exit progression logic
- `Shared/Data/BarkWalletFFI.swift` - FFI wallet implementation
- `Shared/Data/BDKCpfpHelper.swift` - CPFP transaction creation
- `Shared/Models/NetworkConfig.swift` - Network configuration
- `Shared/Models/FeePriority.swift` - Fee priority enum (exists)

---

## Conclusion

### ✅ Investigation Results

**Initial Concern**: Exit errors showing "fee rate of 2092" appeared to indicate excessive fees (2092 sat/vB)

**Actual Finding**: 
- ✅ Bark's fee estimation is **working correctly**
- ✅ The 2092 value is in **sat/kwu**, not sat/vB
- ✅ Real fee rate: 2092 ÷ 250 = **8.37 sat/vB** (appropriate for Signet)
- ✅ Bark validates network via genesis hash and queries correct fee endpoints

### Root Causes Identified

1. **Unit Display Mismatch**: Error messages show internal sat/kwu values instead of user-friendly sat/vB
2. **Insufficient Balance**: 10,000 sats is too low for complex unilateral exits (need 15,000-50,000+ sats)
3. **No Pre-Flight Validation**: Users aren't warned about exit costs before starting
4. **Lack of Education**: Users don't understand unilateral exits require substantial fees by design
### Recommended Actions

**High Priority**:
1. ✅ Convert error message fee rates: sat/kwu → sat/vB (user-facing fix)
2. ✅ Add pre-flight cost estimation: Show total cost before starting exit
3. ✅ Add balance validation: Warn if insufficient onchain balance

**Medium Priority**:
4. Document minimum balance requirements per VTXO size
5. Add educational UI explaining exit costs
6. Improve error messages with actionable guidance ("Board more funds")

**Low Priority**:
7. Add fee priority selection for advanced users
8. Implement cost estimation API for UI

### Impact Assessment

**No Code Changes Needed For**:
- ❌ ~~Fee estimation logic~~ (already correct)
- ❌ ~~Network detection~~ (already working)
- ❌ ~~Fallback fee rates~~ (only used on estimation failure)

**Code Changes Needed For**:
- ✅ Error message display (format sat/kwu as sat/vB)
- ✅ Balance validation (check before exit)
- ✅ User education (explain costs)

**Expected Outcome**:
- Users understand actual fee rates (~8 sat/vB, not 2092)
- Users know upfront if they can afford exit
- Fewer failed exit attempts due to insufficient balance
- Better understanding of unilateral exit costs

