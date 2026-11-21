//
//  PollCardRules.swift
//  Monal
//
//  isaCloud: the rules of the poll card in a group or channel: what the card shows, which lines can be tapped, the footer, the options that
//  are not chips, what can be created and closed. No UI here (the card is in PollViews.swift), no XMPP (see Polls.swift for the protocol).
//  See docs/implementacao-enquetes-ios.md (sections 5 and 6) and docs/decisoes-enquetes-fluux.md (sections 6, 8, 10 and 11).
//

import Foundation
import monalxmpp

//isaCloud: one line of the card: the option, its count and its bar, and whether it is the user's own vote
struct PollCardRow: Equatable {
    let emoji: String
    let label: String
    let count: Int
    //isaCloud: 0...1, the part of the bar that is filled; 0 while the results are hidden
    let fraction: Double
    let isMine: Bool
    //isaCloud: the count and the bar are drawn only when the results are visible
    let showsResults: Bool
}

//isaCloud: what the footer of the card says (the text is in PollViews.swift). The votes are nil when they are not to be shown
enum PollFooter: Equatable {
    //isaCloud: the frozen tally of a closing message
    case finalResult(votes: Int?)
    //isaCloud: closed by its creator (the original message of the poll)
    case closed(votes: Int?)
    //isaCloud: the deadline is past
    case expired
    //isaCloud: hide-results and the user has not voted yet
    case voteToSee
    case noVotes
    case votes(Int)
}

//isaCloud: everything the card draws
struct PollCardModel: Equatable {
    let title: String
    let description: String?
    //isaCloud: "Select one or more options" (multiple choice, while the poll is open)
    let showsMultipleHint: Bool
    let rows: [PollCardRow]
    let footer: PollFooter
    //isaCloud: the lines are buttons that vote
    let isVotable: Bool
}

enum PollCardRules {
    //isaCloud: the creation takes 2 to 9 options (the emojis are the keycaps 1️⃣…9️⃣, by position)
    static let minimumOptions = 2
    static let maximumOptions = 9

    //isaCloud: the keycap of a position: 1️⃣ is 0031 FE0F 20E3 (docs 2.1). The emoji of an option is never built from this key when voting
    static func keycap(_ position: Int) -> String {
        return "\(position)\u{FE0F}\u{20E3}"
    }

    //isaCloud: the options of a new poll: the labels without spaces, empty ones dropped, the emojis numbered again by position
    static func options(fromLabels labels: [String]) -> [PollOption] {
        let filled = labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(maximumOptions)
        return filled.enumerated().map { index, label in
            PollOption(emoji: keycap(index + 1), label: label)
        }
    }

    //isaCloud: the send button of the creation: a question and at least two filled options
    static func canCreate(question: String, labels: [String]) -> Bool {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedQuestion.isEmpty && options(fromLabels: labels).count >= minimumOptions
    }

    //isaCloud: the emoji shown in front of a row of the creation: the number of the row among the filled ones (the one it gets when sent)
    static func displayedKeycap(forRow index: Int, labels: [String]) -> String {
        let filledBefore = labels.prefix(index).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        return keycap(filledBefore + 1)
    }

    //isaCloud: the emojis of the options of a poll message (its definition, or the tally of a closing), empty when there is none
    static func optionEmojis(pollJSON: String?, closingJSON: String?) -> [String] {
        if let pollJSON = pollJSON, let poll = PollRules.decode(pollJSON) {
            return poll.options.map { $0.emoji }
        }
        if let closingJSON = closingJSON, let closed = PollRules.decodeClosed(closingJSON) {
            return closed.tally.map { $0.emoji }
        }
        return []
    }

    //isaCloud: YES when the emoji is an option of the poll, compared by its key (the variation selector FE0F is left out)
    static func isOptionEmoji(_ emoji: String, of optionEmojis: [String]) -> Bool {
        let key = PollRules.key(emoji)
        return optionEmojis.contains { PollRules.key($0) == key }
    }

    //isaCloud: the reactions shown as chips under a message, without the options of its poll (the card shows those); 👍 and the others stay
    static func reactionsWithoutOptions(_ reactions: [String], optionEmojis: [String]) -> [String] {
        return reactions.filter { !isOptionEmoji($0, of: optionEmojis) }
    }

    //isaCloud: a line of the card can be tapped to vote only in a group or channel where the message has a stanza id and the room
    //announces occupant-id (the same condition as reacting, see ChatView canReactTo), and the message is not on its way
    static func votesAllowed(isMuc: Bool, hasStanzaId: Bool, roomHasOccupantId: Bool, isPending: Bool) -> Bool {
        return isMuc && hasStanzaId && roomHasOccupantId && !isPending
    }

    //isaCloud: the card is shown in a group or channel, for a poll or for its closing
    static func showsCard(isMuc: Bool, hasPoll: Bool, hasClosing: Bool) -> Bool {
        return isMuc && (hasPoll || hasClosing)
    }

    //isaCloud: a poll (or its closing) is not edited: the edit would change the fallback text and leave the <poll> out of date
    static func allowsEdit(hasPoll: Bool, hasClosing: Bool) -> Bool {
        return !hasPoll && !hasClosing
    }

    //isaCloud: "Close poll" is offered on our own poll while it is open, in a group or channel with occupant-id, and not on its way
    static func canClose(isOwn: Bool, hasPoll: Bool, isFrozen: Bool, isEnded: Bool, isMuc: Bool, roomHasOccupantId: Bool, isPending: Bool) -> Bool {
        return isOwn && hasPoll && !isFrozen && !isEnded && isMuc && roomHasOccupantId && !isPending
    }

    //isaCloud: the card of a poll, or of its closing (frozen, its tally as it was sent). The live tally counts the reactions of the voters
    //(voters: each one with its reactions on the poll message). Own reactions are the reactions of the user. nil when there is nothing to draw
    static func card(poll: PollDefinition?, closing: PollClosedInfo?, endedAt: Bool, voters: [PollVoter], ownReactions: [String], votesAllowed: Bool, now: Date = Date()) -> PollCardModel? {
        if let closing = closing {
            return frozenCard(closing)
        }
        guard let poll = poll else {
            return nil
        }
        let ownKeys = Set(ownReactions.map { PollRules.key($0) })
        let tally = PollRules.tally(poll, voters: voters)
        let total = tally.totalVoters
        let votedAlready = poll.options.contains { ownKeys.contains(PollRules.key($0.emoji)) }
        let hidden = poll.hideResults && !votedAlready
        let expired = !PollRules.canVote(poll, now: now)
        let rows = poll.options.indices.map { index -> PollCardRow in
            let option = poll.options[index]
            let count = tally.entries[index].count
            return PollCardRow(
                emoji: option.emoji,
                label: option.label,
                count: count,
                fraction: hidden ? 0 : share(of: count, outOf: total),
                isMine: ownKeys.contains(PollRules.key(option.emoji)),
                showsResults: !hidden
            )
        }
        let footer: PollFooter
        if endedAt {
            footer = .closed(votes: hidden || total == 0 ? nil : total)
        } else if expired {
            footer = .expired
        } else if hidden {
            footer = .voteToSee
        } else if total == 0 {
            footer = .noVotes
        } else {
            footer = .votes(total)
        }
        return PollCardModel(
            title: poll.title,
            description: poll.description,
            showsMultipleHint: poll.allowMultiple && !endedAt,
            rows: rows,
            footer: footer,
            isVotable: votesAllowed && !endedAt && !expired
        )
    }

    //isaCloud: the number of voters of a closing: the distinct nicks of its tally, or the biggest count when the nicks are unknown
    static func closedTotal(_ closing: PollClosedInfo) -> Int {
        let nicks = Set(closing.tally.flatMap { $0.voters })
        let biggest = closing.tally.map { $0.count }.max() ?? 0
        return max(nicks.count, biggest)
    }

    private static func frozenCard(_ closing: PollClosedInfo) -> PollCardModel {
        let total = closedTotal(closing)
        let rows = closing.tally.map { entry in
            PollCardRow(emoji: entry.emoji, label: entry.label, count: entry.count, fraction: share(of: entry.count, outOf: total), isMine: false, showsResults: true)
        }
        return PollCardModel(
            title: closing.title,
            description: closing.description,
            showsMultipleHint: false,
            rows: rows,
            footer: .finalResult(votes: total > 0 ? total : nil),
            isVotable: false
        )
    }

    private static func share(of count: Int, outOf total: Int) -> Double {
        guard total > 0 else {
            return 0
        }
        return min(1, Double(count) / Double(total))
    }
}
