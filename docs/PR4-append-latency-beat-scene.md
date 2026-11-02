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

## Dawid 1.1(5) — kick / DEBUG / suwaki (`20c5584`)

### Przyczyny (root cause)
1. **Metronom przy ciszy** — syntetyczny kick co 500 ms był włączany przez `showAudioDebug` (`RootView` → `audioDebugSyntheticKick`), więc sam overlay DEBUG odpalał fale bez muzyki.
2. **Fałszywy rytm onsetu** — `BandAnalyzer` przepuszczał słaby flux przy niskim progu (μ+1.05σ); `BeatPunchState` miał stały próg 0.30 niezależny od suwaka **Sensitivity** (Mic).
3. **Panel DEBUG „martwy”** — `noteAudioFrame` wołane z wątku GL bez `@MainActor`; `@Published` (PCM, RMS, RX) nie odświeżały się co klatkę.
4. **Tsunami bez gradacji** — `triggerPeak ≈ onset × siła` ignorował nadmiar nad progiem i energię basu 40–120 Hz → każdy trigger podobnej wielkości.

### Naprawa
- **Testowy kick** — osobny toggle (domyślnie OFF) na Mic + TV settings; sync **kind 12** + pole ack @26; TV zeruje timer metronomu przy OFF.
- **Sensitivity** — `MicTuning.kickOnsetTriggerThreshold(sensitivity)` steruje bramką kicka na TV; **Intensywność** nadal tylko przez `MicSceneModulation` (permille → PCM/tsunami).
- **Kick proporcjonalny** — `kickPeakMagnitude(onset, próg, bass)`; cisza: bramka `presence`/`loudness` + ostrzejszy flux w `BandAnalyzer`.
- **DEBUG live** — `Task { @MainActor in noteAudioFrame }`; wiersze: próg, szczyt kicka, Test kick, RX suwaki.
- **Test offline**: `python3 scripts/simulate_beat_punch_kicks.py`

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

---

## Intensywniej i czulej na bit — build 1.1(4)+

### Domyślne suwaki
| Parametr | Było | Jest |
|----------|------|------|
| **Intensywność** | 1000 (‰) = 10×, max 2000 | **2000 = 20×**, max **4000 = 40×** |
| **Siła bitu** | 70% | **85%** |

Wire kind 11: permille **0…4000** (100 = 1× f301047). Ack bez zmian (26 B).

### Saturacja (bez twardego clipu)
- Boost `projectm_set_beat_sensitivity`: **tanh** względem sufitu 10.0 (`MicTuning.sceneSoftSaturate`).
- PCM po kicku w `applyScenePunch`: **tanh** @ `softPeak` (0.68), zamiast segmentowego limitera.

### Detekcja onsetu (`BandAnalyzer` — telefon + Continuity)
- **Flux basowy**: max(Δ energii pasma bass, Δ szczytu bass po filtrze LP 110 Hz).
- **Próg adaptacyjny**: średnia + **1.35·σ** fluxu, okno EMA **~1 s** (`onsetAdaptiveWindowSeconds`).
- **Bramki**: bass shaped > **0.18**, loudness > **0.08**, refractory analizatora **75 ms**.
- **Zanik onsetu**: τ_release **42 ms** (szybsze rozdzielenie kicków @ 120–130 BPM).
- TV `MicReceiver`: follow onset attack **~2 ms** (~1 klatka), release **52 ms**.

### `BeatPunchState` (punch sceny)
- Trigger onset > **0.34**, re-arm < **0.16** (było 0.48 / 0.26).
- Attack envelope **1/60 s** (~1 klatka GL), refractory **120 ms** bez zmian.

### DEBUG TV
- Wiersz **Detekcja bitu**: `X.XX/s  ~YYY bpm` (okno triggerów punch, zsynchronizowane z BEAT TEST).
- **Scene punch**: envelope + Siła bitu % (BPM przeniesione do Detekcja bitu).

Pliki: `MicTuning`, `MicAnalyzer`, `BeatPunchState`, `MicReceiver`, `ProjectMAudioHub`, `MicFrame`, `MicAudioDebugOverlay`, `MicRootView` (zakres suwaka z `MicTuning`).

(Wklej do PR #4 przed `<!-- CURSOR_AGENT_PR_BODY_END -->`.)

---

## Tsunami radialne na kick (osobno od Intensywności) — build 1.1(5)+

### Dlaczego nie A/C
- **A)** `ProjectMController` nie wystawia mostu do `per_frame` / custom vars — tylko PCM, sensitivity, render FBO.
- **C)** Sam PCM kick daje głównie globalny `pulse`/zoom w presetach (Study of Space) — odrzucone jako jedyny efekt (mechaniczny), bez edycji `.milk`.

### Podejście **B** — kompozytor po projectM
- libprojectM renderuje do **offscreen FBO**; pełnoekranowy **GLES3** pass próbkuje teksturę z **radialnym przesunięciem UV** (fala wychodząca od środka, faza ∝ czas od onsetu).
- **Jasność neutralna** — tylko warp UV, bez skali UIView i bez brighteningu audio.

### Kick envelope vs Intensywność
| Ścieżka | Trigger | Skala suwakiem | Efekt |
|---------|---------|----------------|--------|
| **Kick (discrete)** | ten sam onset co BEAT TEST / `BeatPunchState`, **0 klatek opóźnienia** | **Siła bitu** (domyślnie 85%) | envelope → tsunami compositor + opcjonalny krótki PCM kick |
| **Continuous** | `MicDrive.bass` (płynna energia sali) | **Intensywność** (‰) | boost `projectm_set_beat_sensitivity` (`sceneContinuousSensitivityBaseline × bass × N`) — **bez** mnożenia kick envelope |

### Parametry kick envelope
- Attack: **1 klatka** (natychmiast `triggerPeak`).
- Decay: wykładniczy **τ = 200 ms** (`MicTuning.kickWaveReleaseTau`), bez overshootu.
- Refractory / progi onsetu: bez zmian względem 273d231.

### Parametry fali (tsunami)
| Stała | Wartość | Znaczenie |
|-------|---------|-----------|
| `kickWaveRingFrequency` | 22 | częstotliwość pierścieni w promieniu UV |
| `kickWavePhaseSpeed` | 16 rad/s | faza fali wychodzącej od onsetu |
| `kickWaveMaxDisplacement` | 0.042 | max przesunięcie UV @ env=1, Siła=100% |

Siła bitu skaluje envelope (`triggerPeak`), compositor i PCM kick — **Intensywność nie**.

### DEBUG
- **Kick env**: wartość envelope + etykieta `ONSET` przy flashu + Siła bitu %.
- **BEAT TEST**: słupek KICK z envelope; kropka = flash onsetu.

(Wklej do PR #4 przed `<!-- CURSOR_AGENT_PR_BODY_END -->`.)

---

## Kompilacja tvOS + onset kick (40–120 Hz) — build 1.1(5)+ fix

### Kompilacja (Xcode / Dawid)
- **ProjectMCanvasView**: `GLKView.defaultFramebufferObject` nie istnieje na tvOS → na początku `drawIn` zapis FBO przez `glGetIntegerv(GL_FRAMEBUFFER_BINDING)` po bindzie GLKView; blit tsunami na ten FBO zamiast `defaultFramebufferObject`.
- **MicRootView**: operator `...` w `in:` suwaka Intensywność nie może być rozdzielony na linie → `sceneIntensitySliderRange` (`ClosedRange<Double>`).

Brak nowego kind UDP — onset nadal w pakiecie audio (40 B, pole `onset` f32).

### Onset (telefon + Continuity, `BandAnalyzer`)
| Parametr | Było | Jest |
|----------|------|------|
| Pasmo kick | LP bass 110 Hz + błędny Δ (zawsze 0 po `previousEnergy = energy`) | **HP 40 Hz + LP 120 Hz**, flux **tylko dodatni** Δ energii kick |
| Próg adaptacyjny | μ + **1.35·σ** | μ + **1.05·σ** |
| Refractory analizatora | 75 ms | **120 ms** |
| Pasmo bass / Intensywność (continuous) | bez zmian | **bez zmian** (LP 110 Hz, normalizer) |

### TV (`MicReceiver` + `BeatPunchState`)
- Przy **nowym** datagramie cech: `onset = max(smooth, target.onset)` — zero dodatkowego opóźnienia transiente vs telefon.
- Trigger tsunami: próg onset **0.30** (było 0.34); refractory punch **120 ms** bez zmian.

(Wklej do PR #4 przed `<!-- CURSOR_AGENT_PR_BODY_END -->`.)

---

## Build 1.1(4) — suwaki + tsunami (ROOT CAUSE) — fix agent

### Przyczyny (PL)
1. **`ProjectMController.setBeatSensitivity`** wołało `MicTuning.clampSensitivity` (**max 3.0**), podczas gdy ścieżka sceny liczy boost do **~10** (`sceneBeatSensitivityCeiling`) — każda klatka **obcinała** efekt suwaków; przy domyślnej Intensywności 20× wyjście i tak siedziało na **3.0** → suwaki „martwe”.
2. **`clampSceneBeatSensitivity`** stosowało **tanh(base+boost)** — przy wysokim boostcie saturacja **zjadała** rozdzielczość Intensywności (continuous); poprawka: **base + tanh(boost)**.
3. **Tsunami**: podwójne mnożenie **Siły bitu** (envelope w `BeatPunchState` × `uStrength` w shaderze) + **`uMaxDisp` z pełnym envelope** (potrójne) + niski **`kickWaveMaxDisplacement` (0.042)** → fala prawie niewidoczna.
4. **Intensywność (‰)** dotyczy tylko **continuous** (`drive.bass` → boost sensitivity); **Siła bitu** — kick/tsunami/PCM — to oczekiwane po rozdzieleniu ścieżek, ale bez (1–3) oba suwaki wyglądały na bezużyteczne.

### Naprawa
- `clampProjectMBeatSensitivity` (0.25…**10**) w `projectm_set_beat_sensitivity`.
- `MicSceneModulation` + DEBUG: **RX suwaki**, **mnożniki**, **→ projectM**, **Tsunami UV**.
- Kompozytor: jedno mnożenie envelope, **`kickWaveMaxDisplacement = 0.12`**, łagodniejszy falloff pierścieni.
- **AUDIO DEBUG**: syntetyczny kick co **500 ms** (bez muzyki w sali).
- Offline: `scripts/render_kick_envelope_test.py` → `docs/kick-envelope-test/envelope_{0,0.5,1.0}.png`.

(Wklej do PR #4 przed `<!-- CURSOR_AGENT_PR_BODY_END -->`.)

---

## Build 1.1(6)+ — bas ciągły + słabszy kick

### Problem
Po `20c5584` wrażenie „tylko kick”: suma `kickBoost + continuousBoost` szła przez **jeden tanh** → spike kicka saturował łączny boost `projectm_set_beat_sensitivity`; kick PCM/tsunami (bez Intensywności w `applyScenePunch`) dominował nad płynnym zoomem z `MicDrive.bass`.

### Mix (domyślnie Intensywność 20×, Siła 85%)
| Ścieżka | Trigger | Skala | Parametry @1× |
|---------|---------|-------|----------------|
| **Bas ciągły** | `drive.bass`, TV follow τ_release **240 ms** | **Intensywność** | sensitivity boost **0.88×** bass (cap 2.8), tanh sufit **10** |
| **Kick akcent** | onset + Siła | **Intensywność × Siła** | sensitivity **+0.20×env**, PCM **0.16×env**, UV max **0.058**, tanh sufit kick **2.4**, envelope τ **95 ms** |

Przy basie 0.75 i env kick 0.55: stosunek boostów cont/kick ≈ **7×**; `projectM` sensitivity idle→hit nie spada (osobne tanh).

### DEBUG
- Wiersz **Mix bas/kick**: stosunek cont/kick, PCM mix, UV peak.

### Test offline
`python3 scripts/simulate_scene_modulation_mix.py`

(Wklej do PR #4 przed `<!-- CURSOR_AGENT_PR_BODY_END -->`.)
