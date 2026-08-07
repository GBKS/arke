//
//  BlockRef.swift
//  Arké
//
//  Block reference for Bitcoin blockchain
//  Created by Christoph on 4/27/26.
//

import Foundation

/// Reference to a block in the Bitcoin blockchain
nonisolated public struct ArkeBlockRef: Equatable, Hashable, Codable {
    public let height: UInt32
    public let hash: String
    
    public init(height: UInt32, hash: String) {
        self.height = height
        self.hash = hash
    }
    
    /// Parse from "height:hash" format
    /// Example: "301628:000000015d9ea966e622a009bfcd733e74b1a9b8252f7e788e7c66164b42cf22"
    public init?(from string: String) {
        let parts = string.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let height = UInt32(parts[0]) else {
            return nil
        }
        self.height = height
        self.hash = String(parts[1])
    }
    
    public var description: String {
        "\(height):\(hash)"
    }
    
    /// Short hash for display (first 8 + last 8 characters)
    public var shortHash: String {
        if hash.count > 16 {
            return String(hash.prefix(8)) + "..." + String(hash.suffix(8))
        }
        return hash
    }
}
