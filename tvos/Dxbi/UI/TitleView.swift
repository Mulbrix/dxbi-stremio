// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import SwiftUI

/**
 * A film or show: its art across the screen, the logo, Play (one press: dx.bi picks the stream, as on
 * the iPhone), My List and the rest, then the seasons and episodes, and the cast. How Play picks and
 * when it plays is the iPhone app's (ios/Dxbi/UI/TitleView.swift).
 */
struct TitleView: View {
    @Environment(Stremio.self) private var stremio
    @Environment(\.dismiss) private var dismiss
    var ref: TitleRef

    @State private var choices: StreamChoices?
    /** Play was pressed for this video: dx.bi's pick plays as soon as it's sure */
    @State private var waitingFor: String?
    @State private var streamsOpen = false
    @State private var season: Int?
    @State private var reviews: Reviews?
    @State private var reviewsOpen = false
    @State private var aboutOpen = false
    @State private var autoPlayed = false
    @State private var cast: [JSON]?
    @FocusState private var playFocused: Bool

    private var details: Details? { stremio.details?.metaId == ref.id ? stremio.details : nil }
    private var title: Title { details?.title ?? Title(id: ref.id, type: ref.type, name: ref.name) }
    private var current: StreamChoices? {
        guard let c = choices, let v = details?.videoId, c.videoId == v else { return nil }
        return c
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 60) {
                header
                if ref.type == "series" { episodes }
                people
            }
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        .background {
            // the art across the screen, darkened where the words are
            Art(url: title.backdrop)
                .overlay(LinearGradient(stops: [.init(color: .black.opacity(0.92), location: 0), .init(color: .black.opacity(0.55), location: 0.5), .init(color: .black.opacity(0.1), location: 0.85)], startPoint: .leading, endPoint: .trailing))
                .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.95), location: 0.85)], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $streamsOpen) {
            StreamsView(choices: current, heading: title.name, subheading: episodeLine) { option, target in play(option, in: target) }
        }
        .sheet(isPresented: $reviewsOpen) { ReviewsView(title: title, reviews: reviews) }
        .sheet(isPresented: $aboutOpen) { AboutView(title: title, details: details) }
        .task(id: ref.id) {
            if stremio.details?.metaId != ref.id { stremio.open(ref.type, ref.id) }
            reviews = await stremio.reviews(ref.type, ref.id)
        }
        .task(id: "\(ref.id)-\(details?.state == .ready)") {
            guard let d = details, d.state == .ready else { return }
            let names: [JSON] = d.directors.prefix(3).map { ["name": $0, "role": "Director"] } + d.cast.prefix(13).map { ["name": $0, "role": ""] }
            cast = await stremio.cast(ref.type, imdbId ?? "", names: names)
        }
        // a series: the episode they're on, ready before Play is pressed
        .onChange(of: details?.state == .ready, initial: true) {
            guard let d = details, d.state == .ready, ref.type == "series" else { return }
            if season == nil { season = nextVideo(d)?.season ?? d.seasons.first }
            if d.videoId == nil, let v = nextVideo(d) { stremio.open(ref.type, ref.id, videoId: v.id) }
            if ref.play && !autoPlayed { autoPlayed = true; start(nextVideo(d)?.id) }
        }
        .onChange(of: details?.state == .ready && ref.type != "series", initial: true) { _, ready in
            if ready && ref.play && !autoPlayed { autoPlayed = true; start(nil) }
        }
        // back from the player, the page picks the next episode when the last was finished
        .onChange(of: details?.videoId) { _, id in
            guard let d = details, let v = d.videos.first(where: { $0.id == id }), let s = v.season else { return }
            season = s
        }
        // dx.bi's reading of the streams, again as more addons answer
        .task(id: details?.streamsKey) {
            guard details?.videoId != nil else { return }
            choices = await stremio.streams()
            justPlayIfSure()
        }
        .task(id: waitingFor) {
            guard waitingFor != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            if let c = current, c.justPlay, waitingFor == c.videoId, let pick = c.picked { play(pick) }
        }
        .onAppear { playFocused = true }
        // Menu goes back to where the title was opened from, always (with nothing focused, tvOS took
        // it as leaving the app)
        .onExitCommand { dismiss() }
        // back from the player: the focus comes back to the page (it was left nowhere)
        .onChange(of: stremio.playback == nil) { _, closed in
            guard closed else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { playFocused = true }
        }
    }

    // MARK: - Playing

    /** What Play starts: the episode they're in the middle of, else the first one that's out */
    private func nextVideo(_ d: Details) -> Video? {
        guard ref.type == "series" else { return nil }
        return d.videos.first { $0.id == d.videoId } ?? d.videos.first { $0.id == d.resumeVideoId } ?? d.videos.first { ($0.season ?? 0) > 0 && !$0.upcoming } ?? d.videos.first
    }

    private func start(_ videoId: String?) {
        let target = videoId ?? details?.videoId ?? ref.id
        if ref.type == "series", let videoId, videoId != details?.videoId {
            choices = nil
            stremio.open(ref.type, ref.id, videoId: videoId)
        }
        waitingFor = target
        streamsOpen = true
        justPlayIfSure()
    }

    /** Just press Play: the stream chosen last time plays at once, anything else once every addon has answered */
    private func justPlayIfSure() {
        guard let c = current, c.justPlay, waitingFor == c.videoId, let pick = c.picked else { return }
        if c.sameAsLastTime || c.settled { play(pick) }
    }

    private func play(_ option: StreamOption, in target: Stremio.Target = .player) {
        waitingFor = nil
        streamsOpen = false
        stremio.play(option, in: target)
    }

    private var playLabel: String {
        guard let d = details else { return "Play" }
        if ref.type == "series", let v = nextVideo(d), let s = v.season, let e = v.episode {
            let resuming = v.id == d.resumeVideoId && d.resumeMs > 0
            return "\(resuming ? "Resume" : "Play") S\(s), E\(e)"
        }
        return d.resumeMs > 0 && d.resumeVideoId == ref.id ? "Resume" : "Play"
    }

    private var episodeLine: String? {
        guard let d = details, let v = d.videos.first(where: { $0.id == d.videoId }), let s = v.season, let e = v.episode else { return nil }
        return "S\(s), E\(e) · \(v.title)"
    }

    private var imdbId: String? { ref.id.wholeMatch(of: /tt\d+/) != nil ? ref.id : nil }

    // MARK: - The top: logo, what it is, buttons

    private var header: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 0)
            TitleLogo(title: title, maxHeight: 190, textSize: 72, alignment: .leading)
                .frame(maxWidth: 720, alignment: .leading)
            Text(([typeName(title.type), title.year, title.runtime].compactMap { $0 } + title.genres.prefix(3)).joined(separator: " · "))
                .font(.headline)
                .foregroundStyle(Dx.muted)
            if let scores = reviews?.scores, !scores.isEmpty {
                HStack(spacing: 30) {
                    ForEach(scores.prefix(5)) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.value).font(.headline)
                            Text(s.name).font(.caption).foregroundStyle(Dx.muted)
                        }
                    }
                }
            }
            if let d = title.description {
                Text(d).font(.callout).foregroundStyle(.white.opacity(0.85)).lineLimit(3).frame(maxWidth: 1000, alignment: .leading)
            }
            buttons.padding(.top, 10)
        }
        .padding(.horizontal, TV.gutter)
        .frame(minHeight: 860, alignment: .bottomLeading)
    }

    private var buttons: some View {
        let inList = title.inLibrary
        return HStack(spacing: 24) {
            Button { if details?.state == .ready { start(details.flatMap(nextVideo)?.id) } } label: {
                Label(playLabel, systemImage: "play.fill").padding(.horizontal, 16)
            }
            .buttonStyle(.borderedProminent)
            .opacity(details?.state == .ready ? 1 : 0.6)
            .focused($playFocused)
            Button {
                stremio.setInLibrary(!inList)
                stremio.show(inList ? "Removed from your Library" : "Added to your Library")
            } label: {
                Label("My List", systemImage: inList ? "checkmark" : "plus")
            }
            if details?.videoId != nil {
                Button { streamsOpen = true } label: { Label("Streams", systemImage: "list.bullet") }
            }
            Button { stremio.setWatched(!title.watched) } label: {
                Label(title.watched ? "Watched" : "Mark Watched", systemImage: title.watched ? "eye.fill" : "eye")
            }
            Button { reviewsOpen = true } label: { Label("Reviews", systemImage: "star") }
            Button { aboutOpen = true } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("About")
        }
    }

    // MARK: - Seasons and episodes

    @ViewBuilder
    private var episodes: some View {
        if let d = details, !d.videos.isEmpty {
            let shown = d.videos.filter { $0.season == (season ?? d.seasons.first) }
            VStack(alignment: .leading, spacing: 24) {
                if d.seasons.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 20) {
                            ForEach(d.seasons, id: \.self) { s in
                                let on = s == (season ?? d.seasons.first)
                                Button { season = s } label: { Text(s == 0 ? "Specials" : "Season \(s)").fontWeight(on ? .bold : .regular) }
                                    .buttonStyle(.bordered)
                                    .tint(on ? .white : nil)
                            }
                        }
                        .padding(.horizontal, TV.gutter)
                        .padding(.vertical, 12)
                    }
                    .scrollClipDisabled()
                    .scrollIndicators(.hidden)
                } else {
                    let s = season ?? d.seasons.first ?? 1
                    Text(s == 0 ? "Specials" : "Season \(s)").font(.title3.bold()).padding(.horizontal, TV.gutter)
                }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: TV.rowSpacing) {
                        ForEach(shown) { v in episodeButton(v, d: d) }
                    }
                    .padding(.horizontal, TV.gutter)
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()
                .scrollIndicators(.hidden)
            }
        }
    }

    private func episodeButton(_ v: Video, d: Details) -> some View {
        Button { start(v.id) } label: {
            EpisodeCard(video: v, width: 440, fallbackArt: title.backdrop, playing: v.id == nextVideo(d)?.id)
        }
        .buttonStyle(Lift())
        .contextMenu {
            Button { start(v.id) } label: { Label("Play", systemImage: "play.fill") }
            Button {
                choices = nil
                stremio.open(ref.type, ref.id, videoId: v.id)
                streamsOpen = true
            } label: { Label("Choose a Stream", systemImage: "list.bullet") }
            if v.watched {
                Button { stremio.setWatched(video: v.id, false) } label: { Label("Mark as Unwatched", systemImage: "eye.slash") }
            } else {
                Button { stremio.setWatched(video: v.id, true) } label: { Label("Mark as Watched", systemImage: "eye") }
            }
            if (v.episode ?? 0) > 1 {
                Button { stremio.setWatched(video: v.id, true, upTo: true) } label: { Label("Mark Up to Here as Watched", systemImage: "checkmark.circle") }
            }
        }
    }

    // MARK: - Cast and crew

    @ViewBuilder
    private var people: some View {
        let list: [(String, String?, String?)] = {
            if let cast, !cast.isEmpty { return cast.map { ($0.string("name"), $0.text("role"), $0.text("photo")) } }
            guard let d = details else { return [] }
            return d.directors.prefix(3).map { ($0, "Director", nil) } + d.cast.prefix(15).map { ($0, nil, nil) }
        }()
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text("Cast & Crew").font(.title3.bold()).padding(.horizontal, TV.gutter)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 36) {
                        ForEach(Array(list.enumerated()), id: \.offset) { _, p in person(name: p.0, role: p.1, photo: p.2) }
                    }
                    .padding(.horizontal, TV.gutter)
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()
                .scrollIndicators(.hidden)
            }
        }
    }

    /** Someone in it: pressing them searches for them, as on the desktop */
    private func person(name: String, role: String?, photo: String?) -> some View {
        VStack(spacing: 12) {
            Button { stremio.searchFor(name) } label: {
                ZStack {
                    Dx.raised
                    Text(name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()).font(.title2.weight(.semibold))
                    if let photo, let url = URL(string: photo) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                        }
                    }
                }
                .frame(width: 160, height: 160)
                .clipShape(.circle)
            }
            .buttonStyle(Lift())
            Text(name).font(.callout).lineLimit(2).multilineTextAlignment(.center)
            if let role, !role.isEmpty { Text(role).font(.caption).foregroundStyle(Dx.muted).lineLimit(1) }
        }
        .frame(width: 190)
    }
}

/** All of a title's description and facts (the page shows three lines) */
private struct AboutView: View {
    var title: Title
    var details: Details?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text(title.name).font(.title2.bold())
                Text(([typeName(title.type), title.year, title.runtime].compactMap { $0 } + title.genres).joined(separator: " · "))
                    .foregroundStyle(Dx.muted)
                if let d = title.description { Text(d).font(.body) }
                if let d = details {
                    if !d.directors.isEmpty { fact("Directed by", d.directors.joined(separator: ", ")) }
                    if !d.cast.isEmpty { fact("Starring", d.cast.prefix(12).joined(separator: ", ")) }
                }
            }
            .frame(maxWidth: 1200, alignment: .leading)
            .padding(60)
            .focusable()
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.headline).foregroundStyle(Dx.muted)
            Text(value)
        }
    }
}
