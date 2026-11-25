// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import AVFoundation
import SwiftUI
import UIKit

/**
 * The player on Apple TV: mpv's picture and the Siri Remote, as Apple's own player has it.
 *
 * Controls away: select or Play/Pause pauses (or skips the intro, or plays the next episode when
 * that's offered), left and right skip 10 seconds, up or down shows the controls, Menu closes.
 * Controls up: on the seek bar, left and right move through the video (faster the more they're
 * pressed) and select goes there; down reaches Subtitles, Audio, Speed and the rest; up or Menu hides
 * them again. Menu with the controls up while paused closes the player.
 */
struct PlayerScreen: View {
    @Environment(Stremio.self) private var stremio
    let playback: Playback

    enum Focus: Hashable { case surface, bar, button(String), option(Int) }
    enum Panel: String { case subtitles, audio, speed, picture }

    @State private var visible = true
    @State private var panel: Panel?
    @State private var panelFrom: String?
    @State private var scrub: Double?
    @State private var hideTask: Task<Void, Never>?
    @State private var now = Date()
    @State private var lastStep = Date.distantPast
    @State private var steps = 0
    /** When a finger last glided on the remote (the swipe's own left or right then doesn't step too) */
    @State private var lastGlide = Date.distantPast
    @FocusState private var focus: Focus?

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(mpv: playback.mpv).ignoresSafeArea()
            surface
            if playback.buffering && scrub == nil { ProgressView().scaleEffect(1.6).tint(.white).allowsHitTesting(false) }
            if visible { controls.transition(.opacity) }
            prompts
            if let panel { panelView(panel).transition(.move(edge: .trailing).combined(with: .opacity)) }
        }
        .animation(.easeOut(duration: 0.25), value: visible)
        .animation(.easeOut(duration: 0.25), value: panel)
        .onExitCommand(perform: back)
        .onPlayPauseCommand {
            if let target = scrub {
                playback.mpv.seek(to: target)
                scrub = nil
                playback.mpv.play()
            } else {
                playback.mpv.toggle()
            }
            poke()
        }
        .onReceive(clock) { now = $0 }
        .onAppear { poke() }
        // a finger gliding on the remote's touch surface moves through the video as it goes
        .background(RemoteGlide(enabled: { glideOn }, moved: glide, ended: { lastGlide = Date() }))
        // the TV to the video's HDR and frame rate (Match Content), once mpv knows them
        .task { await DisplayMatch.follow(playback.mpv) }
    }

    // MARK: - The remote, with the controls away

    /** The whole screen: what has the remote's focus while nothing else shows */
    private var surface: some View {
        Button(action: selectOnSurface) { Color.clear.contentShape(.rect) }
            .buttonStyle(Bare())
            .focused($focus, equals: .surface)
            .disabled(visible || panel != nil)
            .onMoveCommand { direction in
                switch direction {
                case .left: if !gliding { skip(-10) }
                case .right: if !gliding { skip(10) }
                default: poke()
                }
            }
            .ignoresSafeArea()
    }

    private func selectOnSurface() {
        if playback.upNextDue, playback.nextTitle != nil { return playback.playNext() }
        if playback.segment != nil { return playback.skip() }
        playback.mpv.toggle()
        poke()
    }

    private func skip(_ seconds: Double) {
        playback.mpv.seek(by: seconds)
        playback.show(seconds > 0 ? "+\(Int(seconds)) seconds" : "−\(Int(-seconds)) seconds")
    }

    private func back() {
        if panel != nil { return closePanel() }
        if scrub != nil {
            scrub = nil
            return poke()
        }
        if visible && !playback.paused { return hide() }
        playback.finish(ended: false)
    }

    /** Shows the controls, on the seek bar, and hides them again after a few seconds of playing */
    private func poke() {
        if !visible || focus == nil || focus == .surface {
            visible = true
            DispatchQueue.main.async { if panel == nil { focus = .bar } }
        }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled && !playback.paused && scrub == nil && panel == nil { hide() }
        }
    }

    private func hide() {
        hideTask?.cancel()
        visible = false
        scrub = nil
        DispatchQueue.main.async { focus = .surface }
    }

    // MARK: - Controls

    private var controls: some View {
        ZStack {
            LinearGradient(stops: [.init(color: .black.opacity(0.7), location: 0), .init(color: .clear, location: 0.25), .init(color: .clear, location: 0.6), .init(color: .black.opacity(0.85), location: 1)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 50)
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(playback.title).font(.title2.bold()).lineLimit(1)
                if !playback.subtitle.isEmpty { Text(playback.subtitle).font(.headline).foregroundStyle(Dx.muted).lineLimit(1) }
            }
            Spacer()
            if let party = playback.party {
                Label("\(party.people.count) · \(party.code)", systemImage: "person.2.fill")
                    .font(.headline)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: .capsule)
            }
            if playback.duration > 0 {
                Text("Ends at \(now.addingTimeInterval((playback.duration - playback.position) / max(playback.speed, 0.1)), format: .dateTime.hour().minute())")
                    .font(.headline).foregroundStyle(Dx.muted)
            }
        }
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 24) {
            Button(action: selectOnBar) {
                SeekBar(position: scrub ?? playback.position, playing: playback.position, duration: playback.duration,
                        accent: Color(playback.accent), segments: playback.segments, scrubbing: scrub != nil, focused: focus == .bar, paused: playback.paused)
            }
            .buttonStyle(Bare())
            .disabled(panel != nil)
            .focused($focus, equals: .bar)
            .onMoveCommand { direction in
                switch direction {
                case .left: if !gliding { step(forward: false) }
                case .right: if !gliding { step(forward: true) }
                case .up: hide()
                default: break
                }
            }
            HStack(spacing: 20) {
                if !playback.subtitleTracks.isEmpty || !playback.subtitles.isEmpty {
                    controlButton("subtitles", "Subtitles", "captions.bubble.fill") { open(.subtitles, from: "subtitles") }
                }
                if playback.audioTracks.count > 1 {
                    controlButton("audio", "Audio", "speaker.wave.2.fill") { open(.audio, from: "audio") }
                }
                controlButton("speed", playback.speed == 1 ? "Speed" : "\(playback.speed.formatted())×", "gauge.with.dots.needle.67percent") { open(.speed, from: "speed") }
                controlButton("picture", playback.fit.rawValue, "rectangle.arrowtriangle.2.outward") { open(.picture, from: "picture") }
                if OtherApp.find(stremio.otherApp) != nil {
                    controlButton("external", OtherApp.find(stremio.otherApp)?.name ?? "Other App", "arrow.up.forward.app") { stremio.playExternally(playback) }
                }
                Spacer()
                if playback.nextTitle != nil {
                    controlButton("next", "Next Episode", "forward.end.fill") { playback.playNext() }
                }
            }
            .disabled(panel != nil)
        }
    }

    private func controlButton(_ id: String, _ label: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(label, systemImage: icon).font(.headline) }
            .focused($focus, equals: .button(id))
    }

    private func selectOnBar() {
        if let target = scrub {
            playback.mpv.seek(to: target)
            scrub = nil
        } else {
            playback.mpv.toggle()
        }
        poke()
    }

    /** Through the video on the seek bar: 10 seconds a press, then 30 and 60 as presses come quickly */
    private func step(forward: Bool) {
        guard playback.duration > 0 else { return }
        let quick = Date().timeIntervalSince(lastStep) < 0.6
        steps = quick ? steps + 1 : 0
        lastStep = Date()
        let size: Double = steps > 10 ? 60 : steps > 4 ? 30 : 10
        let from = scrub ?? playback.position
        scrub = min(max(from + (forward ? size : -size), 0), max(playback.duration - 2, 0))
        hideTask?.cancel()
    }

    // MARK: - Gliding through the video

    /** A glide moves through the video on the seek bar, or with the controls away (not in a menu or the buttons) */
    private var glideOn: Bool {
        panel == nil && playback.duration > 0 && (!visible || focus == .bar || focus == .surface)
    }

    private var gliding: Bool { Date().timeIntervalSince(lastGlide) < 0.5 }

    /**
     * The finger moved [dx] across the touch surface ([width] its whole width) at [speed]: the point to
     * go to moves with it. Slowly for small changes; quickly, a whole swipe goes up to a third of the
     * video (30 minutes at most). Glides add up; select (or Play/Pause) goes there
     */
    private func glide(_ dx: CGFloat, width: CGFloat, speed: CGFloat) {
        lastGlide = Date()
        if !visible { poke() }
        hideTask?.cancel()
        let span = min(max(playback.duration * 0.35, 90), 1800)
        let reach = 0.3 + 0.7 * min(abs(Double(speed)) / 2500, 1)
        let from = scrub ?? playback.position
        scrub = min(max(from + Double(dx / max(width, 1)) * span * reach, 0), max(playback.duration - 2, 0))
    }

    // MARK: - Skip, up next, messages

    private var prompts: some View {
        VStack {
            if let text = playback.flash {
                Text(text)
                    .font(.headline)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(.top, 60)
                    .transition(.opacity)
            }
            Spacer()
            HStack {
                Spacer()
                if playback.upNextDue, let next = playback.nextTitle {
                    upNext(next)
                } else if let segment = playback.segment {
                    hint(segment.label)
                }
            }
            .padding(.bottom, visible ? 250 : 80)
            .padding(.horizontal, 80)
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: playback.flash)
    }

    /** Skip Intro: select skips while the controls are away */
    private func hint(_ label: String) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.headline)
            if !visible { Image(systemName: "hand.tap.fill").font(.subheadline).foregroundStyle(.black.opacity(0.6)) }
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
        .foregroundStyle(.black)
        .background(.white, in: .capsule)
    }

    private func upNext(_ next: String) -> some View {
        HStack(spacing: 20) {
            Art(url: playback.nextArt).frame(width: 240, height: 135).clipShape(.rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text("UP NEXT").font(.caption.weight(.bold)).foregroundStyle(Dx.muted)
                Text(next).font(.headline).lineLimit(2)
                Text(visible ? "Next Episode, below" : "Press to play").font(.subheadline).foregroundStyle(Dx.muted)
            }
            .frame(width: 320, alignment: .leading)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
    }

    // MARK: - Subtitles, audio, speed, picture

    private struct Option {
        var label: String
        var detail: String?
        var on: Bool
        var heading: String?
        var pick: () -> Void
    }

    private func open(_ p: Panel, from: String) {
        hideTask?.cancel()
        panelFrom = from
        panel = p
        let first = options(p).firstIndex(where: \.on) ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focus = .option(first) }
    }

    private func closePanel() {
        let from = panelFrom
        panel = nil
        DispatchQueue.main.async { focus = from.map { .button($0) } ?? .bar }
        poke()
    }

    private func options(_ p: Panel) -> [Option] {
        switch p {
        case .subtitles:
            let subs = playback.subtitleTracks
            var list = [Option(label: "Off", on: !subs.contains(where: \.selected), heading: "Subtitles") { playback.mpv.select("sub", nil) }]
            for (source, heading) in [("video", "In the Video"), ("stream", "With This Stream"), ("addon", "From Subtitle Addons · may not match")] {
                let group = subs.filter { playback.source(of: $0) == source }
                for (i, t) in group.enumerated() {
                    list.append(Option(label: trackName(t), on: t.selected, heading: i == 0 ? heading : nil) { playback.mpv.select("sub", t.id) })
                }
            }
            return list
        case .audio:
            return playback.audioTracks.enumerated().map { i, t in
                Option(label: trackName(t), detail: t.codec.isEmpty ? nil : t.codec.uppercased(), on: t.selected, heading: i == 0 ? "Audio" : nil) { playback.mpv.select("audio", t.id) }
            }
        case .speed:
            return [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].enumerated().map { i, r in
                Option(label: r == 1 ? "Normal" : "\(r.formatted())×", on: playback.speed == r, heading: i == 0 ? "Speed" : nil) { playback.mpv.setSpeed(r) }
            }
        case .picture:
            return Playback.Fit.allCases.enumerated().map { i, f in
                Option(label: f == .fit ? "Fit the Screen" : f == .fill ? "Fill the Screen" : "Stretch", on: playback.fit == f, heading: i == 0 ? "Picture" : nil) { playback.fit = f }
            }
        }
    }

    private func panelView(_ p: Panel) -> some View {
        let list = options(p)
        return HStack {
            Spacer()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(list.enumerated()), id: \.offset) { i, o in
                        if let heading = o.heading {
                            Text(heading).font(.headline).foregroundStyle(Dx.muted).padding(.top, i == 0 ? 0 : 20).padding(.leading, 10)
                        }
                        Button {
                            o.pick()
                            if p != .subtitles { closePanel() }
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "checkmark").opacity(o.on ? 1 : 0)
                                Text(o.label).lineLimit(2)
                                Spacer(minLength: 0)
                                if let d = o.detail { Text(d).font(.callout).foregroundStyle(.secondary) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .focused($focus, equals: .option(i))
                    }
                }
                .padding(40)
            }
            .frame(width: 720)
            .background(.regularMaterial)
        }
        .ignoresSafeArea()
    }
}

/**
 * The finger on the remote's touch surface as it moves, for gliding through the video (SwiftUI on tvOS
 * only hears whole swipes, as steps). Watches the window while the player shows; only horizontal
 * movement, and only when [enabled]; the focus engine still has the touches too.
 */
private struct RemoteGlide: UIViewRepresentable {
    var enabled: () -> Bool
    /** How far the finger went since last time, the surface's width, and its speed */
    var moved: (CGFloat, CGFloat, CGFloat) -> Void
    var ended: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: Anchor, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.moved = moved
        context.coordinator.ended = ended
    }

    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) { coordinator.detach() }

    final class Anchor: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { coordinator?.attach(to: window) } else { coordinator?.detach() }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var enabled: () -> Bool = { false }
        var moved: (CGFloat, CGFloat, CGFloat) -> Void = { _, _, _ in }
        var ended: () -> Void = {}
        private var pan: UIPanGestureRecognizer?
        private var last: CGFloat = 0

        func attach(to window: UIWindow) {
            guard pan == nil else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            pan.cancelsTouchesInView = false
            pan.delegate = self
            window.addGestureRecognizer(pan)
            self.pan = pan
        }

        func detach() {
            if let pan { pan.view?.removeGestureRecognizer(pan) }
            pan = nil
        }

        @objc func panned(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            let x = g.translation(in: view).x
            switch g.state {
            case .began:
                last = x
            case .changed:
                moved(x - last, view.bounds.width, g.velocity(in: view).x)
                last = x
            default:
                ended()
            }
        }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard enabled(), let pan = g as? UIPanGestureRecognizer, let view = pan.view else { return false }
            let v = pan.velocity(in: view)
            return abs(v.x) > abs(v.y)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/** A button that looks like nothing (the remote's way in, with no focus effect of its own) */
private struct Bare: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/** The seek bar: where it's playing, where it'll go, skip segments marked */
private struct SeekBar: View {
    var position: Double
    var playing: Double
    var duration: Double
    var accent: Color
    var segments: [Playback.Segment]
    var scrubbing: Bool
    var focused: Bool
    var paused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { g in
                let width = g.size.width
                let at = duration > 0 ? min(max(position / duration, 0), 1) : 0
                let played = duration > 0 ? min(max(playing / duration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                        if duration > 0 {
                            let end = s.end > 0 ? s.end : duration
                            Capsule().fill(.white.opacity(0.35))
                                .frame(width: max(width * (end - s.start) / duration, 3))
                                .offset(x: width * s.start / duration)
                        }
                    }
                    Capsule().fill(accent).frame(width: width * played)
                    if scrubbing {
                        Capsule().fill(.white).frame(width: 4, height: 36).offset(x: width * at - 2)
                    }
                    Circle().fill(.white).frame(width: focused ? 26 : 16).offset(x: width * played - (focused ? 13 : 8))
                }
                .frame(height: focused ? 12 : 8)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if scrubbing {
                        Text(timeText(position))
                            .font(.headline.monospacedDigit())
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: .capsule)
                            .fixedSize()
                            .offset(x: min(max(width * at - 50, 0), width - 110), y: -46)
                    }
                }
            }
            .frame(height: 36)
            HStack {
                Text(timeText(playing)).monospacedDigit()
                if scrubbing {
                    Text("Press to jump \(position >= playing ? "ahead" : "back") \(timeText(abs(position - playing)))").foregroundStyle(Dx.muted)
                } else if focused {
                    Text(paused ? "◀ ▶ to move · press to play" : "◀ ▶ to move · press to pause").foregroundStyle(Dx.faint)
                }
                Spacer()
                Text("−" + timeText(max(duration - playing, 0))).monospacedDigit().foregroundStyle(Dx.muted)
            }
            .font(.headline)
        }
        .animation(.snappy(duration: 0.15), value: focused)
    }
}

/** mpv's picture */
private struct VideoSurface: UIViewRepresentable {
    let mpv: MPV
    func makeUIView(context: Context) -> Surface { Surface(layer: mpv.layer) }
    func updateUIView(_ view: Surface, context: Context) {}

    final class Surface: UIView {
        let video: CALayer
        init(layer: CALayer) {
            video = layer
            super.init(frame: .zero)
            backgroundColor = .black
            isUserInteractionEnabled = false
            self.layer.addSublayer(layer)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            video.frame = bounds
            CATransaction.commit()
        }
    }
}

private func timeText(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let s = Int(max(seconds, 0))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

private func trackName(_ t: MPV.Track) -> String {
    let lang = Locale.current.localizedString(forLanguageCode: t.lang) ?? t.lang.uppercased()
    if t.external { return t.title.ifEmpty(lang.ifEmpty("Subtitles")) }
    return [lang, t.title].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty("Track \(t.id)")
}
