import Foundation

/// A free-play performance: note events relative to the start of recording.
public struct PerformanceRecording: Codable, Equatable, Sendable {
    public struct Event: Codable, Equatable, Sendable {
        public var offset: TimeInterval
        public var kind: NoteEvent.Kind
        public var midi: Int
        public var velocity: Float
        public init(offset: TimeInterval, kind: NoteEvent.Kind, midi: Int, velocity: Float) {
            self.offset = offset; self.kind = kind; self.midi = midi; self.velocity = velocity
        }
    }

    public struct PedalEvent: Codable, Equatable, Sendable {
        public var offset: TimeInterval
        public var down: Bool
    }

    public var events: [Event]
    public var pedal: [PedalEvent]
    public var duration: TimeInterval

    public init(events: [Event] = [], pedal: [PedalEvent] = [], duration: TimeInterval = 0) {
        self.events = events
        self.pedal = pedal
        self.duration = duration
    }

    public var noteCount: Int { events.filter { $0.kind == .noteOn }.count }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> PerformanceRecording { try JSONDecoder().decode(PerformanceRecording.self, from: data) }
}

public struct PerformanceRecorder {
    public private(set) var isRecording = false
    private var startTime: TimeInterval = 0
    private var recording = PerformanceRecording()
    private var held = Set<Int>()

    public init() {}

    public mutating func start(at time: TimeInterval) {
        recording = PerformanceRecording()
        held.removeAll()
        startTime = time
        isRecording = true
    }

    public mutating func record(_ event: NoteEvent) {
        guard isRecording else { return }
        let offset = max(0, event.time - startTime)
        switch event.kind {
        case .noteOn: held.insert(event.pitch.midi)
        case .noteOff:
            guard held.remove(event.pitch.midi) != nil else { return }
        }
        recording.events.append(.init(offset: offset, kind: event.kind, midi: event.pitch.midi, velocity: event.velocity))
    }

    public mutating func recordPedal(down: Bool, at time: TimeInterval) {
        guard isRecording else { return }
        recording.pedal.append(.init(offset: max(0, time - startTime), down: down))
    }

    /// Stops and closes any notes still held so playback never hangs.
    public mutating func stop(at time: TimeInterval) -> PerformanceRecording {
        let offset = max(0, time - startTime)
        for m in held.sorted() {
            recording.events.append(.init(offset: offset, kind: .noteOff, midi: m, velocity: 0))
        }
        if recording.pedal.last?.down == true { recording.pedal.append(.init(offset: offset, down: false)) }
        held.removeAll()
        recording.duration = offset
        isRecording = false
        return recording
    }
}

/// Steps through a recording; the app calls `advance(to:)` from a display-link/timer and plays what it returns.
public struct PlaybackCursor {
    public let recording: PerformanceRecording
    private var noteIndex = 0
    private var pedalIndex = 0
    public init(recording: PerformanceRecording) { self.recording = recording }

    public var isAtEnd: Bool { noteIndex >= recording.events.count && pedalIndex >= recording.pedal.count }

    public mutating func advance(to offset: TimeInterval) -> (notes: [PerformanceRecording.Event], pedal: [PerformanceRecording.PedalEvent]) {
        var notes: [PerformanceRecording.Event] = []
        var pedal: [PerformanceRecording.PedalEvent] = []
        while noteIndex < recording.events.count && recording.events[noteIndex].offset <= offset {
            notes.append(recording.events[noteIndex]); noteIndex += 1
        }
        while pedalIndex < recording.pedal.count && recording.pedal[pedalIndex].offset <= offset {
            pedal.append(recording.pedal[pedalIndex]); pedalIndex += 1
        }
        return (notes, pedal)
    }
}
