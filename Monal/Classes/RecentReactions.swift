//
//  RecentReactions.swift
//  Monal
//
//  isaCloud: the emojis of the reaction row in the long press menu of a message. The row keeps the last six emojis the
//  user reacted with (the least recently used one drops out), and the emojis already on the message come after them.
//  Kept in the defaults database, like the other isaCloud settings.
//

import Foundation

enum RecentReactions {
    static let key = "recentReactionEmojis"
    static let size = 6
    static let initial = ["❤️", "👍", "👎", "😂", "😨", "🥲"]

    /// the stored list without empty and repeated emojis, cut to `size`, and completed with the initial emojis if short
    static func normalized(_ stored: [String]?) -> [String] {
        guard let stored = stored else {
            return initial
        }
        var result = Array(unique(stored).prefix(size))
        for emoji in initial where result.count < size && !result.contains(emoji) {
            result.append(emoji)
        }
        return result
    }

    /// the emoji goes to the front, its older place is removed, and the list is cut to `size`
    static func adding(_ emoji: String, to list: [String]) -> [String] {
        guard !emoji.isEmpty else {
            return list
        }
        let others = unique(list).filter { $0 != emoji }
        return Array(([emoji] + others).prefix(size))
    }

    /// the recent emojis, followed by the emojis the user already put on the message that are not in the recent ones
    static func row(recent: [String], own: [String]) -> [String] {
        var result = unique(recent)
        for emoji in own where !result.contains(emoji) {
            result.append(emoji)
        }
        return result
    }

    static func current() -> [String] {
        return normalized(HelperTools.defaultsDB().array(forKey: key) as? [String])
    }

    static func record(_ emoji: String) {
        let defaults = HelperTools.defaultsDB()
        let list = normalized(defaults.array(forKey: key) as? [String])
        defaults.set(adding(emoji, to: list), forKey: key)
    }

    private static func unique(_ emojis: [String]) -> [String] {
        var result: [String] = []
        for emoji in emojis where !emoji.isEmpty && !result.contains(emoji) {
            result.append(emoji)
        }
        return result
    }
}
