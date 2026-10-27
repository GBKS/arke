//
//  SendBlockedReasonText.swift
//  Arké
//
//  The one line under a disabled Send button that says why. Renders
//  nothing when there is no reason, so the layout does not jump for the
//  common case of an empty amount.
//

import SwiftUI

struct SendBlockedReasonText: View {
    let reason: String?

    var body: some View {
        if let reason {
            Text(reason)
                .font(.caption)
                .foregroundColor(.orange)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .accessibilityLabel(Text(String(localized: "accessibility_send_blocked", defaultValue: "Send is unavailable: \(reason)")))
        }
    }
}
