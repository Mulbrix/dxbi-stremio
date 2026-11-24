// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import SwiftUI

/** Posters in a grid across the screen; [onEnd] when the focus nears the last ones (the next page) */
struct PosterGrid: View {
    var items: [Title]
    var onEnd: (() -> Void)?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: TV.poster, maximum: TV.poster + 20), spacing: TV.rowSpacing)], spacing: 60) {
            let shown = items.unique
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, title in
                PosterButton(title: title)
                    .onAppear { if i >= shown.count - 6 { onEnd?() } }
            }
        }
        .padding(.horizontal, TV.gutter)
    }
}

// MARK: - Search

/**
 * Search: tvOS's own keyboard (a text field, which also takes typing from an iPhone), searched when
 * it's sent, then a row of results from each addon. (SwiftUI's searchable froze the app on Apple TV.)
 */
struct SearchView: View {
    @Environment(Stremio.self) private var stremio
    @State private var query = ""
    @State private var searched = ""
    @AppStorage("recentSearches") private var recentText = ""
    @FocusState private var fieldFocused: Bool

    private var recent: [String] { recentText.split(separator: "\n").map(String.init) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                HStack(spacing: 24) {
                    TextField("Search films, shows, people", text: $query)
                        .focused($fieldFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit(run)
                        .frame(maxWidth: 1100)
                    if !searched.isEmpty {
                        Button("Clear") {
                            query = ""
                            searched = ""
                            fieldFocused = true
                        }
                    }
                }
                .padding(.horizontal, TV.gutter)
                .padding(.top, 30)
                if searched.isEmpty { start } else { results }
            }
            .padding(.bottom, 60)
        }
        .scrollClipDisabled()
        .screenBackground()
        // a name pressed on a title's page
        .onChange(of: stremio.pendingSearch, initial: true) { _, q in
            guard let q else { return }
            stremio.pendingSearch = nil
            query = q
            run()
        }
    }

    @ViewBuilder
    private var start: some View {
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text("Recent Searches").font(.title3.bold()).padding(.horizontal, TV.gutter)
                ScrollView(.horizontal) {
                    HStack(spacing: 20) {
                        ForEach(recent, id: \.self) { r in
                            Button { query = r; run() } label: { Label(r, systemImage: "clock.arrow.circlepath") }
                        }
                        Button("Clear") { recentText = "" }
                    }
                    .padding(.horizontal, TV.gutter)
                    .padding(.vertical, 12)
                }
                .scrollClipDisabled()
                .scrollIndicators(.hidden)
            }
        } else {
            Text("Films, series and anime; actors, directors and writers; channels and TV from your addons.")
                .font(.headline)
                .foregroundStyle(Dx.muted)
                .padding(.horizontal, TV.gutter)
        }
    }

    @ViewBuilder
    private var results: some View {
        let rows = stremio.search.filter { !$0.items.isEmpty }
        if rows.isEmpty {
            if stremio.search.contains(where: { $0.state == .loading }) || stremio.search.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(60)
            } else {
                Text("Nothing found for “\(searched)”. Check the spelling, or try another name.")
                    .font(.headline)
                    .foregroundStyle(Dx.muted)
                    .padding(.horizontal, TV.gutter)
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 56) {
                ForEach(rows) { row in
                    Shelf(title: row.heading, see: row.discover.map { .browse(link: $0, name: row.heading) }) {
                        ForEach(row.items.unique) { title in PosterButton(title: title) }
                    }
                }
            }
        }
    }

    private func run() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, q != searched || stremio.search.isEmpty else { return }
        searched = q
        stremio.search(q)
        recentText = ([q] + recent.filter { $0.caseInsensitiveCompare(q) != .orderedSame }).prefix(8).joined(separator: "\n")
    }
}

// MARK: - Discover

/**
 * Which catalog a Discover request is (its type, catalog and genre; not the page), to tell Discover's
 * own from a See All's: the two share Stremio's one Discover. (Not the addon's address: the page may
 * write it otherwise than the link did, and a See All would then wait for ever.)
 */
func catalogKey(_ request: JSON?) -> String? {
    guard let request, let path = request.object("path") else { return nil }
    let extra = ((path["extra"] as? [Any]) ?? []).compactMap { $0 as? [String] }
    let genre = extra.first { $0.first == "genre" }?.last ?? ""
    return [path.string("type"), path.string("id"), genre].joined(separator: "|")
}

/** Every catalog the addons have, by type, catalog and genre */
struct DiscoverView: View {
    @Environment(Stremio.self) private var stremio
    /** The catalog chosen here last (a See All may have shown another one since) */
    @State private var mine: JSON?
    @State private var showing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if let d = stremio.discover, mine == nil || catalogKey(d.request) == catalogKey(mine) {
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
        .onAppear {
            showing = true
            // back from a See All: Discover's own catalog again
            if let mine, catalogKey(mine) != catalogKey(stremio.discover?.request) { stremio.discover(request: mine) } else { stremio.discoverStart() }
        }
        .onDisappear { showing = false }
        .onChange(of: catalogKey(stremio.discover?.request)) {
            if showing, let request = stremio.discover?.request { mine = request }
        }
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
    @Environment(\.dismiss) private var dismiss
    var link: String
    var name: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                Text(name).font(.title2.bold()).padding(.horizontal, TV.gutter)
                // (until it's this row's catalog, Discover's is still there: not shown)
                if let d = stremio.discover, catalogKey(d.request) == catalogKey(Stremio.discoverRequest(link: link)) {
                    PosterGrid(items: d.items) { if d.nextPage { stremio.discoverMore() } }
                    if d.state == .loading { ProgressView().frame(maxWidth: .infinity).padding() }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(80)
                }
            }
            .padding(.vertical, 40)
        }
        .scrollClipDisabled()
        .screenBackground()
        .onAppear { stremio.discover(link: link) }
        .onExitCommand { dismiss() }
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
