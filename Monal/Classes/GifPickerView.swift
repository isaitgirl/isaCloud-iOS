//
//  GifPickerView.swift
//  Monal
//
//  isaCloud: GIFs of the chat input. The picker searches GIPHY or KLIPY (or shows the trending ones of the chosen provider;
//  a menu in the bar switches between them), and the chat shows a sent GIF animated. Both use FLAnimatedImage, the same
//  library as the older chat cells.
//

import ExyteChat
import FLAnimatedImage
import SwiftUI

/// an animated GIF from a local file or from the network. With `loops`, it plays that many times and then stays on the
/// last frame; changing `replayToken` plays it again from the first frame. With `fit`, the whole GIF shows inside the frame
/// (the chat bubble); without it, the GIF fills the frame and is cropped (the picker thumbnails).
struct AnimatedGifView: View {
    let url: URL
    var loops: Int? = nil
    var replayToken: Int = 0
    // isaCloud: the chat shows the whole GIF (fit), the picker thumbnails fill their square (fill)
    var fit: Bool = false
    @State private var data: Data?

    var body: some View {
        Group {
            if let data {
                AnimatedGifRepresentable(data: data, loops: loops, replayToken: replayToken, fit: fit)
            } else {
                Color(uiColor: .secondarySystemBackground)
            }
        }
        .task(id: url) {
            data = await GiphySearch.loadData(url)
        }
    }
}

private struct AnimatedGifRepresentable: UIViewRepresentable {
    let data: Data
    let loops: Int?
    let replayToken: Int
    let fit: Bool

    /// keeps the decoded GIF and the count of finished loops between updates
    final class Coordinator {
        var animated: FLAnimatedImage?
        var finishedLoops = 0
        var token = 0
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    func makeUIView(context: Context) -> FLAnimatedImageView {
        let view = FLAnimatedImageView()
        // isaCloud: the chat bubble shows the whole GIF; the thumbnails keep filling their square
        view.contentMode = fit ? .scaleAspectFit : .scaleAspectFill
        view.clipsToBounds = true
        // taps belong to the SwiftUI view around the GIF, not to the image
        view.isUserInteractionEnabled = false
        return view
    }

    // isaCloud: the view takes the size SwiftUI offers. Without this it kept the natural size of the GIF (a 387x290 GIF inside a
    // 220x165 bubble) and the clip showed only its middle, which is what cut the GIFs
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: FLAnimatedImageView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    func updateUIView(_ view: FLAnimatedImageView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.animated == nil {
            coordinator.animated = FLAnimatedImage(animatedGIFData: data)
            coordinator.token = replayToken
            start(view, coordinator)
        } else if coordinator.token != replayToken {
            coordinator.token = replayToken
            start(view, coordinator)
        }
    }

    private func start(_ view: FLAnimatedImageView, _ coordinator: Coordinator) {
        let loops = self.loops
        coordinator.finishedLoops = 0
        view.loopCompletionBlock = { [weak view] _ in
            coordinator.finishedLoops += 1
            if let loops, coordinator.finishedLoops >= loops {
                view?.stopAnimating()
            }
        }
        // setting nil first makes the view start the GIF from its first frame
        view.animatedImage = nil
        view.animatedImage = coordinator.animated
    }
}

/// isaCloud: the size of a GIF in the chat. It is as big as fits in a box, keeping its proportions, so the whole GIF shows.
enum GifLayout {
    /// the side of the square used when the size of the GIF is not known
    static let defaultSide: CGFloat = 220
    private static let defaultSize = CGSize(width: defaultSide, height: defaultSide)
    private static let pixelSizes = NSCache<NSURL, NSValue>()

    /// the width and height in pixels, read from the file header (no frame is decoded); nil when it cannot be read
    static func pixelSize(of url: URL) -> CGSize? {
        if let cached = pixelSizes.object(forKey: url as NSURL) {
            return cached.cgSizeValue
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else {
            return nil
        }
        let size = CGSize(width: width, height: height)
        pixelSizes.setObject(NSValue(cgSize: size), forKey: url as NSURL)
        return size
    }

    /// the largest size, with the proportions of `pixel`, that fits in `box` (small GIFs grow up to the box). Never zero;
    /// without a usable size, the default square.
    static func fittedSize(for pixel: CGSize, in box: CGSize = CGSize(width: 220, height: 280)) -> CGSize {
        guard pixel.width > 0, pixel.height > 0 else {
            return defaultSize
        }
        let scale = min(box.width / pixel.width, box.height / pixel.height)
        return CGSize(width: max(1, (pixel.width * scale).rounded()), height: max(1, (pixel.height * scale).rounded()))
    }

    /// the size the GIF is shown at in the chat
    static func chatSize(for url: URL) -> CGSize {
        return fittedSize(for: pixelSize(of: url) ?? defaultSize)
    }
}

/// a GIF sent in the chat: plays twice, then stays still until it is tapped. Around it the same things the other messages have: the sender's
/// avatar beside it, the reactions below it (as the footer of the other messages), the time (with the lock of an encrypted message) below
/// them, the delivery status icon beside it (own messages), and the message menu (with the reactions to choose from) on a long press.
struct GifMessageBubble: View {
    let url: URL
    @ObservedObject var message: ExyteChat.Message
    @ObservedObject var user: ExyteChat.User
    let isCurrentUser: Bool
    /// groups and channels: who sent the GIF is also shown above the picture, in a gray bubble like the text messages of others
    var showSender: Bool = false
    /// the avatar is drawn beside the last message of a sender's group, an empty space beside the others (they line up with the bubbles)
    var isLastOfSenderGroup: Bool = true
    /// opens the message menu (reactions, reply, copy...)
    var showContextMenu: () -> Void = {}
    /// called when the reactions are tapped, to show who reacted with what
    var onReactionsTap: () -> Void = {}
    /// isaCloud: a sticker (XEP-0449) is a still picture of `stickerSide` points, without the bubble, from a local file (see Stickers.swift)
    var isSticker: Bool = false
    //isaCloud: a tap on a sticker opens the chat's fullscreen viewer (the GIF replays instead, see below)
    var onSelect: (() -> Void)? = nil
    @State private var replayToken = 0
    @Environment(\.chatTheme) private var theme

    static let stickerSide: CGFloat = 128
    private static let avatarSize: CGFloat = 32
    //the same width the ExyteChat message view reserves for the status icon
    private static let statusSize: CGFloat = 16

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isCurrentUser {
                avatar
            }
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 2) {
                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 2) {
                    if showSender && !isCurrentUser && isSticker {
                        //isaCloud: a sticker has no bubble at all, not even in a group: only the name above it
                        Text(user.name)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        gif
                    } else if showSender && !isCurrentUser {
                        //like the other messages of others in a group or channel: a gray bubble with the name above the picture
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.name)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                            gif
                                .padding(.horizontal, 6)
                                .padding(.bottom, 6)
                        }
                        .background(RoundedRectangle(cornerRadius: 14).fill(theme.colors.messageFriendBG))
                    } else {
                        gif
                    }
                    // isaCloud: the reactions under the GIF, as the footer of the other messages; the space is reserved only when there are some
                    if !reactionItems.isEmpty {
                        GifReactionsFooter(reactions: reactionItems, width: gifSize.width, onTap: onReactionsTap)
                    }
                }
                // isaCloud: the picture and its reactions are the bubble for the long press of the chat; the time below, the avatar and the status are not
                .reportsMessageBubbleFrame()
                timeView
            }
            if isCurrentUser, let status = message.status {
                statusIcon(status)
                    .frame(width: Self.statusSize, height: Self.statusSize)
                    //the status icon lines up with the time, not with the bottom of the picture
                    .padding(.bottom, 1)
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    /// isaCloud: the whole GIF, at the size that fits the chat (see GifLayout)
    private var gifSize: CGSize {
        //isaCloud: a sticker has its own fixed size
        if isSticker {
            return CGSize(width: Self.stickerSide, height: Self.stickerSide)
        }
        return GifLayout.chatSize(for: url)
    }

    private var gif: some View {
        Group {
            if isSticker {
                StickerImageView(url: url)
            } else {
                AnimatedGifView(url: url, loops: 2, replayToken: replayToken, fit: true)
            }
        }
        .frame(width: gifSize.width, height: gifSize.height)
        .clipShape(RoundedRectangle(cornerRadius: isSticker ? 0 : 14))
        .contentShape(RoundedRectangle(cornerRadius: isSticker ? 0 : 14))
        //isaCloud: a sticker opens on a tap, so it is a button for VoiceOver (a GIF is not)
        .accessibilityAddTraits(isSticker ? .isButton : [])
        .onTapGesture {
            //isaCloud: a tap on a sticker opens it in the fullscreen viewer; a tap on a GIF replays it
            if isSticker {
                onSelect?()
            } else {
                replayToken += 1
            }
        }
            .onLongPressGesture(minimumDuration: 0.15) {     //same time as the other messages (ExyteChat fork, UIList.swift)
                showContextMenu()
            }
    }

    /// the time of the message, with the lock when it was encrypted (OMEMO), like under the photos
    private var timeView: some View {
        HStack(spacing: 4) {
            if message.encrypted {
                Image(systemName: "lock.fill")
            }
            Text(message.createdAt, style: .time)
        }
        .font(.caption2)      //isaCloud: 11 pt at the default size, and it follows the chat text size (see ChatTextSize)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    /// the same icons as the other messages (see `IsaCloudStatusIcons` and the chat theme)
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

    /// each emoji reaction with whether the current user sent it
    private var reactionItems: [(emoji: String, isMine: Bool)] {
        return message.reactions.compactMap { reaction in
            if case .emoji(let emoji) = reaction.type {
                return (emoji: emoji, isMine: reaction.user.isCurrentUser)
            }
            return nil
        }
    }
}

/// colours of the messages the current user sends. They come from Settings > User Interface > Appearance: "#RRGGBB" in the
/// ownBubbleColorHex and ownBubbleTextColorHex keys; an empty value is the isaCloud default, the pink asset with white text.
/// The hex and contrast helpers are in IsaCloudColorMath (pure, unit tested).
enum IsaCloudBubbleColors {
    private static let bubbleKey = "ownBubbleColorHex"
    private static let textKey = "ownBubbleTextColorHex"
    private static let bubbleCache = HexColorCache()
    private static let textCache = HexColorCache()

    static var mine: Color { bubble(storedHex(bubbleKey)) }
    static var mineText: Color { text(storedHex(textKey)) }
    static var mineTime: Color { time(storedHex(textKey)) }

    /// the bubble colour for a hex value; the chat view passes the value it observes, so it redraws when the value changes
    static func bubble(_ hex: String) -> Color {
        return bubbleCache.color(for: hex) { IsaCloudColorMath.color(fromHex: $0) ?? Color("isaCloudPink") }
    }

    /// the text colour for a hex value
    static func text(_ hex: String) -> Color {
        return textCache.color(for: hex) { IsaCloudColorMath.color(fromHex: $0) ?? Color.white }
    }

    /// the time under my messages: the text colour at 85% opacity (white at 85% by default)
    static func time(_ hex: String) -> Color {
        return text(hex).opacity(0.85)
    }

    /// true when a colour was chosen in the settings (the default is both values empty)
    static var hasCustomColors: Bool {
        return !storedHex(bubbleKey).isEmpty || !storedHex(textKey).isEmpty
    }

    /// false when a chosen colour leaves the text hard to read on the bubble; the default is not warned about
    static var hasReadableContrast: Bool {
        guard hasCustomColors else {
            return true
        }
        return IsaCloudColorMath.isReadable(bubble: mine, text: mineText)
    }

    /// back to the isaCloud default colours (empty values)
    static func resetToDefaults() {
        let defaults = HelperTools.defaultsDB()
        defaults.set("", forKey: bubbleKey)
        defaults.set("", forKey: textKey)
    }

    private static func storedHex(_ key: String) -> String {
        return HelperTools.defaultsDB().string(forKey: key) ?? ""
    }
}

/// keeps the colour of the last hex value read. The settings are read while the chats draw the messages, which can happen
/// off the main thread, so the cache is locked.
private final class HexColorCache {
    private let lock = NSLock()
    private var lastHex: String?
    private var lastColor = Color.clear

    func color(for hex: String, make: (String) -> Color) -> Color {
        lock.lock()
        defer { lock.unlock() }
        if lastHex == hex {
            return lastColor
        }
        let color = make(hex)
        lastHex = hex
        lastColor = color
        return color
    }
}

/// isaCloud: the reactions of a GIF, drawn like the footer of the other messages (ExyteChat fork, MessageReactionView.swift): a row of
/// capsule buttons, one per emoji with its count, up to five; the ones that do not fit become a "+N" capsule. A tap opens who reacted with what.
/// The footer always sits outside any bubble (the gray bubble of a group wraps only the picture), so it uses the palette of the
/// fork's media-only reactions: gray for all, pink with pink text for my own reaction, whoever sent the GIF.
struct GifReactionsFooter: View {
    let reactions: [(emoji: String, isMine: Bool)]
    /// the width of the GIF: the footer is centered under it
    let width: CGFloat
    /// opens the list of who reacted with what
    let onTap: () -> Void
    @Environment(\.chatTheme) private var theme

    private static let maxCapsules = 5

    var body: some View {
        let all = groups
        let shown = Array(all.prefix(Self.maxCapsules))
        let hidden = all.count - shown.count
        HStack(spacing: 6) {
            ForEach(shown, id: \.emoji) { item in
                capsule(item.count > 1 ? "\(item.emoji) \(item.count)" : item.emoji, isMine: item.isMine)
            }
            if hidden > 0 {
                // the reactions that did not fit: one more capsule, it opens the same list
                capsule("+\(hidden)", isMine: false)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: all.map { "\($0.emoji) \($0.count)" }.joined(separator: ", ")))
        .accessibilityAddTraits(.isButton)
    }

    /// one capsule: gray for the reactions in general, pink with pink text for my own reaction (no bubble behind it)
    @ViewBuilder
    private func capsule(_ text: String, isMine: Bool) -> some View {
        let button = Button(action: onTap) {
            Text(verbatim: text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isMine ? theme.colors.messageMyBG : theme.colors.mainText)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonBorderShape(.capsule)
        .controlSize(.mini)
        button.buttonStyle(.bordered).tint(isMine ? theme.colors.messageMyBG : theme.colors.mainText)
    }

    /// one capsule per emoji; it is mine when I reacted with that emoji
    private var groups: [(emoji: String, count: Int, isMine: Bool)] {
        return GifReactionCounts.counts(of: reactions.map { $0.emoji }).map { item in
            (emoji: item.emoji, count: item.count, isMine: reactions.contains { $0.emoji == item.emoji && $0.isMine })
        }
    }
}

struct GifPickerView: View {
    @Environment(\.dismiss) private var dismiss
    /// isaCloud: the keys from the build; the menu offers the providers that have one
    let keys: GifKeys
    var onPick: (URL) -> Void

    @State private var query: String = ""
    @State private var gifs: [GiphyGif] = []
    @State private var state: LoadState = .loading
    @State private var downloading = false
    /// the provider searched now; nil when the build has no key at all
    @State private var provider: GifProvider?
    /// the page of the GIFs on screen (the first page is 0); loadMore asks the next one
    @State private var pageIndex = 0
    /// isaCloud: how many GIFs a page has on screen: 50 for the trending ones, 24 for a search (see GifSearch)
    @State private var currentPageSize = GifSearch.pageSize
    /// true while the last page says there may be more
    @State private var hasMore = false
    /// true while a page after the first one is loading, so the same page is not asked twice
    @State private var loadingMore = false
    /// the search term of the GIFs on screen, or nil for the trending ones
    @State private var currentQuery: String?
    /// counts the first-page requests, so an answer that arrives after a new search or trending load is dropped
    @State private var generation = 0

    private enum LoadState: Equatable {
        case loading
        case loaded
        case failed
        case missingKey
    }

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 6)]

    init(keys: GifKeys, onPick: @escaping (URL) -> Void) {
        self.keys = keys
        self.onPick = onPick
        // isaCloud: the provider chosen last time (read as a plain string, not with @defaultsDB), or the one the build can use
        _provider = State(initialValue: keys.resolved(stored: HelperTools.defaultsDB().string(forKey: GifProvider.defaultsKey)))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("GIF"))
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: searchPrompt)
                .onSubmit(of: .search) { runSearch() }
                .onChange(of: query) { _, newValue in
                    if newValue.isEmpty {
                        loadTrending()
                    }
                }
                .toolbar {
                    if keys.available.count > 1 {
                        ToolbarItem(placement: .topBarLeading) {
                            providerMenu
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    poweredBy
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
                .disabled(downloading)
                .overlay {
                    if downloading {
                        ProgressView()
                    }
                }
                .task {
                    loadTrending()
                }
        }
        .onAppear {
            GifNetworkStats.shared.reset()
        }
        .onDisappear {
            logStats()
        }
    }

    /// isaCloud: the menu on the left of the bar to switch between the providers that have a key
    private var providerMenu: some View {
        Menu {
            Picker(selection: Binding(get: { provider ?? GifProvider.defaultProvider }, set: { choose($0) })) {
                ForEach(keys.available) { option in
                    Text(verbatim: option.displayName).tag(option)
                }
            } label: {
                Text("GIF provider")
            }
        } label: {
            // text and chevron side by side: a Label in the navigation bar would show only the icon
            HStack(spacing: 3) {
                Text(verbatim: provider?.displayName ?? "")
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
        }
        .accessibilityLabel(Text("GIF provider"))
    }

    /// the attribution each provider asks for
    @ViewBuilder
    private var poweredBy: some View {
        if provider == .klipy {
            Text("Powered by KLIPY")
        } else {
            Text("Powered by GIPHY")
        }
    }

    /// KLIPY asks for its name in the search field; GIPHY keeps the text it always had
    private var searchPrompt: Text {
        if provider == .klipy {
            return Text("Search KLIPY")
        }
        return Text("Search GIFs")
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .missingKey:
            ContentUnavailableView("GIF search is not available", systemImage: "photo.on.rectangle", description: Text("The GIF search key is not set in this build."))
        case .failed:
            ContentUnavailableView("Could not search GIFs", systemImage: "wifi.exclamationmark", description: Text("Try again in a moment."))
        case .loading:
            ProgressView()
        case .loaded where gifs.isEmpty:
            ContentUnavailableView("No GIFs found", systemImage: "magnifyingglass")
        case .loaded:
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(gifs, id: \.id) { gif in
                        AnimatedGifView(url: gif.previewURL)
                            .frame(height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture {
                                pick(gif)
                            }
                            .accessibilityElement()
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("GIF")
                            .onAppear {
                                // the last GIF on screen: the next page comes in (see loadMore)
                                if gif.id == gifs.last?.id {
                                    loadMore()
                                }
                            }
                    }
                }
                .padding(6)
            }
        }
    }

    /// isaCloud: saves the provider the user picked and searches again with it (the search term, or the trending ones)
    private func choose(_ newValue: GifProvider) {
        guard newValue != provider else {
            return
        }
        provider = newValue
        HelperTools.defaultsDB().set(newValue.rawValue, forKey: GifProvider.defaultsKey)
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            loadTrending()
        } else {
            runSearch()
        }
    }

    /// the GIFs most used at the moment, shown until the user searches. A fresh saved first page is shown without a request;
    /// otherwise the first page is asked and saved (see GifTrendingCache)
    private func loadTrending() {
        guard let provider, let apiKey = keys.key(for: provider) else {
            state = .missingKey
            return
        }
        currentQuery = nil
        if let entry = GifTrendingCache.shared.load(provider: provider) {
            showSaved(entry, provider: provider)
            return
        }
        loadFirstPage(query: nil, provider: provider, apiKey: apiKey, pageSize: GifSearch.trendingPageSize)
    }

    /// shows a saved trending list at once, shuffled like a fresh one; the next pages continue from it
    private func showSaved(_ entry: GifTrendingCache.Entry, provider: GifProvider) {
        generation += 1
        state = .loaded
        loadingMore = false
        pageIndex = 0
        currentPageSize = GifSearch.trendingPageSize
        gifs = entry.gifs.shuffled()
        hasMore = entry.hasMore
        let ageMinutes = max(0, Int(Date().timeIntervalSince(entry.fetchedAt) / 60))
        DDLogInfo("GIF cache: trending \(provider.rawValue) from saved list, age \(ageMinutes) min, \(entry.gifs.count) GIFs")
    }

    private func runSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            loadTrending()
            return
        }
        guard let provider, let apiKey = keys.key(for: provider) else {
            state = .missingKey
            return
        }
        currentQuery = text
        loadFirstPage(query: text, provider: provider, apiKey: apiKey, pageSize: GifSearch.pageSize)
    }

    /// the first page replaces the grid; a failure here shows the error, as before. A trending first page is saved for later openings.
    private func loadFirstPage(query: String?, provider: GifProvider, apiKey: String, pageSize: Int) {
        generation += 1
        let current = generation
        state = .loading
        loadingMore = false
        hasMore = false
        pageIndex = 0
        currentPageSize = pageSize
        Task {
            do {
                let page = try await GifSearch.fetch(provider: provider, query: query, apiKey: apiKey, pageIndex: 0, pageSize: pageSize)
                guard current == generation else {
                    return
                }
                // an empty answer is not kept: it would show "No GIFs found" until the saved list expires
                if query == nil && !page.gifs.isEmpty {
                    GifTrendingCache.shared.save(page, provider: provider)
                }
                logPage(query: query, provider: provider, pageIndex: 0, page: page)
                gifs = query == nil ? page.gifs.shuffled() : page.gifs
                hasMore = page.hasMore
                state = .loaded
            } catch {
                guard current == generation else {
                    return
                }
                state = .failed
            }
        }
    }

    /// the page after the last one shown, for the same trending or search. A failure keeps the GIFs on screen: nothing changes
    /// here, and the next time the end of the grid shows, it asks again.
    private func loadMore() {
        // isaCloud: at most GifSearch.maxPages pages (150 trending or 72 searched GIFs): fast scrolling spent one API call per page
        // and both keys allow 100 calls per hour for everyone
        guard hasMore, !loadingMore, state == .loaded, pageIndex + 1 < GifSearch.maxPages,
              let provider, let apiKey = keys.key(for: provider) else {
            return
        }
        loadingMore = true
        let current = generation
        let query = currentQuery
        let next = pageIndex + 1
        Task {
            do {
                let page = try await GifSearch.fetch(provider: provider, query: query, apiKey: apiKey, pageIndex: next, pageSize: currentPageSize)
                guard current == generation else {
                    return
                }
                logPage(query: query, provider: provider, pageIndex: next, page: page)
                // a GIF already on screen is not repeated
                let known = Set(gifs.map { $0.id })
                gifs += page.gifs.filter { !known.contains($0.id) }
                hasMore = page.hasMore
                pageIndex = next
            } catch {
                // the grid keeps what it has
            }
            if current == generation {
                loadingMore = false
            }
        }
    }

    /// one line per page for the log: trending or search, where the page came from, how many GIFs, the rate limit left.
    /// The search term is never logged, only its length.
    private func logPage(query: String?, provider: GifProvider, pageIndex: Int, page: GifPage) {
        let kind = query == nil ? "trending" : "search"
        let queryPart = query.map { ", query of \($0.count) chars" } ?? ""
        let source = page.fromCache ? "HTTP cache" : "network"
        let remaining = page.rateLimitRemaining.map { String($0) } ?? "unknown"
        DDLogInfo("GIF cache: \(kind) \(provider.rawValue) page \(pageIndex)\(queryPart) from \(source), \(page.gifs.count) GIFs, rate limit remaining \(remaining)")
    }

    /// how the requests of this opening were answered, for the API and for the previews (logged when the picker closes)
    private func logStats() {
        let stats = GifNetworkStats.shared.snapshot()
        DDLogInfo("GIF cache: picker closed, API \(stats.apiFromCache) from HTTP cache / \(stats.apiFromNetwork) from network, previews \(stats.previewsFromCache) from cache / \(stats.previewsFromNetwork) from network")
    }

    private func pick(_ gif: GiphyGif) {
        downloading = true
        Task {
            do {
                let url = try await GiphySearch.download(gif)
                downloading = false
                onPick(url)
                dismiss()
            } catch {
                downloading = false
                state = .failed
            }
        }
    }
}

/// isaCloud: the status icon of a message the server confirmed: a gray hollow circle with a gray check inside, to sit between the
/// clock (sending, also gray) and the check in a pink hollow circle (delivered): same shape as "delivered", gray instead of pink.
/// It is drawn here because ExyteChat's own icon for this state is empty, and stretched by ExyteChat to a small square (see
/// statusViewWidth in our fork).
/// The gray is baked into the image (original rendering), because the chat would tint a template image with the pink of our messages.
enum IsaCloudStatusIcons {
    static let sentToServer: UIImage = {
        let side: CGFloat = 60
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setStrokeColor(UIColor.systemGray.cgColor)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            // the hollow circle
            let lineWidth: CGFloat = 4.5
            cg.setLineWidth(lineWidth)
            cg.strokeEllipse(in: CGRect(x: lineWidth / 2 + 1, y: lineWidth / 2 + 1, width: side - lineWidth - 2, height: side - lineWidth - 2))

            // the check
            cg.setLineWidth(5)
            cg.move(to: CGPoint(x: side * 0.28, y: side * 0.52))
            cg.addLine(to: CGPoint(x: side * 0.43, y: side * 0.67))
            cg.addLine(to: CGPoint(x: side * 0.73, y: side * 0.35))
            cg.strokePath()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }()
}
