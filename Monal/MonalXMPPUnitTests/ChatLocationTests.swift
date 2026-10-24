//
//  ChatLocationTests.swift
//  MonalXMPPUnitTests
//
//  The text of a location message must be the geo: URI the other clients and Monal read.
//

import Testing

struct ChatLocationTests {

    @Test("the location message is a geo URI with latitude and longitude")
    func geoURI() {
        #expect(ChatLocation.geoURI(latitude: -23.5505, longitude: -46.6333) == "geo:-23.5505,-46.6333")
    }

    @Test("the location message starts with the geo scheme Monal reads as a location")
    func geoScheme() {
        #expect(ChatLocation.geoURI(latitude: 0, longitude: 0).hasPrefix("geo:"))
    }
}
