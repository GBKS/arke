//
//  RefreshModalSuccessView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/24/25.
//

import SwiftUI
import ArkeUI

struct RefreshModalSuccessView: View {
    /// Headline and body vary by outcome — a newly scheduled refresh and one
    /// that was already under way are both successes, but only one of them
    /// started something (see `ManualRefreshOutcome`).
    var title: String = String(localized: "status_refresh_started", defaultValue: "Refresh started")
    var message: String = String(localized: "balance_refresh_background", defaultValue: "You can close this modal and the refresh will continue in the background.")
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
                    Text(title)
                        .font(.system(.title, design: .serif))

                    Text(message)
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
                        .foregroundStyle(Color.Arke.gold4)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(L10n.buttonDone)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(Color.Arke.gold)
            }
        }
        .padding()
    }
}
