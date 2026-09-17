//
//  ImportRecoveryLogicTests.swift
//  Arke
//
//  Pins the seed-import recovery retry decision (launch sequence contract,
//  rule 2): a nil recovery report means the creating open's scan errored,
//  and the only way to re-run it is to wipe the seconds-old database and
//  redo the creating open — until attempts run out, at which point the
//  import proceeds without recovery rather than failing.
//

import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Import Recovery Logic Tests")
struct ImportRecoveryLogicTests {

    @Test("A recovery report accepts the wallet on any attempt")
    func reportAcceptsImmediately() {
        #expect(ImportRecoveryLogic.decision(hasReport: true, attempt: 1) == .accept)
        #expect(ImportRecoveryLogic.decision(hasReport: true, attempt: ImportRecoveryLogic.maxAttempts) == .accept)
    }

    @Test("No report with attempts remaining wipes and retries")
    func nilReportRetriesWhileAttemptsRemain() {
        for attempt in 1..<ImportRecoveryLogic.maxAttempts {
            #expect(ImportRecoveryLogic.decision(hasReport: false, attempt: attempt) == .wipeAndRetry)
        }
    }

    @Test("No report on the final attempt accepts without recovery — never fails the import")
    func nilReportOnFinalAttemptAccepts() {
        #expect(ImportRecoveryLogic.decision(hasReport: false, attempt: ImportRecoveryLogic.maxAttempts) == .acceptWithoutRecovery)
    }

    @Test("Retries are bounded")
    func retriesAreBounded() {
        // A regression to unlimited retries would loop a failing import
        // forever; past the cap the decision must terminate
        #expect(ImportRecoveryLogic.decision(hasReport: false, attempt: ImportRecoveryLogic.maxAttempts + 1) == .acceptWithoutRecovery)
        #expect(ImportRecoveryLogic.maxAttempts > 1)
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
