//
//  WalletActiveElsewhereView_iOS.swift
//  Arké
//
//  Created by Claude on 2026-05-07.
//

import SwiftUI
import ArkeUI

struct WalletActiveElsewhereView_iOS: View {
    let primaryDeviceName: String
    let onMigrateToThisDevice: () -> Void
    
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background video covering entire view
            LoopingVideoPlayer_iOS(videoName: "cover-animation", videoExtension: "mp4")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
            
            // Content overlaid at bottom
            VStack(spacing: 30) {
                VStack(spacing: 16) {
                    Image(systemName: "lock.iphone")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.Arke.gold)
                    
                    Text("Wallet Active on Another Device")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("Your wallet is currently active on **\(primaryDeviceName)**. Only one device can be active at a time.")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 20)
                }
                
                VStack(spacing: 16) {
                    Button {
                        onMigrateToThisDevice()
                    } label: {
                        Text("Make This Device Active")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Color.Arke.gold3)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(Color.Arke.gold)
                    
                    Text("This will deactivate your wallet on \(primaryDeviceName)")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 50)
            .frame(maxWidth: .infinity)
        }
        .colorScheme(.dark)
        .background(Color.Arke.gold3)
        .safeAreaPadding([.top, .bottom])
    }
}
