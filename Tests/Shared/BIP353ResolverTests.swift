//
//  BIP353ResolverTests.swift
//  Arké Tests
//
//  Decisions behind BIP-353 resolution through two validating resolvers
//  (Docs/Features/BIP353_DNSSEC.md). Fixtures are real dns-json bodies
//  captured from Cloudflare and Google on 2026-10-29. No test touches
//  the network.
//

import Testing
import Foundation

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

// MARK: - Fixtures

private enum Fixture {
    /// The two character-strings of matt@mattcorallo.com's record, 492 bytes together.
    static let mattPart1 = "bitcoin:bc1qztwy6xen3zdtt7z0vrgapmjtfz8acjkfp5fp7l?lno=lno1zr5qyugqgskrk70kqmuq7v3dnr2fnmhukps9n8hut48vkqpqnskt2svsqwjakp7k6pyhtkuxw7y2kqmsxlwruhzqv0zsnhh9q3t9xhx39suc6qsr07ekm5esdyum0w66mnx8vdquwvp7dp5jp7j3v5cp6aj0w329fnkqqv60q96sz5nkrc5r95qffx002q53tqdk"
    static let mattPart2 = "8x9m2tmt85jtpmcycvfnrpx3lr45h2g7na3sec7xguctfzzcm8jjqtj5ya27te60j03vpt0vq9tm2n9yxl2hngfnmygesa25s4u4zlxewqpvp94xt7rur4rhxunwkthk9vly3lm5hh0pqv4aymcqejlgssnlpzwlggykkajp7yjs5jvr2agkyypcdlj280cy46jpynsezrcj2kwa2lyr8xvd6lfkph4xrxtk2xc3lpq"
    static let mattURI = mattPart1 + mattPart2
    static let decoy = "as long as it doesn't start with bitcoin:, other records should be ignored"

    /// Cloudflare: quoted, space-separated character-strings, decoy first.
    static let cloudflareMatt = Data("""
    {"Status":0,"TC":false,"RD":true,"RA":true,"AD":true,"CD":false,
     "Question":[{"name":"matt.user._bitcoin-payment.mattcorallo.com","type":16}],
     "Answer":[
      {"name":"matt.user._bitcoin-payment.mattcorallo.com","type":16,"TTL":3600,"data":"\\"\(decoy)\\""},
      {"name":"matt.user._bitcoin-payment.mattcorallo.com","type":16,"TTL":3600,"data":"\\"\(mattPart1)\\" \\"\(mattPart2)\\""}
     ]}
    """.utf8)

    /// Google: unquoted, already concatenated, bitcoin record first.
    static let googleMatt = Data("""
    {"Status":0,"TC":false,"RD":true,"RA":true,"AD":true,"CD":false,
     "Question":[{"name":"matt.user._bitcoin-payment.mattcorallo.com.","type":16}],
     "Answer":[
      {"name":"matt.user._bitcoin-payment.mattcorallo.com.","type":16,"TTL":3600,"data":"\(mattURI)"},
      {"name":"matt.user._bitcoin-payment.mattcorallo.com.","type":16,"TTL":3600,"data":"\(decoy)"}
     ]}
    """.utf8)

    /// A signed denial: NXDOMAIN with AD set and no Answer array.
    static let nxdomainSigned = Data("""
    {"Status":3,"TC":false,"RD":true,"RA":true,"AD":true,"CD":false,
     "Question":[{"name":"nope.user._bitcoin-payment.mattcorallo.com","type":16}],
     "Authority":[{"name":"mattcorallo.com","type":6,"TTL":1800,"data":"ns1.example. hostmaster.example. 1 7200 3600 1209600 1800"}]}
    """.utf8)

    /// An unsigned zone: records present, AD false.
    static let unsignedZone = Data("""
    {"Status":0,"TC":false,"RD":true,"RA":true,"AD":false,"CD":false,
     "Question":[{"name":"google.com","type":16}],
     "Answer":[{"name":"google.com","type":16,"TTL":297,"data":"\\"v=spf1 include:_spf.google.com ~all\\""}]}
    """.utf8)
}

/// A resolver whose answer is scripted; records the name it was asked for.
private final class FakeSource: DNSTXTSource, @unchecked Sendable {
    let name: String
    private let result: Result<DNSTXTAnswer, Swift.Error>
    private(set) var queriedNames: [String] = []
    private let lock = NSLock()

    init(name: String, answer: DNSTXTAnswer) {
        self.name = name
        self.result = .success(answer)
    }

    init(name: String, error: Swift.Error) {
        self.name = name
        self.result = .failure(error)
    }

    func queryTXT(_ dnsName: String) async throws -> DNSTXTAnswer {
        lock.lock()
        queriedNames.append(dnsName)
        lock.unlock()
        return try result.get()
    }
}

private func secure(_ records: [String], ttl: TimeInterval? = 3600) -> DNSTXTAnswer {
    DNSTXTAnswer(rcode: 0, authenticated: true, records: records, minimumTTL: ttl)
}

private struct TransportFailure: Swift.Error {}

// MARK: - TXT presentation parsing

@Suite("BIP-353 TXT record data")
struct TXTRecordDataTests {

    @Test("Cloudflare's quoted strings concatenate without separators and equal Google's form")
    func quotedStringsConcatenate() {
        let cloudflare = "\"\(Fixture.mattPart1)\" \"\(Fixture.mattPart2)\""
        #expect(TXTRecordData.concatenated(cloudflare) == Fixture.mattURI)
        #expect(TXTRecordData.concatenated(Fixture.mattURI) == Fixture.mattURI)
    }

    @Test("RFC 1035 escapes inside quoted strings are decoded, multi-byte UTF-8 included")
    func escapesDecode() {
        #expect(TXTRecordData.concatenated(#""say \"hi\" \\ now""#) == #"say "hi" \ now"#)
        #expect(TXTRecordData.concatenated(#""\065\066""#) == "AB")
        #expect(TXTRecordData.concatenated(#""tab\009end""#) == "tab\tend")
        // Cloudflare writes "é" as two escaped bytes; Google hands back "café".
        #expect(TXTRecordData.concatenated(#""caf\195\169""#) == "café")
        #expect(TXTRecordData.concatenated("\"caf\u{E9}\"") == "café")
    }

    @Test("Malformed presentation never traps: unterminated quote, trailing backslash, out-of-range escape")
    func malformedPresentation() {
        #expect(TXTRecordData.concatenated("\"open") == "open")
        #expect(TXTRecordData.concatenated("\"end\\") == "end")
        #expect(TXTRecordData.concatenated(#""\999x""#) == "999x")
        #expect(TXTRecordData.concatenated("\"\"") == "")
    }

    @Test("Unquoted data passes through, including apostrophes and spaces")
    func unquotedPassesThrough() {
        #expect(TXTRecordData.concatenated(Fixture.decoy) == Fixture.decoy)
        #expect(TXTRecordData.concatenated("") == "")
    }
}

// MARK: - dns-json parsing

@Suite("BIP-353 dns-json parsing")
struct DoHJSONParsingTests {

    @Test("Cloudflare and Google bodies parse to the same authenticated record set")
    func bothProvidersAgree() throws {
        let cloudflare = try DoHJSONSource.parse(Fixture.cloudflareMatt)
        let google = try DoHJSONSource.parse(Fixture.googleMatt)

        #expect(cloudflare.rcode == 0)
        #expect(cloudflare.authenticated)
        #expect(cloudflare.records.sorted() == [Fixture.decoy, Fixture.mattURI].sorted())
        #expect(cloudflare.minimumTTL == 3600)
        #expect(google.records.sorted() == cloudflare.records.sorted())
        #expect(google.authenticated)
    }

    @Test("A signed NXDOMAIN parses as rcode 3, authenticated, no records")
    func signedDenial() throws {
        let answer = try DoHJSONSource.parse(Fixture.nxdomainSigned)
        #expect(answer.rcode == DNSTXTAnswer.nxdomain)
        #expect(answer.authenticated)
        #expect(answer.records.isEmpty)
        #expect(answer.minimumTTL == nil)
    }

    @Test("An unsigned zone parses with AD false")
    func unsignedZone() throws {
        let answer = try DoHJSONSource.parse(Fixture.unsignedZone)
        #expect(!answer.authenticated)
        #expect(answer.records == ["v=spf1 include:_spf.google.com ~all"])
    }

    @Test("Non-TXT answers are dropped")
    func nonTXTDropped() throws {
        let body = Data("""
        {"Status":0,"AD":true,"Answer":[
          {"name":"x","type":5,"TTL":60,"data":"alias.example."},
          {"name":"x","type":16,"TTL":60,"data":"\\"bitcoin:bc1qexample\\""}]}
        """.utf8)
        let answer = try DoHJSONSource.parse(body)
        #expect(answer.records == ["bitcoin:bc1qexample"])
        #expect(answer.minimumTTL == 60)
    }

    @Test("Garbage is a malformed response, not a crash")
    func malformed() {
        #expect(throws: DoHJSONSource.DoHError.malformedResponse) {
            try DoHJSONSource.parse(Data("<html>".utf8))
        }
    }
}

// MARK: - Validation policy

@Suite("BIP-353 validation policy")
struct BIP353ValidationTests {

    @Test("Two authenticated answers with the same bitcoin: records are accepted regardless of order")
    func agreementAccepted() throws {
        let a = secure([Fixture.decoy, Fixture.mattURI])
        let b = secure([Fixture.mattURI, Fixture.decoy])
        #expect(try BIP353Validation.combine([a, b]) == [Fixture.mattURI])
    }

    @Test("Sibling records that differ between providers do not cause a refusal")
    func siblingRecordsMayDiffer() throws {
        let withDecoy = secure([Fixture.decoy, Fixture.mattURI])
        let withoutDecoy = secure([Fixture.mattURI, "v=spf1 -all"])
        #expect(try BIP353Validation.combine([withDecoy, withoutDecoy]) == [Fixture.mattURI])
    }

    @Test("A SERVFAIL from either resolver is a resolver failure, never 'not signed'")
    func serverFailureIsNotUnsigned() {
        let fine = secure([Fixture.mattURI])
        let servfail = DNSTXTAnswer(rcode: DNSTXTAnswer.serverFailure, authenticated: false, records: [], minimumTTL: nil)
        #expect(throws: BIP353Resolver.BIP353Error.resolverFailure) {
            try BIP353Validation.combine([fine, servfail])
        }
    }

    @Test("One resolver finding records and the other denying the name is a disagreement")
    func mixedCodesDisagree() {
        let found = secure([Fixture.mattURI])
        let denied = DNSTXTAnswer(rcode: DNSTXTAnswer.nxdomain, authenticated: true, records: [], minimumTTL: nil)
        #expect(throws: BIP353Resolver.BIP353Error.resolversDisagree) {
            try BIP353Validation.combine([found, denied])
        }
    }

    @Test("One resolver without AD fails validation even if the other has it")
    func unauthenticatedRefused() {
        let signed = secure([Fixture.mattURI])
        let unsigned = DNSTXTAnswer(rcode: 0, authenticated: false, records: [Fixture.mattURI], minimumTTL: 60)
        #expect(throws: BIP353Resolver.BIP353Error.dnssecValidationFailed) {
            try BIP353Validation.combine([signed, unsigned])
        }
    }

    @Test("Differing record sets are refused")
    func disagreementRefused() {
        let a = secure([Fixture.mattURI])
        let b = secure(["bitcoin:bc1qattacker"])
        #expect(throws: BIP353Resolver.BIP353Error.resolversDisagree) {
            try BIP353Validation.combine([a, b])
        }
    }

    @Test("A single answer is never enough")
    func singleAnswerRefused() {
        #expect(throws: BIP353Resolver.BIP353Error.self) {
            try BIP353Validation.combine([secure([Fixture.mattURI])])
        }
    }

    @Test("A signed NXDOMAIN from both is 'no record', an unsigned one is 'not signed'")
    func denials() {
        let signedDenial = DNSTXTAnswer(rcode: 3, authenticated: true, records: [], minimumTTL: nil)
        #expect(throws: BIP353Resolver.BIP353Error.noDNSRecord) {
            try BIP353Validation.combine([signedDenial, signedDenial])
        }
        let unsignedDenial = DNSTXTAnswer(rcode: 3, authenticated: false, records: [], minimumTTL: nil)
        #expect(throws: BIP353Resolver.BIP353Error.dnssecValidationFailed) {
            try BIP353Validation.combine([signedDenial, unsignedDenial])
        }
    }

    @Test("NOERROR with no TXT records is 'no record'")
    func emptyRecordSet() {
        #expect(throws: BIP353Resolver.BIP353Error.noDNSRecord) {
            try BIP353Validation.combine([secure([], ttl: nil), secure([], ttl: nil)])
        }
    }

    @Test("Exactly one bitcoin: record is selected, case-insensitively, ignoring others")
    func selectsSingleBitcoinRecord() throws {
        #expect(try BIP353Validation.selectBitcoinURI(from: [Fixture.decoy, Fixture.mattURI]) == Fixture.mattURI)
        #expect(try BIP353Validation.selectBitcoinURI(from: ["BITCOIN:bc1qupper"]) == "BITCOIN:bc1qupper")
    }

    @Test("No bitcoin: record and more than one are both refused")
    func bitcoinRecordCount() {
        #expect(throws: BIP353Resolver.BIP353Error.noBitcoinRecord) {
            try BIP353Validation.selectBitcoinURI(from: [Fixture.decoy, "v=spf1 -all"])
        }
        #expect(throws: BIP353Resolver.BIP353Error.multipleBitcoinRecords) {
            try BIP353Validation.selectBitcoinURI(from: ["bitcoin:bc1qa", "Bitcoin:bc1qb"])
        }
    }
}

// MARK: - Resolver end to end with scripted sources

@Suite("BIP-353 resolver", .serialized)
@MainActor
struct BIP353ResolverTests {

    init() {
        BIP353Resolver.clearCache()
    }

    @Test("₿matt@mattcorallo.com and matt@mattcorallo.com query the same DNS name and resolve to the URI")
    func resolvesBothForms() async throws {
        for address in ["₿matt@mattcorallo.com", "matt@mattcorallo.com"] {
            BIP353Resolver.clearCache()
            let a = FakeSource(name: "A", answer: secure([Fixture.decoy, Fixture.mattURI]))
            let b = FakeSource(name: "B", answer: secure([Fixture.mattURI, Fixture.decoy]))

            let resolved = try await BIP353Resolver.resolve(address, using: [a, b])

            #expect(resolved.bip21URI == Fixture.mattURI)
            #expect(resolved.originalAddress == address)
            #expect(resolved.resolvedFrom == "matt.user._bitcoin-payment.mattcorallo.com")
            #expect(a.queriedNames == ["matt.user._bitcoin-payment.mattcorallo.com"])
            #expect(b.queriedNames == ["matt.user._bitcoin-payment.mattcorallo.com"])
        }
    }

    @Test("A transport failure at either resolver fails the lookup closed")
    func transportFailureFailsClosed() async {
        let good = FakeSource(name: "A", answer: secure([Fixture.mattURI]))
        let broken = FakeSource(name: "B", error: TransportFailure())

        await #expect(throws: BIP353Resolver.BIP353Error.self) {
            try await BIP353Resolver.resolve("matt@mattcorallo.com", using: [good, broken])
        }
    }

    @Test("Cache lives no longer than the record TTL, capped at ten minutes")
    func cacheHonoursTTL() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let shortLived = FakeSource(name: "A", answer: secure([Fixture.mattURI], ttl: 15))
        let shortLived2 = FakeSource(name: "B", answer: secure([Fixture.mattURI], ttl: 15))

        let resolved = try await BIP353Resolver.resolve("matt@mattcorallo.com", using: [shortLived, shortLived2], now: start)
        #expect(resolved.expiresAt == start.addingTimeInterval(15))

        // Within the TTL the sources are not asked again.
        _ = try await BIP353Resolver.resolve("matt@mattcorallo.com", using: [shortLived, shortLived2], now: start.addingTimeInterval(10))
        #expect(shortLived.queriedNames.count == 1)

        // After the TTL they are.
        _ = try await BIP353Resolver.resolve("matt@mattcorallo.com", using: [shortLived, shortLived2], now: start.addingTimeInterval(16))
        #expect(shortLived.queriedNames.count == 2)

        BIP353Resolver.clearCache()
        let longLived = FakeSource(name: "A", answer: secure([Fixture.mattURI], ttl: 86_400))
        let longLived2 = FakeSource(name: "B", answer: secure([Fixture.mattURI], ttl: 86_400))
        let capped = try await BIP353Resolver.resolve("matt@mattcorallo.com", using: [longLived, longLived2], now: start)
        #expect(capped.expiresAt == start.addingTimeInterval(600))
    }

    @Test("Error descriptions never call the address compromised for a lookup failure")
    func errorTextTone() {
        let lookup = BIP353Resolver.BIP353Error.dnsLookupFailed("offline").errorDescription ?? ""
        #expect(!lookup.lowercased().contains("compromised"))
        #expect(!lookup.isEmpty)
        let unsigned = BIP353Resolver.BIP353Error.dnssecValidationFailed.errorDescription ?? ""
        #expect(unsigned.contains("DNSSEC"))
        let outage = BIP353Resolver.BIP353Error.resolverFailure.errorDescription ?? ""
        #expect(!outage.contains("aren't DNSSEC-signed"))
        #expect(outage.contains("temporary"))
    }
}
