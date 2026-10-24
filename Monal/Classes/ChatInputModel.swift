//
//  ChatInputModel.swift
//  Monal
//
//  isaCloud: state of the chat input bar (text, reply, edit, attachments) without any UI,
//  so the rules can be tested. The input bar itself only renders this model.
//

import Foundation

/// A voice message being recorded. Holding: the finger is still on the microphone. Locked: recording continues
/// without the finger, with the controls. Paused: locked and paused.
enum ChatRecordingState: Equatable {
    case holding
    case locked
    case paused
}

struct ChatInputReply: Equatable {
    let messageId: String
    let previewText: String
}

struct ChatInputEdit: Equatable {
    let messageId: String
}

struct ChatInputAttachment: Equatable {
    enum Kind: Equatable {
        case image
        case animatedGif
        case file
    }
    let kind: Kind
    let url: URL
}

/// What the trailing button of the input bar does right now.
enum ChatInputTrailingAction: Equatable {
    case microphone
    case send
    case saveEdit
}

/// The content handed to the chat when the user sends.
struct ChatInputDraft: Equatable {
    let text: String
    let reply: ChatInputReply?
    let attachments: [ChatInputAttachment]
}

final class ChatInputModel: ObservableObject {
    @Published private(set) var text: String
    @Published private(set) var reply: ChatInputReply?
    @Published private(set) var edit: ChatInputEdit?
    @Published private(set) var attachments: [ChatInputAttachment] = []
    @Published private(set) var recording: ChatRecordingState?

    private let makeRecorder: () -> ChatAudioRecording
    private var recorder: ChatAudioRecording?
    private var recordingURL: URL?

    init(draftText: String = "", makeRecorder: @escaping () -> ChatAudioRecording = { ChatAudioRecorder() }) {
        self.text = draftText
        self.makeRecorder = makeRecorder
    }

    /// Text is trimmed only to decide whether there is something to send; the sent text is trimmed too.
    private var hasText: Bool {
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSend: Bool {
        return hasText || !attachments.isEmpty
    }

    var trailingAction: ChatInputTrailingAction {
        if edit != nil {
            return .saveEdit
        }
        // while recording the microphone stays under the finger that started it
        if recording != nil {
            return .microphone
        }
        return canSend ? .send : .microphone
    }

    /// seconds of the voice message being recorded
    var recordingElapsed: TimeInterval {
        return recorder?.elapsed ?? 0
    }

    /// Starts a voice message. Returns false when one is already running, while editing, or when the microphone cannot start.
    func startRecording(holding: Bool) -> Bool {
        guard recording == nil, edit == nil else {
            return false
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let newRecorder = makeRecorder()
        do {
            try newRecorder.start(into: url)
        } catch {
            return false
        }
        recorder = newRecorder
        recordingURL = url
        recording = holding ? .holding : .locked
        return true
    }

    /// Called when the finger leaves the microphone. After a long press the message is sent; after a short tap it keeps recording.
    /// Returns the file to send when the recording ends here.
    func releaseMicrophone(afterLongPress: Bool) -> URL? {
        guard recording == .holding else {
            return nil
        }
        if afterLongPress {
            return finishRecording()
        }
        recording = .locked
        return nil
    }

    /// Pauses a locked recording, or resumes a paused one.
    func togglePauseRecording() {
        switch recording {
        case .locked:
            recorder?.pause()
            recording = .paused
        case .paused:
            recorder?.resume()
            recording = .locked
        case .holding, nil:
            break
        }
    }

    /// Stops the recording and returns its file, to be sent. Nil when nothing is being recorded.
    func finishRecording() -> URL? {
        guard recording != nil, let url = recordingURL else {
            return nil
        }
        recorder?.stop()
        resetRecording()
        return url
    }

    /// Stops the recording and deletes its file.
    func discardRecording() {
        guard recording != nil else {
            return
        }
        recorder?.stop()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        resetRecording()
    }

    private func resetRecording() {
        recorder = nil
        recordingURL = nil
        recording = nil
    }

    func setText(_ newText: String) {
        text = newText
    }

    func startReply(to messageId: String, previewText: String) {
        // replying while editing is not allowed: editing wins
        guard edit == nil else {
            return
        }
        reply = ChatInputReply(messageId: messageId, previewText: previewText)
    }

    func cancelReply() {
        reply = nil
    }

    func startEdit(of messageId: String, text: String) {
        edit = ChatInputEdit(messageId: messageId)
        self.text = text
        reply = nil
        attachments = []
    }

    func cancelEdit() {
        edit = nil
        text = ""
    }

    func addAttachment(_ attachment: ChatInputAttachment) {
        // attachments cannot be added while editing a text message
        guard edit == nil else {
            return
        }
        attachments.append(attachment)
    }

    func removeAttachment(at index: Int) {
        guard attachments.indices.contains(index) else {
            return
        }
        attachments.remove(at: index)
    }

    /// Returns what has to be sent, or nil when there is nothing to send. Clears the input on success.
    func send() -> ChatInputDraft? {
        guard canSend, edit == nil else {
            return nil
        }
        let draft = ChatInputDraft(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            reply: reply,
            attachments: attachments
        )
        text = ""
        reply = nil
        attachments = []
        return draft
    }

    /// Returns the edited text for the message being edited, or nil when not editing. Ends the edit.
    func saveEdit() -> (messageId: String, text: String)? {
        guard let edit, hasText else {
            return nil
        }
        let result = (messageId: edit.messageId, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        self.edit = nil
        text = ""
        return result
    }
}
