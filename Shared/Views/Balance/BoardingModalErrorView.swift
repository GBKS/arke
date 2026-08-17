//
//  BoardingModalErrorView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 11/12/25.
//

import SwiftUI
import ArkeUI

struct BoardingModalErrorView: View {
    let errorMessage: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                // Large red X icon
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.Arke.red)
                
                VStack(spacing: 8) {
                    Text(String(localized: "error_boarding_failed", defaultValue: "Boarding Failed"))
                        .font(.system(.title, design: .serif))
                    
                    Text(errorMessage)
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                }
            }
            
            Spacer()
            
            Button(L10n.buttonTryAgain) {
                onRetry()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}
