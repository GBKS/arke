//
//  ExitProgress.swift
//  Arké
//
//  Shared step model for the unilateral exit process. Built from an
//  ExitTransactionStatus, it drives both the compact segmented progress bar
//  (TransactionClaimExitBanner) and the full step timeline
//  (ExitStatusDetailView), so the two always agree on step count and position.
//
//  Steps: 1 = prepare, 2...k+1 = one per exit transaction,
//  k+2 = wait for unlock, k+3 = claim, k+4 = complete.
//

import Foundation
import Bark

public struct ExitProgress: Equatable {

    /// Coarse phase of the exit, used for tinting the progress UI.
    public enum Phase: Equatable {
        case preparing      // start / unparsed
        case confirming     // exit transactions confirming onchain
        case waiting        // timelock wait (awaiting delta / claimable)
        case claiming       // claim transaction in flight
        case complete       // claimed
        case cancelled      // VTXO was already spent elsewhere; exit aborted
    }

    public enum StepState: Equatable {
        case done
        case current
        case upcoming
    }

    public enum StepKind: Equatable {
        case prepare
        /// One of the exit package transactions. `transaction` is nil until
        /// the chain is known (before the first Processing state arrives).
        case confirmTransaction(index: Int, total: Int, transaction: ExitTransaction?)
        case waitForUnlock(confirmedBlock: ArkeBlockRef?, claimableHeight: UInt32?)
        case claim(claimTxid: String?)
        case complete(txid: String?, block: ArkeBlockRef?)
    }

    public struct Step: Equatable, Identifiable {
        /// 1-based step number; matches the segment position in the bar.
        public let id: Int
        public let kind: StepKind
        public let state: StepState
    }

    public let steps: [Step]
    /// 1-based; equals the number of filled segments in the bar.
    public let currentStep: Int
    public let totalSteps: Int
    public let phase: Phase
    /// Block height at which the exit becomes claimable, once known.
    public let claimableHeight: UInt32?
    public var isCancelled: Bool { phase == .cancelled }

    /// Blocks left until the exit timelock expires, clamped to zero.
    public func blocksUntilUnlock(currentHeight: UInt32?) -> Int? {
        guard let claimableHeight, let currentHeight else { return nil }
        return max(0, Int(claimableHeight) - Int(currentHeight))
    }

    public init(status: ExitTransactionStatus) {
        let parsed = status.parsedState ?? .unparsed(status.state)

        // Transactions in chain order: the live Processing state is freshest,
        // otherwise fall back to the chain reconstructed from history.
        let transactions: [ExitTransaction]
        if case .processing(let data) = parsed {
            transactions = data.transactions
        } else {
            transactions = status.transactionChain
        }
        // Every exit needs at least one transaction, so assume one until the
        // real chain is known. The step count can grow once it arrives.
        let transactionCount = max(1, transactions.count)

        let current: Int
        let phase: Phase
        switch parsed {
        case .start, .unparsed:
            current = 1
            phase = .preparing

        case .processing(let data):
            let confirmedCount = data.transactions.filter { tx in
                if case .confirmed = tx.status { return true }
                return false
            }.count
            current = 2 + confirmedCount
            phase = confirmedCount >= transactionCount ? .waiting : .confirming

        case .awaitingDelta, .claimable:
            current = transactionCount + 2
            phase = .waiting

        case .claimInProgress:
            current = transactionCount + 3
            phase = .claiming

        case .claimed:
            current = transactionCount + 4
            phase = .complete

        case .vtxoAlreadySpent:
            current = 1
            phase = .cancelled
        }

        var confirmedBlock: ArkeBlockRef?
        var claimableHeight: UInt32?
        var claimTxid: String?
        var completeTxid: String?
        var completeBlock: ArkeBlockRef?
        switch parsed {
        case .awaitingDelta(let data):
            confirmedBlock = data.confirmedBlock
            claimableHeight = data.claimableHeight
        case .claimable(let data):
            claimableHeight = data.claimableSince.height
        case .claimInProgress(let data):
            claimableHeight = data.claimableSince.height
            claimTxid = data.claimTxid
        case .claimed(let data):
            claimTxid = data.txid
            completeTxid = data.txid
            completeBlock = data.block
        default:
            break
        }

        let total = transactionCount + 4
        let clampedCurrent = min(max(current, 1), total)

        func state(for stepNumber: Int) -> StepState {
            if phase == .complete { return .done }
            if stepNumber < clampedCurrent { return .done }
            if stepNumber == clampedCurrent { return .current }
            return .upcoming
        }

        var steps: [Step] = []
        steps.append(Step(id: 1, kind: .prepare, state: state(for: 1)))
        for index in 1...transactionCount {
            let transaction = index <= transactions.count ? transactions[index - 1] : nil
            steps.append(Step(
                id: index + 1,
                kind: .confirmTransaction(index: index, total: transactionCount, transaction: transaction),
                state: state(for: index + 1)
            ))
        }
        steps.append(Step(
            id: transactionCount + 2,
            kind: .waitForUnlock(confirmedBlock: confirmedBlock, claimableHeight: claimableHeight),
            state: state(for: transactionCount + 2)
        ))
        steps.append(Step(
            id: transactionCount + 3,
            kind: .claim(claimTxid: claimTxid),
            state: state(for: transactionCount + 3)
        ))
        steps.append(Step(
            id: transactionCount + 4,
            kind: .complete(txid: completeTxid, block: completeBlock),
            state: state(for: transactionCount + 4)
        ))

        self.steps = steps
        self.totalSteps = steps.count
        self.currentStep = clampedCurrent
        self.phase = phase
        self.claimableHeight = claimableHeight
    }

    /// Aggregate progress across multiple concurrent exits. Cancelled movements
    /// (vtxoAlreadySpent) are excluded. Claimed movements contribute their full
    /// step count so the bar advances monotonically as each finishes.
    public init(statuses: [ExitTransactionStatus]) {
        let active = statuses.filter { status in
            guard let parsed = status.parsedState else { return true }
            if case .vtxoAlreadySpent = parsed { return false }
            return true
        }

        guard !active.isEmpty else {
            self.steps = []
            self.totalSteps = 0
            self.currentStep = 0
            self.phase = .cancelled
            self.claimableHeight = nil
            return
        }

        let progresses = active.map { ExitProgress(status: $0) }

        self.steps = []
        self.totalSteps = progresses.reduce(0) { $0 + $1.totalSteps }
        self.currentStep = progresses.reduce(0) { $0 + $1.currentStep }
        // Phase = earliest (slowest) among exits still in flight;
        // falls back to .complete when every active exit is done.
        let inFlight = progresses.filter { $0.phase != .complete }
        self.phase = inFlight.min { $0.phase.order < $1.phase.order }?.phase ?? .complete
        // Latest claimable height — all exits must unlock before claiming can proceed.
        self.claimableHeight = progresses.compactMap(\.claimableHeight).max()
    }
}

private extension ExitProgress.Phase {
    var order: Int {
        switch self {
        case .preparing:  return 0
        case .confirming: return 1
        case .waiting:    return 2
        case .claiming:   return 3
        case .complete:   return 4
        case .cancelled:  return 5
        }
    }
}
