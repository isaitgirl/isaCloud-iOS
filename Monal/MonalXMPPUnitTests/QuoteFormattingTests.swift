//
//  QuoteFormattingTests.swift
//  MonalXMPPUnitTests
//
//  Quotes in messages: how a quote line is written, shortened, recognised, and started from the input bar.
//

import Testing

struct QuoteFormattingTests {

    @Test("a quote line is the author and the text, flattened to one line")
    func quoteLineFlattens() {
        #expect(QuoteFormatting.quoteLine(author: "Lu", text: "primeira linha\n\n  segunda  ") == "> Lu: primeira linha segunda")
    }

    @Test("in a 1:1 chat the quote line has no author, only the text")
    func quoteLineWithoutAuthor() {
        #expect(QuoteFormatting.quoteLine(author: nil, text: "primeira linha\n\n  segunda  ") == "> primeira linha segunda")
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
