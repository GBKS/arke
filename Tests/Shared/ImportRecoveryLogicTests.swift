//
//  ImportRecoveryLogicTests.swift
//  Arke
//
//  Pins the seed-import recovery retry decision (launch sequence contract,
//  rule 2): a recovery that never started on the creating open can only be
//  re-run by wiping the seconds-old database and redoing the creating open,
//  until attempts run out, at which point the import proceeds without
//  recovery rather than failing. Since bark 0.9.0 a started recovery can
//  also park in progress and resume on every sync; that keeps the wallet
//  but blocks the immediate recoverVtxos retry.
//

import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Import Recovery Logic Tests")
struct ImportRecoveryLogicTests {

    @Test("A completed recovery accepts the wallet on any attempt")
    func completedAcceptsImmediately() {
        #expect(ImportRecoveryLogic.decision(outcome: .completed, attempt: 1) == .accept)
        #expect(ImportRecoveryLogic.decision(outcome: .completed, attempt: ImportRecoveryLogic.maxAttempts) == .accept)
    }

    @Test("An in-progress recovery is a started recovery: accept, never wipe")
    func inProgressAcceptsWithoutWipe() {
        // Wiping here would throw away a recovery bark is mid-way through
        // and that every sync would have finished
        for attempt in 1...ImportRecoveryLogic.maxAttempts {
            #expect(ImportRecoveryLogic.decision(outcome: .inProgress, attempt: attempt) == .accept)
        }
    }

    @Test("A failed start with attempts remaining wipes and retries")
    func failedStartRetriesWhileAttemptsRemain() {
        for attempt in 1..<ImportRecoveryLogic.maxAttempts {
            #expect(ImportRecoveryLogic.decision(outcome: .failed(message: "server unreachable"), attempt: attempt) == .wipeAndRetry)
        }
    }

    @Test("Not-run on a creating open is treated like a failed start")
    func notRunIsTreatedAsFailed() {
        #expect(ImportRecoveryLogic.decision(outcome: .notRun, attempt: 1) == .wipeAndRetry)
        #expect(ImportRecoveryLogic.decision(outcome: .notRun, attempt: ImportRecoveryLogic.maxAttempts) == .acceptWithoutRecovery)
    }

    @Test("A failed start on the final attempt accepts without recovery — never fails the import")
    func failedStartOnFinalAttemptAccepts() {
        #expect(ImportRecoveryLogic.decision(outcome: .failed(message: "x"), attempt: ImportRecoveryLogic.maxAttempts) == .acceptWithoutRecovery)
    }

    @Test("Retries are bounded")
    func retriesAreBounded() {
        // A regression to unlimited retries would loop a failing import
        // forever; past the cap the decision must terminate
        #expect(ImportRecoveryLogic.decision(outcome: .failed(message: "x"), attempt: ImportRecoveryLogic.maxAttempts + 1) == .acceptWithoutRecovery)
        #expect(ImportRecoveryLogic.maxAttempts > 1)
    }

    // MARK: - Post-open retry gate (bark 0.9.0)

    @Test("The immediate recoverVtxos retry runs only on a final report")
    func retryOnlyAfterCompletedRecovery() {
        // bark 0.9.0 refuses recoverVtxos while a recovery is being driven,
        // and an in-progress recovery is driven by every sync
        #expect(ImportRecoveryLogic.shouldRetryAfterOpen(outcome: .completed))
        #expect(!ImportRecoveryLogic.shouldRetryAfterOpen(outcome: .inProgress))
        #expect(!ImportRecoveryLogic.shouldRetryAfterOpen(outcome: .failed(message: "x")))
        #expect(!ImportRecoveryLogic.shouldRetryAfterOpen(outcome: .notRun))
    }

    // MARK: - Post-scan retry passes (v0.24 gapLimit override)

    @Test("A clean scan produces no retry passes")
    func cleanScanProducesNoPasses() {
        #expect(ImportRecoveryLogic.retryPasses(failedIds: [], foreignIds: [], widenedGapLimit: 100_000).isEmpty)
    }

    @Test("Failed ids retry with the wallet's configured gap limit, not the widened one")
    func failedIdsKeepConfiguredGapLimit() {
        // failed = transient per-VTXO errors; ownership was already proven,
        // so paying the widened scan's worst case would be pure waste
        let passes = ImportRecoveryLogic.retryPasses(failedIds: ["a", "b"], foreignIds: [], widenedGapLimit: 100_000)
        #expect(passes == [.init(bucket: .failed, vtxoIds: ["a", "b"], gapLimit: nil)])
    }

    @Test("Abandoned ids join the failed pass once, without the widened scan")
    func abandonedIdsJoinFailedPass() {
        // abandoned = bark gave up after 40 undecided attempts but keeps the
        // VTXO locked and names recoverVtxos as the way to try again; an id
        // reported in both buckets is submitted once
        let passes = ImportRecoveryLogic.retryPasses(failedIds: ["a"], abandonedIds: ["b", "a"], foreignIds: [], widenedGapLimit: 100_000)
        #expect(passes == [.init(bucket: .failed, vtxoIds: ["a", "b"], gapLimit: nil)])
    }

    @Test("Foreign ids retry with the widened gap limit")
    func foreignIdsGetWidenedGapLimit() {
        // foreign = no key derivable within the configured limit; only a
        // wider scan can rescue a wallet's own VTXOs keyed beyond it
        let passes = ImportRecoveryLogic.retryPasses(failedIds: [], foreignIds: ["c"], widenedGapLimit: 100_000)
        #expect(passes == [.init(bucket: .foreign, vtxoIds: ["c"], gapLimit: 100_000)])
    }

    @Test("Both buckets stay separate passes, cheap failed retry first")
    func bucketsNeverMergeIntoOneScan() {
        let passes = ImportRecoveryLogic.retryPasses(failedIds: ["a"], foreignIds: ["c"], widenedGapLimit: 100_000)
        #expect(passes == [
            .init(bucket: .failed, vtxoIds: ["a"], gapLimit: nil),
            .init(bucket: .foreign, vtxoIds: ["c"], gapLimit: 100_000),
        ])
    }
}
