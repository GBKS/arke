//
//  LightningSettlementTests.swift
//  ArkéTests
//
//  The wait after a Lightning send started with `wait: false`: "Sent" only
//  on bark's paid record, "failed" only on bark's records, never on a read
//  error. State meanings read at bark-0.8.1 (see `LightningSettlement`).
//  Created by Assistant on 11/17/26.
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
    private static let paid = LightningSendStatus.paid(paymentHash: hash, preimage: "bb22")

    private static func inProgress(failedRevocation: Bool = false) -> LightningSendStatus {
        .inProgress(send: LightningSend(
            invoice: "lnbc1test", paymentHash: hash, movementId: nil, amountSats: 1_000,
            feeSats: 5, htlcVtxoCount: 1, hasFailedRevocation: failedRevocation
        ))
    }

    /// Hands out the given reads in order, then repeats the last one
    private final class Reads {
        private var queue: [Result<LightningSendStatus, Swift.Error>]
        private(set) var count = 0

        init(_ reads: [Result<LightningSendStatus, Swift.Error>]) { queue = reads }

        func next(_ paymentHash: String) throws -> LightningSendStatus {
            #expect(paymentHash == LightningSettlementTests.hash)
            count += 1
            let read = queue.count > 1 ? queue.removeFirst() : queue[0]
            return try read.get()
        }
    }

    private struct ReadFailed: Swift.Error {}

    private func wait(_ started: LightningSendStatus, knownHash: String? = nil, _ reads: Reads) async throws -> LightningSendStatus {
        try await LightningSettlement.wait(for: started, paymentHash: knownHash, pollInterval: .milliseconds(1)) { try reads.next($0) }
    }

    @Test("Waits through in-progress reads and returns the paid status")
    func paidAfterPending() async throws {
        let reads = Reads([.success(Self.inProgress()), .success(Self.inProgress()), .success(Self.paid)])
        #expect(try await wait(Self.inProgress(), reads) == Self.paid)
        #expect(reads.count == 3)
    }

    @Test("A pay call that already settled, or failed with no hash, is not polled")
    func settledOrFailedInsideThePayCall() async throws {
        let reads = Reads([.success(Self.inProgress())])
        #expect(try await wait(Self.paid, reads) == Self.paid)
        await #expect(throws: LightningSettlement.SettlementError.failed) { try await wait(.unknown, reads) }
        #expect(reads.count == 0)
    }

    @Test("An unknown from an invoice pay call is read again with the invoice's hash")
    func unknownFromPayCallWithKnownHash() async throws {
        let reads = Reads([.success(Self.paid)])
        #expect(try await wait(.unknown, knownHash: Self.hash, reads) == Self.paid)
    }

    @Test("One unknown read is read again: a settlement can finish between bark's two lookups")
    func unknownThenPaidIsPaid() async throws {
        let reads = Reads([.success(.unknown), .success(Self.paid)])
        #expect(try await wait(Self.inProgress(), reads) == Self.paid)
    }

    @Test("Two unknown reads in a row are a failure")
    func unknownTwiceIsFailed() async throws {
        let reads = Reads([.success(.unknown), .success(.unknown)])
        await #expect(throws: LightningSettlement.SettlementError.failed) { try await wait(Self.inProgress(), reads) }
        #expect(reads.count == 2)
    }

    @Test("A failed revocation ends the wait as a failure, not as a wait that never ends")
    func failedRevocation() async throws {
        let reads = Reads([.success(Self.inProgress(failedRevocation: true))])
        await #expect(throws: LightningSettlement.SettlementError.failed) { try await wait(Self.inProgress(), reads) }
    }

    @Test("A failed read is 'status unreadable', never a failed payment")
    func readErrorIsNotAFailure() async throws {
        let reads = Reads([.failure(ReadFailed())])
        await #expect(throws: LightningSettlement.SettlementError.statusUnreadable) { try await wait(Self.inProgress(), reads) }
    }
}
