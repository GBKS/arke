//
//  PaymentDestinationSelectorTests.swift
//  ArkéTests
//
//  A bitcoin address can be paid from Savings (BDK) or from Payments (bark's
//  collaborative offboard). The ranker emits one row per source, Savings
//  first, and judges each by its own balance; nothing else gets a twin
//  (`Features/Send_Onchain_From_Payments.md` §3.1).
//

import Testing
import Foundation
import ArkeUI

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Payment destination selector: funding sources")
@MainActor
struct PaymentDestinationSelectorTests {

    private typealias Selector = PaymentDestinationSelector

    private func destination(_ format: AddressFormat) -> PaymentDestination {
        PaymentDestination(format: format, network: format.supportsBitcoinNetworks ? .signet : nil, address: "addr-\(format.rawValue)")
    }

    /// No wallet manager: the ranker estimates nothing, which keeps these
    /// tests about shape and viability rather than live fees
    private func context(ark: Int?, bitcoin: Int?) -> Selector.PaymentContext {
        Selector.PaymentContext(arkBalance: ark, bitcoinBalance: bitcoin, networkConfig: .signet)
    }

    @Test("A bitcoin address gets a Savings row and a Payments row, Savings first")
    func bitcoinHasTwoRows() async {
        let ranked = await Selector.rankDestinations(destination(.bitcoin), amount: nil, context: context(ark: 1_000, bitcoin: 1_000))
        #expect(ranked.map(\.balanceSource) == [.bitcoin, .arkToOnchain])
        #expect(ranked[0].priority < ranked[1].priority)
    }

    @Test("Lightning, Ark and silent-payment destinations keep a single row")
    func otherFormatsHaveOneRow() async {
        for format in [AddressFormat.lightning, .lightningInvoice, .ark, .silentPayments] {
            let ranked = await Selector.rankDestinations(destination(format), amount: nil, context: context(ark: 1_000, bitcoin: 1_000))
            #expect(ranked.count == 1, "\(format.rawValue)")
        }
    }

    @Test("Each row is judged by its own balance: empty Savings leaves Payments as the first viable row")
    func emptySavingsFallsToPayments() async {
        let request = PaymentRequest(destination: destination(.bitcoin), amount: 5_000)
        let ranked = await Selector.rankDestinations(from: request, context: context(ark: 10_000, bitcoin: 0))
        #expect(ranked.first?.balanceSource == .arkToOnchain)
        #expect(ranked.first?.viable == true)
        let savingsRow = ranked.first { $0.balanceSource == .bitcoin }
        #expect(savingsRow?.viable == false)
    }

    @Test("Both viable: Savings stays the default (first) row")
    func savingsIsDefaultWhenBothViable() async {
        let request = PaymentRequest(destination: destination(.bitcoin), amount: 5_000)
        let ranked = await Selector.rankDestinations(from: request, context: context(ark: 10_000, bitcoin: 10_000))
        #expect(ranked.first?.balanceSource == .bitcoin)
        let allViable = ranked.allSatisfy { $0.viable }
        #expect(allViable)
    }

    @Test("The Payments row needs the Ark server; the Savings row does not")
    func paymentsRowNeedsServer() async {
        let request = PaymentRequest(destination: destination(.bitcoin), amount: 5_000)
        let offline = Selector.PaymentContext(arkBalance: 10_000, bitcoinBalance: 10_000, networkConfig: .signet, arkServerConnected: false)
        let ranked = await Selector.rankDestinations(from: request, context: offline)
        #expect(ranked.first { $0.balanceSource == .bitcoin }?.viable == true)
        #expect(ranked.first { $0.balanceSource == .arkToOnchain }?.viable == false)
    }

    @Test("Re-ranking with the typed amount uses known fees per row and estimates nothing")
    func rerankUsesKnownFees() {
        let bitcoin = destination(.bitcoin)
        let request = PaymentRequest(destination: bitcoin)
        let savings = Selector.Choice(destinationId: bitcoin.id, source: .bitcoin)
        let payments = Selector.Choice(destinationId: bitcoin.id, source: .arkToOnchain)

        // 9,000 + 1,500 fee exceeds Savings; Payments covers 9,000 + 400
        let ranked = Selector.rerankDestinations(
            from: request, amount: 9_000, context: context(ark: 10_000, bitcoin: 10_000),
            knownFees: [savings: 1_500, payments: 400]
        )
        #expect(ranked.first { $0.choice == savings }?.viable == false)
        #expect(ranked.first { $0.choice == savings }?.estimatedFee == 1_500)
        #expect(ranked.first { $0.choice == payments }?.viable == true)
        #expect(ranked.first { $0.choice == payments }?.estimatedFee == 400)
        // Viable rows sort first, so Payments leads even though Savings is the default
        #expect(ranked.first?.choice == payments)
    }

    @Test("Without a known fee a row is judged by the amount alone")
    func rerankWithoutFeeJudgesAmount() {
        let bitcoin = destination(.bitcoin)
        let request = PaymentRequest(destination: bitcoin)
        let ranked = Selector.rerankDestinations(from: request, amount: 10_000, context: context(ark: 10_000, bitcoin: 9_999), knownFees: [:])
        #expect(ranked.first { $0.balanceSource == .arkToOnchain }?.viable == true)
        #expect(ranked.first { $0.balanceSource == .arkToOnchain }?.estimatedFee == nil)
        #expect(ranked.first { $0.balanceSource == .bitcoin }?.viable == false)
    }

    @Test("The load-time pick skips a default source that holds nothing (empty Savings starts on Payments)")
    func initialPickSkipsEmptyBalance() async {
        let request = PaymentRequest(destination: destination(.bitcoin))  // no amount: every row is viable
        let emptySavings = await Selector.rankDestinations(from: request, context: context(ark: 10_000, bitcoin: 0))
        #expect(Selector.initialPick(in: emptySavings)?.balanceSource == .arkToOnchain)

        let bothFunded = await Selector.rankDestinations(from: request, context: context(ark: 10_000, bitcoin: 10_000))
        #expect(Selector.initialPick(in: bothFunded)?.balanceSource == .bitcoin)

        // Nothing funded: the default row still gets picked rather than none
        let nothingFunded = await Selector.rankDestinations(from: request, context: context(ark: 0, bitcoin: 0))
        #expect(Selector.initialPick(in: nothingFunded)?.balanceSource == .bitcoin)
    }

    @Test("A request with an Ark and a bitcoin address offers each balance once: Payments via Ark, Savings (DECIDED 2026-10-28, §9.1)")
    func oneRowPerBalanceDropsTheDominatedPath() async {
        let request = PaymentRequest(destinations: [destination(.ark), destination(.bitcoin)], originalString: "bitcoin:…")
        let ranked = await Selector.rankDestinations(from: request, context: context(ark: 10_000, bitcoin: 10_000))
        #expect(ranked.map(\.balanceSource) == [.ark, .bitcoin])
        let reranked = Selector.rerankDestinations(from: request, amount: 1_000, context: context(ark: 10_000, bitcoin: 10_000), knownFees: [:])
        #expect(reranked.map(\.balanceSource) == [.ark, .bitcoin])
    }

    @Test("Two bitcoin addresses in one request both stay: same balance, same rail, different payees")
    func sameRailRowsAreNotDominated() async {
        let request = PaymentRequest(destinations: [destination(.bitcoin), destination(.bitcoin)], originalString: "bitcoin:…")
        let ranked = await Selector.rankDestinations(from: request, context: context(ark: 10_000, bitcoin: 10_000))
        #expect(ranked.filter { $0.balanceSource == .bitcoin }.count == 2)
        #expect(ranked.filter { $0.balanceSource == .arkToOnchain }.count == 2)
    }

    @Test("Rows are titled by balance alone; the rail is a caption (DECIDED 2026-10-28)")
    func rowTitlesNameTheBalance() async {
        let ranked = await Selector.rankDestinations(destination(.bitcoin), amount: nil, context: context(ark: 1, bitcoin: 1))
        let rows = ranked.map { DisplayDestination(ranked: $0, matchedContact: nil) }
        #expect(rows.map(\.title) == ["Savings", "Payments"])
        #expect(rows.map(\.railName) == ["onchain", "onchain"])
        let lightning = await Selector.rankDestinations(destination(.lightning), amount: nil, context: context(ark: 1, bitcoin: 1))
        let lightningRow = DisplayDestination(ranked: lightning[0], matchedContact: nil)
        #expect(lightningRow.title == "Payments")
        #expect(lightningRow.railName == "Lightning")
    }

    @Test("The collapsed row names the source as \"Pay from\", the sheet rows do not (DECIDED 2026-10-28)")
    func collapsedRowSaysPayFrom() async {
        let ranked = await Selector.rankDestinations(destination(.bitcoin), amount: nil, context: context(ark: 1, bitcoin: 1))
        let rows = ranked.map { DisplayDestination(ranked: $0, matchedContact: nil) }
        #expect(rows.map(\.payFromTitle) == ["Pay from Savings", "Pay from Payments"])
    }
}
