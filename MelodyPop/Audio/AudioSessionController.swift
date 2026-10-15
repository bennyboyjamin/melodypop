import AVFoundation

/// Owns the shared AVAudioSession. Playback-only for touch/MIDI; play-and-record for the microphone.
enum AudioSessionController {
    enum Profile { case playback, listening }

    private(set) static var current: Profile?

    static func configure(_ profile: Profile) {
        guard profile != current else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            switch profile {
            case .playback:
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            case .listening:
                // .measurement turns off voice processing / AGC so the piano's pitch reaches us untouched.
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
            }
            try session.setPreferredIOBufferDuration(0.005) // ~5 ms for low-latency touches
            try session.setActive(true)
            current = profile
        } catch {
            print("Audio session configuration failed: \(error)")
        }
        PianoAudioEngine.shared.rebuild()
    }

    static func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    static var microphonePermissionDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }
}
