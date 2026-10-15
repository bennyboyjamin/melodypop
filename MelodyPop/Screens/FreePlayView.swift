import MelodyPopKit
import SwiftData
import SwiftUI

@Observable
@MainActor
final class FreePlayModel {
    private(set) var isRecording = false
    private(set) var isPlayingBack = false
    private(set) var recording: PerformanceRecording?
    private(set) var playbackKeys: Set<Int> = []
    private(set) var elapsed: TimeInterval = 0
    private(set) var notesPlayed = 0

    @ObservationIgnored private var recorder = PerformanceRecorder()
    @ObservationIgnored private var cursor: PlaybackCursor?
    @ObservationIgnored private var playbackStart: TimeInterval = 0
    @ObservationIgnored private var recordStart: TimeInterval = 0
    @ObservationIgnored private var ticker: FrameTicker?
    @ObservationIgnored private weak var controller: PlayModeController?
    @ObservationIgnored private var listener: UUID?
    @ObservationIgnored private var sustainListener: UUID?
    @ObservationIgnored private(set) var openedAt = HostClock.now

    func attach(_ play: PlayModeController) {
        controller = play
        openedAt = HostClock.now
        listener = play.addListener { [weak self] e in MainActor.assumeIsolated { self?.handle(e) } }
        sustainListener = play.addSustainListener { [weak self] down in
            MainActor.assumeIsolated {
                guard let self, self.isRecording else { return }
                self.recorder.recordPedal(down: down, at: HostClock.now)
            }
        }
        ticker = FrameTicker { [weak self] in MainActor.assumeIsolated { self?.tick() } }
        ticker?.start()
    }

    func detach() {
        if let listener { controller?.removeListener(listener) }
        if let sustainListener { controller?.removeListener(sustainListener) }
        listener = nil
        sustainListener = nil
        stopPlayback()
        if isRecording { stopRecording() }
        ticker?.stop()
    }

    private func handle(_ e: NoteEvent) {
        if e.kind == .noteOn { notesPlayed += 1 }
        if isRecording { recorder.record(e) }
    }

    func startRecording() {
        stopPlayback()
        recordStart = HostClock.now
        recorder.start(at: recordStart)
        if controller?.sustain == true { recorder.recordPedal(down: true, at: recordStart) }
        isRecording = true
        elapsed = 0
    }

    func stopRecording() {
        let r = recorder.stop(at: HostClock.now)
        isRecording = false
        recording = r.noteCount > 0 ? r : nil
    }

    func playRecording(_ r: PerformanceRecording? = nil) {
        guard let r = r ?? recording else { return }
        stopPlayback()
        if isRecording { stopRecording() }
        cursor = PlaybackCursor(recording: r)
        playbackStart = HostClock.now + 0.1
        isPlayingBack = true
        controller?.setAppPlaying(true)
    }

    func stopPlayback() {
        guard isPlayingBack else { return }
        for k in playbackKeys { PianoAudioEngine.shared.noteOff(k) }
        PianoAudioEngine.shared.setSustain(controller?.sustain ?? false)
        playbackKeys = []
        cursor = nil
        isPlayingBack = false
        let c = controller
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { c?.setAppPlaying(false) }
    }

    private func tick() {
        let now = HostClock.now
        if isRecording { elapsed = now - recordStart }
        guard isPlayingBack, var c = cursor else { return }
        let offset = now - playbackStart
        elapsed = max(0, offset)
        let step = c.advance(to: offset)
        for p in step.pedal { PianoAudioEngine.shared.setSustain(p.down) }
        for e in step.notes {
            switch e.kind {
            case .noteOn:
                PianoAudioEngine.shared.noteOn(e.midi, velocity: e.velocity)
                playbackKeys.insert(e.midi)
            case .noteOff:
                PianoAudioEngine.shared.noteOff(e.midi)
                playbackKeys.remove(e.midi)
            }
        }
        cursor = c
        if c.isAtEnd && offset > c.recording.duration { stopPlayback() }
    }
}

/// Free play: the full virtual piano (or any play mode), with recording and playback.
struct FreePlayView: View {
    @Environment(PlayModeController.self) private var play
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var model = FreePlayModel()
    @State private var offset: Double = 23
    @State private var showRecordings = false
    @State private var savedMessage: String?

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Free Play").font(Theme.font(landscape ? .headline : .title2, weight: .heavy))
                        Text(play.lastNote.map { "Last note: \($0.fullName)" } ?? "Play anything you like!")
                            .font(Theme.font(.subheadline, weight: .bold))
                            .foregroundStyle(Theme.lavenderDeep)
                            .accessibilityIdentifier("last-note")
                    }
                    Spacer()
                    NavigationLink {
                        PlayModeSelectionView()
                    } label: {
                        Label(play.mode.shortTitle, systemImage: play.mode.symbol)
                            .font(Theme.font(.caption, weight: .bold))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(play.mode.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(play.mode.color)
                    }
                }
                ModeStatusBanner()
                recorderBar
                PianoPanel(offset: $offset, hinted: model.playbackKeys)
                    .frame(maxHeight: .infinity)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { model.attach(play) }
        .onDisappear {
            let seconds = HostClock.now - model.openedAt
            model.detach()
            if model.notesPlayed >= 10, let s = app.currentStudent(in: context) {
                ProgressService.log(activity: "freePlay", itemID: 0, title: "Free Play", seconds: seconds, accuracy: 0, source: play.mode, student: s, context: context)
                ProgressService.awardStickers(student: s, context: context)
            }
        }
        .sheet(isPresented: $showRecordings) {
            RecordingsListView { rec in
                showRecordings = false
                model.playRecording(rec)
            }
        }
    }

    private var recorderBar: some View {
        HStack(spacing: 8) {
            if model.isRecording {
                Button { model.stopRecording() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(PopButtonStyle(color: Theme.berry, compact: true))
                    .accessibilityIdentifier("stop-recording")
                Circle().fill(Theme.berry).frame(width: 10, height: 10)
                Text(timeString(model.elapsed)).font(Theme.font(.subheadline, weight: .bold)).monospacedDigit()
            } else {
                Button { model.startRecording() } label: { Label("Record", systemImage: "record.circle") }
                    .buttonStyle(PopButtonStyle(color: Theme.berry, compact: true))
                    .accessibilityIdentifier("record-button")
                    .disabled(model.isPlayingBack)
            }
            if model.isPlayingBack {
                Button { model.stopPlayback() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(PopButtonStyle(color: Theme.mintDeep, compact: true))
                    .accessibilityIdentifier("stop-playback")
                Text(timeString(model.elapsed)).font(Theme.font(.subheadline, weight: .bold)).monospacedDigit()
                    .accessibilityIdentifier("playback-time")
            } else if let rec = model.recording, !model.isRecording {
                Button { model.playRecording() } label: { Label("Play back", systemImage: "play.fill") }
                    .buttonStyle(PopButtonStyle(color: Theme.mintDeep, compact: true))
                    .accessibilityIdentifier("play-recording")
                Button { save(rec) } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    .buttonStyle(PopButtonStyle(color: Theme.peach, foreground: Theme.ink, compact: true))
                    .accessibilityIdentifier("save-recording")
            }
            Spacer()
            if let msg = savedMessage {
                Text(msg).font(Theme.font(.caption, weight: .bold)).foregroundStyle(Theme.mintDeep)
                    .accessibilityIdentifier("saved-message")
            }
            Button { showRecordings = true } label: { Image(systemName: "folder.fill") }
                .buttonStyle(PopButtonStyle(color: Theme.lavender, foreground: Theme.ink, compact: true))
                .accessibilityLabel("My recordings")
                .accessibilityIdentifier("recordings-list")
        }
    }

    private func save(_ rec: PerformanceRecording) {
        guard let s = app.currentStudent(in: context) else { return }
        let title = "My song \(s.recordings.count + 1)"
        guard let saved = try? SavedRecording(title: title, recording: rec) else { return }
        context.insert(saved)
        saved.student = s
        try? context.save()
        ProgressService.awardStickers(student: s, context: context)
        savedMessage = "Saved “\(title)”"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { savedMessage = nil }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct RecordingsListView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedRecording.createdAt, order: .reverse) private var all: [SavedRecording]
    var onPlay: (PerformanceRecording) -> Void

    private var mine: [SavedRecording] {
        all.filter { $0.student?.id == app.currentStudentID || app.currentStudentID == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                if mine.isEmpty {
                    Text("No recordings yet. Tap Record, play something, then Save.")
                        .font(Theme.font(.subheadline))
                        .foregroundStyle(Theme.inkSoft)
                }
                ForEach(mine) { r in
                    Button {
                        if let rec = r.recording { onPlay(rec) }
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Theme.mintDeep)
                            VStack(alignment: .leading) {
                                Text(r.title).font(Theme.font(.headline))
                                Text("\(r.noteCount) notes · \(Int(r.duration)) s · \(r.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(Theme.font(.caption)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        .foregroundStyle(Theme.ink)
                    }
                }
                .onDelete { idx in
                    for i in idx { context.delete(mine[i]) }
                    try? context.save()
                }
            }
            .navigationTitle("My Recordings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
