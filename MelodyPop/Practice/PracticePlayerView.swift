import MelodyPopKit
import SwiftData
import SwiftUI

/// The one practice screen used by every lesson and song, in every play mode.
struct PracticePlayerView: View {
    @Environment(PlayModeController.self) private var play
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let item: PracticeItem
    var nextItem: PracticeItem? = nil
    var onNext: ((PracticeItem) -> Void)? = nil

    @State private var model: PracticePlayerModel
    @State private var keyboardOffset: Double = 23
    @State private var visibleKeys: Double = 14
    @State private var didPositionKeyboard = false
    @State private var earnedStickers: [Sticker] = []

    init(item: PracticeItem, source: InputSource, nextItem: PracticeItem? = nil, onNext: ((PracticeItem) -> Void)? = nil) {
        self.item = item
        self.nextItem = nextItem
        self.onNext = onNext
        _model = State(initialValue: PracticePlayerModel(item: item, source: source))
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            VStack(spacing: landscape ? 6 : 10) {
                header(compact: landscape)
                ModeStatusBanner()
                if case .ready = model.phase, !landscape {
                    tipCard
                }
                StaffView(
                    piece: item.piece,
                    targets: model.session.targets,
                    playheadBeat: model.isTimed ? (model.demoBeat ?? model.currentBeat) : model.demoBeat,
                    showFingers: item.showFingers
                )
                .frame(height: staffHeight(geo.size, landscape: landscape))
                .background(Theme.cream)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .topTrailing) { feedbackBubble }
                .overlay { countInOverlay }

                controls(compact: landscape)

                PianoPanel(
                    offset: $keyboardOffset,
                    hinted: model.hintedKeys,
                    showControls: !landscape || geo.size.height > 420,
                    interactive: true,
                    onVisibleKeysChanged: { v in
                        visibleKeys = v
                        positionKeyboard()
                    }
                )
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .screenBackground()
        .overlay {
            if model.phase == .finished, let result = model.result {
                ResultCard(item: item, result: result, stickers: earnedStickers, hasNext: nextItem != nil,
                           onRetry: { earnedStickers = []; model.retry() },
                           onNext: { if let n = nextItem { onNext?(n) } },
                           onDone: { dismiss() })
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.phase == .finished)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            model.attach(to: play)
            model.onFinished = { result, seconds, source in
                earnedStickers = saveResult(result, seconds: seconds, source: source)
            }
        }
        .onDisappear { model.detach() }
        .onChange(of: play.status) { _, status in
            if status == .ready, case .paused(let reason?) = model.phase, item.unavailableReason(for: play.mode) != reason {
                model.modeDidChange(to: play.mode)
            }
        }
    }

    private func staffHeight(_ size: CGSize, landscape: Bool) -> CGFloat {
        let grand = item.piece.usesBothHands || (item.piece.lowest?.midi ?? 60) < 55
        let base: CGFloat = grand ? 230 : 150
        return landscape ? min(base, size.height * 0.36) : min(base, size.height * 0.3)
    }

    private func positionKeyboard() {
        guard !didPositionKeyboard, let lo = item.piece.lowest?.midi, let hi = item.piece.highest?.midi else { return }
        let layout = KeyboardLayout(whiteKeyWidth: 1, height: 1)
        let lowWhite = Pitch(lo).isBlackKey ? lo - 1 : lo
        let highWhite = Pitch(hi).isBlackKey ? hi + 1 : hi
        keyboardOffset = layout.offset(centering: lowWhite, highWhite, visibleWhiteKeys: visibleKeys)
        didPositionKeyboard = true
    }

    // MARK: Header

    private func header(compact: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36)
                        .background(.white, in: Circle())
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("close-practice")
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.kind == .lesson ? "Lesson \(item.id)" : "Song")
                        .font(Theme.font(.caption, weight: .bold))
                        .foregroundStyle(Theme.inkSoft)
                    Text(item.title)
                        .font(Theme.font(compact ? .headline : .title3, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
                Spacer()
                progressPill
            }
            ModeSelector(compact: compact, unavailable: { item.unavailableReason(for: $0) }) { source in
                switchMode(to: source)
            }
        }
        .padding(.top, 6)
    }

    private var progressPill: some View {
        let _ = model.revision
        return Text("\(model.session.completedCount) of \(model.session.targets.count)")
            .font(Theme.font(.subheadline, weight: .bold))
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.mintSoft, in: Capsule())
            .foregroundStyle(Theme.mintDeep)
            .accessibilityIdentifier("progress-label")
    }

    private func switchMode(to source: InputSource) {
        guard source != play.mode || play.status != .ready else { return }
        model.modeWillChange()
        Task {
            await play.select(source)
            model.modeDidChange(to: source)
        }
    }

    // MARK: Tip

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 12) {
            PipMascot(size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.subtitle).font(Theme.font(.subheadline, weight: .bold))
                Text(item.tip).font(Theme.font(.caption, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(Theme.lavenderSoft)
    }

    // MARK: Controls

    private func controls(compact: Bool) -> some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            mainButton
            Button {
                model.retry()
            } label: {
                Label("Retry", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(PopButtonStyle(color: Theme.peach, foreground: Theme.ink, compact: true))
            .accessibilityIdentifier("retry-button")
            .disabled(model.phase == .ready)

            Button {
                model.playDemo()
            } label: {
                Label(model.phase == .demo ? "Stop" : "Listen", systemImage: model.phase == .demo ? "stop.fill" : "ear")
            }
            .buttonStyle(PopButtonStyle(color: Theme.mint, foreground: Theme.ink, compact: true))
            .accessibilityIdentifier("listen-button")

            Spacer(minLength: 4)

            if model.isTimed {
                Menu {
                    Picker("Speed", selection: $model.tempoScale) {
                        Text("Slow 50%").tag(0.5)
                        Text("Easy 75%").tag(0.75)
                        Text("Normal 100%").tag(1.0)
                        Text("Fast 120%").tag(1.2)
                    }
                    Toggle("Metronome", isOn: $model.metronomeOn)
                } label: {
                    Label("\(Int(model.tempoScale * item.piece.tempo)) bpm", systemImage: "metronome")
                        .font(Theme.font(.caption, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(.white, in: Capsule())
                }
                .accessibilityIdentifier("tempo-menu")
            }
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder private var mainButton: some View {
        switch model.phase {
        case .ready:
            Button { model.start() } label: { Label("Start", systemImage: "play.fill") }
                .buttonStyle(PopButtonStyle(compact: true))
                .accessibilityIdentifier("start-button")
        case .playing, .countIn:
            Button { model.togglePause() } label: { Label("Pause", systemImage: "pause.fill") }
                .buttonStyle(PopButtonStyle(compact: true))
                .accessibilityIdentifier("pause-button")
        case .paused:
            Button { model.togglePause() } label: { Label("Resume", systemImage: "play.fill") }
                .buttonStyle(PopButtonStyle(compact: true))
                .accessibilityIdentifier("resume-button")
        case .demo, .finished:
            Button {} label: { Label("Start", systemImage: "play.fill") }
                .buttonStyle(PopButtonStyle(color: Theme.inkSoft, compact: true))
                .disabled(true)
        }
    }

    // MARK: Overlays

    @ViewBuilder private var feedbackBubble: some View {
        if let g = model.feedback {
            Text(g.label)
                .font(Theme.font(.headline, weight: .heavy))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(g == .missed ? Theme.berry : g == .ok || g == .partial ? Theme.peachDeep : Theme.mintDeep, in: Capsule())
                .foregroundStyle(.white)
                .padding(8)
                .id(model.feedbackID)
                .transition(.scale.combined(with: .opacity))
                .accessibilityIdentifier("feedback")
        }
    }

    @ViewBuilder private var countInOverlay: some View {
        if case .countIn(let n) = model.phase {
            Text("\(n)")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.lavenderDeep)
                .frame(width: 100, height: 100)
                .background(.white.opacity(0.9), in: Circle())
                .accessibilityIdentifier("count-in")
        } else if case .paused(let reason?) = model.phase {
            Text(reason)
                .font(Theme.font(.subheadline))
                .multilineTextAlignment(.center)
                .padding(14)
                .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
                .padding(12)
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("paused-reason")
        }
    }

    // MARK: Persistence

    private func saveResult(_ result: SessionResult, seconds: TimeInterval, source: InputSource) -> [Sticker] {
        guard let student = app.currentStudent(in: context) else { return [] }
        return ProgressService.record(item: item, result: result, seconds: seconds, source: source, student: student, context: context)
    }
}

struct ResultCard: View {
    let item: PracticeItem
    let result: SessionResult
    var stickers: [Sticker]
    var hasNext: Bool
    var onRetry: () -> Void
    var onNext: () -> Void
    var onDone: () -> Void

    private var passed: Bool { result.accuracy >= item.passAccuracy }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                PipMascot(size: 70, mood: passed ? .cheering : .thinking)
                Text(passed ? "You did it!" : "Nice try — let's practise again!")
                    .font(Theme.font(.title2, weight: .heavy))
                    .multilineTextAlignment(.center)
                StarRow(stars: result.stars, size: 30)
                Text("\(Int((result.accuracy * 100).rounded()))%")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.lavenderDeep)
                    .accessibilityIdentifier("result-accuracy")
                HStack(spacing: 16) {
                    stat("Right notes", "\(result.correctTargets)/\(result.totalTargets)")
                    if item.mode == .timed { stat("Timing", "\(Int((result.timingAccuracy * 100).rounded()))%") }
                    stat("Oops notes", "\(result.wrongNotes)")
                }
                if !stickers.isEmpty {
                    HStack {
                        ForEach(stickers) { s in StickerBadge(sticker: s, earned: true, size: 44) }
                    }
                    Text("New sticker!").font(Theme.font(.caption, weight: .bold)).foregroundStyle(Theme.peachDeep)
                }
                HStack(spacing: 10) {
                    Button("Try again", action: onRetry)
                        .buttonStyle(PopButtonStyle(color: Theme.peach, foreground: Theme.ink))
                        .accessibilityIdentifier("result-retry")
                    if passed && hasNext {
                        Button("Next", action: onNext)
                            .buttonStyle(PopButtonStyle(color: Theme.mintDeep))
                            .accessibilityIdentifier("result-next")
                    }
                    Button("Done", action: onDone)
                        .buttonStyle(PopButtonStyle())
                        .accessibilityIdentifier("result-done")
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(24)
            .frame(maxWidth: 420)
            .background(Theme.cream, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(24)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.font(.headline, weight: .heavy))
            Text(title).font(Theme.font(.caption2)).foregroundStyle(Theme.inkSoft)
        }
    }
}
