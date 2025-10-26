//
//  OnboardingView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

struct FirstUseView: View {
    let onCreateWallet: () -> Void
    let onImportWallet: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // Left column - Big image
            LoopingVideoPlayer(videoName: "cover-animation", videoExtension: "mp4")
                .frame(maxWidth: .infinity)
                .clipped()
            
            // Right column - Existing content
            VStack(spacing: 30) {
                VStack(spacing: 8) {
                    Text("Welcome to")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("Arké")
                        .font(.system(size: 80, design: .serif))
                        .fontWeight(.regular)
                        .foregroundStyle(Color.arkeGold)
                    
                    Text("A MacOS prototype for the Ark protocol implementation by second.tech. This is 110% alpha software using the bitcoin signet.")
                        .fontWeight(.light)
                        .font(.system(size: 21))
                        .lineSpacing(6)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                    
                    Text("More about second.tech")
                        .font(.system(size: 17))
                        .padding(.top, 16)
                        .foregroundStyle(Color.arkeGold)
                        .onTapGesture {
                            if let url = URL(string: "https://second.tech") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                }
                
                Spacer()
                
                VStack(spacing: 16) {
                    Button("Create new wallet") {
                        onCreateWallet()
                    }
                    .buttonStyle(ArkeButtonStyle(size: .large))
                    
                    Button("Import existing wallet") {
                        onImportWallet()
                    }
                    .buttonStyle(ArkeButtonStyle(size: .large, variant: .outline))
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color.arkeDark)
    }
}

#Preview {
    FirstUseView(
        onCreateWallet: {},
        onImportWallet: {}
    )
    .frame(width: 800, height: 600)
}
