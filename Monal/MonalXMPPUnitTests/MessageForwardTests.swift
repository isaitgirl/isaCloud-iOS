//
//  MessageForwardTests.swift
//  MonalXMPPUnitTests
//
//  isaCloud: forwarding a message: the label line, who can receive it and the limit of destinations.
//

import Foundation
import Testing

struct MessageForwardTests {

    @Test("the forwarded text starts with the label line")
    func bodyHasLabel() {
        #expect(MessageForward.body(forwarding: "oi, tudo bem?", word: "Encaminhado") == "➦ Encaminhado\noi, tudo bem?")
    }

    @Test("a text with line breaks and quotes is kept as it is after the label")
    func bodyKeepsText() {
        let text = "> Ana: oi\nsim\n\nvamos"
        #expect(MessageForward.body(forwarding: text, word: "Forwarded") == "➦ Forwarded\n\(text)")
    }

    @Test("forwarding a forwarded text does not stack labels")
    func noDoubleLabel() {
        let once = MessageForward.body(forwarding: "oi", word: "Encaminhado")
        #expect(MessageForward.body(forwarding: once, word: "Encaminhado") == once)
    }

    @Test("the label line is told from the text, with any of the symbols and in any language")
    func splitsTheLabel() {
        #expect(MessageForward.split("↪ Encaminhado\noi")?.rest == "oi")
        #expect(MessageForward.split("↪\u{FE0E} Encaminhado\noi")?.label == "➦ Encaminhado")
        #expect(MessageForward.split("↪ Encaminhado\noi")?.rest == "oi")
        #expect(MessageForward.split("↪️ Weitergeleitet\nHallo")?.rest == "Hallo")
        #expect(MessageForward.split("➦ Transféré\nsalut")?.rest == "salut")
        #expect(MessageForward.split("↷ Forwarded message\nhi\nthere")?.rest == "hi\nthere")
    }

    @Test("a text that only looks like a label is not one")
    func notALabel() {
        #expect(MessageForward.split("oi\nsegunda linha") == nil)
        #expect(MessageForward.split("↪ Encaminhado") == nil)                                    // nothing after the label
        #expect(MessageForward.split("↪ Isso é uma frase inteira, não um rótulo.\ntexto") == nil)  // a sentence
        #expect(MessageForward.split("↪Encaminhado\ntexto") == nil)                               // no space
        #expect(MessageForward.split("") == nil)
    }

    @Test("only texts that went out and were not retracted can be forwarded")
    func whatCanBeForwarded() {
        #expect(MessageForward.canForward(text: "oi", isRetracted: false, hasSendError: false))
        #expect(!MessageForward.canForward(text: "", isRetracted: false, hasSendError: false))
        #expect(!MessageForward.canForward(text: "oi", isRetracted: true, hasSendError: false))
        #expect(!MessageForward.canForward(text: "oi", isRetracted: false, hasSendError: true))
    }

    @Test("a group or channel needs a role with a voice")
    func whoCanWrite() {
        #expect(MessageForward.canWrite(isMuc: false, role: nil))
        #expect(MessageForward.canWrite(isMuc: true, role: "participant"))
        #expect(MessageForward.canWrite(isMuc: true, role: "moderator"))
        #expect(!MessageForward.canWrite(isMuc: true, role: "visitor"))
        #expect(!MessageForward.canWrite(isMuc: true, role: "none"))
        #expect(!MessageForward.canWrite(isMuc: true, role: nil))
    }

    @Test("up to five destinations can be chosen, and a tap on a chosen one takes it out")
    func limit() {
        var chosen: [String] = []
        for name in ["a", "b", "c", "d", "e", "f"] {
            chosen = MessageForward.toggled(chosen, name)
        }
        #expect(chosen == ["a", "b", "c", "d", "e"])
        chosen = MessageForward.toggled(chosen, "c")
        #expect(chosen == ["a", "b", "d", "e"])
        chosen = MessageForward.toggled(chosen, "f")
        #expect(chosen == ["a", "b", "d", "e", "f"])
    }
}
