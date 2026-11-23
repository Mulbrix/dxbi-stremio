// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import SwiftUI

/** The first screen until they sign in (or choose to go without an account) */
struct WelcomeView: View {
    @Environment(Stremio.self) private var stremio
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        HStack(spacing: 120) {
            VStack(alignment: .leading, spacing: 30) {
                Logo(size: 160)
                Text("Sign in with your Stremio account.\nYour addons, library and progress come with it.")
                    .font(.title3)
                    .foregroundStyle(Dx.muted)
                Text("No account yet? Create one for free at stremio.com on your phone or computer.")
                    .font(.callout)
                    .foregroundStyle(Dx.faint)
            }
            .frame(maxWidth: 700, alignment: .leading)
            VStack(spacing: 24) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onSubmit(signIn)
                if let problem { Text(problem).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center) }
                Button(action: signIn) {
                    Label(busy ? "Signing In…" : "Sign In", systemImage: "person.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || email.isEmpty || password.isEmpty || !stremio.ready)
                if !stremio.ready {
                    Label("Starting Stremio…", systemImage: "hourglass").font(.callout).foregroundStyle(Dx.faint)
                }
                Button { stremio.guest = true } label: { Text("Continue Without an Account").frame(maxWidth: .infinity) }
            }
            .frame(width: 640)
        }
        .padding(TV.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Dx.accent.opacity(0.3), .black, .black], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
    }

    private func signIn() {
        guard !email.isEmpty, !password.isEmpty else { return }
        busy = true
        problem = nil
        Task {
            problem = await stremio.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            busy = false
        }
    }
}

/** Profile: the account, who's watching, addons, settings, Customise Home */
struct AccountView: View {
    @Environment(Stremio.self) private var stremio

    var body: some View {
        List {
            Section {
                HStack(spacing: 30) {
                    Avatar(email: stremio.viewer?.name ?? stremio.account?.email, size: 90)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stremio.account?.email ?? "Not signed in").font(.headline)
                        Text(stremio.account?.signedIn == true ? "Stremio account" : "Using dx.bi without an account").font(.callout).foregroundStyle(Dx.muted)
                    }
                }
                .padding(.vertical, 10)
                .focusable()
            }
            if stremio.viewers.count > 1 {
                Section("Who's Watching") {
                    ForEach(stremio.viewers) { v in
                        Button { stremio.chooseViewer(v.id) } label: {
                            HStack {
                                Text(v.name)
                                Spacer()
                                if v.id == stremio.viewer?.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
            Section {
                NavigationLink { PartyView() } label: { Label("Watch Party", systemImage: "person.2.fill") }
                NavigationLink { AddonsView() } label: { Label("Addons", systemImage: "puzzlepiece.extension.fill") }
                NavigationLink { StatsView() } label: { Label("Your Stats", systemImage: "chart.bar.fill") }
                NavigationLink { CustomiseHomeView() } label: { Label("Customise Home", systemImage: "square.stack.3d.up.fill") }
                NavigationLink { DxbiSettingsView() } label: { Label("dx.bi Settings", systemImage: "slider.horizontal.3") }
                NavigationLink { PlaybackSettingsView() } label: { Label("Playback", systemImage: "play.rectangle.fill") }
                NavigationLink { ReportView() } label: { Label("Report a Problem", systemImage: "exclamationmark.bubble.fill") }
            }
            Section {
                if stremio.account?.signedIn == true {
                    Button("Sign Out", role: .destructive) { stremio.signOut() }
                } else {
                    Button("Sign In") { stremio.guest = false }
                }
            } footer: {
                Text("dx.bi \(Page.version) for Apple TV · Not affiliated with Stremio.")
            }
        }
        .frame(maxWidth: 1200)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Addons

struct AddonsView: View {
    @Environment(Stremio.self) private var stremio
    @State private var list = "installed"
    @State private var link = ""
    @State private var busy: String?

    var body: some View {
        List {
            Section {
                Picker("List", selection: $list) {
                    Text("Installed").tag("installed")
                    Text("Official").tag("official")
                    Text("Community").tag("community")
                }
                .pickerStyle(.segmented)
            }
            if list == "installed" {
                Section {
                    TextField("Add from a link: https://…/manifest.json", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { if !link.isEmpty { act("link") { await stremio.install(link: link) } } }
                } footer: {
                    Text("Addons that need setting up (with a debrid key, say) are set up on their own web page from a phone or computer; install the link it gives here, or on any device with your Stremio account.")
                }
            }
            Section {
                let addons = list == "installed" ? stremio.installedAddons : stremio.remoteAddons
                if list != "installed" && stremio.remoteAddonsLoading && addons.isEmpty { ProgressView() }
                ForEach(addons) { addon in row(addon) }
            }
        }
        .frame(maxWidth: 1400)
        .frame(maxWidth: .infinity)
        .navigationTitle("Addons")
        .onAppear { stremio.loadAddons() }
        .onChange(of: list) { _, l in if l != "installed" { stremio.loadRemoteAddons(l) } }
    }

    private func row(_ addon: Addon) -> some View {
        let installed = addon.installed || stremio.installedAddons.contains { $0.transportUrl == addon.transportUrl }
        return Button {
            if !installed { act(addon.transportUrl) { await stremio.install(addon) } }
        } label: {
            HStack(spacing: 24) {
                AsyncImage(url: URL(string: addon.logo ?? "")) { phase in
                    if let i = phase.image { i.resizable().scaledToFit() } else { Image(systemName: "puzzlepiece.extension").foregroundStyle(Dx.muted) }
                }
                .frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 4) {
                    Text(addon.name).font(.headline)
                    Text(addon.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if busy == addon.transportUrl {
                    ProgressView()
                } else if installed {
                    Text("Installed").font(.callout).foregroundStyle(.secondary)
                } else {
                    Label("Get", systemImage: "plus.circle.fill").font(.callout.weight(.semibold))
                }
            }
        }
        .contextMenu {
            if installed && !addon.isProtected {
                Button(role: .destructive) { act(addon.transportUrl) { await stremio.uninstall(addon) } } label: { Label("Uninstall", systemImage: "trash") }
            }
        }
    }

    private func act(_ key: String, _ work: @escaping () async -> String?) {
        busy = key
        Task {
            let problem = await work()
            busy = nil
            if let problem { stremio.show(problem) } else if key == "link" { link = ""; stremio.show("Installed") }
            stremio.loadAddons()
        }
    }
}

// MARK: - Settings

/** dx.bi settings: the same list the phone shows */
struct DxbiSettingsView: View {
    @Environment(Stremio.self) private var stremio
    @State private var settings: [Setting]?

    /** How Stremio's page looks: the app's own screens don't use these */
    private static let webOnly: Set<String> = [
        "liteMode", "builtInTheme", "previews", "ratings", "animeTitles", "wideContinue", "librarySort", "trailers",
        "whoIsWatching", "addonTools", "posterAccent", "crispPosters", "streamTools", "streamRows", "splash", "introSound",
        "profileSync", "uiSounds", "focusColour", "videoRowsOnly", "newEpisodes", "accent", "tvTorrents",
    ]

    var body: some View {
        List {
            if let settings {
                let groups = settings.reduce(into: [String]()) { if !$0.contains($1.group) { $0.append($1.group) } }
                ForEach(groups, id: \.self) { group in
                    Section(group.isEmpty ? "General" : group) {
                        ForEach(settings.filter { $0.group == group }) { s in SettingRow(setting: s) { json in save(s, json) } }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: 1400)
        .frame(maxWidth: .infinity)
        .navigationTitle("dx.bi Settings")
        .task { settings = await stremio.settings().filter { !Self.webOnly.contains($0.key) } }
    }

    private func save(_ s: Setting, _ json: String) {
        if let i = settings?.firstIndex(where: { $0.key == s.key }) { settings?[i].value = json }
        Task { await stremio.saveSetting(s.key, json: json) }
    }
}

private struct SettingRow: View {
    var setting: Setting
    var onChange: (String) -> Void
    @State private var text = ""

    var body: some View {
        switch setting.type {
        case "toggle":
            Toggle(isOn: Binding(get: { setting.isOn }, set: { onChange($0 ? "true" : "false") })) { label }
        case "select":
            Picker(selection: Binding(get: { setting.value }, set: { onChange($0) })) {
                ForEach(setting.options, id: \.value) { Text($0.label).tag($0.value) }
            } label: { label }
        default:
            VStack(alignment: .leading, spacing: 8) {
                label
                TextField("Not set", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { onChange(Json.encode(text)) }
                    .onAppear { text = setting.textValue }
            }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(setting.label)
            if !setting.description.isEmpty {
                Text(setting.description).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
    }
}

/** Stremio's own player settings, and where videos play */
struct PlaybackSettingsView: View {
    @Environment(Stremio.self) private var stremio
    @State private var server = ""

    var body: some View {
        @Bindable var stremio = stremio
        let settings = stremio.profileSettings
        List {
            Section {
                Picker("Play videos in", selection: $stremio.otherApp) {
                    Text("dx.bi").tag(String?.none)
                    ForEach(OtherApp.all) { app in Text(app.name + (app.installed ? "" : " (not installed)")).tag(String?.some(app.id)) }
                }
            } footer: {
                Text("dx.bi's player plays almost anything. Another app keeps no watch progress in Stremio.")
            }
            Section("Languages") {
                LanguagePicker(title: "Audio", value: settings.string("audioLanguage")) { stremio.updateSettings(["audioLanguage": $0]) }
                LanguagePicker(title: "Subtitles", value: settings.string("subtitlesLanguage")) { stremio.updateSettings(["subtitlesLanguage": $0]) }
            }
            Section {
                TextField("http://192.168.1.10:11470", text: $server)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { stremio.updateSettings(["streamingServerUrl": server]) }
                    .onAppear { server = settings.string("streamingServerUrl") }
            } header: {
                Text("Streaming server")
            } footer: {
                Text("Torrents need Stremio (or dx.bi) running on a computer on the same network: put its address here. Debrid streams play without one.")
            }
        }
        .frame(maxWidth: 1400)
        .frame(maxWidth: .infinity)
        .navigationTitle("Playback")
    }
}

private struct LanguagePicker: View {
    var title: String
    var value: String
    var onPick: (String) -> Void
    private static let languages: [(String, String)] = [
        ("eng", "English"), ("spa", "Spanish"), ("fre", "French"), ("ger", "German"), ("ita", "Italian"), ("por", "Portuguese"),
        ("ara", "Arabic"), ("urd", "Urdu"), ("hin", "Hindi"), ("tur", "Turkish"), ("rus", "Russian"), ("jpn", "Japanese"),
        ("kor", "Korean"), ("chi", "Chinese"), ("dut", "Dutch"), ("pol", "Polish"), ("swe", "Swedish"), ("per", "Persian"),
    ]
    var body: some View {
        Picker(title, selection: Binding(get: { value }, set: onPick)) {
            if !Self.languages.contains(where: { $0.0 == value }) { Text(value.isEmpty ? "Default" : value).tag(value) }
            ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
        }
    }
}

/** Customise Home: which catalog rows show, and in what order (held down: move it) */
struct CustomiseHomeView: View {
    @Environment(Stremio.self) private var stremio
    @State private var keys: [String] = []
    @State private var hidden: Set<String> = []

    var body: some View {
        let byKey = Dictionary(stremio.allRows.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        List {
            Section {
                ForEach(Array(keys.enumerated()), id: \.element) { i, key in
                    if let row = byKey[key] {
                        Button {
                            if hidden.contains(key) { hidden.remove(key) } else { hidden.insert(key) }
                            save()
                        } label: {
                            HStack(spacing: 20) {
                                Image(systemName: hidden.contains(key) ? "eye.slash" : "eye.fill").foregroundStyle(hidden.contains(key) ? .secondary : .primary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stremio.layout.names[key] ?? row.heading)
                                    Text(row.addon).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(hidden.contains(key) ? "Hidden" : "Shown").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            if i > 0 { Button { move(i, to: i - 1) } label: { Label("Move Up", systemImage: "arrow.up") } }
                            if i < keys.count - 1 { Button { move(i, to: i + 1) } label: { Label("Move Down", systemImage: "arrow.down") } }
                            if i > 0 { Button { move(i, to: 0) } label: { Label("Move to the Top", systemImage: "arrow.up.to.line") } }
                        }
                    }
                }
            } footer: {
                Text("Press a row to show or hide it; hold it down to move it. dx.bi saves this to your profile, so your other devices follow it.")
            }
        }
        .frame(maxWidth: 1400)
        .frame(maxWidth: .infinity)
        .navigationTitle("Customise Home")
        .onAppear {
            let all = stremio.allRows.map(\.key)
            keys = stremio.layout.order.filter(all.contains) + all.filter { !stremio.layout.order.contains($0) }
            hidden = stremio.layout.hidden
        }
    }

    private func move(_ from: Int, to: Int) {
        let key = keys.remove(at: from)
        keys.insert(key, at: to)
        save()
    }

    private func save() {
        var layout = stremio.layout
        layout.order = keys
        layout.hidden = hidden
        stremio.saveLayout(layout)
    }
}

/** Report a problem: what went wrong, sent with dx.bi's own report (as on the desktop and phones) */
struct ReportView: View {
    @Environment(Stremio.self) private var stremio
    @State private var text = ""
    @State private var sending = false
    @State private var sent: String?
    @State private var problem: String?

    var body: some View {
        List {
            if let sent {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Report sent", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
                        Text("Thanks! Your report code is **\(sent)**. Post it in dx.bi's Discord (#bug-reports) so it can be matched to you.")
                    }
                    .padding(.vertical, 10)
                    .focusable()
                }
            } else {
                Section {
                    TextField("What went wrong, and what were you doing?", text: $text)
                } footer: {
                    Text("dx.bi adds its version, this Apple TV's model, your settings, addon names and recent errors. No passwords, keys or stream links are sent.")
                }
                if let problem { Section { Text(problem).foregroundStyle(.red) } }
                Section {
                    Button {
                        sending = true
                        problem = nil
                        Task {
                            switch await stremio.report(text) {
                            case .success(let code): sent = code
                            case .failure(let failure): problem = failure.message
                            }
                            sending = false
                        }
                    } label: {
                        HStack {
                            Text(sending ? "Sending…" : "Send Report")
                            if sending { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(sending || text.trimmingCharacters(in: .whitespaces).count < 3)
                }
            }
        }
        .frame(maxWidth: 1400)
        .frame(maxWidth: .infinity)
        .navigationTitle("Report a Problem")
    }
}
