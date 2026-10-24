//
//  ChatLocation.swift
//  Monal
//
//  isaCloud: the text of a location message. It is the same "geo:" URI the other XMPP clients and Monal's own messages use.
//

import Foundation

enum ChatLocation {
    static func geoURI(latitude: Double, longitude: Double) -> String {
        return "geo:\(latitude),\(longitude)"
    }
}
