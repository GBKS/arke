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
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "format_network", defaultValue: "Network: \(arkInfoData.network.uppercased())"))
                    Text(String(localized: "data_server", defaultValue: "Server: \(arkInfoData.serverPubkeyShort)"))
                    Text(String(localized: "data_round_interval", defaultValue: "Round Interval: \(arkInfoData.roundInterval)"))
                    Text(String(localized: "data_round_nonces", defaultValue: "Round Nonces: \(arkInfoData.nbRoundNonces)"))
                    if let maxVtxoAmountBTC = arkInfoData.maxVtxoAmountBTC {
                        Text(String(localized: "data_max_vtxo_amount", defaultValue: "Max VTXO Amount: \(maxVtxoAmountBTC.formatted(.number.precision(.fractionLength(8)))) BTC"))
                    } else {
                        Text("data_max_vtxo_not_set")
                    }
                    Text(String(localized: "data_min_board_amount", defaultValue: "Min Board Amount: \(arkInfoData.minBoardAmountBTC.formatted(.number.precision(.fractionLength(8)))) BTC"))
                    Text(String(localized: "data_vtxo_exit_delta", defaultValue: "VTXO Exit Delta: \(arkInfoData.vtxoExitDelta) blocks"))
                    Text(String(localized: "data_vtxo_expiry_delta", defaultValue: "VTXO Expiry Delta: \(arkInfoData.vtxoExpiryDelta) blocks"))
                    Text(String(localized: "data_htlc_send_expiry_delta", defaultValue: "HTLC Send Expiry Delta: \(arkInfoData.htlcSendExpiryDelta) blocks"))
                    Text(String(localized: "data_htlc_expiry_delta", defaultValue: "HTLC Expiry Delta: \(arkInfoData.htlcExpiryDelta) blocks"))
                    Text(String(localized: "data_max_user_invoice_cltv", defaultValue: "Max User Invoice CLTV Delta: \(arkInfoData.maxUserInvoiceCltvDelta) blocks"))
                    Text(String(localized: "balance_board_confirmations", defaultValue: "Board Confirmations: \(arkInfoData.requiredBoardConfirmations)"))
                    Text(String(localized: "data_max_vtxo_exit_depth", defaultValue: "Max VTXO Exit Depth: \(arkInfoData.maxVtxoExitDepth)"))
                    Text(String(localized: "data_ln_receive_antidos", defaultValue: "LN Receive Anti-DoS: \(arkInfoData.lnReceiveAntiDosRequired ? "Required" : "Not Required")"))
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
