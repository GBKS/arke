//
//  TransactionTestingView_iOS.swift
//  Arké
//
//  Created by Assistant on 12/15/25.
//

import SwiftUI
import ArkeUI

/// Developer tool for testing transaction functionality at scale
struct TransactionTestingView_iOS: View {
    @Environment(WalletManager.self) private var manager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Play around and find out.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack {
                    NavigationLink(destination: IncrementalPaymentTestView_iOS()) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Spam Payments")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text("Send multiple payments with increasing amounts")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            
                            Spacer()
                            
                            // Chevron
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                    
                    NavigationLink(destination: InvoiceGenerationTestView_iOS()) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Generate Invoices")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text("Create multiple Lightning invoices and copy to clipboard")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            
                            Spacer()
                            
                            // Chevron
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Transaction Testing")
        .navigationBarTitleDisplayMode(.large)
    }
}
