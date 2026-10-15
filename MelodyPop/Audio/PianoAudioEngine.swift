import AVFoundation
import MelodyPopKit
import QuartzCore
import os

/// Host clock shared by touches (UITouch.timestamp), Core MIDI and AVAudioTime host times.
enum HostClock {
    static var now: TimeInterval { CACurrentMediaTime() }
    static func seconds(forHostTime t: UInt64) -> TimeInterval { AVAudioTime.seconds(forHostTime: t) }
}

/// Main-thread → audio-thread command hand-off. The audio thread only ever *tries* the lock,
/// so it never blocks; commands that miss a cycle are applied on the next one (~5 ms later).
final class SynthCommandQueue: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [PianoSynth.Command]())

    init() {
        lock.withLock { $0.reserveCapacity(1024) }
    }

    func push(_ command: PianoSynth.Command) {
        lock.withLock { $0.append(command) }
    }

    /// Audio thread.
    func drain(into synth: PianoSynth) {
        lock.withLockIfAvailable { pending in
            for c in pending { synth.apply(c) }
            pending.removeAll(keepingCapacity: true)
        }
    }
}

enum AudioEngineError: LocalizedError {
    case noSamples
    var errorDescription: String? { "The piano sounds could not be loaded." }
}

/// Plays the piano. One AVAudioEngine with an AVAudioSourceNode that renders `PianoSynth`.
final class PianoAudioEngine {
    static let shared = PianoAudioEngine()

    private let engine = AVAudioEngine()
    private let queue = SynthCommandQueue()
    private var sourceNode: AVAudioSourceNode?
    private var bank: SampleBank?
    private var scratch = UnsafeMutablePointer<Float>.allocate(capacity: 8192)
    private(set) var isRunning = false
    private(set) var lastError: Error?
    private var configObserver: NSObjectProtocol?
    private var volume: Float = 0.8

    private init() {
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.rebuild()
        }
    }

    /// Loads samples (once) and starts the engine. Safe to call repeatedly.
    func start() {
        do {
            if bank == nil { bank = try PianoAudioEngine.loadBank() }
            if sourceNode == nil { try attachSourceNode() }
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            isRunning = true
            lastError = nil
        } catch {
            // No audio device (e.g. a CI simulator) or an interrupted session: the app keeps working silently.
            isRunning = false
            lastError = error
            print("PianoAudioEngine start failed: \(error)")
        }
    }

    func stop() {
        engine.stop()
        isRunning = false
    }

    /// Called after the audio session category or route changes (sample rate may have changed).
    func rebuild() {
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        start()
    }

    private func attachSourceNode() throws {
        guard let bank, !bank.isEmpty else { throw AudioEngineError.noSamples }
        let hwFormat = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = hwFormat.sampleRate > 0 ? hwFormat.sampleRate : 48000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { throw AudioEngineError.noSamples }
        let synth = PianoSynth(bank: bank, outputSampleRate: sampleRate)
        synth.apply(.volume(volume))
        let queue = self.queue
        let scratch = self.scratch
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            queue.drain(into: synth)
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            var done = 0
            let total = Int(frameCount)
            while done < total {
                let n = min(8192, total - done)
                synth.render(into: scratch, frameCount: n)
                for buffer in buffers {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    (data + done).update(from: scratch, count: n)
                }
                done += n
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }

    static func loadBank(bundle: Bundle = .main) throws -> SampleBank {
        let urls = bundle.urls(forResourcesWithExtension: "wav", subdirectory: nil) ?? []
        var samples: [PianoSample] = []
        for url in urls {
            guard let info = SampleBank.parse(fileName: url.lastPathComponent) else { continue }
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { continue }
            try file.read(into: buffer)
            guard let ch = buffer.floatChannelData?[0] else { continue }
            let frames = Array(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))
            samples.append(PianoSample(rootMIDI: info.midi, layer: info.layer, frames: frames, sampleRate: file.processingFormat.sampleRate))
        }
        guard !samples.isEmpty else { throw AudioEngineError.noSamples }
        return SampleBank(samples: samples)
    }

    // MARK: Commands (any thread)

    func noteOn(_ midi: Int, velocity: Float) { queue.push(.noteOn(midi: midi, velocity: velocity)) }
    func noteOff(_ midi: Int) { queue.push(.noteOff(midi: midi)) }
    func setSustain(_ on: Bool) { queue.push(.sustain(on)) }
    func allNotesOff() { queue.push(.allNotesOff) }
    func click(accent: Bool) { queue.push(.click(accent: accent)) }
    func setVolume(_ v: Float) {
        volume = v
        queue.push(.volume(v))
    }
}
