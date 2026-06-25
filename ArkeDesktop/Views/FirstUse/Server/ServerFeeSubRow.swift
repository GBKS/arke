//
//  ServerFeeSubRow.swift
//  Arké
//
//  Created by Christoph on 11/25/25.
//

import SwiftUI
import ArkeUI

struct ServerFeeSubRow: View {
    let label: String
    let amount: Int
    
    var body: some View {
        HStack {
            Text("   \(label)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            
            Spacer()
            
            Text("\(BitcoinFormatter.shared.formatAmount(amount))")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.leading, 16)
    }
}
