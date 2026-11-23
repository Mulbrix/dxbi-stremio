// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
// Only built, not installed: whether the iPhone app's player (MPVKit, Streamyfin's build) builds for tvOS.
import MPVKit
import SwiftUI

@main
struct MPVCheckApp: App {
    var body: some Scene {
        WindowGroup {
            Text("mpv client API \(mpv_client_api_version())")
        }
    }
}
