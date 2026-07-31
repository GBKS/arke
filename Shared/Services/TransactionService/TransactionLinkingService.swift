//
//  TransactionLinkingService.swift
//  Arke
//
//  Service for linking movement transactions with their corresponding onchain transactions.
//  Handles boarding, offboarding, and exit operations bidirectionally.
//

import Foundation
import SwiftData
import Bark
import ArkeUI
import os

/// Service responsible for linking movement transactions with onchain transactions
@MainActor
class TransactionLinkingService {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "TransactionLinking")
    
    private weak var walletManager: WalletManager?
    
    init(walletManager: WalletManager? = nil) {
        self.walletManager = walletManager
    }
    
    func setWalletManager(_ manager: WalletManager) {
        self.walletManager = manager
    }
    
    // MARK: - Public Methods
    
    /// Re-link all unlinked or partially linked exit movements
    /// Called when exit status cache is refreshed to pick up new transactions.
    ///
    /// `statusFor` resolves a VTXO's exit status; tests inject it. The
    /// default tries the in-memory cache and falls back to
    /// getExitStatus(vtxoId:) — bark purges completed exits from its exit
    /// list (which scopes the in-memory cache) but per-id lookups and the
    /// persisted snapshots still answer. Without the fallback, an onchain
    /// record that appears after the purge (e.g. a late CPFP re-bump synced
    /// by BDK) could never be linked (field case 2026-07-30, txid 0dc9ffa0…).
    func relinkExitMovements(
        context: ModelContext,
        statusFor: ((String) async -> ExitTransactionStatus?)? = nil
    ) async {
        let statusFor = statusFor ?? { [weak walletManager] vtxoId in
            if let cached = walletManager?.getCachedExitStatus(for: vtxoId) {
                return cached
            }
            return try? await walletManager?.getExitStatus(
                vtxoId: vtxoId,
                includeHistory: true,
                includeTransactions: true
            )
        }

        do {
            // Find all exit movements (linked or unlinked)
            let descriptor = FetchDescriptor<PersistentTransaction>(
                predicate: #Predicate { transaction in
                    transaction.sourceType == "ark" && transaction.subsystemCategory == "exit"
                }
            )
            
            let exitMovements = try context.fetch(descriptor)
            
            guard !exitMovements.isEmpty else {
                Self.logger.debug("🔗 No exit movements found to re-link")
                return
            }
            
            Self.logger.info("🔗 Re-linking \(exitMovements.count) exit movement(s)")
            
            var totalLinked = 0
            var totalSkipped = 0
            
            for movement in exitMovements {
                // For exits, the VTXOs are in inputVtxoIds (not exitedVtxoIds which is empty)
                let vtxoIds = movement.inputVtxoIds
                guard !vtxoIds.isEmpty else {
                    Self.logger.debug("   ⏭️ Movement \(movement.txid) has no input VTXOs, skipping")
                    totalSkipped += 1
                    continue
                }
                
                Self.logger.debug("   🔍 Processing movement \(movement.txid) with \(vtxoIds.count) input VTXO(s)")
                
                var allTxids = Set<String>()
                for vtxoId in vtxoIds {
                    if let status = await statusFor(vtxoId) {
                        // User-funded only: CPFP children a third party created
                        // by spending our anchor must not be linked into the
                        // user's history or fee totals
                        let txids = ExitStatusParser.extractUserFundedTransactionIds(from: status)
                        Self.logger.debug("      📋 VTXO \(vtxoId.prefix(16))... has \(txids.count) user-funded txid(s): \(txids.map { $0.prefix(16) }.joined(separator: ", "))")
                        allTxids.formUnion(txids)
                    } else {
                        Self.logger.warning("      ⚠️ No exit status available for VTXO \(vtxoId.prefix(16))...")
                    }
                }
                
                guard !allTxids.isEmpty else {
                    Self.logger.debug("   ⏭️ Movement \(movement.txid) has no extractable txids from exit statuses")
                    totalSkipped += 1
                    continue
                }
                
                Self.logger.info("   📦 Found \(allTxids.count) total txid(s) for movement \(movement.txid)")
                
                // Get currently linked txids
                let currentlyLinked = Set(movement.childTxids ?? [])
                if !currentlyLinked.isEmpty {
                    Self.logger.debug("   🔗 Already linked: \(currentlyLinked.map { $0.replacingOccurrences(of: "onchain_", with: "").prefix(16) }.joined(separator: ", "))")
                    // Diagnostic: dump fee attribution of existing children so
                    // misattributed fees (e.g. third-party anchor spends) show
                    // up even when no new links are created
                    for childTxid in currentlyLinked.sorted() {
                        let childDescriptor = FetchDescriptor<PersistentTransaction>(
                            predicate: #Predicate { $0.txid == childTxid }
                        )
                        if let child = try? context.fetch(childDescriptor).first {
                            Self.logger.info("   🔎 Child \(childTxid.prefix(28))...: fee=\(child.onchainFeeSat.map(String.init) ?? "nil"), sent=\(child.onchainSent.map(String.init) ?? "nil"), received=\(child.onchainReceived.map(String.init) ?? "nil"), source=\(child.sourceType)")
                        } else {
                            Self.logger.info("   🔎 Child \(childTxid.prefix(28))...: no wallet record")
                        }
                    }
                }
                
                // Find new txids to link
                let newTxids = allTxids.filter { txid in
                    let onchainTxid = "onchain_\(txid)"
                    return !currentlyLinked.contains(onchainTxid)
                }
                
                if newTxids.isEmpty {
                    Self.logger.debug("   ✅ Movement \(movement.txid) already has all txids linked")
                    continue
                }
                
                Self.logger.info("   🆕 Found \(newTxids.count) new txid(s) to link")
                
                // Link new transactions
                for txid in newTxids {
                    let onchainTxid = "onchain_\(txid)"
                    let onchainDescriptor = FetchDescriptor<PersistentTransaction>(
                        predicate: #Predicate { $0.txid == onchainTxid }
                    )
                    
                    if let onchainTx = try context.fetch(onchainDescriptor).first {
                        linkParentToChild(parent: movement, child: onchainTx, onchainTxid: onchainTxid)
                        Self.logger.info("      ✅ Linked exit movement \(movement.txid) -> onchain \(txid.prefix(16))... (fee: \(onchainTx.onchainFeeSat.map(String.init) ?? "nil"), sent: \(onchainTx.onchainSent.map(String.init) ?? "nil"), received: \(onchainTx.onchainReceived.map(String.init) ?? "nil"), source: \(onchainTx.sourceType))")
                        totalLinked += 1
                    } else {
                        Self.logger.debug("      ⚠️ Onchain transaction \(onchainTxid) not found in database")
                    }
                }
            }
            
            try context.save()
            
            Self.logger.info("🔗 Re-linking complete: \(totalLinked) new link(s) created, \(totalSkipped) movement(s) skipped")
            
        } catch {
            Self.logger.error("❌ Failed to re-link exit movements: \(error)")
        }
    }
    
    /// Link a just-broadcast claim transaction to its exit movement(s).
    /// Called at drain time with the exact VTXO ids being claimed — bark
    /// purges completed exits from its exit list, so the status-cache
    /// relink above can miss the claim txid entirely if no refresh lands
    /// in the window between broadcast and purge. This path has no such
    /// window: everything needed is known the moment the claim exists.
    /// A single claim can drain multiple exits; all matching movements get
    /// the claim tx in childTxids (parentTxid points to the last one, which
    /// is enough to hide the claim from the activity list).
    func linkClaimTransaction(claimTxid: String, drainedVtxoIds: [String], context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<PersistentTransaction>(
                predicate: #Predicate { transaction in
                    transaction.sourceType == "ark" && transaction.subsystemCategory == "exit"
                }
            )
            let drained = Set(drainedVtxoIds)
            let parents = try context.fetch(descriptor).filter { movement in
                !drained.isDisjoint(with: movement.inputVtxoIds)
            }

            guard !parents.isEmpty else {
                Self.logger.warning("🔗 No exit movement found for claim \(claimTxid.prefix(16))... (\(drainedVtxoIds.count) VTXO(s))")
                return
            }

            let onchainTxid = "onchain_\(claimTxid)"
            let onchainDescriptor = FetchDescriptor<PersistentTransaction>(
                predicate: #Predicate { $0.txid == onchainTxid }
            )
            guard let onchainTx = try context.fetch(onchainDescriptor).first else {
                Self.logger.warning("🔗 Claim onchain record \(onchainTxid) not found - cannot link")
                return
            }

            for parent in parents {
                linkParentToChild(parent: parent, child: onchainTx, onchainTxid: onchainTxid)
            }
            try context.save()

            Self.logger.info("🔗 Linked claim \(claimTxid.prefix(16))... to \(parents.count) exit movement(s)")

        } catch {
            Self.logger.error("❌ Failed to link claim transaction: \(error)")
        }
    }

    /// Establish links when a movement transaction is upserted
    /// Searches for matching onchain transactions and links them if found
    /// - Parameters:
    ///   - movementTxid: The movement transaction ID (e.g., "movement_123")
    ///   - metadataJson: The raw metadata JSON from the movement
    ///   - subsystemName: The subsystem name (e.g., "bark.board", "bark.offboard")
    ///   - category: The movement category
    ///   - context: SwiftData model context
    func establishLinksForMovement(
        movementTxid: String,
        movementId: Int,
        metadataJson: String?,
        subsystemName: String,
        category: MovementCategory,
        context: ModelContext
    ) {
        do {
            // Fetch the movement transaction
            let descriptor = FetchDescriptor<PersistentTransaction>(
                predicate: #Predicate { $0.txid == movementTxid }
            )
            guard let movement = try context.fetch(descriptor).first else {
                Self.logger.warning("⚠️ Movement not found: \(movementTxid)")
                return
            }
            
            Self.logger.debug("🔍 Establishing links for movement \(movementTxid) (category: \(category.rawValue))")
            
            // For exits, allow re-linking since exit status may not be available initially
            // For other categories, skip if already linked
            if category != .exit && movement.childTxids != nil && !(movement.childTxids?.isEmpty ?? true) {
                Self.logger.debug("   ⏭️ Already linked (\(movement.childTxids?.count ?? 0) child(s)), skipping")
                return
            }
            
            // Extract linkable onchain txids using provided metadata
            // For exits, pass inputVtxoIds (not exitedVtxoIds which is empty for exits)
            let vtxoIdsForLinking = category == .exit ? movement.inputVtxoIds : movement.exitedVtxoIds
            let linkableTxids = extractLinkableTransactionIds(
                category: category,
                metadataJson: metadataJson,
                subsystemName: subsystemName,
                movementId: movementId,
                exitedVtxoIds: vtxoIdsForLinking
            )
            
            if linkableTxids.isEmpty {
                /*
                if category == .exit {
                    Self.logger.debug("   ℹ️ No linkable txids found yet (exit status may not be cached)")
                } else {
                    Self.logger.debug("   ℹ️ No linkable txids found in metadata")
                }
                */
                return
            }
            
            Self.logger.info("   📦 Found \(linkableTxids.count) linkable txid(s): \(linkableTxids.map { $0.prefix(16) }.joined(separator: ", "))")
            
            // Search for matching onchain transactions
            var linkedCount = 0
            for txid in linkableTxids {
                let onchainTxid = "onchain_\(txid)"
                let onchainDescriptor = FetchDescriptor<PersistentTransaction>(
                    predicate: #Predicate { $0.txid == onchainTxid }
                )
                
                if let onchainTx = try context.fetch(onchainDescriptor).first {
                    linkParentToChild(parent: movement, child: onchainTx, onchainTxid: onchainTxid)
                    Self.logger.info("      ✅ Linked movement \(movementTxid) -> onchain \(txid.prefix(16))... (fee: \(onchainTx.onchainFeeSat.map(String.init) ?? "nil"), sent: \(onchainTx.onchainSent.map(String.init) ?? "nil"), source: \(onchainTx.sourceType))")
                    linkedCount += 1
                } else {
                    Self.logger.debug("      ⚠️ Onchain transaction \(onchainTxid) not found in database")
                }
            }
            
            try context.save()
            
            if linkedCount > 0 {
                Self.logger.info("   ✅ Successfully linked \(linkedCount) onchain transaction(s)")
            }
            
        } catch {
            Self.logger.error("❌ Failed to establish links for movement: \(error)")
        }
    }
    
    /// Establish links when an onchain transaction is upserted
    /// Searches for a parent movement that should link to this onchain transaction
    func establishLinksForOnchain(onchainTxid: String, context: ModelContext) {
        do {
            // Fetch the onchain transaction
            let descriptor = FetchDescriptor<PersistentTransaction>(
                predicate: #Predicate { $0.txid == onchainTxid }
            )
            guard let onchainTx = try context.fetch(descriptor).first else {
                Self.logger.warning("⚠️ Onchain transaction not found: \(onchainTxid)")
                return
            }
            
            // Skip if already linked
            if onchainTx.parentTxid != nil {
                return
            }
            
            // Extract actual txid (remove "onchain_" prefix)
            guard onchainTxid.hasPrefix("onchain_") else {
                return
            }
            let actualTxid = String(onchainTxid.dropFirst("onchain_".count))
            
            // Find parent movement
            if let parentMovement = findParentMovement(for: actualTxid, context: context) {
                linkParentToChild(parent: parentMovement, child: onchainTx, onchainTxid: onchainTxid)
                Self.logger.info("🔗 Linked movement \(parentMovement.txid) <- onchain \(onchainTxid)")
                try context.save()
            }
            
        } catch {
            Self.logger.error("❌ Failed to establish links for onchain: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    /// Extract linkable onchain transaction IDs from movement metadata
    private func extractLinkableTransactionIds(
        category: MovementCategory,
        metadataJson: String?,
        subsystemName: String,
        movementId: Int,
        exitedVtxoIds: [String]
    ) -> [String] {
        var txids = [String]()
        
        switch category {
        case .boarding:
            // Extract from BoardMetadata chain_anchor
            if let metadata = parseMetadata(metadataJson: metadataJson, subsystemName: subsystemName)?.asBoard {
                // chain_anchor format: "txid:vout"
                if let txid = extractTxidFromChainAnchor(metadata.chainAnchor) {
                    txids.append(txid)
                }
            }
            
        case .offboarding, .onchainSend:
            // Extract from OffboardMetadata offboard_txid
            // Both offboarding and onchainSend use bark.offboard subsystem and have offboard_txid
            if let metadata = parseMetadata(metadataJson: metadataJson, subsystemName: subsystemName)?.asOffboard {
                txids.append(metadata.offboardTxid)
            }
            
        case .exit:
            // For exits, the VTXOs are in exitedVtxoIds parameter (passed as inputVtxoIds from movement)
            // Extract txids from cached exit statuses
            if !exitedVtxoIds.isEmpty {
                Self.logger.debug("   🔍 Extracting txids from \(exitedVtxoIds.count) input VTXO(s)")
                for vtxoId in exitedVtxoIds {
                    if let status = walletManager?.getCachedExitStatus(for: vtxoId) {
                        // User-funded only — see relinkExitMovements
                        let exitTxids = ExitStatusParser.extractUserFundedTransactionIds(from: status)
                        if !exitTxids.isEmpty {
                            Self.logger.debug("      📋 VTXO \(vtxoId.prefix(16))... yielded \(exitTxids.count) txid(s)")
                            txids.append(contentsOf: exitTxids)
                        }
                    } else {
                        Self.logger.warning("      ⚠️ No cached exit status for VTXO \(vtxoId.prefix(16))...")
                    }
                }
            } else {
                Self.logger.debug("   ℹ️ No input VTXOs for this exit movement")
            }
            
        default:
            break
        }
        
        return txids
    }
    
    /// Find the parent movement that should link to this onchain txid
    private func findParentMovement(for actualTxid: String, context: ModelContext) -> PersistentTransaction? {
        do {
            // Fetch all unlinked movements (where childTxids is nil or empty)
            let descriptor = FetchDescriptor<PersistentTransaction>(
                predicate: #Predicate { transaction in
                    transaction.sourceType == "ark" && transaction.childTxids == nil
                }
            )
            
            _ = try context.fetch(descriptor)
            
            // Search each movement for matching txid
            // Note: This requires re-fetching movement metadata, which isn't stored in PersistentTransaction
            // For now, we'll rely on the movement->onchain direction being the primary linking path
            // The onchain->movement direction will work for exits via exit status
            
            /*
            for movement in unlinkedMovements {
                guard let category = movement.category else { continue }
                
                // For exits, linking is skipped (see note in extractLinkableTransactionIds)
                // Exit transactions remain as separate entries in the list
                
                // For boarding/offboarding, we can't easily re-parse metadata
                // The primary linking happens when the movement is upserted
            }
            */
            
        } catch {
            Self.logger.error("❌ Failed to find parent movement: \(error)")
        }
        
        return nil
    }
    
    /// Establish bidirectional link between parent movement and child onchain transaction
    private func linkParentToChild(parent: PersistentTransaction, child: PersistentTransaction, onchainTxid: String) {
        // Set parent reference on child
        child.parentTxid = parent.txid
        
        // Add child to parent's childTxids array
        if parent.childTxids == nil {
            parent.childTxids = [onchainTxid]
        } else if !(parent.childTxids?.contains(onchainTxid) ?? false) {
            parent.childTxids?.append(onchainTxid)
        }
    }
    
    /// Extract txid from chain_anchor format (txid:vout)
    private func extractTxidFromChainAnchor(_ chainAnchor: String) -> String? {
        let components = chainAnchor.split(separator: ":")
        guard !components.isEmpty else { return nil }
        return String(components[0])
    }
    
    /// Parse movement metadata JSON
    private func parseMetadata(metadataJson: String?, subsystemName: String) -> MovementMetadata? {
        guard let json = metadataJson, !json.isEmpty else {
            return nil
        }
        return MovementMetadataParser.parse(json: json, subsystemName: subsystemName)
    }
}
