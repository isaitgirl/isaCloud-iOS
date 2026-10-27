//
//  QuoteFormattingTests.swift
//  MonalXMPPUnitTests
//
//  Quotes in messages: how a quote line is written, shortened, recognised, and started from the input bar.
//

import Foundation
import Testing

struct QuoteFormattingTests {

    @Test("every line of the original message is a quote line, the author comes first")
    func quoteLineKeepsLines() {
        #expect(QuoteFormatting.quoteLine(author: "Lu", text: "primeira linha\n\n  segunda  ") == "> Lu: primeira linha\n> segunda")
    }

    @Test("in a 1:1 chat the quote line has no author, only the text")
    func quoteLineWithoutAuthor() {
        #expect(QuoteFormatting.quoteLine(author: nil, text: "primeira linha\n\n  segunda  ") == "> primeira linha\n> segunda")
        #expect(QuoteFormatting.quoteLine(author: "", text: "oi") == "> oi")
    }

    @Test("a long quote is cut with an ellipsis")
    func quoteLineShortens() {
        let long = String(repeating: "a", count: QuoteFormatting.maxQuoteLength + 20)
        let line = QuoteFormatting.quoteLine(author: "Lu", text: long)
        #expect(line == "> Lu: " + String(repeating: "a", count: QuoteFormatting.maxQuoteLength) + "…")
    }

    @Test("only lines starting with a quote marker and a space are quotes")
    func recognisesQuotes() {
        #expect(QuoteFormatting.containsQuote("> Lu: oi\nresposta"))
        #expect(QuoteFormatting.containsQuote("resposta\n> Lu: oi"))
        #expect(QuoteFormatting.containsQuote(">sem espaço") == false)
        #expect(QuoteFormatting.containsQuote("texto comum") == false)
    }

    @Test("the lines of a body keep the quoted ones apart, without their marker")
    func splitsLines() {
        let lines = QuoteFormatting.lines(of: "> Lu: oi\nresposta\n> outra")
        #expect(lines.map { $0.depth } == [1, 0, 1])
        #expect(lines.map { $0.text } == ["Lu: oi", "resposta", "outra"])
    }

    @Test("every marker followed by a space or another marker is one level of quote")
    func nestedDepth() {
        #expect(QuoteFormatting.parse("> a") == (1, "a"))
        #expect(QuoteFormatting.parse(">> a") == (2, "a"))
        #expect(QuoteFormatting.parse("> > a") == (2, "a"))
        #expect(QuoteFormatting.parse(">>> a") == (3, "a"))
        #expect(QuoteFormatting.parse(">   > a") == (2, "a"))
        #expect(QuoteFormatting.parse("a > b") == (0, "a > b"))
    }

    @Test("a marker followed by something else is just text")
    func notQuotes() {
        #expect(QuoteFormatting.parse(">a") == (0, ">a"))
        #expect(QuoteFormatting.parse(">:)") == (0, ">:)"))
        #expect(QuoteFormatting.parse("> >a") == (1, ">a"))
        #expect(QuoteFormatting.parse("") == (0, ""))
    }

    @Test("the depth stops at the maximum")
    func depthIsLimited() {
        let line = String(repeating: ">", count: QuoteFormatting.maxDepth + 3) + " a"
        #expect(QuoteFormatting.parse(line).depth == QuoteFormatting.maxDepth)
    }

    @Test("quoting a reply nests what it quoted one level deeper and keeps the reply as the first level")
    func quotingAReply() {
        let reply = "> Ana: oi tudo bem\nsim, e você?"
        #expect(QuoteFormatting.quoteLine(author: "Lu", text: reply) == ">> Ana: oi tudo bem\n> Lu: sim, e você?")
        #expect(QuoteFormatting.quoteLine(author: nil, text: reply) == ">> Ana: oi tudo bem\n> sim, e você?")
    }

    @Test("lines that are already nested too deep are left out when quoting")
    func quotingLeavesOutDeepLines() {
        let reply = ">> Ana: oi\n> Lu: tudo bem?\nsim"
        #expect(QuoteFormatting.quoteLine(author: "Bia", text: reply) == ">> Lu: tudo bem?\n> Bia: sim")
    }

    @Test("a quote made only of too deep lines is an empty quote")
    func quotingOnlyDeepLines() {
        #expect(QuoteFormatting.quoteLine(author: "Bia", text: ">> a\n>> b") == "> ")
    }

    @Test("starting a reply puts the quote in front of the text and keeps what was typed")
    func startsReplyInInput() {
        let model = ChatInputModel()
        model.quote(author: "Lu", text: "oi tudo bem")
        #expect(model.text == "> Lu: oi tudo bem\n")
        model.setText(model.text + "sim")
        #expect(model.text == "> Lu: oi tudo bem\nsim")
    }

    @Test("a reply cannot start while editing a message")
    func noReplyWhileEditing() {
        let model = ChatInputModel()
        model.startEdit(of: "m1", text: "texto original")
        model.quote(author: "Lu", text: "oi")
        #expect(model.text == "texto original")
    }

    // TEMPORARY labels for replying to a message without text, until Monal implements XEP-0461 and XEP-0428

    @Test("a message without text is quoted by a label with an emoji in front of the word")
    func attachmentLabels() {
        let same: (String) -> String = { $0 }
        #expect(QuoteFormatting.attachmentLabel(.photo, localize: same) == "📷 Photo")
        #expect(QuoteFormatting.attachmentLabel(.gif, localize: same) == "🎞️ GIF")
        #expect(QuoteFormatting.attachmentLabel(.video, localize: same) == "🎥 Video")
        #expect(QuoteFormatting.attachmentLabel(.audio, localize: same) == "🎤 Audio message")
        #expect(QuoteFormatting.attachmentLabel(.location, localize: same) == "📍 Location")
        #expect(QuoteFormatting.attachmentLabel(.file(name: "contrato.pdf"), localize: same) == "📎 File: contrato.pdf")
    }

    @Test("the word is translated, the emoji and the file name are not")
    func attachmentLabelsAreTranslated() {
        let pt: (String) -> String = { ["Photo": "Foto", "File: %@": "Arquivo: %@"][$0] ?? $0 }
        #expect(QuoteFormatting.attachmentLabel(.photo, localize: pt) == "📷 Foto")
        #expect(QuoteFormatting.attachmentLabel(.file(name: "a.pdf"), localize: pt) == "📎 Arquivo: a.pdf")
    }

    @Test("a file name with line breaks stays on one line, and one without name falls back to the word")
    func attachmentLabelFileNames() {
        let same: (String) -> String = { $0 }
        #expect(QuoteFormatting.attachmentLabel(.file(name: "a\nb.pdf"), localize: same) == "📎 File: a b.pdf")
        #expect(QuoteFormatting.attachmentLabel(.file(name: "  "), localize: same) == "📎 File")
    }

    @Test("the label is quoted like any text: with the author in groups and channels, and it nests like a reply")
    func attachmentLabelIsQuoted() {
        let label = QuoteFormatting.attachmentLabel(.photo, localize: { $0 })
        #expect(QuoteFormatting.quoteLine(author: nil, text: label) == "> 📷 Photo")
        #expect(QuoteFormatting.quoteLine(author: "Ana", text: label) == "> Ana: 📷 Photo")
        #expect(QuoteFormatting.parse("> 📷 Photo") == (1, "📷 Photo"))
        //replying to a reply that quoted a photo: the quote goes one level down, as with any other quote
        #expect(QuoteFormatting.quoteLine(author: "Lu", text: "> 📷 Photo\nque legal") == ">> 📷 Photo\n> Lu: que legal")
    }
}

@Suite("Chat message batching")
struct ChatMessageBatchingTests {
    @Test("messages of shown days and of new days are told apart, keeping their order")
    func splitsByDay() {
        let day1 = Date(timeIntervalSince1970: 86400)
        let day2 = Date(timeIntervalSince1970: 2 * 86400)
        let day3 = Date(timeIntervalSince1970: 3 * 86400)
        let incoming = [(1, day1), (2, day3), (3, day1), (4, day2)]
        let result = ChatMessageBatching.split(incoming, shownDays: [day1, day2]) { $0.1 }
        #expect(result.shownDays.map { $0.0 } == [1, 3, 4])
        #expect(result.newDays.map { $0.0 } == [2])
    }

    @Test("an empty batch gives two empty lists")
    func emptyBatch() {
        let result = ChatMessageBatching.split([Int](), shownDays: []) { _ in Date() }
        #expect(result.shownDays.isEmpty && result.newDays.isEmpty)
    }
}
