//
//  LightningInvoiceParserTests.swift
//  Arke
//
//  Tests for Lightning Invoice Parser
//

import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Lightning Invoice Parser Tests")
struct LightningInvoiceParserTests {
    
    @Test("Extract payment hash from real invoice")
    func testPaymentHashExtraction() async throws {
        let invoice = "lnbc20u1p4pxzcgpp5ugadm6v6t45xka40v72ufn7lmsla5umhv7470tjrhfv2gm880pqqdq5g9kxy7fqd9h8vmmfvdjscqzpgxqyz5vqsp5884qlg03qftasvufef7y6xafcvpaxr9aeyl40kzf92jqffl82u9q9qxpqysgqz0r0ud3ha7vrwmkfwsnrrw5nwjukmcmkpzkn2whahvr3uqeyd443942nyrg8252sh2x4rmdavfvs3mr2mkypyxdyjqjr9md64g2xfkcqkhrz7f"
        let expectedHash = "e23adde99a5d686b76af6795c4cfdfdc3fda737767abe7ae43ba58a46ce77840"
        
        let extractedHash = LightningInvoiceParser.extractPaymentHash(fromInvoice: invoice)
        
        #expect(extractedHash != nil, "Should extract payment hash")
        #expect(extractedHash == expectedHash, "Payment hash should match expected value. Got: \(extractedHash ?? "nil"), Expected: \(expectedHash)")
    }
    
    @Test("Parse full invoice")
    func testFullInvoiceParsing() async throws {
        let invoice = "lnbc20u1p4pxzcgpp5ugadm6v6t45xka40v72ufn7lmsla5umhv7470tjrhfv2gm880pqqdq5g9kxy7fqd9h8vmmfvdjscqzpgxqyz5vqsp5884qlg03qftasvufef7y6xafcvpaxr9aeyl40kzf92jqffl82u9q9qxpqysgqz0r0ud3ha7vrwmkfwsnrrw5nwjukmcmkpzkn2whahvr3uqeyd443942nyrg8252sh2x4rmdavfvs3mr2mkypyxdyjqjr9md64g2xfkcqkhrz7f"
        
        let parsed = try LightningInvoiceParser.parse(invoice)
        
        print("Parsed invoice:")
        print("  Amount: \(parsed.amountSatoshis ?? 0) sats")
        print("  Description: \(parsed.description ?? "none")")
        print("  Payment Hash: \(parsed.paymentHash ?? "none")")
        print("  Network: \(parsed.network.rawValue)")
    }

    // MARK: - Amount

    // Synthetic strings: a prefix plus seven data characters (the 35-bit
    // timestamp). The parser reads the amount before any checksum or signature.

    @Test("Amount multipliers convert to sats", arguments: [
        ("lnbc2500u1qqqqqqq", UInt64(250_000)),
        ("lnbc20m1qqqqqqq", UInt64(2_000_000)),
        ("lnbc10n1qqqqqqq", UInt64(1)),
        ("lnbc21000000" + "1qqqqqqq", UInt64(2_100_000_000_000_000))
    ])
    func testAmountMultipliers(invoice: String, expectedSats: UInt64) async throws {
        #expect(try LightningInvoiceParser.parse(invoice).amountSatoshis == expectedSats)
    }

    @Test("An amount that is not digits, or exceeds 21M BTC, is rejected", arguments: [
        "lnbc99999999999999999999991qqqqqqq",   // used to trap converting to UInt64
        "lnbc1e5001qqqqqqq",                    // exponent form, parsed as infinity
        "lnbc92233720369" + "1qqqqqqq",         // fits UInt64 but not Int
        "lnbc21000001" + "1qqqqqqq"
    ])
    func testImpossibleAmountIsRejected(invoice: String) async throws {
        #expect(throws: LightningInvoiceParseError.self) {
            try LightningInvoiceParser.parse(invoice)
        }
    }
}
