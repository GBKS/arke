//
//  OffboardingModalSuccessView.swift
//  Ark wallet prototype
//
//  Created by Christoph on 10/19/25.
//

import SwiftUI

struct OffboardingModalSuccessView: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                // Large green checkmark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                
                VStack(spacing: 8) {
                    Text("Transfer Initiated")
                        .font(.title)
                        .fontWeight(.semibold)
                    
                    Text("Your coins are being transferred to the Bitcoin network. This process may take some time to complete.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            Spacer()
            
            Button("Continue") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

#Preview {
    OffboardingModalSuccessView {
        print("Continue tapped")
    }
}
