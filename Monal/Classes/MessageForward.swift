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
        guard !rest.isEmpty, firstLine.count <= maxLabelLength else {
            return nil
        }
        for symbol in knownSymbols where firstLine.hasPrefix(symbol + " ") {
            let word = firstLine.dropFirst(symbol.count + 1).trimmingCharacters(in: .whitespaces)
            //one or two words, nothing else (no sentence that happens to start with an arrow)
            if !word.isEmpty && word.split(separator: " ").count <= 2 && !word.contains(where: { $0.isPunctuation && $0 != "-" }) {
                //the label as it is drawn: always with the symbol in its text form, whichever form it was sent in
                return ("\(MessageForward.symbol) \(word)", rest)
            }
        }
        return nil
    }

    /// can a message be forwarded: a text that was not retracted and did not fail to send
    static func canForward(text: String, isRetracted: Bool, hasSendError: Bool) -> Bool {
        return !text.isEmpty && !isRetracted && !hasSendError
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
