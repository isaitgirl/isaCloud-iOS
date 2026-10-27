//
//  MessageSearchResults.swift
//  Monal
//
//  isaCloud: the messages found by the search bar of the home screen ("search in the conversations"): the model that looks them up
//  (outside of the main thread, a moment after the person stops typing, one page at a time) and the list that shows them.
//

import SwiftUI

/// one message found: who it is with, who wrote it, the piece of the text around the words, and when
struct MessageSearchHit: Identifiable {
    let id: Int                     // message_history_id
    let contact: MLContact          // the conversation the message belongs to
    let sender: String?             // who wrote it, shown before the snippet (nil in a conversation with one person)
    let snippet: AttributedString
    let date: Date
    let accountJid: String?         // only with more than one account enabled
}

final class MessageSearchModel: ObservableObject {
    static let pageSize = 30
    /// below this the search finds nearly every message: it does not run
    static let minLength = 2

    @Published private(set) var hits: [MessageSearchHit] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasMore = false
    private(set) var query = ""

    /// counts the searches: the answer of a search that is not the last one is thrown away
    private var generation = 0
    private var pending: DispatchWorkItem?

    func search(_ rawQuery: String, immediately: Bool = false) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        pending?.cancel()
        generation += 1
        self.query = query
        guard query.count >= MessageSearchModel.minLength else {
            hits = []
            hasMore = false
            isSearching = false
            return
        }
        isSearching = true
        let current = generation
        let item = DispatchWorkItem { [weak self] in
            let page = MessageSearchModel.fetch(query: query, offset: 0)
            DispatchQueue.main.async {
                guard let self = self, current == self.generation else {
                    return
                }
                self.hits = page.hits
                self.hasMore = page.hasMore
                self.isSearching = false
            }
        }
        pending = item
        //a moment after the last key, so typing does not run a search per letter
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + (immediately ? 0 : 0.25), execute: item)
    }

    func loadMore() {
        guard hasMore, !isSearching else {
            return
        }
        isSearching = true
        let current = generation
        let query = self.query
        let offset = hits.count
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let page = MessageSearchModel.fetch(query: query, offset: offset)
            DispatchQueue.main.async {
                guard let self = self, current == self.generation else {
                    return
                }
                self.hits.append(contentsOf: page.hits)
                self.hasMore = page.hasMore
                self.isSearching = false
            }
        }
    }

    /// runs on a background thread (the DataLayer gives every thread its own database connection)
    private static func fetch(query: String, offset: Int) -> (hits: [MessageSearchHit], hasMore: Bool) {
        //one more than a page, to know if there is another page
        let ids = (DataLayer.sharedInstance().searchMessageHistoryIds(forQuery: query, limit: UInt(pageSize + 1), offset: UInt(offset))) as [NSNumber]
        var hits: [MessageSearchHit] = []
        for historyId in ids.prefix(pageSize) {
            let message = MLMessage.createMessage(fromHistoryID: historyId)
            let contact = MLContact.createContact(fromJid: message.buddyName, andAccountID: message.accountID)
            var sender: String? = nil
            if !message.inbound {
                sender = NSLocalizedString("You", comment: "who wrote a message found by the search: the person using the app")
            } else if message.isMuc {
                sender = message.contactDisplayName
            }
            hits.append(MessageSearchHit(
                id: historyId.intValue,
                contact: contact,
                sender: sender,
                snippet: MessageSearchSnippet.make(text: message.messageText, query: query),
                date: message.timestamp,
                accountJid: HelperTools.accountJidToShow(forAccountID: message.accountID)
            ))
        }
        return (hits, ids.count > pageSize)
    }
}

struct MessageSearchResultsList: View {
    @ObservedObject var model: MessageSearchModel
    let onSelect: (MLContact, NSNumber) -> Void
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 40

    var body: some View {
        if model.query.count < MessageSearchModel.minLength {
            Text("Type at least two letters to search in the messages.")
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if model.hits.isEmpty && !model.isSearching {
            ContentUnavailableShimView.search(text: model.query)
        } else {
            List {
                ForEach(model.hits) { hit in
                    Button {
                        onSelect(hit.contact, NSNumber(value: hit.id))
                    } label: {
                        row(hit)
                    }
                    .onAppear {
                        if hit.id == model.hits.last?.id {
                            model.loadMore()
                        }
                    }
                }
                if model.isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }

    private func row(_ hit: MessageSearchHit) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(uiImage: hit.contact.avatar)
                .resizable()
                .frame(width: avatarSize, height: avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(hit.contact.contactDisplayNameWithoutSelfnotesPrefix)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(MessageSearchResultsFormat.shortDate(hit.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                (Text(hit.sender.map { "\($0): " } ?? "").foregroundColor(.secondary) + Text(hit.snippet))
                    .font(.subheadline)
                    .lineLimit(2)
                if let accountJid = hit.accountJid {
                    HStack(spacing: 3) {
                        Image(systemName: "person.crop.circle")
                        Text(accountJid)
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}

enum MessageSearchResultsFormat {
    /// today: the time; any other day: the date
    static func shortDate(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
