//
//  PollsTests.swift
//  MonalXMPPUnitTests
//
//  isaCloud: polls (urn:fluux:poll:0). The rules of Polls.swift (tally, toggle of a vote, deadline, bodies, check of a closing) and what we send
//  (the <poll> and <poll-closed> elements of XMPPMessage). See docs/implementacao-enquetes-ios.md, sections 2, 5 and 7.
//

import Foundation
import Testing
import monalxmpp

struct PollsTests {

    //the keycaps of the default options: 0031 FE0F 20E3 and 0032 FE0F 20E3, as the protocol wants them
    private let one = "1\u{FE0F}\u{20E3}"
    private let two = "2\u{FE0F}\u{20E3}"
    private let thumbsUp = "\u{1F44D}"

    private func poll(multiple: Bool = false, hide: Bool = false, deadline: Int64? = nil, description: String? = nil) -> PollDefinition {
        return PollDefinition(
            title: "Almoço?",
            description: description,
            allowMultiple: multiple,
            hideResults: hide,
            deadline: deadline,
            options: [PollOption(emoji: one, label: "Pizza"), PollOption(emoji: two, label: "Sushi")]
        )
    }

    private func voter(_ nick: String, _ reactions: [String]) -> PollVoter {
        return PollVoter(id: nick, nick: nick, reactions: reactions)
    }

    //MARK: definition

    @Test("a poll needs a title and two options with emoji and label")
    func testPollNeedsTitleAndTwoOptions() {
        #expect(PollRules.definition(title: nil, description: nil, allowMultiple: false, hideResults: false, deadlineText: nil,
                                     options: [PollOption(emoji: one, label: "a"), PollOption(emoji: two, label: "b")]) == nil)
        #expect(PollRules.definition(title: "  ", description: nil, allowMultiple: false, hideResults: false, deadlineText: nil,
                                     options: [PollOption(emoji: one, label: "a"), PollOption(emoji: two, label: "b")]) == nil)
        //one option is not a poll
        #expect(PollRules.definition(title: "x", description: nil, allowMultiple: false, hideResults: false, deadlineText: nil,
                                     options: [PollOption(emoji: one, label: "a")]) == nil)
        //an option without emoji or label is left out, so only one option is left
        #expect(PollRules.definition(title: "x", description: nil, allowMultiple: false, hideResults: false, deadlineText: nil,
                                     options: [PollOption(emoji: one, label: "a"), PollOption(emoji: "", label: "b"), PollOption(emoji: two, label: " ")]) == nil)
    }

    @Test("options without emoji or label are dropped, an empty description is no description")
    func testOptionsAndDescriptionAreCleaned() {
        let definition = PollRules.definition(title: "x", description: "", allowMultiple: true, hideResults: true, deadlineText: nil,
                                              options: [PollOption(emoji: one, label: "a"), PollOption(emoji: "", label: "b"), PollOption(emoji: two, label: "c")])
        #expect(definition?.options.count == 2)
        #expect(definition?.description == nil)
        #expect(definition?.allowMultiple == true)
        #expect(definition?.hideResults == true)
    }

    @Test("deadline in ISO 8601, with and without fractions of a second", arguments: [
        "2026-12-01T10:00:00.000Z",
        "2026-12-01T10:00:00Z",
        "2026-12-01T07:00:00.000-03:00",
    ])
    func testDeadlineFormats(_ text: String) {
        #expect(PollRules.parseDeadline(text) == 1_796_119_200_000)
    }

    @Test("a deadline that is no date is no deadline")
    func testInvalidDeadline() {
        #expect(PollRules.parseDeadline("amanhã") == nil)
        let definition = PollRules.definition(title: "x", description: nil, allowMultiple: false, hideResults: false, deadlineText: "amanhã",
                                              options: [PollOption(emoji: one, label: "a"), PollOption(emoji: two, label: "b")])
        #expect(definition?.deadline == nil)
    }

    @Test("deadline is written with milliseconds and read back")
    func testDeadlineRoundTrip() {
        let text = PollRules.formatDeadline(1_796_119_200_000)
        #expect(text.hasSuffix(".000Z"))
        #expect(PollRules.parseDeadline(text) == 1_796_119_200_000)
    }

    //MARK: JSON

    @Test("the poll JSON round trips and keeps the emoji of the options as they came")
    func testJSONRoundTrip() throws {
        let original = poll(multiple: true, hide: true, deadline: 1_796_119_200_000, description: "com descrição")
        let json = try #require(PollRules.encode(original))
        #expect(PollRules.decode(json) == original)
        //the keycap is written as 0031 FE0F 20E3, byte for byte
        #expect(json.contains("1\u{FE0F}\u{20E3}"))
    }

    @Test("a poll JSON without the flags reads them as false")
    func testJSONWithoutFlags() throws {
        let json = #"{"title":"Almoço?","options":[{"emoji":"1️⃣","label":"Pizza"},{"emoji":"2️⃣","label":"Sushi"}]}"#
        let decoded = try #require(PollRules.decode(json))
        #expect(decoded.allowMultiple == false)
        #expect(decoded.hideResults == false)
        #expect(decoded.deadline == nil)
    }

    @Test("the closing JSON round trips")
    func testClosedJSONRoundTrip() throws {
        let closed = PollClosedInfo(messageId: "poll-1", title: "Almoço?", description: nil, tally: [
            PollTallyEntry(emoji: one, label: "Pizza", count: 3, voters: ["ana", "bia"]),
            PollTallyEntry(emoji: two, label: "Sushi", count: 7, voters: []),
        ])
        let json = try #require(PollRules.encode(closed))
        #expect(PollRules.decodeClosed(json) == closed)
    }

    //MARK: tally

    @Test("single choice: a voter counts only on the last option he reacted with (legacy 1️⃣ and 2️⃣ count on 2️⃣)")
    func testSingleChoiceLastWins() {
        let voters = [voter("ana", [one, two]), voter("bia", [one])]
        let tally = PollRules.tally(poll(), voters: voters)
        #expect(tally.entries.map(\.count) == [1, 1])
        #expect(tally.entries[0].voters == ["bia"])
        #expect(tally.entries[1].voters == ["ana"])
        #expect(tally.totalVoters == 2)
    }

    @Test("multiple choice: a voter counts on every option he reacted with")
    func testMultipleChoice() {
        let voters = [voter("ana", [one, two]), voter("bia", [two])]
        let tally = PollRules.tally(poll(multiple: true), voters: voters)
        #expect(tally.entries.map(\.count) == [1, 2])
        #expect(tally.totalVoters == 2)
    }

    @Test("the total counts each voter once, and reactions that are no option do not count")
    func testTotalAndOtherReactions() {
        let voters = [voter("ana", [one, two]), voter("bia", [thumbsUp]), voter("carla", [])]
        let tally = PollRules.tally(poll(multiple: true), voters: voters)
        #expect(tally.totalVoters == 1)
        #expect(tally.entries.map(\.count) == [1, 1])
    }

    @Test("keys ignore the variation selector: a keycap stored without FE0F still counts")
    func testTallyIgnoresVariationSelector() {
        let tally = PollRules.tally(poll(), voters: [voter("ana", ["1\u{20E3}"])])
        #expect(tally.entries.map(\.count) == [1, 0])
    }

    @Test("the closing carries the tally with nicks, and a voter without nick is counted but not named")
    func testClosedInfoFromTally() {
        let voters = [voter("ana", [one]), PollVoter(id: "anon", nick: nil, reactions: [one]), voter("bia", [two])]
        let closed = PollRules.closedInfo(for: poll(), messageId: "poll-1", voters: voters)
        #expect(closed.messageId == "poll-1")
        #expect(closed.title == "Almoço?")
        #expect(closed.tally[0].count == 2)
        #expect(closed.tally[0].voters == ["ana"])
        #expect(closed.tally[1].voters == ["bia"])
    }

    //MARK: voting

    @Test("single choice: tapping an option chooses it, tapping the chosen one again takes the vote back")
    func testToggleSingleChoice() {
        let single = poll()
        #expect(PollRules.toggledReactions(single, current: [], optionEmoji: one) == [one])
        #expect(PollRules.toggledReactions(single, current: [one], optionEmoji: two) == [two])
        #expect(PollRules.toggledReactions(single, current: [two], optionEmoji: two) == [])
        //a legacy set with both numbers: the effective choice is 2️⃣, so tapping 1️⃣ leaves 1️⃣ alone
        #expect(PollRules.toggledReactions(single, current: [one, two], optionEmoji: one) == [one])
    }

    @Test("multiple choice: only the tapped option toggles")
    func testToggleMultipleChoice() {
        let multiple = poll(multiple: true)
        #expect(PollRules.toggledReactions(multiple, current: [one], optionEmoji: two) == [one, two])
        #expect(PollRules.toggledReactions(multiple, current: [one, two], optionEmoji: one) == [two])
    }

    @Test("reactions that are no option stay, in their order, and the new one goes last")
    func testToggleKeepsOtherReactions() {
        #expect(PollRules.toggledReactions(poll(), current: [thumbsUp, one], optionEmoji: two) == [thumbsUp, two])
        #expect(PollRules.toggledReactions(poll(multiple: true), current: [thumbsUp, one], optionEmoji: two) == [thumbsUp, one, two])
    }

    @Test("the emoji sent is the one of the option, even when the stored keycap has no FE0F")
    func testToggleSendsRawOptionEmoji() {
        #expect(PollRules.toggledReactions(poll(), current: ["1\u{20E3}"], optionEmoji: "1\u{20E3}") == [])
        #expect(PollRules.toggledReactions(poll(), current: [], optionEmoji: "1\u{20E3}") == [one])
    }

    @Test("tapping something that is no option of the poll changes nothing")
    func testToggleNotAnOption() {
        #expect(PollRules.toggledReactions(poll(), current: [one], optionEmoji: thumbsUp) == nil)
    }

    @Test("a poll takes votes until its deadline")
    func testCanVote() {
        let now = Date(timeIntervalSince1970: 1_796_000_000)
        #expect(PollRules.canVote(poll(), now: now))
        #expect(PollRules.canVote(poll(deadline: 1_796_119_200_000), now: now))
        #expect(!PollRules.canVote(poll(deadline: 1_795_000_000_000), now: now))
    }

    //MARK: bodies and closing

    @Test("the fallback body is exact")
    func testFallbackBody() {
        #expect(PollRules.fallbackBody(poll()) == "📊 Poll: Almoço?\n\(one) Pizza\n\(two) Sushi")
        #expect(PollRules.fallbackBody(poll(description: "Hoje")) == "📊 Poll: Almoço?\nHoje\n\(one) Pizza\n\(two) Sushi")
    }

    @Test("the body of a closing is exact")
    func testClosedFallbackBody() {
        let closed = PollClosedInfo(messageId: "poll-1", title: "Almoço?", description: nil, tally: [
            PollTallyEntry(emoji: one, label: "Pizza", count: 3, voters: []),
            PollTallyEntry(emoji: two, label: "Sushi", count: 7, voters: []),
        ])
        #expect(PollRules.closedFallbackBody(closed) == "📊 Poll encerrada: Almoço?\n\(one) Pizza: 3\n\(two) Sushi: 7")
    }

    @Test("a closing matches a poll with the same title and emojis of options only")
    func testClosedMatches() {
        let closedAll = PollClosedInfo(messageId: "poll-1", title: "Almoço?", description: nil, tally: [
            PollTallyEntry(emoji: two, label: "Sushi", count: 1, voters: []),
        ])
        #expect(PollRules.closed(closedAll, matches: poll()))
        let otherTitle = PollClosedInfo(messageId: "poll-1", title: "Janta?", description: nil, tally: [])
        #expect(!PollRules.closed(otherTitle, matches: poll()))
        let unknownEmoji = PollClosedInfo(messageId: "poll-1", title: "Almoço?", description: nil, tally: [
            PollTallyEntry(emoji: "3\u{FE0F}\u{20E3}", label: "Macarrão", count: 1, voters: []),
        ])
        #expect(!PollRules.closed(unknownEmoji, matches: poll()))
    }

    //MARK: what we send and what we read (XML)

    @Test("a poll element carries the title, the options and only the flags that are true")
    func testPollElement() throws {
        let message = XMPPMessage(type: "groupchat", to: "sala@conference.example.org")!
        let json = try #require(PollRules.encode(poll(multiple: true, hide: false, deadline: 1_796_119_200_000, description: "Hoje")))
        message.addPoll(fromJSON: json)
        let xml = message.xmlString
        #expect(xml.contains("allow-multiple='true'"))
        #expect(!xml.contains("hide-results"))
        #expect(xml.contains("deadline='2026-12-01T10:00:00.000Z'"))
        #expect(xml.contains("<title>Almoço?</title>"))
        #expect(xml.contains("<description>Hoje</description>"))
        #expect(xml.contains("<option emoji='\(one)'>Pizza</option>"))
        #expect(xml.contains("<option emoji='\(two)'>Sushi</option>"))
        #expect(xml.contains("<fallback for='urn:fluux:poll:0' xmlns='urn:xmpp:fallback:0'><body/></fallback>"))
    }

    @Test("a poll element with no flags has no flag attributes")
    func testPollElementWithoutFlags() throws {
        let message = XMPPMessage(type: "groupchat", to: "sala@conference.example.org")!
        let json = try #require(PollRules.encode(poll()))
        message.addPoll(fromJSON: json)
        let xml = message.xmlString
        #expect(!xml.contains("allow-multiple"))
        #expect(!xml.contains("hide-results"))
        #expect(!xml.contains("deadline"))
    }

    @Test("a closing element carries message-id, the tally with count and the voters that have a nick")
    func testPollClosedElement() throws {
        let message = XMPPMessage(type: "groupchat", to: "sala@conference.example.org")!
        let closed = PollClosedInfo(messageId: "poll-1", title: "Almoço?", description: nil, tally: [
            PollTallyEntry(emoji: one, label: "Pizza", count: 3, voters: ["ana", "bia"]),
            PollTallyEntry(emoji: two, label: "Sushi", count: 0, voters: []),
        ])
        let json = try #require(PollRules.encode(closed))
        message.addPollClosed(fromJSON: json)
        let xml = message.xmlString
        #expect(xml.contains("<poll-closed"))
        #expect(xml.contains("message-id='poll-1'"))
        #expect(xml.contains("<tally count='3' emoji='\(one)' label='Pizza' voters='ana,bia'/>"))
        #expect(xml.contains("<tally count='0' emoji='\(two)' label='Sushi'/>"))
        #expect(xml.contains("<fallback for='urn:fluux:poll:0' xmlns='urn:xmpp:fallback:0'><body/></fallback>"))
    }

    @Test("the fields read back from the poll JSON are the ones a <poll> needs")
    func testPollFieldsFromJSON() throws {
        let json = try #require(PollRules.encode(poll(multiple: true, deadline: 1_796_119_200_000)))
        let fields = try #require(ISACloudPolls.pollFields(fromJSON: json))
        #expect(fields["title"] as? String == "Almoço?")
        #expect(fields["allowMultiple"] as? Bool == true)
        #expect(fields["hideResults"] as? Bool == false)
        #expect(fields["deadline"] as? String == "2026-12-01T10:00:00.000Z")
        #expect((fields["options"] as? [[String: String]])?.count == 2)
    }

    @Test("the Objective-C face refuses a poll without two options and takes a valid one")
    func testBridgeValidation() {
        #expect(ISACloudPolls.pollJSON(fromFields: ["title": "x", "options": [["emoji": one, "label": "a"]]]) == nil)
        let json = ISACloudPolls.pollJSON(fromFields: [
            "title": "x",
            "allowMultiple": true,
            "options": [["emoji": one, "label": "a"], ["emoji": two, "label": "b"]],
        ])
        #expect(json != nil)
        #expect(ISACloudPolls.canVote(pollJSON: json ?? "") == true)
    }
}
