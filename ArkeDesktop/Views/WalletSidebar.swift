//
//  WalletSidebar.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/7/25.
//

import SwiftUI
import ArkeUI

struct WalletSidebar: View {
    @Binding var selectedItem: NavigationItem
    @Environment(WalletManager.self) private var manager
    
    @State private var isBalanceHidden = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Balance Card at the top
            if let totalBalance = manager.totalBalance {
                BalanceCard(totalBalance: totalBalance, isHidden: $isBalanceHidden)
                    .onLongPressGesture(minimumDuration: 0.5) {
                        withAnimation(.snappy) {
                            isBalanceHidden.toggle()
                        }
                    }
                    .onTapGesture {
                        selectedItem = .balance
                    }
                    .padding()
            } else {
                SkeletonLoader(
                    itemCount: 1,
                    itemHeight: 150,
                    spacing: 10,
                    cornerRadius: 15
                )
                .padding()
            }
            
            // Navigation List
            List(NavigationItem.allCases, id: \.self, selection: $selectedItem) { item in
                if item != .balance {
                    // In read-only mode: hide Send (requires wallet)
                    // Keep Receive visible (addresses work via CloudKit, Lightning hidden in view)
                    if !manager.isReadOnlyMode || item != .send {
                        NavigationLink(value: item) {
                            Label(item.rawValue, systemImage: item.systemImage)
                                .font(.system(size: 15))
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "nav_title_wallet", defaultValue: "Wallet"))
    }
}
