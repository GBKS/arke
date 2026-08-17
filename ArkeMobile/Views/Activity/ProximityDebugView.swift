//
//  ProximityDebugView.swift
//  Arké
//
//  Created by Christoph on 5/8/26.
//

import SwiftUI

/// Debug view showing proximity detection state information
struct ProximityDebugView: View {
    @ObservedObject var proximityManager: ProximityExchangeManager
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.5))
            .cornerRadius(12)
            
            // Show browsing/advertising status
            if proximityManager.isBrowsing || proximityManager.isAdvertising {
                HStack(spacing: 8) {
                    if proximityManager.isAdvertising {
                        HStack(spacing: 3) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.caption2)
                            Text(String(localized: "activity_advertising", defaultValue: "Advertising"))
                                .font(.caption2)
                        }
                    }
                    if proximityManager.isBrowsing {
                        HStack(spacing: 3) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption2)
                            Text(String(localized: "activity_browsing", defaultValue: "Browsing"))
                                .font(.caption2)
                        }
                    }
                    if !proximityManager.discoveredPeers.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .font(.caption2)
                            Text("\(proximityManager.discoveredPeers.count)")
                                .font(.caption2)
                        }
                    }
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
            }
            
            if let detailText = statusDetailText {
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Status Properties
    
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
            return "arrow.left.arrow.right"
        case .complete:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
    
    /// Color representing the current proximity state
    private var statusColor: Color {
        switch proximityManager.state {
        case .idle, .awaitingPermission:
            return .gray
        case .discovering:
            return .blue
        case .peerFound, .proximityMet:
            return .orange
        case .exchanging:
            return .yellow
        case .complete:
            return .green
        case .error:
            return .red
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
            return "Looking for nearby devices..."
        case .peerFound(let peerName):
            return "Found: \(peerName)"
        case .proximityMet:
            return "Proximity met"
        case .exchanging:
            return "Exchanging info..."
        case .complete(_, let peerName):
            return "Received from \(peerName)"
        case .error(_):
            return "Error"
        }
    }
    
    /// Additional detail text for certain states
    private var statusDetailText: String? {
        switch proximityManager.state {
        case .error(let message):
            return message
        case .complete(let bip21URI, _):
            // Show truncated URI
            let truncated = bip21URI.count > 30 
                ? "\(bip21URI.prefix(15))...\(bip21URI.suffix(15))" 
                : bip21URI
            return truncated
        default:
            return nil
        }
    }
}
