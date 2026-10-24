//
//  PublicChannelsView.swift
//  Monal
//
//  isaCloud: lists the public channels of the user's server (XEP-0030 disco#items on the MUC services)
//

import SwiftUI

struct PublicChannel: Identifiable {
    let jid: String
    let name: String
    var id: String { jid }
}

struct PublicChannelsView: View {
    //isaCloud: closes the contacts sheet and opens the chat of the given contact
    private let dismissWithContact: (MLContact) -> ()

    @State private var channels: [PublicChannel] = []
    @State private var loading = false
    @State private var failed = false
    @State private var visibleCount = 50    //isaCloud: the whole list is loaded and sorted; "Carregar mais" only shows more rows
    @State private var memberCounts: [String: Int] = [:]
    @State private var requestedCounts: Set<String> = []
    @State private var avatars: [String: UIImage] = [:]         //isaCloud: loaded channel avatars
    @State private var requestedAvatars: Set<String> = []
    @State private var joinedJids: Set<String> = []     //isaCloud: channels the account is already in
    @State private var joiningJids: Set<String> = []    //isaCloud: channels being joined, the row waits for the buddy list entry
    private static let avatarCache = NSCache<NSString, UIImage>()   //kept while the app runs, shared by every opening of the list
    private let pageSize = 50

    init(dismissWithContact: @escaping (MLContact) -> ()) {
        self.dismissWithContact = dismissWithContact
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            if loading {
                ProgressView()
            } else if failed {
                Text("Could not load the public channels of your server.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding()
            } else if channels.isEmpty {
                Text("Your server has no public channels to show.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List {
                    ForEach(channels.prefix(visibleCount)) { channel in
                        //isaCloud: tapping a channel joins it (or opens it, when already joined)
                        Button {
                            activate(channel)
                        } label: {
                            row(for: channel)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            loadMemberCount(channel.jid)
                            loadAvatar(channel)
                        }
                    }
                    if channels.count > visibleCount {
                        Button {
                            visibleCount += pageSize
                        } label: {
                            Text("Load more…")
                                .foregroundStyle(Color("isaCloudPink"))
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(Text("Public channels"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            load()
        }
    }

    private func row(for channel: PublicChannel) -> some View {
        HStack(spacing: 12) {
            avatarView(for: channel)
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text(channel.name)
                    if joinedJids.contains(channel.jid) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color("isaCloudBlue"))
                            .accessibilityLabel(Text("Already joined"))
                    }
                }
                Text(channel.jid)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let count = memberCounts[channel.jid] {
                Text(count == 1 ? NSLocalizedString("1 member", comment: "") : String(format: NSLocalizedString("%d members", comment: ""), count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func connectedAccount() -> xmpp? {
        let connected = MLXMPPManager.sharedInstance().connectedXMPP as? [xmpp] ?? []
        return connected.first
    }

    private func load() {
        guard let account = connectedAccount() else {
            failed = true
            return
        }
        loading = true
        account.mucProcessor.queryPublicChannels(completion: { result in
            DispatchQueue.main.async {
                loading = false
                guard let items = result as? [[String: String]] else {
                    failed = true
                    return
                }
                failed = false
                joinedJids = joinedChannels(among: items.compactMap { $0["jid"] })
                channels = items
                    .map { PublicChannel(jid: $0["jid"] ?? "", name: $0["name"] ?? "") }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        })
    }

    //isaCloud: a channel is joined when it is in the account's buddy list as a MUC
    private func joinedChannels(among jids: [String]) -> Set<String> {
        guard let account = connectedAccount() else {
            return []
        }
        return Set(jids.filter { DataLayer.sharedInstance().isBuddyMuc($0, forAccount: account.accountID) })
    }

    //isaCloud: a joined channel opens its chat; any other one is joined first
    private func activate(_ channel: PublicChannel) {
        guard let account = connectedAccount() else {
            return
        }
        if joinedJids.contains(channel.jid) {
            openChat(of: channel, account: account)
        } else if !joiningJids.contains(channel.jid) {
            joiningJids.insert(channel.jid)
            account.joinMuc(channel.jid)
            waitForJoin(channel, account: account, attempt: 0)
        }
    }

    //isaCloud: joining creates the buddy list entry asynchronously; open the chat as soon as it exists (about 20 s at most)
    private func waitForJoin(_ channel: PublicChannel, account: xmpp, attempt: Int) {
        if DataLayer.sharedInstance().isBuddyMuc(channel.jid, forAccount: account.accountID) {
            joiningJids.remove(channel.jid)
            joinedJids.insert(channel.jid)
            openChat(of: channel, account: account)
            return
        }
        guard attempt < 80 else {
            joiningJids.remove(channel.jid)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            waitForJoin(channel, account: account, attempt: attempt + 1)
        }
    }

    //isaCloud: puts the channel in the recent conversations and closes the contacts sheet on its chat
    private func openChat(of channel: PublicChannel, account: xmpp) {
        DataLayer.sharedInstance().addActiveBuddies(channel.jid, forAccount: account.accountID)
        dismissWithContact(MLContact.createContact(fromJid: channel.jid, andAccountID: account.accountID))
    }

    //isaCloud: the channel avatar, or colored initials (XEP-0392 color) while it is not loaded
    private func avatarView(for channel: PublicChannel) -> some View {
        let image = avatars[channel.jid]
            ?? MLImageManager.sharedInstance().generateDummyIcon(withName: channel.name, andColorInput: channel.jid)
        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 44, height: 44)
            .clipShape(Circle())
    }

    //isaCloud: one vCard per room, only once; the image is kept in the cache
    private func loadAvatar(_ channel: PublicChannel) {
        if let cached = PublicChannelsView.avatarCache.object(forKey: channel.jid as NSString) {
            avatars[channel.jid] = cached
            return
        }
        guard !requestedAvatars.contains(channel.jid), let account = connectedAccount() else {
            return
        }
        requestedAvatars.insert(channel.jid)
        account.mucProcessor.queryAvatar(ofRoom: channel.jid, completion: { result in
            guard let data = result as? Data, let image = UIImage(data: data) else {
                return
            }
            PublicChannelsView.avatarCache.setObject(image, forKey: channel.jid as NSString)
            DispatchQueue.main.async {
                avatars[channel.jid] = image
            }
        })
    }

    //isaCloud: one disco#info per visible row, only once per room
    private func loadMemberCount(_ jid: String) {
        guard !requestedCounts.contains(jid), let account = connectedAccount() else {
            return
        }
        requestedCounts.insert(jid)
        account.mucProcessor.queryMemberCount(ofRoom: jid, completion: { result in
            guard let count = result as? NSNumber else {
                return
            }
            DispatchQueue.main.async {
                memberCounts[jid] = count.intValue
            }
        })
    }
}
