//
//  DataView_iOS.swift
//  Arké
//
//  Created by Christoph on 11/27/25.
//

import SwiftUI
import ArkeUI

struct DataView_iOS: View {
    @Environment(WalletManager.self) private var manager
    var onNavigateToDetail: ((DataDetailItem_iOS) -> Void)? = nil
    @State private var reloadTrigger = 0
    @State private var isReloading = false
    
    // Minimum amount of sats required for a refresh operation
    private let minimumRefreshAmountSats: UInt64 = 330
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                /*
                ArkBalanceView(reloadTrigger: reloadTrigger)
                
                OnchainBalanceView(reloadTrigger: reloadTrigger)
                 */
                
                VTXOListView_iOS(
                    reloadTrigger: reloadTrigger,
                    onSelectItem: { vtxo in
                        onNavigateToDetail?(.vtxo(vtxo))
                    },
                    onRefreshComplete: {
                        await reloadAllData()
                    },
                    minimumRefreshAmountSats: minimumRefreshAmountSats
                )
                .padding(.top, 15)
                
                UnilateralExitListView_iOS(reloadTrigger: reloadTrigger)
                
                PendingRoundsListView_iOS(reloadTrigger: reloadTrigger)
                
                /*
                UTXOListView_iOS(onSelectItem: { utxo in
                    onNavigateToDetail?(.utxo(utxo))
                })
                */
                
                ConfigurationSectionView(reloadTrigger: reloadTrigger)
                
                ArkInfoSectionView(reloadTrigger: reloadTrigger)

                BlockHeightSectionView(reloadTrigger: reloadTrigger)

                FeeRatesSectionView(reloadTrigger: reloadTrigger)

                DebugLogExportButton_iOS()

                /*
                VStack {
                    Button(action: {
                        Task {
                            try? await manager.maintenanceWithOnchainDelegated()
                        }
                    }) {
                        Text("Run maintenance")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.Arke.gold4)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular)
                    .tint(Color.Arke.gold)
                    .padding(.bottom, 20)
                    
                    Button(action: {
                        Task {
                            try? await manager.sync()
                        }
                    }) {
                        Text("Sync")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.Arke.gold4)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular)
                    .tint(Color.Arke.gold)
                    .padding(.bottom, 20)
                }
                .padding(.horizontal)
                 */
            }
        }
        .navigationTitle("data_xray_title")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await reloadAllData()
                    }
                } label: {
                    if isReloading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .accessibilityLabel("accessibility_reload_all_data")
                .accessibilityHint("accessibility_reload_all_data_hint")
                .disabled(isReloading)
            }
        }
    }
    
    private func reloadAllData() async {
        isReloading = true
        reloadTrigger += 1
        
        // Wait a brief moment to allow all child views to complete their reload
        try? await Task.sleep(for: .seconds(0.5))
        
        isReloading = false
    }
}
