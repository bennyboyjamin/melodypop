import MelodyPopKit
import UIKit

/// Multitouch piano keyboard. UIKit is used (rather than SwiftUI gestures) so every finger is tracked
/// independently: chords, glissandos (sliding across keys), and the same key held by two fingers.
final class KeyboardUIView: UIView {
    var onKeyDown: ((Int, Float, TimeInterval) -> Void)?
    var onKeyUp: ((Int, TimeInterval) -> Void)?

    var range: ClosedRange<Int> = Pitch.pianoRange { didSet { if range != oldValue { relayout() } } }
    var visibleWhiteKeys: Double = 14 { didSet { if visibleWhiteKeys != oldValue { relayout() } } }
    var scrollOffset: Double = 23 { didSet { if scrollOffset != oldValue { layoutModel.scrollOffset = scrollOffset; refresh() } } }
    /// Keys sounding from any source (touch, MIDI, microphone).
    var pressed: Set<Int> = [] { didSet { if pressed != oldValue { setNeedsDisplay() } } }
    /// Keys the lesson wants next.
    var hinted: Set<Int> = [] { didSet { if hinted != oldValue { setNeedsDisplay() } } }
    var showLabels = true { didSet { if showLabels != oldValue { setNeedsDisplay() } } }
    var isPlayable = true {
        didSet { if !isPlayable { releaseAllTouches(at: CACurrentMediaTime()) } }
    }

    private(set) var layoutModel = KeyboardLayout(whiteKeyWidth: 40, height: 200)
    private var touchKeys: [ObjectIdentifier: Int] = [:]
    private var holdCounts: [Int: Int] = [:]
    private var accessibilityKeys: [UIAccessibilityElement] = []

    // Colors
    private let whiteKey = UIColor(hex: 0xFFFDF8)
    private let whiteKeyEdge = UIColor(hex: 0xE6DCC8)
    private let blackKey = UIColor(hex: 0x3B2F5E)
    private let pressedWhite = UIColor(hex: 0xB9A5F2)
    private let pressedBlack = UIColor(hex: 0x8C74E0)
    private let hintWhite = UIColor(hex: 0xFFC6A6)
    private let hintBlack = UIColor(hex: 0xE4774A)
    private let labelColor = UIColor(hex: 0x7A6F99)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        backgroundColor = UIColor(hex: 0x3B2F5E)
        contentMode = .redraw
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        relayout()
    }

    private func relayout() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        layoutModel = KeyboardLayout(range: range, whiteKeyWidth: Double(bounds.width) / visibleWhiteKeys, height: Double(bounds.height), scrollOffset: scrollOffset)
        refresh()
    }

    private func refresh() {
        setNeedsDisplay()
        rebuildAccessibility()
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let visible = layoutModel.visibleKeys(viewWidth: Double(bounds.width))
        let whites = visible.filter { !Pitch($0).isBlackKey }
        let blacks = visible.filter { Pitch($0).isBlackKey }
        let radius = min(10, CGFloat(layoutModel.whiteKeyWidth) * 0.18)

        for m in whites {
            let r = cgRect(layoutModel.frame(for: m)).insetBy(dx: 1, dy: 0)
            let path = UIBezierPath(roundedRect: r, byRoundingCorners: [.bottomLeft, .bottomRight], cornerRadii: CGSize(width: radius, height: radius))
            let fill = pressed.contains(m) ? pressedWhite : hinted.contains(m) ? hintWhite : whiteKey
            fill.setFill()
            path.fill()
            whiteKeyEdge.setStroke()
            path.lineWidth = 1
            path.stroke()
            if pressed.contains(m) {
                // Pressed keys "sink" a little.
                UIColor(white: 0, alpha: 0.08).setFill()
                UIBezierPath(rect: CGRect(x: r.minX, y: r.minY, width: r.width, height: 6)).fill()
            }
            if showLabels || m == 60 {
                drawLabel(for: m, in: r, onBlack: false)
            }
        }
        for m in blacks {
            let r = cgRect(layoutModel.frame(for: m))
            let path = UIBezierPath(roundedRect: r, byRoundingCorners: [.bottomLeft, .bottomRight], cornerRadii: CGSize(width: radius * 0.6, height: radius * 0.6))
            let fill = pressed.contains(m) ? pressedBlack : hinted.contains(m) ? hintBlack : blackKey
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: UIColor(white: 0, alpha: 0.25).cgColor)
            fill.setFill()
            path.fill()
            ctx.restoreGState()
            UIColor(white: 1, alpha: 0.12).setFill()
            UIBezierPath(roundedRect: r.insetBy(dx: r.width * 0.18, dy: 3).offsetBy(dx: 0, dy: -2), cornerRadius: 3).fill()
            if showLabels && layoutModel.whiteKeyWidth >= 44 {
                drawLabel(for: m, in: r, onBlack: true)
            }
        }
    }

    private func drawLabel(for midi: Int, in r: CGRect, onBlack: Bool) {
        let p = Pitch(midi)
        let text = p.pitchClass == 0 ? p.fullName : p.name
        let size = max(9, min(15, r.width * 0.32))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: midi == 60 ? .heavy : .semibold).rounded,
            .foregroundColor: onBlack ? UIColor.white.withAlphaComponent(0.85) : (midi == 60 ? UIColor(hex: 0x6E55C8) : labelColor),
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let ts = s.size()
        s.draw(at: CGPoint(x: r.midX - ts.width / 2, y: r.maxY - ts.height - 8))
    }

    private func cgRect(_ k: KeyRect) -> CGRect {
        CGRect(x: k.x, y: k.y, width: k.width, height: k.height)
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isPlayable else { return }
        for t in touches {
            let p = t.location(in: self)
            guard let key = layoutModel.key(atX: Double(p.x), y: Double(p.y)) else { continue }
            touchKeys[ObjectIdentifier(t)] = key
            press(key, velocity: velocity(for: t, at: p, key: key), time: t.timestamp)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isPlayable else { return }
        for t in touches {
            let id = ObjectIdentifier(t)
            let p = t.location(in: self)
            let key = layoutModel.key(atX: Double(p.x), y: Double(p.y))
            let old = touchKeys[id]
            guard key != old else { continue }
            if let old { release(old, time: t.timestamp) }
            if let key {
                touchKeys[id] = key
                press(key, velocity: 0.6, time: t.timestamp) // glissando
            } else {
                touchKeys[id] = nil
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }

    private func end(_ touches: Set<UITouch>) {
        for t in touches {
            if let key = touchKeys.removeValue(forKey: ObjectIdentifier(t)) {
                release(key, time: t.timestamp)
            }
        }
    }

    private func press(_ key: Int, velocity: Float, time: TimeInterval) {
        let count = holdCounts[key, default: 0]
        holdCounts[key] = count + 1
        if count == 0 {
            onKeyDown?(key, velocity, time)
        }
    }

    private func release(_ key: Int, time: TimeInterval) {
        let count = holdCounts[key, default: 0]
        if count <= 1 {
            holdCounts[key] = nil
            if count == 1 { onKeyUp?(key, time) }
        } else {
            holdCounts[key] = count - 1
        }
    }

    func releaseAllTouches(at time: TimeInterval) {
        for key in holdCounts.keys { onKeyUp?(key, time) }
        holdCounts.removeAll()
        touchKeys.removeAll()
    }

    /// 3D-Touch force when available; otherwise how far down the key you press (like a real key, playing
    /// nearer the front is easier to play loudly).
    private func velocity(for touch: UITouch, at p: CGPoint, key: Int) -> Float {
        if touch.maximumPossibleForce > 0, touch.force > 0 {
            return Float(0.35 + 0.65 * min(1, touch.force / touch.maximumPossibleForce))
        }
        let h = Pitch(key).isBlackKey ? bounds.height * CGFloat(layoutModel.blackKeyHeightRatio) : bounds.height
        let depth = max(0, min(1, p.y / max(1, h)))
        return Float(0.45 + 0.5 * depth)
    }

    // MARK: Accessibility (VoiceOver + UI tests)

    private func rebuildAccessibility() {
        let visible = layoutModel.visibleKeys(viewWidth: Double(bounds.width))
        accessibilityKeys = visible.compactMap { m -> UIAccessibilityElement? in
            let p = Pitch(m)
            let k = p.isBlackKey ? layoutModel.frame(for: m) : layoutModel.uncoveredFrame(forWhite: m)
            let r = cgRect(k).intersection(bounds)
            guard r.width > 4 else { return nil }
            let e = UIAccessibilityElement(accessibilityContainer: self)
            e.accessibilityFrameInContainerSpace = r
            e.accessibilityIdentifier = "key-\(m)"
            e.accessibilityLabel = p.fullName
            e.accessibilityTraits = [.allowsDirectInteraction, .playsSound]
            return e
        }
    }

    override var accessibilityElements: [Any]? {
        get { accessibilityKeys }
        set {}
    }
}

private extension UIFont {
    var rounded: UIFont {
        guard let d = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: d, size: pointSize)
    }
}
