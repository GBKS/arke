//
//  ClaimableExitView.swift
//  Arké
//
//  Created by Christoph on 1/7/26.
//

import SwiftUI
import ArkeUI
import Bark

struct ClaimableExitView_iOS: View {
    let exit: ExitVtxo
    let isProcessing: Bool
    let onClaim: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            #if os(iOS)
            GeometryReader { geometry in
                LoopingVideoPlayer_iOS.aspectFill(videoName: "tai-chi-seated", videoExtension: "mp4")
                    .frame(width: geometry.size.width, height: 250)
                    .cornerRadius(25)
                    .clipped()
            }
            .frame(height: 250)
            #elseif os(macOS)
            GeometryReader { geometry in
                LoopingVideoPlayer.aspectFill(videoName: "tai-chi-seated", videoExtension: "mp4")
                    .frame(width: geometry.size.width, height: 250)
                    .cornerRadius(25)
                    .clipped()
            }
            .frame(height: 250)
            #endif
            
            Text("action_withdraw_bitcoin")
                .font(.system(.title, design: .serif))
            
            // Amount
            VStack(spacing: 8) {
                Text("label_amount")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Text(exit.formattedAmount)
                    .font(.title)
                    .fontWeight(.bold)
            }
            
            Text(String(localized: "balance_add_to_savings"))
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Claim button
            Button {
                onClaim()
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 27))
                    .foregroundStyle(Color.Arke.gold2)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Color.Arke.gold)
            .accessibilityLabel("button_start_withdrawal")
            .disabled(isProcessing)
            
            Spacer()
        }
    }
}
