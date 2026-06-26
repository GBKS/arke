//
//  SendModalSuccessView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI
import ArkeUI

struct SendModalSuccessView: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 25) {
            #if os(iOS)
            LoopingVideoPlayer_iOS.aspectFill(videoName: "puppy-thumbs-up", videoExtension: "mp4")
                .frame(maxWidth: .infinity, minHeight: 250)
            #elseif os(macOS)
            LoopingVideoPlayer.aspectFill(videoName: "puppy-thumbs-up", videoExtension: "mp4")
                .frame(maxWidth: .infinity, minHeight: 250)
            #endif
            
            VStack(spacing: 15) {
                VStack(spacing: 8) {
                    Text("status_payment_sent")
                        .font(.system(size: 24, design: .serif))
                    
                    Text(String(localized: "message_confirm_shortly"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                }
                
                Button {
                    onContinue()
                } label: {
                    Text("button_done")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.Arke.gold4)
                        .padding(.horizontal, 20)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(.Arke.gold)
            }
        }
        .padding(.bottom, 25)
    }
}
