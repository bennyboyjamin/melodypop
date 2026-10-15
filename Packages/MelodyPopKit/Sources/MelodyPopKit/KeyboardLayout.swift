import Foundation

public struct KeyRect: Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var maxX: Double { x + width }
    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px < x + width && py >= y && py < y + height
    }
}

/// Geometry of an 88-key (or any sub-range) piano keyboard, independent of UIKit.
/// `scrollOffset` is measured in white keys from the leftmost key of the range, so the
/// visible window can be scrolled smoothly and snapped to octaves.
public struct KeyboardLayout: Equatable, Sendable {
    public var range: ClosedRange<Int>
    public var whiteKeyWidth: Double
    public var height: Double
    public var blackKeyHeightRatio: Double = 0.62
    public var blackKeyWidthRatio: Double = 0.58
    public var scrollOffset: Double = 0

    public init(range: ClosedRange<Int> = Pitch.pianoRange, whiteKeyWidth: Double, height: Double, scrollOffset: Double = 0) {
        precondition(!Pitch(range.lowerBound).isBlackKey && !Pitch(range.upperBound).isBlackKey, "range must start and end on white keys")
        self.range = range
        self.whiteKeyWidth = whiteKeyWidth
        self.height = height
        self.scrollOffset = scrollOffset
    }

    public static func whiteKeyCount(in range: ClosedRange<Int>) -> Int {
        range.filter { !Pitch($0).isBlackKey }.count
    }

    public var whiteKeyCount: Int { KeyboardLayout.whiteKeyCount(in: range) }
    public var blackKeyCount: Int { range.count - whiteKeyCount }
    public var totalWidth: Double { Double(whiteKeyCount) * whiteKeyWidth }

    /// Index of a white key counted from the lowest key in the range; for black keys, the white key to its left.
    public func whiteIndex(of midi: Int) -> Int {
        var count = 0
        for m in range.lowerBound..<midi where !Pitch(m).isBlackKey { count += 1 }
        return Pitch(midi).isBlackKey ? count - 1 : count
    }

    /// MIDI number of the n-th white key in the range.
    public func midiForWhiteIndex(_ index: Int) -> Int? {
        var count = 0
        for m in range where !Pitch(m).isBlackKey {
            if count == index { return m }
            count += 1
        }
        return nil
    }

    /// Black keys sit slightly off-centre on the boundary, like a real keyboard.
    static func blackKeyShift(pitchClass: Int) -> Double {
        switch pitchClass {
        case 1: return -0.12  // C♯
        case 3: return 0.12   // D♯
        case 6: return -0.15  // F♯
        case 8: return 0      // G♯
        case 10: return 0.15  // A♯
        default: return 0
        }
    }

    /// Frame in view coordinates (already shifted by `scrollOffset`).
    public func frame(for midi: Int) -> KeyRect {
        let p = Pitch(midi)
        let originX = -scrollOffset * whiteKeyWidth
        if p.isBlackKey {
            let w = whiteKeyWidth * blackKeyWidthRatio
            let boundary = Double(whiteIndex(of: midi) + 1) * whiteKeyWidth
            let centre = boundary + KeyboardLayout.blackKeyShift(pitchClass: p.pitchClass) * w
            return KeyRect(x: originX + centre - w / 2, y: 0, width: w, height: height * blackKeyHeightRatio)
        }
        return KeyRect(x: originX + Double(whiteIndex(of: midi)) * whiteKeyWidth, y: 0, width: whiteKeyWidth, height: height)
    }

    /// The part of a white key not covered by black keys (used for accessibility and labels).
    public func uncoveredFrame(forWhite midi: Int) -> KeyRect {
        let f = frame(for: midi)
        let top = height * blackKeyHeightRatio
        return KeyRect(x: f.x, y: top, width: f.width, height: height - top)
    }

    /// Hit-test in view coordinates. Black keys win where they overlap white keys.
    public func key(atX x: Double, y: Double) -> Int? {
        guard y >= 0, y < height else { return nil }
        let originX = -scrollOffset * whiteKeyWidth
        let local = (x - originX) / whiteKeyWidth
        guard local >= 0 else { return nil }
        let idx = Int(local)
        guard let white = midiForWhiteIndex(idx) else { return nil }
        if y < height * blackKeyHeightRatio {
            for candidate in [white - 1, white + 1] where range.contains(candidate) && Pitch(candidate).isBlackKey {
                if frame(for: candidate).contains(x: x, y: y) { return candidate }
            }
        }
        return white
    }

    /// MIDI notes whose frames intersect the visible width.
    public func visibleKeys(viewWidth: Double) -> [Int] {
        range.filter { m in
            let f = frame(for: m)
            return f.maxX > 0 && f.x < viewWidth
        }
    }

    public var maxScrollOffset: Double { max(0, Double(whiteKeyCount)) }

    public func clampedOffset(_ offset: Double, visibleWhiteKeys: Double) -> Double {
        min(max(0, offset), max(0, Double(whiteKeyCount) - visibleWhiteKeys))
    }

    /// Scroll offset that puts `midi` (snapped down to its C) at the left edge.
    public func offset(showingOctaveOf midi: Int, visibleWhiteKeys: Double) -> Double {
        let c = midi - Pitch(midi).pitchClass
        let anchor = max(range.lowerBound, c)
        let start = Pitch(anchor).isBlackKey ? anchor - 1 : anchor
        return clampedOffset(Double(whiteIndex(of: start)), visibleWhiteKeys: visibleWhiteKeys)
    }

    /// Scroll offset that centres the span lowest...highest in the visible window.
    public func offset(centering lowest: Int, _ highest: Int, visibleWhiteKeys: Double) -> Double {
        let lo = Double(whiteIndex(of: lowest))
        let hi = Double(whiteIndex(of: highest)) + 1
        let mid = (lo + hi) / 2
        return clampedOffset(mid - visibleWhiteKeys / 2, visibleWhiteKeys: visibleWhiteKeys)
    }
}
