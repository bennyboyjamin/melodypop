import MelodyPopKit
import SwiftUI

extension InputSource {
    var symbol: String {
        switch self {
        case .microphone: return "mic.fill"
        case .midi: return "cable.connector"
        case .touch: return "hand.tap.fill"
        }
    }

    var color: Color {
        switch self {
        case .microphone: return Theme.peachDeep
        case .midi: return Theme.mintDeep
        case .touch: return Theme.lavenderDeep
        }
    }
}

/// The per-lesson mode switch: Listen to My Piano / Connect My Keyboard / Play on Screen.
struct ModeSelector: View {
    @Environment(PlayModeController.self) private var play
    var compact = false
    var unavailable: (InputSource) -> String? = { _ in nil }
    var onSelect: (InputSource) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach([InputSource.microphone, .midi, .touch]) { source in
                let selected = play.mode == source
                let blocked = unavailable(source) != nil
                Button {
                    onSelect(source)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: source.symbol)
                        Text(compact ? source.shortTitle : source.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .font(Theme.font(.caption, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selected ? .white : source.color)
                    .background(selected ? source.color : source.color.opacity(0.12), in: Capsule())
                    .opacity(blocked && !selected ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mode-\(source.rawValue)")
                .accessibilityLabel(source.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint(unavailable(source) ?? "")
            }
        }
    }
}

/// Live status for the active mode (setup prompts, keyboard name, microphone meter).
struct ModeStatusBanner: View {
    @Environment(PlayModeController.self) private var play
    @State private var showPairing = false

    var body: some View {
        Group {
            switch play.mode {
            case .microphone:
                micBanner
            case .midi:
                midiBanner
            case .touch:
                EmptyView()
            }
        }
        .sheet(isPresented: $showPairing) {
            BluetoothMIDIPairingView()
        }
    }

    @ViewBuilder private var micBanner: some View {
        if let msg = play.status.message {
            banner(msg, symbol: "mic.slash.fill", color: Theme.berry) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "waveform").foregroundStyle(Theme.peachDeep)
                if play.micMeter.calibrating {
                    Text("Shh… measuring the room").font(Theme.font(.caption))
                } else if let p = play.micMeter.pitch {
                    Text("Hearing \(p.fullName)").font(Theme.font(.caption, weight: .bold))
                } else {
                    Text("Listening — play one note at a time").font(Theme.font(.caption))
                }
                Spacer()
                GeometryReader { g in
                    Capsule().fill(Theme.peachSoft)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.peachDeep).frame(width: g.size.width * CGFloat(play.micMeter.level))
                        }
                }
                .frame(width: 70, height: 8)
            }
            .foregroundStyle(Theme.ink)
            .padding(10)
            .background(Theme.peachSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("mic-status")
        }
    }

    @ViewBuilder private var midiBanner: some View {
        if let msg = play.status.message {
            banner(msg, symbol: "pianokeys", color: Theme.mintDeep) {
                Button("Pair Bluetooth") { showPairing = true }
                    .accessibilityIdentifier("pair-bluetooth")
            }
        } else {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mintDeep)
                Text("Connected: \(play.midiDevices.joined(separator: ", "))")
                    .font(Theme.font(.caption, weight: .bold))
                    .lineLimit(1)
                Spacer()
                Button("Bluetooth") { showPairing = true }
                    .font(Theme.font(.caption))
            }
            .foregroundStyle(Theme.ink)
            .padding(10)
            .background(Theme.mintSoft, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("midi-status")
        }
    }

    private func banner<A: View>(_ text: String, symbol: String, color: Color, @ViewBuilder action: () -> A) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(Theme.font(.caption)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            action()
                .buttonStyle(PopButtonStyle(color: color, compact: true))
        }
        .foregroundStyle(Theme.ink)
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("mode-status-banner")
    }
}
