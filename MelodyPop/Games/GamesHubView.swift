import MelodyPopKit
import SwiftData
import SwiftUI

struct GamesHubView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \StudentProfile.createdAt) private var students: [StudentProfile]

    private var student: StudentProfile? { students.first { $0.id == app.currentStudentID } ?? students.first }

    private func best(_ game: PianoGame) -> Int? {
        student?.practiceLogs.filter { $0.activity == "game" && $0.itemID == game.logID }.map(\.score).max()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    PipMascot(size: 56, mood: .cheering)
                    Text("Warm up your brain and fingers with a game!")
                        .font(Theme.font(.headline, weight: .bold))
                    Spacer()
                }
                .card(Theme.peachSoft)
                ForEach(PianoGame.allCases) { game in
                    NavigationLink {
                        GamePlayView(game: game)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: game.symbol)
                                .font(.system(size: 24, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(width: 60, height: 60)
                                .background([Theme.lavenderDeep, Theme.mintDeep, Theme.peachDeep][PianoGame.allCases.firstIndex(of: game)!], in: RoundedRectangle(cornerRadius: 18))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(game.title).font(Theme.font(.title3, weight: .heavy))
                                Text(game.blurb).font(Theme.font(.caption, weight: .medium)).foregroundStyle(Theme.inkSoft)
                                    .multilineTextAlignment(.leading)
                                if let b = best(game) {
                                    Label("Best: \(b)", systemImage: "trophy.fill")
                                        .font(Theme.font(.caption, weight: .heavy))
                                        .foregroundStyle(Theme.peachDeep)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(Theme.inkSoft)
                        }
                        .foregroundStyle(Theme.ink)
                        .card()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("game-\(game.rawValue)")
                }
            }
            .padding(16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Piano Games")
    }
}

@Observable
@MainActor
final class GameModel {
    enum Phase: Equatable { case intro, playing, listening, over }

    let game: PianoGame
    private(set) var phase: Phase = .intro
    private(set) var quiz: NoteQuiz?
    private(set) var memory: MelodyMemory?
    private(set) var flash: Bool?            // true = right, false = wrong (brief feedback)
    private(set) var flashID = 0
    private(set) var now = HostClock.now
    private(set) var playingKey: Int?
    let pool: [Pitch]

    @ObservationIgnored var onFinish: ((Int, Double, TimeInterval) -> Void)?
    @ObservationIgnored private weak var play: PlayModeController?
    @ObservationIgnored private var listener: UUID?
    @ObservationIgnored private var ticker: FrameTicker?
    @ObservationIgnored private var rng = SystemRandomNumberGenerator()
    @ObservationIgnored private var startedAt: TimeInterval = 0
    @ObservationIgnored private var demo: [(time: TimeInterval, midi: Int, on: Bool)] = []

    init(game: PianoGame, pool: [Pitch]) {
        self.game = game
        self.pool = pool
    }

    func attach(_ play: PlayModeController) {
        self.play = play
        listener = play.addListener { [weak self] e in MainActor.assumeIsolated { self?.handle(e) } }
        ticker = FrameTicker { [weak self] in MainActor.assumeIsolated { self?.tick() } }
        ticker?.start()
    }

    func detach() {
        if let listener { play?.removeListener(listener) }
        ticker?.stop()
        play?.setAppPlaying(false)
    }

    func start() {
        startedAt = HostClock.now
        flash = nil
        switch game {
        case .noteCatcher:
            quiz = NoteQuiz(kind: .exactPitch, pool: pool, count: 10, timeLimit: 6, generator: &rng)
            quiz?.beginRound(at: HostClock.now)
            phase = .playing
        case .keyFinder:
            let letters = pool.filter { !$0.isBlackKey }
            quiz = NoteQuiz(kind: .letterName, pool: letters.isEmpty ? pool : letters, count: 10, timeLimit: 6, generator: &rng)
            quiz?.beginRound(at: HostClock.now)
            phase = .playing
        case .melodyMemory:
            memory = MelodyMemory(pool: pool)
            nextMemoryRound()
        }
    }

    var hint: Set<Int> {
        if let k = playingKey { return [k] }
        return []
    }

    var targetPitch: Pitch? { quiz?.current?.target }

    var timeFraction: Double {
        guard let q = quiz, phase == .playing else { return 0 }
        return q.timeLeft(at: now) / q.timeLimit
    }

    var score: Int {
        switch game {
        case .melodyMemory: return memory?.score ?? 0
        default: return quiz?.score ?? 0
        }
    }

    private func handle(_ e: NoteEvent) {
        guard e.kind == .noteOn, phase == .playing else { return }
        switch game {
        case .noteCatcher, .keyFinder:
            guard var q = quiz else { return }
            let ok = q.answer(e.pitch, at: e.time)
            if ok { q.beginRound(at: HostClock.now) }
            quiz = q
            showFlash(ok)
            if q.isFinished { finish() }
        case .melodyMemory:
            guard var m = memory else { return }
            let r = m.play(e.pitch)
            memory = m
            switch r {
            case .correct: break
            case .roundComplete:
                showFlash(true)
                phase = .listening
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.nextMemoryRound() }
            case .wrong:
                showFlash(false)
                finish()
            case .ignored: break
            }
        }
    }

    private func showFlash(_ ok: Bool) {
        flash = ok
        flashID += 1
    }

    private func nextMemoryRound() {
        guard var m = memory, !m.isOver else { return }
        m.nextRound(using: &rng)
        memory = m
        // Pip plays the tune; the microphone is muted meanwhile.
        let t0 = HostClock.now + 0.4
        var events: [(time: TimeInterval, midi: Int, on: Bool)] = []
        for (i, p) in m.sequence.enumerated() {
            events.append((time: t0 + Double(i) * 0.6, midi: p.midi, on: true))
            events.append((time: t0 + Double(i) * 0.6 + 0.45, midi: p.midi, on: false))
        }
        demo = events
        play?.setAppPlaying(true)
        phase = .listening
    }

    private func tick() {
        now = HostClock.now
        if !demo.isEmpty {
            while let e = demo.first, e.time <= now {
                demo.removeFirst()
                if e.on {
                    PianoAudioEngine.shared.noteOn(e.midi, velocity: 0.75)
                    playingKey = e.midi
                } else {
                    PianoAudioEngine.shared.noteOff(e.midi)
                    playingKey = nil
                }
            }
            if demo.isEmpty {
                phase = .playing
                let p = play
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { p?.setAppPlaying(false) }
            }
            return
        }
        if phase == .playing, var q = quiz {
            if q.checkTimeout(at: now) {
                showFlash(false)
                q.beginRound(at: now)
                quiz = q
                if q.isFinished { finish() }
            }
        }
    }

    private func finish() {
        guard phase != .over else { return }
        phase = .over
        let accuracy: Double
        switch game {
        case .melodyMemory: accuracy = Double(memory?.bestLength ?? 0) / 10
        default: accuracy = quiz?.accuracy ?? 0
        }
        onFinish?(score, min(1, accuracy), HostClock.now - startedAt)
    }
}

struct GamePlayView: View {
    @Environment(PlayModeController.self) private var play
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    let game: PianoGame
    @State private var model: GameModel
    @State private var offset: Double = 23
    @State private var visible: Double = 14

    init(game: PianoGame) {
        self.game = game
        _model = State(initialValue: GameModel(game: game, pool: GamePlayView.pool(for: game)))
    }

    static func pool(for game: PianoGame) -> [Pitch] {
        switch game {
        case .noteCatcher: return [60, 62, 64, 65, 67, 69, 71, 72].map(Pitch.init)
        case .keyFinder: return (60...71).map(Pitch.init)
        case .melodyMemory: return [60, 62, 64, 65, 67].map(Pitch.init)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ModeStatusBanner()
            HStack {
                Text(game.title).font(Theme.font(.title2, weight: .heavy))
                Spacer()
                Label("\(model.score)", systemImage: "star.fill")
                    .font(Theme.font(.headline, weight: .heavy))
                    .foregroundStyle(Theme.peachDeep)
                    .accessibilityIdentifier("game-score")
            }
            board
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: 24))
                .overlay(alignment: .topTrailing) {
                    if let ok = model.flash {
                        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(ok ? Theme.mintDeep : Theme.berry)
                            .padding(10)
                            .id(model.flashID)
                            .transition(.scale)
                    }
                }
            PianoPanel(offset: $offset, hinted: model.hint, onVisibleKeysChanged: { v in
                visible = v
                offset = KeyboardLayout(whiteKeyWidth: 1, height: 1).offset(centering: 60, 72, visibleWhiteKeys: v)
            })
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(Theme.ink)
        .padding(12)
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            model.attach(play)
            model.onFinish = { score, accuracy, seconds in
                guard let s = app.currentStudent(in: context) else { return }
                ProgressService.log(activity: "game", itemID: game.logID, title: game.title, seconds: seconds, accuracy: accuracy, score: score, source: play.mode, student: s, context: context)
                ProgressService.awardStickers(student: s, context: context)
            }
        }
        .onDisappear { model.detach() }
    }

    @ViewBuilder private var board: some View {
        switch model.phase {
        case .intro:
            VStack(spacing: 12) {
                Text(game.blurb).font(Theme.font(.headline)).multilineTextAlignment(.center)
                Button("Start") { model.start() }
                    .buttonStyle(PopButtonStyle())
                    .accessibilityIdentifier("game-start")
            }
            .padding()
        case .over:
            VStack(spacing: 10) {
                Text("Game over!").font(Theme.font(.title2, weight: .heavy))
                Text("\(model.score) points").font(Theme.font(.title3, weight: .bold)).foregroundStyle(Theme.lavenderDeep)
                    .accessibilityIdentifier("game-final-score")
                Button("Play again") { model.start() }
                    .buttonStyle(PopButtonStyle())
            }
        case .listening:
            VStack(spacing: 10) {
                PipMascot(size: 70, mood: .cheering)
                Text("Listen…").font(Theme.font(.title3, weight: .heavy))
            }
        case .playing:
            switch game {
            case .noteCatcher:
                VStack(spacing: 6) {
                    if let p = model.targetPitch {
                        StaffView(piece: Piece(title: "", tempo: 60, notes: [ScoreNote(id: 0, pitches: [p], startBeat: 0, beats: 4, hand: .right)]),
                                  targets: PracticeSession(piece: Piece(title: "", tempo: 60, notes: [ScoreNote(id: 0, pitches: [p], startBeat: 0, beats: 4, hand: .right)]), mode: .waitForNotes, capabilities: InputSource.touch.capabilities).targets,
                                  playheadBeat: nil, showFingers: false)
                            .frame(height: 150)
                            .accessibilityIdentifier("game-target-\(p.midi)")
                    }
                    timerBar
                }
                .padding(10)
            case .keyFinder:
                VStack(spacing: 10) {
                    Text("Find").font(Theme.font(.headline)).foregroundStyle(Theme.inkSoft)
                    Text(model.targetPitch?.name ?? "")
                        .font(.system(size: 80, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.lavenderDeep)
                        .accessibilityIdentifier("game-letter")
                    timerBar
                }
                .padding(10)
            case .melodyMemory:
                VStack(spacing: 10) {
                    Text("Your turn!").font(Theme.font(.title2, weight: .heavy))
                    Text("Notes: \(model.memory?.position ?? 0) / \(model.memory?.sequence.count ?? 0)")
                        .font(Theme.font(.headline)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    private var timerBar: some View {
        GeometryReader { g in
            Capsule().fill(Theme.lavenderSoft)
                .overlay(alignment: .leading) {
                    Capsule().fill(model.timeFraction > 0.3 ? Theme.mintDeep : Theme.peachDeep)
                        .frame(width: g.size.width * model.timeFraction)
                }
        }
        .frame(height: 10)
        .padding(.horizontal, 20)
    }
}
