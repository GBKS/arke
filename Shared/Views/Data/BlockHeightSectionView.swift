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
                Text("data_block_height")
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
                    Text("data_no_block_height")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if let lastLoaded = lastLoadedBlockHeight {
                        Text(String(localized: "data_last_loaded", defaultValue: "Last Loaded: \(lastLoaded.formatted())"))
                    }
                    
                    if let estimated = estimatedBlockHeight {
                        Text(String(localized: "data_estimated_current", defaultValue: "Estimated Current: \(estimated.formatted())"))
                    }
                    
                    // Show the difference if both values are available
                    if let lastLoaded = lastLoadedBlockHeight, 
                       let estimated = estimatedBlockHeight,
                       estimated > lastLoaded {
                        Text(String(localized: "data_estimated_blocks_behind", defaultValue: "Estimated Blocks Behind: \(estimated - lastLoaded)"))
                            .foregroundStyle(.orange)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
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
