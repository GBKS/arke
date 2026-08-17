//
//  ActionButtonsView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/21/25.
//

import SwiftUI
import ArkeUI

struct ActionButtonsView: View {
    let selectedBalance: ReceiveBalanceType
    let shareContent: String?
    let hasQRContent: Bool
    let onShowQRCode: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            // Share button
            if let shareContent = shareContent {
                ShareLink(item: shareContent) {
                    Text(L10n.buttonShare)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.Arke.gold4)
                        .padding(.horizontal, 40)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
                .tint(Color.Arke.gold)
            }
            
            // QR Code button
            if hasQRContent {
                Button {
                    onShowQRCode()
                } label: {
                    Image(systemName: "qrcode")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.Arke.gold4)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
                .tint(Color.Arke.gold)
                .accessibilityLabel(L10n.buttonBack)
            }
        }
    }
}
