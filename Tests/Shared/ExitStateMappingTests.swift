//
//  ExitStateMappingTests.swift
//  ArkéTests
//
//  Bark 0.16 typed exit state ↔ ParsedExitState mapping, and the
//  persisted snapshot's v2 format + v1 (Rust-Debug string) fallback.
//

import Testing
import Foundation
import Bark

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Exit State Mapping")
struct ExitStateMappingTests {

    private let block = Bark.BlockRef(height: 301_543, hash: "000000094dd54e6609ccbfd6af266066e6e088f426b0c6d8f8990ffa2fee4e0d")

    // MARK: Forward: Bark → ParsedExitState

    @Test("Simple states map with their tip heights")
    func testSimpleStates() {
        #expect(ParsedExitState(from: .start(tipHeight: 1)) == .start(.init(tipHeight: 1)))
        #expect(ParsedExitState(from: .vtxoAlreadySpent(tipHeight: 2)) == .vtxoAlreadySpent(.init(tipHeight: 2)))
        #expect(ParsedExitState(from: .canceled(tipHeight: 3)) == .canceled(.init(tipHeight: 3)))
    }

    @Test("AwaitingDelta carries confirmed block and claimable height")
    func testAwaitingDelta() {
        let parsed = ParsedExitState(from: .awaitingDelta(tipHeight: 301_587, confirmedBlock: block, claimableHeight: 301_555))
        guard case .awaitingDelta(let data) = parsed else {
            Issue.record("Expected awaitingDelta"); return
        }
        #expect(data.tipHeight == 301_587)
        #expect(data.confirmedBlock == ArkeBlockRef(height: block.height, hash: block.hash))
        #expect(data.claimableHeight == 301_555)
    }

    @Test("Processing maps nested transactions, statuses and origins")
    func testProcessingNested() {
        let state = Bark.ExitState.processing(tipHeight: 10, transactions: [
            Bark.ExitTx(txid: "aa", status: .verifyInputs),
            Bark.ExitTx(txid: "bb", status: .awaitingInputConfirmation(txids: ["cc", "dd"])),
            Bark.ExitTx(txid: "ee", status: .awaitingCpfpBroadcast),
            Bark.ExitTx(txid: "ff", status: .awaitingConfirmation(childTxid: "11", origin: .wallet(confirmedIn: nil))),
            Bark.ExitTx(txid: "22", status: .confirmed(childTxid: "33", block: block, origin: .block(confirmedIn: block)))
        ])

        guard case .processing(let data) = ParsedExitState(from: state) else {
            Issue.record("Expected processing"); return
        }
        #expect(data.transactions.count == 5)
        #expect(data.transactions[0].status == .verifyInputs)
        #expect(data.transactions[1].status == .awaitingInputConfirmation(.init(dependencyTxids: ["cc", "dd"])))
        #expect(data.transactions[2].status == .awaitingCpfpBroadcast)
        // Bark's AwaitingConfirmation folds into the app's broadcastWithCpfp
        #expect(data.transactions[3].status == .broadcastWithCpfp(.init(childTxid: "11", origin: .wallet(.init(confirmedIn: nil)))))
        guard case .confirmed(let confirmed) = data.transactions[4].status else {
            Issue.record("Expected confirmed"); return
        }
        #expect(confirmed.childTxid == "33")
        #expect(confirmed.origin == .block(confirmedIn: ArkeBlockRef(height: block.height, hash: block.hash)))
    }

    @Test("ClaimInProgress and Claimed carry their txids")
    func testClaimStates() {
        let inProgress = ParsedExitState(from: .claimInProgress(tipHeight: 5, claimableSince: block, claimTxid: "dc2b"))
        guard case .claimInProgress(let data) = inProgress else {
            Issue.record("Expected claimInProgress"); return
        }
        #expect(data.claimTxid == "dc2b")

        let claimed = ParsedExitState(from: .claimed(tipHeight: 6, txid: "dc2b", block: block))
        guard case .claimed(let claimedData) = claimed else {
            Issue.record("Expected claimed"); return
        }
        #expect(claimedData.txid == "dc2b")
    }

    // MARK: Reverse: ParsedExitState → Bark (snapshot reconstruction)

    @Test("Bark states survive a forward-then-reverse round trip")
    func testRoundTrip() {
        let states: [Bark.ExitState] = [
            .start(tipHeight: 1),
            .processing(tipHeight: 2, transactions: [
                Bark.ExitTx(txid: "aa", status: .awaitingInputConfirmation(txids: ["bb"])),
                Bark.ExitTx(txid: "cc", status: .confirmed(childTxid: "dd", block: block, origin: .wallet(confirmedIn: block)))
            ]),
            .awaitingDelta(tipHeight: 3, confirmedBlock: block, claimableHeight: 4),
            .claimable(tipHeight: 5, claimableSince: block, lastScannedBlock: nil),
            .claimInProgress(tipHeight: 6, claimableSince: block, claimTxid: "ee"),
            .claimed(tipHeight: 7, txid: "ff", block: block),
            .vtxoAlreadySpent(tipHeight: 8),
            .canceled(tipHeight: 9)
        ]
        for state in states {
            #expect(Bark.ExitState(from: ParsedExitState(from: state)) == state)
        }
    }

    @Test("Legacy pre-0.11 tx statuses map to their nearest Bark case")
    func testLegacyTxStatusFallbacks() {
        let origin = TxOrigin.wallet(.init(confirmedIn: nil))
        #expect(Bark.ExitTxStatus(from: .needsSignedPackage) == .verifyInputs)
        #expect(Bark.ExitTxStatus(from: .needsBroadcasting(.init(childTxid: "aa", origin: origin)))
                == .awaitingConfirmation(childTxid: "aa", origin: .wallet(confirmedIn: nil)))
        #expect(Bark.ExitTxStatus(from: .unparsed("garbage")) == .verifyInputs)
        // Unparsed origins must never count as wallet-funded
        #expect(Bark.ExitTxOrigin(from: .unparsed("garbage")) == .mempool)
        #expect(Bark.ExitState(from: .unparsed("SomeFutureState")) == .start(tipHeight: 0))
    }
}

@Suite("Exit Snapshot Format")
struct ExitSnapshotFormatTests {

    private let block = Bark.BlockRef(height: 301_628, hash: "000000015d9ea966e622a009bfcd733e74b1a9b8252f7e788e7c66164b42cf22")

    @Test("v2 snapshots round-trip through JSON")
    func testV2RoundTrip() throws {
        let status = Bark.ExitTransactionStatus(
            vtxoId: "vtxo_a",
            state: .claimed(tipHeight: 301_797, txid: "dc2b", block: block),
            history: [
                .start(tipHeight: 301_492),
                .processing(tipHeight: 301_494, transactions: [
                    Bark.ExitTx(txid: "aa", status: .awaitingConfirmation(childTxid: "bb", origin: .wallet(confirmedIn: block)))
                ])
            ],
            transactionCount: 1
        )

        let json = try #require(ExitStatusSnapshot.encodeJson(from: status))
        let decoded = try #require(ExitStatusSnapshot.decode(fromJson: json))
        #expect(decoded.version == ExitStatusSnapshot.currentVersion)
        #expect(decoded.status == status)
    }

    @Test("v1 snapshots (Rust-Debug strings) decode via the legacy parser")
    func testV1Fallback() throws {
        // Written by a pre-0.16 build: state/history are Rust-Debug strings
        let v1Json = """
        {"vtxoId":"vtxo_a",\
        "state":"Claimed(ExitClaimedState { tip_height: 301797, txid: dc2b6582c0563df15e403fbae305b605273cc00d1d15ee1d99090b3f450bcbd0, block: 301628:000000015d9ea966e622a009bfcd733e74b1a9b8252f7e788e7c66164b42cf22 })",\
        "history":["Start(ExitStartState { tip_height: 301492 })"],\
        "transactionCount":1}
        """

        let decoded = try #require(ExitStatusSnapshot.decode(fromJson: v1Json))
        #expect(decoded.version == ExitStatusSnapshot.currentVersion)
        guard case .claimed(let data) = decoded.state else {
            Issue.record("Expected claimed"); return
        }
        #expect(data.txid == "dc2b6582c0563df15e403fbae305b605273cc00d1d15ee1d99090b3f450bcbd0")
        #expect(decoded.history == [.start(.init(tipHeight: 301_492))])

        // Reconstruction keeps the claim inspectable through the same channels
        let status = decoded.status
        #expect(status.isClaimed)
        #expect(status.vtxoId == "vtxo_a")
    }

    @Test("v1 snapshots with pre-0.11 tx statuses still yield their txids")
    func testV1LegacyTxStatuses() throws {
        // BroadcastWithCpfp is bark ≤0.10 vocabulary — exists only on disk
        let v1Json = """
        {"vtxoId":"vtxo_b",\
        "state":"Processing(ExitProcessingState { tip_height: 313395, transactions: [ExitTx { txid: 613ea85cb823337443598fe005bb3fa01532cb3c0c9655c47023633851989a70, status: BroadcastWithCpfp { child_txid: 831c5580495b061457d298ea7220f0ce1dae2e2e14415d3a03edccbb2a169900, origin: Wallet { confirmed_in: None } } }] })",\
        "history":null,\
        "transactionCount":1}
        """

        let decoded = try #require(ExitStatusSnapshot.decode(fromJson: v1Json))
        let txids = ExitStatusParser.extractUserFundedTransactionIds(from: decoded.status)
        #expect(txids.contains("613ea85cb823337443598fe005bb3fa01532cb3c0c9655c47023633851989a70"))
        #expect(txids.contains("831c5580495b061457d298ea7220f0ce1dae2e2e14415d3a03edccbb2a169900"))
    }

    @Test("Garbage JSON decodes to nil, not a crash")
    func testGarbage() {
        #expect(ExitStatusSnapshot.decode(fromJson: "not json") == nil)
        #expect(ExitStatusSnapshot.decode(fromJson: "{\"foo\":1}") == nil)
    }
}
