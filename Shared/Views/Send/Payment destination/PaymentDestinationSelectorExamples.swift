//
//  PaymentDestinationSelectorExamples.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/17/25.
//

import Foundation

/// Examples of how to use PaymentDestinationSelector in your app

// MARK: - Example 1: Basic Payment Selection

func exampleBasicSelection() async {
    // User scans a BIP-21 QR code with multiple payment options
    let bip21URI = "bitcoin:tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx?amount=0.001&ark=tark1qxyzexample&lightning=lntb100n1example"
    
    // Parse the payment request
    guard let paymentRequest = AddressValidator.parsePaymentRequest(bip21URI) else {
        print("Invalid payment request")
        return
    }
    
    print("Payment request has \(paymentRequest.destinations.count) destinations:")
    for destination in paymentRequest.destinations {
        print("  - \(destination.format.displayName)")
    }
    
    // Create context with current wallet state
    let context = PaymentDestinationSelector.PaymentContext(
        arkBalance: 500_000,      // 500k sats in Ark
        bitcoinBalance: 1_000_000, // 1M sats on-chain
        networkConfig: NetworkConfig.signet
    )
    
    // Select optimal destination
    if let optimal = await paymentRequest.selectOptimalDestination(context: context) {
        print("\nOptimal payment method: \(optimal.format.displayName)")
        print("Address: \(optimal.shortAddress)")
        
        let balanceSource = PaymentDestinationSelector.balanceSource(for: optimal)
        print("Will use: \(balanceSource.displayName)")
    } else {
        print("\nNo viable payment method found")
    }
}

// MARK: - Example 2: Showing All Options to User

func exampleShowAllOptions() async {
    let bip21URI = "bitcoin:tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx?amount=0.001&ark=tark1qxyzexample"
    
    guard let paymentRequest = AddressValidator.parsePaymentRequest(bip21URI) else {
        return
    }
    
    let context = PaymentDestinationSelector.PaymentContext(
        arkBalance: 500_000,
        bitcoinBalance: 1_000_000,
        networkConfig: NetworkConfig.signet
    )
    
    // Get all destinations ranked by preference
    let ranked = await paymentRequest.rankedDestinations(context: context)
    
    print("Payment options (ranked):")
    for (index, option) in ranked.enumerated() {
        let icon = option.viable ? "✓" : "✗"
        print("\n\(icon) Option \(index + 1): \(option.destination.format.displayName)")
        print("  Balance Source: \(option.balanceSource.displayName)")
        print("  Available: \(option.availableBalance ?? 0) sats")
        print("  Estimated Fee: ~\(option.estimatedFee ?? 0) sats")
        print("  Status: \(option.reason)")
        
        if index == 0 && option.viable {
            print("  ⭐ RECOMMENDED")
        }
    }
}

// MARK: - Example 3: Handling Insufficient Ark Balance

func exampleInsufficientArkBalance() async {
    // Large payment that exceeds Ark balance
    let bip21URI = "bitcoin:tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx?amount=0.008&ark=tark1qxyzexample&lightning=lntb800000n1example"
    
    guard let paymentRequest = AddressValidator.parsePaymentRequest(bip21URI) else {
        return
    }
    
    let context = PaymentDestinationSelector.PaymentContext(
        arkBalance: 300_000,      // Only 300k sats in Ark
        bitcoinBalance: 1_000_000, // 1M sats on-chain (sufficient)
        networkConfig: NetworkConfig.signet
    )
    
    print("Payment amount: \(paymentRequest.amount ?? 0) sats")
    print("Ark balance: 300,000 sats (insufficient)")
    print("Bitcoin balance: 1,000,000 sats (sufficient)")
    
    if let optimal = await paymentRequest.selectOptimalDestination(context: context) {
        print("\nAutomatic fallback to: \(optimal.format.displayName)")
        print("This will use your Bitcoin on-chain balance")
    }
}

// MARK: - Example 4: Server Connectivity Issues

func exampleServerOffline() async {
    let bip21URI = "bitcoin:tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx?amount=0.001&lightning=lntb100n1example"
    
    guard let paymentRequest = AddressValidator.parsePaymentRequest(bip21URI) else {
        return
    }
    
    // Ark server is offline
    let context = PaymentDestinationSelector.PaymentContext(
        arkBalance: 500_000,
        bitcoinBalance: 1_000_000,
        networkConfig: NetworkConfig.signet,
        arkServerConnected: false // Server offline!
    )
    
    let ranked = await paymentRequest.rankedDestinations(context: context)
    
    print("Ark server is offline")
    print("\nPayment options:")
    for option in ranked {
        if option.requiresServerRouting {
            print("✗ \(option.destination.format.displayName) - \(option.reason)")
        } else if option.viable {
            print("✓ \(option.destination.format.displayName) - Available")
        }
    }
}

// MARK: - Example 5: Custom User Preferences

func exampleCustomPreferences() async {
    let bip21URI = "bitcoin:tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx?amount=0.001&ark=tark1qxyzexample"
    
    guard let paymentRequest = AddressValidator.parsePaymentRequest(bip21URI) else {
        return
    }
    
    // User prefers on-chain Bitcoin for all payments
    let customPreferences = PaymentDestinationSelector.PaymentPreferences(
        priorityOrder: [.bitcoin, .ark, .lightning],
        preferOnChainForLargeAmounts: true,
        largeAmountThreshold: 500_000, // 500k sats
        minimumArkReserve: 50_000      // Keep 50k sats in Ark
    )
    
    let context = PaymentDestinationSelector.PaymentContext(
        arkBalance: 500_000,
        bitcoinBalance: 1_000_000,
        networkConfig: NetworkConfig.signet,
        userPreferences: customPreferences
    )
    
    if let optimal = await paymentRequest.selectOptimalDestination(context: context) {
        print("With custom preferences, selected: \(optimal.format.displayName)")
    }
}

// MARK: - Example 6: Large Payment Optimization

func exampleLargePayment() async {
    // Very large payment
    let bip21URI = "bitcoin:tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx?amount=0.02&ark=tark1qxyzexample"
    
    guard let paymentRequest = AddressValidator.parsePaymentRequest(bip21URI) else {
        return
    }
    
    // User has preference for on-chain settlements for large amounts
    let preferences = PaymentDestinationSelector.PaymentPreferences(
        preferOnChainForLargeAmounts: true,
        largeAmountThreshold: 1_000_000 // 1M sats threshold
    )
    
    let context = PaymentDestinationSelector.PaymentContext(
        arkBalance: 3_000_000,      // Sufficient Ark balance
        bitcoinBalance: 3_000_000,   // Sufficient Bitcoin balance
        networkConfig: NetworkConfig.signet,
        userPreferences: preferences
    )
    
    print("Payment amount: \(paymentRequest.amount ?? 0) sats (large payment)")
    print("Large amount threshold: 1,000,000 sats")
    
    if let optimal = await paymentRequest.selectOptimalDestination(context: context) {
        print("\nSelected: \(optimal.format.displayName)")
        print("Reason: For large amounts, on-chain settlement provides better security")
    }
}

// MARK: - Example 7: Viability Report for Debugging

func exampleViabilityReport() async {
    let bip21URI = "bitcoin:tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx?amount=0.006&ark=tark1qxyzexample&lightning=lntb600000n1example"
    
    guard let paymentRequest = AddressValidator.parsePaymentRequest(bip21URI) else {
        return
    }
    
    let context = PaymentDestinationSelector.PaymentContext(
        arkBalance: 500_000,      // Insufficient
        bitcoinBalance: 400_000,   // Also insufficient
        networkConfig: NetworkConfig.signet
    )
    
    // Get detailed viability report
    let report = await PaymentDestinationSelector.viabilityReport(from: paymentRequest, context: context)
    print(report)
    
    // This would output something like:
    // Payment Destination Analysis:
    // Amount: 600000 sats
    // Ark Balance: 500000 sats
    // Bitcoin Balance: 400000 sats
    //
    // Destinations:
    //
    // 1. Ark
    //    Address: tark1qxy...example
    //    Balance Source: Ark Balance
    //    Available: 500000 sats
    //    Estimated Fee: 0 sats
    //    Viable: ✗
    //    Reason: Insufficient balance (500000 < 600000 sats)
    //    Priority: #1
    // ...
}

// MARK: - Example 8: Integration with SendView

func exampleIntegrationWithSendView() async {
    // This would be called when user pastes/scans an address in SendView
    
    func handleScannedPaymentRequest(_ input: String, walletManager: WalletManager) async {
        guard let paymentRequest = AddressValidator.parsePaymentRequest(input) else {
            // Show error: Invalid address
            return
        }
        
        // Create context from wallet state (manual approach)
        let context = PaymentDestinationSelector.PaymentContext(
            arkBalance: walletManager.arkBalance?.spendableSat,
            bitcoinBalance: walletManager.onchainBalance?.spendableSat,
            networkConfig: walletManager.networkConfig ?? NetworkConfig.signet
        )
        
        // Check if payment is possible
        let (feasible, _) = await PaymentDestinationSelector.canFulfillPayment(
            paymentRequest,
            with: context
        )
        
        if !feasible {
            // Show error: Insufficient balance for all payment methods
            return
        }
        
        // Get all viable options
        let ranked = await paymentRequest.rankedDestinations(context: context)
        let viableOptions = ranked.filter { $0.viable }
        
        if viableOptions.count == 1 {
            // Only one option, use it automatically
            let _ = viableOptions[0].destination
            // Proceed with payment
        } else {
            // Multiple options, let user choose
            // Show picker with:
            // - Recommended option first (with ⭐)
            // - Other viable options
            // - Show estimated fees and balance sources
        }
    }
}

// MARK: - Example 9: Checking Individual Destination Viability

func exampleCheckIndividualViability() async {
    let arkDestination = PaymentDestination(
        format: .ark,
        network: .signet,
        address: "tark1qxyzexample"
    )
    
    let context = PaymentDestinationSelector.PaymentContext(
        arkBalance: 500_000,
        bitcoinBalance: 1_000_000,
        networkConfig: NetworkConfig.signet
    )
    
    // Check if this specific destination is viable for 600k sats
    let isViable = await PaymentDestinationSelector.isViable(
        destination: arkDestination,
        amount: 600_000,
        context: context
    )
    
    if isViable {
        print("Can pay 600k sats via Ark")
    } else {
        print("Cannot pay 600k sats via Ark (insufficient balance)")
    }
}

// MARK: - Example 10: Reserve Balance Protection

func exampleReserveProtection() async {
    let paymentRequest = PaymentRequest(
        destinations: [
            PaymentDestination(format: .ark, network: .signet, address: "tark1qxyz"),
            PaymentDestination(format: .bitcoin, network: .signet, address: "tb1qxyz")
        ],
        amount: 495_000, // Would leave only 5k sats
        originalString: "bitcoin:tb1qxyz?ark=tark1qxyz&amount=0.00495"
    )
    
    // User wants to keep minimum 10k sats in Ark
    let preferences = PaymentDestinationSelector.PaymentPreferences(
        minimumArkReserve: 10_000
    )
    
    let context = PaymentDestinationSelector.PaymentContext(
        arkBalance: 500_000,
        bitcoinBalance: 1_000_000,
        networkConfig: NetworkConfig.signet,
        userPreferences: preferences
    )
    
    if let optimal = await paymentRequest.selectOptimalDestination(context: context) {
        print("Selected: \(optimal.format.displayName)")
        
        if optimal.format == .bitcoin {
            print("Using Bitcoin to preserve your Ark reserve balance")
        }
    }
}
