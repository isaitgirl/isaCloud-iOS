//
//  Stickers.swift
//  Monal
//
//  isaCloud: stickers (figurinhas) made from a photo. The library is kept on the device (in the group folder of the app). The picker
//  opens from the attachment menu of the chat (Favorites, All, Create) and sends a sticker at once. The editor crops the photo to a
//  square, can remove the background (Vision) and adds texts. The sticker goes out as a 512x512 PNG, uploaded like a
//  photo, with the XEP-0449 marker (see MLXMPPManager sendMessageAndAddToHistory and xmpp.m sendMessage). Only SwiftUI, Vision and CryptoKit.
//

import CoreImage
import CryptoKit
import PhotosUI
import SwiftUI
import UIKit
import Vision

// MARK: - Library

/// isaCloud: one sticker of the library. `url` is its PNG (512x512, transparent where there is no picture).
struct Sticker: Identifiable, Equatable {
    let id: String
    let created: Date
    let lastUsed: Date
    let favorite: Bool
    let sha256: String
    let url: URL
}

/// isaCloud: what index.json keeps for one sticker (its picture is `<id>.png` next to the index)
private struct StickerEntry: Codable {
    let id: String
    var created: Date
    var lastUsed: Date
    var favorite: Bool
    let sha256: String
}

/// isaCloud: the stickers the person made, kept in `<app group>/stickers/`: one `<id>.png` per sticker and an `index.json` with the
/// creation date, the last use, the favorite flag and the hash (so the same picture is not kept twice). The index is written atomically.
/// A damaged index starts the library empty, and an entry whose PNG is gone is dropped.
final class StickerLibrary: ObservableObject {
    static let shared = StickerLibrary()

    /// the stickers in no particular order (see `all`)
    @Published private var entries: [StickerEntry] = []
    private let folder: URL

    private var indexURL: URL {
        return folder.appendingPathComponent("index.json")
    }

    private init() {
        folder = HelperTools.getContainerURL(forPathComponents: ["stickers"])
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
    }

    /// all stickers, the last used first (then the newest)
    var all: [Sticker] {
        return entries
            .sorted { ($0.lastUsed, $0.created) > ($1.lastUsed, $1.created) }
            .map { sticker(for: $0) }
    }

    /// the favorite stickers, in the order of `all`
    var favorites: [Sticker] {
        return all.filter { $0.favorite }
    }

    /// keeps the PNG in the library. A picture already there (same hash) is not kept twice: its sticker comes back instead.
    @discardableResult
    func add(pngData: Data) -> Sticker? {
        let hash = SHA256.hash(data: pngData).map { String(format: "%02x", $0) }.joined()
        if let existing = entries.first(where: { $0.sha256 == hash }) {
            return sticker(for: existing)
        }
        let id = UUID().uuidString
        do {
            try pngData.write(to: pngURL(for: id), options: .atomic)
        } catch {
            DDLogError("Stickers: could not write the PNG: \(error)")
            return nil
        }
        let now = Date()
        let entry = StickerEntry(id: id, created: now, lastUsed: now, favorite: false, sha256: hash)
        entries.append(entry)
        save()
        return sticker(for: entry)
    }

    func toggleFavorite(_ id: String) {
        mutate(id) { $0.favorite.toggle() }
    }

    /// a sticker that was sent goes to the top of `all`
    func markUsed(_ id: String) {
        mutate(id) { $0.lastUsed = Date() }
    }

    func delete(_ id: String) {
        guard entries.contains(where: { $0.id == id }) else {
            return
        }
        try? FileManager.default.removeItem(at: pngURL(for: id))
        entries.removeAll { $0.id == id }
        save()
    }

    func url(of sticker: Sticker) -> URL {
        return pngURL(for: sticker.id)
    }

    private func mutate(_ id: String, _ change: (inout StickerEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }
        change(&entries[index])
        save()
    }

    private func sticker(for entry: StickerEntry) -> Sticker {
        return Sticker(id: entry.id, created: entry.created, lastUsed: entry.lastUsed, favorite: entry.favorite, sha256: entry.sha256, url: pngURL(for: entry.id))
    }

    private func pngURL(for id: String) -> URL {
        return folder.appendingPathComponent("\(id).png")
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else {
            //no index yet: an empty library
            entries = []
            return
        }
        do {
            var loaded = try JSONDecoder().decode([StickerEntry].self, from: data)
            let count = loaded.count
            //a sticker whose picture is gone is dropped from the index
            loaded.removeAll { !FileManager.default.fileExists(atPath: pngURL(for: $0.id).path) }
            entries = loaded
            if loaded.count != count {
                save()
            }
        } catch {
            //a damaged index starts the library empty (the pictures stay on disk)
            DDLogError("Stickers: the index is damaged, starting empty: \(error)")
            entries = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            DDLogError("Stickers: could not write the index: \(error)")
        }
    }
}

/// isaCloud: the decoded stickers, so the grids and the chat do not read the PNG again on every redraw
enum StickerImageCache {
    private static let cache = NSCache<NSURL, UIImage>()

    static func image(at url: URL) -> UIImage? {
        if let image = cache.object(forKey: url as NSURL) {
            return image
        }
        guard let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// isaCloud: a still sticker from a local file, fitted in its frame (the chat shows it without a bubble, the grids in squares)
struct StickerImageView: View {
    let url: URL

    var body: some View {
        if let image = StickerImageCache.image(at: url) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Color(uiColor: .secondarySystemBackground)
        }
    }
}

// MARK: - Picker

/// isaCloud: the sticker sheet of the chat input: Favorites, All (the last used first) and the button to create one.
/// A tap sends the sticker at once (the chat does it through `onPick`), and the sheet closes.
struct StickerPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = StickerLibrary.shared
    var onPick: (Sticker) -> Void

    private enum Tab: Hashable {
        case favorites
        case all
    }

    @State private var tab: Tab = .all
    @State private var showEditor = false
    @State private var pendingDelete: Sticker?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    init(onPick: @escaping (Sticker) -> Void) {
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Stickers", selection: $tab) {
                    Text("Favorites").tag(Tab.favorites)
                    Text("All stickers").tag(Tab.all)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding()
                content
            }
            .navigationTitle(Text("Stickers"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEditor = true
                    } label: {
                        //a plain HStack: the toolbar of iOS 26 and later shows only the icon of a Label
                        HStack(spacing: 4) {
                            Image(systemName: "face.smiling")
                            Text("Create")
                        }
                        .foregroundStyle(.primary)
                    }
                    .accessibilityLabel(Text("Create sticker"))
                }
            }
            .sheet(isPresented: $showEditor) {
                StickerEditorView()
            }
            .confirmationDialog("Delete sticker?", isPresented: deleteDialogBinding, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let sticker = pendingDelete {
                        library.delete(sticker.id)
                    }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDelete = nil
                }
            }
        }
    }

    private var deleteDialogBinding: Binding<Bool> {
        return Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    @ViewBuilder
    private var content: some View {
        let shown = tab == .favorites ? library.favorites : library.all
        if library.all.isEmpty {
            ContentUnavailableView {
                Label("No stickers yet", systemImage: "face.smiling")
            } actions: {
                Button("Create sticker") {
                    showEditor = true
                }
                .buttonStyle(.borderedProminent)
            }
        } else if shown.isEmpty {
            ContentUnavailableView("No favorite stickers yet", systemImage: "star")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(shown) { sticker in
                        StickerImageView(url: sticker.url)
                            .aspectRatio(1, contentMode: .fit)
                            .padding(4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onPick(sticker)
                                dismiss()
                            }
                            .contextMenu {
                                Button {
                                    library.toggleFavorite(sticker.id)
                                } label: {
                                    if sticker.favorite {
                                        Label("Remove from favorites", systemImage: "star.slash")
                                    } else {
                                        Label("Favorite", systemImage: "star")
                                    }
                                }
                                Button(role: .destructive) {
                                    pendingDelete = sticker
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .accessibilityElement()
                            .accessibilityLabel(Text("Sticker"))
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(8)
            }
        }
    }
}

// MARK: - Editor

/// isaCloud: the colours of the texts; index 1 is black (its outline is white, the others have a black outline)
enum StickerTextColors {
    static let all: [Color] = [.white, .black, .yellow, .pink, .blue]
    static let blackIndex = 1
}

/// isaCloud: a text on the sticker. Its centre and its size are fractions of the square (the preview and the PNG use the same numbers).
struct StickerText: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var colorIndex: Int = 0
    /// the centre, from 0 to 1 of the side
    var x: CGFloat = 0.5
    var y: CGFloat = 0.5
    /// 1 is 11% of the side
    var scale: CGFloat = 1
}

/// isaCloud: the sticker as drawn on a square of `side` points: the photo cropped to the square (zoom and offset), and the texts over it.
/// The editor shows it at a few hundred points, and the PNG is drawn by ImageRenderer at 512 points; everything is a fraction of the side.
/// It has no background, so the transparent parts of the PNG stay transparent.
struct StickerCanvas: View {
    let side: CGFloat
    let photo: UIImage?
    let zoom: CGFloat
    /// the position of the photo, as a fraction of the side from its centre
    let offset: CGSize
    let texts: [StickerText]

    /// the margin around the crop square, as a fraction of the side
    static let margin: CGFloat = 0.06

    /// the size of the crop square on a square of `side` points
    static func frame(side: CGFloat) -> CGSize {
        let largest = side * (1 - 2 * margin)
        return CGSize(width: largest, height: largest)
    }

    var body: some View {
        ZStack {
            if let photo {
                let frame = StickerCanvas.frame(side: side)
                let base = max(frame.width / photo.size.width, frame.height / photo.size.height)
                Image(uiImage: photo)
                    .resizable()
                    .frame(width: photo.size.width * base * zoom, height: photo.size.height * base * zoom)
                    .offset(x: offset.width * side, y: offset.height * side)
                    .frame(width: frame.width, height: frame.height)
                    .clipped()
            }
            ForEach(texts) { item in
                StickerTextView(item: item, side: side)
                    .offset(x: (item.x - 0.5) * side, y: (item.y - 0.5) * side)
            }
        }
        .frame(width: side, height: side)
    }
}

/// isaCloud: one text of the sticker: white by default, with an outline (black, or white for black text), in a rounded heavy font
struct StickerTextView: View {
    let item: StickerText
    let side: CGFloat

    var body: some View {
        let font = Font.system(size: side * 0.11 * item.scale, weight: .heavy, design: .rounded)
        let fill = StickerTextColors.all[item.colorIndex]
        let outline: Color = item.colorIndex == StickerTextColors.blackIndex ? .white : .black
        let thickness = max(1, side * 0.008 * item.scale)
        ZStack {
            //the outline is the same text drawn in eight directions behind the fill
            ForEach(0..<8, id: \.self) { step in
                let angle = Double(step) * Double.pi / 4
                Text(item.text)
                    .font(font)
                    .foregroundStyle(outline)
                    .offset(x: CGFloat(cos(angle)) * thickness, y: CGFloat(sin(angle)) * thickness)
            }
            Text(item.text)
                .font(font)
                .foregroundStyle(fill)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: side * 0.9)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// isaCloud: the transparent area of the picture is drawn as a chequered background, in the editor only
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 12
            let columns = Int((size.width / cell).rounded(.up))
            let rows = Int((size.height / cell).rounded(.up))
            for row in 0..<rows {
                for column in 0..<columns where (row + column) % 2 == 0 {
                    let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(Color(uiColor: .systemGray5)))
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
}

/// isaCloud: the texts of the editor over the picture. A tap selects a text (its field shows below the picture), a drag moves it and a
/// pinch resizes it. A text can be anywhere on the square: over the picture or in its transparent margin.
private struct EditableTextLayer: View {
    let side: CGFloat
    @Binding var texts: [StickerText]
    @Binding var selected: UUID?
    //not private: the memberwise initializer is used by StickerEditorView (same file)
    @State var dragID: UUID?
    @State var dragStart = CGPoint.zero
    @State var scaleID: UUID?
    @State var scaleStart: CGFloat = 1

    var body: some View {
        ZStack {
            ForEach(texts) { item in
                StickerTextView(item: shown(item), side: side)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor, lineWidth: 1)
                            .opacity(selected == item.id ? 1 : 0)
                    )
                    .offset(x: (item.x - 0.5) * side, y: (item.y - 0.5) * side)
                    .onTapGesture {
                        selected = item.id
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                move(item.id, value.translation)
                            }
                            .onEnded { _ in
                                dragID = nil
                            }
                    )
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                resize(item.id, value.magnification)
                            }
                            .onEnded { _ in
                                scaleID = nil
                            }
                    )
            }
        }
        .frame(width: side, height: side)
    }

    /// an empty text shows its placeholder, so it can be found and selected
    private func shown(_ item: StickerText) -> StickerText {
        var copy = item
        if copy.text.isEmpty {
            copy.text = NSLocalizedString("Text", comment: "placeholder of a new text on a sticker, shown until it is typed")
        }
        return copy
    }

    private func move(_ id: UUID, _ translation: CGSize) {
        guard let index = texts.firstIndex(where: { $0.id == id }) else {
            return
        }
        if dragID != id {
            dragID = id
            dragStart = CGPoint(x: texts[index].x, y: texts[index].y)
        }
        texts[index].x = clampValue(dragStart.x + translation.width / side, 0, 1)
        texts[index].y = clampValue(dragStart.y + translation.height / side, 0, 1)
    }

    private func resize(_ id: UUID, _ factor: CGFloat) {
        guard let index = texts.firstIndex(where: { $0.id == id }) else {
            return
        }
        if scaleID != id {
            scaleID = id
            scaleStart = texts[index].scale
        }
        texts[index].scale = clampValue(scaleStart * factor, 0.4, 3)
    }
}

/// isaCloud: the editor of a sticker: choose the photo, crop it (square, drag and pinch), remove the background (optional),
/// add texts, and save the 512x512 PNG to the library.
struct StickerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    /// the picture as chosen, and the one in use (the same, or the one without its background)
    @State private var originalPhoto: UIImage?
    @State private var photo: UIImage?
    @State private var backgroundRemoved = false
    @State private var removingBackground = false
    @State private var showRemovalFailed = false
    @State private var showSaveFailed = false
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var offsetStart: CGSize = .zero
    @State private var texts: [StickerText] = []
    @State private var selectedText: UUID?
    @FocusState private var textFocused: Bool

    /// the side of the preview, in points (the PNG is 512 pixels)
    private static let previewSide: CGFloat = 320
    private static let outputSide: CGFloat = 512

    var body: some View {
        NavigationStack {
            Group {
                if photo == nil {
                    ContentUnavailableView {
                        Label("Choose photo", systemImage: "photo.on.rectangle")
                    } actions: {
                        Button("Choose photo") {
                            showPhotoPicker = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    editor
                }
            }
            .navigationTitle(Text("Create sticker"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .disabled(photo == nil || removingBackground)
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItem, matching: .images)
            //choosing a photo is the only way to start, so the picker opens at once (a moment later: the sheet must be up to present it)
            .onAppear {
                if photo == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showPhotoPicker = true
                    }
                }
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    await load(item)
                }
            }
            .alert("Could not remove the background", isPresented: $showRemovalFailed) {
                Button("Close", role: .cancel) {}
            }
            .alert("Could not save the sticker", isPresented: $showSaveFailed) {
                Button("Close", role: .cancel) {}
            }
        }
    }

    private var editor: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 16) {
                preview

                //while a text is typed the buttons are not needed: without them the field and its colours stay above the keyboard
                if !textFocused {
                VStack(spacing: 8) {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Choose photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        toggleBackground()
                    } label: {
                        if backgroundRemoved {
                            Label("Restore background", systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Remove background", systemImage: "scissors")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(removingBackground)

                    Button {
                        addText()
                    } label: {
                        Text("Aa")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text("Text"))
                }
                }

                if let index = selectedIndex {
                    textRow(index)
                        .id("textRow")
                }
            }
            .padding()
        }
        //the keyboard only keeps the field in sight: the colours below it are scrolled into sight too (after the keyboard is up)
        .onChange(of: textFocused) { _, focused in
            if focused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation {
                        proxy.scrollTo("textRow", anchor: .bottom)
                    }
                }
            }
        }
        }
    }

    /// the square where the sticker is made: the chequered background, the picture, the guide of the crop square, and the texts
    private var preview: some View {
        ZStack {
            Checkerboard()
            StickerCanvas(side: Self.previewSide, photo: photo, zoom: zoom, offset: offset, texts: [])
            let frame = StickerCanvas.frame(side: Self.previewSide)
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .frame(width: frame.width, height: frame.height)
                .allowsHitTesting(false)
            EditableTextLayer(side: Self.previewSide, texts: $texts, selected: $selectedText)
            if removingBackground {
                ProgressView()
            }
        }
        .frame(width: Self.previewSide, height: Self.previewSide)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    let limit = photoLimit()
                    offset = CGSize(
                        width: clampValue(offsetStart.width + value.translation.width / Self.previewSide, -limit.width, limit.width),
                        height: clampValue(offsetStart.height + value.translation.height / Self.previewSide, -limit.height, limit.height)
                    )
                }
                .onEnded { _ in
                    offsetStart = offset
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    zoom = clampValue(zoomStart * value.magnification, 1, 4)
                    offset = clampedOffset(offset)
                }
                .onEnded { _ in
                    zoomStart = zoom
                    offsetStart = offset
                }
        )
    }

    /// the field and the colours of the selected text, and the button that deletes it
    @ViewBuilder
    private func textRow(_ index: Int) -> some View {
        //the field takes the whole line (with the delete button), the colours go below it
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Text", text: $texts[index].text)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .focused($textFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        selectedText = nil
                    }
                Button(role: .destructive) {
                    texts.remove(at: index)
                    selectedText = nil
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(Text("Delete"))
            }
            HStack(spacing: 14) {
                colorButtons(index)
            }
        }
    }

    /// the colours of the selected text
    @ViewBuilder
    private func colorButtons(_ index: Int) -> some View {
            ForEach(0..<StickerTextColors.all.count, id: \.self) { colorIndex in
                Circle()
                    .fill(StickerTextColors.all[colorIndex])
                    .overlay(Circle().stroke(Color.secondary.opacity(0.6), lineWidth: 1))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .stroke(Color.accentColor, lineWidth: texts[index].colorIndex == colorIndex ? 3 : 0)
                            .padding(-3)
                    )
                    .onTapGesture {
                        texts[index].colorIndex = colorIndex
                    }
            }
    }

    private var selectedIndex: Int? {
        return texts.firstIndex { $0.id == selectedText }
    }

    /// how far the photo can move from the centre without leaving the frame empty (fractions of the side)
    private func photoLimit() -> CGSize {
        guard let photo else {
            return .zero
        }
        let frame = StickerCanvas.frame(side: 1)
        let base = max(frame.width / photo.size.width, frame.height / photo.size.height)
        return CGSize(
            width: max(0, (photo.size.width * base * zoom - frame.width) / 2),
            height: max(0, (photo.size.height * base * zoom - frame.height) / 2)
        )
    }

    private func clampedOffset(_ value: CGSize) -> CGSize {
        let limit = photoLimit()
        return CGSize(
            width: clampValue(value.width, -limit.width, limit.width),
            height: clampValue(value.height, -limit.height, limit.height)
        )
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            return
        }
        let normalized = StickerPhoto.normalized(image, maxSide: 1024)
        originalPhoto = normalized
        photo = normalized
        backgroundRemoved = false
        zoom = 1
        zoomStart = 1
        offset = .zero
        offsetStart = .zero
    }

    private func toggleBackground() {
        if backgroundRemoved {
            photo = originalPhoto
            backgroundRemoved = false
            offset = clampedOffset(offset)
            offsetStart = offset
            return
        }
        guard let original = originalPhoto else {
            return
        }
        removingBackground = true
        Task {
            let result = await StickerPhoto.removeBackground(from: original)
            removingBackground = false
            if let result {
                photo = result
                backgroundRemoved = true
                offset = clampedOffset(offset)
                offsetStart = offset
            } else {
                showRemovalFailed = true
            }
        }
    }

    private func addText() {
        let item = StickerText(text: "")
        texts.append(item)
        selectedText = item.id
        textFocused = true
    }

    /// renders the square at 512 points (a PNG of 512 pixels, transparent outside the picture and the texts) and adds it to the library
    private func save() {
        let shown = texts.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let renderer = ImageRenderer(content: StickerCanvas(side: Self.outputSide, photo: photo, zoom: zoom, offset: offset, texts: shown))
        renderer.scale = 1
        guard let image = renderer.uiImage, let png = image.pngData(), StickerLibrary.shared.add(pngData: png) != nil else {
            DDLogError("Stickers: could not render the sticker")
            showSaveFailed = true
            return
        }
        dismiss()
    }
}

/// isaCloud: photo helpers of the editor: the upright picture, and the background removal with Vision (the foreground subject)
enum StickerPhoto {
    /// the picture turned upright and made smaller than `maxSide` (a 512 sticker does not need more pixels)
    static func normalized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else {
            return image
        }
        let scale = min(1, maxSide / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// the picture with its background removed (transparent), or nil when Vision can not do it (the simulator may not)
    static func removeBackground(from image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
                    return nil
                }
                let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
                let ciImage = CIImage(cvPixelBuffer: buffer)
                let context = CIContext()
                guard let output = context.createCGImage(ciImage, from: ciImage.extent) else {
                    return nil
                }
                return UIImage(cgImage: output)
            } catch {
                DDLogError("Stickers: background removal failed: \(error)")
                return nil
            }
        }.value
    }
}

/// isaCloud: a value kept between two limits
private func clampValue<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    return min(upper, max(lower, value))
}
