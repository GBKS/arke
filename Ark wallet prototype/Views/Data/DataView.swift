//
//  DataView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

enum VTXOError: Error, LocalizedError {
    case walletNotAvailable
    case parsingFailed
    
    var errorDescription: String? {
        switch self {
        case .walletNotAvailable:
            return "Wallet not available"
        case .parsingFailed:
            return "Failed to parse VTXO data"
        }
    }
}

struct DataView: View {
    @Binding var selectedDataItem: DataDetailItem?
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                ArkBalanceView()
                
                OnchainBalanceView()
                
                VTXOListView(selectedDataItem: $selectedDataItem)
                
                UTXOListView(selectedDataItem: $selectedDataItem)
                
                ConfigurationSectionView()
                
                ArkInfoSectionView()
                
                BlockHeightSectionView()
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 30)
            .navigationTitle("Your wallet in-depth")
        }
    }
}

#Preview {
    NavigationStack {
        DataView(selectedDataItem: .constant(nil))
            .environment(WalletManager(useMock: true))
    }
    .frame(width: 400, height: 800)
}
