//
//  BlockTimeFormatter.swift
//  ArkéUI
//
//  Created by Christoph on 7/7/26.
//
//  Converts block counts into approximate human-readable durations,
//  assuming Bitcoin's average block interval of 10 minutes.
//

import Foundation

public enum BlockTimeFormatter {
    /// Average Bitcoin block interval in seconds.
    public static let secondsPerBlock = 600

    /// Formats a block count as an approximate localized duration,
    /// e.g. "26d 5h". Negative counts are treated as elapsed time
    /// (their absolute value is formatted); the caller decides how to
    /// phrase past vs. future.
    public static func duration(forBlocks blocks: Int) -> String {
        let seconds = abs(blocks) * secondsPerBlock

        // For very short durations, show "< 1m"
        if seconds < 60 {
            return "< 1m"
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll

        return formatter.string(from: TimeInterval(seconds)) ?? "< 1m"
    }

    /// A confirmation target as the time it roughly takes, with the tilde
    /// that says "roughly": "~10 min", "~30 min", "~1 hr". Used by the fee
    /// tiers, whose targets are 1, 3 and 6 blocks.
    public static func confirmationEstimate(forBlocks blocks: Int) -> String {
        let seconds = max(blocks, 1) * secondsPerBlock

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .short
        formatter.zeroFormattingBehavior = .dropAll

        let duration = formatter.string(from: TimeInterval(seconds)) ?? "\(seconds / 60) min"
        return String(localized: "confirmation_estimate_format", defaultValue: "~\(duration)", bundle: .module)
    }
}
