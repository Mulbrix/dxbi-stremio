# dx.bi for Apple TV

dx.bi for Apple TV (tvOS 17 and later), installed by sideloading with your own Apple ID.

## Installing

1. Download **dxbi-tv.ipa** from a release, or from the latest run of the *Apple TV app* workflow (GitHub Actions → the run → *Artifacts*, then unzip it).
2. On the Apple TV, open *Settings → Remotes and Devices → Remote App and Devices*, and leave it open.
3. On a Mac or PC on the same network, open [Sideloadly](https://sideloadly.io). The Apple TV shows up among its devices; pair it if asked. Drop in dxbi-tv.ipa, sign in with your Apple ID and install.
4. Open dx.bi on the Apple TV and sign in with your Stremio account (or carry on without one).

Good to know:

- With a free Apple ID, sideloaded apps stop opening after 7 days: install it again with Sideloadly (your sign-in and settings stay). A paid developer account makes that a year.
- Torrents don't play on the Apple TV itself: they need dx.bi or Stremio running on a computer on the same network (*Profile → Playback → Streaming server*). Debrid streams play straight away.
- When there's a new release, dx.bi says so when it opens: install the new dxbi-tv.ipa over the old one.

## On the remote

| | Controls away | Controls up (on the seek bar) |
|---|---|---|
| Select or Play/Pause | Pause or play (Skip Intro, or the next episode, when shown) | Pause or play, or go to the point chosen |
| Left / right (click) | Back or forward 10 seconds | Choose a point, 10 seconds a click (faster the more you click) |
| Glide a finger left / right | Show the controls and choose a point | Choose a point, following the finger (slowly for small moves) |
| Up / down | Show the controls | Up hides them; down reaches Subtitles, Audio, Speed, Picture |
| Menu | Close the player | Hide the controls (close the player when paused) |

Elsewhere, hold select on a poster, episode or stream for more (Play, Details, Choose a Stream, Mark as Watched…).

## How it works

It's the iPhone app ([ios/](../ios)) with screens for the TV.

- Like the iPhone app, it runs Stremio's web app (web.stremio.com) out of sight with dx.bi's scripts (`dxbi-tv.js`, `dxbi-engine.js` and the dx.bi plugin, bundled at build time), and the app's screens show what it finds. The engine, the models, the mpv player (MPVKit) and the cards are the iPhone app's own files, shared by `project.yml`.
- tvOS has WebKit, but not for apps: no headers, nothing to link against. `Engine/DxWebView.m` loads WebKit when the app starts and finds its classes by name. `Probe/` (`probe.yml`) is the small app that checked this works on a real Apple TV; it's kept for checking a new tvOS.
- `Engine/Page.swift` is the iPhone app's page host on `DxWebView`. It also keeps a copy of Stremio's sign-in, in case tvOS doesn't keep a web page's storage between launches.
- `UI/` has the screens, made for focus and the Siri Remote, and `Player/PlayerScreen.swift` the player's.
- There are no downloads: tvOS gives apps no lasting storage for films.

## Building

There's no Xcode project in git: [XcodeGen](https://github.com/yonaskolb/XcodeGen) makes it from `project.yml`. On a Mac with Xcode 26 and the tvOS platform:

```sh
cd tvos
xcodegen generate
open Dxbi.xcodeproj
```

GitHub Actions builds it on every push that touches it (`.github/workflows/tvos.yml`) and keeps an unsigned `dxbi-tv.ipa` as the run's artifact; publishing a release attaches it to the release. It needs no signing key: Sideloadly signs the IPA with your own Apple ID when it installs it.

The app's version is the dx.bi plugin's, as the other apps' is.
