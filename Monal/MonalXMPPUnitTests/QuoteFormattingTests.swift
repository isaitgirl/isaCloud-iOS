//
//  QuoteFormattingTests.swift
//  MonalXMPPUnitTests
//
//  Quotes in messages: how a quote line is written, shortened, recognised, and started from the input bar.
//

import Testing
import UIKit

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

    @Test("a long quoted text is broken into lines that fit the width, without losing words")
    func wrapsToWidth() {
        let text = "Quem puder verificar o estado de funcionalidade do TSE e informações sobre a situação eleitoral"
        let width: CGFloat = 200
        let font = UIFont.preferredFont(forTextStyle: .body)
        let lines = QuoteFormatting.wrapped(text, maxWidth: width, font: font)
        #expect(lines.count > 1)
        #expect(lines.joined(separator: " ") == text)
        for line in lines {
            #expect((line as NSString).size(withAttributes: [.font: font]).width <= width)
        }
    }

    @Test("a short quoted text stays one line, an empty one stays empty")
    func wrapsShortText() {
        #expect(QuoteFormatting.wrapped("oi", maxWidth: 200) == ["oi"])
        #expect(QuoteFormatting.wrapped("", maxWidth: 200) == [""])
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
        #expect(lines.map { $0.quoted } == [true, false, true])
        #expect(lines.map { $0.text } == ["Lu: oi", "resposta", "outra"])
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
