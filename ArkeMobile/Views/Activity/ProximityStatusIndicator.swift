//
//  ProximityStatusIndicator.swift
//  Arké
//
//  Created by Christoph on 5/8/26.
//

import SwiftUI

/// Compact proximity status indicator with circular progress ring and icon
struct ProximityStatusIndicator: View {
    @ObservedObject var proximityManager: ProximityExchangeManager
    @State private var showText = false
    
    private let ringSize: CGFloat = 36
    private let lineWidth: CGFloat = 3
    
    var body: some View {
        VStack(spacing: 6) {
            // Progress ring with icon
            ZStack {
                // Background ring (dimmed)
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: lineWidth)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: progressValue)
                    .stroke(
                        Color.white,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progressValue)
                
                // Icon with pulsating opacity for discovering state
                Image(systemName: statusIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white)
                    .id(statusIcon) // Force recreation when icon changes
                    .modifier(PulsatingOpacityModifier(isDiscovering: proximityManager.state == .discovering))
            }
            .frame(width: ringSize, height: ringSize)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showText.toggle()
                }
            }
            
            // Status text - only visible when toggled. Kept hidden at rest so the
            // indicator stays minimal for this secondary feature. On error, tapping the
            // revealed text opens Settings (e.g. to grant Local Network access).
            if showText {
                Text(statusText)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .onTapGesture {
                        if case .error = proximityManager.state {
                            proximityManager.openAppSettings()
                        }
                    }
            }
        }
    }
    
    // MARK: - Status Properties
    
    /// Progress value for the circular ring (0.0 to 1.0)
    private var progressValue: CGFloat {
        switch proximityManager.state {
        case .idle, .awaitingPermission:
            return 0.0
        case .discovering:
            return 0.0
        case .peerFound:
            return 0.25
        case .proximityMet:
            return 0.5
        case .exchanging:
            return 0.75
        case .complete:
            return 1.0
        case .error:
            return 0.0
        }
    }
    
    /// Icon opacity for pulsating effect
    private var iconOpacity: Double {
        proximityManager.state == .discovering ? 0.5 : 1.0
    }
    
    /// Icon representing the current proximity state
    private var statusIcon: String {
        switch proximityManager.state {
        case .idle:
            return "moon.zzz"
        case .awaitingPermission:
            return "hand.raised"
        case .discovering:
            return "antenna.radiowaves.left.and.right"
        case .peerFound:
            return "person.wave.2"
        case .proximityMet:
            return "arrow.left.and.right"
        case .exchanging:
            return "arrow.triangle.2.circlepath"
        case .complete:
            return "checkmark"
        case .error:
            return "exclamationmark"
        }
    }
    

    /// Text describing the current proximity state
    private var statusText: String {
        switch proximityManager.state {
        case .idle:
            return "Idle"
        case .awaitingPermission:
            return "Awaiting Permission"
        case .discovering:
            // Surface a radio-environment hint here when one applies, otherwise the
            // normal searching message.
            return proximityManager.environmentWarning ?? "Looking for nearby devices..."
        case .peerFound(let peerName):
            return "Found: \(peerName)"
        case .proximityMet:
            return "Proximity met"
        case .exchanging:
            return "Exchanging info..."
        case .complete(_, let peerName):
            return "Received from \(peerName)"
        case .error(let message):
            // The exclamation icon already conveys the error; show the guidance directly.
            return message
        }
    }
}
// MARK: - Pulsating Opacity Modifier

/// ViewModifier that applies a pulsating opacity animation
private struct PulsatingOpacityModifier: ViewModifier {
    let isDiscovering: Bool
    @State private var opacity: Double = 1.0
    
    func body(content: Content) -> some View {
        content
            .opacity(isDiscovering ? opacity : 1.0)
            .onAppear {
                if isDiscovering {
                    startPulsating()
                }
            }
            .onChange(of: isDiscovering) { _, newValue in
                if newValue {
                    startPulsating()
                } else {
                    opacity = 1.0
                }
            }
    }
    
    private func startPulsating() {
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            opacity = 0.5
        }
    }
}

