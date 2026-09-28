//
//  SendAmountFiatLine.swift
//  Arké
//
//  The fiat "≈" line beside the send amount field (Fiat_Rates.md, Phase 3
//  step 2). Follows whatever the field holds — always whole sats, the
//  send flow's single source of truth. Present from the start whenever a
//  rate exists: an empty or zero field shows "≈ $0.00" in placeholder
//  style, mirroring the field's own "0" placeholder, so nothing pops in
//  on the first keystroke. Display only: it never writes back into the
//  amount, so a rates refresh while the user is about to tap Send cannot
//  change what is sent.
//

import SwiftUI

struct SendAmountFiatLine: View {
    /// The amount field's text, whole sats
    let amount: String

    private var sats: Int {
        Int(amount) ?? 0
    }

    var body: some View {
        FiatAmountText(sats: sats)
            .font(.body)
            .foregroundStyle(sats > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
    }
}
