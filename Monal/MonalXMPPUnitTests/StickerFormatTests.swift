//
//  StickerFormatTests.swift
//  MonalXMPPUnitTests
//
//  isaCloud: the format of a sticker comes from its bytes (StickerLibrary.format(of:)). This file is NOT in the MonalXMPPUnitTests target yet:
//  add it to that target together with Monal/Classes/Stickers.swift before running it.
//

import Foundation
import Testing

struct StickerFormatTests {

    @Test("GIF8 is a GIF, the PNG signature is a PNG, and anything else is neither")
    func formatFromBytes() {
        #expect(StickerLibrary.format(of: Data("GIF89a....".utf8)) == "gif")
        #expect(StickerLibrary.format(of: Data("GIF87a....".utf8)) == "gif")
        #expect(StickerLibrary.format(of: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) == "png")
        #expect(StickerLibrary.format(of: Data([0xFF, 0xD8, 0xFF, 0xE0])) == nil)
        #expect(StickerLibrary.format(of: Data("não é imagem".utf8)) == nil)
        #expect(StickerLibrary.format(of: Data([0x47, 0x49])) == nil)
        #expect(StickerLibrary.format(of: Data()) == nil)
    }
}
