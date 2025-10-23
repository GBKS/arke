//
//  ContentView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

struct ActivityView: View {
    @Environment(WalletManager.self) private var manager
    @Binding var selectedTransaction: TransactionModel?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Transaction List
                TransactionList(transactions: manager.transactions, selectedTransaction: $selectedTransaction, isInitialLoading: manager.isInitialLoading)
                
                // Error Display
                if let error = manager.error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }
            }
        }
        .navigationTitle("Activity")
        .refreshable {
            await manager.refresh()
        }
        .task {
            await manager.initialize()
        }
    }
}

#Preview {
    ActivityView(selectedTransaction: .constant(nil))
        .environment(WalletManager(useMock: true))
        .frame(width: 600, height: 600)
}
