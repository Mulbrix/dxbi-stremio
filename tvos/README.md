# dx.bi for Apple TV: the probe

Before dx.bi is ported to Apple TV, this small app finds out what can run its engine there.

The iPhone app ([ios/](../ios)) runs Stremio's web app hidden in a `WKWebView`. Stremio's core runs in that page as WebAssembly in a worker, and does the account, addon, library and stream work; the app's screens show the results. tvOS has no public web view, so the probe checks, on a real Apple TV:

1. **JavaScriptCore** (public on tvOS): whether WebAssembly runs, and whether JavaScript runs fast enough to suggest a JIT.
2. **WKWebView and UIWebView**, found at run time in tvOS's private WebKit (`Probe/WebProbe.m`): whether each one starts and runs a test page (WebAssembly, a worker, localStorage, IndexedDB), and whether web.stremio.com's core starts in it and answers.

It ends with a one-line summary (the red box). Send that back. If a web view runs Stremio's core, the Apple TV app can reuse the iPhone app's engine and screens. If not, it needs a native Stremio client.

CI also checks whether MPVKit, the iPhone app's player, builds for tvOS (`mpvcheck.yml`; only built, never installed).

## Getting it onto an Apple TV

GitHub Actions builds it (`.github/workflows/tvos.yml`) and keeps an unsigned `dxbi-tv-probe.ipa` as the run's artifact. Install it with [Sideloadly](https://sideloadly.io) from a Mac or PC on the same network as the Apple TV. Pair the Apple TV under *Settings → Remotes and Devices → Remote App and Devices*. A free Apple ID is enough. Open *dx.bi probe*, wait about a minute until the summary appears, and photograph the screen or type the summary out.

## Building by hand

On a Mac with Xcode and the tvOS platform:

```sh
cd tvos
xcodegen generate
open DxbiProbe.xcodeproj
```
