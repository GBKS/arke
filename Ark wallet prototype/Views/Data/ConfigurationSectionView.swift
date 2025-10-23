//
//  ConfigurationSectionView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI

struct ConfigurationSectionView: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var configData: ArkConfigModel?
    @State private var isLoadingConfig = false
    @State private var error: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Configuration")
                    .font(.system(size: 24, design: .serif))
                
                Spacer()
                
                Button("Refresh") {
                    Task {
                        await loadConfigData()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingConfig)
            }
            
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
                    Text("No configuration data")
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
        .task {
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

#Preview {
    NavigationStack {
        ConfigurationSectionView()
            .environment(WalletManager(useMock: true))
            .padding(.vertical, 40)
            .padding(.horizontal, 20)
    }
}
