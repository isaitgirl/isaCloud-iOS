//
//  HelperToolsTest.swift
//  MonalXMPPUnitTests
//
//  Created by Matthew Fennell on 09/08/2026.
//  Copyright © 2026 monal-im.org. All rights reserved.
//

import Testing
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

}
