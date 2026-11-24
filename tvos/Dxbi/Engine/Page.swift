// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import Foundation
import UIKit

/**
 * Stremio's web app, running out of sight, as in the iPhone app (ios/Dxbi/Engine/Page.swift): it does
 * Stremio's work (account, addons, library, finding streams, watch progress) with dx.bi's plugin, and
 * the app's screens show it. The same page and scripts (dxbi-tv.js, dxbi-engine.js, dxbi.plugin.js),
 * with the same stand-in for Android's `DxbiTV` bridge, so the plugin runs as it does on the iPhone.
 *
 * The difference: tvOS keeps WebKit to itself, so the web view is DxWebView (WebKit found at run time).
 *
 * To the page: `window.__dxbiEngine.handle({id, op, args})`, run by [send].
 * From it: `{type: "reply", id, ok, data | error}`, `{type: "state", field, data}` for each watched
 * model as it changes, `{type: "event", event, args}` and `{type: "ready"}`.
 */
@MainActor
final class Page: NSObject {

    static let origin = "https://web.stremio.com"
    static let home = URL(string: "https://web.stremio.com/")!

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /** nil when WebKit wouldn't start on this Apple TV (see [problem]) */
    let web: DxWebView?
    /** Why there's no page, when there isn't */
    let problem: String?
    var view: UIView? { web?.view }

    private var ids = 0
    private var pending: [Int: CheckedContinuation<Any?, Error>] = [:]
    private var watched: [String] = []
    private var keeping: Task<Void, Never>?

    /** Stremio's core is up (it starts again with the page) */
    var onReady: (() -> Void)?
    var onGone: (() -> Void)?
    var onState: ((String, JSON?) -> Void)?
    var onEvent: ((String, JSON?) -> Void)?
    /** dxbi-tv.js handing a stream to the player (the play payload), and the watch party steering it */
    var onPlay: ((String) -> Void)?
    var onControl: ((JSON) -> Void)?
    var onToast: ((String) -> Void)?

    private static let settings = UserDefaults.standard

    override init() {
        // Stremio's web app is made for a computer's browser. dxbi-tv/ tells dx.bi it runs in the app
        // (no intro, the app's own player…); dxbi-ios that it's the iPhone app's engine
        let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15 dxbi-tv/\(Self.version) dxbi-ios dxbi-appletv"
        let web = DxWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), userScript: Self.startScript(), userAgent: agent, messageName: "dxbi")
        self.web = web
        problem = web == nil ? (DxWebView.unavailableReason() ?? "WebKit wouldn't start on this Apple TV") : nil
        super.init()
        guard let web else { return }
        web.onMessage = { [weak self] body, main, host in
            MainActor.assumeIsolated { self?.received(body, main: main, host: host) }
        }
        web.onNavigate = { url, main in
            // Embedded trailers stay in the page; it goes nowhere else (an Apple TV has no browser to send links to)
            guard let url else { return .allow }
            if !main || url.host == "web.stremio.com" || url.scheme == "about" { return .allow }
            return .cancel
        }
        web.onTerminate = { [weak self] in
            MainActor.assumeIsolated { self?.restart() }
        }
        web.load(Self.home)
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            // the clock changes (daylight saving) while the app is away
            MainActor.assumeIsolated { self?.js("window.__dxbiIos && (window.__dxbiIos.utcOffset = \(Self.utcOffset))") }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepStorage() }
        }
    }

    static var utcOffset: Int { TimeZone.current.secondsFromGMT() / 60 }

    /** The Apple TV's model identifier (AppleTV14,1) */
    static var model: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    // MARK: - What the page is given before it starts

    private static func resource(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil), let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    private static var savedSettings: JSON {
        (settings.string(forKey: "plugin-settings")).flatMap { Json.decode($0) as? JSON } ?? [:]
    }

    private static func startScript() -> String {
        let device: JSON = [
            "app": version,
            // (reports show this: the model, e.g. AppleTV14,1, and that it's the Apple TV app)
            "device": "\(model) · dx.bi for Apple TV",
            "ios": UIDevice.current.systemVersion,
            "tvos": UIDevice.current.systemVersion,
            "phone": true,
        ]
        let shim = """
        (function () {
          if (window.DxbiTV) return;
          // No Web Audio in the page: the app's player does the playing (and an audio context would
          // make the app's sound "ambient", which can't be Now Playing)
          for (const name of ["AudioContext", "webkitAudioContext", "OfflineAudioContext", "webkitOfflineAudioContext"]) {
            try { Object.defineProperty(window, name, { value: undefined, configurable: false, writable: false }); } catch (_) {}
          }
          const post = (message) => { try { window.webkit.messageHandlers.dxbi.postMessage(message); } catch (_) {} };
          const ios = (window.__dxbiIos = { settings: \(Json.encode(savedSettings)), plugin: \(Json.quote(resource("dxbi.plugin.js"))), active: "", pendingClose: "", utcOffset: \(utcOffset) });
          window.DxbiTV = {
            pluginSource: () => ios.plugin,
            getSettings: (t, plugin) => JSON.stringify(ios.settings[plugin] || {}),
            saveSetting: (t, plugin, key, valueJson) => {
              const all = (ios.settings[plugin] = ios.settings[plugin] || {});
              try { all[key] = JSON.parse(valueJson); } catch (_) { all[key] = valueJson; }
              post({ op: "saveSetting", plugin, key, value: valueJson });
            },
            play: (t, json) => post({ op: "play", json }),
            activePlayback: () => ios.active || "",
            takePendingClose: () => { const c = ios.pendingClose; ios.pendingClose = ""; return c || ""; },
            control: (t, json) => post({ op: "control", json }),
            openExternal: (t, url) => post({ op: "openExternal", url }),
            toast: (t, text) => post({ op: "toast", text }),
            engine: (t, json) => post({ op: "engine", json }),
            findServers: () => post({ op: "findServers" }),
            // Whether the streaming server answers (the page itself isn't allowed to reach an http:// one)
            serverUp: (t, url) => new Promise((resolve) => {
              const id = (ios.asked = (ios.asked || 0) + 1);
              (ios.answers = ios.answers || {})[id] = resolve;
              post({ op: "serverUp", id, url });
              setTimeout(() => { if (ios.answers[id]) { delete ios.answers[id]; resolve(false); } }, 8000);
            }),
            deviceInfo: () => \(Json.quote(Json.encode(device))),
            utcOffset: () => ios.utcOffset,
            isPhone: () => true,
            version: () => \(Json.quote(version)),
            // (no torrentUrl: an Apple TV can't download torrents itself; a streaming server plays them)
          };
        })();
        """
        return [restoreScript(), shim, resource("dxbi-tv.js"), resource("dxbi-engine.js")].joined(separator: "\n;\n")
    }

    // MARK: - Keeping Stremio's sign-in

    /**
     * Stremio keeps its account, addons and settings in the page's localStorage. In case tvOS doesn't
     * keep a web page's storage between launches, the app keeps a copy (in its caches) and puts it
     * back when the page starts with nothing. When WebKit keeps it, this does nothing.
     */
    private static var storageFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("stremio-storage.json")
    }

    private static func restoreScript() -> String {
        guard let saved = try? String(contentsOf: storageFile, encoding: .utf8), saved.hasPrefix("{") else { return "" }
        return """
        (function () {
          try {
            if (location.host !== "web.stremio.com" || !window.localStorage || localStorage.length > 0) return;
            const saved = \(saved);
            for (const key in saved) localStorage.setItem(key, saved[key]);
          } catch (_) {}
        })();
        """
    }

    private func keepStorage() {
        guard web != nil else { return }
        let script = """
        (function () {
          const kept = {};
          let size = 0;
          for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i), value = localStorage.getItem(key);
            if (value != null && value.length < 1500000 && size + value.length < 3000000) { kept[key] = value; size += value.length; }
          }
          return JSON.stringify(kept);
        })()
        """
        let file = Self.storageFile
        web?.evaluate(script) { result, _ in
            guard let text = result as? String, text.contains("\"profile\"") else { return }
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Running things in the page

    func js(_ script: String) {
        web?.evaluate(script, completion: nil)
    }

    /** Asks the page for something and waits for its answer (a JSON object, array, string, number… or nil) */
    func call(_ op: String, _ args: JSON = [:], timeout: Double = 20) async throws -> Any? {
        guard web != nil else { throw Failure(message: problem ?? "No page") }
        ids += 1
        let id = ids
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            send(op, args, id: id)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.pending.removeValue(forKey: id)?.resume(throwing: Failure(message: "The page didn't answer"))
            }
        }
    }

    /** Fire and forget */
    func send(_ op: String, _ args: JSON = [:], id: Int = 0) {
        let message: JSON = ["id": id, "op": op, "args": args]
        js("window.__dxbiEngine && window.__dxbiEngine.handle(\(Json.encode(message)))")
    }

    /** Keeps [field] coming as it changes (onState) */
    func watch(_ field: String) {
        guard !watched.contains(field) else { return }
        watched.append(field)
        send("watch", ["fields": watched])
    }

    private func engineMessage(_ text: String) {
        guard let message = Json.decode(text) as? JSON else { return }
        switch message.string("type") {
        case "reply":
            guard let answer = pending.removeValue(forKey: message.int("id")) else { return }
            if message.bool("ok") {
                let data = message["data"]
                answer.resume(returning: data is NSNull ? nil : data)
            } else {
                answer.resume(throwing: Failure(message: message.text("error") ?? "the page couldn't do that"))
            }
        case "state":
            onState?(message.string("field"), message.object("data"))
        case "ready":
            // a page that started again has forgotten what was watched
            if !watched.isEmpty { send("watch", ["fields": watched]) }
            onReady?()
            // the sign-in kept now and then (and as the app goes away)
            keeping?.cancel()
            keeping = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    self?.keepStorage()
                    try? await Task.sleep(for: .seconds(100))
                }
            }
        case "event":
            onEvent?(message.string("event"), message.object("args"))
        default:
            break
        }
    }

    private func saveSetting(plugin: String, key: String, valueJson: String) {
        var all = Self.savedSettings
        var mine = all[plugin] as? JSON ?? [:]
        mine[key] = Json.decode(valueJson) ?? NSNull()
        all[plugin] = mine
        Self.settings.set(Json.encode(all), forKey: "plugin-settings")
    }

    /** Stremio's streaming server at [address] answers (its settings, as Stremio asks for them) */
    nonisolated static func serverAnswers(_ address: String) async -> Bool {
        guard let base = URL(string: address.hasSuffix("/") ? address : address + "/"),
              base.scheme == "http" || base.scheme == "https" else { return false }
        var request = URLRequest(url: base.appending(path: "settings"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        request.httpMethod = "GET"
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0) < 500
    }

    private func received(_ message: Any, main: Bool, host: String?) {
        // Only Stremio's own page, not a trailer or anything else it embeds
        guard main, host == "web.stremio.com", let body = message as? JSON else { return }
        switch body.string("op") {
        case "engine": engineMessage(body.string("json"))
        case "play": onPlay?(body.string("json"))
        case "control": if let c = Json.decode(body.string("json")) as? JSON { onControl?(c) }
        case "saveSetting": saveSetting(plugin: body.string("plugin"), key: body.string("key"), valueJson: body.string("value"))
        case "openExternal":
            // (no browser on an Apple TV: the link's for a phone or computer)
            if let url = URL(string: body.string("url")), let host = url.host {
                onToast?("Open \(host)\(url.path) on your phone or computer")
            }
        case "toast": onToast?(body.string("text"))
        case "serverUp":
            let id = body.int("id")
            Task { @MainActor in
                let up = await Self.serverAnswers(body.string("url"))
                js("(function (a) { const f = a && a[\(id)]; if (f) { delete a[\(id)]; f(\(up)); } })(window.__dxbiIos && window.__dxbiIos.answers)")
            }
        case "findServers":
            // (not looked for: Profile → Playback → Streaming server takes an address)
            js("window.__dxbiTv && window.__dxbiTv.serversFound && window.__dxbiTv.serversFound([])")
        default: break
        }
    }

    /** The page's engine crashed, or tvOS took its memory back: start it again */
    private func restart() {
        for (_, answer) in pending { answer.resume(throwing: Failure(message: "The page restarted")) }
        pending.removeAll()
        keeping?.cancel()
        onGone?()
        web?.load(Self.home)
    }
}
