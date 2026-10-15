import Foundation
import MelodyPopKit

/// "Play on Screen": events come from `KeyboardUIView`'s multitouch handling.
final class TouchPianoInput: PianoInput {
    let source = InputSource.touch
    var onEvent: ((NoteEvent) -> Void)?
    private(set) var isRunning = false

    func start() throws { isRunning = true }
    func stop() { isRunning = false }

    func keyDown(_ midi: Int, velocity: Float, time: TimeInterval) {
        guard isRunning else { return }
        onEvent?(NoteEvent(kind: .noteOn, pitch: Pitch(midi), velocity: velocity, time: time, source: .touch))
    }

    func keyUp(_ midi: Int, time: TimeInterval) {
        guard isRunning else { return }
        onEvent?(NoteEvent(kind: .noteOff, pitch: Pitch(midi), velocity: 0, time: time, source: .touch))
    }
}
