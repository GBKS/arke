//
//  TagRowContent.swift
//  Ark wallet prototype
//
//  Created by Assistant on 12/2/25.
//

import SwiftUI
import ArkeUI

/// Shared content component for displaying tag information in rows
/// Can be customized per platform while maintaining consistent data display
struct TagRowContent: View {
    let tag: TagModel
    let statistic: TagStatistic
    let showNetChangeBar: Bool
    let largestPositiveAmount: Int
    let largestNegativeAmount: Int
    
    init(
        tag: TagModel,
        statistic: TagStatistic,
        showNetChangeBar: Bool = false,
        largestPositiveAmount: Int = 0,
        largestNegativeAmount: Int = 0
    ) {
        self.tag = tag
        self.statistic = statistic
        self.showNetChangeBar = showNetChangeBar
        self.largestPositiveAmount = largestPositiveAmount
        self.largestNegativeAmount = largestNegativeAmount
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Tag chip
            TagChip(tag: tag.appearance, size: .medium)
            
            Spacer()
            
            // Transaction count
            Text("\(statistic.transactionCount) transaction\(statistic.transactionCount == 1 ? "" : "s")")
                .font(.body)
                .foregroundColor(.secondary)
            
            // Amount
            if statistic.transactionCount > 0 {
                Text(statistic.formattedTotalAmount)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(statistic.totalAmount >= 0 ? .Arke.green : .Arke.red)
                    .frame(minWidth: 80, alignment: .trailing)
            }
            
            // Optional net change bar (typically for macOS)
            if showNetChangeBar && (largestPositiveAmount > 0 || largestNegativeAmount < 0) {
                NetChangeBar(
                    currentAmount: statistic.totalAmount,
                    largestPositiveAmount: largestPositiveAmount,
                    largestNegativeAmount: largestNegativeAmount
                )
                .frame(width: 100)
            }
        }
    }
}
