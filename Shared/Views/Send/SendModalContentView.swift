//
//  SendModalContentView.swift
//  Arké
//
//  Created by Claude on 6/24/26.
//

import SwiftUI
import SwiftData
import ArkeUI

struct SendModalContentView: View {
    let state: SendModalState
    @Binding var pendingMetadata: PendingPaymentMetadata?
    let onDismiss: () -> Void
    let onDismissEntireView: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 25) {
            // Video background based on state
            videoBackground
                .frame(maxWidth: .infinity, minHeight: 250)
            
            // Content based on state
            VStack(spacing: 15) {
                // Title
                Text(stateTitle)
                    .font(.system(size: 27, design: .serif))
                
                /*
                // Message
                if let message = stateMessage {
                    Text(message)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .padding(.horizontal)
                }
                 */
                
                // Error message (only for error state)
                if case .error(let errorMessage) = state {
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .padding(.horizontal)
                }
                
                // Metadata section
                if pendingMetadata != nil {
                    SendMetadataSection(pendingMetadata: $pendingMetadata)
                }
                
                // Action button (always visible unless error state)
                if case .error = state {
                    // Don't show the success button in error state
                } else {
                    Button {
                        onDismiss()
                        onDismissEntireView?()
                    } label: {
                        Text("button_done")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Color.Arke.gold4)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(.Arke.gold)
                    .disabled(!(state == .success))
                }
                
                // Dismiss button (only for error state)
                if case .error = state {
                    Button {
                        onDismiss()
                    } label: {
                        Text("button_cancel")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Color.Arke.gold4)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(.Arke.gold)
                }
            }
        }
        .padding(.bottom, 40)
    }
    
    // MARK: - State-based helpers
    
    @ViewBuilder
    private var videoBackground: some View {
        switch state {
        case .sending:
            #if os(iOS)
            LoopingVideoPlayer_iOS.aspectFill(videoName: "puppy-idle", videoExtension: "mp4")
            #elseif os(macOS)
            LoopingVideoPlayer.aspectFill(videoName: "puppy-idle", videoExtension: "mp4")
            #endif
            
        case .success:
            #if os(iOS)
            LoopingVideoPlayer_iOS.aspectFill(videoName: "puppy-thumbs-up", videoExtension: "mp4")
            #elseif os(macOS)
            LoopingVideoPlayer.aspectFill(videoName: "puppy-thumbs-up", videoExtension: "mp4")
            #endif
            
        case .error:
            // For now, use the same video as sending state
            // Phase 3b will add an error-specific video
            #if os(iOS)
            LoopingVideoPlayer_iOS.aspectFill(videoName: "puppy-idle", videoExtension: "mp4")
            #elseif os(macOS)
            LoopingVideoPlayer.aspectFill(videoName: "puppy-idle", videoExtension: "mp4")
            #endif
        }
    }
    
    private var stateTitle: LocalizedStringKey {
        switch state {
        case .sending:
            return "status_sending_payment"
        case .success:
            return "status_payment_sent"
        case .error:
            return "error_payment_failed"
        }
    }
    
    private var stateMessage: LocalizedStringKey? {
        switch state {
        case .sending:
            return "onboarding_relax"
        case .success:
            return "message_confirm_shortly"
        case .error:
            return nil // Error message comes from the error itself
        }
    }
}
