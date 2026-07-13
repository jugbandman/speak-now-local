# SpeakNowLocal — Maintenance & Daily-Use Runbook

How to install, update, and run SpeakNowLocal for daily use, plus how to
recover if stale build copies pile up. Written 2026-07-13.

## Daily use (normal)

The app is installed at `/Applications/SpeakNowLocal.app` and set as a Login
Item, so it launches automatically at login. Click the sparkles menu-bar icon
to open the panel (transcripts, quick capture, enhance, capture controls).

You do NOT need Xcode for daily use. Xcode is only for active development when
you want the debugger/console.

## Update after code changes

Run the installer from the project root:

```bash
./install.sh
```

It builds Release, auto-bumps the build number (`CFBundleVersion`), replaces
the `/Applications` copy, refreshes Launch Services, and relaunches. One copy,
always current. First launch of a fresh unsigned build may show a Gatekeeper
prompt — right-click the app in `/Applications` → **Open** once to trust it.

To also bump the marketing version (e.g. 1.0.1 → 1.0.2), edit
`MARKETING_VERSION` in `project.yml`, mirror it into `CFBundleShortVersionString`
in `SpeakNowLocal/Info.plist`, run `xcodegen generate`, then `./install.sh`.

## Develop with the console (Xcode)

```bash
open -a Xcode SpeakNowLocal.xcodeproj
```

Press ⌘R to run with the debugger. The console shows startup logs (e.g.
`SystemAudioCapture initialized with ScreenCaptureKit` = healthy start).

## Recovery: "I see multiple versions of the app to test"

Cause: multiple `.app` bundles get registered with Launch Services — a copy in
`/Applications`, a Release build in `build/`, and the Xcode Debug build in
DerivedData. If they all share the same version string they're indistinguishable
in Spotlight / the app switcher, and you can end up running a stale one.

Diagnose — list every registered copy:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -dump 2>/dev/null | grep -i "speaknowlocal.app" | grep -i "path:" | sort -u
```

Check which one is actually running:

```bash
ps aux | grep -i SpeakNowLocal | grep -v grep | awk '{print $2, $NF}'
```

Fix — delete stale copies, keep the canonical `/Applications` one, rebuild the
LS database:

```bash
# quit any running instance
osascript -e 'tell application "System Events" to quit application "SpeakNowLocal"' 2>/dev/null || true
pkill -9 -f SpeakNowLocal; sleep 1

# remove stale build outputs (keep /Applications and, if developing, DerivedData Debug)
rm -rf build

# rebuild the Launch Services database (note: the -kill flag was removed by Apple)
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -r -domain local -domain system -domain user

# reinstall a clean current copy
./install.sh
```

Prevention: `./install.sh` bumps the build number every run, so copies stay
distinguishable, and it removes its own intermediate build dir. Don't leave
hand-built `.app`s lying around in `/Applications` or `build/`.

## Recovery: "menu is featureless (only Settings / Quit)"

That is the `MenuBarView` scroll region collapsing to zero height, not lost
settings. Inside a `MenuBarExtra(.window)`, a `ScrollView` sized with
`.frame(maxHeight: .infinity)` resolves to zero because the window proposes an
unbounded height — only the intrinsic-height footer survives. The container
must have a definite height (currently `.frame(width: 360, height: 520)` in
`SpeakNowLocal/Views/MenuBarView.swift`). Fixed 2026-07-13 (commit 6855579).

## Settings storage

User settings live in the macOS defaults domain
`com.andycarlson.SpeakNowLocal`:

```bash
defaults read com.andycarlson.SpeakNowLocal
```

Bundle-ID drift creates orphan domains that look like "lost settings" (older
builds used `com.speaknow.local` and `com.andycarlson.SpeakNowDev`). Keep the
bundle ID fixed at `com.andycarlson.SpeakNowLocal` — settings do NOT migrate
across a bundle-ID rename.
