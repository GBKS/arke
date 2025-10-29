//
//  Ark_wallet_prototypeApp.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import SwiftData

@main
struct Ark_wallet_prototypeApp: App {
    @State private var walletManager = WalletManager()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(walletManager)
        }
        .defaultSize(width: 800, height: 600)
        .windowResizability(.contentMinSize)
        .modelContainer(for: [TransactionModel.self, PersistedArkBalance.self, PersistedOnchainBalance.self])
    }
}
