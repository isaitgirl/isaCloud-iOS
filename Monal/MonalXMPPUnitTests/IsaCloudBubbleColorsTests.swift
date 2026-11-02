//
//  IsaCloudBubbleColorsTests.swift
//  MonalXMPPUnitTests
//
//  The colours of the messages the user sends: "#RRGGBB" text to Color and back, invalid values, and the WCAG contrast.
//  Only the pure helpers (IsaCloudColorMath) are tested here: they do not read the settings.
//

import SwiftUI
import Testing

struct IsaCloudBubbleColorsTests {

    @Test("a hex colour goes to Color and comes back the same, in uppercase")
    func hexRoundTrip() throws {
        for hex in ["#FF006F", "#000000", "#FFFFFF", "#12AB34"] {
            let color = try #require(IsaCloudColorMath.color(fromHex: hex))
            #expect(IsaCloudColorMath.hex(from: color) == hex)
        }
    }

    @Test("the hash is optional and the case does not matter")
    func hexWithoutHashAndLowercase() throws {
        let color = try #require(IsaCloudColorMath.color(fromHex: "ff006f"))
        #expect(IsaCloudColorMath.hex(from: color) == "#FF006F")
    }

    @Test("an empty or invalid hex value is no colour, so the isaCloud default is used")
    func invalidHexIsNoColour() {
        #expect(IsaCloudColorMath.color(fromHex: "") == nil)
        #expect(IsaCloudColorMath.color(fromHex: "#") == nil)
        #expect(IsaCloudColorMath.color(fromHex: "#12345") == nil)
        #expect(IsaCloudColorMath.color(fromHex: "#1234567") == nil)
        #expect(IsaCloudColorMath.color(fromHex: "#GG0000") == nil)
        #expect(IsaCloudColorMath.color(fromHex: "+12345") == nil)
    }

    @Test("white on black is the highest contrast, 21 to 1")
    func contrastWhiteOnBlack() {
        let ratio = IsaCloudColorMath.contrastRatio(.white, .black)
        #expect(abs(ratio - 21) < 0.01)
    }

    @Test("a colour has no contrast with itself: 1 to 1")
    func contrastSameColour() {
        #expect(abs(IsaCloudColorMath.contrastRatio(.white, .white) - 1) < 0.01)
    }

    @Test("the order of the two colours does not change the contrast")
    func contrastIsSymmetric() {
        let pink = IsaCloudColorMath.color(fromHex: "#FF006F")!
        #expect(abs(IsaCloudColorMath.contrastRatio(pink, .white) - IsaCloudColorMath.contrastRatio(.white, pink)) < 0.0001)
    }

    @Test("black text on white is readable, white text on white is not")
    func readableContrast() {
        #expect(IsaCloudColorMath.isReadable(bubble: .white, text: .black))
        #expect(!IsaCloudColorMath.isReadable(bubble: .white, text: .white))
    }

    @Test("the isaCloud default (white on the pink #FF006F) is measured below 4.5, so the default is not warned about in the settings")
    func defaultPinkWithWhiteIsBelowThreshold() {
        // the pink of the isaCloudPink asset is sRGB 255, 0, 111. Its contrast with white is about 3.8: the value is kept,
        // only the warning for colours chosen by the person depends on it (IsaCloudBubbleColors.hasReadableContrast)
        let pink = IsaCloudColorMath.color(fromHex: "#FF006F")!
        let ratio = IsaCloudColorMath.contrastRatio(pink, .white)
        #expect(ratio > 3.5 && ratio < 4.5)
        #expect(!IsaCloudColorMath.isReadable(bubble: pink, text: .white))
    }
}
