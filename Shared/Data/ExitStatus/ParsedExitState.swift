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
    case needsBroadcasting(NeedsBroadcastingData)
    case broadcastWithCpfp(BroadcastWithCpfpData)
    case awaitingInputConfirmation(AwaitingInputData)
    case confirmed(ConfirmedData)
    case unparsed(String)
    
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

/// Origin of a transaction
public enum TxOrigin: Equatable {
    case wallet(WalletOrigin)
    case unparsed(String)
    
    public struct WalletOrigin: Equatable {
        public let confirmedIn: ArkeBlockRef?
        
        public init(confirmedIn: ArkeBlockRef?) {
            self.confirmedIn = confirmedIn
        }
    }
}
