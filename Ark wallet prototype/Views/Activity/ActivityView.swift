//
//  ContentView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import SwiftData

struct ActivityView: View {
    @Environment(WalletManager.self) private var manager
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedTransaction: TransactionModel?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Transaction List
                if let transactionService = manager.transactionServiceInstance {
                    TransactionList(selectedTransaction: $selectedTransaction)
                        .environment(transactionService)
                        .onAppear {
                            // Double-check ModelContext is set (defensive programming)
                            transactionService.setModelContext(modelContext)
                        }
                } else {
                    ContentUnavailableView {
                        VStack(spacing: 15) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading transactions...")
                                .font(.system(size: 19, design: .serif))
                        }
                    }
                }
                
                // Error Display
                if let error = manager.error {
                    ErrorView(errorMessage: error)
                        .padding(.horizontal, 12)
                }
            }
        }
        .navigationTitle("Activity")
        .refreshable {
            await manager.refresh()
        }
        .task {
            // CRITICAL: Set ModelContext BEFORE calling initialize
            manager.setModelContext(modelContext)
            await manager.initialize()
        }
    }
}

#Preview {
    @Previewable @State var selectedTransaction: TransactionModel? = nil
    @Previewable @State var walletManager = WalletManager(useMock: true)
    
    ActivityView(selectedTransaction: $selectedTransaction)
        .environment(walletManager)
        .frame(width: 600, height: 600)
        .modelContainer(for: TransactionModel.self, inMemory: true)
        .task {
            // Initialize the wallet manager to set up services
            await walletManager.initialize()
        }
}
