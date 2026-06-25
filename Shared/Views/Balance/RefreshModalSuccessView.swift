//
//  RefreshModalSuccessView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/24/25.
//

import SwiftUI
import ArkeUI

struct RefreshModalSuccessView: View {
    let onDone: () -> Void
    
    var body: some View {
        VStack(spacing: 25) {
            #if os(iOS)
            LoopingVideoPlayer_iOS.aspectFill(videoName: "poolside-pose", videoExtension: "mp4")
                .frame(maxWidth: .infinity, maxHeight: 250)
                .cornerRadius(25)
                .clipped()
            #elseif os(macOS)
            LoopingVideoPlayer.aspectFill(videoName: "poolside-pose", videoExtension: "mp4")
                .frame(maxWidth: .infinity, maxHeight: 250)
                .cornerRadius(15)
                .clipped()
            #endif
            
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("status_refresh_started")
                        .font(.system(.title, design: .serif))
                    
                    Text(String(localized: "balance_refresh_background"))
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                }
            
                Button {
                    onDone()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 27))
                        .foregroundStyle(Color.Arke.gold3)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("button_done")
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(Color.Arke.gold)
            }
        }
        .padding()
    }
}
