//
//  SendViewModel+ComputedProperties.swift
//  Ark wallet prototype
//
//  Created by Assistant on 12/8/25.
//
//  Computed properties that derive state from core properties.
//  These are UI-facing helpers for displaying balances, fees, and state.
//

import SwiftUI
import ArkeUI
import Bark

extension SendViewModel {
    
    // MARK: - Amount Limits
    
    /// Returns the minimum send amount based on the destination format
    /// - For onchain (Bitcoin): 546 sats (dust limit)
    /// - For Ark: 1000 sats (placeholder - adjust based on actual requirements)
    /// - For Lightning: 1 sat (no meaningful minimum for Lightning)
    var minimumSendAmount: Int {
        guard let destination = selectedDestination else {
            // No destination selected, use conservative default
            return 0
        }
        
        switch destination.format {
        case .bitcoin, .silentPayments:
            // Bitcoin dust limit
            return 546
        case .ark:
            // Ark minimum (placeholder - adjust based on actual requirements)
            return 0
        case .lightning, .lightningInvoice, .lnurl, .bolt12:
            // Lightning has effectively no minimum
            return 0
        case .bip353, .bip21:
            // These are wrappers, default to conservative value
            return 0
        }
    }
    
    // MARK: - Network & Context
    
    /// Returns the current network configuration based on arkInfo
    var currentNetworkConfig: NetworkConfig {
        // Try to get the network from arkInfo
        guard let arkInfo = walletManager.arkInfo,
              let bitcoinNetwork = arkInfo.bitcoinNetwork else {
            // Fallback to networkConfig if available
            return walletManager.networkConfig ?? .signet
        }
        
        // Map BitcoinNetwork to NetworkConfig
        switch bitcoinNetwork {
        case .mainnet:
            return .mainnet
        case .testnet:
            return .testnet
        case .signet:
            return .signet
        case .regtest:
            // No predefined regtest config, use signet as fallback
            return .signet
        }
    }
    
    /// Creates payment context for destination selection with real Lightning fee estimation
    var paymentContext: PaymentDestinationSelector.PaymentContext {
        PaymentDestinationSelector.PaymentContext(
            arkBalance: walletManager.arkBalance?.spendableSat,
            bitcoinBalance: walletManager.onchainBalance?.spendableSat,
            networkConfig: currentNetworkConfig,
            userPreferences: .default,
            arkServerConnected: walletManager.isArkServerReachable,
            hasLightningCapability: true, // Ark servers always provide Lightning routing
            walletManager: walletManager
        )
    }
    
    // MARK: - Amount State
    
    /// Checks if the amount is locked (e.g., Lightning invoice with embedded amount)
    var isAmountLocked: Bool {
        guard let paymentRequest = currentPaymentRequest else { return false }
        guard let destination = selectedDestination else { return false }
        return destination.format == .lightningInvoice && paymentRequest.amount != nil
    }
    
    /// Reason why amount is locked
    var lockedAmountReason: String? {
        guard isAmountLocked else { return nil }
        return "set by Lightning invoice"
    }
    
    /// Returns the maximum spendable amount based on the selected destination
    var maxSpendableAmount: Int {
        guard let destination = selectedDestination else {
            // No destination selected, show total balance
            return walletManager.totalBalance?.totalSpendableSat ?? 0
        }
        
        // Use the selector to get available balance for this specific destination
        if let balance = PaymentDestinationSelector.availableBalance(for: destination, context: paymentContext) {
            return balance
        }
        
        return 0
    }
    
    /// Returns the appropriate balance text based on the selected destination
    var availableBalanceText: String {
        guard let destination = selectedDestination else {
            let formattedBalance = BitcoinFormatter.shared.formatAmount(walletManager.totalBalance?.totalSpendableSat ?? 0)
            return "Total balance: \(formattedBalance)"
        }
        
        let balanceSource = PaymentDestinationSelector.balanceSource(for: destination)
        let balance = maxSpendableAmount
        let formattedBalance = BitcoinFormatter.shared.formatAmount(balance)
        
        return "\(balanceSource.displayName): \(formattedBalance)"
    }
    
    /// Returns the balance source name based on the selected destination
    var availableBalanceName: String {
        guard let destination = selectedDestination else {
            return "Total balance"
        }
        
        let balanceSource = PaymentDestinationSelector.balanceSource(for: destination)
        return balanceSource.displayName
    }
    
    /// Returns the formatted balance amount based on the selected destination
    var availableBalanceAmount: String {
        let balance = maxSpendableAmount
        return BitcoinFormatter.shared.formatAmount(balance)
    }
    
    // MARK: - Fee Information

    /// Returns the estimated fee text for the selected destination
    var feeText: String? {
        guard let destination = selectedDestination else {
            return nil
        }
        
        let ranked = rankedDestinations.first { $0.destination.id == destination.id }
        return ranked?.estimatedFee.map { fee in
            fee > 0 ? BitcoinFormatter.shared.formatAmount(fee) : L10n.labelNoFee
        }
    }
    
    /// What the fee row shows for the selected destination. Onchain
    /// destinations distinguish a priced fee from the size-based placeholder
    /// and from an open request; the other formats show a fee or nothing.
    var feeDisplayState: FeeDisplayState {
        guard let destination = selectedDestination else {
            return .unavailable
        }

        if isOnchainDestination {
            let roughFee = PaymentDestinationSelector.estimateOnchainFee(
                for: destination,
                amount: Int(amount),
                feeRate: onchainFeeRates.rate(for: selectedFeePriority)
            )
            return OnchainFeeQuote.displayState(
                quote: onchainFeeQuote,
                address: destination.address,
                amountSats: Int(amount),
                rates: onchainFeeRates,
                priority: selectedFeePriority,
                isEstimating: isEstimatingOnchainFee,
                roughFee: roughFee
            )
        }

        // Lightning and Ark: the cached estimate or nothing, never a stale ranked fee
        if isLightningDestination {
            return cachedLightningFee.map(FeeDisplayState.value) ?? .unavailable
        }
        if isArkDestination {
            return cachedArkFee.map(FeeDisplayState.value) ?? .unavailable
        }

        // For other destinations, use the ranked fee estimate
        let ranked = rankedDestinations.first { $0.destination.id == destination.id }
        return ranked?.estimatedFee.map(FeeDisplayState.value) ?? .unavailable
    }

    /// The onchain quote when it covers the selected destination, this
    /// amount and the current rates; nil otherwise, so views never see a
    /// quote for other inputs
    func currentOnchainFeeQuote(amountSats: Int?) -> OnchainFeeQuote? {
        guard let destination = selectedDestination, isOnchainDestination,
              let amountSats,
              let quote = onchainFeeQuote,
              quote.matches(address: destination.address, amountSats: amountSats, rates: onchainFeeRates) else {
            return nil
        }
        return quote
    }

    /// The quote for the amount as entered, for the speed sheet
    var currentOnchainFeeQuote: OnchainFeeQuote? {
        currentOnchainFeeQuote(amountSats: Int(amount))
    }

    /// BDK's exact fee at the selected tier for the selected onchain
    /// destination and this amount, or nil when no current quote covers
    /// them. The pre-send balance check prefers this over the ranker's
    /// rough medium-tier placeholder.
    func exactOnchainFee(amountSats: Int) -> Int? {
        currentOnchainFeeQuote(amountSats: amountSats)?.fee(for: selectedFeePriority)
    }
    
    // MARK: - Destination State
    
    /// Returns the number of viable payment destinations
    var viableDestinationCount: Int {
        rankedDestinations.filter { $0.viable }.count
    }
    
    /// Returns whether multiple viable destinations are available
    var hasMultipleViableDestinations: Bool {
        viableDestinationCount > 1
    }
    
    /// Returns whether the selected destination is an on-chain format that supports fee selection
    var isOnchainDestination: Bool {
        guard let destination = selectedDestination else { return false }
        return destination.format == .bitcoin || destination.format == .silentPayments
    }
    
    /// Returns whether the selected destination is a Lightning-based format
    var isLightningDestination: Bool {
        guard let destination = selectedDestination else { return false }
        return destination.format == .lightning || destination.format == .lightningInvoice || destination.format == .lnurl || destination.format == .bolt12
    }
    
    /// Returns whether the selected destination is an Ark format
    var isArkDestination: Bool {
        guard let destination = selectedDestination else { return false }
        return destination.format == .ark
    }
    
    /// Why Send is disabled right now, nil when it may be tapped. The one
    /// gate for all three flows; see `SendBlocker`.
    var sendBlocker: SendBlocker? {
        SendBlocker.evaluate(
            amountSats: Int(amount),
            isAmountLocked: isAmountLocked,
            minimumSendAmount: minimumSendAmount,
            availableSats: maxSpendableAmount,
            feeState: feeDisplayState,
            isOnchain: isOnchainDestination,
            fastTierAtMainnetCeiling: fastTierAtMainnetCeiling
        )
    }

    /// The line under the Send button, when the blocker has one
    var sendBlockedReason: String? {
        sendBlocker?.reason
    }

    /// The live fast rate equals the mainnet sanity ceiling: a poisoned or
    /// broken estimator (`Features/Mainnet_Fee_Rate_Ceiling.md` §2); the
    /// clamp warning in `FeeRateService` fires on the same condition. Only
    /// mainnet: the signet cap is hit routinely under fee spam and is a
    /// different constant.
    var fastTierAtMainnetCeiling: Bool {
        currentNetworkConfig.isMainnet && onchainFeeRates.fast == FeeRateService.mainnetMaxRateSatPerVb
    }

    /// Returns whether to show the fee disclosure indicator: an onchain
    /// destination whose tiers differ in rate. When every tier is priced
    /// the same there is nothing to choose, so the row does not pretend
    /// (DECIDED 2026-10-27).
    var shouldShowFeeDisclosure: Bool {
        isOnchainDestination && FeeTierGroup.groups(from: onchainFeeRates).count > 1
    }
    
    // MARK: - Balance Loading State
    
    /// Whether balance data has been loaded from the wallet
    /// Returns false if balances are still loading or unavailable
    var hasBalanceLoaded: Bool {
        walletManager.arkBalance != nil && walletManager.onchainBalance != nil
    }
}
