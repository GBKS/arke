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
}
