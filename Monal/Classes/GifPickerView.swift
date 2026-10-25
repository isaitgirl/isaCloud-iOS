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
/// last frame; changing `replayToken` plays it again from the first frame.
struct AnimatedGifView: View {
    let url: URL
    var loops: Int? = nil
    var replayToken: Int = 0
    @State private var data: Data?

    var body: some View {
        Group {
            if let data {
                AnimatedGifRepresentable(data: data, loops: loops, replayToken: replayToken)
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
        view.contentMode = .scaleAspectFill
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

/// a GIF sent in the chat: plays twice, then stays still until it is tapped. Its reactions are drawn over the top edge,
/// on the same side as the other messages do (left for the own messages, right for the others).
struct GifMessageBubble: View {
    let url: URL
    @ObservedObject var user: ExyteChat.User
    let isCurrentUser: Bool
    let reactions: [Reaction]
    /// groups and channels: who sent the GIF is shown, like for the other messages (avatar on the last message of a sender's group, name above)
    var showSender: Bool = false
    var isLastOfSenderGroup: Bool = true
    @State private var replayToken = 0
    @Environment(\.chatTheme) private var theme

    private static let avatarSize: CGFloat = 32

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if showSender && !isCurrentUser {
                avatar
            }
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
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private var gif: some View {
        AnimatedGifView(url: url, loops: 2, replayToken: replayToken)
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture {
                replayToken += 1
            }
            .overlay(alignment: isCurrentUser ? .topLeading : .topTrailing) {
                GifReactionsView(reactions: reactionItems)
                    .offset(x: isCurrentUser ? -8 : 8, y: -10)
            }
    }

    /// the sender's picture beside the last GIF of a group of messages, an empty space beside the others (they line up with the bubbles)
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
        return reactions.compactMap { reaction in
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

/// the reaction bubbles of a GIF, drawn like the ones of the other messages: a circle with the emoji, overlapping each other.
/// When more than one person reacted with the same emoji, a small circle with the count sits on the bubble.
struct GifReactionsView: View {
    let reactions: [(emoji: String, isMine: Bool)]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(groups, id: \.emoji) { item in
                Text(verbatim: item.emoji)
                    .font(.body)
                    .padding(6)
                    .background(
                        ZStack {
                            // the same colours as the reactions of the other messages: mine or the other person's
                            Circle()
                                .fill(item.isMine ? IsaCloudBubbleColors.mine : ChatTheme().colors.messageFriendBG)
                            Circle()
                                .stroke(Color(uiColor: .systemBackground), lineWidth: 2)
                        }
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if item.count > 1 {
                            Text(verbatim: "\(item.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color(uiColor: .systemBackground))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Circle().fill(Color(uiColor: .label)))
                                .offset(x: 4, y: 4)
                        }
                    }
            }
        }
    }

    /// one bubble per emoji; it is mine when I reacted with that emoji
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
