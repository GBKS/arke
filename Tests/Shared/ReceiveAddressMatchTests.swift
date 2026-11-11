//
//  ReceiveAddressMatchTests.swift
//  ArkéTests
//
//  The Lightning invoice sheet matches incoming movements against the Ark
//  address it displays. The FFI wraps every address in a JSON payment-method
//  object, so the match has to decode before comparing.
//

#if os(iOS)
import Testing
@testable import ArkeMobile

@Suite("Receive Address Match")
struct ReceiveAddressMatchTests {

    private let ark = "ark1qexampleaddress0000000000000000000000000000000000000000000000"

    @Test("A JSON-wrapped Ark entry matches the displayed address")
    func wrappedArkEntryMatches() {
        let entries = [#"{"type":"ark","value":"\#(ark)"}"#]
        #expect(LightningInvoiceSheet_iOS.receivedOnArkAddress(entries, ark))
    }

    @Test("Bare strings, other addresses and other types do not match")
    func nonMatches() {
        #expect(!LightningInvoiceSheet_iOS.receivedOnArkAddress([ark], ark))
        #expect(!LightningInvoiceSheet_iOS.receivedOnArkAddress([#"{"type":"ark","value":"ark1qother"}"#], ark))
        #expect(!LightningInvoiceSheet_iOS.receivedOnArkAddress([#"{"type":"bitcoin","value":"\#(ark)"}"#], ark))
        #expect(!LightningInvoiceSheet_iOS.receivedOnArkAddress([], ark))
        #expect(!LightningInvoiceSheet_iOS.receivedOnArkAddress([#"{"type":"ark","value":""}"#], ""))
    }
}
#endif
