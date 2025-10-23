//
//  TransactionStatusBadge.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

struct TransactionStatusBadge: View {
    let status: TransactionStatusEnum
    
    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.backgroundColor)
            .foregroundColor(status.textColor)
            .cornerRadius(6)
    }
}
