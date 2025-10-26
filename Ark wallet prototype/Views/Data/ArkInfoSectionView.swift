//
//  ArkInfoSectionView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI

struct ArkInfoSectionView: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var arkInfoData: ArkInfoModel?
    @State private var isLoadingArkInfo = false
    @State private var error: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Ark Info")
                    .font(.system(size: 24, design: .serif))
                
                Spacer()
                
                Button("Refresh") {
                    Task {
                        await loadArkInfoData()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingArkInfo)
            }
            
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
                    Text("No ark info data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if let arkInfoData = arkInfoData {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network: \(arkInfoData.network.uppercased())")
                    Text("Server: \(arkInfoData.serverPubkeyShort)")
                    Text("Round Interval: \(arkInfoData.roundInterval)")
                    Text("Max VTXO Amount: \(arkInfoData.maxVtxoAmountBTC.formatted(.number.precision(.fractionLength(8)))) BTC")
                    Text("Exit Delta: \(arkInfoData.vtxoExitDelta) blocks")
                    Text("Expiry Delta: \(arkInfoData.vtxoExpiryDelta) blocks")
                    Text("Board Confirmations: \(arkInfoData.requiredBoardConfirmations)")
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if let error = error {
                ErrorView(errorMessage: error)
            }
        }
        .task {
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

#Preview {
    NavigationStack {
        ArkInfoSectionView()
            .environment(WalletManager(useMock: true))
            .padding(.vertical, 40)
            .padding(.horizontal, 20)
    }
}
