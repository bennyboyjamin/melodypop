import Foundation
import MelodyPopKit
import Observation

/// Routes the active `PianoInput` to sound, key highlighting, and whoever is listening
/// (a lesson, a game, the recorder). Switching modes never touches listeners, so a lesson
/// keeps its progress when the student changes how they play.
@Observable
@MainActor
final class PlayModeController {
    enum Status: Equatable {
        case starting
        case ready
        case needsSetup(String)
        case failed(String)

        var message: String? {
            switch self {
            case .needsSetup(let m), .failed(let m): return m
            default: return nil
            }
        }
    }

    private(set) var mode: InputSource
    private(set) var status: Status = .starting
    private(set) var pressedKeys: Set<Int> = []
    private(set) var lastNote: Pitch?
    private(set) var midiDevices: [String] = []
    private(set) var micMeter = MicrophonePianoInput.Meter()
    private(set) var sustain = false

    var playSoundForMIDI: Bool {
        didSet { UserDefaults.standard.set(playSoundForMIDI, forKey: Keys.midiSound) }
    }
    var volume: Float {
        didSet {
            PianoAudioEngine.shared.setVolume(volume)
            UserDefaults.standard.set(volume, forKey: Keys.volume)
        }
    }
    var micSensitivity: Double {
        didSet {
            mic.minConfidence = micSensitivity
            UserDefaults.standard.set(micSensitivity, forKey: Keys.micSensitivity)
        }
    }

    let touch = TouchPianoInput()
    let midi = MIDIPianoInput()
    let mic = MicrophonePianoInput()
    @ObservationIgnored private var listeners: [UUID: (NoteEvent) -> Void] = [:]
    @ObservationIgnored private var sustainListeners: [UUID: (Bool) -> Void] = [:]
    @ObservationIgnored private var heldTouchCounts: [Int: Int] = [:]

    enum Keys {
        static let mode = "playMode"
        static let midiSound = "playSoundForMIDI"
        static let volume = "pianoVolume"
        static let micSensitivity = "micSensitivity"
    }

    init(initialMode: InputSource? = nil) {
        let defaults = UserDefaults.standard
        mode = initialMode ?? InputSource(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .touch
        playSoundForMIDI = defaults.object(forKey: Keys.midiSound) as? Bool ?? true
        volume = defaults.object(forKey: Keys.volume) as? Float ?? 0.8
        micSensitivity = defaults.object(forKey: Keys.micSensitivity) as? Double ?? 0.85
        mic.minConfidence = micSensitivity
        PianoAudioEngine.shared.setVolume(volume)

        // All inputs call back on the main thread.
        touch.onEvent = { [weak self] e in MainActor.assumeIsolated { self?.handle(e) } }
        midi.onEvent = { [weak self] e in MainActor.assumeIsolated { self?.handle(e) } }
        mic.onEvent = { [weak self] e in MainActor.assumeIsolated { self?.handle(e) } }
        midi.onSustain = { [weak self] down in MainActor.assumeIsolated { self?.applySustain(down, fromUser: false) } }
        midi.onDevicesChanged = { [weak self] names in MainActor.assumeIsolated { self?.midiDevicesChanged(names) } }
        mic.onMeter = { [weak self] meter in MainActor.assumeIsolated { self?.micMeter = meter } }
    }

    // MARK: Listeners

    func addListener(_ handler: @escaping (NoteEvent) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = handler
        return id
    }

    func addSustainListener(_ handler: @escaping (Bool) -> Void) -> UUID {
        let id = UUID()
        sustainListeners[id] = handler
        return id
    }

    func removeListener(_ id: UUID) {
        listeners[id] = nil
        sustainListeners[id] = nil
    }

    // MARK: Mode switching

    func activateCurrentMode() async {
        await select(mode, force: true)
    }

    func select(_ newMode: InputSource, force: Bool = false) async {
        guard force || newMode != mode || status != .ready else { return }
        stopAll()
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: Keys.mode)
        status = .starting
        switch newMode {
        case .touch:
            AudioSessionController.configure(.playback)
            try? touch.start()
            status = .ready
        case .midi:
            AudioSessionController.configure(.playback)
            do {
                try midi.start()
                midiDevicesChanged(midi.deviceNames)
            } catch {
                status = .failed(error.localizedDescription)
            }
        case .microphone:
            guard await AudioSessionController.requestMicrophonePermission() else {
                status = .failed(MicrophonePianoInput.MicError.permissionDenied.localizedDescription)
                return
            }
            guard mode == .microphone else { return } // switched away while the prompt was up
            AudioSessionController.configure(.listening)
            do {
                try mic.start()
                status = .ready
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    private func stopAll() {
        touch.stop()
        midi.stop()
        mic.stop()
        pressedKeys.removeAll()
        heldTouchCounts.removeAll()
        PianoAudioEngine.shared.allNotesOff()
        if sustain { applySustain(false, fromUser: true) }
    }

    private func midiDevicesChanged(_ names: [String]) {
        midiDevices = names
        guard mode == .midi else { return }
        status = names.isEmpty
            ? .needsSetup("No keyboard found yet. Plug in a USB MIDI keyboard (use a USB-C or Lightning adapter) or pair a Bluetooth one.")
            : .ready
    }

    // MARK: Events

    /// Sustain from the on-screen pedal button (touch mode) or a MIDI pedal.
    func applySustain(_ down: Bool, fromUser: Bool) {
        guard sustain != down else { return }
        sustain = down
        PianoAudioEngine.shared.setSustain(down)
        sustainListeners.values.forEach { $0(down) }
    }

    func toggleSustain() { applySustain(!sustain, fromUser: true) }

    private func handle(_ event: NoteEvent) {
        guard event.source == mode else { return } // ignore stragglers from a mode we just left
        let midiNote = event.pitch.midi
        switch event.kind {
        case .noteOn:
            pressedKeys.insert(midiNote)
            lastNote = event.pitch
            if event.source == .touch || (event.source == .midi && playSoundForMIDI) {
                PianoAudioEngine.shared.noteOn(midiNote, velocity: event.velocity)
            }
        case .noteOff:
            pressedKeys.remove(midiNote)
            if event.source == .touch || (event.source == .midi && playSoundForMIDI) {
                PianoAudioEngine.shared.noteOff(midiNote)
            }
        }
        listeners.values.forEach { $0(event) }
    }

    /// Mutes microphone analysis while the app itself plays notes (demos, playback).
    func setAppPlaying(_ playing: Bool) {
        mic.isSuppressed = playing
    }
}
