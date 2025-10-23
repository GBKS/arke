//
//  OnboardingView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/16/25.
//

import SwiftUI

extension Color {
    init(r: Double, g: Double, b: Double) {
        self.init(red: r/255, green: g/255, blue: b/255)
    }
    
    static let gold = Color(r: 255, g: 215, b: 0)
}

struct FirstUseView: View {
    let onWalletCreated: () -> Void
    
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
                        .fontWeight(.regular)
                        .font(.system(size: 80, design: .serif))
                        .foregroundStyle(Color(r: 248, g: 209, b: 117))
                    
                    Text("A MacOS prototype for the Ark protocol implementation by second.tech. This is 110% alpha software using the bitcoin signet.")
                        .fontWeight(.light)
                        .font(.system(size: 21))
                        .lineSpacing(4)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                    
                    Text("More about second.tech")
                        .font(.system(size: 17))
                        .padding(.top, 16)
                        .foregroundStyle(Color(r: 248, g: 209, b: 117))
                        .onTapGesture {
                            if let url = URL(string: "https://second.tech") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                }
                
                Spacer()
                
                VStack(spacing: 16) {
                    Button("Create new wallet") {
                        // Handle wallet creation
                        onWalletCreated()
                    }
                    .foregroundStyle(Color(r: 41, g: 20, b: 0))
                    .fontWeight(.semibold)
                    .font(.system(size: 17))
                    .padding(.horizontal, 25)
                    .padding(.vertical, 12)
                    .background(Color(r: 248, g: 209, b: 117))
                    .cornerRadius(25)
                    .buttonStyle(.plain)
                    
                    Button("Import existing wallet") {
                        // Handle wallet import
                        onWalletCreated()
                    }
                    .foregroundStyle(Color(r: 248, g: 209, b: 117))
                    .fontWeight(.semibold)
                    .font(.system(size: 17))
                    .padding(.horizontal, 25)
                    .padding(.vertical, 12)
                    .background(.clear)
                    .cornerRadius(25)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color(r: 248, g: 209, b: 117), lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(r: 23, g: 11, b: 0))
    }
}

#Preview {
    FirstUseView {
        // Preview action - no actual functionality needed
    }
    .frame(width: 800, height: 600)
}
