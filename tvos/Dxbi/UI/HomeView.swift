// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import SwiftUI

extension Array where Element == Title {
    /** Each title once (addons sometimes list one twice, and SwiftUI's rows need each just once) */
    var unique: [Title] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}

/** TV sizes */
enum TV {
    /** tvOS's own side margin */
    static let gutter: CGFloat = 80
    static let poster: CGFloat = 220
    static let wide: CGFloat = 500
    static let rowSpacing: CGFloat = 40
}

/**
 * Home: a billboard at the top (the title's art across the screen, its logo, Play and My List), then
 * Continue Watching, dx.bi's own rows and the addons' catalogs in the viewer's order, each ending in
 * See All.
 */
struct HomeView: View {
    @Environment(Stremio.self) private var stremio

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 56) {
                if !stremio.billboard.isEmpty {
                    Billboard(titles: stremio.billboard)
                } else {
                    Logo(size: 80).padding(.horizontal, TV.gutter).padding(.top, 40)
                }
                if !stremio.continueWatching.isEmpty {
                    Shelf(title: "Continue Watching") {
                        ForEach(stremio.continueWatching) { item in ContinueTile(item: item) }
                    }
                }
                ForEach(Array(stremio.myList.enumerated()), id: \.offset) { _, row in
                    if !row.items.isEmpty { titleRow(row.name, row.items, see: .library) }
                }
                if let forYou = stremio.forYou { titleRow(forYou.name, forYou.items) }
                if !stremio.airing.isEmpty {
                    Shelf(title: "New Episodes This Week") {
                        ForEach(stremio.airing) { item in
                            NavigationLink(value: Route.title(TitleRef(type: "series", id: item.id, name: item.name))) {
                                AiringCard(item: item, width: TV.wide)
                            }
                            .buttonStyle(Lift())
                        }
                    }
                }
                ForEach(Array(stremio.rows.enumerated()), id: \.element.id) { i, row in
                    if row.state == .ready && !row.items.isEmpty {
                        // Netflix's Top 10: the first row is numbered
                        titleRow(row.heading, row.items, rank: i == 0, see: row.discover.map { .browse(link: $0, name: row.heading) })
                    } else if row.state == .loading {
                        loadingRow(row.heading)
                    }
                }
                if stremio.rows.isEmpty && stremio.ready {
                    ContentUnavailableView("Nothing to show yet", systemImage: "puzzlepiece.extension", description: Text("Install addons to fill Home: Profile, then Addons."))
                        .focusable()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        .ignoresSafeArea(edges: .top)
        .screenBackground()
    }

    private func titleRow(_ name: String, _ items: [Title], rank: Bool = false, see: Route? = nil) -> some View {
        Shelf(title: name, see: see) {
            ForEach(Array(items.unique.prefix(rank ? 10 : 30).enumerated()), id: \.element.id) { i, title in
                PosterButton(title: title, rank: rank ? i + 1 : nil)
            }
        }
    }

    private func loadingRow(_ name: String) -> some View {
        Shelf(title: name) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 18).fill(Dx.raised).frame(width: TV.poster, height: TV.poster * 1.5)
            }
        }
        .redacted(reason: .placeholder)
    }
}

/**
 * How a card shows the remote's focus: it grows and lifts off the page, as tvOS's own cards do, but
 * without tvOS's card style's grey backing (its corners showed round the cards' own)
 */
struct Lift: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { LiftedLabel(configuration: configuration) }

    private struct LiftedLabel: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 1.03 : focused ? 1.1 : 1)
                .brightness(focused ? 0.06 : 0)
                .shadow(color: .black.opacity(focused ? 0.7 : 0), radius: focused ? 24 : 0, y: focused ? 16 : 0)
                .zIndex(focused ? 1 : 0)
                .animation(.easeOut(duration: 0.18), value: focused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/** A titled row of cards that scrolls sideways as the focus moves along it; See All at its end */
struct Shelf<Content: View>: View {
    var title: String
    var see: Route?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.title3.bold()).lineLimit(1).padding(.horizontal, TV.gutter)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: TV.rowSpacing) {
                    content
                    if let see {
                        NavigationLink(value: see) {
                            VStack(spacing: 12) {
                                Image(systemName: "square.grid.2x2.fill").font(.system(size: 40))
                                Text("See All").font(.headline)
                            }
                            .frame(width: TV.poster * 0.8, height: TV.poster * 1.5)
                            .foregroundStyle(.white)
                            .background(Dx.raised, in: .rect(cornerRadius: 18))
                        }
                        .buttonStyle(Lift())
                    }
                }
                .padding(.horizontal, TV.gutter)
                .padding(.vertical, 24)
            }
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
        }
    }
}

/** A poster that opens its title; held down, Play or Details */
struct PosterButton: View {
    var title: Title
    var rank: Int?
    var width: CGFloat = TV.poster

    var body: some View {
        NavigationLink(value: Route.title(title.ref)) {
            PosterCard(title: title, width: width, rank: rank)
        }
        .buttonStyle(Lift())
        .contextMenu { TitleMenu(title: title) }
    }
}

/** Held down on a title */
struct TitleMenu: View {
    var title: Title
    var body: some View {
        NavigationLink(value: Route.title(TitleRef(type: title.type, id: title.id, name: title.name, play: true))) { Label("Play", systemImage: "play.fill") }
        NavigationLink(value: Route.title(title.ref)) { Label("Details", systemImage: "info.circle") }
    }
}

/** Continue Watching: plays where they left off; held down, the rest */
private struct ContinueTile: View {
    @Environment(Stremio.self) private var stremio
    var item: Continue

    var body: some View {
        NavigationLink(value: Route.title(TitleRef(type: item.title.type, id: item.title.id, name: item.title.name, play: true))) {
            ContinueCard(item: item, width: TV.wide)
        }
        .buttonStyle(Lift())
        .contextMenu {
            NavigationLink(value: Route.title(item.title.ref)) { Label("Details", systemImage: "info.circle") }
            Button(role: .destructive) { stremio.removeFromContinue(item.title.id) } label: { Label("Remove from Continue Watching", systemImage: "eye.slash") }
        }
    }
}

/**
 * The billboard at the top of Home: one title at a time, across the screen, fading into the next every
 * few seconds (Next goes on at once)
 */
private struct Billboard: View {
    @Environment(Stremio.self) private var stremio
    var titles: [Title]
    @State private var index = 0
    @FocusState private var focused: Int?

    /** [index] within the titles there are now (the list can get shorter while it's showing) */
    private var shown: Int { titles.isEmpty ? 0 : index % titles.count }
    private var current: Title { titles[shown] }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                ForEach(Array(titles.enumerated()), id: \.element.id) { i, title in
                    if i == shown { picture(title).transition(.opacity) }
                }
            }
            info(current)
        }
        .frame(height: 900)
        .frame(maxWidth: .infinity)
        // turns by itself; moving about on it starts the wait again
        .task(id: "\(index)-\(titles.count)-\(focused ?? -1)") {
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled && titles.count > 1 { go(shown + 1) }
        }
    }

    private func go(_ i: Int) {
        guard !titles.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.8)) { index = (i + titles.count) % titles.count }
    }

    private func picture(_ title: Title) -> some View {
        Color.clear
            .overlay { Art(url: title.backdrop) }
            .clipped()
            .overlay(LinearGradient(stops: [.init(color: .black.opacity(0.85), location: 0), .init(color: .black.opacity(0.3), location: 0.45), .init(color: .clear, location: 0.7)], startPoint: .leading, endPoint: .trailing))
            .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.5), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea()
    }

    private func info(_ title: Title) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Group {
                TitleLogo(title: title, maxHeight: 170, textSize: 64, alignment: .leading)
                    .frame(maxWidth: 640, alignment: .leading)
                Text(([typeName(title.type), title.year].compactMap { $0 } + title.genres.prefix(2)).joined(separator: " · "))
                    .font(.headline)
                    .foregroundStyle(Dx.muted)
                if let d = title.description {
                    Text(d).font(.callout).foregroundStyle(.white.opacity(0.8)).lineLimit(3).frame(maxWidth: 860, alignment: .leading)
                }
            }
            .id(title.id)
            .transition(.opacity)
            HStack(spacing: 24) {
                NavigationLink(value: Route.title(TitleRef(type: title.type, id: title.id, name: title.name, play: true))) {
                    Label("Play", systemImage: "play.fill").padding(.horizontal, 20)
                }
                .focused($focused, equals: 0)
                NavigationLink(value: Route.title(title.ref)) {
                    Label("More Info", systemImage: "info.circle")
                }
                .focused($focused, equals: 1)
                Button {
                    stremio.setInLibrary(title, !title.inLibrary)
                    stremio.show(title.inLibrary ? "Removed from your Library" : "Added to your Library")
                } label: {
                    Label("My List", systemImage: title.inLibrary ? "checkmark" : "plus")
                }
                .focused($focused, equals: 2)
                if titles.count > 1 {
                    Button { go(shown + 1) } label: { Image(systemName: "chevron.right") }
                        .focused($focused, equals: 3)
                        .accessibilityLabel("Next")
                }
            }
            .padding(.top, 10)
            HStack(spacing: 10) {
                ForEach(titles.indices, id: \.self) { i in
                    Capsule().fill(i == shown ? .white : .white.opacity(0.35)).frame(width: i == shown ? 28 : 9, height: 9)
                }
            }
            .animation(.snappy, value: shown)
            .padding(.top, 6)
        }
        .padding(.horizontal, TV.gutter)
        .padding(.bottom, 40)
    }
}

/** The signed-in person: their initial */
struct Avatar: View {
    var email: String?
    var size: CGFloat = 60
    var body: some View {
        Text(String((email ?? "?").prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .semibold))
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(red: 0.35, green: 0.6, blue: 0.75), Color(red: 0.2, green: 0.4, blue: 0.55)], startPoint: .top, endPoint: .bottom), in: .circle)
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
}
