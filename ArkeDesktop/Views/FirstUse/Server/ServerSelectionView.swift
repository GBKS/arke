//
//  ServerSelectionView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/25/25.
//

import SwiftUI
import ArkeUI

struct ServerSelectionView: View {
    let onBack: (ServerUsageProfile) -> Void
    let onServerSelected: () -> Void
    let usagePattern: ServerUsageProfile?
    
    @State private var selectedServer: ServerFeeConfig?
    @State private var selectedProfile: ServerUsageProfile = .casual
    @State private var comparisons: [ServerComparison] = []
    
    // Define available servers
    private let availableServers: [ServerFeeConfig] = [
        ServerFeeConfig(
            id: "second",
            name: "Second",
            logoImage: "second",
            refreshFeeModel: .percentage(annualRate: 0.03),
            expiryDays: 30,
            lightningBaseFee: 0,
            lightningPPM: 500,
            freeRefreshWindowDays: nil,
            websiteURL: URL(string: "https://second.tech")!,
            serverURL: URL(string: "https://ark.signet.2nd.dev/")!,
            enabled: true
        ),
        ServerFeeConfig(
            id: "kinto",
            name: "Kinto",
            logoImage: "kinto",
            refreshFeeModel: .absolute(sats: 50),
            expiryDays: 14,
            lightningBaseFee: 1,
            lightningPPM: 1000,
            freeRefreshWindowDays: 3,
            websiteURL: URL(string: "https://www.kinto.com")!,
            serverURL: URL(string: "https://ark.kinto.com")!,
            enabled: true
        ),
        ServerFeeConfig(
            id: "bodega",
            name: "Bodega",
            logoImage: "bodega",
            refreshFeeModel: .tiered(annualRate: 0.015, minimumSats: 25),
            expiryDays: 45,
            lightningBaseFee: 2,
            lightningPPM: 1500,
            freeRefreshWindowDays: 7,
            websiteURL: URL(string: "https://www.bodega.com")!,
            serverURL: URL(string: "https://ark.bodega.com")!,
            enabled: true
        )
    ]
    
    private let calculator = ArkFeeCalculator()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Top navigation area
                HStack {
                    Button {
                        onBack(selectedProfile)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.Arke.gold)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                
                VStack(spacing: 8) {
                    Text("Select a Server")
                        .font(.system(size: 30, design: .serif))
                        .foregroundStyle(Color.Arke.gold)
                    
                    Text("They route your payments for safe and fast transactions. Fees are based on usage.")
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                
                // Usage profile selector
                ServerUsageProfilePicker(
                    selectedProfile: $selectedProfile,
                    customProfile: usagePattern
                )
                .frame(maxWidth: 600)
                .onChange(of: selectedProfile) {
                    updateComparisons()
                }
                
                // Server list
                VStack(spacing: 16) {
                    ForEach(comparisons, id: \.server.id) { comparison in
                        ServerCard(
                            comparison: comparison,
                            isSelected: selectedServer?.id == comparison.server.id,
                            onSelect: {
                                selectedServer = comparison.server
                            }
                        )
                    }
                }
                .animation(.smooth(duration: 0.4), value: comparisons.map { $0.server.id })
                .padding(.vertical, 8)
                .frame(maxWidth: 600)
                
                Button("Continue") {
                    onServerSelected()
                }
                .buttonStyle(ArkeButtonStyle(size: ArkeButtonSize.large))
                .disabled(selectedServer == nil)
                .opacity(selectedServer == nil ? 0.5 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Arke.gold3)
        .onAppear {
            // If custom usage pattern is provided, use it directly
            if let pattern = usagePattern {
                selectedProfile = pattern
            }
            updateComparisons()
            // Select the "second" server by default
            if selectedServer == nil {
                selectedServer = availableServers.first { $0.id == "second" }
            }
        }
    }
    
    private func updateComparisons() {
        comparisons = calculator.compareServers(
            servers: availableServers,
            profile: selectedProfile
        )
    }
}
