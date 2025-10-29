//
//  SendModalSendingView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/27/25.
//

import SwiftUI

struct SendModalSendingView: View {
    var body: some View {
        VStack(spacing: 25) {
            LoopingVideoPlayer.aspectFill(videoName: "coffee", videoExtension: "mp4")
                .frame(maxWidth: .infinity, minHeight: 250)
            
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Sending Payment")
                        .font(.system(size: 24, design: .serif))
                    
                    Text("Relax your mind and body.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .padding(.horizontal)
                }
            }
        }
        .padding(.bottom, 25)
    }
}

#Preview("Sending") {
    SendModalView(state: .sending)
        .frame(width: 400, height: 400)
}
