//
//  ExitFeeAttributionTests.swift
//  Arke
//
//  Regression tests for fee attribution on unilateral exits, based on a real
//  signet exit (VTXO c866e398…:0). Exit anchors are anyone-can-spend: one of
//  the four exit transactions was fee-bumped by a THIRD PARTY (2c776835…,
//  origin: Block), and its 9,896-sat fee must never be attributed to the
//  user. The user's true cost is 31,625 sats: three wallet CPFPs
//  (9,901 + 9,785 + 8,563) plus the claim fee (3,376).
//

import Testing
import SwiftData
import Foundation
import Bark
import ArkeUI

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

// MARK: - Signet fixture (real txids)

private enum Fixture {
    // Exit package transactions, in chain order
    static let tx1 = "613ea85cb823337443598fe005bb3fa01532cb3c0c9655c47023633851989a70"
    static let tx2 = "37c923e5eb79b93d2aa14090bf512ae77b6424f398fc4bc937d6f5a90f9166c7"
    static let tx3 = "80b4066ce0b4eb922b1e5677fe209176c4bc3260829e042e8e6b90cbe0f50c96"
    static let tx4 = "c866e398d5a5448cca8f7356009d0dd79d875f2865bf270c9461cad5ca0c30b5"

    // CPFP children spending the anchors
    static let cpfp1 = "831c5580495b061457d298ea7220f0ce1dae2e2e14415d3a03edccbb2a169900"  // user, 9,901 sats
    static let cpfp2 = "1cabbe0e9860990c6229f368e68e10f5c99d1f1f7194da09c844f8e35ab9ccbb"  // user, 9,785 sats
    static let cpfp3 = "2c776835b6d37d4044f6b3eb9b6207c4d0ca31a26905d2df887786015b6de063"  // THIRD PARTY, 9,896 sats
    static let cpfp4 = "0d7a4ebe4ba3e8bb11b1c4077c851edd9e179a67b906a3bdb91ec95ca2ac83f8"  // user, 8,563 sats

    static let claim = "78d9120defb9eff71934619a0699d280699f7402f9bccb73f37e21af8b846cf8"  // 3,376 sats

    static let block1 = "313391:000000053483b42c382a52b4c1b9f23b57fc87c1fc38057dabf46136a58799d6"
    static let block2 = "313392:0000000191b40f051fbb35ad4b735228a58aaeb7da4d640565bb37264b8c19cb"
    static let block3 = "313395:00000005cd533b07d8cd81337789a01911fde77bc3979aa5cf3dae96eef099fa"
    static let claimBlock = "313411:000000075560dbb2e7bda5b02203212b68dbd0d821fffdd66c057fde809a1152"

    /// The final Processing snapshot from the real exit history. Tx4's child
    /// only ever appears in an AwaitingConfirmation status (the exit jumped
    /// to AwaitingDelta before a Confirmed snapshot was written), and Tx3's
    /// child is the third party's (origin: Block).
    static let finalProcessing = """
        Processing(ExitProcessingState { tip_height: 313395, transactions: [\
        ExitTx { txid: \(tx1), status: Confirmed { child_txid: \(cpfp1), block: \(block1), origin: Wallet { confirmed_in: Some(\(block1)) } } }, \
        ExitTx { txid: \(tx2), status: Confirmed { child_txid: \(cpfp2), block: \(block2), origin: Wallet { confirmed_in: Some(\(block2)) } } }, \
        ExitTx { txid: \(tx3), status: Confirmed { child_txid: \(cpfp3), block: \(block3), origin: Block { confirmed_in: \(block3) } } }, \
        ExitTx { txid: \(tx4), status: AwaitingConfirmation { child_txid: \(cpfp4), origin: Wallet { confirmed_in: None } } }] })
        """

    static let claimedState = "Claimed(ExitClaimedState { tip_height: 313418, txid: \(claim), block: \(claimBlock) })"

    static func status() -> ExitTransactionStatus {
        ExitTransactionStatus(
            vtxoId: "\(tx4):0",
            state: claimedState,
            history: [
                "Start(ExitStartState { tip_height: 313389 })",
                finalProcessing,
                "ClaimInProgress(ExitClaimInProgressState { tip_height: 313408, claimable_since: 313408:0000000e22c16b0092658a78a3791dba2c9a111b1bdbb66821c9257cc995916a, claim_txid: \(claim) })"
            ],
            transactionCount: 4
        )
    }
}

// MARK: - Parser: bark 0.11 status variants and origins

@Suite("Exit Fee Attribution — Parser")
struct ExitFeeAttributionParserTests {

    @Test("AwaitingConfirmation parses with child txid and wallet origin")
    func testAwaitingConfirmationParsed() throws {
        let result = ExitStatusParser.parseState(Fixture.finalProcessing)

        guard case .processing(let data) = result else {
            Issue.record("Expected Processing state, got \(String(describing: result))")
            return
        }
        let tx4 = try #require(data.transactions.first { $0.txid == Fixture.tx4 })

        guard case .broadcastWithCpfp(let cpfp) = tx4.status else {
            Issue.record("Expected broadcastWithCpfp for AwaitingConfirmation, got \(tx4.status)")
            return
        }
        #expect(cpfp.childTxid == Fixture.cpfp4)
        #expect(cpfp.origin.isWallet)
    }

    @Test("AwaitingCpfpBroadcast parses as its own status")
    func testAwaitingCpfpBroadcastParsed() throws {
        let input = "Processing(ExitProcessingState { tip_height: 313389, transactions: [ExitTx { txid: \(Fixture.tx1), status: AwaitingCpfpBroadcast }] })"
        let result = ExitStatusParser.parseState(input)

        guard case .processing(let data) = result,
              let tx = data.transactions.first else {
            Issue.record("Expected Processing state with one tx, got \(String(describing: result))")
            return
        }
        #expect(tx.status == .awaitingCpfpBroadcast)
    }

    @Test("Third-party anchor spend parses with Block origin, not wallet")
    func testThirdPartyOriginParsed() throws {
        let result = ExitStatusParser.parseState(Fixture.finalProcessing)

        guard case .processing(let data) = result else {
            Issue.record("Expected Processing state")
            return
        }
        let tx3 = try #require(data.transactions.first { $0.txid == Fixture.tx3 })
        let child = try #require(tx3.status.cpfpChild)

        #expect(child.txid == Fixture.cpfp3)
        #expect(!child.origin.isWallet)
        guard case .block(let confirmedIn) = child.origin else {
            Issue.record("Expected .block origin, got \(child.origin)")
            return
        }
        #expect(confirmedIn?.height == 313395)
    }

    @Test("Mempool origin parses and is not wallet")
    func testMempoolOriginParsed() throws {
        let input = "Processing(ExitProcessingState { tip_height: 313394, transactions: [ExitTx { txid: \(Fixture.tx3), status: AwaitingConfirmation { child_txid: \(Fixture.cpfp3), origin: Mempool } }] })"
        let result = ExitStatusParser.parseState(input)

        guard case .processing(let data) = result,
              let tx = data.transactions.first,
              let child = tx.status.cpfpChild else {
            Issue.record("Expected Processing state with parsed child")
            return
        }
        #expect(child.origin == .mempool)
        #expect(!child.origin.isWallet)
    }

    @Test("User-funded extraction excludes the third-party CPFP")
    func testUserFundedExtractionExcludesThirdParty() {
        let status = Fixture.status()

        let userFunded = Set(ExitStatusParser.extractUserFundedTransactionIds(from: status))
        let all = Set(ExitStatusParser.extractAllTransactionIds(from: status))

        // Package txs, wallet CPFPs and claim are the user's
        for txid in [Fixture.tx1, Fixture.tx2, Fixture.tx3, Fixture.tx4,
                     Fixture.cpfp1, Fixture.cpfp2, Fixture.cpfp4, Fixture.claim] {
            #expect(userFunded.contains(txid), "missing \(txid.prefix(16))")
        }
        // The third party's CPFP is excluded from linking/fee attribution…
        #expect(!userFunded.contains(Fixture.cpfp3))
        // …but stays visible in the full set (step detail shows it as
        // externally fee-bumped rather than silently dropping it)
        #expect(all.contains(Fixture.cpfp3))
        #expect(all.subtracting(userFunded) == [Fixture.cpfp3])
    }
}

// MARK: - Fee summation with the fixture records

@Suite("Exit Fee Attribution — Totals")
@MainActor
struct ExitFeeAttributionTotalsTests {

    private func createTestContainer() throws -> ModelContainer {
        let schema = Schema([
            PersistentTransaction.self,
            PendingPaymentMetadata.self,
            PendingTagAssignment.self,
            PersistentTag.self,
            PersistentContact.self,
            TransactionTagAssignment.self,
            TransactionContactAssignment.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Insert an onchain wallet record like UnifiedTransactionService creates
    private func insertOnchainRecord(
        txid: String,
        fee: Int?,
        sent: UInt64,
        subsystemKind: String,
        context: ModelContext
    ) {
        let record = PersistentTransaction(
            txid: "onchain_\(txid)",
            movementId: nil,
            type: sent > 0 ? .sent : .received,
            amount: 0,
            date: Date(),
            status: .confirmed,
            address: nil,
            subsystemCategory: "onchain_transaction"
        )
        record.sourceType = "onchain"
        record.onchainSent = sent
        record.onchainFeeSat = fee
        record.subsystemKind = subsystemKind
        context.insert(record)
    }

    @Test("userPaidOnchainFeeSat gates on funding and claim marker")
    func testUserPaidFeeGate() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        insertOnchainRecord(txid: Fixture.cpfp1, fee: 9901, sent: 50000, subsystemKind: "self_transfer", context: context)
        insertOnchainRecord(txid: Fixture.cpfp3, fee: 9896, sent: 0, subsystemKind: "receive", context: context)
        insertOnchainRecord(txid: Fixture.claim, fee: 3376, sent: 0, subsystemKind: "exit_claim", context: context)
        try context.save()

        func record(_ txid: String) throws -> PersistentTransaction {
            let namespaced = "onchain_\(txid)"
            let descriptor = FetchDescriptor<PersistentTransaction>(
                predicate: #Predicate { $0.txid == namespaced }
            )
            return try #require(try context.fetch(descriptor).first)
        }

        // Wallet-funded CPFP: fee counts
        #expect(try record(Fixture.cpfp1).userPaidOnchainFeeSat == 9901)
        // Known-unfunded record (third-party bump): fee never counts
        #expect(try record(Fixture.cpfp3).userPaidOnchainFeeSat == nil)
        // Claim: unfunded from BDK's view, but fee persisted from bark counts
        #expect(try record(Fixture.claim).userPaidOnchainFeeSat == 3376)
    }

    @Test("Exit movement total is 31,625 sats — even with a poisoned third-party link")
    func testExitFeeTotalExcludesThirdParty() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        insertOnchainRecord(txid: Fixture.cpfp1, fee: 9901, sent: 50000, subsystemKind: "self_transfer", context: context)
        insertOnchainRecord(txid: Fixture.cpfp2, fee: 9785, sent: 40099, subsystemKind: "self_transfer", context: context)
        insertOnchainRecord(txid: Fixture.cpfp4, fee: 8563, sent: 50000, subsystemKind: "self_transfer", context: context)
        insertOnchainRecord(txid: Fixture.claim, fee: 3376, sent: 0, subsystemKind: "exit_claim", context: context)
        // Poisoned record: a third party's CPFP that somehow got a fee —
        // deliberately linked below to prove the read-time guard holds even
        // if linking ever regresses
        insertOnchainRecord(txid: Fixture.cpfp3, fee: 9896, sent: 0, subsystemKind: "receive", context: context)

        let movement = PersistentTransaction(
            txid: "movement_2",
            movementId: 2,
            type: .transfer,
            amount: 10000,
            date: Date(),
            status: .confirmed,
            address: nil,
            fees: 0,
            subsystemCategory: "exit",
            subsystemName: "bark.exit",
            subsystemKind: "start"
        )
        movement.childTxids = [Fixture.cpfp1, Fixture.cpfp2, Fixture.cpfp3, Fixture.cpfp4, Fixture.claim]
            .map { "onchain_\($0)" }
        context.insert(movement)
        try context.save()

        let model = TransactionModel(from: movement)
        let total = model.totalFeesIncludingLinked(modelContext: context)

        // 9,901 + 9,785 + 8,563 + 3,376 — NOT 41,521 (which would include
        // the third party's 9,896)
        #expect(total == 31625)
    }

    // MARK: - Fee shares for children linked by multiple exit movements

    /// Insert an exit movement like the ones bark creates (one per exiting VTXO)
    private func makeExitMovement(
        txid: String,
        movementId: Int,
        children: [String],
        context: ModelContext
    ) -> PersistentTransaction {
        let movement = PersistentTransaction(
            txid: txid,
            movementId: movementId,
            type: .transfer,
            amount: 10000,
            date: Date(),
            status: .confirmed,
            address: nil,
            fees: 0,
            subsystemCategory: "exit",
            subsystemName: "bark.exit",
            subsystemKind: "start"
        )
        movement.childTxids = children.map { "onchain_\($0)" }
        context.insert(movement)
        return movement
    }

    @Test("Shared children split fees across linking movements; totals sum to what was paid")
    func testSharedChildFeeShares() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        // Two sibling exits: cpfp1 bumps a shared exit-package ancestor and the
        // claim tx drains both VTXOs, so both movements link them. cpfp2
        // belongs to movement A alone.
        insertOnchainRecord(txid: Fixture.cpfp1, fee: 9901, sent: 50000, subsystemKind: "self_transfer", context: context)
        insertOnchainRecord(txid: Fixture.cpfp2, fee: 9785, sent: 40099, subsystemKind: "self_transfer", context: context)
        insertOnchainRecord(txid: Fixture.claim, fee: 3376, sent: 0, subsystemKind: "exit_claim", context: context)

        let movementA = makeExitMovement(
            txid: "movement_10",
            movementId: 10,
            children: [Fixture.cpfp1, Fixture.cpfp2, Fixture.claim],
            context: context
        )
        let movementB = makeExitMovement(
            txid: "movement_11",
            movementId: 11,
            children: [Fixture.cpfp1, Fixture.claim],
            context: context
        )
        try context.save()

        let totalA = TransactionModel(from: movementA).totalFeesIncludingLinked(modelContext: context)
        let totalB = TransactionModel(from: movementB).totalFeesIncludingLinked(modelContext: context)

        // cpfp1 splits 4,951/4,950 (odd fee, remainder to movement_10),
        // the claim splits 1,688/1,688, cpfp2 stays whole with movement A
        #expect(totalA == 4951 + 1688 + 9785)
        #expect(totalB == 4950 + 1688)
        // Combined: exactly what the wallet paid, nothing counted twice
        #expect(totalA + totalB == 9901 + 9785 + 3376)
    }

    @Test("Odd shared fee: remainder goes to the first movement by txid")
    func testSharedFeeRemainderDeterministic() throws {
        let container = try createTestContainer()
        let context = container.mainContext

        insertOnchainRecord(txid: Fixture.claim, fee: 3377, sent: 0, subsystemKind: "exit_claim", context: context)

        let movementA = makeExitMovement(txid: "movement_20", movementId: 20, children: [Fixture.claim], context: context)
        let movementB = makeExitMovement(txid: "movement_21", movementId: 21, children: [Fixture.claim], context: context)
        try context.save()

        let totalA = TransactionModel(from: movementA).totalFeesIncludingLinked(modelContext: context)
        let totalB = TransactionModel(from: movementB).totalFeesIncludingLinked(modelContext: context)

        #expect(totalA == 1689)
        #expect(totalB == 1688)
        #expect(totalA + totalB == 3377)
    }
}
