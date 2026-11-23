// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import SwiftUI

/**
 * The streams for one film or episode, as dx.bi's stream list shows them (ios/Dxbi/UI/StreamsSheet.swift):
 * dx.bi's pick at the top, then every stream with its file name, quality, HDR, source, codec,
 * languages, size and seeds, to filter and sort.
 */
struct StreamsView: View {
    var choices: StreamChoices?
    var heading: String
    var subheading: String?
    var onPlay: (StreamOption, Stremio.Target) -> Void

    private enum Sort: String, CaseIterable {
        case best = "Best Quality", seeds = "Most Seeds", largest = "Largest First", smallest = "Smallest First", addon = "Addon Order"
    }

    @State private var sort = Sort.best
    @State private var quality: String?
    @State private var provider: String?
    @State private var instantOnly = false

    private var all: [StreamOption] { choices?.items ?? [] }

    private var shown: [StreamOption] {
        let kept = all.filter { (quality == nil || $0.quality == quality) && (provider == nil || $0.provider == provider) && (!instantOnly || $0.instant) }
        switch sort {
        case .best: return kept.sorted(by: StreamOption.best)
        case .seeds: return kept.sorted { $0.seeds > $1.seeds }
        case .largest: return kept.sorted { $0.size > $1.size }
        case .smallest: return kept.sorted { ($0.size > 0 ? $0.size : .infinity) < ($1.size > 0 ? $1.size : .infinity) }
        case .addon: return kept
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(heading).font(.title2.bold())
                    if let subheading { Text(subheading).font(.headline).foregroundStyle(Dx.muted) }
                }
                if let best = choices?.picked { pick(best) }
                if all.count > 1 { filters }
                ForEach(shown) { s in row(s, picked: s.index == choices?.pick) }
                status
            }
            .frame(maxWidth: 1400)
            .padding(.horizontal, TV.gutter)
            .padding(.vertical, 50)
            .frame(maxWidth: .infinity)
        }
        .scrollClipDisabled()
        .background(Color.black.opacity(0.6).ignoresSafeArea())
    }

    private func pick(_ best: StreamOption) -> some View {
        Button { onPlay(best, .player) } label: {
            HStack(spacing: 24) {
                Image(systemName: "play.fill").font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(choices?.sameAsLastTime == true ? "Play · Same as Last Time" : "Play the Best Stream").font(.headline)
                    Text([best.label, best.provider, best.sizeText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.callout).opacity(0.75).lineLimit(1)
                    if !best.filename.isEmpty { Text(best.filename).font(.callout).opacity(0.6).lineLimit(2) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if best.instant { Image(systemName: "bolt.fill").foregroundStyle(.green) }
            }
            .padding(24)
        }
        .buttonStyle(.borderedProminent)
    }

    private var filters: some View {
        let qualities = Array(Set(all.map(\.quality))).sorted { a, b in (all.first { $0.quality == a }?.res ?? 0) > (all.first { $0.quality == b }?.res ?? 0) }
        let providers = Array(Set(all.map(\.provider).filter { !$0.isEmpty })).sorted()
        return HStack(spacing: 20) {
            Menu {
                Picker("Sort", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            } label: { Label(sort.rawValue, systemImage: "arrow.up.arrow.down") }
            if qualities.count > 1 {
                Menu {
                    Picker("Quality", selection: $quality) {
                        Text("Any Quality").tag(String?.none)
                        ForEach(qualities, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                } label: { Label(quality ?? "Any Quality", systemImage: "sparkles.tv") }
            }
            if providers.count > 1 {
                Menu {
                    Picker("Source", selection: $provider) {
                        Text("Any Source").tag(String?.none)
                        ForEach(providers, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                } label: { Label(provider ?? "Any Source", systemImage: "server.rack") }
            }
            if all.contains(where: \.instant) && all.contains(where: { !$0.instant }) {
                Button { instantOnly.toggle() } label: { Label("Instant Only", systemImage: instantOnly ? "bolt.fill" : "bolt") }
                    .tint(instantOnly ? .white : nil)
            }
        }
    }

    private func row(_ s: StreamOption, picked: Bool) -> some View {
        Button { onPlay(s, .player) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Badge(text: s.quality, filled: true)
                    if s.dv { Badge(text: "DOLBY VISION") } else if s.hdr { Badge(text: "HDR") }
                    if !s.source.isEmpty && s.source != "Other" { Badge(text: s.source.uppercased(), colour: s.source == "CAM" ? .red : .white) }
                    if !s.codec.isEmpty { Badge(text: s.codec) }
                    Spacer(minLength: 0)
                    if s.instant { Badge(text: "INSTANT", colour: .green) }
                    else if s.pending { Badge(text: "NOT CACHED", colour: .yellow) }
                    else if s.torrent { Badge(text: "TORRENT", colour: Dx.muted) }
                    if picked { Badge(text: "DX.BI'S PICK", colour: Dx.accent) }
                }
                // the file name, always: it says what the stream really is
                if !s.filename.isEmpty {
                    Text(s.filename).font(.callout).lineLimit(2).multilineTextAlignment(.leading)
                }
                Text(Array(Set([s.provider, s.site])).filter { !$0.isEmpty }.sorted().joined(separator: " · "))
                    .font(s.filename.isEmpty ? .headline : .callout.weight(.semibold))
                    .foregroundStyle(s.filename.isEmpty ? .primary : .secondary)
                    .lineLimit(1)
                let facts = [s.sizeText, s.seeds >= 0 ? "\(s.seeds) seeds" : nil, s.langs.filter { !$0.hasPrefix("Not listed") }.joined(separator: ", ").ifEmpty("-"), s.addon != s.provider ? s.addon : nil]
                    .compactMap { $0 }.filter { !$0.isEmpty && $0 != "-" }
                if !facts.isEmpty { Text(facts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                if s.lesser { Text("Upscaled, high frame rate or 3D: may not look as good as it says").font(.caption).foregroundStyle(.tertiary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .buttonStyle(.bordered)
        .contextMenu {
            Button { onPlay(s, .player) } label: { Label("Play", systemImage: "play.fill") }
            Button { onPlay(s, .otherApp) } label: { Label("Play in Another App", systemImage: "arrow.up.forward.app") }
        }
    }

    @ViewBuilder
    private var status: some View {
        if choices == nil || choices?.settled == false {
            HStack(spacing: 16) {
                ProgressView()
                Text(all.isEmpty ? "Finding streams…" : "More addons answering…").foregroundStyle(Dx.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(30)
        } else if all.isEmpty {
            ContentUnavailableView("No Streams", systemImage: "play.slash", description: Text("Your addons may not have this one yet."))
                .focusable()
        } else if shown.isEmpty {
            Text("Nothing matches those filters.").foregroundStyle(Dx.muted).padding()
        }
    }
}

/** Scores and reviews: MDBList, Wikidata, TMDB (with keys set in dx.bi settings) */
struct ReviewsView: View {
    var title: Title
    var reviews: Reviews?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                Text(title.name).font(.title2.bold())
                if let r = reviews {
                    if !r.scores.isEmpty {
                        HStack(spacing: 40) {
                            ForEach(r.scores) { s in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(s.value).font(.title3.bold())
                                    Text(s.name).font(.headline)
                                    if !s.note.isEmpty { Text(s.note).font(.caption).foregroundStyle(Dx.muted) }
                                }
                            }
                        }
                        .focusable()
                    }
                    if !r.critics.isEmpty {
                        section("Critics") { ForEach(r.critics, id: \.self) { Text($0).font(.callout).focusable() } }
                    }
                    section(r.audienceTotal > 0 ? "Audience · \(r.audienceTotal)" : "Audience") {
                        if r.audience.isEmpty {
                            Text(r.audienceProblem ?? "No audience reviews for this one.").foregroundStyle(Dx.muted).focusable()
                        }
                        ForEach(r.audience) { review in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 16) {
                                    Text(review.author).font(.headline)
                                    if let rating = review.rating { Label(String(format: "%.0f", rating), systemImage: "star.fill").font(.callout).foregroundStyle(.yellow) }
                                    Spacer()
                                    Text(review.date).font(.caption).foregroundStyle(Dx.muted)
                                }
                                Text(review.text).font(.callout).lineLimit(10)
                            }
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Dx.raised, in: .rect(cornerRadius: 20))
                            .focusable()
                        }
                    }
                    if let p = r.problem { Text(p).font(.caption).foregroundStyle(Dx.muted).focusable() }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(60)
                }
            }
            .frame(maxWidth: 1400, alignment: .leading)
            .padding(60)
            .frame(maxWidth: .infinity)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title3.bold())
            content()
        }
    }
}
