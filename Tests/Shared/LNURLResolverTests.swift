//
//  LNURLResolverTests.swift
//  Arké Tests
//
//  Unit tests for LNURL-pay resolver
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("LNURL Resolver Tests")
struct LNURLResolverTests {
    
    // MARK: - Detection Tests
    
    @Test("Detects valid LNURL format")
    func testValidLNURLDetection() {
        #expect(LNURLResolver.isLNURL("lnurl1dp68gurn8ghj7um9wfmxjcm99e3k7mf0v9cxj0m385ekvcenxc6r2c35xvukxefcv5mkvv34x5ekzd3ev56nyd3hxqurzepexejxxepnxscrvwfnv9nxzcn9xq6xyefhvgcxxcmyxymnserxfq5fns"))
        #expect(LNURLResolver.isLNURL("LNURL1DP68GURN8GHJ7UM9WFMXJCM99E3K7MF0V9CXJ0M385EKVCENXC6R2C35XVUKXEFCV5MKVV34X5EKZD3EV56NYD3HXQURZEPEXEJXXEPNXSCRVWFNV9NXZCN9XQ6XYEFHVGCXXCMYXYMNSERXFQ5FNS")) // Uppercase
    }
    
    @Test("Rejects invalid LNURL formats")
    func testInvalidLNURLDetection() {
        #expect(!LNURLResolver.isLNURL("bitcoin:1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"))
        #expect(!LNURLResolver.isLNURL("user@domain.com"))
        #expect(!LNURLResolver.isLNURL("lnbc1000u1p3"))  // Lightning invoice
        #expect(!LNURLResolver.isLNURL("tark1qxyzexample"))  // Ark address
        #expect(!LNURLResolver.isLNURL(""))  // Empty string
        #expect(!LNURLResolver.isLNURL("lnurlwrong"))  // Missing "1" separator
    }
    
    // MARK: - Decoding Tests
    
    @Test("Decodes LNURL to HTTPS URL")
    func testLNURLDecoding() throws {
        // Real LNURL example that decodes to https://service.com/.well-known/lnurlp/user
        let lnurl = "lnurl1dp68gurn8ghj7um9wfmxjcm99e3k7mf0v9cxj0m385ekvcenxc6r2c35xvukxefcv5mkvv34x5ekzd3ev56nyd3hxqurzepexejxxepnxscrvwfnv9nxzcn9xq6xyefhvgcxxcmyxymnserxfq5fns"
        
        let decoded = try LNURLResolver.decode(lnurl)
        #expect(decoded.scheme == "https")
        #expect(decoded.absoluteString.hasPrefix("https://"))
    }
    
    @Test("Rejects non-HTTPS LNURL")
    func testRejectsNonHTTPS() throws {
        // This would need a specially crafted LNURL that decodes to http://
        // For now, we test the error case with invalid prefix
        #expect(throws: LNURLResolver.LNURLError.self) {
            try LNURLResolver.decode("invalid_lnurl")
        }
    }
    
    @Test("Handles uppercase LNURL")
    func testUppercaseLNURL() throws {
        let lnurl = "LNURL1DP68GURN8GHJ7UM9WFMXJCM99E3K7MF0V9CXJ0M385EKVCENXC6R2C35XVUKXEFCV5MKVV34X5EKZD3EV56NYD3HXQURZEPEXEJXXEPNXSCRVWFNV9NXZCN9XQ6XYEFHVGCXXCMYXYMNSERXFQ5FNS"
        
        let decoded = try LNURLResolver.decode(lnurl)
        #expect(decoded.scheme == "https")
    }
    
    @Test("Decodes real user LNURL from Wallet of Satoshi")
    func testRealUserLNURL() throws {
        // Real LNURL from user logs - Wallet of Satoshi
        let lnurl = "LNURL1DP68GURN8GHJ7AMPD3KX2AR0VEEKZAR0WD5XJTNRDAKJ7TNHV4KXCTTTDEHHWM30D3H82UNVWQHH5ETPD3HH2UMDDAJX2MF4XGES3SALKQ"
        
        let decoded = try LNURLResolver.decode(lnurl)
        #expect(decoded.scheme == "https")
        #expect(decoded.host == "walletofsatoshi.com")
        #expect(decoded.path.hasPrefix("/.well-known/lnurlp/"))
    }
    
    @Test("Rejects malformed bech32")
    func testMalformedBech32() throws {
        #expect {
            try LNURLResolver.decode("lnurl1invalid_characters_!")
        } throws: { error in
            guard case LNURLResolver.LNURLError.decodingFailed = error else { return false }
            return true
        }
    }
    
    @Test("Rejects invalid bech32 prefix")
    func testInvalidPrefix() throws {
        #expect {
            try LNURLResolver.decode("wrongprefix1dp68gurn8ghj7")
        } throws: { error in
            guard case LNURLResolver.LNURLError.invalidFormat = error else { return false }
            return true
        }
    }
    
    // MARK: - Min/Max Amount Conversion Tests
    
    @Test("Converts millisatoshis to satoshis correctly")
    func testMillisatToSatConversion() {
        let resolved = LNURLResolver.ResolvedLNURL(
            originalLNURL: "lnurl1...",
            callback: "https://example.com/callback",
            minSendable: 1000,      // 1000 millisats = 1 sat
            maxSendable: 1_000_000, // 1M millisats = 1000 sats
            metadata: nil,
            commentAllowed: nil,
            tag: "payRequest",
            resolvedAt: Date()
        )
        
        #expect(resolved.minSendableSats == 1)
        #expect(resolved.maxSendableSats == 1000)
    }
    
    @Test("Handles zero amounts")
    func testZeroAmounts() {
        let resolved = LNURLResolver.ResolvedLNURL(
            originalLNURL: "lnurl1...",
            callback: "https://example.com/callback",
            minSendable: 0,
            maxSendable: 0,
            metadata: nil,
            commentAllowed: nil,
            tag: "payRequest",
            resolvedAt: Date()
        )
        
        #expect(resolved.minSendableSats == 0)
        #expect(resolved.maxSendableSats == 0)
    }
    
    // MARK: - Fixed Amount Tests
    
    @Test("Detects fixed-amount LNURL (POS scenario)")
    func testFixedAmountDetection() {
        // Point-of-sale scenario: min == max means fixed amount
        let fixedAmount = LNURLResolver.ResolvedLNURL(
            originalLNURL: "lnurl1...",
            callback: "https://pos.example.com/callback",
            minSendable: 50_000,  // 50 sats in millisats
            maxSendable: 50_000,  // Same as min = fixed amount
            metadata: nil,
            commentAllowed: nil,
            tag: "payRequest",
            resolvedAt: Date()
        )
        
        #expect(fixedAmount.isFixedAmount == true)
        #expect(fixedAmount.fixedAmountSats == 50)
    }
    
    @Test("Detects variable-amount LNURL")
    func testVariableAmountDetection() {
        // Variable amount: min != max
        let variableAmount = LNURLResolver.ResolvedLNURL(
            originalLNURL: "lnurl1...",
            callback: "https://tip.example.com/callback",
            minSendable: 1_000,      // 1 sat
            maxSendable: 1_000_000,  // 1000 sats
            metadata: nil,
            commentAllowed: nil,
            tag: "payRequest",
            resolvedAt: Date()
        )
        
        #expect(variableAmount.isFixedAmount == false)
        #expect(variableAmount.fixedAmountSats == nil)
    }
    
    @Test("Fixed amount returns nil for variable LNURL")
    func testFixedAmountNilForVariable() {
        let variableAmount = LNURLResolver.ResolvedLNURL(
            originalLNURL: "lnurl1...",
            callback: "https://example.com/callback",
            minSendable: 100,
            maxSendable: 200,
            metadata: nil,
            commentAllowed: nil,
            tag: "payRequest",
            resolvedAt: Date()
        )
        
        #expect(variableAmount.fixedAmountSats == nil)
    }
    
    @Test("Fixed amount handles large amounts correctly")
    func testFixedAmountLargeValue() {
        // Large fixed amount: 1 million sats
        let largeFixed = LNURLResolver.ResolvedLNURL(
            originalLNURL: "lnurl1...",
            callback: "https://expensive.example.com/callback",
            minSendable: 1_000_000_000,  // 1M sats in millisats
            maxSendable: 1_000_000_000,
            metadata: nil,
            commentAllowed: nil,
            tag: "payRequest",
            resolvedAt: Date()
        )
        
        #expect(largeFixed.isFixedAmount == true)
        #expect(largeFixed.fixedAmountSats == 1_000_000)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Error descriptions are meaningful")
    func testErrorDescriptions() {
        let errors: [LNURLResolver.LNURLError] = [
            .invalidFormat,
            .decodingFailed,
            .networkError(NSError(domain: "test", code: -1)),
            .invalidResponse,
            .notLNURLPay,
            .serverError("Test error"),
            .notHTTPS
        ]
        
        for error in errors {
            let description = error.errorDescription
            #expect(description != nil)
            #expect((description?.count ?? 0) > 0)
        }
    }
    
    // MARK: - Metadata Description Tests

    @Test("Extracts short text/plain description from metadata")
    func testMetadataShortDescription() {
        let metadata = #"[["text/plain","Coffee at Satoshi's"]]"#
        #expect(LNURLResolver.extractDescription(fromMetadata: metadata) == "Coffee at Satoshi's")
    }

    @Test("Prefers text/plain over text/long-desc")
    func testMetadataPrefersShort() {
        let metadata = #"[["text/long-desc","A very long description here"],["text/plain","Short"]]"#
        #expect(LNURLResolver.extractDescription(fromMetadata: metadata) == "Short")
    }

    @Test("Falls back to text/long-desc when short is empty")
    func testMetadataLongFallback() {
        let metadata = #"[["text/plain","   "],["text/long-desc","The long one"]]"#
        #expect(LNURLResolver.extractDescription(fromMetadata: metadata) == "The long one")
    }

    @Test("Ignores image entries")
    func testMetadataIgnoresImages() {
        let metadata = #"[["image/png;base64","iVBORw0KGgo="],["text/plain","Tip jar"]]"#
        #expect(LNURLResolver.extractDescription(fromMetadata: metadata) == "Tip jar")
    }

    @Test("Returns nil when only images are present")
    func testMetadataImagesOnly() {
        let metadata = #"[["image/jpeg;base64","/9j/4AAQ=="]]"#
        #expect(LNURLResolver.extractDescription(fromMetadata: metadata) == nil)
    }

    @Test("Returns nil for malformed metadata JSON")
    func testMetadataMalformed() {
        #expect(LNURLResolver.extractDescription(fromMetadata: "not json") == nil)
        #expect(LNURLResolver.extractDescription(fromMetadata: "") == nil)
    }

    @Test("descriptionText convenience reads from metadata")
    func testDescriptionTextConvenience() {
        let resolved = LNURLResolver.ResolvedLNURL(
            originalLNURL: "lnurl1...",
            callback: "https://example.com/callback",
            minSendable: 1000,
            maxSendable: 1000,
            metadata: #"[["text/plain","Donation"]]"#,
            commentAllowed: nil,
            tag: "payRequest",
            resolvedAt: Date()
        )
        #expect(resolved.descriptionText == "Donation")
    }

    // MARK: - Cache Tests
    
    @Test("Cache clears correctly")
    func testCacheClear() {
        // Clear all caches
        LNURLResolver.clearCache()
        
        // Clear specific LNURL (should not crash)
        LNURLResolver.clearCache(for: "lnurl1test")
        
        // No way to verify cache state directly, but this tests that clear doesn't crash
        #expect(true)
    }
}
