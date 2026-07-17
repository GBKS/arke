//
//  ExitProgressTests.swift
//  ArkéTests
//
//  Unit tests for the shared ExitProgress step model that drives the exit
//  banner's segmented bar and the exit status detail timeline.
//

import Testing
import Foundation
import Bark

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Exit Progress Tests")
struct ExitProgressTests {

    // MARK: - Fixtures (real bark state string formats)

    private static let startState = "Start(ExitStartState { tip_height: 301492 })"

    private static let processingTwoUnconfirmed = "Processing(ExitProcessingState { tip_height: 301492, transactions: [ExitTx { txid: 87c27c959bbaaa31d46cd9ee8c74156badd4d86ea06a2253d4a67286ea394216, status: VerifyInputs }, ExitTx { txid: 2fb55a939cff09e3380dd17bff529bdbb60e98a6a9623fbca9b7fd316485bc67, status: VerifyInputs }] })"

    private static let processingOneOfTwoConfirmed = "Processing(ExitProcessingState { tip_height: 301494, transactions: [ExitTx { txid: 87c27c959bbaaa31d46cd9ee8c74156badd4d86ea06a2253d4a67286ea394216, status: Confirmed { child_txid: cdcfdd1a2ff56d23d8a864b541f88dff168ad24dafe0df02213744b49fe9a285, block: 301493:0000000f806d48ff3118018de1f6053a8f97a4360ffca84613902c3e5777a359, origin: Wallet { confirmed_in: Some(301493:0000000f806d48ff3118018de1f6053a8f97a4360ffca84613902c3e5777a359) } } }, ExitTx { txid: 2fb55a939cff09e3380dd17bff529bdbb60e98a6a9623fbca9b7fd316485bc67, status: VerifyInputs }] })"

    private static let awaitingDeltaState = "AwaitingDelta(ExitAwaitingDeltaState { tip_height: 301587, confirmed_block: 301543:000000094dd54e6609ccbfd6af266066e6e088f426b0c6d8f8990ffa2fee4e0d, claimable_height: 301555 })"

    private static let claimableState = "Claimable(ExitClaimableState { tip_height: 301627, claimable_since: 301555:0000000b952992b6b5bd82159bb38933523a86123f7449dcf67c3ed3a7ef636d, last_scanned_block: None })"

    private static let claimInProgressState = "ClaimInProgress(ExitClaimInProgressState { tip_height: 301627, claimable_since: 301555:0000000b952992b6b5bd82159bb38933523a86123f7449dcf67c3ed3a7ef636d, claim_txid: dc2b6582c0563df15e403fbae305b605273cc00d1d15ee1d99090b3f450bcbd0 })"

    private static let claimedState = "Claimed(ExitClaimedState { tip_height: 301797, txid: dc2b6582c0563df15e403fbae305b605273cc00d1d15ee1d99090b3f450bcbd0, block: 301628:000000015d9ea966e622a009bfcd733e74b1a9b8252f7e788e7c66164b42cf22 })"

    private static let alreadySpentState = "VtxoAlreadySpent(ExitVtxoAlreadySpentState { tip_height: 301492 })"

    private func makeStatus(state: String, history: [String]? = nil, transactionCount: UInt32 = 0) -> ExitTransactionStatus {
        ExitTransactionStatus(
            vtxoId: "test-vtxo-id",
            state: state,
            history: history,
            transactionCount: transactionCount
        )
    }

    // MARK: - Step structure

    @Test("Start state: step 1 of 5 (single assumed transaction), preparing")
    func testStartState() {
        let progress = ExitProgress(status: makeStatus(state: Self.startState))

        #expect(progress.currentStep == 1)
        #expect(progress.totalSteps == 5)
        #expect(progress.phase == .preparing)
        #expect(progress.steps[0].kind == .prepare)
        #expect(progress.steps[0].state == .current)
        #expect(progress.steps[1].state == .upcoming)
    }

    @Test("Step kinds are ordered prepare, transactions, wait, claim, complete")
    func testStepOrdering() {
        let progress = ExitProgress(status: makeStatus(state: Self.processingTwoUnconfirmed))

        #expect(progress.totalSteps == 6)
        #expect(progress.steps[0].kind == .prepare)
        guard case .confirmTransaction(let index1, let total1, let tx1) = progress.steps[1].kind,
              case .confirmTransaction(let index2, let total2, let tx2) = progress.steps[2].kind,
              case .waitForUnlock = progress.steps[3].kind,
              case .claim = progress.steps[4].kind,
              case .complete = progress.steps[5].kind else {
            Issue.record("Unexpected step kinds: \(progress.steps.map(\.kind))")
            return
        }
        #expect(index1 == 1 && total1 == 2)
        #expect(index2 == 2 && total2 == 2)
        #expect(tx1?.txid == "87c27c959bbaaa31d46cd9ee8c74156badd4d86ea06a2253d4a67286ea394216")
        #expect(tx2?.txid == "2fb55a939cff09e3380dd17bff529bdbb60e98a6a9623fbca9b7fd316485bc67")

        // Step ids are 1-based and contiguous, matching bar segments
        #expect(progress.steps.map(\.id) == [1, 2, 3, 4, 5, 6])
    }

    // MARK: - Current step per state (mirrors the banner's math)

    @Test("Processing with no confirmations is step 2")
    func testProcessingUnconfirmed() {
        let progress = ExitProgress(status: makeStatus(state: Self.processingTwoUnconfirmed))

        #expect(progress.currentStep == 2)
        #expect(progress.phase == .confirming)
        #expect(progress.steps[0].state == .done)
        #expect(progress.steps[1].state == .current)
    }

    @Test("Processing with 1 of 2 confirmed is step 3")
    func testProcessingPartiallyConfirmed() {
        let progress = ExitProgress(status: makeStatus(state: Self.processingOneOfTwoConfirmed))

        #expect(progress.currentStep == 3)
        #expect(progress.totalSteps == 6)
        #expect(progress.phase == .confirming)
    }

    @Test("AwaitingDelta is the wait step with unlock data")
    func testAwaitingDelta() {
        // History carries the transaction chain (2 transactions)
        let progress = ExitProgress(status: makeStatus(
            state: Self.awaitingDeltaState,
            history: [Self.startState, Self.processingOneOfTwoConfirmed]
        ))

        #expect(progress.totalSteps == 6)
        #expect(progress.currentStep == 4) // transactionCount + 2
        #expect(progress.phase == .waiting)
        #expect(progress.claimableHeight == 301555)

        guard case .waitForUnlock(let confirmedBlock, let claimableHeight) = progress.steps[3].kind else {
            Issue.record("Expected waitForUnlock at step 4, got \(progress.steps[3].kind)")
            return
        }
        #expect(confirmedBlock?.height == 301543)
        #expect(claimableHeight == 301555)
    }

    @Test("Claimable stays on the wait step")
    func testClaimable() {
        let progress = ExitProgress(status: makeStatus(state: Self.claimableState))

        #expect(progress.currentStep == 3) // 1 assumed transaction + 2
        #expect(progress.phase == .waiting)
        #expect(progress.claimableHeight == 301555)
    }

    @Test("ClaimInProgress is the claim step with the claim txid")
    func testClaimInProgress() {
        let progress = ExitProgress(status: makeStatus(state: Self.claimInProgressState))

        #expect(progress.currentStep == 4) // 1 assumed transaction + 3
        #expect(progress.phase == .claiming)

        guard case .claim(let claimTxid) = progress.steps[3].kind else {
            Issue.record("Expected claim at step 4, got \(progress.steps[3].kind)")
            return
        }
        #expect(claimTxid == "dc2b6582c0563df15e403fbae305b605273cc00d1d15ee1d99090b3f450bcbd0")
    }

    @Test("Claimed marks every step done and fills the complete step")
    func testClaimed() {
        let progress = ExitProgress(status: makeStatus(state: Self.claimedState))

        #expect(progress.currentStep == progress.totalSteps)
        #expect(progress.phase == .complete)
        #expect(progress.steps.allSatisfy { $0.state == .done })

        guard case .complete(let txid, let block) = progress.steps.last?.kind else {
            Issue.record("Expected complete as last step")
            return
        }
        #expect(txid == "dc2b6582c0563df15e403fbae305b605273cc00d1d15ee1d99090b3f450bcbd0")
        #expect(block?.height == 301628)
    }

    @Test("VtxoAlreadySpent is cancelled")
    func testAlreadySpent() {
        let progress = ExitProgress(status: makeStatus(state: Self.alreadySpentState))

        #expect(progress.phase == .cancelled)
        #expect(progress.isCancelled)
        #expect(progress.currentStep == 1)
    }

    @Test("Unparseable state falls back to preparing at step 1")
    func testUnparsedState() {
        let progress = ExitProgress(status: makeStatus(state: "SomeFutureState { whatever: 1 }"))

        #expect(progress.currentStep == 1)
        #expect(progress.phase == .preparing)
        #expect(progress.totalSteps == 5)
    }

    // MARK: - Transaction chain status freshness

    @Test("Chain keeps each transaction's latest status from history")
    func testChainUsesLatestStatus() {
        // A finished exit: history shows the first transaction progressing
        // VerifyInputs → Confirmed. The chain must report the newest status,
        // not the one from the transaction's first appearance.
        let status = makeStatus(
            state: Self.claimedState,
            history: [Self.startState, Self.processingTwoUnconfirmed, Self.processingOneOfTwoConfirmed]
        )

        let chain = status.transactionChain
        #expect(chain.count == 2)
        #expect(chain[0].txid == "87c27c959bbaaa31d46cd9ee8c74156badd4d86ea06a2253d4a67286ea394216")
        #expect(chain[1].txid == "2fb55a939cff09e3380dd17bff529bdbb60e98a6a9623fbca9b7fd316485bc67")

        guard case .confirmed(let data) = chain[0].status else {
            Issue.record("First transaction should carry its latest (Confirmed) status, got \(chain[0].status)")
            return
        }
        #expect(data.block.height == 301493)

        // The second transaction never progressed in this history
        guard case .verifyInputs = chain[1].status else {
            Issue.record("Second transaction should still be VerifyInputs, got \(chain[1].status)")
            return
        }

        // And the step model carries the same fresh statuses
        let progress = ExitProgress(status: status)
        guard case .confirmTransaction(_, _, let stepTx) = progress.steps[1].kind else {
            Issue.record("Expected a transaction step at position 2")
            return
        }
        if case .confirmed = stepTx?.status {} else {
            Issue.record("Step transaction should be Confirmed, got \(String(describing: stepTx?.status))")
        }
    }

    // MARK: - Unlock countdown

    @Test("blocksUntilUnlock counts down and clamps at zero")
    func testBlocksUntilUnlock() {
        let progress = ExitProgress(status: makeStatus(state: Self.awaitingDeltaState))

        #expect(progress.blocksUntilUnlock(currentHeight: 301545) == 10)
        #expect(progress.blocksUntilUnlock(currentHeight: 301555) == 0)
        #expect(progress.blocksUntilUnlock(currentHeight: 301600) == 0)
        #expect(progress.blocksUntilUnlock(currentHeight: nil) == nil)
    }

    @Test("blocksUntilUnlock is nil before the unlock height is known")
    func testBlocksUntilUnlockUnknown() {
        let progress = ExitProgress(status: makeStatus(state: Self.processingTwoUnconfirmed))

        #expect(progress.claimableHeight == nil)
        #expect(progress.blocksUntilUnlock(currentHeight: 301545) == nil)
    }

    // MARK: - Aggregate (multi-VTXO)

    @Test("Single-element aggregate matches single-status init")
    func testAggregateOfOne() {
        let status = makeStatus(state: Self.processingOneOfTwoConfirmed)
        let single = ExitProgress(status: status)
        let aggregate = ExitProgress(statuses: [status])

        #expect(aggregate.currentStep == single.currentStep)
        #expect(aggregate.totalSteps == single.totalSteps)
        #expect(aggregate.phase == single.phase)
    }

    @Test("Aggregate sums steps across two exits")
    func testAggregateSumsSteps() {
        let statusA = makeStatus(state: Self.processingTwoUnconfirmed)
        let statusB = makeStatus(state: Self.awaitingDeltaState, history: [Self.startState, Self.processingOneOfTwoConfirmed])
        let a = ExitProgress(status: statusA)
        let b = ExitProgress(status: statusB)
        let aggregate = ExitProgress(statuses: [statusA, statusB])

        #expect(aggregate.totalSteps == a.totalSteps + b.totalSteps)
        #expect(aggregate.currentStep == a.currentStep + b.currentStep)
    }

    @Test("Aggregate phase = slowest phase across all exits")
    func testAggregatePhaseIsSlowest() {
        // A is still confirming, B is waiting — aggregate should be confirming
        let statusA = makeStatus(state: Self.processingTwoUnconfirmed)
        let statusB = makeStatus(state: Self.awaitingDeltaState, history: [Self.startState, Self.processingOneOfTwoConfirmed])
        let aggregate = ExitProgress(statuses: [statusA, statusB])

        #expect(aggregate.phase == .confirming)
    }

    @Test("Aggregate claimable height = max across all exits")
    func testAggregateClaimableHeightIsMax() {
        let statusA = makeStatus(state: Self.awaitingDeltaState, history: [Self.startState, Self.processingOneOfTwoConfirmed])
        let statusB = makeStatus(state: Self.claimableState)
        let aggregate = ExitProgress(statuses: [statusA, statusB])

        // awaitingDeltaState has claimableHeight 301555; claimableState also 301555
        #expect(aggregate.claimableHeight == 301555)
    }

    @Test("Cancelled VTXO excluded from aggregate")
    func testAggregateCancelledExcluded() {
        let active = makeStatus(state: Self.processingTwoUnconfirmed)
        let cancelled = makeStatus(state: Self.alreadySpentState)
        let single = ExitProgress(status: active)
        let aggregate = ExitProgress(statuses: [active, cancelled])

        // Cancelled exit contributes nothing
        #expect(aggregate.totalSteps == single.totalSteps)
        #expect(aggregate.currentStep == single.currentStep)
        #expect(aggregate.phase == .confirming)
    }

    @Test("All-cancelled aggregate is cancelled phase with zero steps")
    func testAggregateAllCancelled() {
        let aggregate = ExitProgress(statuses: [makeStatus(state: Self.alreadySpentState)])

        #expect(aggregate.phase == .cancelled)
        #expect(aggregate.totalSteps == 0)
        #expect(aggregate.currentStep == 0)
    }

    @Test("Claimed exit contributes full steps to keep bar monotonic")
    func testAggregateClaimedContributesFullSteps() {
        let claimed = makeStatus(state: Self.claimedState)
        let active = makeStatus(state: Self.processingTwoUnconfirmed)
        let claimedProgress = ExitProgress(status: claimed)
        let activeProgress = ExitProgress(status: active)
        let aggregate = ExitProgress(statuses: [claimed, active])

        // Claimed exit is at its full step count; active drives the phase
        #expect(aggregate.totalSteps == claimedProgress.totalSteps + activeProgress.totalSteps)
        #expect(aggregate.currentStep == claimedProgress.currentStep + activeProgress.currentStep)
        #expect(aggregate.phase == .confirming) // slowest in-flight phase
    }

    @Test("All claimed aggregate is complete phase")
    func testAggregateAllClaimedIsComplete() {
        let aggregate = ExitProgress(statuses: [makeStatus(state: Self.claimedState)])

        #expect(aggregate.phase == .complete)
    }

    @Test("Empty aggregate is cancelled")
    func testAggregateEmpty() {
        let aggregate = ExitProgress(statuses: [])

        #expect(aggregate.phase == .cancelled)
        #expect(aggregate.totalSteps == 0)
    }
}
