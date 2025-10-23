//
//  ActionButtonsView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/21/25.
//

import SwiftUI
import AppKit

struct ActionButtonsView: View {
    let selectedBalance: ReceiveView.BalanceType
    let shareContent: String?
    let hasQRContent: Bool
    let onShowQRCode: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Share button
            if let shareContent = shareContent {
                Button {
                    shareAction(content: shareContent)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                }
                .buttonStyle(ArkeButtonStyle(size: .medium))
                .controlSize(.large)
            }
            
            // QR Code button
            if hasQRContent {
                Button {
                    onShowQRCode()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "qrcode")
                    }
                }
                .buttonStyle(ArkeIconButtonStyle(size: .medium, variant: .ghost))
            }
        }
    }
    
    private func shareAction(content: String) {
        let sharingPicker = NSSharingServicePicker(items: [content])
        if let window = NSApp.keyWindow {
            sharingPicker.show(relativeTo: .zero, of: window.contentView ?? NSView(), preferredEdge: .maxY)
        }
    }
}
