//
//  FeePriority.swift
//  ArkéUI
//
//  Created by Assistant on 3/25/26.
//  Moved into ArkéUI as a pure, previewable presentation value type
//  (no SwiftData/Bark). Localized strings use `bundle: .module`.
//

import Foundation

/// Priority level for on-chain Bitcoin transaction fees
public enum FeePriority: String, CaseIterable, Identifiable, Sendable {
    case fast = "fast"
    case medium = "medium"
    case slow = "slow"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fast:
            return String(localized: "fee_priority_fast", defaultValue: "Fast", bundle: .module)
        case .medium:
            return String(localized: "fee_priority_medium", defaultValue: "Medium", bundle: .module)
        case .slow:
            return String(localized: "fee_priority_slow", defaultValue: "Slow", bundle: .module)
        }
    }

    public var description: String {
        switch self {
        case .fast:
            return String(localized: "fee_priority_fast_description", defaultValue: "Higher fee for faster confirmation", bundle: .module)
        case .medium:
            return String(localized: "fee_priority_medium_description", defaultValue: "Balanced fee and confirmation time", bundle: .module)
        case .slow:
            return String(localized: "fee_priority_slow_description", defaultValue: "Lower fee with longer confirmation time", bundle: .module)
        }
    }

    public var estimatedConfirmationTime: String {
        switch self {
        case .fast:
            return String(localized: "fee_priority_fast_time", defaultValue: "~10-20 min", bundle: .module)
        case .medium:
            return String(localized: "fee_priority_medium_time", defaultValue: "~30-60 min", bundle: .module)
        case .slow:
            return String(localized: "fee_priority_slow_time", defaultValue: "~1-2 hours", bundle: .module)
        }
    }

    /// Default fee rate in sat/vB for this priority
    /// These are fallback values when real-time fee estimation is unavailable
    public var defaultSatPerVb: UInt64 {
        switch self {
        case .fast:
            return 10 // ~10-20 minutes
        case .medium:
            return 5  // ~30-60 minutes
        case .slow:
            return 2  // ~1-2 hours
        }
    }
}

/// On-chain fee rates for different priority levels
public struct OnchainFeeRates: Sendable {
    public let fast: UInt64    // sat/vB
    public let medium: UInt64  // sat/vB
    public let slow: UInt64    // sat/vB

    public init(fast: UInt64, medium: UInt64, slow: UInt64) {
        self.fast = fast
        self.medium = medium
        self.slow = slow
    }

    /// Default fallback rates when real-time estimation is unavailable
    public static let `default` = OnchainFeeRates(
        fast: FeePriority.fast.defaultSatPerVb,
        medium: FeePriority.medium.defaultSatPerVb,
        slow: FeePriority.slow.defaultSatPerVb
    )

    /// Get the fee rate for a specific priority
    public func rate(for priority: FeePriority) -> UInt64 {
        switch priority {
        case .fast:
            return fast
        case .medium:
            return medium
        case .slow:
            return slow
        }
    }
}
