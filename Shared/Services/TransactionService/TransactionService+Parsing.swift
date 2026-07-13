//
//  TransactionService+Parsing.swift
//  Arke
//
//  Movement-to-transaction parsing logic.
//  Converts API movement data into transaction records.
//

import Foundation
import SwiftData
import ArkeUI
import os

// MARK: - TransactionService+Parsing

extension TransactionService {
    
    // MARK: Private Parsing Methods
    
    /// Parse movement using category-aware logic
    private func parseMovementWithCategory(
        _ movement: MovementData,
        category: MovementCategory,
        date: Date,
        status: TransactionStatusEnum
    ) -> [TransactionData] {
        
        // Handle self-transfer operations (boarding, exit, offboarding, refresh)
        if category == .boarding || category == .exit || category == .offboarding || category == .refresh {
            return parseTransferOperation(movement, category: category, date: date, status: status)
        }
        
        // Handle send operations
        if movement.subsystemKind == "send" || category == .lightningSend || category == .onchainSend {
            return parseSendOperation(movement, category: category, date: date, status: status)
        }
        
        // Handle receive operations
        if movement.subsystemKind == "receive" || category == .lightningReceive {
            return parseReceiveOperation(movement, category: category, date: date, status: status)
        }
        
        // Other operations (refresh, unknown)
        return parseOtherOperation(movement, category: category, date: date, status: status)
    }
    
    /// Parse send operations (send, lightning send, offboard, onchain send)
    private func parseSendOperation(
        _ movement: MovementData,
        category: MovementCategory,
        date: Date,
        status: TransactionStatusEnum
    ) -> [TransactionData] {
        
        let destinations = movement.destinations
        
        guard !destinations.isEmpty else {
            // No destinations - create single transaction with total amount
            return [createTransactionData(
                movement: movement,
                destination: nil,
                recipientIndex: nil,
                type: .sent,
                date: date,
                status: status,
                category: category
            )]
        }
        
        if destinations.count == 1 {
            // Single destination
            return [createTransactionData(
                movement: movement,
                destination: destinations[0],
                recipientIndex: nil,
                type: .sent,
                date: date,
                status: status,
                category: category
            )]
        } else {
            // Multiple destinations - we don't have per-destination amounts
            TransactionService.logger.warning("Movement \(movement.id) has \(destinations.count) destinations but no per-destination amounts. Destinations: \(destinations.map { $0.paymentMethod.displayType }.joined(separator: ", "))")
            
            // Create one transaction showing first destination
            return [createTransactionData(
                movement: movement,
                destination: destinations[0],
                recipientIndex: nil,
                type: .sent,
                date: date,
                status: status,
                category: category
            )]
        }
    }
    
    /// Parse receive operations (receive, lightning receive)
    private func parseReceiveOperation(
        _ movement: MovementData,
        category: MovementCategory,
        date: Date,
        status: TransactionStatusEnum
    ) -> [TransactionData] {
        
        let sources = movement.sources
        let source = sources.first  // May be nil
        
        return [createTransactionData(
            movement: movement,
            destination: source,
            recipientIndex: nil,
            type: .received,
            date: date,
            status: status,
            category: category
        )]
    }
    
    /// Parse transfer operations (boarding, exit, offboarding)
    /// These are self-transfers between the user's onchain and Ark accounts
    private func parseTransferOperation(
        _ movement: MovementData,
        category: MovementCategory,
        date: Date,
        status: TransactionStatusEnum
    ) -> [TransactionData] {
        
        let destinations = movement.destinations
        let destination = destinations.first  // May be nil for boarding (no destination address)
        
        return [createTransactionData(
            movement: movement,
            destination: destination,
            recipientIndex: nil,
            type: .transfer,
            date: date,
            status: status,
            category: category
        )]
    }
    
    /// Parse other operations (exit, refresh, etc.)
    private func parseOtherOperation(
        _ movement: MovementData,
        category: MovementCategory,
        date: Date,
        status: TransactionStatusEnum
    ) -> [TransactionData] {
        
        // Determine transaction type based on balance
        let type: TransactionTypeEnum
        if movement.effectiveBalanceSat < 0 {
            type = .sent
        } else if movement.effectiveBalanceSat > 0 {
            type = .received
        } else {
            // Zero balance (e.g., refresh) - treat as pending for now
            type = .pending
        }
        
        let destinations = movement.destinations
        let destination = destinations.first  // May be nil
        
        return [createTransactionData(
            movement: movement,
            destination: destination,
            recipientIndex: nil,
            type: type,
            date: date,
            status: status,
            category: category
        )]
    }
    
    /// Create a TransactionData object with all metadata
    private func createTransactionData(
        movement: MovementData,
        destination: MovementDestination?,
        recipientIndex: Int?,
        type: TransactionTypeEnum,
        date: Date,
        status: TransactionStatusEnum,
        category: MovementCategory
    ) -> TransactionData {
        
        let amount: Int
        let fees: Int?
        
        // Determine amount and fees based on type and category
        if type == .received {
            amount = Int(movement.effectiveBalanceSat)
            fees = nil  // Receiver doesn't pay offchain fees
        } else if type == .transfer {
            // For internal transfers (boarding, offboarding, exit, refresh),
            // use intendedBalanceSat to get the amount actually transferred,
            // separate from fees. This ensures UI can show "Moved X sats" with "Y sats fee"
            // Example: offboarding 10,000 sats with 265 sat fee
            //   - intendedBalanceSat = -10,000 (amount moved)
            //   - offchainFeeSat = 265 (fee paid)
            //   - effectiveBalanceSat = -10,265 (total impact on balance)
            amount = Int(abs(movement.intendedBalanceSat))
            fees = Int(movement.offchainFeeSat)
        } else {
            // For regular send operations (Lightning, Arkoor, Offboard),
            // use intendedBalanceSat for the amount and offchainFeeSat for fees.
            // This ensures the UI shows the correct intended send amount separate from fees.
            // Example: lightning send 250 sats with 20 sat fee
            //   - intendedBalanceSat = -250 (amount to send)
            //   - offchainFeeSat = 20 (fee paid)
            //   - effectiveBalanceSat = -270 (total deducted from balance)
            amount = Int(abs(movement.intendedBalanceSat))
            fees = Int(movement.offchainFeeSat)
        }
        
        return TransactionData(
            txid: "movement_\(movement.id)",
            movementId: movement.id,
            recipientIndex: recipientIndex,
            type: type,
            amount: amount,
            date: date,
            status: status,
            address: destination?.address,
            fees: fees,
            category: category,
            subsystemName: movement.subsystemName,
            subsystemKind: movement.subsystemKind,
            paymentMethod: destination?.paymentMethod,
            paymentHash: movement.paymentHash,
            paymentPreimage: movement.paymentPreimage,
            onchainFeeSat: movement.onchainFeeSat,
            fundingTxid: movement.fundingTxid,
            inputVtxoIds: movement.inputVtxoIds,
            outputVtxoIds: movement.outputVtxoIds,
            exitedVtxoIds: movement.exitedVtxoIds,
            lightningOffer: movement.lightningOffer
        )
    }
    
    /// Map movement status string to TransactionStatusEnum
    private func mapMovementStatus(_ status: String) -> TransactionStatusEnum {
        switch status.lowercased() {
        case "successful":
            return .confirmed
        case "pending":
            return .pending
        case "failed":
            return .failed
        // Bark serializes MovementStatus::Canceled as "canceled" (single l,
        // bark movement/mod.rs); "cancelled" kept as a safety net.
        case "canceled", "cancelled":
            return .cancelled
        default:
            TransactionService.logger.warning("Unknown movement status '\(status)', defaulting to pending")
            return .pending
        }
    }
    
    private func parseDate(_ dateString: String) -> Date {
        // Try ISO 8601 format first (new API format)
        // Example: "2025-12-05T11:17:01.044108+01:00"
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }
        
        // Fallback to old format for backward compatibility
        // Example: "2025-10-29 14:17:11.193"
        let legacyFormatter = DateFormatter()
        legacyFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        legacyFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        if let date = legacyFormatter.date(from: dateString) {
            return date
        }
        
        // If both fail, try without fractional seconds
        legacyFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = legacyFormatter.date(from: dateString) {
            return date
        }
        
        // Last resort fallback to current date
        TransactionService.logger.warning("Failed to parse date: \(dateString)")
        return Date()
    }
    
    /// Calculate proportional fee allocation for multi-destination transactions
    /// - Parameters:
    ///   - totalFees: Total fees for the movement
    ///   - recipientAmount: Amount for this specific destination
    ///   - totalAmount: Total amount sent across all destinations
    ///   - recipientIndex: Index of this destination (for rounding adjustments)
    ///   - totalRecipients: Total number of destinations
    /// - Returns: Proportionally allocated fee for this destination
    private func calculateProportionalFee(
        totalFees: Int,
        recipientAmount: Int,
        totalAmount: Int,
        recipientIndex: Int,
        totalRecipients: Int
    ) -> Int {
        guard totalAmount > 0, totalRecipients > 0 else {
            return 0
        }
        
        // Calculate proportion of total amount
        let proportion = Double(recipientAmount) / Double(totalAmount)
        let proportionalFee = Int(round(Double(totalFees) * proportion))
        
        return proportionalFee
    }
    
    // MARK: Public Methods
    
    func parseMovementToTransactions(_ movement: MovementData) async -> [TransactionData] {
        let parsedDate = parseDate(movement.completedAt ?? movement.createdAt)
        let status = mapMovementStatus(movement.status)
        let category = movement.category
        
        // Use category-aware parsing
        return parseMovementWithCategory(
            movement,
            category: category,
            date: parsedDate,
            status: status
        )
    }
}
