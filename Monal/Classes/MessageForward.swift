//
//  MessageForward.swift
//  Monal
//
//  isaCloud: forwarding a message to other chats ("Forward…" in the message menu). The forwarded text is sent as a normal message of the person
//  forwarding it, having a first line that says it was forwarded (a symbol and one word). Every other client shows that line as plain text; the
//  isaCloud draws it in italics and gray. No UI here, so it can be tested.
//

import Foundation

enum MessageForward {
    /// how many chats a message can be forwarded to at once
    static let maxDestinations = 5
    /// the symbol in front of the word; a text symbol, not an emoji, so it takes the gray and the italics of the line
    //(U+27A6 has no emoji form, so it takes the gray and the italics; the arrow U+21AA used before was drawn by iOS as a colored emoji unless U+FE0E
    //followed it: a message sent that way is still recognised below)
    static let symbol = "➦"
    /// every symbol that makes a first line a "forwarded" line (the one in use and the ones that were or may be used)
    private static let knownSymbols = ["➦", "↪\u{FE0E}", "↪\u{FE0F}", "↪", "↷"]
    /// the label line is short: a symbol, a space and one or two words
    private static let maxLabelLength = 30

    /// the text to send: the label line (the symbol and `word`, "Forwarded" in the language of the person forwarding) and then the text.
    /// A text that was forwarded before does not get a second label.
    static func body(forwarding text: String, word: String) -> String {
        let original = split(text)?.rest ?? text
        return "\(symbol) \(word)\n\(original)"
    }

    /// the label line and the rest of the text of a forwarded message; nil if it is not one
    static func split(_ text: String) -> (label: String, rest: String)? {
        guard let lineEnd = text.firstIndex(of: "\n") else {
            return nil
        }
        let firstLine = String(text[text.startIndex..<lineEnd])
        let rest = String(text[text.index(after: lineEnd)...])
        guard !rest.isEmpty, let label = normalizedLabel(firstLine) else {
            return nil
        }
        return (label, rest)
    }

    /// isaCloud: the label line alone, when the whole text is one (a file sent with the label in front of it, or a label with no text under it).
    /// Nil if the text is anything else; the label is returned as `split` returns it.
    static func labelAlone(_ text: String) -> String? {
        guard !text.contains("\n") else {
            return nil
        }
        return normalizedLabel(text)
    }

    /// isaCloud: the label as it is drawn ("➦ word", the symbol in its text form) if `line` is one: a known symbol, a space, then one or two
    /// words with an optional emoji among them (no other punctuation); nil otherwise
    private static func normalizedLabel(_ line: String) -> String? {
        guard line.count <= maxLabelLength else {
            return nil
        }
        for symbol in knownSymbols where line.hasPrefix(symbol + " ") {
            let word = line.dropFirst(symbol.count + 1).trimmingCharacters(in: .whitespaces)
            //one or two words, nothing else (no sentence that happens to start with an arrow)
            if !word.isEmpty && word.split(separator: " ").count <= 2 && !word.contains(where: { $0.isPunctuation && $0 != "-" }) {
                return "\(MessageForward.symbol) \(word)"
            }
        }
        return nil
    }

    /// can a message be forwarded: a text that was not retracted and did not fail to send
    static func canForward(text: String, isRetracted: Bool, hasSendError: Bool) -> Bool {
        return !text.isEmpty && !isRetracted && !hasSendError
    }

    /// can a file be forwarded: a file that was not retracted and did not fail to send
    static func canForwardFile(isRetracted: Bool, hasSendError: Bool) -> Bool {
        return !isRetracted && !hasSendError
    }

    /// the label alone, sent in front of a forwarded file (a file has no text to put under the label). isaCloud: with the emoji of the
    /// kind of file between the symbol and the word ("➦ 📷 Forwarded"); the symbol stays the first character
    static func labelOnly(word: String, emoji: String? = nil) -> String {
        guard let emoji = emoji, !emoji.isEmpty else {
            return "\(symbol) \(word)"
        }
        return "\(symbol) \(emoji) \(word)"
    }

    /// isaCloud: the emoji of a forwarded file, by its kind in the order the file is told apart (GIF first, as a GIF is an image too)
    static func mediaEmoji(isGif: Bool, isImage: Bool, isVideo: Bool, isAudio: Bool) -> String {
        if isGif {
            return QuoteFormatting.emoji(for: .gif)
        } else if isImage {
            return QuoteFormatting.emoji(for: .photo)
        } else if isVideo {
            return QuoteFormatting.emoji(for: .video)
        } else if isAudio {
            return QuoteFormatting.emoji(for: .audio)
        }
        return QuoteFormatting.emoji(for: .file(name: ""))
    }

    /// can the person write in this chat: always in a conversation with a contact; in a group or channel only with a role that has a voice
    static func canWrite(isMuc: Bool, role: String?) -> Bool {
        guard isMuc else {
            return true
        }
        guard let role = role else {
            return false
        }
        return role != "none" && role != "visitor"
    }

    /// the choices of the picker after the person tapped `tapped`: it is added (up to the limit), or removed if it was chosen
    static func toggled(_ chosen: [String], _ tapped: String) -> [String] {
        if let index = chosen.firstIndex(of: tapped) {
            var result = chosen
            result.remove(at: index)
            return result
        }
        return chosen.count < maxDestinations ? chosen + [tapped] : chosen
    }
}
