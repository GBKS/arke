//
//  DisplayDestination.swift
//  Arké
//
//  Created by Christoph on 11/19/25.
//

import Foundation
import ArkeUI

/// Helper struct to unify destination display data
struct DisplayDestination {
    let destination: PaymentDestination
    let estimatedFee: Int?
    let balanceSourceName: String?
    let matchedContact: ContactModel?
    let viable: Bool
    let viabilityReason: String
    let availableBalance: Int?
    /// The balance this row pays from; nil when no ranking produced the row
    var balanceSource: PaymentDestinationSelector.BalanceSource? = nil

    /// What selects this row: destination plus source, since a bitcoin
    /// address appears once per balance that can pay it
    var choice: PaymentDestinationSelector.Choice {
        PaymentDestinationSelector.Choice(
            destinationId: destination.id,
            source: balanceSource ?? PaymentDestinationSelector.balanceSource(for: destination)
        )
    }

    /// The balance this row pays from, as the row's title: "Payments" or
    /// "Savings" (DECIDED 2026-10-28). The rail and the address are
    /// captions, shown only where rows need telling apart.
    var title: String {
        effectiveBalanceSource.shortName
    }

    /// The collapsed row's caption in the form, "Pay from Savings". The bare
    /// balance name sat above the recipient's address and read as a label
    /// of that address (DECIDED 2026-10-28, §9.2); the sheet rows keep `title`
    var payFromTitle: String {
        String(localized: "send_pay_from_source %@", defaultValue: "Pay from \(title)")
    }

    /// The rail this row leaves on ("Lightning", "Ark", "onchain")
    var railName: String {
        effectiveBalanceSource.railName
    }

    private var effectiveBalanceSource: PaymentDestinationSelector.BalanceSource {
        balanceSource ?? PaymentDestinationSelector.balanceSource(for: destination)
    }

    init(ranked: PaymentDestinationSelector.RankedDestination, matchedContact: ContactModel?) {
        self.destination = ranked.destination
        self.estimatedFee = ranked.estimatedFee
        self.balanceSourceName = ranked.balanceSource.displayName
        self.matchedContact = matchedContact
        self.viable = ranked.viable
        self.viabilityReason = ranked.reason
        self.availableBalance = ranked.availableBalance
        self.balanceSource = ranked.balanceSource
    }

    init(
        destination: PaymentDestination,
        estimatedFee: Int?,
        balanceSourceName: String?,
        matchedContact: ContactModel?,
        viable: Bool,
        viabilityReason: String,
        availableBalance: Int?,
        balanceSource: PaymentDestinationSelector.BalanceSource? = nil
    ) {
        self.destination = destination
        self.estimatedFee = estimatedFee
        self.balanceSourceName = balanceSourceName
        self.matchedContact = matchedContact
        self.viable = viable
        self.viabilityReason = viabilityReason
        self.availableBalance = availableBalance
        self.balanceSource = balanceSource
    }
}
