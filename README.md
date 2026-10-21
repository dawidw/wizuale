# Wizuale

Tempo data by [GetSongBPM](https://getsongbpm.com).

Full-screen generative pictures for Apple TV. Put a record on — Apple Music on the TV, or music you start from this app — and the screen becomes a MilkDrop-style visualizer instead of the screensaver.

The picture does not listen to the audio. Apple Music is protected, and this app never opens the stream. When a GetSongBPM key is set and the song is in their database, the picture locks to that tempo. Without a key, or when the song is not listed, motion falls back to time and a gentle built-in pulse. If Apple Music permission is on, the title and cover show briefly in the corner, and the cover's colors tint the picture.

## Pictures

Twelve classic MilkDrop-style presets play on their own. They morph into the next over about 1.3 seconds: the new stroke crossfades (a mix, not a sum), the previous frame is dimmed so the two pictures do not stack, and the warp eases across the same window instead of cutting. Without a matched tempo they hold for about 45 seconds. With a matched tempo they wait for the next 8-bar phrase after that, so the change lands on the music. Each picture also wanders a little on its own (zoom, spin, warp, hue), retargeting every few seconds. With Wizuale Mic live, bass pushes zoom, mids spin the warp, and treble adds sparkle; waveforms and spectrum bars follow the room.

1. **Tunnel Vision** — log-zoom rings and spokes rushing through a neon tunnel
2. **Plasma Drift** — hue-cycling plasma contours smeared by feedback warp
3. **Spectrum Spiral** — a bass-driven log spiral with mic-tinted arms
4. **Kaleido Bass** — mirrored arcs in an eight-fold kaleidoscope that swells with bass
5. **Starburst** — a particle starfield that flares on kicks
6. **Waveform Glow** — oscilloscope line, circular scope, and dots driven by the mic
7. **Liquid Mirror** — flowing silk ribbons with a mirrored sheen
8. **Electric Sheep** — drifting luminous particles (sheep in the fog)
9. **Fractal Tunnel** — nested log-radius well rings
10. **Spectrum Bars** — Winamp-style bars along the bottom from bass to treble
11. **Vortex Pulse** — a tight swirling spiral keyed to mids
12. **Hue Wheel** — a twelve-spoke prism wheel with hue spin

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

Wizuale sends the current title and artist to [GetSongBPM](https://getsongbpm.com) and, on a match, locks the picture to that BPM. Each beat zooms the whole frame and lifts its brightness. The downbeat is a little stronger. Time signature and key are used when the database has them (the bar length follows the time signature; the phrase is 8 bars, which is 32 beats in 4/4).

If the corner card never shows a BPM, the lookup did not match: no key, the song is not in the database, or the TV's Music player cannot see the track (AirPlay from an iPhone often does not). The picture still pulses on the preset's own tempo. For the actual sound in the room, use Wizuale Mic.

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

## Microphone

Wizuale Mic is a second app in this project, for an iPhone on the same Wi-Fi. It listens to the room and sends bass, mids, highs, loudness, and kicks to the Apple TV about 60 times a second. The picture then follows the sound: a kick slams the frame (zoom, bend, and a brightness flash) and releases a little slower than it hits, bass keeps the warp moving, highs sparkle and shift the hue, loudness speeds the preset up. Leave the phone app and the picture fades back to the beat clock. A small "Mic" mark sits in the corner of the TV while packets are arriving. The phone screen stays awake while the mic is running.

**Sensitivity** (0.25×–3×, default 1×) is on the phone's main screen, saved on the device, and sent on the control channel. It scales how hard bass, kicks, and highs drive the picture. 1× is the current slam. Loudness is not scaled. **Latency** (−200…+400 ms, step 10, default 0) is on that same screen and sent the same way. Positive delays the visuals so they can line up with a soundbar. The TV has a smaller copy of both controls (swipe down); the phone is the one to use. **Zoom** (0.5×–2×, default 1×) is on that same screen, saved the same way, and sent in the settings packet. It scales the finished picture around the center and eases over about 150 ms. A settings packet without zoom leaves the picture at 1×. The TV shows the value and does not edit it. **Drop** holds the strongest look while your finger is down, or for about 3 seconds after a tap: one hard zoom, then warp, flash, speed, and a hue shift ease back. **Calibrate** listens for about 5 seconds of quiet and saves a noise floor for bass, mids, highs, and level. **Album art colors** (on by default, saved on the phone) is sent on that same control channel. Off fades the picture back to each preset's own colors. On still skips near-white, pastel, near-black, and grey pixels in the cover, keeps every palette color in the mid-tones (about 0.6–0.7) with the saturation turned up, and leaves the preset's dark background alone when the cover has nothing saturated. The picture sheds highlights as they build, hardest in the center. A preset change starts from a dimmed copy of the previous frame. The frame's average luminance is measured and scaled down when it passes about 0.45, then Reinhard keeps the highlights, so a light cover or a crossfade cannot sit on white. Blacks stay black. A kick's brightness flash is still capped.

While a mic is live, the beat clock locks onto the kicks it hears. GetSongBPM is the starting guess and the fallback when the kicks stop. On the TV, swipe down to pick the mic source: iPhone app (Wi-Fi), Continuity Microphone, or Off. Continuity uses the Apple TV's own input, mixes with Music, and leaves voice processing off so echo cancellation does not strip the song. Allow the microphone on the TV when it asks.

The phone shows **Connected to** the Apple TV's name, with a green dot, only after the TV app answers. **Searching for Apple TV…** means the phone has not heard the app yet, even if Bonjour already found the box. The reply also names the picture on screen.

Above Start, the picture strip lists Auto and every preset, in the same order the TV uses. Tap one to ask the TV to lock it. The highlight moves when the TV answers, and that card scrolls into view. Auto lets the pictures rotate again. The white ring is the phone's lock. While Auto is on, the picture that is actually showing keeps a lighter ring. A swipe on the Siri Remote, or the TV's own rotation, updates the phone on the next reply. The corner card on the TV shows the same picture.

In Xcode, choose the **Wizuale Mic** scheme and your iPhone. The Apple TV app has to be open. Tap Start, and allow the microphone and Local Network. If the TV asks, allow Local Network there too (Settings → General → Privacy & Security → Local Network). The level meters move even before an Apple TV answers, so you can see that the phone hears the room. Update both apps together: the packet now includes a settings message, a Drop message, and a longer ack. An older build will ignore the new one.

The bundle id is `app.wizuale.Wizuale.mic`. Signing is automatic, team `59Z33S5F96`. Install it from Xcode or TestFlight. Audio is analyzed on the phone and is not uploaded.

## Open the project

You need a Mac with Xcode 15 or newer. Open `Wizuale.xcodeproj`. Wizuale is the tvOS 17 target. Wizuale Mic is the iOS 17 target.

`project.yml` is only there if you prefer [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen && xcodegen generate`). The checked-in Xcode project is the one to open.

## Signing and Apple Music

The bundle id is `app.wizuale.Wizuale`. Create the App ID with that exact identifier. If you change it, change the target's Signing settings to the same string.

MusicKit needs a paid Apple Developer Program membership. A free personal team cannot enable it.

1. Go to [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) → Identifiers → + → App IDs. Use the explicit identifier `app.wizuale.Wizuale`.
2. Enable the **MusicKit** service and save.
3. In Xcode, select the Wizuale target → Signing & Capabilities → Team. Leave **Automatically manage signing** on.
4. The MusicKit entitlement is already in `Wizuale/Wizuale.entitlements`. If signing fails on that key, the App ID does not have the MusicKit service yet.

The usage string shown in the permission prompt is: "Wizuale reads the album you're playing so the picture can borrow its colors and look up the song's tempo. It never listens to the audio."

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

Paint thin bright strokes. A shape that fills the screen stacks on itself until the frame clips white. `decayTau` around 0.5–1.5 seconds is the useful range: lower fades faster, higher leaves longer trails. Near-white feedback fades in about half a second on top of that, and a preset change multiplies the stored picture by 0.2 so the blend does not add the two looks together. The crossfade is about 1.3 seconds. Warp amounts are in screen-units per second, so a dropped frame does not change the look.

The shader comment at the top of `Shaders.metal` names the uniform fields. `beat` and `music` carry the phase-aligned clock. They stay at zero when no tempo was matched, and the old pulse is what you see.

## What was not run here

This project was prepared on a machine without Xcode, so it has not been compiled, signed, or launched on an Apple TV or an iPhone. The pictures, including the newer MilkDrop set, were not compiled here. The older pictures were tuned by running the same warp math in a WebGL preview, not by running the Metal binary. MusicKit, the Siri Remote, album-color extraction, the idle-timer lock, the GetSongBPM lookup, and the Wizuale Mic link are written to the current tvOS 17 and iOS 17 APIs and have not been exercised on hardware. `SystemMusicPlayer.playbackTime` is the documented playhead (it can be NaN when MusicKit has no finite time). The beat clock assumes normal speed between those samples. The mic path uses `AVAudioEngine` in measurement mode, `NWListener` / `NWBrowser` on `_wizuale._udp`, and the audio, command, settings, boost, and ack packets defined in `Shared/MicFrame.swift`. Continuity Microphone, the beat lock, the latency buffer, Drop, and calibration were not exercised on hardware.

On a Mac, open the project and run it on your Apple TV. If the shader fails to compile, Xcode's issue navigator will point at `Shaders.metal`. If the uniform struct ever disagrees with Swift, the screen shows that message instead of a scrambled picture.
