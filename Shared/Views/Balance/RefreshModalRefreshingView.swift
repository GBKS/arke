//
//  RefreshModalRefreshingView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/24/25.
//

import SwiftUI

struct RefreshModalRefreshingView: View {
    var onCancel: () -> Void = {}
    
    var body: some View {
        VStack(spacing: 25) {
            #if os(iOS)
            LoopingVideoPlayer_iOS.aspectFill(videoName: "poolside", videoExtension: "mp4")
                .frame(maxWidth: .infinity, maxHeight: 250)
                .cornerRadius(25)
                .clipped()
            #elseif os(macOS)
            LoopingVideoPlayer.aspectFill(videoName: "poolside", videoExtension: "mp4")
                .frame(maxWidth: .infinity, maxHeight: 250)
                .cornerRadius(15)
                .clipped()
            #endif
            
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("status_refreshing_balance")
                        .font(.system(.title, design: .serif))
                    
                    Text(String(localized: "onboarding_get_excited"))
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                }
                
                /*
                Button {
                    onCancel()
                } label: {
                    Text("button_cancel")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.Arke.gold3)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .tint(Color.Arke.gold)
                */
            }
        }
        .padding()
    }
}
