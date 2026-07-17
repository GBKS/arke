//
//  TransactionModel+Persistence.swift
//  Ark wallet prototype
//
//  The `TransactionModel` value type itself now lives in the ArkéUI package as a
//  pure, previewable presentation model. This file holds the app-side bridging
//  between that value type and the SwiftData `PersistentTransaction` store, plus
//  the `*IncludingLinked` fee/amount variants that need a `ModelContext` to fetch
//  linked onchain child transactions. Kept here so the model stays free of
//  SwiftData and remains previewable in isolation.
//

import Foundation
import SwiftData
import ArkeUI

extension TransactionModel {

    // MARK: - Initialize from PersistentTransaction

    init(from persistentTransaction: PersistentTransaction) {
        self.init(
            txid: persistentTransaction.txid,
            movementId: persistentTransaction.movementId,
            recipientIndex: persistentTransaction.recipientIndex,
            type: persistentTransaction.transactionType,
            amount: persistentTransaction.amount,
            date: persistentTransaction.date,
            status: persistentTransaction.transactionStatus,
            address: persistentTransaction.address,
            notes: persistentTransaction.notes,
            associatedTags: persistentTransaction.associatedTags.map { TagModel(from: $0) },
            associatedContacts: persistentTransaction.associatedContacts.map { ContactModel(from: $0) },
            fees: persistentTransaction.fees,
            onchainFeeSat: persistentTransaction.onchainFeeSat,
            subsystemCategory: persistentTransaction.subsystemCategory,
            subsystemName: persistentTransaction.subsystemName,
            subsystemKind: persistentTransaction.subsystemKind,
            paymentMethodType: persistentTransaction.paymentMethodType,
            paymentHash: persistentTransaction.paymentHash,
            paymentPreimage: persistentTransaction.paymentPreimage,
            fundingTxid: persistentTransaction.fundingTxid,
            inputVtxoIds: persistentTransaction.inputVtxoIds,
            outputVtxoIds: persistentTransaction.outputVtxoIds,
            exitedVtxoIds: persistentTransaction.exitedVtxoIds,
            confirmationHeight: persistentTransaction.confirmationHeight,
            confirmationCount: persistentTransaction.confirmationCount,
            category: persistentTransaction.category,
            parentTxid: persistentTransaction.parentTxid,
            childTxids: persistentTransaction.childTxids
        )
    }

    // MARK: - Convert to PersistentTransaction

    func toPersistentTransaction() -> PersistentTransaction {
        return PersistentTransaction(
            txid: self.txid,
            movementId: self.movementId,
            recipientIndex: self.recipientIndex,
            type: self.type,
            amount: self.amount,
            date: self.date,
            status: self.status,
            address: self.address,
            notes: self.notes,
            fees: self.fees,
            subsystemCategory: self.subsystemCategory,
            subsystemName: self.subsystemName,
            subsystemKind: self.subsystemKind,
            paymentMethodType: self.paymentMethodType,
            paymentHash: self.paymentHash,
            onchainFeeSat: self.onchainFeeSat,
            fundingTxid: self.fundingTxid,
            inputVtxoIds: self.inputVtxoIds,
            outputVtxoIds: self.outputVtxoIds,
            exitedVtxoIds: self.exitedVtxoIds
        )
        // Note: Tag and contact assignments should be managed separately through services
        // to avoid complex relationship management during transaction creation
    }

    // MARK: - Linked-transaction fee/amount variants

    /// Net amount including fees from linked child transactions (for exits)
    /// - Parameter modelContext: SwiftData context to fetch linked transactions
    /// - Returns: Net amount including all fees
    func netAmountIncludingLinked(modelContext: ModelContext?) -> Int {
        // For sent and transfer transactions, add fees to get total amount that left the wallet
        if type == .sent || type == .transfer {
            return amount + totalFeesIncludingLinked(modelContext: modelContext)
        }
        // For received transactions, amount is what arrived (fees not relevant to user)
        return amount
    }

    /// Formatted net amount including linked transaction fees (for exits)
    /// - Parameter modelContext: SwiftData context to fetch linked transactions
    /// - Returns: Formatted net amount string
    func formattedNetAmountIncludingLinked(modelContext: ModelContext?) -> String {
        // For internal transfers, only show the fees (as negative)
        if isInternalTransfer {
            let feesToShow = totalFeesIncludingLinked(modelContext: modelContext)
            guard feesToShow > 0 else {
                return BitcoinFormatter.shared.formatAmount(0)
            }
            return BitcoinFormatter.shared.formatTransactionAmount(feesToShow, transactionType: .sent, isInternalTransfer: false)
        }

        return BitcoinFormatter.shared.formatTransactionAmount(netAmountIncludingLinked(modelContext: modelContext), transactionType: type, isInternalTransfer: isInternalTransfer)
    }

    /// Calculate total fees including fees from linked child transactions (for exits)
    /// - Parameter modelContext: SwiftData context to fetch linked transactions
    /// - Returns: Total fees including linked transaction fees
    func totalFeesIncludingLinked(modelContext: ModelContext?) -> Int {
        // Start with direct fees
        var total = totalFees

        // For exit transactions, add fees from linked onchain transactions.
        // userPaidOnchainFeeSat guards against fees the user didn't pay
        // (third-party spends of the exit's anyone-can-spend anchors).
        if subsystemName == "bark.exit", let childTxids = childTxids, !childTxids.isEmpty, let modelContext = modelContext {
            for childTxid in childTxids {
                let descriptor = FetchDescriptor<PersistentTransaction>(
                    predicate: #Predicate { $0.txid == childTxid }
                )

                if let childTx = try? modelContext.fetch(descriptor).first,
                   let childFee = childTx.userPaidOnchainFeeSat {
                    total += childFee
                }
            }
        }

        return total
    }

    /// Formatted total fees including linked transactions (for exits)
    /// - Parameter modelContext: SwiftData context to fetch linked transactions
    /// - Returns: Formatted fee string or nil if no fees
    func formattedTotalFeesIncludingLinked(modelContext: ModelContext?) -> String? {
        let total = totalFeesIncludingLinked(modelContext: modelContext)
        guard total > 0 else {
            return nil
        }
        return BitcoinFormatter.shared.formatAmount(total)
    }
}
