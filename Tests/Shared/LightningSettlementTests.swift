//
//  LightningSettlementTests.swift
//  ArkéTests
//
//  The wait after a Lightning send started with `wait: false`: "Sent" only on
//  bark's paid record, each failure kind from bark's records, never a failure
//  on a read error; and a pay-call error that left a pending send is waited
//  for instead of reported. State meanings read at bark-0.8.1
//  (`Features/Lightning_Send_Settlement.md` §3).
//

import Testing
import Foundation
import Bark

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Lightning Settlement")
struct LightningSettlementTests {

    private static let hash = "aa11"
    private static let otherHash = "bb22"
    private static let paid = LightningSendStatus.paid(paymentHash: hash, preimage: "cc33")

    private static func send(_ paymentHash: String = hash, failedRevocation: Bool = false) -> LightningSend {
        LightningSend(
            invoice: "lnbc1test", paymentHash: paymentHash, movementId: nil, amountSats: 1_000,
            feeSats: 5, htlcVtxoCount: 1, hasFailedRevocation: failedRevocation
        )
    }

    private static func inProgress(failedRevocation: Bool = false) -> LightningSendStatus {
        .inProgress(send: send(failedRevocation: failedRevocation))
    }

    /// Hands out the given results in order, then repeats the last one
    private final class Script<T> {
        private var queue: [Result<T, Swift.Error>]
        private(set) var count = 0

        init(_ results: [Result<T, Swift.Error>]) { queue = results }

        func next() throws -> T {
            count += 1
            let result = queue.count > 1 ? queue.removeFirst() : queue[0]
            return try result.get()
        }
    }

    private struct CallFailed: Swift.Error {}

    // MARK: - wait

    private func wait(_ started: LightningSendStatus, knownHash: String? = nil, _ reads: Script<LightningSendStatus>) async throws -> LightningSendStatus {
        try await LightningSettlement.wait(for: started, knownHash: knownHash, pollInterval: .milliseconds(1)) { paymentHash in
            #expect(paymentHash == Self.hash)
            return try reads.next()
        }
    }

    @Test("Waits through in-progress reads and returns the paid status")
    func paidAfterPending() async throws {
        let reads = Script([.success(Self.inProgress()), .success(Self.inProgress()), .success(Self.paid)])
        #expect(try await wait(Self.inProgress(), reads) == Self.paid)
        #expect(reads.count == 3)
    }

    @Test("A pay call that already settled is not polled")
    func settledInsideThePayCall() async throws {
        let reads = Script<LightningSendStatus>([.success(Self.inProgress())])
        #expect(try await wait(Self.paid, reads) == Self.paid)
        #expect(reads.count == 0)
    }

    @Test("An unknown with no hash is an unconfirmed outcome, not a failure")
    func unknownWithoutHashIsUnconfirmed() async throws {
        let reads = Script<LightningSendStatus>([.success(Self.paid)])
        await #expect(throws: LightningSendFailure.outcomeUnknown) { try await wait(.unknown, reads) }
        #expect(reads.count == 0)
        #expect(LightningSendFailure.outcomeUnknown.isUnconfirmed)
    }

    @Test("An unknown from an invoice pay call is read again with the invoice's hash")
    func unknownFromPayCallWithKnownHash() async throws {
        let reads = Script([.success(Self.paid)])
        #expect(try await wait(.unknown, knownHash: Self.hash, reads) == Self.paid)
    }

    @Test("One unknown read is read again: a settlement can finish between bark's two lookups")
    func unknownThenPaidIsPaid() async throws {
        let reads = Script([.success(.unknown), .success(Self.paid)])
        #expect(try await wait(Self.inProgress(), reads) == Self.paid)
    }

    @Test("Two unknown reads in a row mean the payment failed and was refunded")
    func unknownTwiceIsNotSent() async throws {
        let reads = Script<LightningSendStatus>([.success(.unknown), .success(.unknown)])
        await #expect(throws: LightningSendFailure.notSent) { try await wait(Self.inProgress(), reads) }
        #expect(reads.count == 2)
        #expect(!LightningSendFailure.notSent.isUnconfirmed)
    }

    @Test("A failed revocation ends the wait as held by the server, not as a wait that never ends")
    func failedRevocationIsHeldByServer() async throws {
        let reads = Script<LightningSendStatus>([.success(Self.inProgress(failedRevocation: true))])
        await #expect(throws: LightningSendFailure.heldByServer) { try await wait(Self.inProgress(), reads) }
    }

    @Test("A failed read is 'status unreadable', never a failed payment")
    func readErrorIsUnreadable() async throws {
        let reads = Script<LightningSendStatus>([.failure(CallFailed())])
        await #expect(throws: LightningSendFailure.statusUnreadable) { try await wait(Self.inProgress(), reads) }
        #expect(LightningSendFailure.statusUnreadable.isUnconfirmed)
    }

    // MARK: - start

    private func start(knownHash: String? = nil, pending: Script<[LightningSend]>, pay: Script<LightningSendStatus>) async throws -> LightningSendStatus {
        try await LightningSettlement.start(knownHash: knownHash, pendingSends: { try pending.next() }, pay: { try pay.next() })
    }

    @Test("A pay call that returns is passed through without reading pending sends for an invoice")
    func payReturnsForInvoice() async throws {
        let pending = Script<[LightningSend]>([.success([])])
        let pay = Script([.success(Self.inProgress())])
        #expect(try await start(knownHash: Self.hash, pending: pending, pay: pay) == Self.inProgress())
        #expect(pending.count == 0)
    }

    @Test("A pay-call error with the invoice's send pending is waited for, not reported")
    func errorWithPendingInvoiceSend() async throws {
        let pending = Script<[LightningSend]>([.success([Self.send(Self.otherHash), Self.send()])])
        let pay = Script<LightningSendStatus>([.failure(CallFailed())])
        #expect(try await start(knownHash: Self.hash, pending: pending, pay: pay) == Self.inProgress())
    }

    @Test("A pay-call error with no pending send is the error")
    func errorWithoutPendingSend() async throws {
        let pending = Script<[LightningSend]>([.success([Self.send(Self.otherHash)])])
        let pay = Script<LightningSendStatus>([.failure(CallFailed())])
        await #expect(throws: CallFailed.self) { try await start(knownHash: Self.hash, pending: pending, pay: pay) }
    }

    @Test("Without a hash, the one send that appeared during the call is the payment")
    func hashlessErrorWithOneNewSend() async throws {
        let pending = Script<[LightningSend]>([.success([Self.send(Self.otherHash)]), .success([Self.send(Self.otherHash), Self.send()])])
        let pay = Script<LightningSendStatus>([.failure(CallFailed())])
        #expect(try await start(pending: pending, pay: pay) == Self.inProgress())
        #expect(pending.count == 2)
    }

    @Test("Without a hash, two new sends or a failed snapshot cannot be attributed: the error stands")
    func hashlessErrorAmbiguous() async throws {
        let twoNew = Script<[LightningSend]>([.success([]), .success([Self.send(Self.otherHash), Self.send()])])
        await #expect(throws: CallFailed.self) { try await start(pending: twoNew, pay: Script([.failure(CallFailed())])) }

        let snapshotFailed = Script<[LightningSend]>([.failure(CallFailed()), .success([Self.send()])])
        await #expect(throws: CallFailed.self) { try await start(pending: snapshotFailed, pay: Script([.failure(CallFailed())])) }
    }
}
