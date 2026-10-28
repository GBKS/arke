//
//  PaymentDestinationSelector.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/17/25.
//

import Foundation
import Bark
import OSLog
import ArkeUI

/// Selects the optimal payment destination based on balances, fees, and user preferences
class PaymentDestinationSelector {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "PaymentDestinationSelector")
    
    // MARK: - Context
    
    /// Context information needed to make payment destination decisions
    ///
    /// **Lifetime Expectations:**
    /// - `PaymentContext` instances should be **short-lived** and created on-demand
    /// - Typically used for a single ranking/fee estimation operation
    /// - Not intended to be stored long-term in view models or other objects
    ///
    /// **Weak WalletManager Reference:**
    /// - The `walletManager` property uses a `weak` reference to avoid retain cycles
    /// - Fee estimation gracefully degrades to static estimates if `walletManager` becomes nil
    /// - In normal usage, the parent object (e.g., SendViewModel) holds a strong reference to WalletManager
    /// - The weak reference is safe because async operations complete quickly (< 1 second typically)
    ///
    /// **Usage Pattern:**
    /// ```swift
    /// // Good: Create context on-demand via computed property
    /// var paymentContext: PaymentContext {
    ///     PaymentContext(
    ///         arkBalance: walletManager.arkBalance?.spendableSat,
    ///         bitcoinBalance: walletManager.onchainBalance?.spendableSat,
    ///         networkConfig: currentNetworkConfig,
    ///         walletManager: walletManager  // Parent holds strong reference
    ///     )
    /// }
    /// let ranked = await PaymentDestinationSelector.rankDestinations(from: request, context: paymentContext)
    ///
    /// // Bad: Don't store context long-term
    /// let storedContext = paymentContext  // ❌ Avoid storing for extended periods
    /// ```
    struct PaymentContext {
        /// Ark balance in satoshis - used for both Ark and Lightning payments
        let arkBalance: Int?
        
        /// On-chain Bitcoin balance in satoshis
        let bitcoinBalance: Int?
        
        /// Current network configuration
        let networkConfig: NetworkConfig
        
        /// User's payment preferences
        let userPreferences: PaymentPreferences
        
        /// Whether the Ark server is currently reachable
        let arkServerConnected: Bool
        
        /// Whether the Ark server supports Lightning payments for this user
        let hasLightningCapability: Bool
        
        /// Optional WalletManager for real-time fee estimation
        ///
        /// **Why weak?**
        /// - Avoids retain cycles if context is accidentally stored
        /// - Fee estimation gracefully falls back to static estimates if nil
        /// - Safe in practice because contexts are short-lived and parent objects hold strong references
        ///
        /// **Behavior if nil:**
        /// - `estimateFee()` will use static fallback estimates (20 sats for Lightning, 500 for Bitcoin, etc.)
        /// - No crash or error - degraded accuracy only
        weak var walletManager: WalletManager?
        
        init(
            arkBalance: Int?,
            bitcoinBalance: Int?,
            networkConfig: NetworkConfig,
            userPreferences: PaymentPreferences = .default,
            arkServerConnected: Bool = true,
            hasLightningCapability: Bool = true,
            walletManager: WalletManager? = nil
        ) {
            self.arkBalance = arkBalance
            self.bitcoinBalance = bitcoinBalance
            self.networkConfig = networkConfig
            self.userPreferences = userPreferences
            self.arkServerConnected = arkServerConnected
            self.hasLightningCapability = hasLightningCapability
            self.walletManager = walletManager
        }
    }
    
    // MARK: - Preferences
    
    /// User preferences for payment destination selection
    struct PaymentPreferences {
        /// Default priority order optimized for lowest fees
        static let defaultPriority: [AddressFormat] = [
            .ark,              // Same server, instant, typically free
            .lightning,        // Fast, low fees (via Ark server using arkBalance)
            .lightningInvoice, // Fast, low fees (via Ark server using arkBalance)
            .lnurl,            // LNURL-pay resolves to Lightning invoice
            .bolt12,           // BOLT12 offers
            .silentPayments,   // On-chain with privacy
            .bitcoin,          // Standard on-chain
            .bip353,           // Resolves to another format
        ]
        
        /// Default preferences instance
        static let `default` = PaymentPreferences()
        
        /// Priority order for payment formats (first = highest priority)
        var priorityOrder: [AddressFormat]
        
        /// Prefer on-chain Bitcoin for large amounts even if other options available
        var preferOnChainForLargeAmounts: Bool
        
        /// Threshold in satoshis above which to prefer on-chain (if enabled)
        var largeAmountThreshold: Int
        
        /// Minimum Ark balance to keep in reserve (won't use if it would drain below this)
        var minimumArkReserve: Int
        
        init(
            priorityOrder: [AddressFormat] = defaultPriority,
            preferOnChainForLargeAmounts: Bool = false,
            largeAmountThreshold: Int = 1_000_000, // 1M sats = 0.01 BTC
            minimumArkReserve: Int = 10_000 // 10k sats reserve
        ) {
            self.priorityOrder = priorityOrder
            self.preferOnChainForLargeAmounts = preferOnChainForLargeAmounts
            self.largeAmountThreshold = largeAmountThreshold
            self.minimumArkReserve = minimumArkReserve
        }
    }
    
    // MARK: - Balance Source
    
    /// Indicates which balance would be used for a payment
    nonisolated enum BalanceSource: Hashable, Sendable {
        case ark           // Direct Ark-to-Ark transfer using arkBalance
        case arkViaServer  // Lightning payment routed through Ark server using arkBalance
        case bitcoin       // On-chain Bitcoin payment using bitcoinBalance
        /// Bitcoin address paid from the Payments balance: bark splits an
        /// exact VTXO and the server builds the offboard transaction
        /// (`Features/Send_Onchain_From_Payments.md` §2). Server fee rate,
        /// no speed choice, confirms onchain like any Bitcoin payment.
        case arkToOnchain

        var displayName: String {
            switch self {
            case .ark:
                return "Payments Balance"
            case .arkViaServer:
                return "Payments Balance"
            case .bitcoin:
                return "Savings Balance"
            case .arkToOnchain:
                return "Payments Balance"
            }
        }

        var networkName: String {
            switch self {
            case .ark:
                return "Ark Network"
            case .arkViaServer:
                return "Lightning Network"
            case .bitcoin:
                return "Bitcoin Network"
            case .arkToOnchain:
                return "Bitcoin Network"
            }
        }

        /// The balance alone, as the picker rows and the collapsed row name
        /// it (DECIDED 2026-10-28: the currency is always bitcoin, so no
        /// "(Bitcoin)"; the rail is a caption only where rows need telling apart)
        var shortName: String {
            switch self {
            case .ark, .arkViaServer, .arkToOnchain:
                return String(localized: "funding_source_payments", defaultValue: "Payments")
            case .bitcoin:
                return String(localized: "funding_source_savings", defaultValue: "Savings")
            }
        }

        /// The rail the balance leaves on; shown only when two rows share a balance
        var railName: String {
            switch self {
            case .ark:
                return String(localized: "rail_ark", defaultValue: "Ark")
            case .arkViaServer:
                return String(localized: "rail_lightning", defaultValue: "Lightning")
            case .bitcoin, .arkToOnchain:
                return String(localized: "rail_onchain", defaultValue: "onchain")
            }
        }

        /// The payment needs the Ark server on the line
        var needsArkServer: Bool {
            self == .arkViaServer || self == .arkToOnchain
        }

        /// Spends the Payments (offchain) balance
        var spendsArkBalance: Bool {
            self != .bitcoin
        }
    }

    /// One selectable row in the send flow: a destination paid from one
    /// balance. A bitcoin address yields two choices, so the destination id
    /// alone no longer identifies a selection.
    nonisolated struct Choice: Hashable, Sendable {
        let destinationId: UUID
        let source: BalanceSource
    }

    // MARK: - Ranked Destination

    /// A payment destination with ranking and viability information
    struct RankedDestination {
        let destination: PaymentDestination
        let balanceSource: BalanceSource
        let availableBalance: Int?
        let estimatedFee: Int?
        let viable: Bool
        let reason: String
        let priority: Int // Lower number = higher priority

        var requiresServerRouting: Bool {
            balanceSource == .arkViaServer
        }

        var choice: Choice {
            Choice(destinationId: destination.id, source: balanceSource)
        }
    }
    
    // MARK: - Main Selection Methods
    
    /// Selects the optimal payment destination from a payment request
    /// Returns nil if no destinations are viable
    static func selectOptimalDestination(
        from paymentRequest: PaymentRequest,
        context: PaymentContext
    ) async -> PaymentDestination? {
        let ranked = await rankDestinations(from: paymentRequest, context: context)
        return ranked.first(where: { $0.viable })?.destination
    }
    
    /// Ranks all destinations in a payment request by preference and viability
    /// Returns array ordered by priority (best first)
    /// Uses real fee estimates when available for accurate ranking
    static func rankDestinations(
        from paymentRequest: PaymentRequest,
        context: PaymentContext
    ) async -> [RankedDestination] {
        // Filter destinations to match network
        let networkCompatibleDestinations = paymentRequest.destinations.filter { destination in
            destination.isCompatible(with: context.networkConfig)
        }
        
        // Rank each destination from every balance that can pay it
        var rankedDestinations: [RankedDestination] = []
        for destination in networkCompatibleDestinations {
            rankedDestinations.append(contentsOf: await rankDestinations(
                destination,
                amount: paymentRequest.amount,
                context: context
            ))
        }

        return oneRowPerBalance(sorted(rankedDestinations))
    }

    /// Re-ranks the request with the amount as typed, reusing fees the send
    /// flow already holds (`knownFees`, keyed by choice) and estimating
    /// nothing else: entries without a known fee are judged by the amount
    /// alone until their own estimator reports (DECIDED rule 3, 2026-10-10:
    /// viability follows the typed amount; the selection never moves).
    static func rerankDestinations(
        from paymentRequest: PaymentRequest,
        amount: Int?,
        context: PaymentContext,
        knownFees: [Choice: Int]
    ) -> [RankedDestination] {
        var rankedDestinations: [RankedDestination] = []
        for destination in paymentRequest.destinations where destination.isCompatible(with: context.networkConfig) {
            for source in balanceSources(for: destination) {
                let choice = Choice(destinationId: destination.id, source: source)
                rankedDestinations.append(rank(
                    destination,
                    source: source,
                    amount: amount,
                    context: context,
                    estimatedFee: knownFees[choice]
                ))
            }
        }
        return oneRowPerBalance(sorted(rankedDestinations))
    }

    /// "Pay from" offers each balance once (DECIDED 2026-10-28, §9.1 of
    /// `Features/Send_Onchain_From_Payments.md`). Within a balance the
    /// best-ranked row wins: a request that lets Payments reach the payee
    /// directly (Ark, then Lightning) makes the Payments-onchain twin of its
    /// bitcoin address a dominated path, same balance with a fee and a
    /// confirmation wait. Rows on the kept row's own rail stay, since they
    /// are different addresses rather than different paths (a contact with
    /// two bitcoin addresses). Input must already be sorted.
    static func oneRowPerBalance(_ sorted: [RankedDestination]) -> [RankedDestination] {
        var keptRail: [String: String] = [:]
        return sorted.filter { row in
            let balance = row.balanceSource.shortName
            if let rail = keptRail[balance] {
                return rail == row.balanceSource.railName
            }
            keptRail[balance] = row.balanceSource.railName
            return true
        }
    }

    /// The row to start on: the first viable row whose balance holds
    /// anything, else the first viable row. Without an amount every row is
    /// viable, so without this an empty Savings balance would still be the
    /// default for a bitcoin address and the user would type an amount into
    /// a source that cannot pay (DECIDED rule 1 reads "when both are
    /// viable"; an empty balance is not). This is the one load-time pick;
    /// nothing moves the selection afterwards.
    static func initialPick(in ranked: [RankedDestination]) -> RankedDestination? {
        ranked.first { $0.viable && ($0.availableBalance ?? 0) > 0 } ?? ranked.first { $0.viable }
    }

    /// Viable entries first, then by priority number
    private static func sorted(_ ranked: [RankedDestination]) -> [RankedDestination] {
        ranked.sorted { lhs, rhs in
            if lhs.viable != rhs.viable {
                return lhs.viable // Viable destinations first
            }
            return lhs.priority < rhs.priority // Lower priority number = higher priority
        }
    }
    
    /// Checks if a payment request can be fulfilled with any destination
    static func canFulfillPayment(
        _ paymentRequest: PaymentRequest,
        with context: PaymentContext
    ) async -> (feasible: Bool, suggestedDestination: PaymentDestination?) {
        if let optimal = await selectOptimalDestination(from: paymentRequest, context: context) {
            return (feasible: true, suggestedDestination: optimal)
        }
        return (feasible: false, suggestedDestination: nil)
    }
    
    // MARK: - Destination Analysis
    
    /// Ranks a single destination with viability and priority information
    /// Uses real fee estimates when available for accurate ranking
    /// - Parameter exactFee: A fee the wallet has already priced for exactly
    ///   this destination and amount (the send flow's onchain quote at the
    ///   chosen tier). When given it replaces the ranker's own estimate, so
    ///   the viability gate judges the send by the fee it will pay and not
    ///   by the rough medium-tier placeholder.
    /// - Parameter source: the balance to pay from; the destination's default
    ///   source when nil
    static func rankDestination(
        _ destination: PaymentDestination,
        amount: Int?,
        context: PaymentContext,
        exactFee: Int? = nil,
        source: BalanceSource? = nil
    ) async -> RankedDestination? {
        let balanceSource = source ?? balanceSource(for: destination)

        // Get fee estimate - the caller's exact fee, else try real estimation; nil when none could be made
        let estimatedFee: Int?
        if let exactFee {
            estimatedFee = exactFee
        } else {
            estimatedFee = await estimateFee(for: destination, source: balanceSource, amount: amount, context: context)
        }

        return rank(destination, source: balanceSource, amount: amount, context: context, estimatedFee: estimatedFee)
    }

    /// Ranks a destination once per balance that can pay it: a bitcoin
    /// address from Savings and from Payments, everything else from its one
    /// source. Order follows `balanceSources(for:)`, Savings first.
    static func rankDestinations(
        _ destination: PaymentDestination,
        amount: Int?,
        context: PaymentContext
    ) async -> [RankedDestination] {
        var ranked: [RankedDestination] = []
        for source in balanceSources(for: destination) {
            if let entry = await rankDestination(destination, amount: amount, context: context, source: source) {
                ranked.append(entry)
            }
        }
        return ranked
    }

    /// The pure part of ranking: balance, viability and priority for a
    /// destination, source and (possibly absent) fee
    private static func rank(
        _ destination: PaymentDestination,
        source balanceSource: BalanceSource,
        amount: Int?,
        context: PaymentContext,
        estimatedFee: Int?
    ) -> RankedDestination {
        let availableBalance = availableBalance(source: balanceSource, context: context)
        let priority = priorityScore(for: destination.format, source: balanceSource, preferences: context.userPreferences)

        let viabilityCheck = checkViability(
            destination: destination,
            amount: amount,
            availableBalance: availableBalance,
            estimatedFee: estimatedFee,
            balanceSource: balanceSource,
            context: context
        )

        return RankedDestination(
            destination: destination,
            balanceSource: balanceSource,
            availableBalance: availableBalance,
            estimatedFee: estimatedFee,
            viable: viabilityCheck.viable,
            reason: viabilityCheck.reason,
            priority: priority
        )
    }

    /// Checks if a destination is viable for payment
    private static func checkViability(
        destination: PaymentDestination,
        amount: Int?,
        availableBalance: Int?,
        estimatedFee: Int?,
        balanceSource: BalanceSource,
        context: PaymentContext
    ) -> (viable: Bool, reason: String) {
        // Lightning and Payments-funded onchain sends go through the server
        if balanceSource.needsArkServer && !context.arkServerConnected {
            return (false, String(localized: "viability_server_not_connected", defaultValue: "Ark server not connected"))
        }

        if balanceSource == .arkViaServer && !context.hasLightningCapability {
            return (false, String(localized: "viability_lightning_unavailable", defaultValue: "Lightning not available"))
        }
        
        // If no amount specified, all destinations are viable (amount will be entered later)
        guard let amount = amount else {
            return (true, String(localized: "viability_no_amount", defaultValue: "No amount specified"))
        }
        
        // Check balance availability
        guard let balance = availableBalance else {
            return (false, String(localized: "viability_balance_unavailable", defaultValue: "Balance unavailable"))
        }
        
        // Check if balance is sufficient; with no estimate the amount alone is judged
        let totalRequired = amount + (estimatedFee ?? 0)
        
        // Special handling for Ark balance with reserve
        /*
        if balanceSource == .ark || balanceSource == .arkViaServer {
            let remainingAfterPayment = balance - totalRequired
            if remainingAfterPayment < context.userPreferences.minimumArkReserve {
                return (false, "Would drain below minimum Ark reserve")
            }
        }
        */
        
        if balance < totalRequired {
            let shortfall = totalRequired - balance
            return (false, String(localized: "viability_need_more %@", defaultValue: "Need \(BitcoinFormatter.shared.formatAmount(shortfall)) more"))
        }
        
        // Check large amount preference
        if context.userPreferences.preferOnChainForLargeAmounts &&
           amount >= context.userPreferences.largeAmountThreshold &&
           balanceSource != .bitcoin {
            // Deprioritize but don't make unviable
            return (true, String(localized: "viability_large_amount_onchain", defaultValue: "Large amount: on-chain preferred"))
        }
        
        return (true, String(localized: "viability_sufficient", defaultValue: "Sufficient balance"))
    }
    
    /// Determines priority score for a format (lower = higher priority).
    /// Formats take even scores so the Payments twin of a bitcoin address
    /// can sit right behind Savings (DECIDED rule 1, 2026-10-10) without
    /// tying with the next format.
    private static func priorityScore(
        for format: AddressFormat,
        source: BalanceSource,
        preferences: PaymentPreferences
    ) -> Int {
        guard let index = preferences.priorityOrder.firstIndex(of: format) else {
            // Unknown formats get lowest priority
            return Int.max
        }
        return index * 2 + (source == .arkToOnchain ? 1 : 0)
    }

    // MARK: - Balance Helpers

    /// The default balance source for a destination: Savings for a bitcoin
    /// address (DECIDED 2026-10-10), the only source for every other format
    static func balanceSource(for destination: PaymentDestination) -> BalanceSource {
        switch destination.format {
        case .ark:
            return .ark
        case .lightning, .lightningInvoice, .lnurl, .bolt12:
            return .arkViaServer // Lightning uses Ark balance but routed through server
        case .bitcoin, .silentPayments:
            return .bitcoin
        case .bip353, .bip21:
            // These are wrapper formats that resolve to others
            // In practice, they should be resolved before reaching this point
            return .bitcoin // Default fallback
        }
    }

    /// Every balance that can pay a destination, default first. A bitcoin
    /// address can also be paid from Payments as an offboard; a silent
    /// payment cannot, since bark's offboard pays a plain script and the
    /// silent-payment output needs sender-side key derivation it does not do.
    static func balanceSources(for destination: PaymentDestination) -> [BalanceSource] {
        switch destination.format {
        case .bitcoin:
            return [.bitcoin, .arkToOnchain]
        default:
            return [balanceSource(for: destination)]
        }
    }

    /// Gets available balance for a destination paid from its default source
    static func availableBalance(
        for destination: PaymentDestination,
        context: PaymentContext
    ) -> Int? {
        availableBalance(source: balanceSource(for: destination), context: context)
    }

    /// The balance a source spends from
    static func availableBalance(
        source: BalanceSource,
        context: PaymentContext
    ) -> Int? {
        source.spendsArkBalance ? context.arkBalance : context.bitcoinBalance
    }

    /// Checks if a destination requires server routing
    static func requiresServerRouting(_ destination: PaymentDestination) -> Bool {
        return balanceSource(for: destination) == .arkViaServer
    }

    // MARK: - Fee Estimation

    /// Estimates the fee for a destination with the real estimator when
    /// there is one. Returns nil when no estimate could be made: a failed
    /// Lightning estimate is not hidden behind a constant (the old static
    /// 20 sats let one screen show two different fees and let a too-low
    /// number pass a payment that then failed; DECIDED 2026-10-27), and
    /// viability then checks the amount alone.
    private static func estimateFee(
        for destination: PaymentDestination,
        source: BalanceSource,
        amount: Int?,
        context: PaymentContext
    ) async -> Int? {
        // Payments-funded onchain send: only bark can price it (server
        // offboard rate, per-VTXO expiry table); no estimate without an amount
        if source == .arkToOnchain {
            guard let amount else { return nil }
            guard let walletManager = context.walletManager else {
                logger.warning("WalletManager is nil during offboard fee estimation. No estimate.")
                return nil
            }
            do {
                let estimate = try await walletManager.estimateSendToOnchainFee(
                    address: destination.address,
                    amountSats: UInt64(amount)
                )
                return Int(estimate.feeSats)
            } catch {
                logger.error("Offboard fee estimation failed for \(amount) sats: \(error.localizedDescription). No estimate.")
                return nil
            }
        }

        // For Lightning payments, try to use real fee estimation if available
        if let unwrappedAmount = amount,
           (destination.format == .lightning || destination.format == .lightningInvoice ||
            destination.format == .lnurl || destination.format == .bolt12) {

            // Check if walletManager is available for real-time fee estimation
            guard let walletManager = context.walletManager else {
                // This should rarely happen in normal usage since SendViewModel holds a strong reference
                // If you see this warning, it may indicate the context is being used incorrectly (stored long-term)
                logger.warning("WalletManager is nil during Lightning fee estimation for \(destination.format.rawValue). This may indicate PaymentContext is being stored instead of created on-demand. No estimate.")
                return nil
            }

            do {
                let feeEstimate = try await walletManager.estimateLightningSendFee(amountSats: UInt64(unwrappedAmount))
                // Calculate actual fee as difference between gross and payment amount
                let rawFee = Int(feeEstimate.grossAmountSats) - unwrappedAmount

                // Defensive check: ensure fee is non-negative (shouldn't happen, but guard against FFI bugs)
                if rawFee < 0 {
                    logger.warning("Detected negative fee calculation: grossAmount=\(feeEstimate.grossAmountSats), amount=\(unwrappedAmount), rawFee=\(rawFee). Using 0.")
                }
                let actualFee = max(0, rawFee)
                return actualFee
            } catch {
                logger.error("Lightning fee estimation failed for payment (format: \(String(describing: destination.format)), amount: \(unwrappedAmount) sats): \(error.localizedDescription). No estimate.")
                return nil
            }
        }

        // For onchain payments, size the fee with live Esplora rates
        // (medium priority, matching SendViewModel's default selection)
        if destination.format == .bitcoin || destination.format == .silentPayments {
            guard let walletManager = context.walletManager else {
                logger.warning("WalletManager is nil during onchain fee estimation for \(destination.format.rawValue). This may indicate PaymentContext is being stored instead of created on-demand. No estimate.")
                return nil
            }
            let feeRate = await walletManager.currentFeeRates().rate(for: .medium)
            return estimateOnchainFee(for: destination, amount: amount, feeRate: feeRate)
        }

        // Ark-to-Ark transfers on the same server carry no fee; wrapper
        // formats are resolved before they reach this point
        switch destination.format {
        case .ark:
            return 0
        default:
            return nil
        }
    }
    
    /// Estimates on-chain fee based on priority and transaction size
    /// - Parameters:
    ///   - destination: The payment destination
    ///   - amount: Amount in satoshis (optional, for more accurate estimation)
    ///   - feeRate: Fee rate in sat/vB
    /// - Returns: Estimated fee in satoshis
    static func estimateOnchainFee(
        for destination: PaymentDestination,
        amount: Int?,
        feeRate: UInt64
    ) -> Int {
        guard destination.format == .bitcoin || destination.format == .silentPayments else {
            // Only onchain sends have a size-based placeholder
            return 0
        }
        
        // A placeholder until BDK's exact estimate lands, never the fee
        // charged; sized so it does not undershoot the simplest real send
        let fee = Int(feeRate * roughOnchainSendVBytes)
        return fee
    }

    /// Virtual size of the simplest send bark's onchain wallet can build:
    /// one P2TR input (57.5 vB), two P2TR outputs (2 × 43 vB) and the
    /// transaction overhead (10.5 vB), 154 vB, rounded up. The wallet is
    /// BIP86, so the P2WPKH figure of 140 vB used before 2026-10-27
    /// undershot every real estimate by about a tenth (7,000 vs 7,839 sats
    /// at 50 sat/vB on signet). Silent-payment destinations also pay to a
    /// P2TR output, so the same size applies. Multi-input sends are larger;
    /// only BDK knows by how much.
    static let roughOnchainSendVBytes: UInt64 = 155
    
    // MARK: - Convenience Methods
    
    /// Gets all viable destinations from a payment request
    static func viableDestinations(
        from paymentRequest: PaymentRequest,
        context: PaymentContext
    ) async -> [PaymentDestination] {
        return await rankDestinations(from: paymentRequest, context: context)
            .filter { $0.viable }
            .map { $0.destination }
    }
    
    /// Checks if a specific destination is viable for a payment
    static func isViable(
        destination: PaymentDestination,
        amount: Int?,
        context: PaymentContext
    ) async -> Bool {
        guard let ranked = await rankDestination(destination, amount: amount, context: context) else {
            return false
        }
        return ranked.viable
    }
    
    /// Gets a detailed viability report for debugging/UI
    static func viabilityReport(
        from paymentRequest: PaymentRequest,
        context: PaymentContext
    ) async -> String {
        let ranked = await rankDestinations(from: paymentRequest, context: context)
        var report = "Payment Destination Analysis:\n"
        report += "Amount: \(paymentRequest.amount.map { "\($0) sats" } ?? "Not specified")\n"
        report += "Ark Balance: \(context.arkBalance.map { "\($0) sats" } ?? "N/A")\n"
        report += "Bitcoin Balance: \(context.bitcoinBalance.map { "\($0) sats" } ?? "N/A")\n"
        report += "\nDestinations:\n"
        
        for (index, destination) in ranked.enumerated() {
            report += "\n\(index + 1). \(destination.destination.format.displayName)\n"
            report += "   Address: \(destination.destination.shortAddress)\n"
            report += "   Balance Source: \(destination.balanceSource.displayName)\n"
            report += "   Available: \(destination.availableBalance.map { "\($0) sats" } ?? "N/A")\n"
            report += "   Estimated Fee: \(destination.estimatedFee.map { "\($0) sats" } ?? "N/A")\n"
            report += "   Viable: \(destination.viable ? "✓" : "✗")\n"
            report += "   Reason: \(destination.reason)\n"
            report += "   Priority: #\(destination.priority + 1)\n"
        }
        
        return report
    }
}

// MARK: - PaymentRequest Extension

extension PaymentRequest {
    /// Convenience method to select optimal destination
    func selectOptimalDestination(context: PaymentDestinationSelector.PaymentContext) async -> PaymentDestination? {
        return await PaymentDestinationSelector.selectOptimalDestination(from: self, context: context)
    }
    
    /// Convenience method to get ranked destinations
    func rankedDestinations(context: PaymentDestinationSelector.PaymentContext) async -> [PaymentDestinationSelector.RankedDestination] {
        return await PaymentDestinationSelector.rankDestinations(from: self, context: context)
    }
    
    /// Convenience method to check viability
    func canFulfill(with context: PaymentDestinationSelector.PaymentContext) async -> Bool {
        return await PaymentDestinationSelector.canFulfillPayment(self, with: context).feasible
    }
}
