# ThirdParty — libprojectM for tvOS

Wizuale links **libprojectM 4.x** (LGPL) for real Milkdrop `.milk` presets. Nothing in this folder is committed by default except this README.

## Build libprojectM

On a Mac with Xcode 15+:

```bash
brew install cmake ninja   # if needed
./scripts/build-projectm-tvos.sh
# optional pin: ./scripts/build-projectm-tvos.sh --tag v4.2.0
```

Outputs:

- `ThirdParty/projectm-tvos.xcframework` — link this from the **Wizuale** tvOS target
- `ThirdParty/projectm/include/projectM-4/` — C API headers (also inside the xcframework)

Then fetch presets:

```bash
./scripts/fetch-presets.sh --count 100
```

## Xcode linkage (wired in `project.yml` and `Wizuale.xcodeproj`)

- Framework search path: `$(PROJECT_DIR)/ThirdParty`
- Link: `projectm-tvos.xcframework`, `OpenGLES.framework`
- C++ runtime: `-lc++`
- Bridging header: `Wizuale/Wizuale-Bridging-Header.h`
- Swift flag: `WIZUALE_PROJECTM` (tvOS only)

## Verify

```bash
xcodebuild -scheme Wizuale -destination 'generic/platform=tvOS' build
xcodebuild -scheme "Wizuale Mic" -destination 'generic/platform=iOS Simulator' build
```

## Risks

- **OpenGL ES on tvOS** is deprecated but still available; Apple may remove it in a future tvOS SDK. projectM requires GLES 3.
- **Static LGPL lib**: private TestFlight-only distribution is fine; keep `LICENSE.txt` from projectM in app acknowledgements if you ship broadly.
- **Preset licensing**: cream-of-the-crop presets are community Milkdrop files; use only for personal/TestFlight use unless you audit licenses.
