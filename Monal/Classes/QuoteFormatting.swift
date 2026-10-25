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

    /// the quote that starts a reply: every line of the original message is a quote line ("> text"), so the quote bar
    /// shows on each of them; in groups and channels the author comes first on the first line ("> author: text")
    static func quoteLine(author: String?, text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let author, !author.isEmpty {
            lines = ["\(author): " + (lines.first ?? "")] + lines.dropFirst()
        }
        //only the text is limited, the author is not counted
        let prefixLength = (author?.isEmpty == false) ? author!.count + 2 : 0
        var budget = maxQuoteLength + prefixLength
        var quoted: [String] = []
        for line in lines {
            if budget <= 0 {
                quoted[quoted.count - 1] += "…"
                break
            }
            if line.count > budget {
                quoted.append("> " + String(line.prefix(budget)) + "…")
                break
            }
            quoted.append("> " + line)
            budget -= line.count
        }
        return quoted.isEmpty ? "> " : quoted.joined(separator: "\n")
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

//isaCloud: kept in this file because it is one of the few chat helpers that are also compiled into the unit tests
/// isaCloud: ExyteChat applies a new day section and rows added to another day in one table update with wrong section numbers.
/// A batch of new messages is therefore split: the messages of days already shown, and the messages opening days not shown yet.
enum ChatMessageBatching {
    static func split<T>(_ incoming: [T], shownDays: Set<Date>, day: (T) -> Date) -> (shownDays: [T], newDays: [T]) {
        var shown: [T] = []
        var new: [T] = []
        for message in incoming {
            if shownDays.contains(day(message)) {
                shown.append(message)
            } else {
                new.append(message)
            }
        }
        return (shown, new)
    }
}
