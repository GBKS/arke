//
//  BlockHeightSectionView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI
import ArkeUI

struct BlockHeightSectionView: View {
    var reloadTrigger: Int = 0
    @Environment(WalletManager.self) private var walletManager
    @State private var lastLoadedBlockHeight: Int?
    @State private var estimatedBlockHeight: Int?
    @State private var isLoadingBlockHeight = false
    @State private var error: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(String(localized: "data_block_height", defaultValue: "Block Height"))
                    .font(.system(size: 24, design: .serif))
                
                Spacer()
            }
            
            if isLoadingBlockHeight {
                SkeletonLoader(
                    itemCount: 1,
                    itemHeight: 50,
                    spacing: 15,
                    cornerRadius: 15
                )
            } else if lastLoadedBlockHeight == nil && !isLoadingBlockHeight {
                VStack {
                    Image(systemName: "cube")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "data_no_block_height", defaultValue: "No block height data"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if let lastLoaded = lastLoadedBlockHeight {
                        LabeledValueRow(
                            String(localized: "data_last_loaded_label", defaultValue: "Last Loaded"),
                            value: lastLoaded.formatted()
                        )
                    }

                    if let estimated = estimatedBlockHeight {
                        LabeledValueRow(
                            String(localized: "data_estimated_current_label", defaultValue: "Estimated Current"),
                            value: estimated.formatted()
                        )
                    }

                    // Show the difference if both values are available
                    if let lastLoaded = lastLoadedBlockHeight,
                       let estimated = estimatedBlockHeight,
                       estimated > lastLoaded {
                        LabeledValueRow(
                            String(localized: "data_estimated_blocks_behind_label", defaultValue: "Estimated Blocks Behind"),
                            value: (estimated - lastLoaded).formatted(),
                            valueColor: .orange
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if let error = error {
                ErrorBox(errorMessage: error)
            }
        }
        .padding(.horizontal)
        .task(id: reloadTrigger) {
            await loadBlockHeightData()
        }
        .onChange(of: walletManager.hasLoadedOnce) {
            // Refresh block height data when wallet data is refreshed
            if walletManager.hasLoadedOnce {
                Task {
                    await loadBlockHeightData()
                }
            }
        }
    }
    
    private func loadBlockHeightData() async {
        isLoadingBlockHeight = true
        error = nil
        
        print("loadBlockHeightData")
        
        do {
            // Load the last loaded block height
            lastLoadedBlockHeight = try await walletManager.getLatestBlockHeight()
            
            // Get the estimated current block height
            estimatedBlockHeight = await walletManager.getEstimatedBlockHeight()
            
            print("Last loaded block height: \(String(describing: lastLoadedBlockHeight))")
            print("Estimated block height: \(String(describing: estimatedBlockHeight))")
        } catch {
            self.error = error.localizedDescription
            lastLoadedBlockHeight = nil
            estimatedBlockHeight = nil
        }
        
        isLoadingBlockHeight = false
    }
}
