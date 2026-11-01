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
