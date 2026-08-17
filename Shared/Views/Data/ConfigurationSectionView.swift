//
//  ConfigurationSectionView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI
import ArkeUI

struct ConfigurationSectionView: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var configData: ArkConfigModel?
    @State private var isLoadingConfig = false
    @State private var error: String?
    var reloadTrigger: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "data_configuration", defaultValue: "Configuration"))
                .font(.system(size: 24, design: .serif))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if isLoadingConfig {
                SkeletonLoader(
                    itemCount: 1,
                    itemHeight: 100,
                    spacing: 15,
                    cornerRadius: 15
                )
            } else if configData == nil && !isLoadingConfig {
                VStack {
                    Image(systemName: "gear")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "data_no_configuration", defaultValue: "No configuration data"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if let configData = configData {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledValueRow(
                        String(localized: "data_network_label", defaultValue: "Network"),
                        value: configData.network
                    )
                    LabeledValueRow(
                        String(localized: "data_server_label", defaultValue: "Server"),
                        value: configData.serverAddress
                    )
                    if let esploraAddress = configData.esploraAddress, configData.hasEsploraEndpoint {
                        LabeledValueRow(
                            String(localized: "data_esplora_label", defaultValue: "Esplora"),
                            value: esploraAddress
                        )
                    }
                    if let bitcoindAddress = configData.bitcoindAddress, configData.hasBitcoindConnection {
                        LabeledValueRow(
                            String(localized: "data_bitcoind_label", defaultValue: "Bitcoin Core"),
                            value: bitcoindAddress
                        )
                    }
                    LabeledValueRow(
                        String(localized: "data_fallback_fee_rate_label", defaultValue: "Fallback Fee Rate (sat/vB)"),
                        value: "\(configData.fallbackFeeRateSatPerVB)"
                    )
                    LabeledValueRow(
                        String(localized: "data_refresh_threshold_label", defaultValue: "Refresh Threshold (blocks)"),
                        value: "\(configData.vtxoRefreshThresholdBlocks)"
                    )
                    if let exitMargin = configData.vtxoExitMargin {
                        LabeledValueRow(
                            String(localized: "data_exit_margin_label", defaultValue: "Exit Margin (blocks)"),
                            value: "\(exitMargin)"
                        )
                    }
                    if let htlcDelta = configData.htlcRecvClaimDelta {
                        LabeledValueRow(
                            String(localized: "data_htlc_claim_delta_label", defaultValue: "HTLC Claim Delta (blocks)"),
                            value: "\(htlcDelta)"
                        )
                    }
                    if let confirmations = configData.roundTxRequiredConfirmations {
                        LabeledValueRow(
                            String(localized: "data_required_confirmations_label", defaultValue: "Required Confirmations"),
                            value: "\(confirmations)"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
        .task(id: reloadTrigger) {
            await loadConfigData()
        }
    }
    
    private func loadConfigData() async {
        isLoadingConfig = true
        error = nil
        
        print("loadConfigData")
        
        do {
            configData = try await walletManager.getConfig()
            print("configData: \(String(describing: configData))")
        } catch {
            self.error = error.localizedDescription
            configData = nil
        }
        
        isLoadingConfig = false
    }
}
