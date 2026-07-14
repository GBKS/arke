//
//  UTXODetailView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/19/25.
//

import SwiftUI
import ArkeUI

struct UTXODetailView: View {
    let utxo: UTXOModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Section
                VStack(spacing: 16) {
                    // UTXO Icon and Type
                    HStack {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading) {
                            Text("balance_unspent_output")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("balance_available_spending")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    // Amount
                    Text(utxo.formattedAmount)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Confirmation Status Badge
                    HStack {
                        Text("status_confirmed")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.Arke.green)
                            .clipShape(Capsule())
                        
                        Spacer()
                    }
                }
                
                Divider()
                
                // Details Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("balance_utxo_details")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        // Outpoint
                        DetailRow(
                            title: "data_outpoint",
                            value: utxo.outpoint,
                            isCopyable: true
                        )
                        
                        // Transaction Hash
                        DetailRow(
                            title: "data_transaction_hash",
                            value: utxo.transactionHash,
                            isCopyable: true
                        )
                        
                        // Output Index
                        DetailRow(
                            title: "data_output_index",
                            value: String(utxo.outputIndex)
                        )
                        
                        // Confirmation Height
                        DetailRow(
                            title: "data_confirmation_height",
                            value: utxo.confirmationHeight.map(String.init) ?? String(localized: "activity_unconfirmed")
                        )
                        
                        // Short Outpoint for Reference
                        DetailRow(
                            title: "data_short_reference",
                            value: utxo.shortOutpoint
                        )
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("label_utxo")
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
    }
}
