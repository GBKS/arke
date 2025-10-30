//
//  WalletView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import SwiftData

enum NavigationItem: String, CaseIterable {
    case balance = "Balancé"
    case activity = "Activité"
    case send = "Sénd"
    case receive = "Réceive"
    case tags = "Tags"
    case settings = "Séttings"
    case data = "X-Ráy"
    
    var systemImage: String {
        switch self {
        case .balance: return "list.bullet"
        case .activity: return "list.bullet"
        case .send: return "arrow.up.circle.fill"
        case .receive: return "arrow.down.circle.fill"
        case .tags: return "arrow.down.circle.fill"
        case .settings: return "gearshape.fill"
        case .data: return "doc.text.fill"
        }
    }
}

// Enum to represent the selected item in the data view
enum DataDetailItem: Hashable {
    case vtxo(VTXOModel)
    case utxo(UTXOModel)
}

struct WalletSidebar: View {
    @Binding var selectedItem: NavigationItem
    @Environment(WalletManager.self) private var manager
    
    var body: some View {
        VStack(spacing: 0) {
            // Balance Card at the top
            if let totalBalance = manager.totalBalance {
                Button {
                    selectedItem = .balance
                } label: {
                    BalanceCard(totalBalance: totalBalance)
                }
                .buttonStyle(.plain)
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
                if(item != .balance) {
                    NavigationLink(value: item) {
                        Label(item.rawValue, systemImage: item.systemImage)
                            .font(.system(size: 15))
                    }
                }
            }
        }
        .navigationTitle("Wallet")
    }
}

struct WalletView: View {
    @State private var selectedItem: NavigationItem = .activity
    @State private var selectedTransaction: TransactionModel?
    @State private var selectedDataItem: DataDetailItem?
    @Environment(WalletManager.self) private var manager
    
    let onWalletDeleted: (() -> Void)?
    
    var body: some View {
        if selectedItem == .activity {
            // Three-column layout for activity view
            NavigationSplitView {
                // Sidebar
                WalletSidebar(selectedItem: $selectedItem)
                    .navigationSplitViewColumnWidth(min: 250, ideal: 250)
            } content: {
                ActivityView(selectedTransaction: $selectedTransaction)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 500)
            } detail: {
                if let transaction = selectedTransaction {
                    TransactionDetailView(transaction: transaction)
                        .navigationSplitViewColumnWidth(min: 250, ideal: 250)
                } else {
                    ContentUnavailableView {
                        VStack(spacing: 15) {
                            Image(systemName: "list.bullet")
                                .imageScale(.medium)
                                .symbolVariant(.none)
                            Text("Select a transaction")
                                .font(.system(size: 19, design: .serif))
                        }
                    }
                }
            }
        } else if selectedItem == .data {
            // Three-column layout for data view
            NavigationSplitView {
                // Sidebar
                WalletSidebar(selectedItem: $selectedItem)
                    .navigationSplitViewColumnWidth(min: 250, ideal: 250)
            } content: {
                DataView(selectedDataItem: $selectedDataItem)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 300)
            } detail: {
                if let dataItem = selectedDataItem {
                    switch dataItem {
                    case .vtxo(let vtxo):
                        VTXODetailView(vtxo: vtxo)
                            .navigationSplitViewColumnWidth(min: 250, ideal: 250)
                    case .utxo(let utxo):
                        UTXODetailView(utxo: utxo)
                            .navigationSplitViewColumnWidth(min: 250, ideal: 250)
                    }
                } else {
                    ContentUnavailableView {
                        VStack(spacing: 15) {
                            Image(systemName: "list.bullet")
                                .imageScale(.medium)
                                .symbolVariant(.none)
                            Text("Select a VTXO or UTXO")
                                .font(.system(size: 19, design: .serif))
                        }
                    }
                }
            }
        } else {
            // Two-column layout for other views
            NavigationSplitView {
                // Sidebar
                WalletSidebar(selectedItem: $selectedItem)
                    .navigationSplitViewColumnWidth(min: 250, ideal: 250)
            } detail: {
                // Content view for non-activity items
                switch selectedItem {
                case .balance:
                    BalanceView()
                case .send:
                    SendView()
                case .receive:
                    ReceiveView()
                case .tags:
                    TagsView()
                case .settings:
                    SettingsView(onWalletDeleted: onWalletDeleted)
                case .data:
                    EmptyView() // This case shouldn't be reached now
                case .activity:
                    EmptyView() // This case shouldn't be reached
                }
            }
        }
    }
}



#Preview {
    WalletView(onWalletDeleted: nil)
        .environment(WalletManager(useMock: true))
        .modelContainer(for: [TransactionModel.self, ArkBalanceModel.self], inMemory: true)
}
