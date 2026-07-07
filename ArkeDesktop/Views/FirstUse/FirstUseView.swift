//
//  OnboardingView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI
import ArkeUI

struct FirstUseView: View {
    let onCreateWallet: () -> Void
    let onImportWallet: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            VStack {
                // Left column - Big video
                 LoopingVideoPlayer(videoName: "cover-animation", videoExtension: "mp4")
                     .frame(maxWidth: .infinity)
                     .clipped()
            }
            .frame(maxWidth: .infinity)
            
            // Right column - Existing content
            VStack(spacing: 30) {
                VStack(spacing: 8) {
                    Text("firstuse_welcome_to")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("app_name")
                        .font(.system(size: 80, design: .serif))
                        .fontWeight(.regular)
                        .foregroundStyle(Color.Arke.gold)
                    
                    Text("firstuse_welcome_description")
                        .fontWeight(.light)
                        .font(.system(size: 21))
                        .lineSpacing(6)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                    
                    Text("firstuse_more_about")
                        .font(.system(size: 17))
                        .padding(.top, 16)
                        .foregroundStyle(Color.Arke.gold)
                        .onTapGesture {
                            if let url = URL(string: "https://second.tech") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                }
                
                Spacer()
                
                VStack(spacing: 16) {
                    Button("button_create_wallet") {
                        onCreateWallet()
                    }
                    .buttonStyle(ArkeButtonStyle(size: .large))

                    Button("action_import_wallet") {
                        onImportWallet()
                    }
                    .buttonStyle(ArkeButtonStyle(size: .large, variant: .outline))
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity)
        }
        .background(Color.Arke.gold4)
    }
}
