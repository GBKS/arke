//
//  SendBlockedReasonText.swift
//  Arké
//
//  The one line under a disabled Send button that says why. The slot is
//  always present, two caption lines tall, so the button never jumps when
//  a reason appears or clears (DECIDED 2026-10-27); the text itself is
//  shown only when there is a reason.
//

import SwiftUI

struct SendBlockedReasonText: View {
    let reason: String?

    var body: some View {
        Text(reason ?? "")
            .font(.caption)
            .foregroundColor(.orange)
            .multilineTextAlignment(.center)
            .lineLimit(2, reservesSpace: true)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .opacity(reason == nil ? 0 : 1)
            .accessibilityHidden(reason == nil)
            .accessibilityLabel(Text(String(localized: "accessibility_send_blocked", defaultValue: "Send is unavailable: \(reason ?? "")")))
    }
}
