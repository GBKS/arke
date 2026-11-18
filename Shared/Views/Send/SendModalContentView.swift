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

    // Picked once per modal presentation so the character stays
    // consistent across the sending/success/error states
    @State private var videoPair = ReactionVideoPair.random()
    
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
                
                // Error message (error and unconfirmed states)
                if let errorMessage = stateErrorMessage {
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
                
                // Action button (always visible unless error or unconfirmed state)
                if stateErrorMessage != nil {
                    // Don't show the success button in error state
                } else {
                    Button {
                        onDismiss()
                        onDismissEntireView?()
                    } label: {
                        Text(L10n.buttonDone)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Color.Arke.gold4)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(.Arke.gold)
                    .disabled(!(state == .success))
                }
                
                // Dismiss button (error and unconfirmed states)
                if stateErrorMessage != nil {
                    Button {
                        onDismiss()
                    } label: {
                        Text(L10n.buttonCancel)
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
    
    /// The message under the title for the two terminal states that are not a success
    private var stateErrorMessage: String? {
        switch state {
        case .error(let message), .unconfirmed(let message):
            return message
        case .sending, .success:
            return nil
        }
    }
    
    @ViewBuilder
    private var videoBackground: some View {
        // Top-aligned so the character's head survives the crop when the
        // container is shorter than the video's aspect-fill height
        #if os(iOS)
        LoopingVideoPlayer_iOS.aspectFill(videoName: stateVideoName, videoExtension: "mp4", alignment: .top)
        #elseif os(macOS)
        LoopingVideoPlayer.aspectFill(videoName: stateVideoName, videoExtension: "mp4", alignment: .top)
        #endif
    }

    private var stateVideoName: String {
        switch state {
        case .sending:
            return videoPair.idle
        case .success:
            return videoPair.thumbsUp
        case .error, .unconfirmed:
            // For now, use the same video as sending state
            // Phase 3b will add an error-specific video
            return videoPair.idle
        }
    }
    
    private var stateTitle: String {
        switch state {
        case .sending:
            return String(localized: "status_sending_payment", defaultValue: "Sending Payment")
        case .success:
            return String(localized: "status_payment_sent", defaultValue: "Payment Sent")
        case .error:
            return String(localized: "error_payment_failed", defaultValue: "Payment Failed")
        case .unconfirmed:
            return String(localized: "status_payment_not_confirmed", defaultValue: "Payment Not Confirmed")
        }
    }
    
    private var stateMessage: String? {
        switch state {
        case .sending:
            return String(localized: "onboarding_relax", defaultValue: "Relax your mind and body.")
        case .success:
            return String(localized: "message_confirm_shortly", defaultValue: "It will be confirmed shortly.")
        case .error, .unconfirmed:
            return nil // Error message comes from the error itself
        }
    }
}
