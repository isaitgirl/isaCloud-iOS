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
    @State private var joinedAccounts: [String: [NSNumber]] = [:]   //isaCloud: channel jid -> accountIDs that already have it in their buddy list
    @State private var joiningJids: Set<String> = []    //isaCloud: "accountID|jid" of the joins in progress, the row waits for the buddy list entry
    @State private var channelToJoin: PublicChannel?    //isaCloud: channel waiting for the account choice in the sheet
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
        //isaCloud: with more than one ready account, the user picks the account the channel is joined with in a small sheet;
        //only the accounts that are not in the channel yet are offered (the row already says which ones are in it)
        .sheet(item: $channelToJoin) { channel in
            JoinChannelSheet(
                channel: channel,
                accounts: accountsNotInChannel(channel),
                accountJid: { accountJid($0) },
                onJoin: { account in join(channel, with: account) }
            )
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
                    if isJoinedByAny(channel.jid) {
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
                //isaCloud: with several accounts, says which of them are already in the channel (same icon as the conversation list)
                if allAccounts().count > 1 && isJoinedByAny(channel.jid) {
                    ForEach(joinedAccountJids(channel.jid), id: \.self) { jid in
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.circle")
                            Text(jid)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }
                }
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

    //isaCloud: every active account, connected or not (the same list as the conversation list)
    private func allAccounts() -> [xmpp] {
        return MLXMPPManager.sharedInstance().connectedXMPP as? [xmpp] ?? []
    }

    //isaCloud: the accounts that can already query the server and join rooms (same test as BlockedUsers)
    private func readyAccounts() -> [xmpp] {
        return allAccounts().filter {
            $0.accountState.rawValue >= xmppState.stateBound.rawValue && $0.connectionProperties.accountDiscoDone
        }
    }

    //isaCloud: any ready account can query a remote room, so the first one serves the avatar and the member count
    private func primaryAccount() -> xmpp? {
        return readyAccounts().first
    }

    private func accountJid(_ account: xmpp) -> String {
        return account.connectionProperties.identity.jid
    }

    private func load() {
        let accounts = readyAccounts()
        guard !accounts.isEmpty else {
            failed = true
            return
        }
        loading = true
        //isaCloud: every ready account lists the channels of its own server; the answers are merged
        var results: [[[String: String]]] = []
        let group = DispatchGroup()
        for account in accounts {
            group.enter()
            account.mucProcessor.queryPublicChannels(completion: { result in
                DispatchQueue.main.async {
                    if let items = result as? [[String: String]] {
                        results.append(items)
                    }
                    group.leave()
                }
            })
        }
        group.notify(queue: .main) {
            loading = false
            guard !results.isEmpty else {
                failed = true
                return
            }
            failed = false
            let merged = mergeChannels(results.flatMap { $0 })
            joinedAccounts = joinedAccounts(of: merged.map { $0.jid })
            channels = merged
        }
    }

    //isaCloud: the same channel can come from two servers; it is listed once, with the first non-empty name
    private func mergeChannels(_ items: [[String: String]]) -> [PublicChannel] {
        var names: [String: String] = [:]
        var order: [String] = []
        for item in items {
            let jid = item["jid"] ?? ""
            guard !jid.isEmpty else {
                continue
            }
            if let existing = names[jid] {
                if existing.isEmpty {
                    names[jid] = item["name"] ?? ""
                }
            } else {
                names[jid] = item["name"] ?? ""
                order.append(jid)
            }
        }
        return order
            .map { PublicChannel(jid: $0, name: names[$0] ?? "") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    //isaCloud: for each channel, the accounts whose buddy list already has it as a MUC (local DB, so every active account counts)
    private func joinedAccounts(of jids: [String]) -> [String: [NSNumber]] {
        var result: [String: [NSNumber]] = [:]
        for account in allAccounts() {
            for jid in jids where DataLayer.sharedInstance().isBuddyMuc(jid, forAccount: account.accountID) {
                result[jid, default: []].append(account.accountID)
            }
        }
        return result
    }

    private func isJoined(_ jid: String, by account: xmpp) -> Bool {
        return joinedAccounts[jid]?.contains(account.accountID) ?? false
    }

    private func isJoinedByAny(_ jid: String) -> Bool {
        return !(joinedAccounts[jid] ?? []).isEmpty
    }

    //isaCloud: the JIDs of the accounts that are already in the channel, one line each in the row
    private func joinedAccountJids(_ jid: String) -> [String] {
        return allAccounts()
            .filter { isJoined(jid, by: $0) }
            .map { accountJid($0) }
    }

    //isaCloud: the accounts that can join the channel; the ones of the channel's own server come first, the others keep their order.
    //The MUC service does not always share the account domain (isacloud.im accounts use conference.isacloud.cc), so an account
    //counts as "same server" when its server advertises the channel's MUC service, or when the service is a subdomain of the account domain.
    private func accountsForChannel(_ channel: PublicChannel) -> [xmpp] {
        let channelHost = (HelperTools.splitJid(channel.jid)["host"] ?? "").lowercased()
        var sameServer: [xmpp] = []
        var otherServers: [xmpp] = []
        for account in readyAccounts() {
            let accountHost = (HelperTools.splitJid(accountJid(account))["host"] ?? "").lowercased()
            let mucServices = account.connectionProperties.conferenceServers.allKeys.compactMap { ($0 as? String)?.lowercased() }
            if mucServices.contains(channelHost) || channelHost == accountHost || channelHost.hasSuffix("." + accountHost) {
                sameServer.append(account)
            } else {
                otherServers.append(account)
            }
        }
        return sameServer + otherServers
    }

    //isaCloud: one channel with one or more ready accounts: a single account joins right away, several ask first
    private func activate(_ channel: PublicChannel) {
        let accounts = accountsForChannel(channel)
        if accounts.isEmpty {
            return
        }
        if accounts.count == 1 {
            join(channel, with: accounts[0])
        } else if accountsNotInChannel(channel).isEmpty {
            //isaCloud: every ready account is already in the channel, so there is nothing to choose: open its chat
            join(channel, with: accounts[0])
        } else {
            channelToJoin = channel
        }
    }

    //isaCloud: the accounts offered in the "Join with…" sheet, in the same order as accountsForChannel
    private func accountsNotInChannel(_ channel: PublicChannel) -> [xmpp] {
        return accountsForChannel(channel).filter { !isJoined(channel.jid, by: $0) }
    }

    //isaCloud: a channel already in the account opens its chat; any other one is joined first
    private func join(_ channel: PublicChannel, with account: xmpp) {
        if isJoined(channel.jid, by: account) {
            openChat(of: channel, account: account)
        } else if !joiningJids.contains(joinKey(channel, account)) {
            joiningJids.insert(joinKey(channel, account))
            account.joinMuc(channel.jid)
            waitForJoin(channel, account: account, attempt: 0)
        }
    }

    //isaCloud: the same room can be joined by two accounts at once, so the key has the account too
    private func joinKey(_ channel: PublicChannel, _ account: xmpp) -> String {
        return "\(account.accountID)|\(channel.jid)"
    }

    //isaCloud: joining creates the buddy list entry asynchronously; open the chat as soon as it exists (about 20 s at most)
    private func waitForJoin(_ channel: PublicChannel, account: xmpp, attempt: Int) {
        if DataLayer.sharedInstance().isBuddyMuc(channel.jid, forAccount: account.accountID) {
            joiningJids.remove(joinKey(channel, account))
            if !isJoined(channel.jid, by: account) {
                joinedAccounts[channel.jid, default: []].append(account.accountID)
            }
            openChat(of: channel, account: account)
            return
        }
        guard attempt < 80 else {
            joiningJids.remove(joinKey(channel, account))
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
        guard !requestedAvatars.contains(channel.jid), let account = primaryAccount() else {
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
        guard !requestedCounts.contains(jid), let account = primaryAccount() else {
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

//isaCloud: small sheet to pick the account a channel is joined with; same account picker as the "Add contact" screen
//(AddContactMenu). Only the accounts that are not in the channel yet are listed, and the first one (same server) is selected.
private struct JoinChannelSheet: View {
    let channel: PublicChannel
    let accounts: [xmpp]
    let accountJid: (xmpp) -> String
    let onJoin: (xmpp) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAccount: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Join with…", selection: $selectedAccount) {
                        ForEach(Array(accounts.enumerated()), id: \.offset) { idx, account in
                            Text(accountJid(account)).tag(idx)
                        }
                    }
                    .pickerStyle(.menu)
                    HStack {
                        Spacer()
                        Button {
                            guard accounts.indices.contains(selectedAccount) else {
                                return
                            }
                            let account = accounts[selectedAccount]
                            dismiss()
                            onJoin(account)
                        } label: {
                            Text("Join the channel")
                        }
                        .buttonStyle(MonalProminentButtonStyle())
                    }
                }
            }
            .navigationTitle(Text(channel.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(240)])
    }
}
