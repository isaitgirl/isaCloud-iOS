//
//  Polls.swift
//  monalxmpp
//
//  isaCloud: polls (urn:fluux:poll:0), the protocol of the Fluux client and of the isaCloud Android app. Here only the models and the rules:
//  the XML is built and read in XMPPMessage.m and MLMessageProcessor.m, the card and the buttons are in the app. A vote is an XEP-0444
//  reaction on the emoji of the option. See docs/implementacao-enquetes-ios.md (sections 2 and 6) and docs/decisoes-enquetes-fluux.md.
//

import Foundation

//isaCloud: an option of a poll. The emoji is the key of the vote: it is kept exactly as it came, never rebuilt
public struct PollOption: Codable, Equatable {
    public let emoji: String
    public let label: String

    public init(emoji: String, label: String) {
        self.emoji = emoji
        self.label = label
    }
}

//isaCloud: the definition of a poll, stored as JSON in message_history.isacloud_poll
public struct PollDefinition: Codable, Equatable {
    public let title: String
    public let description: String?
    public let allowMultiple: Bool
    public let hideResults: Bool
    //isaCloud: epoch millis, nil when the poll has no deadline
    public let deadline: Int64?
    public let options: [PollOption]

    public init(title: String, description: String?, allowMultiple: Bool, hideResults: Bool, deadline: Int64?, options: [PollOption]) {
        self.title = title
        self.description = description
        self.allowMultiple = allowMultiple
        self.hideResults = hideResults
        self.deadline = deadline
        self.options = options
    }

    //isaCloud: the flags default to false when the JSON does not carry them
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        allowMultiple = try container.decodeIfPresent(Bool.self, forKey: .allowMultiple) ?? false
        hideResults = try container.decodeIfPresent(Bool.self, forKey: .hideResults) ?? false
        deadline = try container.decodeIfPresent(Int64.self, forKey: .deadline)
        options = try container.decode([PollOption].self, forKey: .options)
    }
}

//isaCloud: one line of the tally of a poll. voters are nicks (the <poll-closed> carries nicks, never jids or occupant ids)
public struct PollTallyEntry: Codable, Equatable {
    public let emoji: String
    public let label: String
    public let count: Int
    public let voters: [String]

    public init(emoji: String, label: String, count: Int, voters: [String]) {
        self.emoji = emoji
        self.label = label
        self.count = count
        self.voters = voters
    }
}

//isaCloud: the <poll-closed> of a poll, stored as JSON in message_history.isacloud_poll_closed (on the closing message)
public struct PollClosedInfo: Codable, Equatable {
    public let messageId: String
    public let title: String
    public let description: String?
    public let tally: [PollTallyEntry]

    public init(messageId: String, title: String, description: String?, tally: [PollTallyEntry]) {
        self.messageId = messageId
        self.title = title
        self.description = description
        self.tally = tally
    }
}

//isaCloud: one voter for the rules: `reactions` is the set of reactions this voter has on the poll message, as stored. nick is nil when unknown
public struct PollVoter: Equatable {
    public let id: String
    public let nick: String?
    public let reactions: [String]

    public init(id: String, nick: String?, reactions: [String]) {
        self.id = id
        self.nick = nick
        self.reactions = reactions
    }
}

//isaCloud: the result of counting the votes of a poll. totalVoters counts each voter once, even when the voter chose more than one option
public struct PollTally: Equatable {
    public let entries: [PollTallyEntry]
    public let totalVoters: Int

    public init(entries: [PollTallyEntry], totalVoters: Int) {
        self.entries = entries
        self.totalVoters = totalVoters
    }
}

//isaCloud: the rules of polls, without UI and without XMPP
public enum PollRules {

    //isaCloud: the key of an emoji for comparisons: the variation selectors (FE0E, FE0F) are left out. The emoji sent is never built from the key
    public static func key(_ emoji: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in emoji.unicodeScalars where scalar != "\u{FE0F}" && scalar != "\u{FE0E}" {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    //isaCloud: the count of each option. Single choice: each voter counts only on the LAST option (in the order of the options) he reacted with,
    //so a legacy client that reacted with 1️⃣ and 2️⃣ counts on 2️⃣ alone. Multiple choice: each voter counts on every option he reacted with
    public static func tally(_ poll: PollDefinition, voters: [PollVoter]) -> PollTally {
        let optionKeys = poll.options.map { key($0.emoji) }
        var counts = [Int](repeating: 0, count: poll.options.count)
        var nicks = [[String]](repeating: [], count: poll.options.count)
        var totalVoters = 0
        for voter in voters {
            let reacted = Set(voter.reactions.map { key($0) })
            var counted: [Int] = []
            if poll.allowMultiple {
                counted = optionKeys.indices.filter { reacted.contains(optionKeys[$0]) }
            } else if let last = optionKeys.indices.last(where: { reacted.contains(optionKeys[$0]) }) {
                counted = [last]
            }
            if !counted.isEmpty {
                totalVoters += 1
            }
            for index in counted {
                counts[index] += 1
                if let nick = voter.nick {
                    nicks[index].append(nick)
                }
            }
        }
        let entries = poll.options.indices.map { index in
            PollTallyEntry(emoji: poll.options[index].emoji, label: poll.options[index].label, count: counts[index], voters: nicks[index])
        }
        return PollTally(entries: entries, totalVoters: totalVoters)
    }

    //isaCloud: the new set of reactions of the user after tapping an option (XEP-0444 sends the whole set, see xmpp sendReactions:forMessage:).
    //Single choice: all option reactions are removed and the tapped one is added, unless it was already the user's choice (then it only goes away).
    //Multiple choice: only the tapped option toggles. Reactions that are not options (for example 👍) stay, in their order. nil if the emoji is no option of the poll
    public static func toggledReactions(_ poll: PollDefinition, current: [String], optionEmoji: String) -> [String]? {
        let target = key(optionEmoji)
        guard let option = poll.options.first(where: { key($0.emoji) == target }) else {
            return nil
        }
        let optionKeys = poll.options.map { key($0.emoji) }
        //the choice the user has now: multiple choice, the tapped option is among the reactions; single choice, the last option (in the order of the options) reacted with
        let chosen: Bool
        if poll.allowMultiple {
            chosen = current.contains { key($0) == target }
        } else {
            let reactedInOrder = optionKeys.filter { optionKey in current.contains { key($0) == optionKey } }
            chosen = reactedInOrder.last == target
        }
        //the reactions stay in their order; duplicates (same key) are dropped, the first one stays
        var result: [String] = []
        var seen = Set<String>()
        for reaction in current {
            let reactionKey = key(reaction)
            let isOption = optionKeys.contains(reactionKey)
            //single choice: every option reaction goes away (the chosen one comes back below); multiple choice: only the tapped option toggles
            if isOption && (!poll.allowMultiple || reactionKey == target) {
                continue
            }
            if seen.insert(reactionKey).inserted {
                result.append(reaction)
            }
        }
        if !chosen {
            result.append(option.emoji)     //the emoji of the option, exactly as it came in the poll
        }
        return result
    }

    //isaCloud: a poll takes votes while it has no deadline or the deadline is in the future (a closed poll is decided by its <poll-closed>, not here)
    public static func canVote(_ poll: PollDefinition, now: Date = Date()) -> Bool {
        guard let deadline = poll.deadline else {
            return true
        }
        return deadline > millis(now)
    }

    //isaCloud: the body of a poll for the clients that do not know the protocol (XEP-0428 fallback): the heading is fixed, also in pt-BR
    public static func fallbackBody(_ poll: PollDefinition) -> String {
        var lines = ["📊 Poll: \(poll.title)"]
        if let description = poll.description, !description.isEmpty {
            lines.append(description)
        }
        lines.append(contentsOf: poll.options.map { "\($0.emoji) \($0.label)" })
        return lines.joined(separator: "\n")
    }

    //isaCloud: the body of a closing message, for the clients that do not know the protocol
    public static func closedFallbackBody(_ closed: PollClosedInfo) -> String {
        var lines = ["📊 Poll encerrada: \(closed.title)"]
        lines.append(contentsOf: closed.tally.map { "\($0.emoji) \($0.label): \($0.count)" })
        return lines.joined(separator: "\n")
    }

    //isaCloud: the <poll-closed> is built from the tally of the reactions the poll has now (see docs/implementacao-enquetes-ios.md, 2.3)
    public static func closedInfo(for poll: PollDefinition, messageId: String, voters: [PollVoter]) -> PollClosedInfo {
        let result = tally(poll, voters: voters)
        return PollClosedInfo(messageId: messageId, title: poll.title, description: poll.description, tally: result.entries)
    }

    //isaCloud: the check before a <poll-closed> freezes the original poll (XEP-0POLL 5.6): the same title and every emoji of the tally is an option
    public static func closed(_ closed: PollClosedInfo, matches poll: PollDefinition) -> Bool {
        guard closed.title == poll.title else {
            return false
        }
        let optionKeys = Set(poll.options.map { key($0.emoji) })
        return closed.tally.allSatisfy { optionKeys.contains(key($0.emoji)) }
    }

    //isaCloud: a deadline in ISO 8601, with or without fractions of a second (JavaScript sends .000Z). nil if it is not a date
    public static func parseDeadline(_ text: String) -> Int64? {
        let withFractions = ISO8601DateFormatter()
        withFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFractions = ISO8601DateFormatter()
        withoutFractions.formatOptions = [.withInternetDateTime]
        guard let date = withFractions.date(from: text) ?? withoutFractions.date(from: text) else {
            return nil
        }
        return millis(date)
    }

    //isaCloud: the deadline as the XML carries it, with milliseconds (the formatter of HelperTools wants the fraction too)
    public static func formatDeadline(_ millis: Int64) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(millis) / 1000))
    }

    //isaCloud: the definition from the parts of a <poll> element. nil when it is not valid: a title and at least two options with emoji and label
    public static func definition(title: String?, description: String?, allowMultiple: Bool, hideResults: Bool, deadlineText: String?, options: [PollOption]) -> PollDefinition? {
        guard let title = title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let validOptions = options.filter {
            !$0.emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard validOptions.count >= 2 else {
            return nil
        }
        let deadline = deadlineText.flatMap { parseDeadline($0) }
        let text = description.flatMap { $0.isEmpty ? nil : $0 }
        return PollDefinition(title: title, description: text, allowMultiple: allowMultiple, hideResults: hideResults, deadline: deadline, options: validOptions)
    }

    //isaCloud: the closing from the parts of a <poll-closed> element. A count that is not a number, or is negative, is 0 (the XSD asks for a non-negative integer)
    public static func closedInfo(messageId: String?, title: String?, description: String?, tally: [(emoji: String, label: String, count: String?, voters: String?)]) -> PollClosedInfo? {
        guard let messageId = messageId, !messageId.isEmpty, let title = title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let entries: [PollTallyEntry] = tally.compactMap { line in
            guard !line.emoji.isEmpty else {
                return nil
            }
            let count = max(0, Int(line.count?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0)
            let voters = (line.voters ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return PollTallyEntry(emoji: line.emoji, label: line.label, count: count, voters: voters)
        }
        return PollClosedInfo(messageId: messageId, title: title, description: description.flatMap { $0.isEmpty ? nil : $0 }, tally: entries)
    }

    //isaCloud: the JSON of a definition and back. The keys are sorted, so the same poll always gives the same text
    public static func encode(_ poll: PollDefinition) -> String? {
        return encodeJSON(poll)
    }

    public static func decode(_ json: String) -> PollDefinition? {
        return decodeJSON(PollDefinition.self, json)
    }

    public static func encode(_ closed: PollClosedInfo) -> String? {
        return encodeJSON(closed)
    }

    public static func decodeClosed(_ json: String) -> PollClosedInfo? {
        return decodeJSON(PollClosedInfo.self, json)
    }

    private static func encodeJSON<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func millis(_ date: Date) -> Int64 {
        return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

//isaCloud: the Objective-C face of the rules (MLMessageProcessor, XMPPMessage, MLXMPPManager). The data goes in and out as JSON strings and as
//dictionaries with the names of the XML, so the Objective-C side never has to know the models. nil means "not valid"
@objc(ISACloudPolls) public final class ISACloudPolls: NSObject {

    //isaCloud: the poll JSON from the parts of a <poll>: title, description, allowMultiple, hideResults (NSNumber/Bool), deadline (ISO 8601 text),
    //options (array of {emoji, label}). nil when the poll is not valid
    @objc(pollJSONFromFields:)
    public static func pollJSON(fromFields fields: [String: Any]) -> String? {
        let options = (fields["options"] as? [[String: Any]] ?? []).map {
            PollOption(emoji: string($0["emoji"]) ?? "", label: string($0["label"]) ?? "")
        }
        guard let poll = PollRules.definition(
            title: string(fields["title"]),
            description: string(fields["description"]),
            allowMultiple: bool(fields["allowMultiple"]),
            hideResults: bool(fields["hideResults"]),
            deadlineText: string(fields["deadline"]),
            options: options
        ) else {
            return nil
        }
        return PollRules.encode(poll)
    }

    //isaCloud: the parts of a poll JSON, as a <poll> element needs them: title, description, allowMultiple, hideResults, deadline (ISO 8601 with
    //milliseconds), options (array of {emoji, label})
    @objc(pollFieldsFromJSON:)
    public static func pollFields(fromJSON json: String) -> [String: Any]? {
        guard let poll = PollRules.decode(json) else {
            return nil
        }
        var fields: [String: Any] = [
            "title": poll.title,
            "allowMultiple": poll.allowMultiple,
            "hideResults": poll.hideResults,
            "options": poll.options.map { ["emoji": $0.emoji, "label": $0.label] },
        ]
        if let description = poll.description {
            fields["description"] = description
        }
        if let deadline = poll.deadline {
            fields["deadline"] = PollRules.formatDeadline(deadline)
        }
        return fields
    }

    //isaCloud: the closing JSON from the parts of a <poll-closed>: messageId, title, description, tally (array of {emoji, label, count, voters})
    //where voters is the CSV text of the attribute. nil when it is not valid
    @objc(closedJSONFromFields:)
    public static func closedJSON(fromFields fields: [String: Any]) -> String? {
        let tally = (fields["tally"] as? [[String: Any]] ?? []).map {
            (emoji: string($0["emoji"]) ?? "", label: string($0["label"]) ?? "", count: string($0["count"]), voters: string($0["voters"]))
        }
        guard let closed = PollRules.closedInfo(
            messageId: string(fields["messageId"]),
            title: string(fields["title"]),
            description: string(fields["description"]),
            tally: tally
        ) else {
            return nil
        }
        return PollRules.encode(closed)
    }

    //isaCloud: the parts of a closing JSON, as a <poll-closed> element needs them. voters is a CSV string (empty when nobody has a nick)
    @objc(closedFieldsFromJSON:)
    public static func closedFields(fromJSON json: String) -> [String: Any]? {
        guard let closed = PollRules.decodeClosed(json) else {
            return nil
        }
        var fields: [String: Any] = [
            "messageId": closed.messageId,
            "title": closed.title,
            "tally": closed.tally.map { entry -> [String: Any] in
                ["emoji": entry.emoji, "label": entry.label, "count": entry.count, "voters": entry.voters.joined(separator: ",")]
            },
        ]
        if let description = closed.description {
            fields["description"] = description
        }
        return fields
    }

    //isaCloud: the closing JSON of one of our polls: the tally of the reactions it has now. voters is an array of {nick, reactions}
    //(nick omitted when unknown). nil when the poll JSON is not valid
    @objc(closedJSONForPollJSON:messageId:voters:)
    public static func closedJSON(forPollJSON pollJSON: String, messageId: String, voters: [[String: Any]]) -> String? {
        guard let poll = PollRules.decode(pollJSON) else {
            return nil
        }
        let pollVoters = voters.enumerated().map { index, voter in
            PollVoter(id: "\(index)", nick: string(voter["nick"]), reactions: (voter["reactions"] as? [String]) ?? [])
        }
        return PollRules.encode(PollRules.closedInfo(for: poll, messageId: messageId, voters: pollVoters))
    }

    //isaCloud: the fallback body of a poll (the text of the message, for the clients that do not know the protocol)
    @objc(fallbackBodyForPollJSON:)
    public static func fallbackBody(forPollJSON json: String) -> String? {
        return PollRules.decode(json).map { PollRules.fallbackBody($0) }
    }

    //isaCloud: the fallback body of a closing message
    @objc(fallbackBodyForClosedJSON:)
    public static func fallbackBody(forClosedJSON json: String) -> String? {
        return PollRules.decodeClosed(json).map { PollRules.closedFallbackBody($0) }
    }

    //isaCloud: YES when the closing matches the poll: same title and every emoji of the tally is an option of the poll
    @objc(isClosedJSON:matchingPollJSON:)
    public static func isClosed(json closedJSON: String, matchingPollJSON pollJSON: String) -> Bool {
        guard let closed = PollRules.decodeClosed(closedJSON), let poll = PollRules.decode(pollJSON) else {
            return false
        }
        return PollRules.closed(closed, matches: poll)
    }

    //isaCloud: the new set of reactions after tapping the option `emoji`, or nil if it is no option (see PollRules.toggledReactions)
    @objc(toggledReactionsForPollJSON:current:option:)
    public static func toggledReactions(forPollJSON pollJSON: String, current: [String], option emoji: String) -> [String]? {
        guard let poll = PollRules.decode(pollJSON) else {
            return nil
        }
        return PollRules.toggledReactions(poll, current: current, optionEmoji: emoji)
    }

    //isaCloud: YES while the poll takes votes (see PollRules.canVote)
    @objc(canVotePollJSON:)
    public static func canVote(pollJSON: String) -> Bool {
        guard let poll = PollRules.decode(pollJSON) else {
            return false
        }
        return PollRules.canVote(poll)
    }

    private static func string(_ value: Any?) -> String? {
        return value as? String
    }

    private static func bool(_ value: Any?) -> Bool {
        if let bool = value as? Bool {
            return bool
        }
        return (value as? NSNumber)?.boolValue ?? false
    }
}
