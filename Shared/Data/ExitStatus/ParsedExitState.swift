//
//  ParsedExitState.swift
//  Arké
//
//  Parsed exit state structures from Bark SDK
//  Created by Christoph on 4/27/26.
//

import Foundation

/// Parsed exit state with structured data
public enum ParsedExitState: Equatable {
    case start(StartState)
    case processing(ProcessingState)
    case awaitingDelta(AwaitingDeltaState)
    case claimable(ClaimableState)
    case claimInProgress(ClaimInProgressState)
    case claimed(ClaimedState)
    case vtxoAlreadySpent(VtxoAlreadySpentState)
    case unparsed(String) // Fallback for unknown states
    
    public struct StartState: Equatable {
        public let tipHeight: UInt32
        
        public init(tipHeight: UInt32) {
            self.tipHeight = tipHeight
        }
    }
    
    public struct ProcessingState: Equatable {
        public let tipHeight: UInt32
        public let transactions: [ExitTransaction]
        
        public init(tipHeight: UInt32, transactions: [ExitTransaction]) {
            self.tipHeight = tipHeight
            self.transactions = transactions
        }
    }
    
    public struct AwaitingDeltaState: Equatable {
        public let tipHeight: UInt32
        public let confirmedBlock: ArkeBlockRef
        public let claimableHeight: UInt32
        
        public init(tipHeight: UInt32, confirmedBlock: ArkeBlockRef, claimableHeight: UInt32) {
            self.tipHeight = tipHeight
            self.confirmedBlock = confirmedBlock
            self.claimableHeight = claimableHeight
        }
    }
    
    public struct ClaimableState: Equatable {
        public let tipHeight: UInt32
        public let claimableSince: ArkeBlockRef
        public let lastScannedBlock: ArkeBlockRef?
        
        public init(tipHeight: UInt32, claimableSince: ArkeBlockRef, lastScannedBlock: ArkeBlockRef?) {
            self.tipHeight = tipHeight
            self.claimableSince = claimableSince
            self.lastScannedBlock = lastScannedBlock
        }
    }
    
    public struct ClaimInProgressState: Equatable {
        public let tipHeight: UInt32
        public let claimableSince: ArkeBlockRef
        public let claimTxid: String
        
        public init(tipHeight: UInt32, claimableSince: ArkeBlockRef, claimTxid: String) {
            self.tipHeight = tipHeight
            self.claimableSince = claimableSince
            self.claimTxid = claimTxid
        }
    }
    
    public struct ClaimedState: Equatable {
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
    public struct VtxoAlreadySpentState: Equatable {
        public let tipHeight: UInt32

        public init(tipHeight: UInt32) {
            self.tipHeight = tipHeight
        }
    }
}

/// Individual exit transaction in the chain
public struct ExitTransaction: Equatable {
    public let txid: String
    public let status: ExitTxStatus
    
    public init(txid: String, status: ExitTxStatus) {
        self.txid = txid
        self.status = status
    }
}

/// Status of an exit transaction
public enum ExitTxStatus: Equatable {
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
    
    public struct NeedsBroadcastingData: Equatable {
        public let childTxid: String
        public let origin: TxOrigin
        
        public init(childTxid: String, origin: TxOrigin) {
            self.childTxid = childTxid
            self.origin = origin
        }
    }
    
    public struct BroadcastWithCpfpData: Equatable {
        public let childTxid: String
        public let origin: TxOrigin
        
        public init(childTxid: String, origin: TxOrigin) {
            self.childTxid = childTxid
            self.origin = origin
        }
    }
    
    public struct AwaitingInputData: Equatable {
        public let dependencyTxids: Set<String>
        
        public init(dependencyTxids: Set<String>) {
            self.dependencyTxids = dependencyTxids
        }
    }
    
    public struct ConfirmedData: Equatable {
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
public enum TxOrigin: Equatable {
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

    public struct WalletOrigin: Equatable {
        public let confirmedIn: ArkeBlockRef?

        public init(confirmedIn: ArkeBlockRef?) {
            self.confirmedIn = confirmedIn
        }
    }
}
