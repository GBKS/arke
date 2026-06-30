//
//  SendViewModel+PendingMetadata.swift
//  Arke
//
//  Created for Phase 1: Send Metadata Enhancement
//  Handles creation of pending metadata during payment execution
//

import Foundation
import ArkeUI
import SwiftData
import Bark
import OSLog

extension SendViewModel {
    
    // MARK: - Pending Metadata Creation
    
    /// Creates pending metadata for the current send operation
    /// This metadata will be matched to the transaction when the server movement arrives
    func createPendingMetadata(
        paymentHash: String?,
        destination: String,
        amount: Int,
        paymentType: String
    ) {
        logger.debug("📝 Creating pending metadata:")
        logger.debug("   → Payment type: \(paymentType)")
        logger.debug("   → Destination: \(destination)")
        logger.debug("   → Amount: \(amount) sats")
        logger.debug("   → Payment hash: \(paymentHash ?? "none")")
        
        // Create the pending metadata object
        let metadata = PendingPaymentMetadata(
            paymentHash: paymentHash,
            destinationAddress: destination,
            amountSats: amount,
            paymentType: paymentType,
            timestamp: Date()
        )
        
        // Insert into SwiftData
        modelContext.insert(metadata)
        
        // Save the reference for potential UI integration (Phase 3)
        self.pendingMetadata = metadata
        
        // Persist to database
        do {
            try modelContext.save()
            logger.debug("✅ Pending metadata saved to database")
        } catch {
            logger.error("❌ Failed to save pending metadata: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Payment Hash Extraction
    
    /// Extracts payment hash from Lightning payment status
    /// Returns nil for non-Lightning payments or if hash is unavailable
    /// Note: Payment hash is only available in the .paid case
    func extractPaymentHash(from status: LightningSendStatus) -> String? {
        switch status {
        case .paid(let paymentHash, _):
            return paymentHash
        case .inProgress:
            // Payment hash not available in inProgress case
            // Will be matched via timestamp + amount + address
            return nil
        case .unknown:
            return nil
        }
    }
    
    // MARK: - Payment Type Detection
    
    /// Determines the payment type string from destination format
    /// Used for logging and debugging in pending metadata
    func paymentType(for format: AddressFormat) -> String {
        switch format {
        case .bitcoin, .silentPayments:
            return "onchain"
        case .lightningInvoice, .lightning, .lnurl, .bolt12:
            return "lightning"
        case .ark, .bip353:
            return "ark"
        case .bip21:
            return "bip21"  // Should be resolved before payment
        }
    }
    
    // MARK: - Helper: Update Pending Metadata with Payment Hash
    
    /// Updates the pending metadata with a payment hash after payment completes
    /// This is useful for Lightning payments where the hash is only available after the payment is made
    func updatePendingMetadataWithPaymentHash(_ paymentHash: String) {
        guard let metadata = pendingMetadata else {
            logger.warning("⚠️ No pending metadata to update with payment hash")
            return
        }
        
        logger.debug("🔄 Updating pending metadata with payment hash: \(String(paymentHash.prefix(16)))...")
        metadata.paymentHash = paymentHash
        
        do {
            try modelContext.save()
            logger.debug("✅ Pending metadata updated with payment hash")
        } catch {
            logger.error("❌ Failed to update pending metadata: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Note Pre-population
    
    /// Extracts descriptive text from the payment request to pre-populate the note field.
    /// Draws from (in priority order) BIP-21 label/message, the BOLT-11 invoice description,
    /// and the LNURL-pay metadata description.
    func extractPaymentNote() -> String? {
        switch sendMode {
        case .quick(let request, _):
            // 1. BIP-21 label/message (joined, as before)
            var parts: [String] = []
            if let label = request.label, !label.isEmpty {
                parts.append(label)
            }
            if let message = request.message, !message.isEmpty {
                parts.append(message)
            }
            if !parts.isEmpty {
                return parts.joined(separator: " - ")
            }

            // 2. BOLT-11 Lightning invoice description
            if request.primaryFormat == .lightningInvoice,
               let invoice = request.primaryDestination?.address {
                let (_, description) = LightningInvoiceParser.extractAmountAndDescription(
                    fromInvoice: invoice
                )
                if let description = description, !description.isEmpty {
                    return description
                }
            }

            // 3. LNURL-pay metadata description (only if already resolved)
            if let descriptionText = resolvedLNURL?.descriptionText, !descriptionText.isEmpty {
                return descriptionText
            }

            return nil

        default:
            return nil
        }
    }
    
    /// Pre-populates the note field in pending metadata if payment request has descriptive text
    func prepopulateNoteIfNeeded() {
        guard let metadata = pendingMetadata else { return }
        
        // Only pre-populate if note is currently empty
        guard metadata.notes == nil || metadata.notes?.isEmpty == true else {
            logger.debug("📝 Note already set, skipping pre-population")
            return
        }
        
        if let extractedNote = extractPaymentNote() {
            logger.debug("📝 Pre-populating note from payment request: \(extractedNote)")
            metadata.notes = extractedNote
            
            do {
                try modelContext.save()
                logger.debug("✅ Note pre-populated successfully")
            } catch {
                logger.error("❌ Failed to save pre-populated note: \(error.localizedDescription)")
            }
        }
    }
}
