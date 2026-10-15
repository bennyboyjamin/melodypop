import Foundation

/// The three ways a student can play.
public enum InputSource: String, Codable, Sendable, CaseIterable, Identifiable {
    case microphone   // "Listen to My Piano"
    case midi         // "Connect My Keyboard"
    case touch        // "Play on Screen"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .microphone: return "Listen to My Piano"
        case .midi: return "Connect My Keyboard"
        case .touch: return "Play on Screen"
        }
    }

    public var shortTitle: String {
        switch self {
        case .microphone: return "Real Piano"
        case .midi: return "MIDI Piano"
        case .touch: return "Virtual Piano"
        }
    }

    /// What each source can and cannot report reliably.
    public var capabilities: InputCapabilities {
        switch self {
        case .microphone:
            // Monophonic pitch tracking. Note-off is inferred from the sound fading (or a new note
            // starting), not from the key being released, and a held sustain pedal hides it entirely.
            return InputCapabilities(polyphonic: false, reliableNoteOff: false, reportsVelocity: false, latencyCompensation: 0.07)
        case .midi:
            return InputCapabilities(polyphonic: true, reliableNoteOff: true, reportsVelocity: true, latencyCompensation: 0.005)
        case .touch:
            return InputCapabilities(polyphonic: true, reliableNoteOff: true, reportsVelocity: true, latencyCompensation: 0.015)
        }
    }
}

public struct InputCapabilities: Equatable, Sendable {
    /// Can several simultaneous notes (chords) be reported accurately?
    public var polyphonic: Bool
    /// Does note-off mean the key was actually released?
    public var reliableNoteOff: Bool
    public var reportsVelocity: Bool
    /// Seconds subtracted from event timestamps to compensate for capture/analysis latency.
    public var latencyCompensation: TimeInterval

    public init(polyphonic: Bool, reliableNoteOff: Bool, reportsVelocity: Bool, latencyCompensation: TimeInterval) {
        self.polyphonic = polyphonic
        self.reliableNoteOff = reliableNoteOff
        self.reportsVelocity = reportsVelocity
        self.latencyCompensation = latencyCompensation
    }
}

/// A normalized note event. All sources produce these, and everything downstream
/// (lesson engine, scoring, recording, highlighting) consumes only these.
public struct NoteEvent: Equatable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable { case noteOn, noteOff }

    public var kind: Kind
    public var pitch: Pitch
    /// 0...1
    public var velocity: Float
    /// Seconds on the monotonic host clock (same base as `ProcessInfo.systemUptime`).
    public var time: TimeInterval
    public var source: InputSource
    /// 0...1. Always 1 for MIDI and touch; pitch-tracking confidence for the microphone.
    public var confidence: Float
    /// True when the source guessed this event (microphone note-offs).
    public var isInferred: Bool

    public init(kind: Kind, pitch: Pitch, velocity: Float = 0.8, time: TimeInterval, source: InputSource, confidence: Float = 1, isInferred: Bool = false) {
        self.kind = kind
        self.pitch = pitch
        self.velocity = velocity
        self.time = time
        self.source = source
        self.confidence = confidence
        self.isInferred = isInferred
    }

    /// Timestamp adjusted for the source's known latency.
    public var compensatedTime: TimeInterval { time - source.capabilities.latencyCompensation }
}

/// Every play mode implements this. Concrete inputs live in the app target because they
/// depend on AVFoundation, Core MIDI and UIKit; the protocol and event model live here.
public protocol PianoInput: AnyObject {
    var source: InputSource { get }
    var capabilities: InputCapabilities { get }
    var isRunning: Bool { get }
    /// Called on the main thread for every normalized event.
    var onEvent: ((NoteEvent) -> Void)? { get set }
    func start() throws
    func stop()
}

public extension PianoInput {
    var capabilities: InputCapabilities { source.capabilities }
}

public enum MonotonicClock {
    public static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
