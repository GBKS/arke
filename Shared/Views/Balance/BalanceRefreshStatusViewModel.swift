//
//  BalanceRefreshStatusViewModel.swift
//  Arke
//
//  Created by Assistant on 4/24/26.
//

import SwiftUI
import Observation
import ArkeUI

/// Shared view model for balance refresh status calculations
/// Uses ultra-simple logic: show when refresh becomes ppm-free (cheapest)
@Observable
@MainActor
class BalanceRefreshStatusViewModel {

    // MARK: - Dependencies

    private let walletManager: WalletManager

    // MARK: - State

    var vtxos: [VTXOModel] = []
    var latestBlockHeight: Int?
    var nextRoundStartTime: UInt64?
    var hasCompletedInitialLoad = false

    /// VTXOs the service would submit on a refresh now (updated during
    /// loadData): the SDK's needs-refresh set minus the exit, in-flight and
    /// back-off exclusions the service itself applies.
    var vtxosNeedingRefresh: [VTXOModel] = []

    /// VTXOs the service holds back because the server rejected them as
    /// unusable within the last 24 h (Refresh_Deduplication.md §9, §10).
    /// The card shows them as its refused state rather than hiding them.
    var heldBackVtxos: [VTXOModel] = []

    // MARK: - Initialization

    init(walletManager: WalletManager) {
        self.walletManager = walletManager
    }

    // MARK: - Computed Properties

    var activeVTXOs: [VTXOModel] {
        vtxos.filter { $0.state != .spent }
    }

    var hasActiveRefresh: Bool {
        walletManager.hasActiveRefresh
    }

    /// Smallest input total bark will build a refresh for.
    var minimumRefreshAmountSats: Int {
        walletManager.minimumRefreshAmountSats
    }

    /// The one decision behind the row (Refresh_Deduplication.md §10).
    var cardState: BalanceRefreshCardState {
        BalanceRefreshCardState.resolve(
            hasActiveRefresh: hasActiveRefresh,
            candidateAmountSats: totalAmountToRefresh,
            candidateCount: vtxosNeedingRefresh.count,
            heldBackAmountSats: totalHeldBackAmount,
            heldBackCount: heldBackVtxos.count,
            blocksUntilPpmFree: blocksUntilPpmFree,
            minimumSats: minimumRefreshAmountSats
        )
    }

    /// Whether the row offers the refresh action. Only the `refreshNow`
    /// state does: below the floor or with every candidate refused, a tap
    /// could not schedule anything.
    var hasVtxosToRefresh: Bool {
        cardState.showsAction
    }

    /// Calculate when the next VTXO enters the ppm-free window
    var nextPpmFreeHeight: Int? {
        guard let feeSchedule = walletManager.arkInfo?.feeSchedule,
              let nextExpiry = activeVTXOs.min(by: { $0.expiryHeight < $1.expiryHeight }) else {
            return nil
        }

        return calculatePpmFreeHeight(vtxo: nextExpiry, feeSchedule: feeSchedule)
    }

    /// Calculate blocks until the ppm-free window starts
    var blocksUntilPpmFree: Int? {
        guard let ppmFreeHeight = nextPpmFreeHeight,
              let currentHeight = latestBlockHeight else {
            return nil
        }
        return ppmFreeHeight - currentHeight
    }

    /// Status line per card state. The refused copy is the modal's title,
    /// verbatim; it never says expired or lost (§10 design 5).
    var statusMessage: String {
        switch cardState {
        case .refreshing:
            return String(localized: "balance_refreshing", defaultValue: "Refreshing")
        case .refreshNow:
            return L10n.balanceRefreshNow
        case .refused:
            return String(localized: "status_refresh_refused", defaultValue: "Can't refresh from this device")
        case .tooSmall:
            return String(localized: "status_refresh_too_small", defaultValue: "Too small to refresh")
        case .countdown(let blocks):
            return String(localized: "balance_refresh_in %@", defaultValue: "Refresh in \(formatBlocks(blocks))")
        case .idle:
            return ""
        }
    }

    /// One explanatory line under the status row for the states that need
    /// one; nil otherwise.
    var detailMessage: String? {
        switch cardState {
        case .refused:
            return String(localized: "balance_refresh_refused_card", defaultValue: "The server refused these coins, so they can't be refreshed from this device. Recovering the wallet from your recovery phrase may restore them — contact support first.")
        case .tooSmall(_, let minimumSats):
            return String(localized: "balance_refresh_too_small_detail %@", defaultValue: "A refresh needs at least \(BitcoinFormatter.shared.formatAmount(minimumSats)) in total.")
        case .refreshing, .refreshNow, .countdown, .idle:
            return nil
        }
    }

    /// Returns the total amount (in satoshis) of VTXOs that should be refreshed
    var totalAmountToRefresh: Int {
        return vtxosNeedingRefresh.reduce(0) { $0 + $1.amountSat }
    }

    /// Total amount (in satoshis) of VTXOs the back-off holds.
    var totalHeldBackAmount: Int {
        heldBackVtxos.reduce(0) { $0 + $1.amountSat }
    }

    // MARK: - Data Loading

    func loadData() async {
        // Before launch has opened the wallet every read below throws
        // walletNotInitialized. Stay in the loading state instead of
        // completing with empty data; the containers reload when
        // isInitialized flips (launch contract rule 7b).
        guard walletManager.isInitialized else { return }

        do {
            vtxos = try await walletManager.getVTXOs()
            latestBlockHeight = await walletManager.getEstimatedBlockHeight()
            nextRoundStartTime = try? await walletManager.nextRoundStartTime()

            // Load VTXOs needing refresh from the SDK, then apply the same
            // exclusions the service applies, in the same order, so the
            // card's list, amount and state match what a tap would schedule
            // (Refresh_Deduplication.md §10):
            // - Guard B: mid-exit VTXOs (fail-open like the service path);
            // - Guard C: VTXOs in an in-flight refresh, *through the
            //   near-expiry valve* — a VTXO with a stale Pending entry close
            //   to expiry is still a candidate, as it is for the service;
            // - the 24 h server-rejection back-off, which yields the
            //   held-back set the refused state is built from.
            let vtxosFromSDK = try await walletManager.getVTXOsNeedingRefresh()
            let beingRefreshed = await walletManager.vtxoIdsBeingRefreshed()
            let exitingIds = await walletManager.exitingVtxoIds()
            let guarded = vtxosFromSDK.filter {
                !RefreshExclusion.isExcluded(
                    id: $0.id,
                    expiryHeight: $0.expiryHeight,
                    exitingIds: exitingIds,
                    beingRefreshedIds: beingRefreshed,
                    currentBlockHeight: latestBlockHeight
                )
            }
            let heldBackIds = walletManager.heldBackVtxoIds(
                among: guarded,
                currentBlockHeight: latestBlockHeight
            )
            heldBackVtxos = guarded.filter { heldBackIds.contains($0.id) }
            vtxosNeedingRefresh = guarded.filter { !heldBackIds.contains($0.id) }
        } catch {
            print("BalanceRefreshStatusViewModel: \(error)")
        }
        hasCompletedInitialLoad = true
    }

    // MARK: - Helper Methods

    /// Calculate when a VTXO enters the ppm-free window
    private func calculatePpmFreeHeight(vtxo: VTXOModel, feeSchedule: FeeSchedule) -> Int? {
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

    /// Format blocks into human-readable time, assuming 10-minute blocks
    /// on all networks.
    func formatBlocks(_ blocks: Int) -> String {
        BlockTimeFormatter.duration(forBlocks: blocks)
    }
}
