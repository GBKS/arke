//
//  RejoinWalletView.swift
//  Arké
//
//  Created by Assistant on 08/19/26.
//

import SwiftUI
import ArkeUI

/// Shown when this install deliberately deleted the wallet locally while the
/// wallet still lives on other devices of the same iCloud account.
///
/// The system allows exactly one wallet per iCloud account, so onboarding
/// (with its "Create wallet" path) must never be reachable here — creating
/// would overwrite the shared seed in iCloud Keychain account-wide. Rejoining
/// clears the local-deletion tombstone and re-runs wallet detection, which
/// finds the still-synced seed and restores the wallet on this device.
/// See Wallet_Deletion_And_Rejoin.md.
struct RejoinWalletView: View {
    /// Name of the device currently holding the primary role, for display
    let primaryDeviceName: String

    /// Called when the user chooses to rejoin; the owner clears the tombstone
    /// and re-runs detection
    let onRejoin: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            ArkeCircularIcon(icon: Image(systemName: "icloud"))
                .padding(.bottom, 8)

            Text(String(localized: "rejoin_title", defaultValue: "Your wallet is still active"))
                .font(.system(.title, design: .serif))
                .multilineTextAlignment(.center)

            Text(String(localized: "rejoin_message %@", defaultValue: "This iCloud account has a wallet on \(primaryDeviceName). You can rejoin it on this device. Creating a second wallet is not possible — each iCloud account holds one wallet."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
            
            ArkeGlassButton(
                String(localized: "rejoin_button", defaultValue: "Rejoin This Wallet"),
                action: onRejoin
            )
        }
        .padding(32)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RejoinWalletView(primaryDeviceName: "Christoph's iPhone") {}
}
