//
//  MessageSearchSnippetTests.swift
//  MonalXMPPUnitTests
//
//  isaCloud: the piece of a message shown in the search results: where it starts, which words are in bold.
//

import Foundation
import Testing

struct MessageSearchSnippetTests {

    /// the text of the parts of the snippet that are in bold
    private func bold(_ snippet: AttributedString) -> [String] {
        snippet.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }.map { String(snippet[$0.range].characters) }
    }

    @Test("the words of the query lose the punctuation around them")
    func words() {
        #expect(MessageSearchSnippet.words(of: "  lula   ganhou! ? \"oi\"") == ["lula", "ganhou", "oi"])
        #expect(MessageSearchSnippet.words(of: "?!").isEmpty)
    }

    @Test("a word is found at the beginning of a word, no matter accents or case")
    func matchesPrefixes() {
        let text = "Ação e coração, AÇÃO!"
        let found = MessageSearchSnippet.matches(of: ["acao"], in: text).map { String(text[$0]) }
        #expect(found == ["Ação", "AÇÃO"])
        //"cao" is in the middle of "coração": not a hit
        #expect(MessageSearchSnippet.matches(of: ["cao"], in: text).isEmpty)
        //a prefix covers the beginning of a longer word
        #expect(MessageSearchSnippet.matches(of: ["cora"], in: text).map { String(text[$0]) } == ["cora"])
    }

    @Test("the words found are in bold")
    func marksTheWords() {
        let snippet = MessageSearchSnippet.make(text: "Reunião amanhã cedo, depois da reunião", query: "reuniao amanha")
        #expect(String(snippet.characters) == "Reunião amanhã cedo, depois da reunião")
        #expect(bold(snippet) == ["Reunião", "amanhã", "reunião"])
    }

    @Test("a long text is cut around the first word, with an ellipsis where it was cut")
    func cutsLongTexts() {
        let text = String(repeating: "palavra ", count: 40) + "alvo no meio " + String(repeating: "depois ", count: 40)
        let snippet = MessageSearchSnippet.make(text: text, query: "alvo")
        let shown = String(snippet.characters)
        #expect(shown.hasPrefix("…"))
        #expect(shown.hasSuffix("…"))
        #expect(shown.count <= MessageSearchSnippet.maxLength + 2)
        #expect(bold(snippet) == ["alvo"])
    }

    @Test("a text that starts with the word is not cut at the beginning")
    func startsWithTheWord() {
        let snippet = MessageSearchSnippet.make(text: "alvo " + String(repeating: "depois ", count: 40), query: "alvo")
        #expect(!String(snippet.characters).hasPrefix("…"))
        #expect(String(snippet.characters).hasSuffix("…"))
    }

    @Test("line breaks become spaces, so a row never grows with the message")
    func oneLine() {
        let snippet = MessageSearchSnippet.make(text: "um\n\n  dois com alvo\n", query: "alvo")
        #expect(String(snippet.characters) == "um dois com alvo")
    }

    @Test("a text without the words shows its beginning, with nothing in bold")
    func withoutMatch() {
        //the index also finds a word inside a link, for example
        let snippet = MessageSearchSnippet.make(text: "https://example.org/pagina", query: "xyz")
        #expect(String(snippet.characters) == "https://example.org/pagina")
        #expect(bold(snippet).isEmpty)
    }
}
