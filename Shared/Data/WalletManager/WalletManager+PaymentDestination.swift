//
//  WalletManager+PaymentDestination.swift
//  Ark wallet prototype
//
//  Payment context helpers
//  Convenience methods for creating PaymentContext from current wallet state
//

import Foundation

// MARK: - Payment Context Helpers
extension WalletManager {
    
    /// Create a PaymentContext from current wallet state
    /// Used by PaymentDestinationSelector to determine optimal payment method
    func createPaymentContext(
        preferences: PaymentDestinationSelector.PaymentPreferences? = nil
    ) -> PaymentDestinationSelector.PaymentContext {
        PaymentDestinationSelector.PaymentContext(
            arkBalance: arkBalance?.spendableSat,
            bitcoinBalance: onchainBalance?.spendableSat,
            networkConfig: networkConfig ?? NetworkConfig.mainnet,
            userPreferences: preferences ?? .default,
            arkServerConnected: true, // TODO: Add actual server connectivity check
            hasLightningCapability: true, // TODO: Add actual Lightning capability check
            walletManager: self
        )
    }
}
