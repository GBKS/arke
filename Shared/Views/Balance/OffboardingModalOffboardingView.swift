//
//  OffboardingModalOffboardingView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/12/25.
//

import SwiftUI

struct OffboardingModalOffboardingView: View {
    var body: some View {
        VStack(spacing: 25) {
            #if os(iOS)
            LoopingVideoPlayer_iOS.aspectFill(videoName: "coffee", videoExtension: "mp4")
                .frame(maxWidth: .infinity, maxHeight: 250)
                .cornerRadius(25)
                .clipped()
            #elseif os(macOS)
            LoopingVideoPlayer.aspectFill(videoName: "coffee", videoExtension: "mp4")
                .frame(maxWidth: .infinity, maxHeight: 250)
                .cornerRadius(15)
                .clipped()
            #endif
            
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(String(localized: "status_preparing_transfer", defaultValue: "Preparing Transfer"))
                        .font(.system(.title, design: .serif))
                    
                    Text(String(localized: "status_may_take_moment", defaultValue: "This may take a moment..."))
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .padding(.horizontal)
                }
            }
        }
        .padding()
    }
}
