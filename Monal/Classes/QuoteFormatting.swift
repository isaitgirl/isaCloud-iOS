//
//  QuoteFormatting.swift
//  Monal
//
//  isaCloud: quotes as plain text. A line that starts with "> " is a quote and is part of the message body, so it is
//  encrypted like any text and other clients show it as text too. The quote is a copy of the quoted text.
//

import Foundation

enum QuoteFormatting {
    /// longest quoted text; the rest is cut with an ellipsis
    static let maxQuoteLength = 160

    /// the quote line that starts a reply: "> author: text" in groups and channels, "> text" in 1:1 chats (no author),
    /// with the text flattened to one line
    static func quoteLine(author: String?, text: String) -> String {
        let flat = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let shortened = flat.count > maxQuoteLength ? String(flat.prefix(maxQuoteLength)) + "…" : flat
        guard let author, !author.isEmpty else {
            return "> \(shortened)"
        }
        return "> \(author): \(shortened)"
    }

    static func isQuoteLine(_ line: String) -> Bool {
        return line.hasPrefix("> ")
    }

    /// whether a message body has any quoted line
    static func containsQuote(_ body: String) -> Bool {
        return body.components(separatedBy: "\n").contains(where: isQuoteLine)
    }

    /// the lines of a body as (quoted, text); a quoted line loses its "> "
    static func lines(of body: String) -> [(quoted: Bool, text: String)] {
        return body.components(separatedBy: "\n").map { line in
            isQuoteLine(line) ? (quoted: true, text: String(line.dropFirst(2))) : (quoted: false, text: line)
        }
    }
}
