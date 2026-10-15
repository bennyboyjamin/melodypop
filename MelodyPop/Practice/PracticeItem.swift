import Foundation
import MelodyPopKit
import QuartzCore

/// Anything that can be practised with the shared lesson engine: a lesson or a song.
struct PracticeItem: Identifiable, Equatable {
    enum Kind: String { case lesson, song }
    var kind: Kind
    var id: Int
    var title: String
    var subtitle: String
    var tip: String
    var piece: Piece
    var mode: EvaluationMode
    var passAccuracy: Double
    var showFingers: Bool

    init(lesson: Lesson) {
        kind = .lesson
        id = lesson.id
        title = lesson.title
        subtitle = lesson.goal
        tip = lesson.tip
        piece = lesson.piece
        mode = lesson.mode
        passAccuracy = lesson.passAccuracy
        showFingers = lesson.showFingers
    }

    init(kind: Kind, id: Int, title: String, subtitle: String, tip: String, piece: Piece, mode: EvaluationMode, passAccuracy: Double = 0.7, showFingers: Bool = true) {
        self.kind = kind
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tip = tip
        self.piece = piece
        self.mode = mode
        self.passAccuracy = passAccuracy
        self.showFingers = showFingers
    }

    var requiresPolyphony: Bool { piece.hasSimultaneousNotes }

    func unavailableReason(for source: InputSource) -> String? {
        guard requiresPolyphony, !source.capabilities.polyphonic else { return nil }
        return "This piece has notes played together. The microphone can only follow one piano note at a time reliably, so switch to Connect My Keyboard or Play on Screen."
    }
}

/// CADisplayLink with a closure.
final class FrameTicker: NSObject {
    private var link: CADisplayLink?
    private let onTick: () -> Void

    init(onTick: @escaping () -> Void) {
        self.onTick = onTick
    }

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(step))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step() { onTick() }

    deinit { link?.invalidate() }
}
