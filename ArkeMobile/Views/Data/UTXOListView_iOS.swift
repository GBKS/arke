//
//  UTXOListView_iOS.swift
//  Arké
//
//  Created by Christoph on 12/17/25.
//

import SwiftUI
import ArkeUI

struct UTXOListView_iOS: View {
    var onSelectItem: ((UTXOModel) -> Void)? = nil
    @Environment(WalletManager.self) private var walletManager
    @State private var utxos: [UTXOModel] = []
    @State private var isLoadingUTXOs = false
    @State private var error: String?
    
    private var totalUTXOAmount: Int {
        utxos.reduce(into: 0) { $0 += $1.amountSat }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("label_utxos")
                        .font(.system(size: 24, design: .serif))
                    
                    if !utxos.isEmpty {
                        Text("\(utxos.count) UTXOs • \(totalUTXOAmount.formatted()) ₿")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    Task {
                        await loadUTXOs()
                    }
                } label: {
                    if isLoadingUTXOs {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingUTXOs)
            }
            .padding(.horizontal)
            
            Divider()
                .padding(.top, 12)
                .padding(.horizontal)
            
            if isLoadingUTXOs {
                SkeletonLoader(
                    itemCount: 2,
                    itemHeight: 50,
                    spacing: 15,
                    cornerRadius: 15
                )
                .padding(.top, 10)
                .padding(.horizontal)
            } else if let error = error {
                ErrorBox(errorMessage: error)
            } else if utxos.isEmpty {
                VStack {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                    Text("balance_no_utxos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                .padding(.horizontal)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(utxos.enumerated()), id: \.element.id) { index, utxo in
                        Button {
                            onSelectItem?(utxo)
                        } label: {
                            UTXORowView(
                                utxo: utxo,
                                isSelected: false
                            )
                        }
                        .buttonStyle(.plain)
                        
                        if index < utxos.count - 1 {
                            Divider()
                                .padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .task {
            await loadUTXOs()
        }
    }
    
    private func loadUTXOs() async {
        isLoadingUTXOs = true
        error = nil
        
        print("loadUTXOs")
        
        do {
            utxos = try await walletManager.getUTXOs()
            print("utxos: \(utxos)")
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoadingUTXOs = false
    }
}
