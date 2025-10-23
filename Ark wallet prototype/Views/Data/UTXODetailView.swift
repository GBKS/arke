//
//  UTXODetailView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/19/25.
//

import SwiftUI
import AppKit

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
                            Text("Unspent Output")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Available for spending")
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
                        Text("Confirmed")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.green)
                            .clipShape(Capsule())
                        
                        Spacer()
                    }
                }
                
                Divider()
                
                // Details Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("UTXO Details")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        // Outpoint
                        DetailRow(
                            title: "Outpoint",
                            value: utxo.outpoint,
                            isCopyable: true
                        )
                        
                        // Transaction Hash
                        DetailRow(
                            title: "Transaction Hash",
                            value: utxo.transactionHash,
                            isCopyable: true
                        )
                        
                        // Output Index
                        DetailRow(
                            title: "Output Index",
                            value: String(utxo.outputIndex)
                        )
                        
                        // Confirmation Height
                        DetailRow(
                            title: "Confirmation Height",
                            value: utxo.confirmationHeight.map(String.init) ?? "Unconfirmed"
                        )
                        
                        // Short Outpoint for Reference
                        DetailRow(
                            title: "Short Reference",
                            value: utxo.shortOutpoint
                        )
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("UTXO")
        .background(Color(NSColor.windowBackgroundColor))
    }
}



#Preview {
    NavigationStack {
        UTXODetailView(
            utxo: UTXOModel(
                outpoint: "1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s0t1u2v3w4x5y6z:0",
                amountSat: 50000,
                confirmationHeight: 850123
            )
        )
    }
}
