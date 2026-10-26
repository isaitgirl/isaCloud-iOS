//
//  MucNickTests.swift
//  MonalXMPPUnitTests
//
//  isaCloud: the nickname of the account in one group or channel (MLMucProcessor.validatedNick).
//

import Foundation
import Testing
import monalxmpp

struct MucNickTests {

    @Test("a good nick keeps its text but loses the spaces around it")
    func acceptsAndTrims() {
        #expect(MLMucProcessor.validatedNick("  Isa Ribeiro \n") == "Isa Ribeiro")
        #expect(MLMucProcessor.validatedNick("poli2") == "poli2")
        #expect(MLMucProcessor.validatedNick("Maçã 🍎") == "Maçã 🍎")
    }

    @Test("empty nicks are refused")
    func refusesEmpty() {
        #expect(MLMucProcessor.validatedNick("") == nil)
        #expect(MLMucProcessor.validatedNick("   \n ") == nil)
    }

    @Test("a slash or an at sign would break the address of the occupant")
    func refusesAddressCharacters() {
        #expect(MLMucProcessor.validatedNick("a/b") == nil)
        #expect(MLMucProcessor.validatedNick("isa@casa") == nil)
    }

    @Test("control characters and very long nicks are refused")
    func refusesControlAndLong() {
        #expect(MLMucProcessor.validatedNick("a\u{0007}b") == nil)
        #expect(MLMucProcessor.validatedNick(String(repeating: "a", count: 100)) != nil)
        #expect(MLMucProcessor.validatedNick(String(repeating: "a", count: 101)) == nil)
    }
}
