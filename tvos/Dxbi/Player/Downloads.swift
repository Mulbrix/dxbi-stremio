// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import Foundation
import Observation

/**
 * Downloads, as the shared code knows them (ios/Dxbi/Player/Downloads.swift). An Apple TV gives apps
 * no lasting storage for films (only caches tvOS can empty at any time), so there are none here: the
 * screens don't offer them, and a stream sent here plays instead.
 */
@MainActor
@Observable
final class Downloads {
    static let shared = Downloads()

    struct Item: Identifiable {
        var id: String
        var payload: JSON
    }

    private(set) var items: [Item] = []
    @ObservationIgnored weak var stremio: Stremio?
    @ObservationIgnored var backgroundDone: (() -> Void)?

    func add(_ payload: JSON) { stremio?.show("Apple TV keeps no downloads: play it instead") }
    func playback(_ item: Item) -> JSON? { nil }
    func leftAt(_ id: String, ms: Double, ended: Bool) {}
}
