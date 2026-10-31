//
//  ChatInputBar.swift
//  Monal
//
//  isaCloud: the chat input bar, rendered from ChatInputModel. The ChatView owns the actions (send, upload, edit).
//

import AVFoundation
import SwiftUI

struct ChatInputBar: View {
    @ObservedObject var model: ChatInputModel
    var onSend: () -> Void
    var onSaveEdit: () -> Void
    var onCancelEdit: () -> Void
    var onAttachPhotos: () -> Void
    var onAttachFile: () -> Void
    /// isaCloud: attaches the image on the clipboard; the item is only offered while the clipboard has one
    var onPasteImage: () -> Void = {}
    var onSearchGif: () -> Void
    var onShareLocation: () -> Void
    var onRemoveAttachment: (Int) -> Void
    var onSendRecording: (URL) -> Void
    /// isaCloud: the nicks offered for "@" in a group or channel (none in a 1:1 chat)
    var mentionCandidates: () -> [String] = { [] }
    /// isaCloud: the text size of the chat (see ChatTextSize), used by the floating "sending" capsule; the field keeps the system size
    var sendingHintTypeSize: DynamicTypeSize = .large
    @State private var pressStart: Date?
    @State private var showNoClipboardImage = false
    @State private var showMicrophoneDenied = false

    private var textBinding: Binding<String> {
        Binding(get: { model.text }, set: { model.setText($0) })
    }

    var body: some View {
        VStack(spacing: 6) {
            if model.edit != nil {
                editBanner
            }
            if !model.attachments.isEmpty {
                attachmentsRow
            }
            if model.recording == nil {
                mentionSuggestions
            }
            HStack(alignment: .bottom, spacing: 8) {
                if model.edit == nil && model.recording == nil {
                    attachMenu
                }
                if model.recording != nil {
                    recordingStrip
                } else {
                    inputField
                }
                trailingButton
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
        //isaCloud: the "sending" hint floats above the bar, so the chat does not move up and down while a file goes out
        .overlay(alignment: .top) {
            if model.isUploading {
                SendingHint().dynamicTypeSize(sendingHintTypeSize)
            }
        }
    }

    /// isaCloud: while a "@" word is typed, the matching people of the group or channel; tapping one puts the nick in its place
    @ViewBuilder
    private var mentionSuggestions: some View {
        if let query = MentionAutocomplete.query(in: model.text) {
            let names = MentionAutocomplete.suggestions(for: query, nicks: mentionCandidates(), ownNick: nil)
            if !names.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(names, id: \.self) { nick in
                            Button {
                                model.setText(MentionAutocomplete.replacing(query: query, with: nick, in: model.text))
                            } label: {
                                Text(nick)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    private var attachMenu: some View {
        Menu {
            Button {
                onAttachPhotos()
            } label: {
                Label("Photos and videos", systemImage: "photo.on.rectangle")
            }
            //isaCloud: always offered; without an image on the clipboard it explains why nothing is attached
            Button {
                if UIPasteboard.general.hasImages {
                    onPasteImage()
                } else {
                    showNoClipboardImage = true
                }
            } label: {
                Label("Paste from clipboard", systemImage: "photo.on.rectangle")
            }
            Button {
                onAttachFile()
            } label: {
                Label("File", systemImage: "doc")
            }
            Button {
                onSearchGif()
            } label: {
                Label("GIF", systemImage: "play.rectangle")
            }
            Button {
                onShareLocation()
            } label: {
                Label("Location", systemImage: "location")
            }
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 20))
                .foregroundStyle(Color("isaCloudPink"))
                .frame(width: 36, height: 36)
                .accessibilityLabel("attach")
        }
        .alert("No image on the clipboard", isPresented: $showNoClipboardImage) {
            Button("OK", role: .cancel) {}
        }
    }

    private var inputField: some View {
        HStack(alignment: .bottom, spacing: 0) {
            TextField("Type a message...", text: textBinding, axis: .vertical)
                .padding(.vertical, 10)
                .padding(.leading, 12)
            if !model.text.isEmpty {
                clearTextButton
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    /// shown in place of the text field while a voice message is recorded
    private var recordingStrip: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text(Self.formatted(model.recordingElapsed))
                    .font(.body.monospacedDigit())
            }
            Spacer()
            if model.recording == .holding {
                Text("Release to send")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    model.discardRecording()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Delete recording")
                .accessibilityIdentifier("deleteRecording")
                Button {
                    model.togglePauseRecording()
                } label: {
                    Image(systemName: model.recording == .paused ? "play.fill" : "pause.fill")
                        .foregroundStyle(Color("isaCloudPink"))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(model.recording == .paused ? "Resume recording" : "Pause recording")
                Button {
                    if let url = model.finishRecording() {
                        onSendRecording(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color("isaCloudPink"))
                }
                .accessibilityLabel("Send recording")
                .accessibilityIdentifier("sendRecording")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private static func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// the microphone starts a voice message on touch down; a long press sends it on release, a short tap keeps it recording
    private var micGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard pressStart == nil else {
                    return
                }
                pressStart = Date()
                beginRecording(holding: true)
            }
            .onEnded { _ in
                let longPress = pressStart.map { Date().timeIntervalSince($0) >= 0.3 } ?? false
                pressStart = nil
                if let url = model.releaseMicrophone(afterLongPress: longPress) {
                    onSendRecording(url)
                }
            }
    }

    private func beginRecording(holding: Bool) {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            _ = model.startRecording(holding: holding)
        case .denied:
            showMicrophoneDenied = true
        default:
            // asked for the first time; the recording starts locked, because the finger may already be up
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        _ = model.startRecording(holding: false)
                    } else {
                        showMicrophoneDenied = true
                    }
                }
            }
        }
    }

    private var micButton: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 18))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Color("isaCloudPink"), in: Circle())
            .contentShape(Circle())
            .accessibilityLabel("microphone")
            .accessibilityAddTraits(.isButton)
            .gesture(micGesture)
            .alert("Microphone access is off", isPresented: $showMicrophoneDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Allow isaCloud to use the microphone in Settings to send voice messages.")
            }
    }

    @ViewBuilder
    private var trailingButton: some View {
        //isaCloud: the microphone is ALWAYS the first child of this HStack, in the same position, and only the button after it
        //changes. The first version swapped the whole branch when the recording started (trailingAction goes from .send to
        //.microphone), which tore down the view under the finger: the drag ended at once and the app sent an empty audio before
        //the person could record (seen on 28/10/2026). Keep the microphone's identity stable; changing its branch again breaks it.
        HStack(spacing: 8) {
            if model.edit == nil {
                micButton
            }
            switch model.trailingAction {
            case .send:
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color("isaCloudPink"), in: Circle())
                }
                .accessibilityLabel("arrowSend")
            case .saveEdit:
                Button(action: onSaveEdit) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color("isaCloudPink"), in: Circle())
                }
                .accessibilityIdentifier("checkmark")
            case .microphone:
                EmptyView()
            }
        }
    }

    private var clearTextButton: some View {
        Button {
            model.setText("")
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Clear text")
        .accessibilityIdentifier("clearTextButton")
    }

    private var editBanner: some View {
        HStack {
            Image(systemName: "pencil")
                .foregroundStyle(Color("isaCloudPink"))
            Text("Editing message")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onCancelEdit) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Cancel edit")
        }
        .padding(.horizontal, 12)
    }

    private var attachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.attachments.enumerated()), id: \.offset) { index, attachment in
                    ZStack(alignment: .topTrailing) {
                        attachmentPreview(attachment)
                        Button {
                            onRemoveAttachment(index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .accessibilityLabel("Remove attachment")
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func attachmentPreview(_ attachment: ChatInputAttachment) -> some View {
        if attachment.kind == .file {
            VStack(spacing: 4) {
                Image(systemName: "doc.fill")
                    .font(.title2)
                Text(attachment.url.lastPathComponent)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 80)
            }
            .frame(width: 80, height: 64)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        } else {
            Image(uiImage: thumbnail(for: attachment.url))
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func thumbnail(for url: URL) -> UIImage {
        return UIImage(contentsOfFile: url.path) ?? UIImage(systemName: "photo") ?? UIImage()
    }
}

/// isaCloud: while a file is uploaded to be sent, a capsule floating above the input says so (the top spinner alone is easy to miss).
/// It is filled with the chat background color (white, black in dark mode), with a soft shadow, and takes no room in the layout.
/// Its text follows the text size of the chat, which the caller sets with `dynamicTypeSize`.
private struct SendingHint: View {
    /// how far above the top of the bar the capsule floats (its height plus a gap), scaled with the text size
    @ScaledMetric private var lift: CGFloat = 38

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Sending...")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(uiColor: .systemBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(Color(uiColor: .separator), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .offset(y: -lift)
        .allowsHitTesting(false)
    }
}
