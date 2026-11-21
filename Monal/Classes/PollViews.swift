//
//  PollViews.swift
//  Monal
//
//  isaCloud: the poll card of a group or channel (urn:fluux:poll:0) and the sheet that creates a poll. The card is drawn by ChatView's
//  messageBuilder, like GifMessageBubble: it is a bubble with the sender's avatar, the reactions under it and the time below.
//  The rules (what is shown, what can be tapped, the footer) are in PollCardRules.swift.
//

import SwiftUI
import ExyteChat

/// isaCloud: the poll card in the chat. Tapping an option line votes (only when `model.isVotable`), a long press opens the message menu.
struct PollMessageBubble: View {
    let model: PollCardModel
    @ObservedObject var message: ExyteChat.Message
    @ObservedObject var user: ExyteChat.User
    let isCurrentUser: Bool
    /// isaCloud: groups and channels: the name of the sender is shown inside the card
    var showSender: Bool = false
    /// isaCloud: the avatar is drawn beside the last message of a sender's group, an empty space beside the others
    var isLastOfSenderGroup: Bool = true
    /// isaCloud: opens the message menu (reactions, reply, copy...)
    var showContextMenu: () -> Void = {}
    /// isaCloud: called when the reactions are tapped, to show who reacted with what
    var onReactionsTap: () -> Void = {}
    /// isaCloud: called with the emoji of the option tapped (the chat sends the new set of reactions)
    var onVote: (String) -> Void = { _ in }
    @Environment(\.chatTheme) private var theme

    private static let cardWidth: CGFloat = 260
    private static let avatarSize: CGFloat = 32
    private static let statusSize: CGFloat = 16

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isCurrentUser {
                avatar
            }
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 2) {
                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 2) {
                    card
                    if !reactionItems.isEmpty {
                        GifReactionsFooter(reactions: reactionItems, width: Self.cardWidth, onTap: onReactionsTap)
                    }
                }
                //isaCloud: the card and its reactions are the bubble for the long press; the time below, the avatar and the status are not
                .reportsMessageBubbleFrame()
                timeView
            }
            if isCurrentUser, let status = message.status {
                statusIcon(status)
                    .frame(width: Self.statusSize, height: Self.statusSize)
                    .padding(.bottom, 1)
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    /// isaCloud: the bubble: the sender (groups), the title, the description, the options and the footer
    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showSender && !isCurrentUser {
                Text(user.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }
            Text(model.title)
                .font(.body.weight(.bold))
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
            if let description = model.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.showsMultipleHint {
                Text(NSLocalizedString("Select one or more options", comment: "poll card: the poll accepts more than one option"))
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                    optionView(row)
                }
            }
            .padding(.top, 2)
            Text(PollCardText.footer(model.footer))
                .font(.caption)
                .foregroundStyle(secondaryTextColor)
        }
        .padding(12)
        .frame(width: Self.cardWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(backgroundColor))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onLongPressGesture(minimumDuration: 0.15) {     //isaCloud: same time as the other messages (ExyteChat fork, UIList.swift)
            showContextMenu()
        }
    }

    /// isaCloud: one option: a button when it votes, a plain line otherwise (not dimmed, the footer says why)
    @ViewBuilder
    private func optionView(_ row: PollCardRow) -> some View {
        let line = PollOptionLine(row: row, textColor: textColor, secondaryColor: secondaryTextColor, barColor: barColor, trackColor: trackColor)
        if model.isVotable {
            Button {
                onVote(row.emoji)
            } label: {
                line
            }
            .buttonStyle(.plain)
        } else {
            line
        }
    }

    private var isOwnBubble: Bool { isCurrentUser }
    private var backgroundColor: Color { isOwnBubble ? theme.colors.messageMyBG : theme.colors.messageFriendBG }
    private var textColor: Color { isOwnBubble ? theme.colors.messageMyText : .primary }
    private var secondaryTextColor: Color { isOwnBubble ? theme.colors.messageMyText.opacity(0.85) : .secondary }
    /// isaCloud: the bars: the brand pink in a bubble of others, the text colour of our own bubble (it may be pink too)
    private var barColor: Color { isOwnBubble ? IsaCloudBubbleColors.mineText : Color("isaCloudPink") }
    private var trackColor: Color { barColor.opacity(0.25) }

    /// isaCloud: each emoji reaction with whether the current user sent it (the options of the poll are not among them, see ChatViewMessage.reactions)
    private var reactionItems: [(emoji: String, isMine: Bool)] {
        return message.reactions.compactMap { reaction in
            if case .emoji(let emoji) = reaction.type {
                return (emoji: emoji, isMine: reaction.user.isCurrentUser)
            }
            return nil
        }
    }

    /// isaCloud: the time of the message, with the lock when it was encrypted (OMEMO), like under the other messages
    private var timeView: some View {
        HStack(spacing: 4) {
            if message.encrypted {
                Image(systemName: "lock.fill")
            }
            Text(message.createdAt, style: .time)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    /// isaCloud: the same icons as the other messages of ours (see GifMessageBubble)
    @ViewBuilder
    private func statusIcon(_ status: ExyteChat.Message.Status) -> some View {
        switch status {
        case .sending:
            theme.images.message.sending
                .resizable()
                .foregroundColor(theme.colors.statusGray)
        case .sent:
            theme.images.message.sent
                .resizable()
                .foregroundColor(theme.colors.messageMyBG)
        case .received:
            theme.images.message.received
                .resizable()
                .foregroundColor(theme.colors.messageMyBG)
        case .readBy:
            theme.images.message.read
                .resizable()
                .foregroundColor(theme.colors.messageMyBG)
        case .error:
            theme.images.message.error
                .resizable()
                .foregroundColor(theme.colors.statusError)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if isLastOfSenderGroup, let image = user.avatarImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .clipShape(Circle())
        } else {
            Color.clear.frame(width: Self.avatarSize, height: Self.avatarSize)
        }
    }
}

/// isaCloud: one option of the card: the emoji, the label, the mark of our vote, the count and the bar. Not dimmed when it cannot be tapped
struct PollOptionLine: View {
    let row: PollCardRow
    let textColor: Color
    let secondaryColor: Color
    let barColor: Color
    let trackColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(row.emoji)
                    .font(.body)
                Text(row.label)
                    .font(.subheadline)
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if row.isMine {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(textColor)
                }
                if row.showsResults {
                    Text("\(row.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(textColor)
                }
            }
            if row.showsResults {
                bar
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityAddTraits(row.isMine ? .isSelected : [])
    }

    private var bar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                Capsule()
                    .fill(barColor)
                    .frame(width: geometry.size.width * CGFloat(max(0, row.fraction)))
            }
        }
        .frame(height: 6)
    }

    private var accessibilityText: String {
        var parts = ["\(row.emoji) \(row.label)"]
        if row.showsResults {
            parts.append(PollCardText.votes(row.count))
        }
        if row.isMine {
            parts.append(NSLocalizedString("Your vote", comment: "poll card: the option the user voted for (VoiceOver)"))
        }
        return parts.joined(separator: ", ")
    }
}

/// isaCloud: the texts of the poll card (the footer and the number of votes), in the language of the app
enum PollCardText {
    static func votes(_ count: Int) -> String {
        if count == 1 {
            return NSLocalizedString("1 vote", comment: "poll card: one vote")
        }
        return String(format: NSLocalizedString("%d votes", comment: "poll card: the number of votes"), count)
    }

    static func footer(_ footer: PollFooter) -> String {
        switch footer {
            case .finalResult(let votes):
                return withVotes(NSLocalizedString("Final result", comment: "poll card footer: the frozen result of a closed poll"), votes)
            case .closed(let votes):
                return withVotes(NSLocalizedString("Poll closed", comment: "poll card footer: the creator closed the poll"), votes)
            case .expired:
                return NSLocalizedString("Poll closed", comment: "poll card footer: the deadline of the poll is past")
            case .voteToSee:
                return NSLocalizedString("Vote to see the results", comment: "poll card footer: the results are hidden until the user votes")
            case .noVotes:
                return NSLocalizedString("No votes yet", comment: "poll card footer: nobody voted")
            case .votes(let count):
                return votes(count)
        }
    }

    /// isaCloud: "Final result · 3 votes": the number is left out when there is none (a zero is not written as a count)
    private static func withVotes(_ base: String, _ votes: Int?) -> String {
        guard let votes = votes, votes > 0 else {
            return base
        }
        return "\(base) · \(self.votes(votes))"
    }
}

/// isaCloud: the sheet that creates a poll: the question, an optional description, 2 to 9 options (the emojis are fixed by position),
/// multiple choice and hidden results. The poll is sent as the JSON of PollDefinition (ISACloudPolls.pollJSON(fromFields:))
struct PollCreateView: View {
    /// isaCloud: the JSON of the poll, when it is valid
    var onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var pollDescription = ""
    @State private var labels: [String] = ["", ""]
    @State private var allowMultiple = false
    @State private var hideResults = false

    var body: some View {
        NavigationStack {
            Form {
                questionSection
                optionsSection
                settingsSection
            }
            .navigationTitle(NSLocalizedString("New poll", comment: "the sheet that creates a poll"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "poll sheet: closes without creating the poll")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Create", comment: "poll sheet: creates and sends the poll")) {
                        create()
                    }
                    .disabled(!PollCardRules.canCreate(question: question, labels: labels))
                }
            }
        }
    }

    private var questionSection: some View {
        Section {
            TextField(NSLocalizedString("Question", comment: "poll sheet: the question of the poll (required)"), text: $question)
            TextField(NSLocalizedString("Description (optional)", comment: "poll sheet: an optional text under the question"), text: $pollDescription, axis: .vertical)
                .lineLimit(1...4)
        }
    }

    private var optionsSection: some View {
        Section {
            ForEach(labels.indices, id: \.self) { index in
                optionRow(index)
            }
            if labels.count < PollCardRules.maximumOptions {
                Button {
                    labels.append("")
                } label: {
                    Label(NSLocalizedString("Add option", comment: "poll sheet: a new empty option"), systemImage: "plus.circle")
                }
            }
        } header: {
            Text(NSLocalizedString("Options", comment: "poll sheet: the options section"))
        }
    }

    private func optionRow(_ index: Int) -> some View {
        HStack(spacing: 8) {
            Text(PollCardRules.displayedKeycap(forRow: index, labels: labels))
            TextField(NSLocalizedString("Option", comment: "poll sheet: placeholder of an option"), text: $labels[index])
            if labels.count > PollCardRules.minimumOptions {
                Button(role: .destructive) {
                    labels.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(NSLocalizedString("Remove option", comment: "poll sheet: removes the option of this line")))
            }
        }
    }

    private var settingsSection: some View {
        Section {
            Toggle(NSLocalizedString("Multiple choice", comment: "poll sheet: the voters may choose more than one option"), isOn: $allowMultiple)
                .tint(Color("isaCloudPink"))
            Toggle(NSLocalizedString("Hide results until you vote", comment: "poll sheet: the counts stay hidden until the voter votes"), isOn: $hideResults)
                .tint(Color("isaCloudPink"))
        }
    }

    /// isaCloud: builds the poll from the fields and hands its JSON over; the sheet closes after that
    private func create() {
        let trimmedDescription = pollDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let options: [[String: Any]] = PollCardRules.options(fromLabels: labels).map { ["emoji": $0.emoji, "label": $0.label] }
        let fields: [String: Any] = [
            "title": question.trimmingCharacters(in: .whitespacesAndNewlines),
            "description": trimmedDescription,
            "allowMultiple": allowMultiple,
            "hideResults": hideResults,
            "options": options,
        ]
        guard let pollJSON = ISACloudPolls.pollJSON(fromFields: fields) else {
            return
        }
        onCreate(pollJSON)
        dismiss()
    }
}
