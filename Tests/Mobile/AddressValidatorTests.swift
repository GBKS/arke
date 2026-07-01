//
//  AddressValidatorTests.swift
//  Arke
//
//  Tests for Address Validator
//

import Testing

#if os(iOS)
@testable import ArkeMobile
#else
@testable import ArkeDesktop
#endif

@Suite("Address Validator Tests")
struct AddressValidatorTests {
    
    @Test("Parse BIP-21 with lowercase parameters")
    func testBIP21WithLowercaseParameters() async throws {
        let bip21 = "bitcoin:BC1QLGRRREGY2ZLTHAL2VGM9WQSUPGZQ54EM3ZTNCT?amount=0.00005000&lightning=lnbc50u1p4zt043pp5zuzgwk3cxt2la8as6am3pvfnkgx68xjlepxh4ucly9vhvr7eeqwssp5fqad2zl3fza6pe7cffjylzpm0cd8r6rly7xqzu8s9vmdwepfa34sdq50f5kuut3ypmkzmrvv46qxqrrsscqzyjnp4qgyw03fg9lnp8k9yee0fvjkvzvsk98h0nktj8yavcxx0jc8crvqp59qy9qsqrzjqvkfcajgu3cma73dctgf8cy9fhgn3un33s9djw75gyfj3veaqu53szeepsqq8tcqqqqqqqqqqqqqqqqqfqsrr5t0s44eu49dw3cue6n8d0pzjql84khg2vrnsl8x2r34w0kqdrd7zc63dcjyw6d83u2mjpdcun9svleayt3tanchxdh0sjhf6dgacq589ce3"
        
        let paymentRequest = AddressValidator.parsePaymentRequest(bip21)
        
        #expect(paymentRequest != nil, "Should parse BIP-21 URI")
        #expect(paymentRequest?.destinations.count == 2, "Should have 2 destinations (onchain + lightning)")
        #expect(paymentRequest?.amount == 5000, "Amount should be 5000 sats (0.00005000 BTC)")
        
        // Check that we have both onchain and lightning destinations
        let hasOnchain = paymentRequest?.destinations.contains { $0.format == .bitcoin } ?? false
        let hasLightning = paymentRequest?.destinations.contains { $0.format == .lightningInvoice } ?? false
        
        #expect(hasOnchain, "Should have onchain destination")
        #expect(hasLightning, "Should have lightning destination")
    }
    
    @Test("Parse BIP-21 with uppercase parameters (QR code scenario)")
    func testBIP21WithUppercaseParameters() async throws {
        let bip21 = "BITCOIN:BC1QLGRRREGY2ZLTHAL2VGM9WQSUPGZQ54EM3ZTNCT?AMOUNT=0.00005000&LIGHTNING=LNBC50U1P4ZT043PP5ZUZGWK3CXT2LA8AS6AM3PVFNKGX68XJLEPXH4UCLY9VHVR7EEQWSSP5FQAD2ZL3FZA6PE7CFFJYLZPM0CD8R6RLY7XQZU8S9VMDWEPFA34SDQ50F5KUUT3YPMKZMRVV46QXQRRSSCQZYJNP4QGYW03FG9LNP8K9YEE0FVJKVZVSK98H0NKTJ8YAVCXX0JC8CRVQP59QY9QSQRZJQVKFCAJGU3CMA73DCTGF8CY9FHGN3UN33S9DJW75GYFJ3VEAQU53SZEEPSQQ8TCQQQQQQQQQQQQQQQQQFQSRR5T0S44EU49DW3CUE6N8D0PZJQL84KHG2VRNSL8X2R34W0KQDRD7ZC63DCJYW6D83U2MJPDCUN9SVLEAYT3TANCHXDH0SJHF6DGACQ589CE3"
        
        let paymentRequest = AddressValidator.parsePaymentRequest(bip21)
        
        #expect(paymentRequest != nil, "Should parse BIP-21 URI with uppercase parameters")
        #expect(paymentRequest?.destinations.count == 2, "Should have 2 destinations (onchain + lightning)")
        #expect(paymentRequest?.amount == 5000, "Amount should be 5000 sats (0.00005000 BTC)")
        
        // Check that we have both onchain and lightning destinations
        let hasOnchain = paymentRequest?.destinations.contains { $0.format == .bitcoin } ?? false
        let hasLightning = paymentRequest?.destinations.contains { $0.format == .lightningInvoice } ?? false
        
        #expect(hasOnchain, "Should have onchain destination")
        #expect(hasLightning, "Should have lightning destination")
    }
    
    @Test("Parse BIP-21 with mixed case parameters")
    func testBIP21WithMixedCaseParameters() async throws {
        let bip21 = "bitcoin:BC1QLGRRREGY2ZLTHAL2VGM9WQSUPGZQ54EM3ZTNCT?Amount=0.00005000&Lightning=lnbc50u1p4zt043pp5zuzgwk3cxt2la8as6am3pvfnkgx68xjlepxh4ucly9vhvr7eeqwssp5fqad2zl3fza6pe7cffjylzpm0cd8r6rly7xqzu8s9vmdwepfa34sdq50f5kuut3ypmkzmrvv46qxqrrsscqzyjnp4qgyw03fg9lnp8k9yee0fvjkvzvsk98h0nktj8yavcxx0jc8crvqp59qy9qsqrzjqvkfcajgu3cma73dctgf8cy9fhgn3un33s9djw75gyfj3veaqu53szeepsqq8tcqqqqqqqqqqqqqqqqqfqsrr5t0s44eu49dw3cue6n8d0pzjql84khg2vrnsl8x2r34w0kqdrd7zc63dcjyw6d83u2mjpdcun9svleayt3tanchxdh0sjhf6dgacq589ce3"
        
        let paymentRequest = AddressValidator.parsePaymentRequest(bip21)
        
        #expect(paymentRequest != nil, "Should parse BIP-21 URI with mixed case parameters")
        #expect(paymentRequest?.destinations.count == 2, "Should have 2 destinations (onchain + lightning)")
        #expect(paymentRequest?.amount == 5000, "Amount should be 5000 sats")
        
        // Check that we have both onchain and lightning destinations
        let hasOnchain = paymentRequest?.destinations.contains { $0.format == .bitcoin } ?? false
        let hasLightning = paymentRequest?.destinations.contains { $0.format == .lightningInvoice } ?? false
        
        #expect(hasOnchain, "Should have onchain destination")
        #expect(hasLightning, "Should have lightning destination")
    }
    
    @Test("Parse lightning: URI with LNURL")
    func testLightningURIWithLNURL() async throws {
        // Real example from user logs - lightning:LNURL1...
        let lightningLNURL = "lightning:LNURL1DP68GURN8GHJ7CTSDYHX7URPVAHJUCM0D5HK7URPVAHJ6UR0WVHKZURF9AMRYTMVDE6HYMP0DU69WNJ48ACR6DT424GXCNMTVUUKKMMNX9GYGUR4094KGUTFWEEYWEF9XFRX5JFNV9ENXD6C2468GE6CVEJ45NN3GD69SK3NX4TRVSTKG9UXKUPJW3K5YMJRW5UXZ5TETPA8X6NTFYJNYSJDF95RSKF5Y5EYV4N4XP2NWSJJXYU563R2Y5EYVFFJGE25Y3ZWXDR4ZUE3WA69JJ62XAE9SSN4V39Y7NZ2VAZRV52YGA45VJ6V8QMK5JMYXPKNQDRWT99NVFFJGGEHGCNJXFUNSD6WV3NXYJTRD9UXVSM2G4CRG5MCVVJNX3QEDD4FX"
        
        let paymentRequest = AddressValidator.parsePaymentRequest(lightningLNURL)
        
        #expect(paymentRequest != nil, "Should parse lightning:LNURL URI")
        #expect(paymentRequest?.destinations.count == 1, "Should have 1 LNURL destination")
        
        // Check that the destination is LNURL, not Lightning invoice
        let destination = paymentRequest?.primaryDestination
        #expect(destination?.format == .lnurl, "Should be LNURL format")
        #expect(destination?.address.hasPrefix("LNURL1") == true, "Address should start with LNURL1")
    }
    
    @Test("Parse lightning: URI with Lightning invoice")
    func testLightningURIWithInvoice() async throws {
        let lightningInvoice = "lightning:lnbc50u1p4zt043pp5zuzgwk3cxt2la8as6am3pvfnkgx68xjlepxh4ucly9vhvr7eeqwssp5fqad2zl3fza6pe7cffjylzpm0cd8r6rly7xqzu8s9vmdwepfa34sdq50f5kuut3ypmkzmrvv46qxqrrsscqzyjnp4qgyw03fg9lnp8k9yee0fvjkvzvsk98h0nktj8yavcxx0jc8crvqp59qy9qsqrzjqvkfcajgu3cma73dctgf8cy9fhgn3un33s9djw75gyfj3veaqu53szeepsqq8tcqqqqqqqqqqqqqqqqqfqsrr5t0s44eu49dw3cue6n8d0pzjql84khg2vrnsl8x2r34w0kqdrd7zc63dcjyw6d83u2mjpdcun9svleayt3tanchxdh0sjhf6dgacq589ce3"
        
        let paymentRequest = AddressValidator.parsePaymentRequest(lightningInvoice)
        
        #expect(paymentRequest != nil, "Should parse lightning:invoice URI")
        #expect(paymentRequest?.destinations.count == 1, "Should have 1 Lightning invoice destination")
        
        // Check that the destination is Lightning invoice, not LNURL
        let destination = paymentRequest?.primaryDestination
        #expect(destination?.format == .lightningInvoice, "Should be Lightning invoice format")
        #expect(destination?.address.hasPrefix("lnbc") == true, "Address should start with lnbc")
    }

    @Test("Parse BIP-21 with uppercase Ark address in ark= parameter")
    func testBIP21WithUppercaseArkParameter() async throws {
        // Real example from user: bech32m Ark address supplied in uppercase.
        // Bech32m is case-insensitive, so the ark= destination must still be detected.
        let bip21 = "bitcoin:bc1p90d2l4dkt805y0z7xnj9063hgr3c20sx5785ndykql37fwv7p28ql4ftum?amount=0.00000500&ark=ARK1PU6H30W3ZQQPZSSLLL7Q3SHC64TYNF0ADPZNG6SURCLED29XCMEM9PGDW79U2LPPZQYPJE9GYVCQX3RRD7XK83ASUHQNK0ZUKSH9J3GV706YJ009MKGGTZ4GNM04Q4&lightning=LNBC5U1P4Z8454SP5JQJAZW30TT9G0MR5ZSMZED824CYDML33GU7C383880YR0SSDFWUSPP5MLU85LKWTLKR8A5YLN6P0275Y76M47HJXM203YNDR6V7VMH99Z6SDQQXQY9GCQCQZXG9QYYSGQ5V8QR8T4F8TXX62668S04FR83P66QZEERRKVJZUD5Z0HAVW9ST88DYR0N2JH0V4GP307H2JNPGZY3ZTMRKKNNDK7X3C8UPQPVUL7UPQQA6Q25R"

        let paymentRequest = AddressValidator.parsePaymentRequest(bip21)

        #expect(paymentRequest != nil, "Should parse BIP-21 URI")
        #expect(paymentRequest?.amount == 500, "Amount should be 500 sats (0.00000500 BTC)")

        // The uppercase ark= parameter must produce an Ark destination.
        let hasArk = paymentRequest?.destinations.contains { $0.format == .ark } ?? false
        #expect(hasArk, "Should detect the uppercase Ark address in the ark= parameter")

        // The onchain and lightning destinations should also be present.
        let hasOnchain = paymentRequest?.destinations.contains { $0.format == .bitcoin } ?? false
        let hasLightning = paymentRequest?.destinations.contains { $0.format == .lightningInvoice } ?? false
        #expect(hasOnchain, "Should have onchain destination")
        #expect(hasLightning, "Should have lightning destination")
    }

    @Test("Detect Ark network is case-insensitive")
    func testDetectArkNetworkCaseInsensitive() async throws {
        let upper = "ARK1PU6H30W3ZQQPZSSLLL7Q3SHC64TYNF0ADPZNG6SURCLED29XCMEM9PGDW79U2LPPZQYPJE9GYVCQX3RRD7XK83ASUHQNK0ZUKSH9J3GV706YJ009MKGGTZ4GNM04Q4"
        let lower = upper.lowercased()

        #expect(AddressValidator.detectArkNetwork(upper) == .mainnet, "Uppercase ark address should be mainnet")
        #expect(AddressValidator.detectArkNetwork(lower) == .mainnet, "Lowercase ark address should be mainnet")
        #expect(AddressValidator.isArkAddress(upper), "Uppercase ark address should be recognized as Ark")
    }

    @Test("Detect Silent Payments network is case-insensitive")
    func testDetectSilentPaymentsCaseInsensitive() async throws {
        // Synthetic vector: the simplified bech32m decoder does not verify the checksum,
        // it only requires the sp1 prefix and a 66-byte payload (33-byte scan + 33-byte
        // spend key). 112 charset characters after "sp1" decode to exactly 66 bytes.
        let lower = "sp1" + String(repeating: "q", count: 112)
        let upper = lower.uppercased()

        #expect(AddressValidator.detectSilentPaymentsNetwork(lower) == .mainnet, "Lowercase sp address should be mainnet")
        #expect(AddressValidator.detectSilentPaymentsNetwork(upper) == .mainnet, "Uppercase sp address should be mainnet")
        #expect(AddressValidator.extractSilentPaymentsKeys(upper) != nil, "Should extract keys from uppercase sp address")
    }
}
