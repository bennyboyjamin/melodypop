import MelodyPopKit
import SwiftUI

/// Keyboard + its controls. Used by free play, every lesson, songs and games.
struct PianoPanel: View {
    @Environment(PlayModeController.self) private var play
    @Binding var offset: Double
    var hinted: Set<Int> = []
    var showControls = true
    /// When false, keys only display what the student plays on a real piano / MIDI keyboard.
    var interactive: Bool = true
    var onVisibleKeysChanged: ((Double) -> Void)? = nil

    @AppStorage("showNoteLabels") private var showLabels = true
    @AppStorage("keySize") private var keySize = 1
    @State private var showVolume = false
    @Environment(\.horizontalSizeClass) private var hSize

    private let layout = KeyboardLayout(whiteKeyWidth: 1, height: 1)

    private func visibleKeys(for width: CGFloat) -> Double {
        let base: [CGFloat] = hSize == .regular ? [44, 52, 64] : [36, 44, 54]
        let minWidth = base[max(0, min(2, keySize))]
        return Double(max(7, min(52, floor(width / minWidth))))
    }

    var body: some View {
        GeometryReader { geo in
            let visible = visibleKeys(for: geo.size.width)
            VStack(spacing: 8) {
                if showControls {
                    controls(visible: visible)
                    KeyboardNavigator(offset: $offset, visibleWhiteKeys: visible, pressed: play.pressedKeys, hinted: hinted)
                        .padding(.horizontal, 4)
                }
                PianoKeyboardView(
                    scrollOffset: layout.clampedOffset(offset, visibleWhiteKeys: visible),
                    visibleWhiteKeys: visible,
                    pressed: play.pressedKeys,
                    hinted: hinted,
                    showLabels: showLabels,
                    isPlayable: interactive && play.mode == .touch,
                    onKeyDown: { key, velocity, time in play.touch.keyDown(key, velocity: velocity, time: time) },
                    onKeyUp: { key, time in play.touch.keyUp(key, time: time) }
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .defersSystemGestures(on: .all)
            }
            .onAppear { onVisibleKeysChanged?(visible) }
            .onChange(of: visible) { _, v in onVisibleKeysChanged?(v) }
        }
    }

    @ViewBuilder
    private func controls(visible: Double) -> some View {
        HStack(spacing: 10) {
            Button {
                offset = layout.clampedOffset(offset - 7, visibleWhiteKeys: visible)
            } label: {
                Image(systemName: "chevron.left.2")
            }
            .accessibilityLabel("Octave down")
            .accessibilityIdentifier("octave-down")

            Text(rangeLabel(visible: visible))
                .font(Theme.font(.subheadline, weight: .bold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .frame(minWidth: 72)
                .accessibilityIdentifier("keyboard-range")

            Button {
                offset = layout.clampedOffset(offset + 7, visibleWhiteKeys: visible)
            } label: {
                Image(systemName: "chevron.right.2")
            }
            .accessibilityLabel("Octave up")
            .accessibilityIdentifier("octave-up")

            Spacer(minLength: 4)

            Toggle(isOn: $showLabels) {
                Image(systemName: "character.textbox")
            }
            .toggleStyle(.button)
            .accessibilityLabel("Note names")
            .accessibilityIdentifier("toggle-labels")

            if play.mode == .touch {
                Button {
                    play.toggleSustain()
                } label: {
                    Label("Sustain", systemImage: play.sustain ? "waveform.circle.fill" : "waveform.circle")
                        .labelStyle(.iconOnly)
                }
                .tint(play.sustain ? Theme.mintDeep : Theme.lavenderDeep)
                .accessibilityLabel(play.sustain ? "Sustain on" : "Sustain off")
                .accessibilityIdentifier("toggle-sustain")
            }

            Button {
                showVolume.toggle()
            } label: {
                Image(systemName: play.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .accessibilityLabel("Volume")
            .accessibilityIdentifier("volume")
            .popover(isPresented: $showVolume) {
                VolumePopover()
                    .presentationCompactAdaptation(.popover)
            }
        }
        .buttonStyle(.bordered)
        .tint(Theme.lavenderDeep)
        .font(.system(size: 15, weight: .bold, design: .rounded))
    }

    private func rangeLabel(visible: Double) -> String {
        let start = Int(layout.clampedOffset(offset, visibleWhiteKeys: visible).rounded())
        let end = min(51, start + Int(visible) - 1)
        let lo = Pitch(layout.midiForWhiteIndex(start) ?? 21)
        let hi = Pitch(layout.midiForWhiteIndex(end) ?? 108)
        return "\(lo.fullName)–\(hi.fullName)"
    }
}

struct VolumePopover: View {
    @Environment(PlayModeController.self) private var play
    @AppStorage("keySize") private var keySize = 1

    var body: some View {
        @Bindable var play = play
        VStack(alignment: .leading, spacing: 14) {
            Text("Piano volume").font(Theme.font(.headline))
            HStack {
                Image(systemName: "speaker.fill")
                Slider(value: $play.volume, in: 0...1)
                    .accessibilityIdentifier("volume-slider")
                Image(systemName: "speaker.wave.3.fill")
            }
            Text("Key size").font(Theme.font(.headline))
            Picker("Key size", selection: $keySize) {
                Text("Small").tag(0)
                Text("Medium").tag(1)
                Text("Large").tag(2)
            }
            .pickerStyle(.segmented)
            if play.mode == .midi {
                Toggle("Play sound from iPad/iPhone", isOn: $play.playSoundForMIDI)
            }
        }
        .padding(20)
        .frame(minWidth: 280)
        .foregroundStyle(Theme.ink)
        .tint(Theme.lavenderDeep)
    }
}
