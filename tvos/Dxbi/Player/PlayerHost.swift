// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import SwiftUI
import UIKit

/**
 * The player's own screen, over the app. (Stremio's page stays where it is, in the window behind
 * everything: see PageAnchor, so it keeps hearing from the player while it shows.)
 */
final class PlayerHost: UIHostingController<AnyView> {

    private static weak var shown: PlayerHost?
    private weak var playback: Playback?
    private weak var stremio: Stremio?

    @MainActor
    static func show(_ playback: Playback, stremio: Stremio) {
        if let old = shown {
            shown = nil
            old.dismiss(animated: false)
        }
        let host = PlayerHost(rootView: AnyView(PlayerScreen(playback: playback).environment(stremio).preferredColorScheme(.dark)))
        host.playback = playback
        host.stremio = stremio
        host.modalPresentationStyle = .fullScreen
        host.view.backgroundColor = .black
        shown = host
        present(host, tries: 0)
    }

    /** tvOS won't show it while something else is coming or going (the stream list closing as Play is pressed): it waits */
    @MainActor
    private static func present(_ host: PlayerHost, tries: Int) {
        guard shown === host, host.presentingViewController == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var top = scene.keyWindow?.rootViewController ?? scene.windows.first?.rootViewController else { return giveUp(host) }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        let busy = top.transitionCoordinator != nil || top.isBeingDismissed || top.isBeingPresented || top.presentedViewController != nil
        if busy {
            guard tries < 40 else { return giveUp(host) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { present(host, tries: tries + 1) }
            return
        }
        top.present(host, animated: true)
    }

    /** It couldn't be shown: the stream stops too, rather than play on with no screen to stop it from */
    @MainActor
    private static func giveUp(_ host: PlayerHost) {
        guard shown === host else { return }
        shown = nil
        host.playback?.finish(ended: false)
        host.stremio?.show("The player couldn't open: try again")
    }

    @MainActor
    /** [next]: the next episode's player follows (the TV stays in its mode for it) */
    static func hide(next: Bool = false) {
        guard let host = shown else { return }
        shown = nil
        DisplayMatch.reset(keep: next)
        host.dismiss(animated: true) {
            // the remote's focus back on the app's screens (left nowhere, Menu would leave the app)
            Refocus.now()
        }
    }

    /** Gone some other way than closing (tvOS took it away): the stream stops and Stremio hears where it got to */
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if Self.shown === self {
            Self.shown = nil
            DisplayMatch.reset(keep: false)
            playback?.finish(ended: false)
        }
    }
}
