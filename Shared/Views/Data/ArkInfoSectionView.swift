//
//  ArkInfoSectionView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI
import ArkeUI

struct ArkInfoSectionView: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var arkInfoData: ArkInfoModel?
    @State private var isLoadingArkInfo = false
    @State private var error: String?
    var reloadTrigger: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("data_ark_info")
                .font(.system(size: 24, design: .serif))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if isLoadingArkInfo {
                SkeletonLoader(
                    itemCount: 1,
                    itemHeight: 100,
                    spacing: 15,
                    cornerRadius: 15
                )
            } else if arkInfoData == nil && !isLoadingArkInfo {
                VStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("data_no_ark_info")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if let arkInfoData = arkInfoData {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledValueRow(
                        String(localized: "data_network_label", defaultValue: "Network"),
                        value: arkInfoData.network.uppercased()
                    )
                    LabeledValueRow(
                        String(localized: "data_server_label", defaultValue: "Server"),
                        value: arkInfoData.serverPubkeyShort
                    )
                    LabeledValueRow(
                        String(localized: "data_round_interval_label", defaultValue: "Round Interval"),
                        value: "\(arkInfoData.roundInterval)"
                    )
                    LabeledValueRow(
                        String(localized: "data_round_nonces_label", defaultValue: "Round Nonces"),
                        value: "\(arkInfoData.nbRoundNonces)"
                    )
                    LabeledValueRow(
                        String(localized: "data_max_vtxo_amount_label", defaultValue: "Max VTXO Amount (BTC)"),
                        value: arkInfoData.maxVtxoAmountBTC.map { $0.formatted(.number.precision(.fractionLength(8))) }
                            ?? String(localized: "data_value_not_set", defaultValue: "Not set")
                    )
                    LabeledValueRow(
                        String(localized: "data_min_board_amount_label", defaultValue: "Min Board Amount (BTC)"),
                        value: arkInfoData.minBoardAmountBTC.formatted(.number.precision(.fractionLength(8)))
                    )
                    LabeledValueRow(
                        String(localized: "data_vtxo_exit_delta_label", defaultValue: "VTXO Exit Delta (blocks)"),
                        value: "\(arkInfoData.vtxoExitDelta)"
                    )
                    LabeledValueRow(
                        String(localized: "data_vtxo_expiry_delta_label", defaultValue: "VTXO Expiry Delta (blocks)"),
                        value: "\(arkInfoData.vtxoExpiryDelta)"
                    )
                    LabeledValueRow(
                        String(localized: "data_htlc_send_expiry_delta_label", defaultValue: "HTLC Send Expiry Delta (blocks)"),
                        value: "\(arkInfoData.htlcSendExpiryDelta)"
                    )
                    LabeledValueRow(
                        String(localized: "data_htlc_expiry_delta_label", defaultValue: "HTLC Expiry Delta (blocks)"),
                        value: "\(arkInfoData.htlcExpiryDelta)"
                    )
                    LabeledValueRow(
                        String(localized: "data_max_user_invoice_cltv_label", defaultValue: "Max User Invoice CLTV Delta (blocks)"),
                        value: "\(arkInfoData.maxUserInvoiceCltvDelta)"
                    )
                    LabeledValueRow(
                        String(localized: "data_board_confirmations_label", defaultValue: "Board Confirmations"),
                        value: "\(arkInfoData.requiredBoardConfirmations)"
                    )
                    LabeledValueRow(
                        String(localized: "data_max_vtxo_exit_depth_label", defaultValue: "Max VTXO Exit Depth"),
                        value: "\(arkInfoData.maxVtxoExitDepth)"
                    )
                    LabeledValueRow(
                        String(localized: "data_ln_receive_antidos_label", defaultValue: "LN Receive Anti-DoS"),
                        value: arkInfoData.lnReceiveAntiDosRequired
                            ? String(localized: "data_value_required", defaultValue: "Required")
                            : String(localized: "data_value_not_required", defaultValue: "Not Required")
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if let error = error {
                ErrorBox(errorMessage: error)
            }
        }
        .padding(.horizontal)
        .task(id: reloadTrigger) {
            await loadArkInfoData()
        }
    }
    
    private func loadArkInfoData() async {
        isLoadingArkInfo = true
        error = nil
        
        print("loadArkInfoData")
        
        do {
            arkInfoData = try await walletManager.getArkInfo()
            print("arkInfoData: \(String(describing: arkInfoData))")
        } catch {
            self.error = error.localizedDescription
            arkInfoData = nil
        }
        
        isLoadingArkInfo = false
    }
}
