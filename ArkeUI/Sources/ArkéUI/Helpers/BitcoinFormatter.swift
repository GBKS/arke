//
//  BitcoinFormatter.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/22/25.
//

import Foundation
import Observation

/// A formatter for Bitcoin amounts that respects user preferences and system locale settings.
/// This class reads the user's preferred Bitcoin display format and applies system locale
/// settings for number formatting (decimal/grouping separators, symbol placement, etc.).
@Observable
public class BitcoinFormatter {
    
    // MARK: - Singleton
    
    nonisolated(unsafe) public static let shared = BitcoinFormatter()
    
    // MARK: - Properties
    
    private let userDefaults: UserDefaults
    
    /// Internal trigger to force observable updates
    private var updateTrigger = 0
    
    /// The current selected format from user preferences
    /// This is observable, so views will update when the format changes
    var selectedFormat: BitcoinAmountFormat {
        // Access updateTrigger to make this property depend on it
        _ = updateTrigger
        
        guard let rawValue = userDefaults.string(forKey: BitcoinAmountFormat.userDefaultsKey),
              let format = BitcoinAmountFormat(rawValue: rawValue) else {
            return .defaultFormat
        }
        return format
    }
    
    // MARK: - Initialization
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        
        // Observe UserDefaults changes to trigger SwiftUI updates
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Trigger observation by mutating updateTrigger
            self?.updateTrigger += 1
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Conversion Helpers
    
    /// Converts satoshis to Bitcoin (decimal)
    /// - Parameter satoshis: Amount in satoshis
    /// - Returns: Amount in Bitcoin
    private func satoshisToBitcoin(_ satoshis: Int) -> Double {
        return Double(satoshis) / 100_000_000.0
    }
    
    /// Determines if the current format uses Bitcoin (decimal) vs satoshis (integer)
    private var usesDecimalBitcoin: Bool {
        switch selectedFormat {
        case .fullBitcoin, .corn, .unicorn:
            return true
        case .satoshis, .bip177:
            return false
        }
    }

    /// Public accessor for whether the current format allows decimal input
    /// Use this to determine whether to show decimal point button in keypads
    public var allowsDecimalInput: Bool {
        return usesDecimalBitcoin
    }
    
    // MARK: - NumberFormatter Factory
    
    /// Creates and configures a NumberFormatter for the current format and locale
    /// - Parameter includeSymbol: Whether to include the currency/unit symbol
    /// - Returns: Configured NumberFormatter
    private func makeFormatter(includeSymbol: Bool = true) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        
        switch selectedFormat {
        case .fullBitcoin:
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 8
            formatter.usesGroupingSeparator = true
            
        case .satoshis:
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
            formatter.usesGroupingSeparator = true
            
        case .bip177:
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
            formatter.usesGroupingSeparator = true
            
        case .corn:
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 8
            formatter.usesGroupingSeparator = true
            
        case .unicorn:
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 8
            formatter.usesGroupingSeparator = true
        }
        
        return formatter
    }
    
    /// Gets the appropriate symbol for the current format
    private var formatSymbol: String {
        switch selectedFormat {
        case .fullBitcoin, .bip177:
            return "₿"
        case .satoshis:
            return "sats"
        case .corn:
            return "🌽"
        case .unicorn:
            return "🦄"
        }
    }
    
    /// Determines whether the symbol should be placed before or after the amount
    /// This respects the locale's currency formatting conventions
    private func symbolPlacement(for locale: Locale = .autoupdatingCurrent) -> SymbolPlacement {
        // Use locale's currency format as a guide
        let testFormatter = NumberFormatter()
        testFormatter.locale = locale
        testFormatter.numberStyle = .currency
        testFormatter.currencySymbol = "¤" // Generic currency placeholder
        
        let formatted = testFormatter.string(from: 1) ?? "¤1"
        
        // Check if symbol comes first
        if formatted.hasPrefix("¤") {
            return .prefix
        } else {
            return .suffix
        }
    }
    
    private enum SymbolPlacement {
        case prefix
        case suffix
    }
    
    // MARK: - Core Formatting Logic
    
    /// Formats a raw amount with the current format settings
    /// - Parameter amountSats: Amount in satoshis
    /// - Returns: Formatted string without sign prefix
    private func formatRawAmount(_ amountSats: Int) -> String {
        let formatter = makeFormatter()
        let absoluteAmount = abs(amountSats)
        
        // Handle zero case
        if absoluteAmount == 0 {
            return formatZero()
        }
        
        // Handle extremely large amounts (> 21M BTC)
        let maxSatoshis = 21_000_000 * 100_000_000
        if absoluteAmount > maxSatoshis {
            // Still format it, but this is beyond Bitcoin's max supply
            // Could add a warning or different formatting in the future
        }
        
        // Convert to appropriate unit
        let numberToFormat: NSNumber
        if usesDecimalBitcoin {
            numberToFormat = NSNumber(value: satoshisToBitcoin(absoluteAmount))
        } else {
            numberToFormat = NSNumber(value: absoluteAmount)
        }
        
        // Get formatted number string
        guard let formattedNumber = formatter.string(from: numberToFormat) else {
            return formatZero()
        }
        
        // Apply symbol based on format and locale
        let symbol = formatSymbol
        let placement = symbolPlacement()
        
        switch placement {
        case .prefix:
            // For satoshis, we always use suffix regardless of locale
            if selectedFormat == BitcoinAmountFormat.satoshis {
                return "\(formattedNumber) \(symbol)"
            }
            return "\(symbol) \(formattedNumber)"
        case .suffix:
            return "\(formattedNumber) \(symbol)"
        }
    }
    
    /// Formats a zero amount appropriately for the current format
    private func formatZero() -> String {
        let symbol = formatSymbol
        let placement = symbolPlacement()
        
        let zeroString: String
        switch selectedFormat {
        case .fullBitcoin, .corn, .unicorn:
            zeroString = L10n.formatZero
        case .satoshis, .bip177:
            zeroString = L10n.formatZero
        }
        
        switch placement {
        case .prefix:
            if selectedFormat == BitcoinAmountFormat.satoshis {
                return "\(zeroString) \(symbol)"
            }
            return "\(symbol) \(zeroString)"
        case .suffix:
            return "\(zeroString) \(symbol)"
        }
    }
    
    // MARK: - Public Parsing Methods

    /// Parses user input string to satoshis based on current format
    /// - Parameter input: The user input string (e.g., "0.001" or "100000")
    /// - Returns: Amount in satoshis, or nil if input is invalid
    public func parseUserInput(_ input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // For decimal Bitcoin formats, parse as Bitcoin and convert to satoshis
        if usesDecimalBitcoin {
            // Parse as Double
            guard let btcAmount = Double(trimmed) else { return nil }

            // Convert to satoshis (multiply by 100,000,000)
            let satoshis = btcAmount * 100_000_000.0

            // Check for valid range
            guard satoshis >= 0 && satoshis <= Double(Int.max) else { return nil }

            // Round to nearest satoshi (handles floating point precision)
            return Int(round(satoshis))
        } else {
            // For satoshi formats, parse directly as integer
            return Int(trimmed)
        }
    }

    /// Formats a partial decimal input (e.g., "0.", "0.00") for display while user is typing
    /// - Parameter input: The partial input string
    /// - Returns: Formatted string with symbol (e.g., "₿ 0.00")
    public func formatPartialDecimalInput(_ input: String) -> String {
        let symbol = formatSymbol
        let placement = symbolPlacement()

        switch placement {
        case .prefix:
            return "\(symbol) \(input)"
        case .suffix:
            return "\(input) \(symbol)"
        }
    }

    // MARK: - Public Formatting Methods

    /// Formats a Bitcoin amount in satoshis for general display
    /// - Parameter amountSats: The amount in satoshis
    /// - Returns: Formatted string with appropriate symbol and formatting
    public func formatAmount(_ amountSats: Int) -> String {
        return formatRawAmount(amountSats)
    }
    
    /// Formats a Bitcoin amount with transaction type context (adds +/- prefixes)
    /// - Parameters:
    ///   - amountSats: The amount in satoshis
    ///   - transactionType: The type of transaction to determine sign prefix
    ///   - isInternalTransfer: Whether this is an internal transfer between user's own balances
    /// - Returns: Formatted string with appropriate sign prefix
    public func formatTransactionAmount(_ amountSats: Int, transactionType: TransactionTypeEnum, isInternalTransfer: Bool = false) -> String {
        let baseFormatted = formatRawAmount(amountSats)
        
        // Internal transfers (boarding, offboarding, refresh) show no sign prefix
        if isInternalTransfer {
            return baseFormatted
        }
        
        // Add sign prefix for received transactions
        if transactionType == .received {
            return "+\(baseFormatted)"
        }
        
        // Regular transfers show positive amount (funds moving between own accounts)
        if transactionType == .transfer {
            return baseFormatted
        }
        
        return "-\(baseFormatted)"
    }
    
    /// Formats a Bitcoin amount in accounting style with consistent symbol placement
    /// - Parameters:
    ///   - amountSats: The amount in satoshis
    ///   - transactionType: The type of transaction to determine sign
    ///   - isInternalTransfer: Whether this is an internal transfer between user's own balances
    /// - Returns: Formatted string in accounting style
    public func formatAccountingAmount(_ amountSats: Int, transactionType: TransactionTypeEnum, isInternalTransfer: Bool = false) -> String {
        let formatter = makeFormatter(includeSymbol: false)
        let absoluteAmount = abs(amountSats)
        
        // Convert to appropriate unit
        let numberToFormat: NSNumber
        if usesDecimalBitcoin {
            numberToFormat = NSNumber(value: satoshisToBitcoin(absoluteAmount))
        } else {
            numberToFormat = NSNumber(value: absoluteAmount)
        }
        
        // Get formatted number string
        guard let formattedNumber = formatter.string(from: numberToFormat) else {
            return L10n.formatZero
        }
        
        // In accounting style, always place symbol on the right for consistency
        let symbol = formatSymbol
        
        // Internal transfers show no sign prefix
        if isInternalTransfer {
            return "\(formattedNumber) \(symbol)"
        }
        
        switch transactionType {
        case .received:
            return "+\(formattedNumber) \(symbol)"
        case .transfer:
            return "\(formattedNumber) \(symbol)"
        default: // sent or pending
            return "-\(formattedNumber) \(symbol)"
        }
    }
}
