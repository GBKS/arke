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
                            Text(String(localized: "balance_unspent_output", defaultValue: "Unspent Output"))
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text(String(localized: "balance_available_spending", defaultValue: "Available for spending"))
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
                        Text(L10n.statusConfirmed)
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
                    Text(String(localized: "balance_utxo_details", defaultValue: "UTXO Details"))
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        // Outpoint
                        DetailRow(
                            title: String(localized: "data_outpoint", defaultValue: "Outpoint"),
                            value: utxo.outpoint,
                            isCopyable: true
                        )
                        
                        // Transaction Hash
                        DetailRow(
                            title: String(localized: "data_transaction_hash", defaultValue: "Transaction Hash"),
                            value: utxo.transactionHash,
                            isCopyable: true
                        )
                        
                        // Output Index
                        DetailRow(
                            title: String(localized: "data_output_index", defaultValue: "Output Index"),
                            value: String(utxo.outputIndex)
                        )
                        
                        // Confirmation Height
                        DetailRow(
                            title: String(localized: "data_confirmation_height", defaultValue: "Confirmation Height"),
                            value: utxo.confirmationHeight.map(String.init) ?? L10n.activityUnconfirmed
                        )
                        
                        // Short Outpoint for Reference
                        DetailRow(
                            title: String(localized: "data_short_reference", defaultValue: "Short Reference"),
                            value: utxo.shortOutpoint
                        )
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle(String(localized: "label_utxo", defaultValue: "UTXO"))
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
    }
}
