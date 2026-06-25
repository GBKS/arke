//
//  ValidationFeedbackView.swift
//  Ark wallet prototype
//
//  Created by Assistant on 11/19/25.
//

import SwiftUI
import Combine
import ArkeUI

struct ValidationFeedbackView: View {
    let state: RecipientState
    
    var body: some View {
        Group {
            switch state {
            case .idle:
                EmptyView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                
            case .typing:
                TypingIndicatorView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                
            case .valid:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.Arke.green)
                    
                    Text("status_valid")
                        .font(.body)
                        .foregroundColor(.Arke.green)
                        .fontWeight(.semibold)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                
            case .validBIP353Format:
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.Arke.blue)
                    
                    Text("status_valid") // BIP-353 address detected
                        .font(.body)
                        .foregroundColor(.Arke.blue)
                        .fontWeight(.semibold)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                
            case .resolvingBIP353:
                TypingIndicatorView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                
            case .bip353Resolved:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.Arke.green)
                    
                    Text("status_valid")
                        .font(.body)
                        .foregroundColor(.Arke.green)
                        .fontWeight(.semibold)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                
            case .invalid(let error):
                let _ = {
                    print("[ValidationFeedbackView] Invalid recipient: \(error)")
                }()
                
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.Arke.orange)
                    
                    Text("status_invalid")
                        .font(.body)
                        .foregroundColor(.Arke.orange)
                        .fontWeight(.medium)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.75), value: state)
    }
}
