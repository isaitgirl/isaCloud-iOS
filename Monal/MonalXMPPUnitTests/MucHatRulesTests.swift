//
//  MucHatRulesTests.swift
//  MonalXMPPUnitTests
//
//  The hats of the channel participants: colours by title, the verified emoji, and mentions that use only the nick.
//

import Testing

struct MucHatRulesTests {

    @Test("the same hat title always gets the same colour")
    func sameTitleSameColour() {
        #expect(MucHat.paletteIndex(forTitle: "Verificado") == MucHat.paletteIndex(forTitle: "Verificado"))
        #expect(MucHat.paletteIndex(forTitle: "Deusa do Olimpo") == MucHat.paletteIndex(forTitle: "Deusa do Olimpo"))
    }

    @Test("the colour index stays inside the palette")
    func indexInRange() {
        for title in ["Verificado", "Deusa do Olimpo", "Moderador", "x", ""] {
            let index = MucHat.paletteIndex(forTitle: title)
            #expect(index >= 0 && index < MucHat.paletteSize)
        }
    }

    @Test("the known hats of the channels never share a colour")
    func knownHatsDiffer() {
        let verified = MucHat.paletteIndex(forTitle: "Verificado 🛡️")
        let olympus = MucHat.paletteIndex(forTitle: "Deusa do Olimpo")
        let ceo = MucHat.paletteIndex(forTitle: "CEO")
        #expect(verified != olympus)
        #expect(verified != ceo)
        #expect(olympus != ceo)
    }

    @Test("only the hat titled Verificado makes the user verified")
    func verified() {
        let verified = MucHat(uri: "https://example.org/verified", title: "Verificado")
        let other = MucHat(uri: "https://example.org/olympus", title: "Deusa do Olimpo")
        #expect(MucHat.isVerified([other]) == false)
        #expect(MucHat.isVerified([other, verified]))
        #expect(MucHat.isVerified([]) == false)
    }

    @Test("the title the server sends for the verified hat has its emoji, and is still verified")
    func verifiedTitleWithEmoji() {
        let verified = MucHat(uri: "urn:uuid:532032dc", title: "Verificado 🛡️")
        #expect(MucHat.isVerified([verified]))
        #expect(MucHat.isVerified([MucHat(uri: "urn:uuid:103ff5cc", title: "Deusa do Olimpo")]) == false)
    }

    @Test("a verified name shows the emoji after a space, a plain name only the nick")
    func displayName() {
        let verified = MucHat(uri: "https://example.org/verified", title: "Verificado")
        #expect(ChatNameWithHats.displayName(nick: "Isadora", hats: [verified]).hasSuffix(" " + MucHat.verifiedEmoji))
        #expect(ChatNameWithHats.displayName(nick: "Isadora", hats: []) == "Isadora")
    }

    @Test("mentions use only the nick, never the emoji")
    func mentionUsesNickOnly() {
        let verified = MucHat(uri: "https://example.org/verified", title: "Verificado")
        let name = ChatNameWithHats.displayName(nick: "Isa Ribeiro", hats: [verified])
        #expect(ChatNameWithHats.nick(from: name) == "Isa Ribeiro")
        #expect(ChatNameWithHats.nick(from: "Isadora") == "Isadora")
    }
}
