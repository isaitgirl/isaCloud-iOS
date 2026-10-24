//
//  ChatAudioRecorder.swift
//  Monal
//
//  isaCloud: records a voice message to an AAC file. ChatInputModel talks to it through the protocol,
//  so the recording rules can be tested without a microphone.
//

import AVFoundation

protocol ChatAudioRecording: AnyObject {
    func start(into url: URL) throws
    func pause()
    func resume()
    func stop()
    /// seconds recorded so far; stays the same while paused
    var elapsed: TimeInterval { get }
}

final class ChatAudioRecorder: ChatAudioRecording {
    enum RecorderError: Error {
        case couldNotStart
    }

    private var recorder: AVAudioRecorder?

    func start(into url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 32000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.prepareToRecord(), recorder.record() else {
            throw RecorderError.couldNotStart
        }
        self.recorder = recorder
    }

    func pause() {
        recorder?.pause()
    }

    func resume() {
        recorder?.record()
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    var elapsed: TimeInterval {
        return recorder?.currentTime ?? 0
    }
}
