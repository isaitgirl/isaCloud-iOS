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
    var onSearchGif: () -> Void
    var onShareLocation: () -> Void
    var onRemoveAttachment: (Int) -> Void
    var onSendRecording: (URL) -> Void
    @State private var pressStart: Date?
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
    }

    private var attachMenu: some View {
        Menu {
            Button {
                onAttachPhotos()
            } label: {
                Label("Photos and videos", systemImage: "photo.on.rectangle")
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
        switch model.trailingAction {
        case .microphone:
            micButton
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
