# Wizuale

Tempo data by [GetSongBPM](https://getsongbpm.com).

Full-screen generative pictures for Apple TV. Put a record on — Apple Music on the TV, or music you start from this app — and the screen becomes a MilkDrop-style visualizer instead of the screensaver.

The picture does not listen to the audio. Apple Music is protected, and this app never opens the stream. When a GetSongBPM key is set and the song is in their database, the picture locks to that tempo. Without a key, or when the song is not listed, motion falls back to time and a gentle built-in pulse. If Apple Music permission is on, the title and cover show briefly in the corner, and the cover's colors tint the picture.

## Pictures

Sixteen MilkDrop presets play on their own. They morph into the next over a few seconds: the new stroke crossfades, and the warp eases across the same window instead of cutting. Without a matched tempo they hold for about 45 seconds. With a matched tempo they wait for the next 8-bar phrase after that, so the change lands on the music. Each picture also wanders a little on its own (zoom, spin, warp, hue), retargeting every few seconds.

1. **Spiral Star** — eight neon arms, pink, gold, and teal, over a dark warp
2. **Petal Veil** — a green spiral of glowing petals with fine contour lines
3. **Ember Ring** — a dark field and a soft orange-red ring with trails
4. **Neon Tunnel** — four-fold rings rushing outward
5. **Liquid Silk** — slow ribbons
6. **Prism Wheel** — a twelve-spoke wheel
7. **Scope Trace** — a rose-curve oscilloscope the feedback turns into a spirograph
8. **Mirror Hall** — mirrored arcs repeated in a six-fold kaleidoscope
9. **Plasma Veil** — thin contour lines of a plasma field
10. **Warp Stars** — a starfield stretched by a fast zoom
11. **Fractal Well** — nested log-zoom rings
12. **Color Bleed** — soft color smears with a long trail and a slow spin
13. **Vortex Eye** — a tight swirling spiral
14. **Mesh Tide** — an undulating grid of thin lines
15. **Water Glass** — ripples moving out from a drifting center
16. **Flame Lift** — rising flame tongues

Four quieter pictures stay until you swipe away: **Aurora**, **Soft Bloom**, **Night Border**, and **Slow Drift**. They sit between Prism Wheel and Scope Trace in the swipe order, and the automatic rotation skips them.

Each frame is the previous frame, warped (zoom, rotation, swirl, kaleidoscope), faded, and hue-shifted, with a thin new stroke drawn on top. That feedback is what makes the trails.

## Remote

| Press | What it does |
| --- | --- |
| Swipe left or right | Previous or next picture, including the quiet ones |
| Click | Next picture |
| Hold click | Keep the title card on screen, or let it hide again |
| Play / Pause | Pause or resume. If nothing is queued, start recently played songs |
| Menu | Leave the app |

The title card fades after a few seconds, and again when the song changes. The hint at the top disappears after the first press.

The Apple TV screensaver stays off while the app is in front.

## Tempo

Wizuale sends the current title and artist to [GetSongBPM](https://getsongbpm.com) and, on a match, locks the picture to that BPM. Each beat gives a short zoom and a brighter stroke. The downbeat is a little stronger. Time signature and key are used when the database has them (the bar length follows the time signature; the phrase is 8 bars, which is 32 beats in 4/4).

The downbeat is aligned to the start of the track. GetSongBPM does not provide a beat-grid offset, so a song with a long silent intro can sit a little early or late.

Put your API key in a file that is not committed:

```
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

`Config/Secrets.xcconfig` is gitignored. The setting name is `GETSONGBPM_API_KEY`:

```
GETSONGBPM_API_KEY = your_key_here
```

The tvOS target reads that through `Config/Base.xcconfig`. The build copies it into the app as the Info.plist value `GetSongBPMAPIKey`. Leave the setting empty, keep the placeholder `YOUR_KEY_HERE`, or skip the file, and Wizuale keeps the built-in pulse for every song.

Lookups are cached on device (a match for 30 days, a miss for 3 days). A network failure is not cached; the same song is tried again after a few seconds. While a match is in use, the corner card shows the BPM and the credit line "Tempo data by GetSongBPM" stays on screen.

## Open the project

You need a Mac with Xcode 15 or newer. Open `Wizuale.xcodeproj`. The target is tvOS 17.

`project.yml` is only there if you prefer [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen && xcodegen generate`). The checked-in Xcode project is the one to open.

## Signing and Apple Music

The bundle id is `app.wizuale.Wizuale`. Create the App ID with that exact identifier. If you change it, change the target's Signing settings to the same string.

MusicKit needs a paid Apple Developer Program membership. A free personal team cannot enable it.

1. Go to [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) → Identifiers → + → App IDs. Use the explicit identifier `app.wizuale.Wizuale`.
2. Enable the **MusicKit** service and save.
3. In Xcode, select the Wizuale target → Signing & Capabilities → Team. Leave **Automatically manage signing** on.
4. The MusicKit entitlement is already in `Wizuale/Wizuale.entitlements`. If signing fails on that key, the App ID does not have the MusicKit service yet.

The usage string shown in the permission prompt is: "Wizuale reads the album you're playing so the picture can borrow its colors. It never listens to the audio."

## Run it on an Apple TV

tvOS has no Developer Mode switch.

1. Put the Mac and the Apple TV on the same network. The Mac needs IPv6 working on that network; a guest Wi-Fi that blocks device-to-device traffic will not pair.
2. On the Apple TV: Settings → Remotes and Devices → Remote App and Devices, and leave that screen open.
3. On the Mac: Xcode → Window → Devices and Simulators (Xcode 16 calls this Device Hub). Select the Apple TV and enter the PIN it shows.
4. If the TV asks you to trust the computer, trust it.
5. Choose the Apple TV as the run destination and press Run.
6. The first launch may ask you to trust the developer under Settings → General → VPN & Device Management, or the equivalent profile screen on your tvOS version.

The simulator can show the pictures. It has no Apple Music library, so the title card stays on the fallback colors there. Judge the look on a TV.

## What you will see with music

With permission granted, the app reads the system Music player several times a second: title, artist, cover, and playback position. It does not replace a queue that is already playing. Play/Pause starts your recently played songs only when the queue is stopped, and falls back to the library if recent songs are empty. A matched tempo is described under the artist, for example "116 BPM · 4/4 · Fm".

AirPlay from an iPhone often does not appear in that system player. When it doesn't, the picture keeps its own colors and the card says nothing is playing. That is a limit of MusicKit, not a missing permission.

If you deny access, the pictures still run. They use the colors designed for each preset.

## Add a picture

1. Add a case to `VisualMode` in `Wizuale/Presets.swift`. The raw number is the mode the shader switches on, so keep it in sync.
2. Write a small `emit…` function in `Wizuale/Shaders.metal` and call it from `emitMode`.
3. Append a `Preset` in `PresetLibrary.all`.
4. Set `cyclesAutomatically` if it should join the rotation (about 45 seconds, or the next 8-bar phrase when a tempo is matched). Leave it off and the picture waits until someone swipes.

Paint thin bright strokes. A shape that fills the screen stacks on itself until the frame clips white. `decayTau` around 0.5–1.5 seconds is the useful range: lower fades faster, higher leaves longer trails. Warp amounts are in screen-units per second, so a dropped frame does not change the look.

The shader comment at the top of `Shaders.metal` names the uniform fields. `beat` and `music` carry the phase-aligned clock. They stay at zero when no tempo was matched, and the old pulse is what you see.

## What was not run here

This project was prepared on a machine without Xcode, so it has not been compiled, signed, or launched on an Apple TV. The pictures, including the newer MilkDrop set, were not compiled here. The older pictures were tuned by running the same warp math in a WebGL preview, not by running the Metal binary. MusicKit, the Siri Remote, album-color extraction, the idle-timer lock, and the GetSongBPM lookup are written to the current tvOS 17 APIs and have not been exercised on hardware. `SystemMusicPlayer.playbackTime` is the documented playhead (it can be NaN when MusicKit has no finite time). The beat clock assumes normal speed between those samples.

On a Mac, open the project and run it on your Apple TV. If the shader fails to compile, Xcode's issue navigator will point at `Shaders.metal`. If the uniform struct ever disagrees with Swift, the screen shows that message instead of a scrambled picture.
