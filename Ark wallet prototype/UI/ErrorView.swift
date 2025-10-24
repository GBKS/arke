//
//  ErrorView.swift
//  Ark wallet prototype
//
//  Created by Assistant on 10/24/25.
//

import SwiftUI
import AppKit

struct ErrorView: View {
    let errorMessage: String
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void
    
    @State private var showCopyConfirmation = false
    
    init(
        errorMessage: String,
        onRetry: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.errorMessage = errorMessage
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image("error")
                .resizable()
                .frame(width: 50, height: 50)
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 6) {
                
                HStack(spacing: 8) {
                    Text("Something went wrong")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Spacer()
                    
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss error")
                }
                
                Text(errorMessage)
                    .font(.body)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
                
                HStack(spacing: 12) {
                    Button("Copy Error") {
                        copyErrorToClipboard()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                    
                    if let onRetry = onRetry {
                        Button("Retry") {
                            onRetry()
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.caption)
                    }
                    
                    Spacer()
                    
                    if showCopyConfirmation {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("Copied")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(.top, 5)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.red.opacity(0.05))
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: showCopyConfirmation)
    }
    
    private func copyErrorToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(errorMessage, forType: .string)
        
        // Show confirmation
        showCopyConfirmation = true
        
        // Hide confirmation after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopyConfirmation = false
        }
    }
}

// MARK: - Preview

#Preview("Error with Retry") {
    VStack(spacing: 20) {
        ErrorView(
            errorMessage: "Failed to send transaction: Insufficient funds available. Please check your balance and try again.",
            onRetry: {
                print("Retry tapped")
            },
            onDismiss: {
                print("Dismiss tapped")
            }
        )
        
        ErrorView(
            errorMessage: "Network connection failed",
            onDismiss: {
                print("Dismiss tapped")
            }
        )
        
        Spacer()
    }
    .padding()
    .frame(maxWidth: 400)
}
