//
//  PollCardRulesTests.swift
//  MonalXMPPUnitTests
//
//  isaCloud: the rules of the poll card (PollCardRules.swift): the options of a new poll, what is a chip, what can be tapped, what can be
//  created and closed, the counts and the footer of the card. See docs/implementacao-enquetes-ios.md, sections 5 and 6.
//

import Foundation
import Testing
import monalxmpp

struct PollCardRulesTests {

    //isaCloud: the keycaps of the default options: 0031 FE0F 20E3 and 0032 FE0F 20E3, as the protocol wants them
    private let one = "1\u{FE0F}\u{20E3}"
    private let two = "2\u{FE0F}\u{20E3}"
    private let thumbsUp = "\u{1F44D}"

    private func poll(multiple: Bool = false, hide: Bool = false, deadline: Int64? = nil) -> PollDefinition {
        return PollDefinition(
            title: "Almoço?",
            description: nil,
            allowMultiple: multiple,
            hideResults: hide,
            deadline: deadline,
            options: [PollOption(emoji: one, label: "Pizza"), PollOption(emoji: two, label: "Sushi")]
        )
    }

    //MARK: creation

    @Test("the options of a new poll are numbered by position, the empty ones are dropped")
    func optionsNumberedByPosition() {
        let options = PollCardRules.options(fromLabels: ["Pizza", "   ", "Sushi"])
        #expect(options == [PollOption(emoji: one, label: "Pizza"), PollOption(emoji: two, label: "Sushi")])
    }

    @Test("a new poll takes at most nine options")
    func optionsLimit() {
        let labels = (1...11).map { "Opção \($0)" }
        let options = PollCardRules.options(fromLabels: labels)
        #expect(options.count == 9)
        #expect(options.last?.emoji == "9\u{FE0F}\u{20E3}")
    }

    @Test("the send button needs a question and two filled options")
    func canCreateRules() {
        #expect(PollCardRules.canCreate(question: "", labels: ["a", "b"]) == false)
        #expect(PollCardRules.canCreate(question: "   ", labels: ["a", "b"]) == false)
        #expect(PollCardRules.canCreate(question: "Q", labels: ["a", ""]) == false)
        #expect(PollCardRules.canCreate(question: "Q", labels: ["a", "b"]) == true)
    }

    @Test("the emoji of a row in the creation is the number it gets among the filled rows")
    func displayedKeycapSkipsEmptyRows() {
        let labels = ["", "A", "B"]
        #expect(PollCardRules.displayedKeycap(forRow: 1, labels: labels) == one)
        #expect(PollCardRules.displayedKeycap(forRow: 2, labels: labels) == two)
    }

    //MARK: chips

    @Test("the reactions that are options of the poll are no chips, 👍 stays")
    func chipsWithoutOptions() {
        #expect(PollCardRules.reactionsWithoutOptions([one, thumbsUp], optionEmojis: [one, two]) == [thumbsUp])
    }

    @Test("an option is matched without the variation selector (the legacy keycap 0031 20E3)")
    func optionMatchIgnoresVariationSelector() {
        #expect(PollCardRules.isOptionEmoji("1\u{20E3}", of: [one, two]) == true)
        #expect(PollCardRules.isOptionEmoji(thumbsUp, of: [one, two]) == false)
    }

    @Test("the option emojis come from the poll, or from the tally of a closing")
    func optionEmojisSources() {
        #expect(PollCardRules.optionEmojis(pollJSON: PollRules.encode(poll()), closingJSON: nil) == [one, two])
        let closing = PollClosedInfo(messageId: "m", title: "Almoço?", description: nil, tally: [PollTallyEntry(emoji: two, label: "Sushi", count: 1, voters: [])])
        #expect(PollCardRules.optionEmojis(pollJSON: nil, closingJSON: PollRules.encode(closing)) == [two])
        #expect(PollCardRules.optionEmojis(pollJSON: nil, closingJSON: nil).isEmpty)
    }

    //MARK: what can be tapped, edited and closed

    @Test("the card is shown only in a group or channel, for a poll or for its closing")
    func showsCardRules() {
        #expect(PollCardRules.showsCard(isMuc: false, hasPoll: true, hasClosing: false) == false)
        #expect(PollCardRules.showsCard(isMuc: true, hasPoll: false, hasClosing: false) == false)
        #expect(PollCardRules.showsCard(isMuc: true, hasPoll: true, hasClosing: false) == true)
        #expect(PollCardRules.showsCard(isMuc: true, hasPoll: false, hasClosing: true) == true)
    }

    @Test("a closing whose poll is in the chat is not drawn, its tally is in the poll")
    func hidesClosingRules() {
        #expect(PollCardRules.hidesClosing(hasPoll: false, hasClosing: true, pollIsInChat: true) == true)
        #expect(PollCardRules.hidesClosing(hasPoll: false, hasClosing: true, pollIsInChat: false) == false)
        #expect(PollCardRules.hidesClosing(hasPoll: true, hasClosing: true, pollIsInChat: true) == false)
        #expect(PollCardRules.hidesClosing(hasPoll: false, hasClosing: false, pollIsInChat: true) == false)
    }

    @Test("votes need a group or channel with a stanza id and occupant-id, and a message that is not on its way")
    func votesAllowedRules() {
        #expect(PollCardRules.votesAllowed(isMuc: true, hasStanzaId: true, roomHasOccupantId: true, isPending: false) == true)
        #expect(PollCardRules.votesAllowed(isMuc: true, hasStanzaId: false, roomHasOccupantId: true, isPending: false) == false)
        #expect(PollCardRules.votesAllowed(isMuc: true, hasStanzaId: true, roomHasOccupantId: false, isPending: false) == false)
        #expect(PollCardRules.votesAllowed(isMuc: true, hasStanzaId: true, roomHasOccupantId: true, isPending: true) == false)
        #expect(PollCardRules.votesAllowed(isMuc: false, hasStanzaId: true, roomHasOccupantId: true, isPending: false) == false)
    }

    @Test("a poll or its closing is not edited")
    func editRules() {
        #expect(PollCardRules.allowsEdit(hasPoll: true, hasClosing: false) == false)
        #expect(PollCardRules.allowsEdit(hasPoll: false, hasClosing: true) == false)
        #expect(PollCardRules.allowsEdit(hasPoll: false, hasClosing: false) == true)
    }

    @Test("only the creator closes an open poll, in a group or channel with occupant-id")
    func closeRules() {
        #expect(PollCardRules.canClose(isOwn: true, hasPoll: true, isFrozen: false, isEnded: false, isMuc: true, roomHasOccupantId: true, isPending: false) == true)
        #expect(PollCardRules.canClose(isOwn: false, hasPoll: true, isFrozen: false, isEnded: false, isMuc: true, roomHasOccupantId: true, isPending: false) == false)
        #expect(PollCardRules.canClose(isOwn: true, hasPoll: true, isFrozen: true, isEnded: false, isMuc: true, roomHasOccupantId: true, isPending: false) == false)
        #expect(PollCardRules.canClose(isOwn: true, hasPoll: true, isFrozen: false, isEnded: true, isMuc: true, roomHasOccupantId: true, isPending: false) == false)
        #expect(PollCardRules.canClose(isOwn: true, hasPoll: true, isFrozen: false, isEnded: false, isMuc: false, roomHasOccupantId: true, isPending: false) == false)
        #expect(PollCardRules.canClose(isOwn: true, hasPoll: true, isFrozen: false, isEnded: false, isMuc: true, roomHasOccupantId: false, isPending: false) == false)
        #expect(PollCardRules.canClose(isOwn: true, hasPoll: true, isFrozen: false, isEnded: false, isMuc: true, roomHasOccupantId: true, isPending: true) == false)
    }

    //MARK: the card of an open poll

    @Test("the counts of the open poll and the mark of our own vote")
    func openPollCounts() {
        let voters = [
            PollVoter(id: "a", nick: "Ana", reactions: [one]),
            PollVoter(id: "b", nick: "Bia", reactions: [two]),
        ]
        let card = PollCardRules.card(poll: poll(), closing: nil, endedAt: false, voters: voters, ownReactions: [one], votesAllowed: true)
        #expect(card?.rows.map { $0.count } == [1, 1])
        #expect(card?.rows.map { $0.isMine } == [true, false])
        #expect(card?.footer == .votes(2))
        #expect(card?.isVotable == true)
        #expect(card?.showsMultipleHint == false)
    }

    @Test("a voter of a single choice counts only on the last option he reacted with (legacy 1️⃣ and 2️⃣)")
    func singleChoiceLegacyVoter() {
        let voters = [PollVoter(id: "a", nick: "Ana", reactions: [one, two])]
        let card = PollCardRules.card(poll: poll(), closing: nil, endedAt: false, voters: voters, ownReactions: [], votesAllowed: true)
        #expect(card?.rows.map { $0.count } == [0, 1])
        #expect(card?.footer == .votes(1))
    }

    @Test("a hidden result shows no count and no bar until the user votes")
    func hiddenResults() {
        let voters = [PollVoter(id: "a", nick: "Ana", reactions: [one])]
        let beforeVoting = PollCardRules.card(poll: poll(hide: true), closing: nil, endedAt: false, voters: voters, ownReactions: [], votesAllowed: true)
        #expect(beforeVoting?.rows.allSatisfy { !$0.showsResults && $0.fraction == 0 } == true)
        #expect(beforeVoting?.footer == .voteToSee)

        let afterVoting = PollCardRules.card(poll: poll(hide: true), closing: nil, endedAt: false, voters: voters, ownReactions: [one], votesAllowed: true)
        #expect(afterVoting?.rows.allSatisfy { $0.showsResults } == true)
        #expect(afterVoting?.footer == .votes(1))
    }

    @Test("with no votes the footer says so, and a multiple choice poll asks for more than one option")
    func noVotesAndMultipleHint() {
        let card = PollCardRules.card(poll: poll(multiple: true), closing: nil, endedAt: false, voters: [], ownReactions: [], votesAllowed: true)
        #expect(card?.footer == .noVotes)
        #expect(card?.showsMultipleHint == true)
    }

    @Test("a poll past its deadline is expired, takes no votes and says so")
    func expiredPoll() {
        let card = PollCardRules.card(poll: poll(deadline: 1_000_000), closing: nil, endedAt: false, voters: [], ownReactions: [], votesAllowed: true)
        #expect(card?.footer == .expired)
        #expect(card?.isVotable == false)
    }

    @Test("a poll closed by its creator takes no votes and keeps the count of the votes")
    func closedOriginal() {
        let voters = [PollVoter(id: "a", nick: "Ana", reactions: [one]), PollVoter(id: "b", nick: "Bia", reactions: [one])]
        let card = PollCardRules.card(poll: poll(), closing: nil, endedAt: true, voters: voters, ownReactions: [], votesAllowed: true)
        #expect(card?.footer == .closed(votes: 2))
        #expect(card?.isVotable == false)
    }

    @Test("a closed hidden poll does not show its count in the footer")
    func closedHiddenOriginal() {
        let voters = [PollVoter(id: "a", nick: "Ana", reactions: [one])]
        let card = PollCardRules.card(poll: poll(hide: true), closing: nil, endedAt: true, voters: voters, ownReactions: [], votesAllowed: true)
        #expect(card?.footer == .closed(votes: nil))
    }

    @Test("no poll and no closing: no card")
    func noCard() {
        #expect(PollCardRules.card(poll: nil, closing: nil, endedAt: false, voters: [], ownReactions: [], votesAllowed: true) == nil)
    }

    //MARK: the card of a closing (frozen)

    @Test("the frozen tally of a closing is drawn as it was sent: the voters are the distinct nicks")
    func frozenClosing() {
        let closing = PollClosedInfo(
            messageId: "m",
            title: "Almoço?",
            description: nil,
            tally: [
                PollTallyEntry(emoji: one, label: "Pizza", count: 2, voters: ["Ana", "Bia"]),
                PollTallyEntry(emoji: two, label: "Sushi", count: 0, voters: []),
            ]
        )
        let card = PollCardRules.card(poll: nil, closing: closing, endedAt: false, voters: [], ownReactions: [], votesAllowed: true)
        #expect(card?.footer == .finalResult(votes: 2))
        #expect(card?.rows.map { $0.count } == [2, 0])
        #expect(card?.rows.first?.fraction == 1)
        #expect(card?.isVotable == false)
        #expect(card?.rows.allSatisfy { $0.showsResults } == true)
    }

    @Test("a frozen closing with no votes says only 'Final result'")
    func frozenClosingWithoutVotes() {
        let closing = PollClosedInfo(messageId: "m", title: "Almoço?", description: nil, tally: [PollTallyEntry(emoji: one, label: "Pizza", count: 0, voters: [])])
        let card = PollCardRules.card(poll: nil, closing: closing, endedAt: false, voters: [], ownReactions: [], votesAllowed: true)
        #expect(card?.footer == .finalResult(votes: nil))
    }

    @Test("the original of a closed poll shows its frozen tally with the footer 'closed', and takes no votes")
    func closedOriginalWithTally() {
        let closing = PollClosedInfo(
            messageId: "m",
            title: "Almoço?",
            description: nil,
            tally: [PollTallyEntry(emoji: one, label: "Pizza", count: 2, voters: ["Ana", "Bia"])]
        )
        let card = PollCardRules.card(poll: poll(), closing: closing, endedAt: true, voters: [], ownReactions: [one], votesAllowed: true)
        #expect(card?.footer == .closed(votes: 2))
        #expect(card?.rows.map { $0.isMine } == [true])
        #expect(card?.rows.map { $0.count } == [2])
        #expect(card?.isVotable == false)
    }

    @Test("a closing without its poll in our database keeps the footer 'final result'")
    func closingOnlyKeepsFinalResult() {
        let closing = PollClosedInfo(messageId: "m", title: "Almoço?", description: nil, tally: [PollTallyEntry(emoji: one, label: "Pizza", count: 1, voters: ["Ana"])])
        let card = PollCardRules.card(poll: nil, closing: closing, endedAt: false, voters: [], ownReactions: [], votesAllowed: true)
        #expect(card?.footer == .finalResult(votes: 1))
    }

    @Test("the voters of a closing are the biggest of the distinct nicks and the counts (the nicks may be unknown)")
    func closedTotalCounts() {
        let closing = PollClosedInfo(messageId: "m", title: "Almoço?", description: nil, tally: [PollTallyEntry(emoji: one, label: "Pizza", count: 3, voters: [])])
        #expect(PollCardRules.closedTotal(closing) == 3)
    }
}
