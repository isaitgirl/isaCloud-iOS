//
//  MucHatRules.swift
//  Monal
//
//  isaCloud: rules of the hats (XEP-0317) of the occupants of a channel or group: the colour of each hat, the emoji of the
//  verified users, and the nick that a name shows (mentions use only the nick, never the emoji). No UI here, so it can be tested.
//

import Foundation

struct MucHat: Hashable {
    let uri: String
    let title: String

    static let verifiedTitle = "Verificado"
    static let verifiedEmoji = "🛡️"
    /// the colours of the hat pills; a hat always gets the same one for the same title
    static let paletteSize = 6

    /// index in the palette for a hat title. The hash is fixed (not Swift's randomised hashValue), so it is the same on every launch
    static func paletteIndex(forTitle title: String) -> Int {
        var hash: UInt32 = 5381
        for byte in title.utf8 {
            hash = hash &* 33 &+ UInt32(byte)
        }
        return Int(hash % UInt32(paletteSize))
    }

    /// the server sends the title with its emoji ("Verificado 🛡️"), so the title is recognised by its beginning
    static func isVerified(_ hats: [MucHat]) -> Bool {
        return hats.contains { $0.title.hasPrefix(verifiedTitle) }
    }
}

enum ChatNameWithHats {
    /// invisible marker between the nick and the emoji: everything before it is the nick
    static let marker = "\u{2060}\u{2060}"

    /// the name shown in the messages: the nick, and the verified emoji after a space
    static func displayName(nick: String, hats: [MucHat]) -> String {
        guard MucHat.isVerified(hats) else {
            return nick
        }
        return nick + marker + " " + MucHat.verifiedEmoji
    }

    /// the nick of a name shown in the messages, without the emoji (used when mentioning someone)
    static func nick(from name: String) -> String {
        return name.components(separatedBy: marker).first ?? name
    }
}
