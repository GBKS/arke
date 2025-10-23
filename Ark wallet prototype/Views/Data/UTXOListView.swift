//
//  UTXOListView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI

struct UTXOListView: View {
    @Binding var selectedDataItem: DataDetailItem?
    @Environment(WalletManager.self) private var walletManager
    @State private var utxos: [UTXOModel] = []
    @State private var isLoadingUTXOs = false
    @State private var error: String?
    
    private var totalUTXOAmount: Int {
        utxos.reduce(into: 0) { $0 += $1.amountSat }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("UTXOs")
                        .font(.system(size: 24, design: .serif))
                    
                    if !utxos.isEmpty {
                        Text("\(utxos.count) UTXOs • \(totalUTXOAmount.formatted()) ₿")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Refresh") {
                    Task {
                        await loadUTXOs()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingUTXOs)
            }
            
            Divider()
                .padding(.top, 12)
            
            if isLoadingUTXOs {
                SkeletonLoader(
                    itemCount: 2,
                    itemHeight: 50,
                    spacing: 15,
                    cornerRadius: 15
                )
                .padding(.top, 10)
            } else if let error = error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if utxos.isEmpty {
                VStack {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                    Text("No UTXOs found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(utxos.enumerated()), id: \.element.id) { index, utxo in
                        VStack(spacing: 0) {
                            Button {
                                selectedDataItem = .utxo(utxo)
                            } label: {
                                UTXORowView(utxo: utxo, showDivider: index < utxos.count - 1)
                            }
                            .buttonStyle(.plain)
                            .background(selectedDataItem == .utxo(utxo) ? Color.accentColor.opacity(0.1) : Color.clear)
                        }
                    }
                }
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

#Preview("Default") {
    NavigationStack {
        UTXOListView(selectedDataItem: .constant(nil))
            .environment(WalletManager(useMock: true))
            .padding()
    }
    .frame(width: 400)
}
