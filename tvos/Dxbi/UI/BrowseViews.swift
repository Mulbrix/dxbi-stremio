// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import SwiftUI

/** Posters in a grid across the screen; [onEnd] when the focus nears the last ones (the next page) */
struct PosterGrid: View {
    var items: [Title]
    var onEnd: (() -> Void)?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: TV.poster, maximum: TV.poster + 20), spacing: TV.rowSpacing)], spacing: 60) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, title in
                PosterButton(title: title)
                    .onAppear { if i >= items.count - 6 { onEnd?() } }
            }
        }
        .padding(.horizontal, TV.gutter)
    }
}

// MARK: - Search

struct SearchView: View {
    @Environment(Stremio.self) private var stremio
    @State private var query = ""
    @State private var searched = ""
    @AppStorage("recentSearches") private var recentText = ""

    private var recent: [String] { recentText.split(separator: "\n").map(String.init) }

    var body: some View {
        ScrollView {
            if searched.isEmpty {
                VStack(alignment: .leading, spacing: 24) {
                    if !recent.isEmpty {
                        Text("Recent Searches").font(.title3.bold())
                        ScrollView(.horizontal) {
                            HStack(spacing: 20) {
                                ForEach(recent, id: \.self) { r in
                                    Button { query = r; run() } label: { Label(r, systemImage: "clock.arrow.circlepath") }
                                }
                                Button("Clear") { recentText = "" }
                            }
                            .padding(.vertical, 12)
                        }
                        .scrollClipDisabled()
                    } else {
                        Text("Films, series and anime; actors, directors and writers; channels and TV from your addons.")
                            .font(.headline)
                            .foregroundStyle(Dx.muted)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, TV.gutter)
            } else {
                LazyVStack(alignment: .leading, spacing: 56) {
                    let rows = stremio.search.filter { !$0.items.isEmpty }
                    ForEach(rows) { row in
                        Shelf(title: row.heading, see: row.discover.map { .browse(link: $0, name: row.heading) }) {
                            ForEach(row.items) { title in PosterButton(title: title) }
                        }
                    }
                    if rows.isEmpty {
                        if stremio.search.contains(where: { $0.state == .loading }) || stremio.search.isEmpty {
                            ProgressView().frame(maxWidth: .infinity).padding(60)
                        } else {
                            ContentUnavailableView.search(text: searched).focusable()
                        }
                    }
                }
            }
        }
        .scrollClipDisabled()
        .padding(.bottom, 40)
        .screenBackground()
        .searchable(text: $query, prompt: "Films, shows, people")
        .onSubmit(of: .search, run)
        // a name pressed on a title's page
        .onChange(of: stremio.pendingSearch, initial: true) { _, q in
            guard let q else { return }
            stremio.pendingSearch = nil
            query = q
            run()
        }
        .onChange(of: query) { _, q in if q.isEmpty { searched = "" } }
        .task(id: query) {
            // as they type, after a moment's pause
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 3 else { return }
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled, q != searched { searched = q; stremio.search(q); remember(q) }
        }
    }

    private func run() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searched = q
        stremio.search(q)
        remember(q)
    }

    private func remember(_ q: String) {
        recentText = ([q] + recent.filter { $0 != q && !q.hasPrefix($0) }).prefix(8).joined(separator: "\n")
    }
}

// MARK: - Discover

/** Every catalog the addons have, by type, catalog and genre */
struct DiscoverView: View {
    @Environment(Stremio.self) private var stremio

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if let d = stremio.discover {
                    pickers(d)
                    PosterGrid(items: d.items) { if d.nextPage { stremio.discoverMore() } }
                    if d.state == .loading { ProgressView().frame(maxWidth: .infinity).padding() }
                    if d.state == .failed {
                        ContentUnavailableView("Nothing here", systemImage: "square.grid.2x2", description: Text("This catalog has nothing for that choice.")).focusable()
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(80)
                }
            }
            .padding(.bottom, 60)
        }
        .scrollClipDisabled()
        .screenBackground()
        .onAppear { stremio.discoverStart() }
        .onChange(of: stremio.allRows.count) { stremio.discoverStart() }
    }

    private func pickers(_ d: Discover) -> some View {
        HStack(spacing: 20) {
            ForEach(d.types) { t in
                Button { if let l = t.link { stremio.discover(link: l) } } label: {
                    Text(t.name == "movie" ? "Movies" : t.name == "series" ? "TV Shows" : typeName(t.name)).fontWeight(t.selected ? .bold : .regular)
                }
                .tint(t.selected ? .white : nil)
            }
            Menu {
                ForEach(d.catalogs) { c in
                    Button { if let l = c.link { stremio.discover(link: l) } } label: {
                        if c.selected { Label(c.name, systemImage: "checkmark") } else { Text(c.name) }
                    }
                }
            } label: {
                Label(d.catalogs.first(where: \.selected)?.name ?? "Catalog", systemImage: "list.bullet")
            }
            if !d.genres.isEmpty {
                Menu {
                    Button { stremio.discoverGenre(nil) } label: { if d.genre == nil { Label("All Genres", systemImage: "checkmark") } else { Text("All Genres") } }
                    ForEach(d.genres, id: \.self) { g in
                        Button { stremio.discoverGenre(g) } label: { if d.genre == g { Label(g, systemImage: "checkmark") } else { Text(g) } }
                    }
                } label: {
                    Label(d.genre ?? "All Genres", systemImage: "theatermasks")
                }
            }
        }
        .padding(.horizontal, TV.gutter)
        .padding(.top, 20)
    }
}

/** A row's See All */
struct BrowseView: View {
    @Environment(Stremio.self) private var stremio
    var link: String
    var name: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                Text(name).font(.title2.bold()).padding(.horizontal, TV.gutter)
                if let d = stremio.discover {
                    PosterGrid(items: d.items) { if d.nextPage { stremio.discoverMore() } }
                    if d.state == .loading { ProgressView().frame(maxWidth: .infinity).padding() }
                }
            }
            .padding(.vertical, 40)
        }
        .scrollClipDisabled()
        .screenBackground()
        .onAppear { stremio.discover(link: link) }
    }
}

// MARK: - Library

/** What's saved to their Stremio library (synced with their other devices) */
struct LibraryView: View {
    @Environment(Stremio.self) private var stremio
    @State private var type: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                HStack(spacing: 20) {
                    ForEach(["", "movie", "series"], id: \.self) { kind in
                        let value: String? = kind.isEmpty ? nil : kind
                        Button { type = value } label: {
                            Text(kind.isEmpty ? "All" : kind == "movie" ? "Movies" : "TV Shows").fontWeight(type == value ? .bold : .regular)
                        }
                        .tint(type == value ? .white : nil)
                    }
                }
                .padding(.horizontal, TV.gutter)
                .padding(.top, 20)
                if stremio.library.isEmpty {
                    ContentUnavailableView("Your Library Is Empty", systemImage: "rectangle.stack", description: Text("Press My List on a title to keep it here.")).focusable()
                } else {
                    PosterGrid(items: stremio.library) { stremio.libraryMore() }
                }
            }
            .padding(.bottom, 60)
        }
        .scrollClipDisabled()
        .screenBackground()
        .onAppear { stremio.loadLibrary(type) }
        .onChange(of: type) { _, t in stremio.loadLibrary(t) }
    }
}
