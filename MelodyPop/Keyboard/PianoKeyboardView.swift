import MelodyPopKit
import SwiftUI

/// SwiftUI wrapper for `KeyboardUIView`.
struct PianoKeyboardView: UIViewRepresentable {
    var scrollOffset: Double
    var visibleWhiteKeys: Double
    var pressed: Set<Int>
    var hinted: Set<Int> = []
    var showLabels: Bool
    var isPlayable: Bool
    var onKeyDown: (Int, Float, TimeInterval) -> Void
    var onKeyUp: (Int, TimeInterval) -> Void

    func makeUIView(context: Context) -> KeyboardUIView {
        let v = KeyboardUIView()
        v.accessibilityIdentifier = "piano-keyboard"
        return v
    }

    func updateUIView(_ v: KeyboardUIView, context: Context) {
        v.onKeyDown = onKeyDown
        v.onKeyUp = onKeyUp
        v.visibleWhiteKeys = visibleWhiteKeys
        v.scrollOffset = scrollOffset
        v.pressed = pressed
        v.hinted = hinted
        v.showLabels = showLabels
        v.isPlayable = isPlayable
    }
}

/// Mini map of all 88 keys; drag or tap to scroll the keyboard.
struct KeyboardNavigator: View {
    @Binding var offset: Double
    var visibleWhiteKeys: Double
    var pressed: Set<Int>
    var hinted: Set<Int>

    private let layout = KeyboardLayout(whiteKeyWidth: 1, height: 1)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let unit = w / 52
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    for m in Pitch.pianoRange where !Pitch(m).isBlackKey {
                        let x = Double(layout.whiteIndex(of: m)) * unit
                        let r = CGRect(x: x + 0.5, y: 0, width: unit - 1, height: size.height)
                        let color: Color = pressed.contains(m) ? Theme.lavender : hinted.contains(m) ? Theme.peach : .white
                        ctx.fill(Path(r), with: .color(color))
                    }
                    for m in Pitch.pianoRange where Pitch(m).isBlackKey {
                        let x = Double(layout.whiteIndex(of: m) + 1) * unit - unit * 0.3
                        let r = CGRect(x: x, y: 0, width: unit * 0.6, height: size.height * 0.6)
                        let color: Color = pressed.contains(m) ? Theme.lavenderDeep : hinted.contains(m) ? Theme.peachDeep : Theme.ink
                        ctx.fill(Path(r), with: .color(color))
                    }
                }
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.mintDeep, lineWidth: 3)
                    .background(Theme.mint.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                    .frame(width: unit * visibleWhiteKeys, height: geo.size.height)
                    .offset(x: unit * offset)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let centre = value.location.x / unit
                offset = layout.clampedOffset(centre - visibleWhiteKeys / 2, visibleWhiteKeys: visibleWhiteKeys)
            })
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityIdentifier("keyboard-navigator")
        .accessibilityLabel("Keyboard position")
        .accessibilityValue(Pitch(layout.midiForWhiteIndex(Int(offset.rounded())) ?? 21).fullName)
        .accessibilityAdjustableAction { direction in
            let step: Double = direction == .increment ? 7 : -7
            offset = layout.clampedOffset(offset + step, visibleWhiteKeys: visibleWhiteKeys)
        }
    }
}
