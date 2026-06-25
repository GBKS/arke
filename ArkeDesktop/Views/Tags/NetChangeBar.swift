//
//  NetChangeBar.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/17/25.
//

import SwiftUI
import ArkeUI

/// A visual representation of net change as a horizontal bar chart.
/// Displays positive values (green) extending right from center and negative values (red) extending left from center.
struct NetChangeBar: View {
    let currentAmount: Int
    let largestPositiveAmount: Int
    let largestNegativeAmount: Int
    
    var body: some View {
        GeometryReader { geometry in
            let totalRange = largestPositiveAmount + abs(largestNegativeAmount)
            let zeroPosition: CGFloat = totalRange > 0 ? CGFloat(abs(largestNegativeAmount)) / CGFloat(totalRange) : 0.5
            
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 8)
                
                // Value bar
                if currentAmount != 0 {
                    let barWidth: CGFloat = {
                        if currentAmount > 0 {
                            // Positive value: bar extends from zero to the right
                            let percentage = CGFloat(currentAmount) / CGFloat(largestPositiveAmount)
                            return geometry.size.width * (1.0 - zeroPosition) * percentage
                        } else {
                            // Negative value: bar extends from zero to the left
                            let percentage = CGFloat(abs(currentAmount)) / CGFloat(abs(largestNegativeAmount))
                            return geometry.size.width * zeroPosition * percentage
                        }
                    }()
                    
                    let barOffset: CGFloat = {
                        if currentAmount > 0 {
                            return geometry.size.width * zeroPosition
                        } else {
                            return geometry.size.width * zeroPosition - barWidth
                        }
                    }()
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(currentAmount >= 0 ? Color.Arke.green : Color.Arke.red)
                        .frame(width: barWidth, height: 8)
                        .offset(x: barOffset)
                    
                    // Zero line indicator
                    Rectangle()
                        .fill(Color.black.opacity(1))
                        .frame(width: 1, height: 14)
                        .offset(x: geometry.size.width * zeroPosition)
                }
            }
        }
        .frame(height: 10)
    }
}
