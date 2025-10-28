//
//  SendModalSendingView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/27/25.
//

import SwiftUI

struct SendModalSendingView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                // Animated progress indicator
                ProgressView()
                    .scaleEffect(2)
                    .tint(.blue)
                
                VStack(spacing: 8) {
                    Text("Sending Payment")
                        .font(.title)
                        .fontWeight(.semibold)
                    
                    Text("Please wait while your transaction is being processed...")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

#Preview("Sending") {
    SendModalView(state: .sending)
}
