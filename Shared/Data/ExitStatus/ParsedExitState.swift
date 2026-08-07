//
//  ParsedExitState.swift
//  Arké
//
//  Parsed exit state structures from Bark SDK
//  Created by Christoph on 4/27/26.
//

import Foundation

/// Parsed exit state with structured data
nonisolated public enum ParsedExitState: Equatable, Codable {
    case start(StartState)
    case processing(ProcessingState)
    case awaitingDelta(AwaitingDeltaState)
    case claimable(ClaimableState)
    case claimInProgress(ClaimInProgressState)
    case claimed(ClaimedState)
    case vtxoAlreadySpent(VtxoAlreadySpentState)
    case canceled(CanceledState)
    case unparsed(String) // Fallback for unknown states
    
    nonisolated public struct StartState: Equatable, Codable {
        public let tipHeight: UInt32
        
        public init(tipHeight: UInt32) {
            self.tipHeight = tipHeight
        }
    }
    
    nonisolated public struct ProcessingState: Equatable, Codable {
        public let tipHeight: UInt32
        public let transactions: [ExitTransaction]
        
        public init(tipHeight: UInt32, transactions: [ExitTransaction]) {
            self.tipHeight = tipHeight
            self.transactions = transactions
        }
    }
    
    nonisolated public struct AwaitingDeltaState: Equatable, Codable {
        public let tipHeight: UInt32
        public let confirmedBlock: ArkeBlockRef
        public let claimableHeight: UInt32
        
        public init(tipHeight: UInt32, confirmedBlock: ArkeBlockRef, claimableHeight: UInt32) {
            self.tipHeight = tipHeight
            self.confirmedBlock = confirmedBlock
            self.claimableHeight = claimableHeight
        }
    }
    
    nonisolated public struct ClaimableState: Equatable, Codable {
        public let tipHeight: UInt32
        public let claimableSince: ArkeBlockRef
        public let lastScannedBlock: ArkeBlockRef?
        
        public init(tipHeight: UInt32, claimableSince: ArkeBlockRef, lastScannedBlock: ArkeBlockRef?) {
            self.tipHeight = tipHeight
            self.claimableSince = claimableSince
            self.lastScannedBlock = lastScannedBlock
        }
    }
    
    nonisolated public struct ClaimInProgressState: Equatable, Codable {
        public let tipHeight: UInt32
        public let claimableSince: ArkeBlockRef
        public let claimTxid: String
        
        public init(tipHeight: UInt32, claimableSince: ArkeBlockRef, claimTxid: String) {
            self.tipHeight = tipHeight
            self.claimableSince = claimableSince
            self.claimTxid = claimTxid
        }
    }
    
    nonisolated public struct ClaimedState: Equatable, Codable {
        public let tipHeight: UInt32
        public let txid: String
        public let block: ArkeBlockRef

        public init(tipHeight: UInt32, txid: String, block: ArkeBlockRef) {
            self.tipHeight = tipHeight
            self.txid = txid
            self.block = block
        }
    }

    /// Terminal state: the exit cannot proceed because the VTXO was already
    /// consumed by something other than this exit (e.g. spent via refresh/arkoor,
    /// or forfeited by the server in a round). No exit transactions get broadcast.
    nonisolated public struct VtxoAlreadySpentState: Equatable, Codable {
        public let tipHeight: UInt32

        public init(tipHeight: UInt32) {
            self.tipHeight = tipHeight
        }
    }

    /// The exit was cancelled before its transactions were broadcast (bark 0.4+).
    /// Not producible via this app's bindings yet (no cancel-exit API), but can
    /// appear if the datadir was driven by bark-cli or a future bindings bump.
    nonisolated public struct CanceledState: Equatable, Codable {
        public let tipHeight: UInt32

        public init(tipHeight: UInt32) {
            self.tipHeight = tipHeight
        }
    }
}

/// Individual exit transaction in the chain
nonisolated public struct ExitTransaction: Equatable, Codable {
    public let txid: String
    public let status: ExitTxStatus
    
    public init(txid: String, status: ExitTxStatus) {
        self.txid = txid
        self.status = status
    }
}

/// Status of an exit transaction
nonisolated public enum ExitTxStatus: Equatable, Codable {
    case verifyInputs
    case needsSignedPackage
    /// Bark 0.11: the CPFP child for this transaction has not been created
    /// or broadcast yet. Carries no payload.
    case awaitingCpfpBroadcast
    case needsBroadcasting(NeedsBroadcastingData)
    /// A CPFP child spending this transaction's anchor has been broadcast and
    /// is awaiting confirmation. Covers bark's `BroadcastWithCpfp` (≤0.10)
    /// and `AwaitingConfirmation` (0.11+) debug variants.
    case broadcastWithCpfp(BroadcastWithCpfpData)
    case awaitingInputConfirmation(AwaitingInputData)
    case confirmed(ConfirmedData)
    case unparsed(String)

    /// The CPFP child that spent this transaction's anchor, if known.
    /// Anchors are anyone-can-spend, so check `origin` before attributing
    /// the child's fee to the user.
    public var cpfpChild: (txid: String, origin: TxOrigin)? {
        switch self {
        case .needsBroadcasting(let data):
            return (data.childTxid, data.origin)
        case .broadcastWithCpfp(let data):
            return (data.childTxid, data.origin)
        case .confirmed(let data):
            return (data.childTxid, data.origin)
        default:
            return nil
        }
    }
    
    nonisolated public struct NeedsBroadcastingData: Equatable, Codable {
        public let childTxid: String
        public let origin: TxOrigin
        
        public init(childTxid: String, origin: TxOrigin) {
            self.childTxid = childTxid
            self.origin = origin
        }
    }
    
    nonisolated public struct BroadcastWithCpfpData: Equatable, Codable {
        public let childTxid: String
        public let origin: TxOrigin
        
        public init(childTxid: String, origin: TxOrigin) {
            self.childTxid = childTxid
            self.origin = origin
        }
    }
    
    nonisolated public struct AwaitingInputData: Equatable, Codable {
        public let dependencyTxids: Set<String>
        
        public init(dependencyTxids: Set<String>) {
            self.dependencyTxids = dependencyTxids
        }
    }
    
    nonisolated public struct ConfirmedData: Equatable, Codable {
        public let childTxid: String
        public let block: ArkeBlockRef
        public let origin: TxOrigin
        
        public init(childTxid: String, block: ArkeBlockRef, origin: TxOrigin) {
            self.childTxid = childTxid
            self.block = block
            self.origin = origin
        }
    }
}

/// Origin of a CPFP transaction spending an exit anchor. Anchors are
/// anyone-can-spend, so bark distinguishes children it created itself
/// (`Wallet`) from ones it merely observed onchain (`Mempool`/`Block`) —
/// the latter were funded and paid for by a third party.
nonisolated public enum TxOrigin: Equatable, Codable {
    case wallet(WalletOrigin)
    /// Third-party anchor spend observed in the mempool.
    case mempool
    /// Third-party anchor spend observed in a block.
    case block(confirmedIn: ArkeBlockRef?)
    case unparsed(String)

    /// Whether this wallet created (and funded) the transaction.
    /// Unparsed origins count as not ours, so fees are never attributed
    /// to the user on a parsing gap.
    public var isWallet: Bool {
        if case .wallet = self { return true }
        return false
    }

    nonisolated public struct WalletOrigin: Equatable, Codable {
        public let confirmedIn: ArkeBlockRef?

        public init(confirmedIn: ArkeBlockRef?) {
            self.confirmedIn = confirmedIn
        }
    }
}
