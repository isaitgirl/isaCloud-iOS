//
//  MessageSearchSnippet.swift
//  Monal
//
//  isaCloud: the piece of a message shown in the search results: a short stretch of the text around the first word that was
//  searched for, with the words found in bold. No UI here, so it can be tested.
//

import Foundation

enum MessageSearchSnippet {
    /// how many characters of the message the snippet shows, at most
    static let maxLength = 110
    /// how many characters before the first word found are kept, so the person sees what came before it
    static let contextBefore = 28

    /// the words of what was typed (the search treats each one as the beginning of a word)
    static func words(of query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
            .filter { !$0.isEmpty }
    }

    /// the ranges in `text` where one of the words begins a word of the text, no matter accents or case
    static func matches(of words: [String], in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        for word in words {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: word, options: options, range: searchRange) {
                //only the beginning of a word counts (the search is by prefix): a match in the middle of a word is not a hit
                let startsWord = range.lowerBound == text.startIndex || !(text[text.index(before: range.lowerBound)].isLetter || text[text.index(before: range.lowerBound)].isNumber)
                if startsWord {
                    found.append(range)
                }
                searchRange = range.upperBound..<text.endIndex
            }
        }
        //merge what overlaps, in order
        let sorted = found.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// the snippet for `text`, having the words of `query` in bold. A text without any of the words (the index also finds a word
    /// inside a link, for example) shows its beginning.
    static func make(text: String, query: String) -> AttributedString {
        //one line: a line break would make the row of the results as tall as the message
        let oneLine = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        let words = words(of: query)
        let firstMatch = matches(of: words, in: oneLine).first

        var start = oneLine.startIndex
        if let firstMatch = firstMatch {
            start = oneLine.index(firstMatch.lowerBound, offsetBy: -contextBefore, limitedBy: oneLine.startIndex) ?? oneLine.startIndex
            //do not start in the middle of a word
            while start > oneLine.startIndex, start < firstMatch.lowerBound, oneLine[start].isLetter || oneLine[start].isNumber {
                start = oneLine.index(after: start)
            }
        }
        let end = oneLine.index(start, offsetBy: maxLength, limitedBy: oneLine.endIndex) ?? oneLine.endIndex
        let window = String(oneLine[start..<end])

        var snippet = AttributedString((start > oneLine.startIndex ? "…" : "") + window + (end < oneLine.endIndex ? "…" : ""))
        let prefixLength = start > oneLine.startIndex ? 1 : 0
        for range in matches(of: words, in: window) {
            let lower = window.distance(from: window.startIndex, to: range.lowerBound) + prefixLength
            let upper = window.distance(from: window.startIndex, to: range.upperBound) + prefixLength
            let lowerIndex = snippet.characters.index(snippet.startIndex, offsetBy: lower)
            let upperIndex = snippet.characters.index(snippet.startIndex, offsetBy: upper)
            snippet[lowerIndex..<upperIndex].inlinePresentationIntent = .stronglyEmphasized
        }
        return snippet
    }
}
