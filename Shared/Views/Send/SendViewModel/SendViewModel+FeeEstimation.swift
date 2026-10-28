//
//  SendViewModel+FeeEstimation.swift
//  Arké
//
//  Created by Assistant on 5/18/26.
//
//  Fee estimation for onchain Bitcoin transactions using BDK. One request
//  quotes every priority tier (2026-10-27), so a tier switch reads the
//  quote instead of asking again.
//

import Foundation
import OSLog
import ArkeUI

extension SendViewModel {

    // MARK: - Onchain Fee Estimation

    /// Quotes the onchain fee at every tier for the current address and
    /// amount, unless the current quote already covers them. Replies that
    /// arrive after a newer request started are dropped.
    @MainActor
    func estimateOnchainFee() async {
        guard let destination = selectedDestination else {
            logger.warning("No destination selected")
            return
        }

        // Paid from Payments: bark prices it, the shadow wallet has no say
        if isPaymentsOnchainSend {
            resetOnchainFeeQuote()
            await calculateOffboardFee()
            return
        }

        guard isSavingsOnchainSend else {
            logger.warning("Not an onchain destination")
            return
        }

        // Keep published rates fresh while the send screen stays open
        // (served from FeeRateService's cache when recent, so this is cheap).
        // The rates are part of the quote key, so a change re-quotes by itself.
        onchainFeeRates = await walletManager.currentFeeRates()

        guard let amountInt = Int(amount), amountInt > 0 else {
            logger.debug("No amount to quote for; clearing the onchain quote")
            resetOnchainFeeQuote()
            return
        }
        guard amountInt >= minimumSendAmount else {
            // Below dust BDK refuses to build (OutputBelowDustLimit); the row
            // shows the placeholder and the card shows the minimum
            logger.debug("Amount \(amountInt) under the minimum \(self.minimumSendAmount); not quoting")
            resetOnchainFeeQuote()
            return
        }

        if let quote = onchainFeeQuote,
           quote.matches(address: destination.address, amountSats: amountInt, rates: onchainFeeRates) {
            logger.debug("Onchain quote still current for \(amountInt) sats")
            return
        }

        // Own the newest generation (the debounce may already have claimed
        // one for this request; claiming again is harmless)
        onchainFeeRequestGeneration += 1
        let generation = onchainFeeRequestGeneration
        isEstimatingOnchainFee = true
        defer {
            if generation == onchainFeeRequestGeneration {
                isEstimatingOnchainFee = false
            }
        }

        let rates = onchainFeeRates
        logger.info("Quoting onchain fees for \(amountInt) sats at fast \(rates.fast) / medium \(rates.medium) / slow \(rates.slow) sat/vB")

        do {
            let result = try await walletManager.estimateOnchainFees(
                address: destination.address,
                amountSats: UInt64(amountInt),
                feeRates: rates
            )
            guard generation == onchainFeeRequestGeneration else {
                logger.debug("Dropping onchain quote from superseded request \(generation)")
                return
            }
            let tiers = result.mapValues { tier -> OnchainTierQuote in
                switch tier {
                case .fee(let fee):
                    return .fee(Int(clamping: fee))
                case .insufficientFunds:
                    return .unaffordable
                }
            }
            onchainFeeQuote = OnchainFeeQuote(
                address: destination.address,
                amountSats: amountInt,
                rates: rates,
                tiers: tiers
            )
            let summary = FeePriority.allCases.map { priority -> String in
                switch tiers[priority] {
                case .fee(let fee)?: return "\(priority.rawValue) \(fee)"
                case .unaffordable?: return "\(priority.rawValue) unaffordable"
                case nil: return "\(priority.rawValue) –"
                }
            }.joined(separator: ", ")
            logger.info("Onchain fees quoted for \(amountInt) sats: \(summary)")
        } catch {
            guard generation == onchainFeeRequestGeneration else { return }
            logger.error("Failed to quote onchain fees: \(error)")
            // The row falls back to the approximate placeholder, marked as
            // such; a quote for other inputs must not stand in for this one
            onchainFeeQuote = nil
        }
        rerankForTypedAmount()
    }

    /// Forgets the quote and every request still in flight for it: the
    /// debounce is cancelled, a reply from an open request is dropped by
    /// the generation check, and the row stops saying "estimating".
    /// Called on clear and when the amount is emptied.
    @MainActor
    func resetOnchainFeeQuote() {
        onchainFeeEstimationTask?.cancel()
        onchainFeeRequestGeneration += 1
        isEstimatingOnchainFee = false
        onchainFeeQuote = nil
    }

    /// Updates the onchain fee estimate with debouncing
    /// This should be called when the amount changes
    @MainActor
    func updateOnchainFeeEstimate() {
        // Cancel any pending estimation
        onchainFeeEstimationTask?.cancel()

        // Paid from Payments: bark's estimate, debounced the same way; the
        // BDK quote is dropped so a source switch never shows the old number
        if isPaymentsOnchainSend {
            resetOnchainFeeQuote()
            updateOffboardFeeEstimate()
            return
        }
        clearOffboardFee()

        // The row says "estimating" from the first keystroke, not from the
        // end of the debounce: in that half second the placeholder would
        // otherwise show and the Send gate would let it through (review F3,
        // 2026-10-27). The generation bump makes any older reply stale.
        if let destination = selectedDestination, isSavingsOnchainSend {
            if let amountInt = Int(amount), amountInt >= max(1, minimumSendAmount) {
                if !(onchainFeeQuote?.matches(address: destination.address, amountSats: amountInt, rates: onchainFeeRates) ?? false) {
                    onchainFeeRequestGeneration += 1
                    isEstimatingOnchainFee = true
                }
            } else {
                // Emptied or under the minimum: nothing to quote, and no
                // spinner while the debounce runs out
                resetOnchainFeeQuote()
                return
            }
        }

        // Schedule new estimation with delay
        onchainFeeEstimationTask = Task { @MainActor in
            // Wait for user to stop typing
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            // Perform estimation
            await estimateOnchainFee()
        }
    }

    /// Storage for the debounced estimation task
    private static var onchainFeeEstimationTaskStorage: [ObjectIdentifier: Task<Void, Never>] = [:]

    private var onchainFeeEstimationTask: Task<Void, Never>? {
        get {
            Self.onchainFeeEstimationTaskStorage[ObjectIdentifier(self)]
        }
        set {
            Self.onchainFeeEstimationTaskStorage[ObjectIdentifier(self)] = newValue
        }
    }
}
