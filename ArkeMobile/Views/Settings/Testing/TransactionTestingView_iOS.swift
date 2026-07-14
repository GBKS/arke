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
                Text("testing_play_around_and_find_out")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack {
                    NavigationLink(destination: IncrementalPaymentTestView_iOS()) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("nav_title_spam_payments")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text("testing_spam_payments_subtitle")
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
                                Text("testing_generate_invoices")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text("testing_invoice_generation_subtitle")
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
        .navigationTitle("nav_title_transaction_testing")
        .navigationBarTitleDisplayMode(.large)
    }
}
