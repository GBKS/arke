//
//  ExitStatusParser.swift
//  Arké
//
//  Parser for Rust Debug format exit status strings
//  Created by Christoph on 4/27/26.
//

import Foundation
import Bark
import os

/// Parser for Bark SDK exit status strings (Rust Debug format)
public struct ExitStatusParser {
    
    private static let enableLogging = false
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.arke", category: "ExitStatusParser")
    
    private static func log(_ level: OSLogType = .debug, _ message: String) {
        guard enableLogging else { return }
        logger.log(level: level, "\(message)")
    }
    
    // MARK: - Main Parsing Methods
    
    /// Parse a state string into structured ParsedExitState
    public static func parseState(_ stateString: String) -> ParsedExitState? {
        // Extract the state type (before opening paren)
        guard let stateType = extractStateType(from: stateString) else {
            return .unparsed(stateString)
        }
        
        switch stateType.lowercased() {
        case "start":
            return parseStart(stateString)
        case "processing":
            return parseProcessing(stateString)
        case "awaitingdelta":
            return parseAwaitingDelta(stateString)
        case "claimable":
            return parseClaimable(stateString)
        case "claiminprogress":
            return parseClaimInProgress(stateString)
        case "claimed":
            return parseClaimed(stateString)
        case "vtxoalreadyspent":
            return parseVtxoAlreadySpent(stateString)
        default:
            return .unparsed(stateString)
        }
    }
    
    /// Parse history array into structured states
    public static func parseHistory(_ history: [String]) -> [ParsedExitState] {
        return history.compactMap { parseState($0) }
    }
    
    /// Extract all transaction IDs from status (state + history)
    public static func extractAllTransactionIds(from status: Bark.ExitTransactionStatus) -> [String] {
        var txids = Set<String>()
        
        // Parse current state
        if let parsed = parseState(status.state) {
            txids.formUnion(extractTxids(from: parsed))
        }
        
        // Parse history
        if let history = status.history {
            for historyItem in history {
                if let parsed = parseState(historyItem) {
                    txids.formUnion(extractTxids(from: parsed))
                }
            }
        }
        
        return Array(txids).sorted()
    }
    
    // MARK: - State Type Parsers
    
    private static func parseStart(_ str: String) -> ParsedExitState? {
        // "Start(ExitStartState { tip_height: 301492 })"
        guard let tipHeight = extractUInt32(from: str, field: "tip_height") else {
            return nil
        }
        return .start(.init(tipHeight: tipHeight))
    }
    
    private static func parseProcessing(_ str: String) -> ParsedExitState? {
        // "Processing(ExitProcessingState { tip_height: 301492, transactions: [...] })"
        guard let tipHeight = extractUInt32(from: str, field: "tip_height") else {
            return nil
        }
        
        let transactions = extractTransactions(from: str)
        return .processing(.init(tipHeight: tipHeight, transactions: transactions))
    }
    
    private static func parseAwaitingDelta(_ str: String) -> ParsedExitState? {
        // "AwaitingDelta(ExitAwaitingDeltaState { tip_height: 301587, confirmed_block: 301543:000000..., claimable_height: 301555 })"
        guard let tipHeight = extractUInt32(from: str, field: "tip_height"),
              let confirmedBlock = extractBlockRef(from: str, field: "confirmed_block"),
              let claimableHeight = extractUInt32(from: str, field: "claimable_height") else {
            return nil
        }
        
        return .awaitingDelta(.init(
            tipHeight: tipHeight,
            confirmedBlock: confirmedBlock,
            claimableHeight: claimableHeight
        ))
    }
    
    private static func parseClaimable(_ str: String) -> ParsedExitState? {
        // "Claimable(ExitClaimableState { tip_height: 301627, claimable_since: 301555:000000..., last_scanned_block: None })"
        guard let tipHeight = extractUInt32(from: str, field: "tip_height"),
              let claimableSince = extractBlockRef(from: str, field: "claimable_since") else {
            return nil
        }
        
        let lastScannedBlock = extractOptionalBlockRef(from: str, field: "last_scanned_block")
        
        return .claimable(.init(
            tipHeight: tipHeight,
            claimableSince: claimableSince,
            lastScannedBlock: lastScannedBlock
        ))
    }
    
    private static func parseClaimInProgress(_ str: String) -> ParsedExitState? {
        // "ClaimInProgress(ExitClaimInProgressState { tip_height: 301627, claimable_since: 301555:..., claim_txid: dc2b6... })"
        guard let tipHeight = extractUInt32(from: str, field: "tip_height"),
              let claimableSince = extractBlockRef(from: str, field: "claimable_since"),
              let claimTxid = extractHexString(from: str, field: "claim_txid") else {
            return nil
        }
        
        return .claimInProgress(.init(
            tipHeight: tipHeight,
            claimableSince: claimableSince,
            claimTxid: claimTxid
        ))
    }
    
    private static func parseClaimed(_ str: String) -> ParsedExitState? {
        // "Claimed(ExitClaimedState { tip_height: 301797, txid: dc2b6..., block: 301628:... })"
        guard let tipHeight = extractUInt32(from: str, field: "tip_height"),
              let txid = extractHexString(from: str, field: "txid"),
              let block = extractBlockRef(from: str, field: "block") else {
            return nil
        }
        
        return .claimed(.init(tipHeight: tipHeight, txid: txid, block: block))
    }

    private static func parseVtxoAlreadySpent(_ str: String) -> ParsedExitState? {
        // "VtxoAlreadySpent(ExitVtxoAlreadySpentState { tip_height: 301492 })"
        guard let tipHeight = extractUInt32(from: str, field: "tip_height") else {
            return nil
        }
        return .vtxoAlreadySpent(.init(tipHeight: tipHeight))
    }

    // MARK: - Transaction Parsing
    
    private static func extractTransactions(from str: String) -> [ExitTransaction] {
        // Extract the transactions array content
        // "transactions: [ExitTx { ... }, ExitTx { ... }]"
        
        guard let transactionsContent = extractArrayContent(from: str, field: "transactions") else {
            return []
        }
        
        // Walk each "ExitTx {" occurrence and capture its content with brace
        // counting — statuses like "AwaitingInputConfirmation { txids: {...} }"
        // nest braces two levels deep, which a regex can't match reliably
        var transactions: [ExitTransaction] = []
        var searchRange = transactionsContent.startIndex..<transactionsContent.endIndex

        while let markerRange = transactionsContent.range(of: "ExitTx\\s*\\{", options: .regularExpression, range: searchRange) {
            let contentStart = markerRange.upperBound
            var braceCount = 1
            var currentIndex = contentStart

            while currentIndex < transactionsContent.endIndex && braceCount > 0 {
                let char = transactionsContent[currentIndex]
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                }
                currentIndex = transactionsContent.index(after: currentIndex)
            }

            guard braceCount == 0 else { break }

            let content = String(transactionsContent[contentStart..<transactionsContent.index(before: currentIndex)])
            if let tx = parseExitTx(content) {
                transactions.append(tx)
            }
            searchRange = currentIndex..<transactionsContent.endIndex
        }

        return transactions
    }
    
    private static func parseExitTx(_ content: String) -> ExitTransaction? {
        // "txid: abc123..., status: VerifyInputs" or "status: Confirmed { ... }"
        guard let txid = extractHexString(from: content, field: "txid") else {
            return nil
        }
        
        let status = parseExitTxStatus(from: content)
        return ExitTransaction(txid: txid, status: status)
    }
    
    private static func parseExitTxStatus(from str: String) -> ExitTxStatus {
        // Extract status field content
        guard let statusContent = extractStatusContent(from: str) else {
            log(.debug, "📋 Failed to extract status content from: \(str.prefix(100))...")
            return .unparsed(str)
        }
        
        log(.debug, "📋 Parsing status content: \(statusContent)")
        
        // Determine status type
        if statusContent.hasPrefix("VerifyInputs") {
            return .verifyInputs
        } else if statusContent.hasPrefix("NeedsSignedPackage") {
            return .needsSignedPackage
        } else if statusContent.hasPrefix("NeedsBroadcasting") {
            let childTxid = extractHexString(from: statusContent, field: "child_txid")
            let origin = parseTxOrigin(from: statusContent)
            log(.debug, "   NeedsBroadcasting: child_txid=\(childTxid?.prefix(16) ?? "nil"), origin=\(String(describing: origin))")
            
            if let childTxid = childTxid, let origin = origin {
                log(.info, "✅ Parsed NeedsBroadcasting with child_txid: \(childTxid.prefix(16))...")
                return .needsBroadcasting(.init(childTxid: childTxid, origin: origin))
            } else {
                log(.default, "⚠️ Failed to parse NeedsBroadcasting - missing child_txid or origin")
            }
        } else if statusContent.hasPrefix("BroadcastWithCpfp") {
            let childTxid = extractHexString(from: statusContent, field: "child_txid")
            let origin = parseTxOrigin(from: statusContent)
            log(.debug, "   BroadcastWithCpfp: child_txid=\(childTxid?.prefix(16) ?? "nil"), origin=\(String(describing: origin))")
            
            if let childTxid = childTxid, let origin = origin {
                log(.info, "✅ Parsed BroadcastWithCpfp with child_txid: \(childTxid.prefix(16))...")
                return .broadcastWithCpfp(.init(childTxid: childTxid, origin: origin))
            } else {
                log(.default, "⚠️ Failed to parse BroadcastWithCpfp - missing child_txid or origin")
            }
        } else if statusContent.hasPrefix("AwaitingInputConfirmation") {
            let txids = extractTxidSet(from: statusContent, field: "txids")
            return .awaitingInputConfirmation(.init(dependencyTxids: txids))
        } else if statusContent.hasPrefix("Confirmed") {
            let childTxid = extractHexString(from: statusContent, field: "child_txid")
            let block = extractBlockRef(from: statusContent, field: "block")
            let origin = parseTxOrigin(from: statusContent)
            log(.debug, "   Confirmed: child_txid=\(childTxid?.prefix(16) ?? "nil"), block=\(String(describing: block)), origin=\(String(describing: origin))")
            
            if let childTxid = childTxid, let block = block, let origin = origin {
                log(.info, "✅ Parsed Confirmed with child_txid: \(childTxid.prefix(16))...")
                return .confirmed(.init(childTxid: childTxid, block: block, origin: origin))
            } else {
                log(.default, "⚠️ Failed to parse Confirmed - missing child_txid, block, or origin")
            }
        }
        
        log(.debug, "⚠️ Unparsed status type: \(statusContent.prefix(50))...")
        return .unparsed(statusContent)
    }
    
    private static func parseTxOrigin(from str: String) -> TxOrigin? {
        // "origin: Wallet { confirmed_in: Some(301493:...) }" or "None"
        guard let originContent = extractOriginContent(from: str) else {
            log(.debug, "   🔍 parseTxOrigin: failed to extract origin content from: \(str.prefix(200))")
            return nil
        }

        log(.debug, "   🔍 parseTxOrigin: extracted origin content: \(originContent)")

        if originContent.hasPrefix("Wallet") {
            let confirmedIn = extractOptionalBlockRef(from: originContent, field: "confirmed_in")
            return .wallet(.init(confirmedIn: confirmedIn))
        }

        return .unparsed(originContent)
    }
    
    // MARK: - Field Extraction Utilities
    
    private static func extractStateType(from str: String) -> String? {
        // Extract "Start" from "Start(ExitStartState { ... })"
        guard let parenIndex = str.firstIndex(of: "(") else {
            return str.trimmingCharacters(in: .whitespaces)
        }
        return String(str[..<parenIndex]).trimmingCharacters(in: .whitespaces)
    }
    
    private static func extractUInt32(from str: String, field: String) -> UInt32? {
        // Extract number from "field: 12345"
        let pattern = "\(field):\\s*(\\d+)"
        return extractWithRegex(from: str, pattern: pattern, transform: { UInt32($0) })
    }
    
    private static func extractHexString(from str: String, field: String) -> String? {
        // Extract hex from "field: abc123def..."
        let pattern = "\(field):\\s*([0-9a-fA-F]+)"
        let result = extractWithRegex(from: str, pattern: pattern, transform: { $0 })
        if result == nil {
            log(.debug, "   🔍 extractHexString failed for field '\(field)' in: \(str.prefix(200))")
        }
        return result
    }
    
    private static func extractBlockRef(from str: String, field: String) -> ArkeBlockRef? {
        // Extract "123456:abc..." from "field: 123456:abc..."
        let pattern = "\(field):\\s*(\\d+:[0-9a-fA-F]+)"
        if let blockStr: String = extractWithRegex(from: str, pattern: pattern, transform: { $0 }) {
            return ArkeBlockRef(from: blockStr)
        }
        return nil
    }
    
    private static func extractOptionalBlockRef(from str: String, field: String) -> ArkeBlockRef? {
        // Handle "field: Some(123456:abc...)" or "field: None"
        let pattern = "\(field):\\s*Some\\((\\d+:[0-9a-fA-F]+)\\)"
        if let blockStr: String = extractWithRegex(from: str, pattern: pattern, transform: { $0 }) {
            return ArkeBlockRef(from: blockStr)
        }
        return nil
    }
    
    private static func extractTxidSet(from str: String, field: String) -> Set<String> {
        // Extract "{abc123, def456}" from "field: {abc123, def456}"
        let pattern = "\(field):\\s*\\{([^}]+)\\}"
        if let content: String = extractWithRegex(from: str, pattern: pattern, transform: { $0 }) {
            return Set(content.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            })
        }
        return []
    }
    
    private static func extractArrayContent(from str: String, field: String) -> String? {
        // Extract array content from "field: [...]"
        // This handles nested brackets
        guard let fieldRange = str.range(of: "\(field):\\s*\\[", options: .regularExpression) else {
            return nil
        }
        
        let startIndex = fieldRange.upperBound
        var bracketCount = 1
        var currentIndex = startIndex
        
        while currentIndex < str.endIndex && bracketCount > 0 {
            let char = str[currentIndex]
            if char == "[" {
                bracketCount += 1
            } else if char == "]" {
                bracketCount -= 1
            }
            currentIndex = str.index(after: currentIndex)
        }
        
        if bracketCount == 0 {
            return String(str[startIndex..<str.index(before: currentIndex)])
        }
        
        return nil
    }
    
    private static func extractStatusContent(from str: String) -> String? {
        // Extract content after "status: "
        // Handles both simple values and nested structures
        guard let statusRange = str.range(of: "status:\\s*", options: .regularExpression) else {
            log(.debug, "   🔍 extractStatusContent: no 'status:' found in: \(str.prefix(100))")
            return nil
        }

        let startIndex = statusRange.upperBound
        var endIndex = startIndex
        var braceCount = 0
        var encounteredBraces = false

        while endIndex < str.endIndex {
            let char = str[endIndex]

            if char == "{" {
                braceCount += 1
                encounteredBraces = true
            } else if char == "}" {
                braceCount -= 1
                if braceCount == 0 && encounteredBraces {
                    endIndex = str.index(after: endIndex)
                    break
                }
            } else if char == "," && braceCount == 0 {
                // Break on comma only if we're not inside braces
                // This handles cases where status is at end: "..., status: VerifyInputs, ..."
                break
            }

            endIndex = str.index(after: endIndex)
        }

        let result = String(str[startIndex..<endIndex]).trimmingCharacters(in: .whitespaces)
        log(.debug, "   🔍 extractStatusContent: extracted '\(result.prefix(100))' from input '\(str.prefix(200))'")
        return result
    }
    
    private static func extractOriginContent(from str: String) -> String? {
        // Extract content after "origin: "
        guard let originRange = str.range(of: "origin:\\s*", options: .regularExpression) else {
            return nil
        }
        
        let startIndex = originRange.upperBound
        var endIndex = startIndex
        var braceCount = 0
        
        while endIndex < str.endIndex {
            let char = str[endIndex]
            
            if char == "{" {
                braceCount += 1
            } else if char == "}" {
                braceCount -= 1
                if braceCount == 0 {
                    endIndex = str.index(after: endIndex)
                    break
                }
            }
            
            endIndex = str.index(after: endIndex)
        }
        
        return String(str[startIndex..<endIndex]).trimmingCharacters(in: .whitespaces)
    }
    
    private static func extractWithRegex<T>(from str: String, pattern: String, transform: (String) -> T?) -> T? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        
        let nsString = str as NSString
        if let match = regex.firstMatch(in: str, range: NSRange(location: 0, length: nsString.length)),
           match.numberOfRanges > 1 {
            let captured = nsString.substring(with: match.range(at: 1))
            return transform(captured)
        }
        
        return nil
    }
    
    // MARK: - Transaction ID Extraction
    
    private static func extractTxids(from state: ParsedExitState) -> Set<String> {
        var txids = Set<String>()
        
        switch state {
        case .start:
            break
        case .processing(let data):
            for tx in data.transactions {
                txids.insert(tx.txid)
                // Also extract child txids from status
                switch tx.status {
                case .needsBroadcasting(let data):
                    txids.insert(data.childTxid)
                case .broadcastWithCpfp(let data):
                    txids.insert(data.childTxid)
                case .awaitingInputConfirmation(let data):
                    txids.formUnion(data.dependencyTxids)
                case .confirmed(let data):
                    txids.insert(data.childTxid)
                default:
                    break
                }
            }
        case .awaitingDelta:
            break
        case .claimable:
            break
        case .claimInProgress(let data):
            txids.insert(data.claimTxid)
        case .claimed(let data):
            txids.insert(data.txid)
        case .vtxoAlreadySpent:
            // Terminal state carries no exit transactions.
            break
        case .unparsed:
            break
        }
        
        return txids
    }
}
