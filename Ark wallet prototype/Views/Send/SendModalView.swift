//
//  SendModalView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/20/25.
//

import SwiftUI

enum SendModalState {
    case sending
    case success
    case error(String)
}

struct SendModalView: View {
    let state: SendModalState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        switch state {
        case .sending:
            SendModalSendingView()
        case .success:
            SendModalSuccessView {
                dismiss()
            }
        case .error(let errorMessage):
            SendModalErrorView(errorMessage: errorMessage) {
                dismiss()
            }
        }
    }
}

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

#Preview("Sending") {
    SendModalView(state: .sending)
}

#Preview("Success") {
    SendModalView(state: .success)
}

#Preview("Error") {
    SendModalView(state: .error("Network connection failed. Please check your internet connection and try again."))
}
