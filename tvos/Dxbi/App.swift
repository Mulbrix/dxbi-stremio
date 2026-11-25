// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import SwiftUI
import UIKit

@main
struct DxbiApp: App {
    @State private var stremio: Stremio

    init() {
        // Posters and backdrops: kept so rows scroll and the app opens without fetching them again
        URLCache.shared = URLCache(memoryCapacity: 120 << 20, diskCapacity: 400 << 20)
        _stremio = State(initialValue: Stremio())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(stremio)
                .preferredColorScheme(.dark)
        }
    }
}

enum AppTab: Hashable { case home, discover, library, search, profile }

/** Where a tab's stack can go */
enum Route: Hashable {
    case title(TitleRef)
    /** A row's See All: a Discover link and the row's name */
    case browse(link: String, name: String)
    case library
}

struct RootView: View {
    @Environment(Stremio.self) private var stremio
    @State private var tab = AppTab.home
    @State private var update: Updates.Release?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // Stremio's page, working out of sight (it has to be in the window to keep running)
            PageAnchor(page: stremio.page.view).frame(width: 0, height: 0).accessibilityHidden(true)
            if let problem = stremio.page.problem {
                ContentUnavailableView("dx.bi can't start here", systemImage: "exclamationmark.tv", description: Text("\(problem). Report it in dx.bi's Discord with your Apple TV's model and tvOS version."))
            } else if stremio.account?.signedIn == true || stremio.guest {
                tabs
            } else {
                WelcomeView()
            }
        }
        .screenBackground()
        .overlay(alignment: .top) {
            if let message = stremio.message {
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 18)
                    .background(.regularMaterial, in: .capsule)
                    .padding(.top, 30)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(duration: 0.35), value: stremio.message)
        // A new release: told once when the app opens or comes back (every few hours at most)
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { if let found = await Updates.check() { update = found } }
        }
        .alert("dx.bi \(update?.version ?? "") is out", isPresented: Binding(get: { update != nil }, set: { if !$0 { update = nil } }), presenting: update) { release in
            Button("Skip This Version") { Updates.skip(release) }
            Button("OK", role: .cancel) {}
        } message: { _ in
            Text("You have \(Page.version). On a computer, download \(Updates.asset) from github.com/\(Updates.repo)/releases and install it over this one with Sideloadly: your sign-in and settings stay.")
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Stack { HomeView() }
                .tabItem { Text("Home") }
                .tag(AppTab.home)
            Stack { DiscoverView() }
                .tabItem { Text("Discover") }
                .tag(AppTab.discover)
            Stack { LibraryView() }
                .tabItem { Text("Library") }
                .tag(AppTab.library)
            Stack { SearchView() }
                .tabItem { Image(systemName: "magnifyingglass") }
                .tag(AppTab.search)
            Stack { AccountView() }
                .tabItem { Text(stremio.viewer?.name ?? "Profile") }
                .tag(AppTab.profile)
        }
        .onChange(of: stremio.pendingSearch) { _, q in if q != nil { tab = .search } }
    }
}

/** A tab's navigation, with every screen it can open */
struct Stack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .title(let ref): TitleView(ref: ref)
                    case .browse(let link, let name): BrowseView(link: link, name: name)
                    case .library: LibraryView()
                    }
                }
        }
    }
}

/**
 * Puts Stremio's page in the window, behind everything, once the app's screens are in it. There it
 * stays while the player and other screens come and go over it (a page out of the window stops).
 */
struct PageAnchor: UIViewRepresentable {
    let page: UIView?

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.page = page
        return anchor
    }

    func updateUIView(_ view: Anchor, context: Context) {}

    final class Anchor: UIView {
        weak var page: UIView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, let page, page.window !== window else { return }
            page.removeFromSuperview()
            page.frame = window.bounds
            page.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            // (not quite invisible: WebKit slows a page it thinks nobody can see)
            page.alpha = 0.02
            page.isUserInteractionEnabled = false
            window.insertSubview(page, at: 0)
            Refocus.watch(window)
        }
    }
}
