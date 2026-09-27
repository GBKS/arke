# VTXO Refresh Logic - Simplified Plan

> **📦 Archived 2026-07-09.** Implementation shipped 2026-04-24 (expiry-calculation fixes 2026-05-04). `Shared/Views/Balance/BalanceRefreshStatusViewModel.swift` implements this plan's ppm-free-window design as described.

## Problem

User has a VTXO expiring in 3d 11h. UI shows "Refresh urgent now" (orange), but tapping shows no VTXOs need refreshing. Confusing!

## Root Cause

UI urgency based on arbitrary percentage thresholds (15% of lifespan) doesn't match when:
1. Refresh becomes **ppm-free** (cheapest time to refresh)
2. SDK says refresh is **actually needed** (`getVtxosToRefresh()`)

## Ultra-Simple Solution

### Single Rule: Show When PPM-Free Window Starts

Calculate when the next VTXO enters the **ppm-free window** from the server's fee schedule.

Three states only:
1. **"Refresh in Xd Xh"** - Countdown to ppm-free window
2. **"Refresh now"** + button - SDK has VTXOs ready
3. **"Refreshing"** - Active refresh in progress

---

## Implementation

### 1. Calculate PPM-Free Height

```swift
/// Calculate when a VTXO enters the ppm-free window
func calculatePpmFreeHeight(
    vtxo: VTXOModel,
    feeSchedule: FeeSchedule
) -> Int? {
    // Find the threshold where ppm becomes 0
    let ppmTable = feeSchedule.refresh.ppmExpiryTable
        .sorted { $0.expiryBlocksThreshold > $1.expiryBlocksThreshold }

    for entry in ppmTable {
        if entry.ppm == 0 {
            // VTXO enters ppm-free window at:
            // expiry_height - threshold_blocks
            return vtxo.expiryHeight - entry.expiryBlocksThreshold
        }
    }

    // No ppm-free window exists
    return nil
}
```

**Example**:
- VTXO expires at block 850,000
- Fee schedule: `{ expiryBlocksThreshold: 288, ppm: 0 }` (last 2 days)
- PPM-free height = 850,000 - 288 = **849,712**
- At block 849,700: "Refresh in 12 blocks" (~2 hours)

### 2. BalanceRefreshStatusViewModel

```swift
@Observable
@MainActor
class BalanceRefreshStatusViewModel {
    private let walletManager: WalletManager

    var vtxos: [VTXOModel] = []
    var latestBlockHeight: Int?
    var vtxosNeedingRefresh: [VTXOModel] = []
    var hasCompletedInitialLoad = false

    // Simple computed properties

    var hasActiveRefresh: Bool {
        walletManager.transactions.contains {
            $0.category == .refresh && $0.status == .pending
        }
    }

    var hasVtxosToRefresh: Bool {
        !vtxosNeedingRefresh.isEmpty && !hasActiveRefresh
    }

    var nextPpmFreeHeight: Int? {
        guard let feeSchedule = walletManager.arkInfo?.feeSchedule,
              let nextExpiry = vtxos.filter({ $0.state != .spent })
                .min(by: { $0.expiryHeight < $1.expiryHeight }) else {
            return nil
        }

        return calculatePpmFreeHeight(vtxo: nextExpiry, feeSchedule: feeSchedule)
    }

    var blocksUntilPpmFree: Int? {
        guard let ppmFreeHeight = nextPpmFreeHeight,
              let currentHeight = latestBlockHeight else {
            return nil
        }
        return ppmFreeHeight - currentHeight
    }

    var statusMessage: String {
        if hasActiveRefresh {
            return "Refreshing"
        } else if hasVtxosToRefresh {
            return "Refresh now"
        } else if let blocks = blocksUntilPpmFree, blocks > 0 {
            return "Refresh in \(formatBlocks(blocks))"
        } else {
            return ""
        }
    }

    func formatBlocks(_ blocks: Int) -> String {
        let secondsPerBlock = walletManager.arkInfo?.network == "mainnet" ? 600 : 150
        let seconds = blocks * secondsPerBlock

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll

        return formatter.string(from: TimeInterval(seconds)) ?? "\(blocks) blocks"
    }

    func loadData() async {
        do {
            vtxos = try await walletManager.getVTXOs()
            latestBlockHeight = await walletManager.getEstimatedBlockHeight()

            let vtxosFromSDK = try await walletManager.getVTXOsNeedingRefresh()

            if hasActiveRefresh {
                let beingRefreshed = vtxosBeingRefreshed
                vtxosNeedingRefresh = vtxosFromSDK.filter { !beingRefreshed.contains($0.id) }
            } else {
                vtxosNeedingRefresh = vtxosFromSDK
            }
        } catch {
            print("Error loading data: \(error)")
        }
        hasCompletedInitialLoad = true
    }

    private var vtxosBeingRefreshed: Set<String> {
        guard hasActiveRefresh else { return Set() }
        let pendingRefreshes = walletManager.transactions.filter {
            $0.category == .refresh && $0.status == .pending
        }
        return Set(pendingRefreshes.flatMap { $0.inputVtxoIds })
    }
}
```

### 3. BalanceRefreshStatusContainerCompact

```swift
struct BalanceRefreshStatusContainerCompact: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var viewModel: BalanceRefreshStatusViewModel?

    var onRefresh: (() async -> Void)?

    var body: some View {
        BalanceRefreshStatusCompact(
            message: viewModel?.statusMessage ?? "",
            showButton: viewModel?.hasVtxosToRefresh ?? false,
            onTap: {
                // Open refresh modal
            }
        )
        .task {
            if viewModel == nil {
                viewModel = BalanceRefreshStatusViewModel(walletManager: walletManager)
            }
            await viewModel?.loadData()
        }
        .onChange(of: walletManager.transactionVersion) {
            Task { await viewModel?.loadData() }
        }
    }
}
```

### 4. BalanceRefreshTag (Activity View)

```swift
struct BalanceRefreshTag: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var viewModel: BalanceRefreshStatusViewModel?

    var body: some View {
        let shouldShow = (viewModel?.hasVtxosToRefresh ?? false)

        if shouldShow {
            Text("Refresh now")
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(5)
        }
    }
}
```

### 5. RefreshModalView

No changes needed - already uses `vtxosNeedingRefresh` correctly.

### 6. VTXORefreshService

Keep as-is - already uses SDK's `getNextRequiredRefreshBlockheight()` for notifications.

---

## Behavior Examples

### Scenario 1: VTXO with 3d 11h remaining (your case)

**Fee Schedule**: PPM-free in last 288 blocks (~2 days)

- Current: Block 849,500
- Expiry: Block 850,000
- PPM-free starts: Block 849,712 (2 days before expiry)
- Blocks until ppm-free: 212 blocks (~1.4 days)

**UI Shows**:
- Balance view: "Refresh in 1d 10h" (gray)
- Activity view: Nothing (tag hidden)
- Button: Hidden (SDK hasn't returned VTXOs yet)

### Scenario 2: Entered ppm-free window, SDK ready

- Current: Block 849,750
- PPM-free: Already started
- SDK: Returns VTXOs (within must-refresh threshold)

**UI Shows**:
- Balance view: "Refresh now" (orange) + button visible
- Activity view: "Refresh now" tag (orange)
- Button: Shown, tapping opens modal

### Scenario 3: Active refresh

**UI Shows**:
- Balance view: "Refreshing" (blue)
- Activity view: Nothing (tag hidden during refresh)
- Button: Hidden

---

## Files to Modify

- [ ] **Delete or simplify** `Arke/Shared/Helpers/RefreshUrgency.swift` - No longer needed
- [ ] **Rewrite** `Arke/Shared/Views/Balance/BalanceRefreshStatusViewModel.swift` - Use simple ppm-free calculation
- [ ] **Simplify** `Arke/Shared/Views/Balance/BalanceRefreshStatusContainerCompact.swift` - Three messages only
- [ ] **Simplify** `Arke/Shared/UI/BalanceRefreshTag.swift` - Show only when `hasVtxosToRefresh`
- [ ] `Arke/Shared/Views/Balance/RefreshModalView.swift` - No changes
- [ ] `Arke/Shared/Services/VTXORefreshService.swift` - No changes

---

## Success Criteria

✅ User sees "Refresh in Xd Xh" until ppm-free window
✅ User sees "Refresh now" + button when SDK says refresh available
✅ No confusing "urgent" warnings when nothing to do
✅ Simple, clear messaging
✅ Aligned with economic reality (ppm-free window)

---

## Notes

**If base_fee > 0**: Refresh is never fully free, but ppm-free is still the cheapest time. We could optionally show cost: "Refresh in 1d 10h (100 sats)" but let's start without that complexity.

**Color scheme**: Could add subtle color changes:
- Gray: "Refresh in Xd Xh"
- Orange: "Refresh now"
- Blue: "Refreshing"

But keep it minimal - focus on clear messaging over visual complexity.
