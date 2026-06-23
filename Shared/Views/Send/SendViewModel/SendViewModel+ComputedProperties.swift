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
            arkServerConnected: true, // TODO: Get from manager
            hasLightningCapability: true, // TODO: Get from manager
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
            fee > 0 ? BitcoinFormatter.shared.formatAmount(fee) : String(localized: "label_no_fee")
        }
    }
    
    /// Returns the estimated fee amount (in satoshis) for the selected destination
    var feeAmount: Int? {
        guard let destination = selectedDestination else {
            return nil
        }
        
        // For on-chain destinations, use cached BDK fee if available
        if isOnchainDestination {
            // Use cached BDK fee if we have one
            if let cached = cachedOnchainFee {
                return cached
            }
            
            // Fallback to static estimate while calculating
            let feeRate = onchainFeeRates.rate(for: selectedFeePriority)
            let amountInt = Int(amount)
            return PaymentDestinationSelector.estimateOnchainFee(
                for: destination,
                amount: amountInt,
                feeRate: feeRate
            )
        }
        
        // For Lightning destinations, use the cached fee if available
        if isLightningDestination {
            if let cached = cachedLightningFee {
                return cached
            }
            // No cached fee and no valid amount - return nil instead of stale ranked fee
            return nil
        }
        
        // For Ark destinations, use the cached fee if available
        if isArkDestination {
            if let cached = cachedArkFee {
                return cached
            }
            // No cached fee and no valid amount - return nil instead of stale ranked fee
            return nil
        }
        
        // For other destinations, use the ranked fee estimate
        let ranked = rankedDestinations.first { $0.destination.id == destination.id }
        return ranked?.estimatedFee
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
    
    /// Returns whether to show the fee disclosure indicator
    var shouldShowFeeDisclosure: Bool {
        return isOnchainDestination
    }
    
    // MARK: - Balance Loading State
    
    /// Whether balance data has been loaded from the wallet
    /// Returns false if balances are still loading or unavailable
    var hasBalanceLoaded: Bool {
        walletManager.arkBalance != nil && walletManager.onchainBalance != nil
    }
}
