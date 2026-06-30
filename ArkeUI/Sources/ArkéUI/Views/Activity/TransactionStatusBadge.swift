//
//  TransactionStatusBadge.swift
//  ArkéUI
//
//  Created by Christoph on 10/16/25.
//  Moved into ArkéUI as a pure, previewable presentation view.
//

import SwiftUI

public struct TransactionStatusBadge: View {
    let status: TransactionStatusEnum

    public init(status: TransactionStatusEnum) {
        self.status = status
    }

    public var body: some View {
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

#Preview {
    VStack(spacing: 12) {
        TransactionStatusBadge(status: .confirmed)
        TransactionStatusBadge(status: .pending)
        TransactionStatusBadge(status: .failed)
    }
    .padding()
}
