//
//  QuoteFormatting.swift
//  Monal
//
//  isaCloud: quotes as plain text. A line that starts with "> " is a quote and is part of the message body, so it is
//  encrypted like any text and other clients show it as text too. The quote is a copy of the quoted text. A reply to a reply
//  nests: ">> " (or "> > ") is a quote inside a quote, as in Conversations.
//

import Foundation

enum QuoteFormatting {
    /// longest quoted text; the rest is cut with an ellipsis
    static let maxQuoteLength = 160
    /// how many quotes nested in each other are told apart (as in Conversations); a deeper line is shown at this depth
    static let maxDepth = 7
    /// quoting a message leaves out its lines that are already nested this deep, so a long chain of replies does not
    /// grow forever (as in Conversations): the quote of a reply shows the reply and what it quoted, no more
    static let maxQuotedDepth = 2

    // TEMPORARY: the reply to something that is not text. The quote is only text in the body, so a photo, a video, an
    // audio message, a file or a location is quoted by a short label (a "> 📷 Photo" line), which says what kind of thing
    // it was but not which one. This is to be replaced when Monal implements the XEPs that do it properly: XEP-0461
    // (Message Replies: a reference to the original message, from which the thumbnail and the jump to it come) and XEP-0428
    // (Fallback Indication: this label becomes the fallback text of the reply). Until then it is what a reply to a
    // message without text can be.
    enum AttachmentKind: Equatable {
        case photo, gif, video, audio, location
        case file(name: String)
    }

    /// isaCloud: the emoji of each kind, alone: the label of a quote and the label of a forwarded file both use it
    static func emoji(for kind: AttachmentKind) -> String {
        switch kind {
            case .photo:
                return "📷"
            case .gif:
                return "🎞️"
            case .video:
                return "🎥"
            case .audio:
                return "🎤"
            case .location:
                return "📍"
            case .file:
                return "📎"
        }
    }

    /// the text that stands for a message without text when it is quoted, with an emoji in front of the word; `localize`
    /// translates the word (the emojis and a file name are not translated)
    static func attachmentLabel(_ kind: AttachmentKind, localize: (String) -> String = { NSLocalizedString($0, comment: "label of the quote when replying to a message without text, the emoji in front is not translated") }) -> String {
        let emoji = emoji(for: kind) + " "
        switch kind {
            case .photo:
                return emoji + localize("Photo")
            case .gif:
                return emoji + "GIF"
            case .video:
                return emoji + localize("Video")
            case .audio:
                return emoji + localize("Audio message")
            case .location:
                return emoji + localize("Location")
            case .file(let name):
                //a file name is one line: a line break in it would end the quote
                let oneLine = name.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
                return emoji + (oneLine.isEmpty ? localize("File") : String(format: localize("File: %@"), oneLine))
        }
    }

    /// How deep a line is quoted and what is left of it without the markers. Every ">" that is followed by a space or by another
    /// ">" is one level, so "> a", ">> a" and "> > a" are quotes of depth 1, 2 and 2; ">a" and ">:)" are not quotes.
    static func parse(_ line: String) -> (depth: Int, text: String) {
        var rest = Substring(line)
        var depth = 0
        while depth < maxDepth, rest.first == ">", let next = rest.dropFirst().first, next == " " || next == ">" {
            rest = rest.dropFirst()
            while rest.first == " " {
                rest = rest.dropFirst()
            }
            depth += 1
        }
        return (depth, String(rest))
    }

    /// the quote that starts a reply: every line of the original message is a quote line ("> text"), so the quote bar
    /// shows on each of them; a line that already quotes something is nested one level deeper (">> text"), and lines that are
    /// nested too deep are left out. In groups and channels the author comes first on the first line of the message's own
    /// text ("> author: text"), not on a line it quoted.
    static func quoteLine(author: String?, text: String) -> String {
        var lines: [(depth: Int, text: String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                continue
            }
            let parsed = parse(line)
            if parsed.depth >= maxQuotedDepth {
                continue
            }
            lines.append(parsed)
        }
        //only the text is limited, the author is not counted
        let authorPrefix = (author?.isEmpty == false) ? "\(author!): " : ""
        let authorLine = authorPrefix.isEmpty ? nil : lines.firstIndex(where: { $0.depth == 0 })
        var budget = maxQuoteLength
        var quoted: [String] = []
        for (index, line) in lines.enumerated() {
            if budget <= 0 {
                quoted[quoted.count - 1] += "…"
                break
            }
            let marker = String(repeating: ">", count: line.depth + 1) + " "
            let prefix = index == authorLine ? authorPrefix : ""
            if line.text.count > budget {
                quoted.append(marker + prefix + String(line.text.prefix(budget)) + "…")
                break
            }
            quoted.append(marker + prefix + line.text)
            budget -= line.text.count
        }
        return quoted.isEmpty ? "> " : quoted.joined(separator: "\n")
    }

    static func isQuoteLine(_ line: String) -> Bool {
        return parse(line).depth > 0
    }

    /// whether a message body has any quoted line
    static func containsQuote(_ body: String) -> Bool {
        return body.components(separatedBy: "\n").contains(where: isQuoteLine)
    }

    /// the lines of a body as (depth, text): depth 0 is a normal line, 1 or more a quoted line, which loses its markers
    static func lines(of body: String) -> [(depth: Int, text: String)] {
        return body.components(separatedBy: "\n").map { parse($0) }
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
