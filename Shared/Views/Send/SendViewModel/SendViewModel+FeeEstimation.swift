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

        guard isOnchainDestination else {
            logger.warning("Not an onchain destination")
            return
        }

        // Keep published rates fresh while the send screen stays open
        // (served from FeeRateService's cache when recent, so this is cheap).
        // The rates are part of the quote key, so a change re-quotes by itself.
        onchainFeeRates = await walletManager.currentFeeRates()

        guard let amountInt = Int(amount), amountInt > 0 else {
            logger.debug("No amount to quote for; clearing the onchain quote")
            onchainFeeQuote = nil
            return
        }

        if let quote = onchainFeeQuote,
           quote.matches(address: destination.address, amountSats: amountInt, rates: onchainFeeRates) {
            logger.debug("Onchain quote still current for \(amountInt) sats")
            return
        }

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
            let fees = try await walletManager.estimateOnchainFees(
                address: destination.address,
                amountSats: UInt64(amountInt),
                feeRates: rates
            )
            guard generation == onchainFeeRequestGeneration else {
                logger.debug("Dropping onchain quote from superseded request \(generation)")
                return
            }
            onchainFeeQuote = OnchainFeeQuote(
                address: destination.address,
                amountSats: amountInt,
                rates: rates,
                fees: fees.mapValues { Int(clamping: $0) }
            )
            let summary = FeePriority.allCases
                .map { "\($0.rawValue) \(fees[$0].map(String.init) ?? "–")" }
                .joined(separator: ", ")
            logger.info("Onchain fees quoted for \(amountInt) sats: \(summary)")
        } catch {
            guard generation == onchainFeeRequestGeneration else { return }
            logger.error("Failed to quote onchain fees: \(error)")
            // The row falls back to the approximate placeholder, marked as
            // such; a quote for other inputs must not stand in for this one
            onchainFeeQuote = nil
        }
    }

    /// Updates the onchain fee estimate with debouncing
    /// This should be called when the amount changes
    @MainActor
    func updateOnchainFeeEstimate() {
        // Cancel any pending estimation
        onchainFeeEstimationTask?.cancel()

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
