//
//  ChatInputModel.swift
//  Monal
//
//  isaCloud: state of the chat input bar (text, reply, edit, attachments) without any UI,
//  so the rules can be tested. The input bar itself only renders this model.
//

import Foundation
import SwiftUI

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
    /// isaCloud: a video picked from the gallery or recorded by the camera is converted before its upload (see MLFiletransfer)
    var convertsVideo: Bool = false
}

/// isaCloud: which photo of a batch is being resized before its upload, out of how many photos the batch has
/// (isVideo: a video is being converted before its upload, shown as "Preparing video...")
struct ChatInputPreparing: Equatable {
    let current: Int
    let total: Int
    var isVideo: Bool = false
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
    /// isaCloud: the id of the photo, GIF or sticker the text quotes (sent as urn:isacloud:quote:0), nil when it quotes none
    var quotedMessageId: String? = nil
}

final class ChatInputModel: ObservableObject {
    @Published private(set) var text: String
    /// isaCloud: how many files of the chat are being uploaded to be sent; the input shows a hint while it is more than 0.
    /// A counter, not a flag: with two uploads at once, the first to finish used to hide the hint while the other was still going.
    @Published private(set) var uploadCount = 0
    /// isaCloud: a file of the share sheet outbox is being uploaded (kept apart from uploadCount, so the outbox does not interfere with the chat uploads)
    @Published private(set) var outboxUploading = false
    /// isaCloud: a file is being uploaded to be sent; the input shows a hint while it is
    var isUploading: Bool {
        uploadCount > 0 || outboxUploading
    }
    /// isaCloud: the photo being resized before its upload ("Preparing photo" in the hint, in place of "Sending"); nil when none is
    @Published private(set) var preparing: ChatInputPreparing?
    /// isaCloud: a short notice floating above the input (e.g. "Sticker saved"), in place of an alert; it goes away by itself
    @Published private(set) var notice: String?
    /// isaCloud: the notice is an error (shown in red with an exclamation mark)
    @Published private(set) var noticeIsError = false
    private var noticeToken = 0
    @Published private(set) var reply: ChatInputReply?
    /// isaCloud: the photo, GIF or sticker being quoted in the text (see quote), and the quote line it came with: the id is sent only
    /// while that line is still in the text
    private(set) var quotedMessageId: String?
    private var quoteLine: String?
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
        //isaCloud: a recording that barely started (a stray touch, or a gesture that ended by accident) would become an empty
        //voice message; throw the file away instead of sending it (a real "ok" takes more than that)
        let elapsed = recorder?.elapsed ?? 0
        recorder?.stop()
        resetRecording()
        if elapsed < 0.35 {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
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

    /// isaCloud: a file upload started (every beginUpload is matched by one endUpload)
    func beginUpload() {
        uploadCount += 1
    }

    /// isaCloud: a file upload finished, with success or failure
    func endUpload() {
        uploadCount = max(0, uploadCount - 1)
    }

    /// isaCloud: sets the photo being resized before its upload, or nil when none is being resized
    func setPreparing(_ value: ChatInputPreparing?) {
        preparing = value
    }

    /// isaCloud: the share sheet outbox says whether one of its files is being uploaded
    func setOutboxUploading(_ uploading: Bool) {
        outboxUploading = uploading
    }

    /// isaCloud: shows `text` above the input for `duration` seconds (a newer notice replaces an older one and gets its full time);
    /// `isError` shows it in red as a failure
    func showNotice(_ text: String, duration: TimeInterval = 2, isError: Bool = false) {
        noticeToken += 1
        let token = noticeToken
        withAnimation(.easeIn(duration: 0.15)) {
            notice = text
            noticeIsError = isError
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.noticeToken == token else {
                return
            }
            withAnimation(.easeOut(duration: 0.2)) {
                self.notice = nil
                self.noticeIsError = false
            }
        }
    }

    /// starts a reply by quoting a message: the quote line goes in front of the text, and the answer is written after it
    /// isaCloud: `quotedMessageId` is the id of the quoted photo, GIF or sticker (nil for any other message): the reply then carries it
    func quote(author: String?, text: String, quotedMessageId: String? = nil) {
        guard edit == nil else {
            return
        }
        let line = QuoteFormatting.quoteLine(author: author, text: text)
        self.text = self.text.isEmpty ? line + "\n" : line + "\n" + self.text
        self.quotedMessageId = quotedMessageId
        self.quoteLine = line
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
        clearQuote()
    }

    /// isaCloud: forgets the photo, GIF or sticker quoted in the text (the quote line itself stays where it is)
    private func clearQuote() {
        quotedMessageId = nil
        quoteLine = nil
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
        //isaCloud: the quoted id goes only while its quote line is still in the text (a quote the person deleted quotes nothing)
        var quoted: String? = nil
        if let quotedMessageId, let quoteLine, text.contains(quoteLine) {
            quoted = quotedMessageId
        }
        let draft = ChatInputDraft(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            reply: reply,
            attachments: attachments,
            quotedMessageId: quoted
        )
        text = ""
        reply = nil
        attachments = []
        clearQuote()
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

/// isaCloud: "@" suggestions while a mention is typed in a group or channel. The mention is plain text ("nick "),
/// so the other clients read it as before; no protocol change.
enum MentionAutocomplete {
    static let maxSuggestions = 8

    /// the name typed after the "@" that starts the last word, nil when the last word is not a mention being typed
    static func query(in text: String) -> String? {
        guard let word = text.components(separatedBy: .whitespacesAndNewlines).last, word.hasPrefix("@") else {
            return nil
        }
        return String(word.dropFirst())
    }

    /// the nicks containing the typed name (no accent or case difference), names starting with it first, without our own nick;
    /// a bare "@" offers everyone
    static func suggestions(for query: String, nicks: [String], ownNick: String?) -> [String] {
        let term = fold(query)
        let matching = Set(nicks.filter { $0 != ownNick && (term.isEmpty || fold($0).contains(term)) })
        return matching
            .sorted { lhs, rhs in
                let lhsStarts = fold(lhs).hasPrefix(term)
                let rhsStarts = fold(rhs).hasPrefix(term)
                if lhsStarts != rhsStarts {
                    return lhsStarts
                }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .prefix(maxSuggestions)
            .map { $0 }
    }

    /// the text with the "@name" at its end replaced by the nick and a comma, as the tap on an avatar does
    static func replacing(query: String, with nick: String, in text: String) -> String {
        return String(text.dropLast(query.count + 1)) + nick + ", "
    }

    private static func fold(_ string: String) -> String {
        return string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
