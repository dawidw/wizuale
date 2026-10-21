# Wizuale

Tempo data by [GetSongBPM](https://getsongbpm.com).

Full-screen Milkdrop visuals for Apple TV. Put a record on — Apple Music on the TV, or music you start from this app — and the screen runs **real** [projectM](https://github.com/projectM-visualizer/projectm) presets (stock `.milk` files, unchanged).

The picture does not read Apple Music's audio stream. When a GetSongBPM key is set and the song is in their database, the beat clock can lock to that tempo for the title card and overlay. **Wizuale Mic** sends mono PCM from the room so projectM reacts to the sound you hear.

## Pictures (libprojectM)

The tvOS app renders bundled **Milkdrop presets** through **libprojectM 4.x** (OpenGL ES 3). There is no custom tone mapping, zoom slider, album-art tint, or Metal grading on top — only what the preset author wrote.

Presets come from [presets-cream-of-the-crop](https://github.com/projectM-visualizer/presets-cream-of-the-crop) (see `scripts/fetch-presets.sh`). Textures ship from [presets-milkdrop-texture-pack](https://github.com/projectM-visualizer/presets-milkdrop-texture-pack). Both TV and Mic apps read the same `manifest.json` order.

Preset changes use projectM's **soft cut** (~2 s). Auto-advance (default on, ~45 s, adjustable on the phone) picks a random next preset when not locked to a single choice.

The legacy Metal renderer (`Shaders.metal`, `Presets.swift`, …) remains in the repo but is **not** compiled into the tvOS target.

## Remote

| Press | What it does |
| --- | --- |
| Swipe left or right | Previous or next preset |
| Click | Next preset |
| Hold click | Keep the title card on screen, or let it hide again |
| Play / Pause | Pause or resume. If nothing is queued, start recently played songs |
| Menu | Leave the app |

The title card fades after a few seconds, and again when the song changes. The hint at the top disappears after the first press.

The Apple TV screensaver stays off while the app is in front.

## Tempo

Wizuale sends the current title and artist to [GetSongBPM](https://getsongbpm.com) and, on a match, drives the **beat clock** (title card, overlay timing). projectM's motion is driven by **PCM** when a mic is live.

If the corner card never shows a BPM, the lookup did not match: no key, the song is not in the database, or the TV's Music player cannot see the track (AirPlay from an iPhone often does not). For the actual sound in the room, use Wizuale Mic.

Put your API key in a file that is not committed:

```
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

`Config/Secrets.xcconfig` is gitignored. The setting name is `GETSONGBPM_API_KEY`:

```
GETSONGBPM_API_KEY = your_key_here
```

## Microphone

Wizuale Mic is a second app in this project, for an iPhone on the same Wi-Fi. It sends:

- **PCM** — mono int16 (~512 samples per tap) for libprojectM on the TV
- **Band features** — bass, mids, highs, kicks (legacy path; beat clock may still use kicks)
- **Settings** — latency and sensitivity
- **Cycle** — auto-advance on/off and interval (15–600 s)

**Sensitivity** (0.25×–3×, default 1×) maps to projectM **beat sensitivity** / PCM gain. **Latency** (−200…+400 ms) delays the beat clock for the overlay, not projectM's audio buffer.

**Drop** still sends a boost packet; it is not wired into projectM in this build.

The phone shows **Connected to** the Apple TV's name, with a green dot, only after the TV app answers. The preset strip lists **Auto** and every bundled preset name. Tap one to lock the TV; **Auto** unlocks and resumes rotation when auto-advance is on. The TV ack moves the highlight.

On the TV, swipe down to pick the mic source: iPhone app (Wi-Fi), Continuity Microphone, or Off.

Update **both** apps together when you change the preset bundle or wire protocol.

## Build libprojectM and presets (Mac)

The Xcode project expects a prebuilt xcframework and a fetched preset pack (not committed to git).

```bash
brew install cmake ninja   # if needed
./scripts/build-projectm-tvos.sh
# optional: ./scripts/build-projectm-tvos.sh --tag v4.2.0

./scripts/fetch-presets.sh --count 100   # 50–150 is fine
```

Details: `ThirdParty/README.md`.

```bash
xcodebuild -scheme Wizuale -destination 'generic/platform=tvOS' build
xcodebuild -scheme "Wizuale Mic" -destination 'generic/platform=iOS Simulator' build
```

`project.yml` matches the checked-in `Wizuale.xcodeproj`. Regenerate with XcodeGen if you prefer: `brew install xcodegen && xcodegen generate`.

## Open the project

You need a Mac with Xcode 15 or newer. Open `Wizuale.xcodeproj`. Wizuale is the tvOS 17 target. Wizuale Mic is the iOS 17 target.

## Signing and Apple Music

The bundle id is `app.wizuale.Wizuale`. MusicKit needs a paid Apple Developer Program membership.

The usage string for Music permission still mentions album colors in the plist; the **projectM path does not tint from artwork**.

## Run it on an Apple TV

1. Run the build scripts above on your Mac.
2. Pair the Apple TV in Xcode (Window → Devices and Simulators).
3. Choose the Apple TV as the run destination and press Run.

The simulator can run projectM if the xcframework includes the tvOS simulator slice.

## Licensing notes

- **libprojectM** is LGPL. This repo links it statically for TestFlight-only use; include projectM's license in acknowledgements if you ship broadly.
- **Community presets** in cream-of-the-crop are not relicensed by this repo; use for personal / TestFlight unless you audit each file.

## What was not run here

This environment has no Xcode. The project was not compiled on hardware here. Run the scripts and `xcodebuild` on your Mac before TestFlight.
