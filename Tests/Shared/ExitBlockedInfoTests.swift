//
//  ExitBlockedInfoTests.swift
//  ArkéTests
//
//  Unit tests for ExitBlockedReason classification and ExitBlockedInfo debounce
//  Created by Christoph on 7/14/26.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Exit Blocked Info Tests")
struct ExitBlockedInfoTests {
    
    // MARK: - Classification
    
    @Test("Classify raw insufficient funds message from progressExits")
    func testClassifyInsufficientFundsRaw() {
        // ExitProgressStatus.error carries bark's ExitError display string directly
        let message = "Insufficient Confirmed Funds: 0.00012345 BTC is needed but only 0.00001000 BTC is available"
        #expect(ExitBlockedReason.classify(message) == .insufficientOnchainFunds)
    }
    
    @Test("Classify wrapped claim fee message from drainExits")
    func testClassifyClaimFeeWrapped() {
        // The drainExits throw arrives wrapped in FFI error layers (verified
        // against a real debug log from 2026-07-14)
        let message = "Configuration error: Failed to drain exits: Bark.Error.Inner(message: \"Drain exits failed: Claim Fee Exceeds Output: Cost to claim exits was 0.07026272 BTC, but the total output was 0.00039965 BTC\")"
        #expect(ExitBlockedReason.classify(message) == .claimFeeExceedsOutput)
    }
    
    @Test("Classify raw claim fee message")
    func testClassifyClaimFeeRaw() {
        let message = "Claim Fee Exceeds Output: Cost to claim exits was 0.07026272 BTC, but the total output was 0.00039965 BTC"
        #expect(ExitBlockedReason.classify(message) == .claimFeeExceedsOutput)
    }
    
    @Test("Unknown errors fall back to other")
    func testClassifyUnknownError() {
        let message = "Exit Package Broadcast Failure: Unable to broadcast exit transaction package abc123: bad-txns-inputs-missingorspent"
        #expect(ExitBlockedReason.classify(message) == .other)
    }
    
    // MARK: - Debounce
    
    @Test("Blocked state is not surfaceable after a single attempt")
    func testSingleAttemptNotSurfaceable() {
        let info = ExitBlockedInfo(
            reason: .claimFeeExceedsOutput,
            phase: .claim,
            rawErrorMessage: "Claim Fee Exceeds Output: ...",
            firstSeenAt: Date(),
            lastSeenAt: Date(),
            attemptCount: 1
        )
        #expect(!info.isSurfaceable)
    }
    
    @Test("Blocked state is surfaceable after two attempts")
    func testTwoAttemptsSurfaceable() {
        let info = ExitBlockedInfo(
            reason: .claimFeeExceedsOutput,
            phase: .claim,
            rawErrorMessage: "Claim Fee Exceeds Output: ...",
            firstSeenAt: Date(),
            lastSeenAt: Date(),
            attemptCount: 2
        )
        #expect(info.isSurfaceable)
    }

    // MARK: - Persistence

    @Test("ExitBlockedInfo round-trips through JSON")
    func testJsonRoundTrip() throws {
        // Persistence in PersistentExitCache.blockedInfoJson relies on this
        let original = ExitBlockedInfo(
            reason: .insufficientOnchainFunds,
            phase: .progression,
            rawErrorMessage: "Insufficient Confirmed Funds: 0.00012345 BTC is needed but only 0.00001000 BTC is available",
            firstSeenAt: Date(timeIntervalSince1970: 1_784_000_000),
            lastSeenAt: Date(timeIntervalSince1970: 1_784_000_300),
            attemptCount: 3
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExitBlockedInfo.self, from: data)

        #expect(decoded == original)
        #expect(decoded.isSurfaceable)
    }
}
