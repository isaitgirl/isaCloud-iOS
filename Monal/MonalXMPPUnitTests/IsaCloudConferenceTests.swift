//
//  IsaCloudConferenceTests.swift
//  MonalXMPPUnitTests
//
//  The video conference: the answer of the meet-api must be a 201 with the expected JSON and the meet host's links, and only the
//  public links of the conference host are recognized in the chat.
//

import Testing
import Foundation

struct IsaCloudConferenceTests {

    private let validBody = """
    {"roomID":"qy3mqc6biep4o2ka","roomURL":"https://meet.isacloud.cc/join/qy3mqc6biep4o2ka","hostURL":"https://meet.isacloud.cc/u/qy3mqc6biep4o2ka/?token=t1&pk=p1","hostKey":"k1","expiresAt":"2026-11-22T12:15:15Z"}
    """

    @Test("a 201 with the expected JSON gives the room")
    func parsesRoom() throws {
        let room = try IsaCloudConferenceApi.parse(status: 201, data: Data(validBody.utf8))
        #expect(room.roomID == "qy3mqc6biep4o2ka")
        #expect(room.roomURL.absoluteString == "https://meet.isacloud.cc/join/qy3mqc6biep4o2ka")
        #expect(room.hostURL.host == "meet.isacloud.cc")
        #expect(room.hostKey == "k1")
        #expect(room.expiresAt == Date(timeIntervalSince1970: 1_795_349_715))
    }

    @Test("any answer other than 201 is a server error, whatever the body says")
    func rejectsOtherStatus() {
        for status in [200, 400, 429, 502] {
            #expect(throws: IsaCloudConferenceError.server) {
                try IsaCloudConferenceApi.parse(status: status, data: Data(validBody.utf8))
            }
        }
    }

    @Test("a 201 that is not the expected JSON is a bad response")
    func rejectsBadJSON() {
        #expect(throws: IsaCloudConferenceError.badResponse) {
            try IsaCloudConferenceApi.parse(status: 201, data: Data("não é json".utf8))
        }
        #expect(throws: IsaCloudConferenceError.badResponse) {
            try IsaCloudConferenceApi.parse(status: 201, data: Data("{\"roomID\":\"qy3mqc6biep4o2ka\"}".utf8))
        }
    }

    @Test("the host link must be https on the meet host")
    func rejectsHostURLOutsideMeet() {
        let plainHTTP = validBody.replacingOccurrences(of: "https://meet.isacloud.cc/u/", with: "http://meet.isacloud.cc/u/")
        let otherHost = validBody.replacingOccurrences(of: "https://meet.isacloud.cc/u/", with: "https://example.com/u/")
        #expect(throws: IsaCloudConferenceError.badResponse) {
            try IsaCloudConferenceApi.parse(status: 201, data: Data(plainHTTP.utf8))
        }
        #expect(throws: IsaCloudConferenceError.badResponse) {
            try IsaCloudConferenceApi.parse(status: 201, data: Data(otherHost.utf8))
        }
    }

    @Test("the public link must be the link of the same room")
    func rejectsRoomURLOfAnotherRoom() {
        let otherRoom = validBody.replacingOccurrences(of: "/join/qy3mqc6biep4o2ka", with: "/join/outrasala123")
        #expect(throws: IsaCloudConferenceError.badResponse) {
            try IsaCloudConferenceApi.parse(status: 201, data: Data(otherRoom.utf8))
        }
    }

    @Test("a conference link gives its room id")
    func roomIDOfJoinLink() throws {
        let url = try #require(URL(string: "https://meet.isacloud.cc/join/qy3mqc6biep4o2ka"))
        #expect(IsaCloudConference.roomID(from: url) == "qy3mqc6biep4o2ka")
        let withDashes = try #require(URL(string: "https://meet.isacloud.cc/join/abc_DEF-123"))
        #expect(IsaCloudConference.roomID(from: withDashes) == "abc_DEF-123")
    }

    @Test("other URLs are not conference links")
    func roomIDRejectsOtherURLs() throws {
        let urls = [
            "http://meet.isacloud.cc/join/abc",          // not https
            "https://example.com/join/abc",              // other host
            "https://meet.isacloud.cc/u/abc/?token=t",   // host link, not the public one
            "https://meet.isacloud.cc/join/",            // no id
            "https://meet.isacloud.cc/join/abc/",        // trailing slash
            "https://meet.isacloud.cc/join/abc?x=1",     // query
            "https://meet.isacloud.cc/join/abc#frag",    // fragment
            "https://meet.isacloud.cc/join/a.b",         // id outside [A-Za-z0-9_-]
            "https://meet.isacloud.cc:8443/join/abc",    // port
            "https://meet.isacloud.cc/meet-api/v1/rooms",
        ]
        for text in urls {
            let url = try #require(URL(string: text))
            #expect(IsaCloudConference.roomID(from: url) == nil, "\(text) must not be a conference link")
        }
    }
}
