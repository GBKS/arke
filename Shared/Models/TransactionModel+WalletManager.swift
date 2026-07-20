//
//  TransactionModel+WalletManager.swift
//  Ark wallet prototype
//
//  App-side service lookups for `TransactionModel`. The pure value type lives in
//  the ArkéUI package; these computed properties reach into `WalletManager`
//  (current block height, cached unilateral exits) and therefore stay app-side so
//  the model itself remains free of app singletons and previewable in isolation.
//
//  Views set `TransactionModel.walletManager` before displaying transactions.
//

import Foundation
import ArkeUI
import Bark

extension TransactionModel {

    // MARK: - WalletManager hook

    /// Weak reference to wallet manager for looking up live confirmations and
    /// current exit status. This is set by views when displaying transactions.
    static weak var walletManager: AnyObject?

    // MARK: - Confirmation Helpers

    /// Get live confirmation count based on current block height
    /// This is calculated dynamically from confirmationHeight and current chain tip
    /// Returns nil if this is not an onchain transaction or if confirmation height is unknown
    var liveConfirmations: UInt32? {
        guard let confirmationHeight = confirmationHeight else {
            // Not an onchain transaction or unconfirmed
            return confirmationCount
        }

        // Access wallet manager through the static weak reference
        guard let walletManager = Self.walletManager as? WalletManager else {
            // Fallback to stored confirmationCount if wallet manager unavailable
            return confirmationCount
        }

        // Get current block height
        guard let currentHeight = walletManager.estimatedBlockHeight else {
            // Fallback to stored confirmationCount if current height unavailable
            return confirmationCount
        }

        // Calculate confirmations: currentHeight - confirmationHeight + 1
        // +1 because a transaction in block 100 has 1 confirmation at height 100
        let calculatedConfirmations = UInt32(currentHeight) - confirmationHeight + 1
        return max(calculatedConfirmations, 1)  // Ensure at least 1 confirmation if confirmed
    }

    // MARK: - Exit Status Helpers

    /// Get the current exit status for this transaction
    /// Returns nil if this is not an exit transaction or if wallet manager is not available
    var currentExitStatus: ExitStatus? {
        // Early return: Not an exit transaction
        guard hasUnilateralExit else {
            return nil
        }

        // Early return: Wallet manager not available
        guard let walletManager = Self.walletManager as? WalletManager else {
            return nil
        }

        // Early return: Wallet not initialized yet (prevents cache refresh storms)
        guard walletManager.isInitialized else {
            return nil
        }

        // Get all exits from cache (no refresh triggered)
        let allExits = walletManager.allUnilateralExits

        // For exit transactions, the VTXOs are in inputVtxoIds (not exitedVtxoIds which is empty)
        // Find the exit that matches any of this transaction's input VTXOs
        for vtxoId in inputVtxoIds {
            if let exit = allExits.first(where: { $0.vtxoId == vtxoId }) {
                return ExitStatus(from: exit)
            }
        }

        return nil
    }

    /// Check if the exit associated with this transaction is claimed
    var isExitClaimed: Bool {
        currentExitStatus?.isClaimed ?? false
    }

    /// Whether this transaction's unilateral exit has completed (claimed).
    ///
    /// Checks the persisted movement status first: bark finishes the exit
    /// movement as Successful exactly when the exit reaches Claimed (and the
    /// movement stays Pending the whole exit otherwise), so `.confirmed` is a
    /// terminal signal that survives relaunch. The in-memory exit caches are
    /// empty until the first refresh completes, so relying on them alone makes
    /// completed exits flash as in-progress at launch. The cache check remains
    /// as a fallback for a claim that happened in this session before the next
    /// movement sync.
    var isExitComplete: Bool {
        guard hasUnilateralExit else { return false }
        if transactionStatus == .confirmed { return true }
        return isExitClaimed
    }

    /// Blocked info for this transaction's exit, if the exit can't currently
    /// progress because fees can't be covered. Debounced: only non-nil once the
    /// blockage has persisted for 2+ consecutive progression checks.
    var exitBlockedInfo: ExitBlockedInfo? {
        guard hasUnilateralExit else {
            return nil
        }

        guard let walletManager = Self.walletManager as? WalletManager else {
            return nil
        }

        // Exit transactions carry their VTXOs in inputVtxoIds (exitedVtxoIds is
        // empty for them); check both to match currentExitStatus above
        for vtxoId in inputVtxoIds + exitedVtxoIds {
            if let info = walletManager.getExitBlockedInfo(for: vtxoId) {
                return info
            }
        }

        return nil
    }
}
