import MelodyPopKit
import SwiftUI

/// Scrolling sheet music: treble staff, or a grand staff when the left hand plays.
/// Notes are coloured by how they were played; the current position is highlighted.
struct StaffView: View {
    var piece: Piece
    var targets: [TargetState]
    /// Timed mode: the beat under the playhead. Wait mode: nil (the active note is centred).
    var playheadBeat: Double?
    var showFingers: Bool

    private var grand: Bool { piece.usesBothHands || (piece.lowest?.midi ?? 60) < 55 }

    var body: some View {
        Canvas { ctx, size in
            draw(in: &ctx, size: size)
        }
        .accessibilityElement()
        .accessibilityIdentifier("staff")
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let active = targets.first(where: { $0.status != .done }) {
            return "Sheet music. Next: " + active.note.pitches.map(\.fullName).joined(separator: " and ")
        }
        return "Sheet music. All notes played."
    }

    // MARK: Geometry

    private struct Metrics {
        var ls: CGFloat          // line spacing
        var trebleBottom: CGFloat
        var bassBottom: CGFloat
        var pxPerBeat: CGFloat
        var left: CGFloat
    }

    private func metrics(_ size: CGSize) -> Metrics {
        let staves: CGFloat = grand ? 2 : 1
        // Each staff = 4 spaces; leave room for ledger lines (≈4 spaces) above/below and between.
        let ls = min(14, max(7, size.height / (staves * 4 + (grand ? 14 : 9))))
        let trebleBottom = (grand ? 5.5 : 5.5) * ls + 4 * ls
        let bassBottom = trebleBottom + 9 * ls
        return Metrics(ls: ls, trebleBottom: trebleBottom, bassBottom: bassBottom, pxPerBeat: ls * 6.5, left: ls * 5)
    }

    /// Treble bottom line = E4 (step 30); bass bottom line = G2 (step 18).
    private func y(step: Int, treble: Bool, _ m: Metrics) -> CGFloat {
        treble ? m.trebleBottom - CGFloat(step - 30) * m.ls / 2 : m.bassBottom - CGFloat(step - 18) * m.ls / 2
    }

    private func onTreble(_ note: ScoreNote) -> Bool {
        grand ? note.hand == .right : true
    }

    private func viewBeat(_ size: CGSize, _ m: Metrics) -> Double {
        let anchor = Double((size.width - m.left) * 0.3 / m.pxPerBeat)
        if let b = playheadBeat { return b - anchor }
        let active = targets.first(where: { $0.status != .done })?.note.startBeat ?? piece.totalBeats
        return max(0, active - anchor)
    }

    // MARK: Drawing

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let m = metrics(size)
        let ink = Theme.ink
        let lineColor = Theme.inkSoft.opacity(0.55)

        // Staff lines
        for treble in grand ? [true, false] : [true] {
            let bottom = treble ? m.trebleBottom : m.bassBottom
            for i in 0..<5 {
                let yy = bottom - CGFloat(i) * m.ls
                ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: yy)); p.addLine(to: CGPoint(x: size.width, y: yy)) }, with: .color(lineColor), lineWidth: 1)
            }
        }

        let vb = viewBeat(size, m)
        func x(_ beat: Double) -> CGFloat { m.left + CGFloat(beat - vb) * m.pxPerBeat }

        // Bar lines
        var bar = 0.0
        while bar <= piece.totalBeats {
            let bx = x(bar)
            if bx > m.left - 2 && bx < size.width {
                let top = m.trebleBottom - 4 * m.ls
                let bottom = grand ? m.bassBottom : m.trebleBottom
                ctx.stroke(Path { p in p.move(to: CGPoint(x: bx, y: top)); p.addLine(to: CGPoint(x: bx, y: bottom)) }, with: .color(lineColor), lineWidth: bar == piece.totalBeats ? 3 : 1)
            }
            bar += Double(piece.beatsPerBar)
        }

        // Playhead
        if let b = playheadBeat {
            let px = x(b)
            let top = m.trebleBottom - 6 * m.ls
            let bottom = (grand ? m.bassBottom : m.trebleBottom) + 2 * m.ls
            ctx.fill(Path(roundedRect: CGRect(x: px - 2, y: top, width: 4, height: bottom - top), cornerRadius: 2), with: .color(Theme.mint.opacity(0.9)))
        }

        let activeID = targets.first(where: { $0.status == .active })?.id ?? targets.first(where: { $0.status != .done })?.id

        for target in targets {
            let n = target.note
            let nx = x(n.startBeat)
            guard nx > m.left - m.ls * 2, nx < size.width + m.ls * 2 else { continue }
            let treble = onTreble(n)
            let color: Color
            switch target.grade {
            case .perfect?, .good?: color = Theme.mintDeep
            case .ok?, .partial?: color = Theme.peachDeep
            case .missed?: color = Theme.berry
            case nil: color = target.id == activeID ? Theme.lavenderDeep : ink
            }
            if target.id == activeID && playheadBeat == nil {
                let steps = n.pitches.map { y(step: $0.diatonicStep, treble: treble, m) }
                let top = (steps.min() ?? 0) - m.ls * 1.6
                let bottom = (steps.max() ?? 0) + m.ls * 1.6
                ctx.fill(Path(roundedRect: CGRect(x: nx - m.ls * 1.4, y: top, width: m.ls * 2.8, height: bottom - top), cornerRadius: m.ls), with: .color(Theme.lavender.opacity(0.3)))
            }
            drawNote(n, at: nx, treble: treble, color: color, in: &ctx, m)
        }

        // Clefs drawn last on a cream margin so scrolling notes slide underneath.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: m.left - m.ls * 0.6, height: size.height)), with: .color(Theme.cream))
        for treble in grand ? [true, false] : [true] {
            let bottom = treble ? m.trebleBottom : m.bassBottom
            for i in 0..<5 {
                let yy = bottom - CGFloat(i) * m.ls
                ctx.stroke(Path { p in p.move(to: CGPoint(x: m.ls * 0.5, y: yy)); p.addLine(to: CGPoint(x: m.left - m.ls * 0.6, y: yy)) }, with: .color(lineColor), lineWidth: 1)
            }
            let glyph = Text(treble ? "\u{1D11E}" : "\u{1D122}").font(.system(size: m.ls * (treble ? 6.4 : 3.6))).foregroundColor(ink)
            let cy = treble ? bottom - 1.6 * m.ls : bottom - 2.6 * m.ls
            ctx.draw(glyph, at: CGPoint(x: m.ls * 2.2, y: cy))
        }
    }

    private func drawNote(_ n: ScoreNote, at nx: CGFloat, treble: Bool, color: Color, in ctx: inout GraphicsContext, _ m: Metrics) {
        let ls = m.ls
        let steps = n.pitches.map(\.diatonicStep)
        let ys = steps.map { y(step: $0, treble: treble, m) }
        let hollow = n.beats >= 2
        let middleStep = treble ? 34 : 22 // B4 / D3
        let avgStep = Double(steps.reduce(0, +)) / Double(max(1, steps.count))
        let stemUp = avgStep < Double(middleStep)

        // Ledger lines
        let bottomLineStep = treble ? 30 : 18
        let topLineStep = bottomLineStep + 8
        for s in steps {
            if s < bottomLineStep {
                var l = bottomLineStep - 2
                while l >= s { ledger(at: y(step: l, treble: treble, m), nx, ls, &ctx); l -= 2 }
            } else if s > topLineStep {
                var l = topLineStep + 2
                while l <= s { ledger(at: y(step: l, treble: treble, m), nx, ls, &ctx); l += 2 }
            }
        }

        // Heads (chord seconds are nudged sideways)
        let sortedSteps = Array(zip(steps, ys)).sorted { $0.0 < $1.0 }
        var previous: Int?
        var shiftNext = false
        for (i, (s, yy)) in sortedSteps.enumerated() {
            if let p = previous, s - p == 1 { shiftNext.toggle() } else { shiftNext = false }
            previous = s
            let dx: CGFloat = shiftNext ? (stemUp ? ls * 1.2 : -ls * 1.2) : 0
            let head = CGRect(x: nx - ls * 0.65 + dx, y: yy - ls * 0.5, width: ls * 1.3, height: ls)
            var headPath = Path(ellipseIn: head)
            headPath = headPath.applying(CGAffineTransform(translationX: -head.midX, y: -head.midY).concatenating(CGAffineTransform(rotationAngle: -0.35)).concatenating(CGAffineTransform(translationX: head.midX, y: head.midY)))
            if hollow {
                ctx.stroke(headPath, with: .color(color), lineWidth: ls * 0.22)
            } else {
                ctx.fill(headPath, with: .color(color))
            }
            if n.pitches.sorted()[i].isSharp {
                ctx.draw(Text("♯").font(.system(size: ls * 1.6, weight: .bold)).foregroundColor(color), at: CGPoint(x: nx - ls * 1.6, y: yy))
            }
            if n.beats == 0.75 || n.beats == 1.5 || n.beats == 3 {
                ctx.fill(Path(ellipseIn: CGRect(x: nx + ls * 0.95, y: yy - ls * 0.18, width: ls * 0.36, height: ls * 0.36)), with: .color(color))
            }
        }

        // Stem + flag
        if n.beats < 4 {
            let sx = stemUp ? nx + ls * 0.6 : nx - ls * 0.6
            let from = stemUp ? (ys.max() ?? 0) : (ys.min() ?? 0)
            let to = stemUp ? (ys.min() ?? 0) - ls * 3.3 : (ys.max() ?? 0) + ls * 3.3
            ctx.stroke(Path { p in p.move(to: CGPoint(x: sx, y: from)); p.addLine(to: CGPoint(x: sx, y: to)) }, with: .color(color), lineWidth: max(1.2, ls * 0.13))
            if n.beats <= 0.75 {
                let dir: CGFloat = stemUp ? 1 : -1
                let flag = Path { p in
                    p.move(to: CGPoint(x: sx, y: to))
                    p.addQuadCurve(to: CGPoint(x: sx + ls * 0.9, y: to + dir * ls * 2.2), control: CGPoint(x: sx + ls * 1.1, y: to + dir * ls * 0.8))
                }
                ctx.stroke(flag, with: .color(color), lineWidth: max(1.5, ls * 0.2))
            }
        }

        // Finger number
        if showFingers, let f = n.finger {
            let yy = treble ? min((ys.min() ?? 0) - ls * 4.4, m.trebleBottom - 5.5 * ls) : (ys.max() ?? 0) + ls * 4.4
            ctx.draw(Text("\(f)").font(Theme.font(.caption, weight: .heavy)).foregroundColor(Theme.lavenderDeep), at: CGPoint(x: nx, y: yy))
        }
    }

    private func ledger(at yy: CGFloat, _ nx: CGFloat, _ ls: CGFloat, _ ctx: inout GraphicsContext) {
        ctx.stroke(Path { p in p.move(to: CGPoint(x: nx - ls * 1.1, y: yy)); p.addLine(to: CGPoint(x: nx + ls * 1.1, y: yy)) }, with: .color(Theme.inkSoft), lineWidth: 1)
    }
}
