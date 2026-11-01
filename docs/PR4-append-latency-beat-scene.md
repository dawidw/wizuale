## Bit w scenie projectM (bez transform UIView) — `614fdd7`…`052f0a7`

### Co było nie tak (build 1.1(2))
- **BeatPunchState** skalował/obracał host UIView po `projectm_opengl_render_frame_fbo` → mechaniczny zoom, nie MilkDrop.
- Cechy Wi‑Fi na TV miały długie `follow()` (bass τ_release ~220 ms) + FIFO jitter ~70 ms → odczuwalne opóźnienie ruchu względem sali.

### Podejście
- Usunięto post-frame transform; GLKView bezpośrednio na ekranie.
- Ten sam **onset** z `MicDrive` → envelope w `BeatPunchState` (refractory 120 ms, attack/release jak wcześniej).
- Ruch w **symulacji**: krótki basowy kick w PCM (`applyScenePunch`, ~58 Hz, soft limit) + lekki boost `projectm_set_beat_sensitivity` — presety (Study of Space, `bass`/`bass_att` → `pulse`, zoom, rot) reagują jak MilkDrop, bez tanh-brightening.
- Suwak **Siła bitu** (kind 10) skaluje envelope i sensitivity boost.

### Latencja phone→TV (szacunek @ 48 kHz, `latencyMs=0`)

| Etap | Przed (1.1(2)) | Po |
|------|----------------|-----|
| TV feature smoothing (bass release) | ~220 ms | ~105 ms |
| Onset na TV | peak-hold + decay 140 ms | follow attack 10 ms / release 85 ms |
| PCM FIFO jitter target | 70 ms | 40 ms |
| AGC / bass_att ścieżka | τ ~550 ms/sample | τ ~350 ms/sample |
| **Ruch vs sala (typowo)** | **~250–400 ms** | **~120–180 ms mniej** |

DEBUG: wiersz **Feat age** (ms od datagramu cech), **Scene punch** (envelope + % + ~bpm). Kropka BEAT TEST = flash przy triggerze onsetu.

Presety `.milk` bez zmian. TestFlight nie uruchamiany.

(Wklej powyższe do opisu PR #4 przed `<!-- CURSOR_AGENT_PR_BODY_END -->`.)

---

## Intensywność sceny (~10× domyślnie) — build 1.1(3)+

### Semantyka suwaków
- **Siła bitu** (kind 10): bramkowanie onsetu / transient punch — jak mocno kick przechodzi z `MicDrive.onset` do envelope (`BeatPunchState`, refractory 120 ms).
- **Intensywność** (kind 11): amplituda reakcji sceny — mnożnik ścieżki PCM kick (`applyScenePunch`) i boostu `projectm_set_beat_sensitivity` względem baseline f301047, niezależnie od bramki onsetu.

### Wire
| Pakiet | kind | bajty | pola (LE, po magic `MIC1`) |
|--------|------|-------|------------------------------|
| Scene intensity | 11 | 12 | u16 kind, u16 seq @6, u16 **permille** @8 (0…2000, **100 = 1×** f301047, domyślnie **1000 = 10×**), u16 reserved @10 |
| Ack (pełny) | 3 | **26** | … u16 beatStrength @22, u16 **sceneIntensity permille @24** |

Klucze UserDefaults: `wizuale.mic.sceneIntensity`, `wizuale.tv.sceneIntensity`.

### Gain (baseline f301047 → przy Intensywność = N×)
- PCM mix: `envelope × 0.38 × N` (clamp envelope 0…1.2, `softLimit` na próbkach).
- Sensitivity boost: `envelope × 0.42 × (Siła bitu/100) × N`, suma z bazą czułości → `min(..., 10.0)`.

Przy domyślnej **Intensywność 10×** i Siła bitu 70%: efektywnie ~**10×** mocniejszy kick w PCM i ~**7×** boost sensitivity vs f301047 @ 100% Siła bitu.

### Pliki
`Shared/MicTuning.swift`, `Shared/MicFrame.swift`, `WizualeMic/MicCapture.swift`, `WizualeMic/MicRootView.swift`, `Wizuale/MicReceiver.swift`, `Wizuale/VisualSession.swift`, `Wizuale/ProjectMCanvasView.swift`, `Wizuale/ProjectM/ProjectMAudioHub.swift`, `Wizuale/MicAudioDebugOverlay.swift`, `Wizuale/RootView.swift`.

DEBUG TV: wiersz **Intensywność** (np. `10×`).

(Wklej do PR #4 przed `<!-- CURSOR_AGENT_PR_BODY_END -->`.)
