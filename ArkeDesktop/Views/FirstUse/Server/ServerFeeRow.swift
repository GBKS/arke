//
//  ServerFeeRow.swift
//  Arké
//
//  Created by Christoph on 11/25/25.
//

import SwiftUI
import ArkeUI

struct ServerFeeRow: View {
    let label: String
    let count: Int
    let amount: Int
    
    var body: some View {
        HStack {
            Text("\(label) (\(count)×)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .contentTransition(.numericText())
            
            Spacer()
            
            Text("\(BitcoinFormatter.shared.formatAmount(amount))")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .animation(.smooth(duration: 0.4), value: count)
        .animation(.smooth(duration: 0.4), value: amount)
    }
}
