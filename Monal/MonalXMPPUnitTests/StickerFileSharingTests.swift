//
//  StickerFileSharingTests.swift
//  MonalXMPPUnitTests
//
//  isaCloud: XEP-0449 stickers. What we send (file sharing with the metadata of the file) and what we take from a message
//  (the https url of a sticker's file sharing, when there is no OOB link). See docs/analise-xep0449-conformidade.md.
//

import Foundation
import UIKit
import CryptoKit
import Testing
import monalxmpp

struct StickerFileSharingTests {

    /// a 512x512 PNG (one pixel per point, whatever the screen scale) in a temporary file
    private func writeStickerPng() -> String {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format)
        let png = renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("sticker-test-\(UUID().uuidString).png").path
        try! png.write(to: URL(fileURLWithPath: path))
        return path
    }

    @Test("the file sharing of a sticker has the type, size, dimensions and the base64 sha-256 of its file")
    func fileSharingMetadata() throws {
        let path = writeStickerPng()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let expectedHash = Data(SHA256.hash(data: data)).base64EncodedString()

        let node = try #require(MLFiletransfer.isaCloudFileSharingNode(forFileAtPath: path, url: "https://upload.example.org/sticker.png", mimeType: "image/png"))
        let xml = node.xmlString

        #expect(xml.contains("urn:xmpp:sfs:0"))
        #expect(xml.contains("disposition='inline'") || xml.contains("disposition=\"inline\""))
        #expect(xml.contains("image/png"))
        #expect(xml.contains("<size>\(data.count)</size>"))
        #expect(xml.contains("<dimensions>512x512</dimensions>"))
        #expect(xml.contains("<width>512</width>"))
        #expect(xml.contains("<height>512</height>"))
        #expect(xml.contains(expectedHash))
        #expect(xml.contains("sha-256"))
        #expect(xml.contains("url-data"))
        #expect(xml.contains("https://upload.example.org/sticker.png"))
    }

    @Test("a file that is not an image gets no file sharing, and neither does a missing one")
    func noFileSharingWithoutImage() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("not-an-image-\(UUID().uuidString).txt").path
        try Data("texto".utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect(MLFiletransfer.isaCloudFileSharingNode(forFileAtPath: path, url: "https://upload.example.org/a.txt", mimeType: "text/plain") == nil)
        #expect(MLFiletransfer.isaCloudFileSharingNode(forFileAtPath: "/nao/existe/figurinha.png", url: "https://upload.example.org/a.png", mimeType: "image/png") == nil)
    }

    @Test("a sticker without OOB is a file by its https url-data source")
    func receivesFileSharingUrl() {
        let message = MLXMLNode(element: "message", andNamespace: "jabber:client")
        message.addChildNode(MLXMLNode(element: "sticker", andNamespace: "urn:xmpp:stickers:0"))
        let urlData = MLXMLNode(element: "url-data", andNamespace: "http://jabber.org/protocol/url-data", withAttributes: ["target": "https://upload.example.org/x.png"], andChildren: [], andData: nil)
        let sources = MLXMLNode(element: "sources", andNamespace: "urn:xmpp:sfs:0", withAttributes: [:], andChildren: [urlData], andData: nil)
        let fileSharing = MLXMLNode(element: "file-sharing", andNamespace: "urn:xmpp:sfs:0", withAttributes: ["disposition": "inline"], andChildren: [sources], andData: nil)
        message.addChildNode(fileSharing)

        #expect(MLFiletransfer.isaCloudFileSharingUrl(ofMessageNode: message) == "https://upload.example.org/x.png")
    }

    @Test("only https sources count: an http link or another kind of source is not a file")
    func ignoresOtherSources() {
        let message = MLXMLNode(element: "message", andNamespace: "jabber:client")
        let httpData = MLXMLNode(element: "url-data", andNamespace: "http://jabber.org/protocol/url-data", withAttributes: ["target": "http://upload.example.org/x.png"], andChildren: [], andData: nil)
        let jingle = MLXMLNode(element: "jinglepub", andNamespace: "urn:xmpp:jinglepub:0", withAttributes: [:], andChildren: [], andData: nil)
        let sources = MLXMLNode(element: "sources", andNamespace: "urn:xmpp:sfs:0", withAttributes: [:], andChildren: [httpData, jingle], andData: nil)
        message.addChildNode(MLXMLNode(element: "file-sharing", andNamespace: "urn:xmpp:sfs:0", withAttributes: [:], andChildren: [sources], andData: nil))

        #expect(MLFiletransfer.isaCloudFileSharingUrl(ofMessageNode: message) == nil)

        //an https source after an http one is taken
        let httpsData = MLXMLNode(element: "url-data", andNamespace: "http://jabber.org/protocol/url-data", withAttributes: ["target": "https://upload.example.org/y.png"], andChildren: [], andData: nil)
        let both = MLXMLNode(element: "sources", andNamespace: "urn:xmpp:sfs:0", withAttributes: [:], andChildren: [httpData, httpsData], andData: nil)
        let second = MLXMLNode(element: "message", andNamespace: "jabber:client")
        second.addChildNode(MLXMLNode(element: "file-sharing", andNamespace: "urn:xmpp:sfs:0", withAttributes: [:], andChildren: [both], andData: nil))
        #expect(MLFiletransfer.isaCloudFileSharingUrl(ofMessageNode: second) == "https://upload.example.org/y.png")
    }
}
