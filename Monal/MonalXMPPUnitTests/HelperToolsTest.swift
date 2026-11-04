//
//  HelperToolsTest.swift
//  MonalXMPPUnitTests
//
//  Created by Matthew Fennell on 09/08/2026.
//  Copyright © 2026 monal-im.org. All rights reserved.
//

import Testing
import UIKit
import ImageIO
import monalxmpp

struct HelperToolsTest {

    @Test("parseDateTime treats UTC XEP-0082 DateTimes as UTC", arguments: ["2026-08-09T19:51:11Z", "2026-08-09T19:51:11+00:00", "2026-08-09T19:51:11.000-00:00", "2026-08-09T19:51:11.000Z"])
    func testParseDateTimeTreatsUTCDatesAsUTC(_ dateString: String) {
        let expected = try! Date.ISO8601FormatStyle.iso8601.parse("2026-08-09T19:51:11Z")
        #expect(HelperTools.parseDateTime(dateString) == expected)
    }

    @Test("parseDateTime takes timezone offset into account when parsing non-UTC XEP-0082 DateTimes", arguments: ["2026-08-09T17:51:11-02:00", "2026-08-09T18:51:11.000-01:00", "2026-08-09T20:51:11+01:00", "2026-08-09T21:51:11.000+02:00"])
    func testParseDateTimeTakesTimezoneIntoAccount(_ dateString: String) {
        let expected = try! Date.ISO8601FormatStyle.iso8601.parse("2026-08-09T19:51:11Z")
        #expect(HelperTools.parseDateTime(dateString) == expected)
    }

    //isaCloud: XEP-0202 entity time response
    @Test("setEntityTime adds a XEP-0202 time element with the local timezone offset and the current UTC time")
    func testSetEntityTime() throws {
        let iq: XMPPIQ = XMPPIQ(type: kiqResultType)
        let before = Date()
        iq.setEntityTime()
        let xml = iq.xmlString

        let pattern = #"<time xmlns=['"]urn:xmpp:time['"]><tzo>([+-]\d{2}:\d{2})</tzo><utc>(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)</utc></time>"#
        let regex = try NSRegularExpression(pattern: pattern)
        let match = try #require(regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)), "unexpected XML: \(xml)")

        //timezone offset must match the device timezone
        let seconds = TimeZone.current.secondsFromGMT(for: before)
        let expectedTzo = String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+", abs(seconds) / 3600, (abs(seconds) % 3600) / 60)
        #expect(String(xml[Range(match.range(at: 1), in: xml)!]) == expectedTzo)

        //utc must be the current time (within a few seconds)
        let utc = try #require(HelperTools.parseDateTime(String(xml[Range(match.range(at: 2), in: xml)!])))
        #expect(abs(utc.timeIntervalSince(before)) < 5)
    }

    //isaCloud: mention = whole word of the names, any case and accents
    @Test("text mentions a name as a whole word", arguments: ["oi isa", "isa, vem aqui", "@isa pode ver?", "ISA!", "obrigada, isa.", "(isa)", "isa@isacloud.im escreveu", "Isa", "isá aqui"])
    func testTextMentionsWholeWord(_ text: String) {
        #expect(HelperTools.text(text, mentionsAnyOfNames: ["isa", "isa@isacloud.im"]))
    }

    @Test("text does not mention a name inside another word", arguments: ["isafashiondev", "precisa", "analisar", "avisar", "pesquisa", "Elisa", "isaías", "isa_dev", "visão", "íisa"])
    func testTextIgnoresNameInsideWord(_ text: String) {
        #expect(!HelperTools.text(text, mentionsAnyOfNames: ["isa", "isa@isacloud.im"]))
    }

    @Test("text mentions a name ignoring case and accents", arguments: ["oi zé", "ZE aqui", "Zé!"])
    func testTextMentionIgnoresCaseAndAccents(_ text: String) {
        #expect(HelperTools.text(text, mentionsAnyOfNames: ["Zé"]))
    }

    //isaCloud: display name with a space is searched as a whole
    @Test("text mentions a name with a space as a whole")
    func testTextMentionsNameWithSpace() {
        #expect(HelperTools.text("oi Isa Ribeiro!", mentionsAnyOfNames: ["Isa Ribeiro"]))
        #expect(!HelperTools.text("Elisa Ribeiro", mentionsAnyOfNames: ["Isa Ribeiro"]))
    }

    //isaCloud: nick with a hyphen is searched as a whole
    @Test("text mentions a name with a hyphen as a whole")
    func testTextMentionsNameWithHyphen() {
        #expect(HelperTools.text("valeu isa-dev", mentionsAnyOfNames: ["isa-dev"]))
        #expect(!HelperTools.text("pisa-dev", mentionsAnyOfNames: ["isa-dev"]))
    }

    //isaCloud: empty names never match and a rejected occurrence does not hide a valid one
    @Test("text never mentions empty names")
    func testTextIgnoresEmptyNames() {
        #expect(!HelperTools.text("oi isa", mentionsAnyOfNames: ["", "   "]))
        #expect(!HelperTools.text("oi isa", mentionsAnyOfNames: []))
        #expect(!HelperTools.text("", mentionsAnyOfNames: ["isa"]))
    }

    @Test("text finds a valid occurrence after a rejected one")
    func testTextFindsValidOccurrenceAfterRejected() {
        #expect(HelperTools.text("precisa falar com a isa", mentionsAnyOfNames: ["isa"]))
    }

}

/// isaCloud: photo reduction before the upload (docs/analise-comprimir-imagens.md)
struct ImageCompressionTests {
    private static let mib: UInt64 = 1024 * 1024

    @Test("large mode reduces only photos above 2 MiB")
    func largeModeLimit() {
        #expect(MLFiletransfer.shouldCompressImage(ofSize: 2 * Self.mib, inMode: "large") == false)
        #expect(MLFiletransfer.shouldCompressImage(ofSize: 2 * Self.mib + 1, inMode: "large") == true)
    }

    @Test("never mode does not reduce any photo")
    func neverModeKeepsOriginal() {
        #expect(MLFiletransfer.shouldCompressImage(ofSize: 50 * Self.mib, inMode: "never") == false)
        #expect(MLFiletransfer.shouldCompressImage(ofSize: 1, inMode: "never") == false)
    }

    @Test("always mode reduces every photo, even a small one")
    func alwaysModeReducesSmallPhotos() {
        #expect(MLFiletransfer.shouldCompressImage(ofSize: 1, inMode: "always") == true)
        #expect(MLFiletransfer.shouldCompressImage(ofSize: 50 * Self.mib, inMode: "always") == true)
    }

    @Test("a photo with EXIF orientation 6 keeps its visual orientation when reduced, and the longest side is within the limit")
    func resizedFileKeepsOrientation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        //400 x 200 pixels stored, shown rotated by 90 degrees: 200 x 400 (portrait) on the screen
        let source = folder.appendingPathComponent("foto.jpg")
        try Self.writeJPEG(width: 400, height: 200, orientation: 6, to: source)

        let resized = try #require(MLFiletransfer.resizedImageFile(for: source, maxPixelSize: 100, quality: 0.8))
        defer {
            try? FileManager.default.removeItem(at: resized.deletingLastPathComponent())
        }
        let image = try #require(UIImage(contentsOfFile: resized.path))
        //the pixels are already upright: no orientation is left to apply on the receiver
        #expect(image.imageOrientation == .up)
        #expect(image.size.height > image.size.width)
        #expect(max(image.size.width, image.size.height) <= 100)
        #expect(resized.lastPathComponent == "foto.jpg")
    }

    @Test("a landscape photo is reduced to the limit on its longest side")
    func resizedFileLongestSide() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let source = folder.appendingPathComponent("paisagem.jpg")
        try Self.writeJPEG(width: 3000, height: 2000, orientation: nil, to: source)

        let resized = try #require(MLFiletransfer.resizedImageFile(for: source, maxPixelSize: 1920, quality: 0.8))
        defer {
            try? FileManager.default.removeItem(at: resized.deletingLastPathComponent())
        }
        let image = try #require(UIImage(contentsOfFile: resized.path))
        #expect(image.size.width == 1920)
        #expect(image.size.height == 1280)
    }

    @Test("a small photo with a rotation tag is normalized even under the limit, without being enlarged")
    func smallRotatedPhotoIsNormalized() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        //200 x 100 stored with orientation 6: shown as 100 x 200 (portrait), far below 2 MiB
        let source = folder.appendingPathComponent("pequena.jpg")
        try Self.writeJPEG(width: 200, height: 100, orientation: 6, to: source)
        #expect(MLFiletransfer.imageFileNeedsCompression(source) == true)

        let resized = try #require(MLFiletransfer.resizedImageFile(for: source, maxPixelSize: 1920, quality: 0.8))
        defer {
            try? FileManager.default.removeItem(at: resized.deletingLastPathComponent())
        }
        let image = try #require(UIImage(contentsOfFile: resized.path))
        #expect(image.imageOrientation == .up)
        #expect(image.size == CGSize(width: 100, height: 200))
    }

    @Test("a photo without rotation tag and under the limit is not reduced in large mode")
    func untaggedSmallPhotoIsKept() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let source = folder.appendingPathComponent("normal.jpg")
        try Self.writeJPEG(width: 200, height: 100, orientation: nil, to: source)
        #expect(MLFiletransfer.imageFileNeedsCompression(source) == false)
    }

    @Test("an in-memory image with orientation right is drawn upright when reduced")
    func resizedImageKeepsOrientation() throws {
        let cgImage = try #require(Self.makeImage(width: 400, height: 200).cgImage)
        //shown rotated by 90 degrees: 200 x 400 (portrait)
        let image = UIImage(cgImage: cgImage, scale: 1, orientation: .right)
        let data = try #require(MLFiletransfer.resizedJPEGData(for: image, maxPixelSize: 100, quality: 0.8))
        let result = try #require(UIImage(data: data))
        #expect(result.imageOrientation == .up)
        #expect(result.size.height > result.size.width)
        #expect(max(result.size.width, result.size.height) <= 100)
    }

    @Test("a file that is not an image gives no resized copy, so the original is sent")
    func unreadableFileGivesNoCopy() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let source = folder.appendingPathComponent("texto.jpg")
        try Data("isso não é uma imagem".utf8).write(to: source)
        #expect(MLFiletransfer.resizedImageFile(for: source, maxPixelSize: 100, quality: 0.8) == nil)
    }

    private static func makeImage(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            //left half red, right half blue: the halves tell the orientation apart
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            UIColor.blue.setFill()
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
    }

    private static func writeJPEG(width: Int, height: Int, orientation: Int?, to url: URL) throws {
        let image = makeImage(width: width, height: height)
        guard let cgImage = image.cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
