// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import JavaScriptCore
import Observation
import SwiftUI
import UIKit

/**
 * dx.bi's Apple TV probe. The iPhone app runs Stremio's web app out of sight in a WKWebView, and its
 * core (WebAssembly, in a worker) does Stremio's work. tvOS has no public web view, so before porting
 * the app this finds out, on a real Apple TV, what can run that engine:
 *
 *   1. JavaScriptCore (public on tvOS): is there WebAssembly, and is JavaScript fast (a JIT)?
 *   2. WKWebView and UIWebView, found at run time in tvOS's private WebKit: do they start, run a page
 *      with WebAssembly, workers and storage, and does web.stremio.com's core start in them?
 *
 * Everything shows on screen, ending in a one-line summary to send back.
 */
@main
struct ProbeApp: App {
    @State private var probe = Probe()

    var body: some Scene {
        WindowGroup {
            ProbeView(probe: probe)
                .preferredColorScheme(.dark)
                .task { await probe.runOnce() }
        }
    }
}

struct Line: Identifiable {
    enum Status { case good, bad, info, running }
    let id = UUID()
    var status: Status
    var title: String
    var detail: String
}

@MainActor
@Observable
final class Probe {
    var lines: [Line] = []
    var summary = ""
    var running = false
    private var summaryParts: [String] = []
    private var ran = false

    /** The iPhone app's identity, so web.stremio.com serves the same app */
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15 dxbi-tv-probe"

    func runOnce() async {
        guard !ran else { return }
        ran = true
        await run()
    }

    func run() async {
        guard !running else { return }
        running = true
        lines = []
        summary = ""
        summaryParts = []
        defer { running = false }

        let version = UIDevice.current.systemVersion
        add(.info, "This Apple TV", "\(Self.model) · tvOS \(version) · probe \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
        summaryParts.append("\(Self.model) tvOS\(version)")

        javaScriptCore()

        let loaded = WebProbe.loadWebKit()
        let classes = ["WKWebView", "WKWebViewConfiguration", "WKWebsiteDataStore", "WKUserScript", "UIWebView"]
            .map { "\($0): \(WebProbe.hasClass($0) ? "yes" : "no")" }
            .joined(separator: " · ")
        add(WebProbe.hasClass("WKWebView") || WebProbe.hasClass("UIWebView") ? .good : .bad, "WebKit on this Apple TV", loaded + "\n" + classes)
        summaryParts.append("WK\(WebProbe.hasClass("WKWebView") ? 1 : 0) UI\(WebProbe.hasClass("UIWebView") ? 1 : 0)")

        var engine: String?
        for kind in ["WKWebView", "UIWebView"] {
            if await webView(kind), engine == nil { engine = kind }
        }

        if let engine {
            add(.good, "Verdict", "Stremio's core runs here in \(engine). dx.bi for Apple TV can use the same engine as the iPhone app.")
            summaryParts.append("verdict:\(engine)")
        } else {
            add(.bad, "Verdict", "Stremio's core didn't start in a web view here. dx.bi for Apple TV needs an engine of its own (a native Stremio client).")
            summaryParts.append("verdict:native")
        }
        summary = summaryParts.joined(separator: " | ")
    }

    // MARK: - JavaScriptCore

    private func javaScriptCore() {
        guard let context = JSContext() else {
            add(.bad, "JavaScriptCore", "no JSContext")
            summaryParts.append("JSC:none")
            return
        }
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }
        let wasmType = context.evaluateScript("typeof WebAssembly")?.toString() ?? "?"
        exception = nil
        let sum = context.evaluateScript("""
            (function () {
              const bytes = new Uint8Array(\(Self.wasmAdd));
              return new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports.add(2, 3);
            })()
            """)
        let wasmRuns = exception == nil && sum?.toInt32() == 5
        let wasmDetail = wasmRuns ? "runs (2 + 3 = 5)" : "doesn't run (\(exception ?? "no answer"))"
        exception = nil
        let loop = context.evaluateScript(Self.loopScript)?.toInt32() ?? -1
        self.add(wasmRuns ? .good : .bad, "JavaScriptCore", "WebAssembly: \(wasmType), \(wasmDetail)\nA busy loop took \(loop) ms (\(Self.speed(Int(loop))))")
        summaryParts.append("JSC wasm\(wasmRuns ? 1 : 0) \(loop)ms")
    }

    // MARK: - Web views

    /** Whether Stremio's core started in a [kind] */
    private func webView(_ kind: String) async -> Bool {
        guard WebProbe.hasClass(kind) else {
            add(.bad, kind, "not on this Apple TV")
            summaryParts.append("\(kind):absent")
            return false
        }
        guard let window = Self.window else {
            add(.bad, kind, "no window to put it in")
            return false
        }
        var failure: NSString?
        guard let web = WebProbe(kind: kind, window: window, userAgent: Self.userAgent, error: &failure) else {
            add(.bad, kind, "made: no (\(failure ?? "?"))")
            summaryParts.append("\(kind):nostart")
            return false
        }
        defer { web.tearDown() }

        // 1. A test page: WebAssembly, a worker, storage
        let test = add(.running, "\(kind): test page", "loading…")
        web.loadHTML(Self.testPage, baseURL: URL(string: "https://web.stremio.com/"))
        var answer: String?
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(500))
            if let text = await evaluate(web, "window.__probe || ''").result, !text.isEmpty {
                answer = text
                break
            }
        }
        guard let answer, let report = (try? JSONSerialization.jsonObject(with: Data(answer.utf8))) as? [String: Any] else {
            let said = await evaluate(web, "document.readyState + ' ' + location.href")
            update(test, .bad, "the page never answered (\(said.result ?? said.error ?? "nothing"))")
            summaryParts.append("\(kind):nopage")
            return false
        }
        let wasm = report["wasm"] as? String ?? "?"
        let loop = (report["loopMs"] as? NSNumber)?.intValue ?? -1
        let detail = [
            "WebAssembly: \(wasm)",
            "worker: \(report["worker"] ?? "?")",
            "localStorage: \(report["localStorage"] ?? "?") · IndexedDB: \(report["indexedDB"] ?? "?")",
            "busy loop: \(loop) ms (\(Self.speed(loop)))",
        ].joined(separator: "\n")
        update(test, wasm.hasPrefix("runs") ? .good : .bad, detail)
        summaryParts.append("\(kind) wasm\(wasm.hasPrefix("runs") ? 1 : 0) worker\((report["worker"] as? String) == "runs" ? 1 : 0) \(loop)ms")

        // 2. Stremio's web app, and whether its core starts
        let stremio = add(.running, "\(kind): Stremio's core", "loading web.stremio.com…")
        web.loadURL(URL(string: "https://web.stremio.com/")!)
        let started = Date()
        var core = false
        var last = ""
        for _ in 0..<120 {
            try? await Task.sleep(for: .milliseconds(500))
            let said = await evaluate(web, "JSON.stringify({core: !!(window.core && window.core.getState), state: document.readyState, title: document.title})")
            last = said.result ?? said.error ?? ""
            if last.contains("\"core\":true") { core = true; break }
            update(stremio, .running, "waiting (\(Int(Date().timeIntervalSince(started))) s): \(last)")
        }
        let seconds = Int(Date().timeIntervalSince(started))
        guard core else {
            update(stremio, .bad, "the core didn't start in \(seconds) s (\(last))")
            summaryParts.append("\(kind) core0")
            return false
        }
        // It started: ask it for something real (a guest still has Stremio's default addons)
        _ = await evaluate(web, """
            window.__probeCtx = '';
            window.core.getState('ctx').then(
              (s) => { const p = s && s.profile; window.__probeCtx = JSON.stringify({ addons: p && p.addons ? p.addons.length : null, signedIn: !!(p && p.auth) }); },
              (e) => { window.__probeCtx = 'error ' + e; });
            'asked'
            """)
        var ctx = ""
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(500))
            ctx = await evaluate(web, "window.__probeCtx || ''").result ?? ""
            if !ctx.isEmpty { break }
        }
        let works = ctx.contains("\"addons\":") && !ctx.contains("\"addons\":null")
        update(stremio, works ? .good : .bad, "core started in \(seconds) s · its state: \(ctx.isEmpty ? "no answer" : ctx)")
        summaryParts.append("\(kind) core1 \(seconds)s ctx\(works ? 1 : 0)")
        return works
    }

    private func evaluate(_ web: WebProbe, _ script: String) async -> (result: String?, error: String?) {
        await withCheckedContinuation { continuation in
            web.evaluate(script) { result, error in continuation.resume(returning: (result, error)) }
        }
    }

    // MARK: - Lines

    @discardableResult
    private func add(_ status: Line.Status, _ title: String, _ detail: String) -> UUID {
        let line = Line(status: status, title: title, detail: detail)
        lines.append(line)
        return line.id
    }

    private func update(_ id: UUID, _ status: Line.Status, _ detail: String) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].status = status
        lines[index].detail = detail
    }

    // MARK: - What it runs

    /** A WebAssembly module exporting add(a, b) */
    static let wasmAdd = "[0,97,115,109,1,0,0,0,1,7,1,96,2,127,127,1,127,3,2,1,0,7,7,1,3,97,100,100,0,0,10,9,1,7,0,32,0,32,1,106,11]"

    /** 20 million rounds of arithmetic: tens of ms with a JIT, seconds without */
    static let loopScript = "(function () { const t = Date.now(); let x = 0; for (let i = 0; i < 2e7; i++) { x = (x + i * 7) % 1000003; } return Date.now() - t; })()"

    static func speed(_ ms: Int) -> String {
        ms < 0 ? "didn't run" : ms < 400 ? "fast: likely a JIT" : "slow: likely no JIT"
    }

    static let testPage = """
        <!doctype html><html><head><meta charset="utf-8"></head><body style="background:#000">
        <script>
        (async function () {
          const r = {};
          const settle = (p, ms) => Promise.race([p, new Promise((res) => setTimeout(() => res('timed out'), ms))]);
          try {
            if (typeof WebAssembly !== 'object') r.wasm = 'none';
            else {
              const { instance } = await WebAssembly.instantiate(new Uint8Array(\(wasmAdd)));
              r.wasm = instance.exports.add(2, 3) === 5 ? 'runs' : 'wrong answer';
            }
          } catch (e) { r.wasm = 'error: ' + e; }
          try {
            const code = 'onmessage = (e) => postMessage(e.data + 1)';
            const w = new Worker(URL.createObjectURL(new Blob([code], { type: 'text/javascript' })));
            r.worker = await settle(new Promise((res) => { w.onmessage = (e) => res(e.data === 2 ? 'runs' : 'wrong answer'); w.onerror = (e) => res('error: ' + (e.message || e)); w.postMessage(1); }), 4000);
          } catch (e) { r.worker = 'error: ' + e; }
          try { localStorage.setItem('dxbi-probe', '1'); r.localStorage = localStorage.getItem('dxbi-probe') === '1' ? 'works' : 'lost it'; } catch (e) { r.localStorage = 'error: ' + e; }
          try {
            r.indexedDB = typeof indexedDB === 'undefined' ? 'none' : await settle(new Promise((res) => {
              const q = indexedDB.open('dxbi-probe', 1);
              q.onsuccess = () => { q.result.close(); res('works'); };
              q.onerror = () => res('error: ' + q.error);
            }), 4000);
          } catch (e) { r.indexedDB = 'error: ' + e; }
          r.loopMs = (\(loopScript));
          window.__probe = JSON.stringify(r);
        })();
        </script></body></html>
        """

    static var window: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ??
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first
    }

    /** AppleTV14,1 and the like */
    static var model: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

struct ProbeView: View {
    let probe: Probe

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("dx.bi · Apple TV probe").font(.title2.bold())
                    Spacer()
                    Button(probe.running ? "Running…" : "Run again") { Task { await probe.run() } }
                        .disabled(probe.running)
                }
                if !probe.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Send this back:").font(.headline)
                        Text(probe.summary).font(.system(.callout, design: .monospaced))
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
                    .focusable()
                }
                ForEach(probe.lines) { line in
                    HStack(alignment: .top, spacing: 20) {
                        Text(icon(line.status)).font(.title3)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(line.title).font(.headline)
                            Text(line.detail).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    .focusable()
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
        }
        .background(Color.black)
    }

    private func icon(_ status: Line.Status) -> String {
        switch status {
        case .good: "✅"
        case .bad: "❌"
        case .info: "ℹ️"
        case .running: "⏳"
        }
    }
}
