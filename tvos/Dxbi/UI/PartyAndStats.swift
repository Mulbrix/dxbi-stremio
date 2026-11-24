// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import Charts
import SwiftUI

/** dx.bi's watch party: start one or join with a code; everyone streams from their own addons */
struct PartyView: View {
    @Environment(Stremio.self) private var stremio
    @AppStorage("partyName") private var name = ""
    @State private var code = ""
    @State private var state: JSON?
    @State private var busy = false
    @State private var message = ""

    private var active: Bool { state?.bool("active") == true }

    var body: some View {
        List {
            if active, let state { lobby(state) } else { start }
        }
        .frame(maxWidth: 1400)
        .frame(maxWidth: .infinity)
        .navigationTitle("Watch Party")
        .task {
            // kept current while it's open: who's here, what's playing, the chat
            while !Task.isCancelled {
                state = await stremio.party()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    @ViewBuilder
    private var start: some View {
        Section {
            TextField("Your name", text: $name)
        } footer: {
            Text("Watch together, in sync, with friends anywhere: each of you plays from your own addons. End-to-end encrypted.")
        }
        Section("Start a party") {
            Button { go { await stremio.startParty(name: name) } } label: { Label("Start a Party", systemImage: "person.2.fill") }
                .disabled(name.isEmpty || busy)
        }
        Section("Join a party") {
            TextField("Party code", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button { go { await stremio.joinParty(code: code, name: name) } } label: { Label("Join", systemImage: "arrow.right.circle.fill") }
                .disabled(name.isEmpty || code.isEmpty || busy)
        }
    }

    @ViewBuilder
    private func lobby(_ s: JSON) -> some View {
        Section {
            VStack(spacing: 10) {
                Text(s.string("code")).font(.system(size: 76, weight: .bold, design: .monospaced))
                Text(s.bool("connected") ? "Connected · friends join with this code" : "Connecting…").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .focusable()
        }
        if let media = s.object("media") {
            Section("Playing") {
                Label(media.string("title"), systemImage: media.bool("playing") ? "play.fill" : "pause.fill").focusable()
            }
        }
        Section("People") {
            ForEach(Array(s.objects("members").enumerated()), id: \.offset) { _, m in
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.string("name") + (m.bool("self") ? " (you)" : "") + (m.bool("host") ? " · Host" : "")).font(.headline)
                    Text(m.string("line")).font(.caption).foregroundStyle(.secondary)
                }
                .focusable()
            }
        }
        Section("Chat") {
            ForEach(Array(s.objects("chat").enumerated()), id: \.offset) { _, m in
                Text("\(Text(m.string("name") + ":").bold()) \(m.string("text"))").focusable()
            }
            TextField("Say something", text: $message).onSubmit(say)
        }
        Section {
            Button("Leave Party", role: .destructive) { stremio.leaveParty() }
        }
    }

    private func say() {
        guard !message.isEmpty else { return }
        stremio.sayInParty(message)
        message = ""
    }

    private func go(_ work: @escaping () async -> String?) {
        busy = true
        Task {
            if let problem = await work() { stremio.show(problem) }
            state = await stremio.party()
            busy = false
        }
    }
}

/** Your stats: how long you've watched, what and when (dx.bi's Watch stats, counted on this Apple TV) */
struct StatsView: View {
    @Environment(Stremio.self) private var stremio
    @State private var stats: JSON?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            if let s = stats {
                content(s)
            } else if loaded {
                ContentUnavailableView("Watch Stats Are Off", systemImage: "chart.bar", description: Text("Turn on Watch stats in dx.bi Settings to count how long you watch."))
                    .padding(.top, 80)
                    .focusable()
            } else {
                ProgressView().padding(80)
            }
        }
        .screenBackground()
        .navigationTitle("Your Stats")
        .task {
            stats = await stremio.stats()
            loaded = true
        }
    }

    private func content(_ s: JSON) -> some View {
        let year = s.string("year")
        let since = Date(timeIntervalSince1970: s.double("since") / 1000)
        return VStack(alignment: .leading, spacing: 50) {
            Text("\(hours(s.double("total"))) in total · since \(since.formatted(date: .long, time: .omitted))")
                .font(.headline).foregroundStyle(Dx.muted)
            HStack(spacing: 30) {
                ForEach(Array(s.objects("tiles").enumerated()), id: \.offset) { _, t in
                    tile(t.string("label"), hours(t.double("sec")))
                }
                let streak = s.object("streak")
                tile("Streak", "\(streak?.int("current") ?? 0) days", note: "best \(streak?.int("best") ?? 0)")
            }
            .focusable()
            section("Last 30 Days") {
                Chart(Array(s.objects("days").enumerated()), id: \.offset) { _, d in
                    BarMark(x: .value("Day", day(d.string("day")), unit: .day), y: .value("Minutes", d.double("sec") / 60))
                        .foregroundStyle(Dx.accent.gradient)
                        .clipShape(.rect(cornerRadius: 4))
                }
                .chartYAxis { AxisMarks { v in AxisValueLabel { if let m = v.as(Double.self) { Text(hours(m * 60)) } } } }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: 300)
            }
            section("Most Watched in \(year)") {
                let top = s.objects("top")
                if top.isEmpty {
                    Text("Nothing yet this year. Start watching and it shows up here.").foregroundStyle(Dx.muted)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 520), spacing: 30)], alignment: .leading, spacing: 24) {
                    ForEach(Array(top.enumerated()), id: \.offset) { i, t in
                        HStack(spacing: 20) {
                            Text("\(i + 1)").font(.title2.bold()).frame(width: 50)
                            Art(url: URL(string: t.string("poster"))).frame(width: 80, height: 120).clipShape(.rect(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.string("name")).font(.headline).lineLimit(2)
                                Text("\(t.string("type") == "series" ? "Series" : "Film") · \(hours(t.double("sec")))").font(.callout).foregroundStyle(Dx.muted)
                            }
                        }
                    }
                }
            }
            section("Top Genres in \(year)") {
                let genres = s.objects("genres")
                let total = max(genres.reduce(0) { $0 + $1.double("sec") }, 1)
                if genres.isEmpty {
                    Text("Genres appear once you've watched a few titles.").foregroundStyle(Dx.muted)
                }
                ForEach(Array(genres.enumerated()), id: \.offset) { _, g in
                    let share = g.double("sec") / total
                    HStack(spacing: 20) {
                        Text(g.string("name")).frame(width: 240, alignment: .leading)
                        ProgressLine(value: share, colour: Dx.accent)
                        Text("\(Int((share * 100).rounded()))%").font(.callout.monospacedDigit()).frame(width: 80, alignment: .trailing)
                    }
                }
            }
            section("Habits") {
                fact("Favourite time", s.isNull("hour") ? "–" : String(format: "%02d:00–%02d:00", s.int("hour"), (s.int("hour") + 1) % 24))
                fact("Busiest day", s.text("day") ?? "–")
                fact("In your Stremio library", "\(s.int("movies")) films · \(s.int("series")) series")
            }
            Text("Stats stay on this Apple TV (saved with dx.bi's data). Only time spent actually playing counts.")
                .font(.caption).foregroundStyle(Dx.faint)
                .focusable()
        }
        .padding(.horizontal, TV.gutter)
        .padding(.vertical, 40)
    }

    private func tile(_ label: String, _ value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.callout).foregroundStyle(Dx.muted)
            Text(value).font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.7)
            if let note { Text(note).font(.caption).foregroundStyle(Dx.faint) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Dx.raised, in: .rect(cornerRadius: 24))
    }

    /** (each section takes the remote's focus, so the page scrolls to it) */
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.title3.bold())
            content()
        }
        .focusable()
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Dx.muted)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }

    private func hours(_ sec: Double) -> String {
        let s = Int(sec.rounded())
        if s < 60 { return s > 0 ? "<1m" : "0m" }
        let h = s / 3600, m = s % 3600 / 60
        return h > 0 ? String(format: "%dh %02dm", h, m) : "\(m)m"
    }

    /** The stats' day keys (2026-11-24): Gregorian whatever calendar the Apple TV is set to */
    private static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func day(_ key: String) -> Date {
        Self.dayKey.date(from: key) ?? .now
    }
}
