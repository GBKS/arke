//
//  ParsedExitState+Bark.swift
//  Arké
//
//  Mapping between Bark's typed exit state (v0.16+) and the app's
//  ParsedExitState domain model.
//

import Foundation
import Bark

// MARK: - Bark 0.16 typed-state mapping
//
// Forward (Bark → app): total, used for every live status.
// Reverse (app → Bark): used only to reconstruct an ExitTransactionStatus
// from a persisted snapshot, so completed exits keep flowing through the
// same channels as live ones. App-only legacy cases (pre-0.11 tx statuses,
// unparsed strings) map to the nearest Bark case — see the fallback notes.

// MARK: - Forward: Bark → ParsedExitState

nonisolated extension ParsedExitState {

    /// Map Bark's typed exit state onto the app's domain model. Total —
    /// never produces `.unparsed`.
    init(from state: Bark.ExitState) {
        switch state {
        case .start(let tipHeight):
            self = .start(.init(tipHeight: tipHeight))
        case .processing(let tipHeight, let transactions):
            self = .processing(.init(
                tipHeight: tipHeight,
                transactions: transactions.map { ExitTransaction(from: $0) }
            ))
        case .awaitingDelta(let tipHeight, let confirmedBlock, let claimableHeight):
            self = .awaitingDelta(.init(
                tipHeight: tipHeight,
                confirmedBlock: ArkeBlockRef(from: confirmedBlock),
                claimableHeight: claimableHeight
            ))
        case .claimable(let tipHeight, let claimableSince, let lastScannedBlock):
            self = .claimable(.init(
                tipHeight: tipHeight,
                claimableSince: ArkeBlockRef(from: claimableSince),
                lastScannedBlock: lastScannedBlock.map { ArkeBlockRef(from: $0) }
            ))
        case .claimInProgress(let tipHeight, let claimableSince, let claimTxid):
            self = .claimInProgress(.init(
                tipHeight: tipHeight,
                claimableSince: ArkeBlockRef(from: claimableSince),
                claimTxid: claimTxid
            ))
        case .claimed(let tipHeight, let txid, let block):
            self = .claimed(.init(
                tipHeight: tipHeight,
                txid: txid,
                block: ArkeBlockRef(from: block)
            ))
        case .vtxoAlreadySpent(let tipHeight):
            self = .vtxoAlreadySpent(.init(tipHeight: tipHeight))
        case .canceled(let tipHeight):
            self = .canceled(.init(tipHeight: tipHeight))
        }
    }
}

nonisolated extension ExitTransaction {
    init(from tx: Bark.ExitTx) {
        self.init(txid: tx.txid, status: ExitTxStatus(from: tx.status))
    }
}

nonisolated extension ExitTxStatus {
    init(from status: Bark.ExitTxStatus) {
        switch status {
        case .verifyInputs:
            self = .verifyInputs
        case .awaitingInputConfirmation(let txids):
            self = .awaitingInputConfirmation(.init(dependencyTxids: Set(txids)))
        case .awaitingCpfpBroadcast:
            self = .awaitingCpfpBroadcast
        case .awaitingConfirmation(let childTxid, let origin):
            // The app case covers bark's BroadcastWithCpfp (≤0.10) and
            // AwaitingConfirmation (0.11+) — see its doc comment
            self = .broadcastWithCpfp(.init(childTxid: childTxid, origin: TxOrigin(from: origin)))
        case .confirmed(let childTxid, let block, let origin):
            self = .confirmed(.init(
                childTxid: childTxid,
                block: ArkeBlockRef(from: block),
                origin: TxOrigin(from: origin)
            ))
        }
    }
}

nonisolated extension TxOrigin {
    init(from origin: Bark.ExitTxOrigin) {
        switch origin {
        case .wallet(let confirmedIn):
            self = .wallet(.init(confirmedIn: confirmedIn.map { ArkeBlockRef(from: $0) }))
        case .mempool:
            self = .mempool
        case .block(let confirmedIn):
            self = .block(confirmedIn: ArkeBlockRef(from: confirmedIn))
        }
    }
}

nonisolated extension ArkeBlockRef {
    init(from block: Bark.BlockRef) {
        self.init(height: block.height, hash: block.hash)
    }
}

// MARK: - Reverse: ParsedExitState → Bark

nonisolated extension Bark.ExitState {

    /// Reconstruct a Bark exit state from a persisted snapshot's parsed
    /// state, so completed exits (purged by bark) keep flowing through the
    /// same `ExitTransactionStatus` channels as live ones.
    ///
    /// Fallback for `.unparsed` (a pre-0.16 snapshot string the legacy
    /// parser couldn't read — not observed in practice): `.start(tipHeight: 0)`,
    /// the least-specific state, which renders as "preparing".
    init(from parsed: ParsedExitState) {
        switch parsed {
        case .start(let data):
            self = .start(tipHeight: data.tipHeight)
        case .processing(let data):
            self = .processing(
                tipHeight: data.tipHeight,
                transactions: data.transactions.map { Bark.ExitTx(from: $0) }
            )
        case .awaitingDelta(let data):
            self = .awaitingDelta(
                tipHeight: data.tipHeight,
                confirmedBlock: Bark.BlockRef(from: data.confirmedBlock),
                claimableHeight: data.claimableHeight
            )
        case .claimable(let data):
            self = .claimable(
                tipHeight: data.tipHeight,
                claimableSince: Bark.BlockRef(from: data.claimableSince),
                lastScannedBlock: data.lastScannedBlock.map { Bark.BlockRef(from: $0) }
            )
        case .claimInProgress(let data):
            self = .claimInProgress(
                tipHeight: data.tipHeight,
                claimableSince: Bark.BlockRef(from: data.claimableSince),
                claimTxid: data.claimTxid
            )
        case .claimed(let data):
            self = .claimed(
                tipHeight: data.tipHeight,
                txid: data.txid,
                block: Bark.BlockRef(from: data.block)
            )
        case .vtxoAlreadySpent(let data):
            self = .vtxoAlreadySpent(tipHeight: data.tipHeight)
        case .canceled(let data):
            self = .canceled(tipHeight: data.tipHeight)
        case .unparsed:
            self = .start(tipHeight: 0)
        }
    }
}

nonisolated extension Bark.ExitTx {
    init(from tx: ExitTransaction) {
        self.init(txid: tx.txid, status: Bark.ExitTxStatus(from: tx.status))
    }
}

nonisolated extension Bark.ExitTxStatus {

    /// Fallbacks for app-only cases, which occur only in snapshots written
    /// by pre-0.11 bark versions:
    /// - `.needsSignedPackage` → `.verifyInputs` (not yet broadcastable)
    /// - `.needsBroadcasting` → `.awaitingConfirmation` (same payload; the
    ///   forward mapper folds bark's AwaitingConfirmation into the app's
    ///   `.broadcastWithCpfp` for the same reason)
    /// - `.unparsed` → `.verifyInputs` (least-specific; carries no txids)
    init(from status: ExitTxStatus) {
        switch status {
        case .verifyInputs:
            self = .verifyInputs
        case .needsSignedPackage:
            self = .verifyInputs
        case .awaitingCpfpBroadcast:
            self = .awaitingCpfpBroadcast
        case .needsBroadcasting(let data):
            self = .awaitingConfirmation(childTxid: data.childTxid, origin: Bark.ExitTxOrigin(from: data.origin))
        case .broadcastWithCpfp(let data):
            self = .awaitingConfirmation(childTxid: data.childTxid, origin: Bark.ExitTxOrigin(from: data.origin))
        case .awaitingInputConfirmation(let data):
            self = .awaitingInputConfirmation(txids: data.dependencyTxids.sorted())
        case .confirmed(let data):
            self = .confirmed(
                childTxid: data.childTxid,
                block: Bark.BlockRef(from: data.block),
                origin: Bark.ExitTxOrigin(from: data.origin)
            )
        case .unparsed:
            self = .verifyInputs
        }
    }
}

nonisolated extension Bark.ExitTxOrigin {

    /// `.unparsed` falls back to `.mempool`: a third-party origin, so the
    /// child's fee is never attributed to the user on a parsing gap —
    /// matching `TxOrigin.isWallet`'s own convention.
    init(from origin: TxOrigin) {
        switch origin {
        case .wallet(let data):
            self = .wallet(confirmedIn: data.confirmedIn.map { Bark.BlockRef(from: $0) })
        case .mempool:
            self = .mempool
        case .block(let confirmedIn):
            if let confirmedIn {
                self = .block(confirmedIn: Bark.BlockRef(from: confirmedIn))
            } else {
                self = .mempool
            }
        case .unparsed:
            self = .mempool
        }
    }
}

nonisolated extension Bark.BlockRef {
    init(from block: ArkeBlockRef) {
        self.init(height: block.height, hash: block.hash)
    }
}
