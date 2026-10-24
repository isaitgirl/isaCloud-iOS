//
//  GifPickerView.swift
//  Monal
//
//  isaCloud: GIFs of the chat input. The picker searches Giphy (or shows the trending ones), and the chat shows a
//  sent GIF animated. Both use FLAnimatedImage, the same library as the older chat cells.
//

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

/// a GIF sent in the chat: plays twice, then stays still until it is tapped
struct GifMessageBubble: View {
    let url: URL
    let isCurrentUser: Bool
    @State private var replayToken = 0

    var body: some View {
        AnimatedGifView(url: url, loops: 2, replayToken: replayToken)
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture {
                replayToken += 1
            }
            .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
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
