//
//  ExitStatusParserTests.swift
//  ArkéTests
//
//  Unit tests for ExitStatusParser
//  Created by Christoph on 4/27/26.
//

import Testing
import Foundation
import Bark

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Exit Status Parser Tests")
struct ExitStatusParserTests {
    
    // MARK: - State Type Parsing Tests
    
    @Test("Parse Start state")
    func testParseStartState() async throws {
        let input = "Start(ExitStartState { tip_height: 301492 })"
        let result = ExitStatusParser.parseState(input)
        
        if case .start(let data) = result {
            #expect(data.tipHeight == 301492)
        } else {
            Issue.record("Failed to parse Start state, got: \(String(describing: result))")
        }
    }
    
    @Test("Parse Claimed state")
    func testParseClaimedState() async throws {
        let input = "Claimed(ExitClaimedState { tip_height: 301797, txid: dc2b6582c0563df15e403fbae305b605273cc00d1d15ee1d99090b3f450bcbd0, block: 301628:000000015d9ea966e622a009bfcd733e74b1a9b8252f7e788e7c66164b42cf22 })"
        let result = ExitStatusParser.parseState(input)
        
        if case .claimed(let data) = result {
            #expect(data.tipHeight == 301797)
            #expect(data.txid == "dc2b6582c0563df15e403fbae305b605273cc00d1d15ee1d99090b3f450bcbd0")
            #expect(data.block.height == 301628)
            #expect(data.block.hash == "000000015d9ea966e622a009bfcd733e74b1a9b8252f7e788e7c66164b42cf22")
        } else {
            Issue.record("Failed to parse Claimed state, got: \(String(describing: result))")
        }
    }
    
    @Test("Parse VtxoAlreadySpent state")
    func testParseVtxoAlreadySpentState() async throws {
        let input = "VtxoAlreadySpent(ExitVtxoAlreadySpentState { tip_height: 301492 })"
        let result = ExitStatusParser.parseState(input)

        if case .vtxoAlreadySpent(let data) = result {
            #expect(data.tipHeight == 301492)
        } else {
            Issue.record("Failed to parse VtxoAlreadySpent state, got: \(String(describing: result))")
        }
    }

    @Test("Parse Canceled state (bark 0.4+)")
    func testParseCanceledState() async throws {
        let input = "Canceled(ExitCanceledState { tip_height: 301492 })"
        let result = ExitStatusParser.parseState(input)

        if case .canceled(let data) = result {
            #expect(data.tipHeight == 301492)
        } else {
            Issue.record("Failed to parse Canceled state, got: \(String(describing: result))")
        }
    }

    @Test("Parse AwaitingDelta state")
    func testParseAwaitingDeltaState() async throws {
        let input = "AwaitingDelta(ExitAwaitingDeltaState { tip_height: 301587, confirmed_block: 301543:000000094dd54e6609ccbfd6af266066e6e088f426b0c6d8f8990ffa2fee4e0d, claimable_height: 301555 })"
        let result = ExitStatusParser.parseState(input)
        
        if case .awaitingDelta(let data) = result {
            #expect(data.tipHeight == 301587)
            #expect(data.confirmedBlock.height == 301543)
            #expect(data.claimableHeight == 301555)
        } else {
            Issue.record("Failed to parse AwaitingDelta state, got: \(String(describing: result))")
        }
    }
    
    @Test("Parse Claimable state")
    func testParseClaimableState() async throws {
        let input = "Claimable(ExitClaimableState { tip_height: 301627, claimable_since: 301555:0000000b952992b6b5bd82159bb38933523a86123f7449dcf67c3ed3a7ef636d, last_scanned_block: None })"
        let result = ExitStatusParser.parseState(input)
        
        if case .claimable(let data) = result {
            #expect(data.tipHeight == 301627)
            #expect(data.claimableSince.height == 301555)
            #expect(data.lastScannedBlock == nil)
        } else {
            Issue.record("Failed to parse Claimable state, got: \(String(describing: result))")
        }
    }
    
    @Test("Parse ClaimInProgress state")
    func testParseClaimInProgressState() async throws {
        let input = "ClaimInProgress(ExitClaimInProgressState { tip_height: 301627, claimable_since: 301555:0000000b952992b6b5bd82159bb38933523a86123f7449dcf67c3ed3a7ef636d, claim_txid: dc2b6582c0563df15e403fbae305b605273cc00d1d15ee1d99090b3f450bcbd0 })"
        let result = ExitStatusParser.parseState(input)
        
        if case .claimInProgress(let data) = result {
            #expect(data.tipHeight == 301627)
            #expect(data.claimableSince.height == 301555)
            #expect(data.claimTxid == "dc2b6582c0563df15e403fbae305b605273cc00d1d15ee1d99090b3f450bcbd0")
        } else {
            Issue.record("Failed to parse ClaimInProgress state, got: \(String(describing: result))")
        }
    }
    
    @Test("Parse Processing state with transactions")
    func testParseProcessingState() async throws {
        let input = "Processing(ExitProcessingState { tip_height: 301492, transactions: [ExitTx { txid: 87c27c959bbaaa31d46cd9ee8c74156badd4d86ea06a2253d4a67286ea394216, status: VerifyInputs }, ExitTx { txid: 2fb55a939cff09e3380dd17bff529bdbb60e98a6a9623fbca9b7fd316485bc67, status: VerifyInputs }] })"
        let result = ExitStatusParser.parseState(input)
        
        if case .processing(let data) = result {
            #expect(data.tipHeight == 301492)
            #expect(data.transactions.count == 2)
            #expect(data.transactions[0].txid == "87c27c959bbaaa31d46cd9ee8c74156badd4d86ea06a2253d4a67286ea394216")
            #expect(data.transactions[1].txid == "2fb55a939cff09e3380dd17bff529bdbb60e98a6a9623fbca9b7fd316485bc67")
            
            if case .verifyInputs = data.transactions[0].status {
                // Success
            } else {
                Issue.record("Transaction status should be VerifyInputs")
            }
        } else {
            Issue.record("Failed to parse Processing state, got: \(String(describing: result))")
        }
    }
    
    // MARK: - Transaction Status Parsing Tests
    
    @Test("Parse VerifyInputs status")
    func testParseVerifyInputsStatus() async throws {
        let input = "Processing(ExitProcessingState { tip_height: 301492, transactions: [ExitTx { txid: 87c27c959bbaaa31d46cd9ee8c74156badd4d86ea06a2253d4a67286ea394216, status: VerifyInputs }] })"
        let result = ExitStatusParser.parseState(input)
        
        if case .processing(let data) = result,
           case .verifyInputs = data.transactions.first?.status {
            // Success
        } else {
            Issue.record("Failed to parse VerifyInputs status")
        }
    }
    
    @Test("Parse NeedsSignedPackage status")
    func testParseNeedsSignedPackageStatus() async throws {
        let input = "Processing(ExitProcessingState { tip_height: 301494, transactions: [ExitTx { txid: 2fb55a939cff09e3380dd17bff529bdbb60e98a6a9623fbca9b7fd316485bc67, status: NeedsSignedPackage }] })"
        let result = ExitStatusParser.parseState(input)
        
        if case .processing(let data) = result,
           case .needsSignedPackage = data.transactions.first?.status {
            // Success
        } else {
            Issue.record("Failed to parse NeedsSignedPackage status")
        }
    }
    
    @Test("Parse Confirmed status with block")
    func testParseConfirmedStatus() async throws {
        let input = "Processing(ExitProcessingState { tip_height: 301494, transactions: [ExitTx { txid: 87c27c959bbaaa31d46cd9ee8c74156badd4d86ea06a2253d4a67286ea394216, status: Confirmed { child_txid: cdcfdd1a2ff56d23d8a864b541f88dff168ad24dafe0df02213744b49fe9a285, block: 301493:0000000f806d48ff3118018de1f6053a8f97a4360ffca84613902c3e5777a359, origin: Wallet { confirmed_in: Some(301493:0000000f806d48ff3118018de1f6053a8f97a4360ffca84613902c3e5777a359) } } }] })"
        let result = ExitStatusParser.parseState(input)
        
        if case .processing(let data) = result,
           case .confirmed(let confirmedData) = data.transactions.first?.status {
            #expect(confirmedData.childTxid == "cdcfdd1a2ff56d23d8a864b541f88dff168ad24dafe0df02213744b49fe9a285")
            #expect(confirmedData.block.height == 301493)
            
            if case .wallet(let walletOrigin) = confirmedData.origin {
                #expect(walletOrigin.confirmedIn?.height == 301493)
            } else {
                Issue.record("Origin should be wallet")
            }
        } else {
            Issue.record("Failed to parse Confirmed status")
        }
    }
    
    @Test("Parse AwaitingInputConfirmation status")
    func testParseAwaitingInputConfirmationStatus() async throws {
        let input = "Processing(ExitProcessingState { tip_height: 301492, transactions: [ExitTx { txid: 2fb55a939cff09e3380dd17bff529bdbb60e98a6a9623fbca9b7fd316485bc67, status: AwaitingInputConfirmation { txids: {87c27c959bbaaa31d46cd9ee8c74156badd4d86ea06a2253d4a67286ea394216} } }] })"
        let result = ExitStatusParser.parseState(input)
        
        if case .processing(let data) = result,
           case .awaitingInputConfirmation(let awaitingData) = data.transactions.first?.status {
            #expect(awaitingData.dependencyTxids.contains("87c27c959bbaaa31d46cd9ee8c74156badd4d86ea06a2253d4a67286ea394216"))
        } else {
            Issue.record("Failed to parse AwaitingInputConfirmation status")
        }
    }
    
    // MARK: - BlockRef Tests
    
    @Test("Parse BlockRef from string")
    func testBlockRefParsing() async throws {
        let blockStr = "301628:000000015d9ea966e622a009bfcd733e74b1a9b8252f7e788e7c66164b42cf22"
        let blockRef = ArkeBlockRef(from: blockStr)
        
        #expect(blockRef != nil)
        #expect(blockRef?.height == 301628)
        #expect(blockRef?.hash == "000000015d9ea966e622a009bfcd733e74b1a9b8252f7e788e7c66164b42cf22")
    }
    
    @Test("BlockRef short hash")
    func testBlockRefShortHash() async throws {
        let blockRef = ArkeBlockRef(height: 301628, hash: "000000015d9ea966e622a009bfcd733e74b1a9b8252f7e788e7c66164b42cf22")
        #expect(blockRef.shortHash == "00000001...4b42cf22")
    }
    
    // MARK: - Transaction ID Extraction Tests
    
    @Test("Extract transaction IDs from Claimed state")
    func testExtractTxidsFromClaimedState() async throws {
        let input = "Claimed(ExitClaimedState { tip_height: 301797, txid: dc2b6582c0563df15e403fbae305b605273cc00d1d15ee1d99090b3f450bcbd0, block: 301628:000000015d9ea966e622a009bfcd733e74b1a9b8252f7e788e7c66164b42cf22 })"
        
        if let parsed = ExitStatusParser.parseState(input) {
            // Create a mock ExitTransactionStatus for testing
            let status = createMockStatus(state: input, history: nil)
            let txids = ExitStatusParser.extractAllTransactionIds(from: status)
            
            #expect(txids.contains("dc2b6582c0563df15e403fbae305b605273cc00d1d15ee1d99090b3f450bcbd0"))
        } else {
            Issue.record("Failed to parse state")
        }
    }
    
    @Test("Extract multiple transaction IDs from Processing state")
    func testExtractMultipleTxidsFromProcessingState() async throws {
        let input = "Processing(ExitProcessingState { tip_height: 301492, transactions: [ExitTx { txid: 87c27c959bbaaa31d46cd9ee8c74156badd4d86ea06a2253d4a67286ea394216, status: NeedsBroadcasting { child_txid: cdcfdd1a2ff56d23d8a864b541f88dff168ad24dafe0df02213744b49fe9a285, origin: Wallet { confirmed_in: None } } }, ExitTx { txid: 2fb55a939cff09e3380dd17bff529bdbb60e98a6a9623fbca9b7fd316485bc67, status: AwaitingInputConfirmation { txids: {87c27c959bbaaa31d46cd9ee8c74156badd4d86ea06a2253d4a67286ea394216} } }] })"
        
        let status = createMockStatus(state: input, history: nil)
        let txids = ExitStatusParser.extractAllTransactionIds(from: status)
        
        // Should extract: parent txids + child txid + dependency txid
        #expect(txids.contains("87c27c959bbaaa31d46cd9ee8c74156badd4d86ea06a2253d4a67286ea394216"))
        #expect(txids.contains("2fb55a939cff09e3380dd17bff529bdbb60e98a6a9623fbca9b7fd316485bc67"))
        #expect(txids.contains("cdcfdd1a2ff56d23d8a864b541f88dff168ad24dafe0df02213744b49fe9a285"))
    }
    
    // MARK: - History Parsing Tests
    
    @Test("Parse history array")
    func testParseHistory() async throws {
        let history = [
            "Start(ExitStartState { tip_height: 301492 })",
            "Processing(ExitProcessingState { tip_height: 301492, transactions: [ExitTx { txid: 87c27c959bbaaa31d46cd9ee8c74156badd4d86ea06a2253d4a67286ea394216, status: VerifyInputs }] })",
            "Claimed(ExitClaimedState { tip_height: 301797, txid: dc2b6582c0563df15e403fbae305b605273cc00d1d15ee1d99090b3f450bcbd0, block: 301628:000000015d9ea966e622a009bfcd733e74b1a9b8252f7e788e7c66164b42cf22 })"
        ]
        
        let parsed = ExitStatusParser.parseHistory(history)
        
        #expect(parsed.count == 3)
        
        if case .start = parsed[0] {
            // Success
        } else {
            Issue.record("First history item should be Start")
        }
        
        if case .processing = parsed[1] {
            // Success
        } else {
            Issue.record("Second history item should be Processing")
        }
        
        if case .claimed = parsed[2] {
            // Success
        } else {
            Issue.record("Third history item should be Claimed")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Build a status from legacy string fixtures via the v1 parse +
    /// reverse-map pipeline (same as persisted v1 snapshots)
    private func createMockStatus(state: String, history: [String]?) -> Bark.ExitTransactionStatus {
        return Bark.ExitTransactionStatus(
            vtxoId: "test:0",
            state: Bark.ExitState(from: ExitStatusParser.parseState(state) ?? .unparsed(state)),
            history: history.map { $0.map { Bark.ExitState(from: ExitStatusParser.parseState($0) ?? .unparsed($0)) } },
            transactionCount: 1
        )
    }
}
