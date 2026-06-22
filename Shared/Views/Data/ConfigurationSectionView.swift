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
            Text("data_configuration")
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
                    Text("data_no_configuration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if let configData = configData {
                Text(configData.configurationSummary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
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
