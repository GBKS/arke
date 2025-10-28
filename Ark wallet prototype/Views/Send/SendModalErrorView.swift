//
//  SendModalErrorView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/27/25.
//

import SwiftUI

struct SendModalErrorView: View {
    let errorMessage: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                // Large red X or warning icon
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                
                VStack(spacing: 8) {
                    Text("Payment Failed")
                        .font(.title)
                        .fontWeight(.semibold)
                    
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            Spacer()
            
            Button("Try Again") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

#Preview("Error") {
    SendModalView(state: .error("Network connection failed. Please check your internet connection and try again."))
}
