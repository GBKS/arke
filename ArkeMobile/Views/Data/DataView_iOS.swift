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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                ArkBalanceView()
                
                OnchainBalanceView()
                
                VTXOListView_iOS(onSelectItem: { vtxo in
                    onNavigateToDetail?(.vtxo(vtxo))
                })
                
                UnilateralExitListView_iOS(onSelectItem: { exitVtxo in
                    onNavigateToDetail?(.exitVtxo(exitVtxo))
                })
                
                PendingRoundsListView_iOS()
                
                /*
                UTXOListView_iOS(onSelectItem: { utxo in
                    onNavigateToDetail?(.utxo(utxo))
                })
                */
                
                ConfigurationSectionView()
                
                ArkInfoSectionView()

                BlockHeightSectionView()

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
                            .foregroundStyle(Color.Arke.gold3)
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
                            .foregroundStyle(Color.Arke.gold3)
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
    }
}
