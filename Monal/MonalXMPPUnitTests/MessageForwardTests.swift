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

    @Test("only files that went out and were not retracted can be forwarded")
    func whatFilesCanBeForwarded() {
        #expect(MessageForward.canForwardFile(isRetracted: false, hasSendError: false))
        #expect(!MessageForward.canForwardFile(isRetracted: true, hasSendError: false))
        #expect(!MessageForward.canForwardFile(isRetracted: false, hasSendError: true))
    }

    @Test("the label sent alone before a file is the symbol and the word, on one line")
    func labelAlone() {
        #expect(MessageForward.labelOnly(word: "Encaminhado") == "➦ Encaminhado")
        #expect(!MessageForward.labelOnly(word: "Encaminhado").contains("\n"))
    }

    @Test("the label sent before a file has the emoji of the kind of file after the symbol, and the symbol stays first")
    func labelOnlyWithEmoji() {
        #expect(MessageForward.labelOnly(word: "Encaminhado", emoji: "📷") == "➦ 📷 Encaminhado")
        #expect(MessageForward.labelOnly(word: "Encaminhado", emoji: "🎞️") == "➦ 🎞️ Encaminhado")
        #expect(MessageForward.labelOnly(word: "Encaminhado", emoji: "🎥") == "➦ 🎥 Encaminhado")
        #expect(MessageForward.labelOnly(word: "Encaminhado", emoji: "🎤") == "➦ 🎤 Encaminhado")
        #expect(MessageForward.labelOnly(word: "Encaminhado", emoji: "📎") == "➦ 📎 Encaminhado")
        #expect(MessageForward.labelOnly(word: "Encaminhado", emoji: nil) == "➦ Encaminhado")
        #expect(MessageForward.labelOnly(word: "Encaminhado", emoji: "") == "➦ Encaminhado")
        #expect(MessageForward.labelOnly(word: "Encaminhado", emoji: "📷").hasPrefix("➦ "))
    }

    @Test("the emoji of a forwarded file is told by its kind: a GIF is not a photo, and a file is the last choice")
    func mediaEmojiByKind() {
        #expect(MessageForward.mediaEmoji(isGif: true, isImage: false, isVideo: false, isAudio: false) == "🎞️")
        //a GIF is an image too: it is told apart first
        #expect(MessageForward.mediaEmoji(isGif: true, isImage: true, isVideo: false, isAudio: false) == "🎞️")
        #expect(MessageForward.mediaEmoji(isGif: false, isImage: true, isVideo: false, isAudio: false) == "📷")
        #expect(MessageForward.mediaEmoji(isGif: false, isImage: false, isVideo: true, isAudio: false) == "🎥")
        #expect(MessageForward.mediaEmoji(isGif: false, isImage: false, isVideo: false, isAudio: true) == "🎤")
        #expect(MessageForward.mediaEmoji(isGif: false, isImage: false, isVideo: false, isAudio: false) == "📎")
    }

    @Test("a label with an emoji in front of the word is told from the text, the emoji included")
    func splitsLabelWithEmoji() {
        #expect(MessageForward.split("➦ 📷 Encaminhado\ncorpo")?.label == "➦ 📷 Encaminhado")
        #expect(MessageForward.split("➦ 📷 Encaminhado\ncorpo")?.rest == "corpo")
        #expect(MessageForward.split("➦ 🎞️ Encaminhado\ncorpo")?.label == "➦ 🎞️ Encaminhado")
        #expect(MessageForward.split("➦ 🎥 Encaminhado\ncorpo")?.rest == "corpo")
        #expect(MessageForward.split("➦ 📎 Encaminhado\ncorpo")?.label == "➦ 📎 Encaminhado")
        //the emoji does not make a sentence of it
        #expect(MessageForward.split("➦ 📷 uma frase longa demais aqui\ncorpo") == nil)
    }

    @Test("a label alone is told from any other text: with or without an emoji, and only when it is the whole text")
    func labelAloneIsRecognised() {
        #expect(MessageForward.labelAlone("➦ 📷 Encaminhado") == "➦ 📷 Encaminhado")
        #expect(MessageForward.labelAlone("➦ Encaminhado") == "➦ Encaminhado")
        //the other symbols are normalised to the one in use, as split does
        #expect(MessageForward.labelAlone("↪ Forwarded") == "➦ Forwarded")
        //a label with text under it is a forwarded text, not a label alone
        #expect(MessageForward.labelAlone("➦ Encaminhado\ncorpo") == nil)
        #expect(MessageForward.labelAlone("oi, tudo bem?") == nil)
        #expect(MessageForward.labelAlone("➦ Isso é uma frase, com vírgula") == nil)
        #expect(MessageForward.labelAlone("") == nil)
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
