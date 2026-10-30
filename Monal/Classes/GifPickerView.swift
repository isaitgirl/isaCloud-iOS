//
//  GifPickerView.swift
//  Monal
//
//  isaCloud: GIFs of the chat input. The picker searches Giphy (or shows the trending ones), and the chat shows a
//  sent GIF animated. Both use FLAnimatedImage, the same library as the older chat cells.
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
    @State private var replayToken = 0
    @Environment(\.chatTheme) private var theme

    private static let avatarSize: CGFloat = 32
    //the same width the ExyteChat message view reserves for the status icon
    private static let statusSize: CGFloat = 16

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isCurrentUser {
                avatar
            }
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 2) {
                if showSender && !isCurrentUser {
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
                    GifReactionsFooter(reactions: reactionItems, width: gifSize.width, isCurrentUser: isCurrentUser, onTap: onReactionsTap)
                }
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
        return GifLayout.chatSize(for: url)
    }

    private var gif: some View {
        AnimatedGifView(url: url, loops: 2, replayToken: replayToken, fit: true)
            .frame(width: gifSize.width, height: gifSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture {
                replayToken += 1
            }
            .onLongPressGesture(minimumDuration: 0.3) {      //same time as the other messages (ExyteChat fork, UIList.swift)
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

/// colours of the messages the current user sends: the isaCloud pink with white text
enum IsaCloudBubbleColors {
    static let mine = Color("isaCloudPink")
    static let mineText = Color.white
    static let mineTime = Color.white.opacity(0.85)
}

/// isaCloud: the reactions of a GIF, drawn like the footer of the other messages (ExyteChat fork, MessageReactionView.swift): a row of
/// capsule buttons, one per emoji with its count, up to five; the ones that do not fit become a "+N" capsule. A tap opens who reacted with what.
struct GifReactionsFooter: View {
    let reactions: [(emoji: String, isMine: Bool)]
    /// the width of the GIF: the footer is centered under it
    let width: CGFloat
    /// my message: the capsules are white on the pink of my bubbles
    let isCurrentUser: Bool
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

    /// one capsule: solid white on my pink bubbles, so it can be seen; gray on the others, pink for my own reaction
    @ViewBuilder
    private func capsule(_ text: String, isMine: Bool) -> some View {
        let button = Button(action: onTap) {
            Text(verbatim: text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isCurrentUser ? theme.colors.messageMyBG : theme.colors.mainText)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonBorderShape(.capsule)
        .controlSize(.mini)
        if isCurrentUser {
            button.buttonStyle(.borderedProminent).tint(.white)
        } else {
            button.buttonStyle(.bordered).tint(isMine ? theme.colors.messageMyBG : theme.colors.mainText)
        }
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
    let apiKey: String?
    var onPick: (URL) -> Void

    @State private var query: String = ""
    @State private var gifs: [GiphyGif] = []
    @State private var state: LoadState = .loading
    @State private var downloading = false

    private enum LoadState: Equatable {
        case loading
        case loaded
        case failed
        case missingKey
    }

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 6)]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("GIF"))
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: Text("Search GIFs"))
                .onSubmit(of: .search) { runSearch() }
                .onChange(of: query) { _, newValue in
                    if newValue.isEmpty {
                        loadTrending()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Text("Powered by GIPHY")
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
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .missingKey:
            ContentUnavailableView("GIF search is not available", systemImage: "photo.on.rectangle", description: Text("The GIPHY key is not set in this build."))
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
                    }
                }
                .padding(6)
            }
        }
    }

    /// the GIFs most used at the moment, shown until the user searches
    private func loadTrending() {
        guard let apiKey else {
            state = .missingKey
            return
        }
        state = .loading
        Task {
            do {
                gifs = try await GiphySearch.trending(apiKey: apiKey)
                state = .loaded
            } catch {
                state = .failed
            }
        }
    }

    private func runSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            loadTrending()
            return
        }
        guard let apiKey else {
            state = .missingKey
            return
        }
        state = .loading
        Task {
            do {
                gifs = try await GiphySearch.search(query: text, apiKey: apiKey)
                state = .loaded
            } catch {
                state = .failed
            }
        }
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
