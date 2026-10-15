import Foundation

/// Turns a stream of per-frame pitch estimates from the microphone into note-on / note-off events.
///
/// What it can do reliably (and what the lessons rely on):
/// * Detect the onset and pitch of single notes played one at a time.
/// * Detect a repeated note when it is re-struck (energy jumps back up).
///
/// What it cannot infer, and why:
/// * **Key release.** An acoustic piano note keeps sounding after the key is lifted only if the
///   sustain pedal is down, and otherwise fades over a second or more. The microphone only hears
///   the sound, so a note-off here means "the sound faded below the gate or a different note took
///   over" — events are marked `isInferred`. Lessons never grade note length in microphone mode.
/// * **Chords / polyphony.** YIN finds one fundamental. With several strings sounding it reports
///   one of them (often the lowest or loudest). Chord lessons therefore require MIDI or the
///   on-screen piano.
public struct NoteSegmenter {
    public struct Configuration: Sendable {
        /// Minimum YIN confidence to accept a frame as pitched.
        public var minConfidence: Double = 0.85
        /// RMS level below which everything is treated as silence (set from calibration).
        public var noiseGate: Double = 0.01
        /// Consecutive frames that must agree on a pitch before a note-on is emitted.
        public var stableFrames: Int = 2
        /// Maximum deviation (semitones) for frames to count as the same pitch.
        public var pitchTolerance: Double = 0.45
        /// Energy rise (ratio over the recent minimum) that counts as a re-strike of the same note.
        public var reattackRatio: Double = 1.8
        /// The note ends when its level falls to this fraction of its peak.
        public var releaseFraction: Double = 0.06
        /// Unpitched frames tolerated inside a note before ending it.
        public var dropoutFrames: Int = 4
        /// Minimum time between two onsets of the same pitch (prevents one strike counting twice).
        public var minReattackInterval: TimeInterval = 0.15
        public init() {}
    }

    public var configuration: Configuration
    public private(set) var currentPitch: Pitch?

    private var candidate: Pitch?
    private var candidateCount = 0
    private var candidateStart: TimeInterval = 0
    private var candidateConfidence: Double = 0
    private var notePeak: Double = 0
    private var recentMin: Double = .infinity
    private var dropout = 0
    private var lastRMS: Double = 0
    private var lastOnsetTime: TimeInterval = -.infinity

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public mutating func reset() {
        currentPitch = nil
        candidate = nil
        candidateCount = 0
        notePeak = 0
        recentMin = .infinity
        dropout = 0
        lastRMS = 0
        lastOnsetTime = -.infinity
    }

    /// Feed one analysis frame. `time` is the timestamp of the end of the analysis window.
    public mutating func process(_ estimate: PitchEstimate, at time: TimeInterval) -> [NoteEvent] {
        var events: [NoteEvent] = []
        let c = configuration
        let rms = estimate.rms
        defer { lastRMS = rms }
        let voiced = rms >= c.noiseGate && estimate.confidence >= c.minConfidence && estimate.frequency > 0
        let midiValue = estimate.midiValue ?? 0
        let framePitch: Pitch? = voiced ? Pitch(Int(midiValue.rounded())) : nil
        let inTune = voiced && abs(midiValue - midiValue.rounded()) <= c.pitchTolerance

        // 1. End the current note when the sound fades or pitch tracking drops out.
        if let current = currentPitch {
            notePeak = max(notePeak, rms)
            recentMin = min(recentMin, rms)
            let faded = rms < c.noiseGate || rms < notePeak * c.releaseFraction
            if framePitch == current { dropout = 0 } else { dropout += 1 }
            if faded || dropout > c.dropoutFrames {
                events.append(noteOff(current, at: time))
                currentPitch = nil
            } else if framePitch == current, inTune, recentMin < .infinity, rms > recentMin * c.reattackRatio, rms > lastRMS * 1.3, time - lastOnsetTime >= c.minReattackInterval {
                // 2. Same pitch struck again: energy jumped after decaying.
                events.append(noteOff(current, at: time))
                events.append(NoteEvent(kind: .noteOn, pitch: current, velocity: velocity(for: rms), time: time, source: .microphone, confidence: Float(estimate.confidence)))
                notePeak = rms
                recentMin = rms
                lastOnsetTime = time
                candidate = nil
                return events
            }
        }

        // 3. Track a candidate for a new note.
        guard let p = framePitch, inTune else {
            candidate = nil
            candidateCount = 0
            return events
        }
        if p == currentPitch { candidate = nil; candidateCount = 0; return events }
        if p == candidate {
            candidateCount += 1
            candidateConfidence = min(candidateConfidence, estimate.confidence)
        } else {
            candidate = p
            candidateCount = 1
            candidateStart = time
            candidateConfidence = estimate.confidence
        }
        if candidateCount >= c.stableFrames {
            if let current = currentPitch { events.append(noteOff(current, at: candidateStart)) }
            currentPitch = p
            notePeak = rms
            recentMin = rms
            dropout = 0
            lastOnsetTime = time
            events.append(NoteEvent(kind: .noteOn, pitch: p, velocity: velocity(for: rms), time: candidateStart, source: .microphone, confidence: Float(candidateConfidence)))
            candidate = nil
            candidateCount = 0
        }
        return events
    }

    /// Flushes a sounding note (e.g. when the microphone stops).
    public mutating func finish(at time: TimeInterval) -> [NoteEvent] {
        guard let current = currentPitch else { return [] }
        currentPitch = nil
        return [noteOff(current, at: time)]
    }

    private func noteOff(_ p: Pitch, at time: TimeInterval) -> NoteEvent {
        NoteEvent(kind: .noteOff, pitch: p, velocity: 0, time: time, source: .microphone, confidence: 1, isInferred: true)
    }

    private func velocity(for rms: Double) -> Float {
        // Rough loudness → velocity mapping; only used for display, never for grading.
        let db = 20 * log10(max(rms, 1e-6))
        return Float(max(0.1, min(1, (db + 50) / 40)))
    }
}

/// Measures ambient noise so the gate sits safely above the room's background level.
public struct NoiseCalibrator {
    private var levels: [Double] = []
    public init() {}
    public mutating func add(rms: Double) { levels.append(rms) }
    public var sampleCount: Int { levels.count }
    /// 90th-percentile ambient level × 3, never below a floor of 0.004 (≈ −48 dBFS).
    public var recommendedGate: Double {
        guard !levels.isEmpty else { return 0.01 }
        let sorted = levels.sorted()
        let p90 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))]
        return max(0.004, p90 * 3)
    }
}
