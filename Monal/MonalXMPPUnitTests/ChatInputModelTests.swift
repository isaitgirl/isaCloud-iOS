//
//  ChatInputModelTests.swift
//  MonalXMPPUnitTests
//
//  Rules of the chat input bar: what is sent, the trailing button, replies, edits and attachments.
//

import Testing
import Foundation

struct ChatInputModelTests {

    @Test("empty input shows the microphone and cannot send")
    func emptyInput() {
        let model = ChatInputModel()
        #expect(model.canSend == false)
        #expect(model.trailingAction == .microphone)
        #expect(model.send() == nil)
    }

    @Test("whitespace only is not sendable")
    func whitespaceOnly() {
        let model = ChatInputModel()
        model.setText("  \n\t ")
        #expect(model.canSend == false)
        #expect(model.trailingAction == .microphone)
        #expect(model.send() == nil)
    }

    @Test("typed text shows the send button and sending trims it and clears the input")
    func typedTextSends() {
        let model = ChatInputModel()
        model.setText("  hello there \n")
        #expect(model.trailingAction == .send)

        let draft = model.send()
        #expect(draft == ChatInputDraft(text: "hello there", reply: nil, attachments: []))
        #expect(model.text == "")
        #expect(model.trailingAction == .microphone)
    }

    @Test("a draft text restores the input and shows the send button")
    func draftRestored() {
        let model = ChatInputModel(draftText: "saved draft")
        #expect(model.text == "saved draft")
        #expect(model.trailingAction == .send)
    }

    @Test("attachments alone are sendable and are part of the draft")
    func attachmentsOnly() {
        let model = ChatInputModel()
        let gif = ChatInputAttachment(kind: .animatedGif, url: URL(fileURLWithPath: "/tmp/cat.gif"))
        model.addAttachment(gif)
        #expect(model.canSend)
        #expect(model.trailingAction == .send)

        let draft = model.send()
        #expect(draft == ChatInputDraft(text: "", reply: nil, attachments: [gif]))
        #expect(model.attachments.isEmpty)
    }

    @Test("removing an attachment by index keeps the others and ignores invalid indexes")
    func removeAttachment() {
        let model = ChatInputModel()
        let first = ChatInputAttachment(kind: .image, url: URL(fileURLWithPath: "/tmp/a.jpg"))
        let second = ChatInputAttachment(kind: .file, url: URL(fileURLWithPath: "/tmp/b.pdf"))
        model.addAttachment(first)
        model.addAttachment(second)
        model.removeAttachment(at: 9)
        model.removeAttachment(at: 0)
        #expect(model.attachments == [second])
    }

    @Test("a reply is part of the next sent draft and is then cleared")
    func replyIsSent() {
        let model = ChatInputModel()
        model.startReply(to: "msg-1", previewText: "original")
        model.setText("answer")

        let draft = model.send()
        #expect(draft?.reply == ChatInputReply(messageId: "msg-1", previewText: "original"))
        #expect(model.reply == nil)
    }

    @Test("a reply can be cancelled before sending")
    func replyCancelled() {
        let model = ChatInputModel()
        model.startReply(to: "msg-1", previewText: "original")
        model.cancelReply()
        model.setText("plain")
        #expect(model.send()?.reply == nil)
    }

    @Test("editing loads the text, shows save, and saving returns the trimmed text")
    func editSaves() {
        let model = ChatInputModel()
        model.startEdit(of: "msg-2", text: "old text")
        #expect(model.text == "old text")
        #expect(model.trailingAction == .saveEdit)

        model.setText("  new text  ")
        let saved = model.saveEdit()
        #expect(saved?.messageId == "msg-2")
        #expect(saved?.text == "new text")
        #expect(model.text == "")
        #expect(model.trailingAction == .microphone)
    }

    @Test("while editing nothing is sent as a new message")
    func editingBlocksSend() {
        let model = ChatInputModel()
        model.startEdit(of: "msg-2", text: "old text")
        #expect(model.send() == nil)
        #expect(model.text == "old text")
    }

    @Test("an empty edit cannot be saved")
    func emptyEditNotSaved() {
        let model = ChatInputModel()
        model.startEdit(of: "msg-2", text: "old text")
        model.setText("   ")
        #expect(model.saveEdit() == nil)
        #expect(model.trailingAction == .saveEdit)
    }

    @Test("cancelling an edit clears the input and goes back to normal")
    func editCancelled() {
        let model = ChatInputModel()
        model.startEdit(of: "msg-2", text: "old text")
        model.cancelEdit()
        #expect(model.text == "")
        #expect(model.trailingAction == .microphone)
    }

    @Test("starting an edit drops the reply and the attachments")
    func editDropsReplyAndAttachments() {
        let model = ChatInputModel()
        model.startReply(to: "msg-1", previewText: "original")
        model.addAttachment(ChatInputAttachment(kind: .image, url: URL(fileURLWithPath: "/tmp/a.jpg")))
        model.startEdit(of: "msg-2", text: "old text")
        #expect(model.reply == nil)
        #expect(model.attachments.isEmpty)
    }

    @Test("replies and attachments cannot be added while editing")
    func editBlocksReplyAndAttachments() {
        let model = ChatInputModel()
        model.startEdit(of: "msg-2", text: "old text")
        model.startReply(to: "msg-1", previewText: "original")
        model.addAttachment(ChatInputAttachment(kind: .image, url: URL(fileURLWithPath: "/tmp/a.jpg")))
        #expect(model.reply == nil)
        #expect(model.attachments.isEmpty)
    }
}

/// Records nothing: keeps the calls and writes an empty file where the model asks for one.
private final class FakeAudioRecorder: ChatAudioRecording {
    var startedURL: URL?
    var isPaused = false
    var isStopped = false
    var failsToStart = false
    var elapsed: TimeInterval = 4

    func start(into url: URL) throws {
        if failsToStart {
            throw CocoaError(.fileWriteUnknown)
        }
        startedURL = url
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    func stop() {
        isStopped = true
    }
}

struct ChatInputRecordingTests {

    private func makeModel(_ recorder: FakeAudioRecorder) -> ChatInputModel {
        return ChatInputModel(makeRecorder: { recorder })
    }

    @Test("a tap on the microphone starts a locked recording")
    func tapStartsLocked() {
        let recorder = FakeAudioRecorder()
        let model = makeModel(recorder)
        #expect(model.startRecording(holding: false))
        #expect(model.recording == .locked)
        #expect(recorder.startedURL != nil)
    }

    @Test("a long press sends the recording when the finger is released")
    func longPressSends() throws {
        let recorder = FakeAudioRecorder()
        let model = makeModel(recorder)
        #expect(model.startRecording(holding: true))
        let url = try #require(model.releaseMicrophone(afterLongPress: true))
        #expect(url == recorder.startedURL)
        #expect(model.recording == nil)
        #expect(recorder.isStopped)
    }

    @Test("a short tap keeps the recording going after the finger is released")
    func shortTapKeepsRecording() {
        let recorder = FakeAudioRecorder()
        let model = makeModel(recorder)
        #expect(model.startRecording(holding: true))
        #expect(model.releaseMicrophone(afterLongPress: false) == nil)
        #expect(model.recording == .locked)
        #expect(recorder.isStopped == false)
    }

    @Test("releasing the microphone when not holding changes nothing")
    func releaseWithoutHoldIsIgnored() {
        let model = makeModel(FakeAudioRecorder())
        #expect(model.releaseMicrophone(afterLongPress: true) == nil)
        #expect(model.recording == nil)
    }

    @Test("pause and resume switch between locked and paused")
    func pauseAndResume() {
        let recorder = FakeAudioRecorder()
        let model = makeModel(recorder)
        #expect(model.startRecording(holding: false))
        model.togglePauseRecording()
        #expect(model.recording == .paused)
        #expect(recorder.isPaused)
        model.togglePauseRecording()
        #expect(model.recording == .locked)
        #expect(recorder.isPaused == false)
    }

    @Test("pause does nothing while the finger is still on the microphone")
    func pauseIgnoredWhileHolding() {
        let model = makeModel(FakeAudioRecorder())
        #expect(model.startRecording(holding: true))
        model.togglePauseRecording()
        #expect(model.recording == .holding)
    }

    @Test("finishing returns the file and ends the recording")
    func finishReturnsFile() throws {
        let recorder = FakeAudioRecorder()
        let model = makeModel(recorder)
        #expect(model.startRecording(holding: false))
        let url = try #require(model.finishRecording())
        #expect(url == recorder.startedURL)
        #expect(model.recording == nil)
        #expect(recorder.isStopped)
        #expect(model.finishRecording() == nil)
    }

    @Test("discarding deletes the file and ends the recording")
    func discardDeletesFile() throws {
        let recorder = FakeAudioRecorder()
        let model = makeModel(recorder)
        #expect(model.startRecording(holding: false))
        let url = try #require(recorder.startedURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        model.discardRecording()
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
        #expect(model.recording == nil)
        #expect(model.finishRecording() == nil)
    }

    @Test("only one recording at a time")
    func onlyOneRecording() {
        let model = makeModel(FakeAudioRecorder())
        #expect(model.startRecording(holding: false))
        #expect(model.startRecording(holding: true) == false)
        #expect(model.recording == .locked)
    }

    @Test("no recording while editing a message")
    func noRecordingWhileEditing() {
        let model = makeModel(FakeAudioRecorder())
        model.startEdit(of: "m1", text: "texto")
        #expect(model.startRecording(holding: false) == false)
        #expect(model.recording == nil)
    }

    @Test("a microphone that cannot start leaves no recording behind")
    func failedStartLeavesNothing() {
        let recorder = FakeAudioRecorder()
        recorder.failsToStart = true
        let model = makeModel(recorder)
        #expect(model.startRecording(holding: false) == false)
        #expect(model.recording == nil)
        #expect(model.trailingAction == .microphone)
    }

    @Test("while recording the trailing button stays the microphone")
    func trailingButtonWhileRecording() {
        let model = makeModel(FakeAudioRecorder())
        #expect(model.startRecording(holding: false))
        #expect(model.trailingAction == .microphone)
        #expect(model.recordingElapsed == 4)
    }
}
