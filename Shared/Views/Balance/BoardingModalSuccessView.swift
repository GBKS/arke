//
//  BoardingModalSuccessView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/19/25.
//

import SwiftUI
import ArkeUI

struct BoardingModalSuccessView: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 25) {
            #if os(iOS)
            LoopingVideoPlayer_iOS.aspectFill(videoName: "thumbs-up-animation", videoExtension: "mp4")
                .frame(maxWidth: .infinity, maxHeight: 250)
                .cornerRadius(25)
                .clipped()
            #elseif os(macOS)
            LoopingVideoPlayer.aspectFill(videoName: "thumbs-up-animation", videoExtension: "mp4")
                .frame(maxWidth: .infinity, maxHeight: 250)
                .cornerRadius(15)
                .clipped()
            #endif
            
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("status_transfer_initiated")
                        .font(.system(.title, design: .serif))
                    
                    Text(String(localized: "balance_transfer_ark_progress"))
                        .font(.title3)
                        .foregroundColor(.arkeSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                }
            }
            
            Button {
                onContinue()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 27))
                    .foregroundStyle(Color.Arke.gold4)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("button_done")
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Color.Arke.gold)
        }
        .padding()
    }
}
