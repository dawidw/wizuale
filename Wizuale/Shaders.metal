#include <metal_stdlib>
using namespace metal;

// MilkDrop-style feedback. Each frame samples the previous frame through a
// warped coordinate, fades it, then stamps a thin new shape. The warp is what
// turns those stamps into trails, petals, and filaments. To add a look, add
// an emit function and a branch in emitMode, then a Preset in Presets.swift
// whose mode raw value matches the branch. Paint thin and bright. A full-screen
// fill stacks until the picture clips white.

struct FrameUniforms {
    float2 resolution;
    float time;
    float deltaTime;
    float4 flow;     // expansion, rotation, rotationInner, kaleidoSpin
    float4 warp;     // amount, frequency, speed, radial
    float4 center;   // centerAmp, goo, folds, kaleidoMix
    float4 persist;  // decayTau, blurPx, hueShift, chroma
    float4 wave;     // zoom (1 = fit), frequency, thickness, radiusOffset
    float4 shape;    // count, radius, softness, intensity
    float4 grade;    // sparkle, dropPunch, saturation, vignette
    float4 style;    // exposure, baseLevel, emissionGain, pulseAmount
    float4 tempo;    // bpm, modeFrom, modeTo, modeT
    float4 hole;     // centerHole, centerDark, grain, drop (held)
    float4 beat;     // kick, downbeat, beatPhase, barPhase  (0 when no matched tempo)
    float4 music;    // phrasePhase, beatsPerBar, realTempo (1 = matched), feedback dim (0.2 on a switch)
    float4 color0;
    float4 color1;
    float4 color2;
    float4 baseColor;
    float4 ear;      // onset, bass, high, loudness          (mic; 0 when the phone is gone)
    float4 link;     // presence, flux, lowMid, mid
};

struct Varyings {
    float4 position [[position]];
    float2 uv;
};

vertex Varyings fullscreenVertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid == 1) ? 3.0 : -1.0, (vid == 2) ? 3.0 : -1.0);
    Varyings out;
    out.position = float4(pos, 0.0, 1.0);
    out.uv = float2(pos.x * 0.5 + 0.5, 0.5 - pos.y * 0.5);
    return out;
}

constant float PI = 3.14159265359;
constant float TAU = 6.28318530718;

float safeMod(float x, float y) { return x - y * floor(x / y); }

float hash21(float2 p) {
  p = fract(p * float2(123.34, 345.45));
  p += dot(p, p + 34.345);
  return fract(p.x * p.y);
}

float2 rot2(float2 p, float a) {
  float c = cos(a), s = sin(a);
  return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float3 ramp(float t, constant FrameUniforms &u) {
  float x = fract(t);
  float3 a = mix(u.color0.rgb, u.color1.rgb, smoothstep(0.0, 0.55, x));
  return mix(a, u.color2.rgb, smoothstep(0.32, 1.0, x));
}

float pulseAmt(constant FrameUniforms &u) {
  // Matched tempo: the CPU clock is already phase-aligned to playback time.
  // Otherwise keep the original narrow pulse so an unmatched song looks the same.
  if (u.music.z > 0.5) {
    return u.beat.x * u.style.w;
  }
  float beat = u.time * u.tempo.x * (TAU / 60.0);
  return pow(max(sin(beat), 0.0), 12.0) * u.style.w;
}

float kick(constant FrameUniforms &u) {
  return u.beat.x * step(0.5, u.music.z);
}

float downbeat(constant FrameUniforms &u) {
  return u.beat.y * step(0.5, u.music.z);
}

// Phrase angle when a tempo matched, otherwise a slow clock so the picture still moves.
float phraseTurn(constant FrameUniforms &u) {
  if (u.music.z > 0.5) return u.music.x * TAU;
  return u.time * 0.22;
}

// 1 while Wizuale Mic is sending, fading to 0 after the last packet.
float liveWeight(constant FrameUniforms &u) {
  return clamp(u.link.x, 0.0, 1.0);
}

// 0..1. A matched tempo uses the phase-aligned kick. Otherwise a wider spike
// at the preset BPM, so a song the database missed still moves.
float clockEnvelope(constant FrameUniforms &u) {
  if (u.music.z > 0.5) {
    return max(kick(u), downbeat(u) * 0.85);
  }
  float phase = u.time * max(u.tempo.x, 1.0) * (TAU / 60.0);
  return pow(max(sin(phase), 0.0), 6.0);
}

float2 toP(float2 uv, constant FrameUniforms &u) {
  float aspect = u.resolution.x / max(u.resolution.y, 1.0);
  return float2((uv.x - 0.5) * aspect, (0.5 - uv.y));
}

float2 toUV(float2 p, constant FrameUniforms &u) {
  float aspect = u.resolution.x / max(u.resolution.y, 1.0);
  return float2(p.x / aspect + 0.5, 0.5 - p.y);
}

float2 foldKaleido(float2 p, float folds, float mixAmt) {
  if (mixAmt < 0.001 || folds < 1.5) return p;
  float n = max(floor(folds + 0.5), 1.0);
  float a = atan2(p.y, p.x);
  float r = length(p);
  float slice = TAU / n;
  a = safeMod(a + slice * 0.5, slice);
  a = abs(a - slice * 0.5);
  float2 f = r * float2(cos(a), sin(a));
  return mix(p, f, clamp(mixAmt, 0.0, 1.0));
}

float2 advect(float2 p, constant FrameUniforms &u) {
  float r = length(p);
  float a = atan2(p.y, p.x);
  float beat = pulseAmt(u);
  float dt = u.deltaTime;
  float mic = liveWeight(u);
  // Bass and low-mid shove the warp. Loudness speeds the whole preset up.
  float body = max(u.ear.y, u.link.z * 0.85);
  float loud = u.ear.w;
  // Drop is the phone's held button. It speeds the preset and swirls harder.
  // The zoom itself is `dropPunch`, a one-shot, so holding the button does not
  // keep integrating zoom into the feedback buffer.
  float drop = clamp(u.hole.w, 0.0, 1.0);
  float slam = clamp(u.grade.y, 0.0, 1.5);
  float drive = (1.0 + loud * mic * 0.85) * (1.0 + drop * 1.55);
  // Onset carries the kick. Flux only fills in if the onset gate missed it.
  float hit = max(u.ear.x, u.link.y * 0.45);
  a += (u.flow.y + (body * 1.35 + hit * 0.45) * mic + drop * 1.8) * dt * drive;
  a += u.flow.z * dt * drive / (r + 0.28);
  float warpAmt = u.warp.x + (body * 0.95 + hit * 0.62) * mic + drop * 1.05;
  a += sin(r * u.warp.y - u.time * u.warp.z * drive) * warpAmt * dt * drive;
  // `punch` is a zoom rate, multiplied by dt below. It integrates for the
  // length of the hit and then stops, so the frame slams forward and settles.
  // The mic hit replaces the clock while the phone is live, so the two don't stack.
  float clockZoom = clockEnvelope(u) * 2.2;
  float micZoom = hit * 4.0 + body * 0.36;
  float punch = mix(clockZoom, micZoom, mic) + slam * 8.5;
  float expand = u.flow.x * drive * (1.0 + beat * (1.0 - mic) * 1.4) + punch;
  r = r / max(exp(expand * dt), 0.0001);
  r += sin(a * max(u.center.z, 1.0) + u.time * u.warp.z * drive * 0.65) * u.warp.w * dt * drive;
  float2 q = float2(cos(a), sin(a)) * r;
  float goo = u.center.y * dt * drive;
  float f = u.warp.y;
  float s = u.warp.z;
  q.x += (sin(q.y * f + u.time * s) * 0.72 + sin(q.y * f * 2.07 - u.time * s * 1.37) * 0.28) * goo;
  q.y += (sin(q.x * f * 0.86 - u.time * s * 0.77) * 0.72 + sin(q.x * f * 1.9 + u.time * s * 0.53) * 0.28) * goo;
  q += float2(sin(u.time * 0.17), cos(u.time * 0.13)) * u.center.x;
  return q;
}


float3 samplePrev(float2 uv, texture2d<float> prevTex, sampler samp) {
  float2 m = clamp(uv, float2(0.0), float2(1.0));
  float outside = max(max(-uv.x, uv.x - 1.0), max(-uv.y, uv.y - 1.0));
  float3 c = prevTex.sample(samp, m).rgb;
  return c * (1.0 - smoothstep(0.0, 0.012, outside));
}

float3 blurAt(float2 uv, float px, texture2d<float> prevTex, sampler samp, constant FrameUniforms &u) {
  float2 t = float2(px) / max(u.resolution, float2(1.0));
  float3 center = samplePrev(uv, prevTex, samp);
  float3 c = center * 0.62;
  c += samplePrev(uv + float2(t.x, 0.0), prevTex, samp) * 0.095;
  c += samplePrev(uv - float2(t.x, 0.0), prevTex, samp) * 0.095;
  c += samplePrev(uv + float2(0.0, t.y), prevTex, samp) * 0.095;
  c += samplePrev(uv - float2(0.0, t.y), prevTex, samp) * 0.095;
  return max(c, center * 0.88);
}

float micEnergy(constant FrameUniforms &u) {
  float mic = liveWeight(u);
  if (mic < 0.001) return 0.0;
  return mic * (u.ear.y * 0.55 + u.link.z * 0.38 + u.link.w * 0.28 + u.ear.z * 0.22);
}

float luma3(float3 c) {
  return dot(max(c, float3(0.0)), float3(0.2126, 0.7152, 0.0722));
}

// Hue-preserving peak cap (no Reinhard grey lift).
float3 capPeak(float3 c, float cap) {
  float m = max(c.r, max(c.g, c.b));
  if (m > cap) c *= cap / m;
  return max(c, float3(0.0));
}

float3 boostSat(float3 c, float amount) {
  float y = luma3(c);
  return max(mix(float3(y), c, amount), float3(0.0));
}

float3 capLuma(float3 c, float cap) {
  float y = luma3(c);
  if (y > cap) c *= cap / y;
  return max(c, float3(0.0));
}

float sampleMicWave(float x, constant FrameUniforms &u) {
  float mic = liveWeight(u);
  float bass = u.ear.y * mic;
  float mid = u.link.w * mic;
  float low = u.link.z * mic;
  float high = u.ear.z * mic;
  float onset = u.ear.x * mic;
  float t = u.time * 3.6 + x * 14.0;
  float w = bass * sin(t) * 1.05 + mid * sin(t * 2.08 + 0.7) * 0.72
          + high * sin(t * 4.4 + 1.2) * 0.42 + low * sin(t * 1.35 - 0.4) * 0.48;
  w += onset * sin(t * 8.5) * 0.32;
  return w;
}

// Mode numbers match VisualMode in Presets.swift (0…19).
float3 emitTunnelVision(float2 p, constant FrameUniforms &u) {
  float r = length(p);
  float a = atan2(p.y, p.x);
  float n = max(u.shape.x, 1.0);
  float k = kick(u);
  float d = downbeat(u);
  float travel = (u.music.z > 0.5) ? (u.beat.z * TAU) : (u.time * 1.4);
  float rings = pow(0.5 + 0.5 * sin(log(max(r, 0.002)) * u.wave.y - travel), 24.0);
  float beams = pow(0.5 + 0.5 * cos(a * n), max(u.shape.z, 0.6));
  float streak = pow(0.5 + 0.5 * cos(a * n * 0.5 - r * 8.0 + u.time * 0.6), 18.0);
  float fade = smoothstep(0.85, 0.05, r);
  float3 col = ramp(r * 1.4 + u.time * 0.05 + a * 0.05 + micEnergy(u), u);
  float m = (rings * 0.85 + streak * 0.95) * fade + beams * exp(-r * 2.2) * 0.12;
  m += exp(-pow(r / 0.02, 2.0)) * 0.12;
  return capPeak(col * m * (0.55 + k * 0.35 + d * 0.18), 0.42);
}

float3 emitPlasmaDrift(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float d = downbeat(u);
  float turn = phraseTurn(u);
  float field = sin(p.x * 5.4 + turn) + sin(p.y * 4.5 - u.time * 0.32) + sin((p.x + p.y) * 3.3 + turn * 0.45);
  field += micEnergy(u) * sin(p.x * 9.0 - u.time * 0.5) * 0.35;
  float ridge = pow(abs(sin(field * 2.15)), 16.0);
  float3 col = ramp(0.5 + 0.5 * sin(field * 0.5) + u.music.x * 0.25, u);
  return capPeak(col * ridge * (0.5 + k * 0.35 + d * 0.15), 0.38);
}

float3 emitSpectrumSpiral(float2 p, constant FrameUniforms &u) {
  float r = length(p);
  float a = atan2(p.y, p.x);
  float n = max(u.shape.x, 1.0);
  float k = kick(u);
  float d = downbeat(u);
  float mic = liveWeight(u);
  float arm = pow(max(cos(a * n * 0.5), 0.0), 6.0);
  float bins = sin(a * n * 3.0 + u.time * 0.6) * 0.5 + 0.5;
  bins *= mix(0.35, u.ear.y * 0.9 + u.link.w * 0.5 + u.ear.z * 0.35, mic);
  float phase = a * n - log(max(r, 0.004)) * u.wave.y + u.time * 0.55 + k * 0.55 + bins * 0.4;
  float ridge = exp(-pow(sin(phase) / 0.10, 2.0));
  float strand = exp(-pow(sin(a * n * 2.0 + r * 22.0 - u.time * 0.4) / 0.07, 2.0));
  float core = exp(-pow(r / 0.02, 2.0));
  float3 col = ramp(0.02 + r * 1.7 + d * 0.08 + micEnergy(u), u);
  float body = ridge * arm * 0.72 + strand * arm * 0.28 + core * 0.1;
  return capPeak(col * body * (0.55 + k * 0.45 + d * 0.2), 0.4);
}

float3 emitKaleidoBass(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float d = downbeat(u);
  float turn = phraseTurn(u);
  float2 q = float2(abs(p.x), abs(p.y));
  float bass = max(u.ear.y, u.link.z * 0.85) * liveWeight(u);
  float arc = exp(-pow((length(q - float2(0.20, 0.06)) - 0.14 - bass * 0.04) / 0.007, 2.0));
  float spoke = exp(-pow((q.y - 0.02 * sin(q.x * 10.0 + turn)) / 0.006, 2.0));
  spoke *= smoothstep(0.62, 0.04, q.x);
  float gem = exp(-pow(length(q - float2(0.12, 0.28)) / (0.02 + k * 0.012 + bass * 0.02), 2.0));
  float3 col = ramp(q.x + q.y + u.music.x * 0.35 + bass, u);
  return capPeak(col * (arc * (0.65 + k * 0.4) + spoke * 0.45 + gem * (0.25 + d * 0.28)), 0.42);
}

float3 emitStarburst(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float d = downbeat(u);
  float turn = phraseTurn(u);
  float hit = max(u.ear.x, u.link.y * 0.45) * liveWeight(u);
  float3 acc = float3(0.0);
  float2 gp = p * 13.0;
  float2 cellId = floor(gp);
  float2 cellFract = fract(gp) - 0.5;
  for (int gy = -1; gy <= 1; gy++) {
    for (int gx = -1; gx <= 1; gx++) {
      float2 cell = cellId + float2(float(gx), float(gy));
      float h = hash21(cell);
      if (h < 0.48 - hit * 0.12) continue;
      float twinkle = 0.45 + 0.55 * sin(u.time * (0.55 + h) + turn + h * 19.0);
      float2 glide = 0.18 * float2(sin(u.time * 0.09 + h * 6.2), cos(u.time * 0.07 + h * 3.7));
      float2 delta = cellFract - float2(float(gx), float(gy)) - glide;
      float star = exp(-dot(delta, delta) * 42.0);
      acc += ramp(h + u.music.x * 0.22, u) * star * twinkle * (0.7 + k * 0.85 + d * 0.35 + hit * 1.1);
    }
  }
  return capPeak(acc * smoothstep(1.05, 0.12, length(p)), 0.45);
}

float3 emitWaveformGlow(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float d = downbeat(u);
  float mic = liveWeight(u);
  float wave = sampleMicWave(p.x, u);
  if (mic < 0.02) {
    wave += 0.09 * sin(p.x * 8.0 + u.time * 2.0) * clockEnvelope(u);
  }
  float thick = max(u.wave.z, 0.004);
  float line = exp(-pow((p.y - wave) / thick, 2.0));
  float glow = exp(-pow((p.y - wave) / (thick * 4.0), 2.0));
  float r = length(p);
  float ang = atan2(p.y, p.x);
  float circ = sampleMicWave(ang / TAU + u.time * 0.12, u);
  float ring = exp(-pow((r - 0.30 - circ * 0.55) / 0.0065, 2.0));
  float dots = 0.0;
  for (int i = 0; i < 24; i++) {
    float fi = float(i) / 24.0;
    float da = fi * TAU + u.time * 0.15;
    float2 pt = float2(cos(da), sin(da)) * (0.28 + sampleMicWave(fi, u) * 0.35);
    dots += exp(-dot(p - pt, p - pt) * 1200.0);
  }
  float3 col = ramp(0.5 + p.x * 0.3 + u.music.x * 0.2 + micEnergy(u), u);
  return capPeak(col * (line * (0.75 + k * 0.5 + d * 0.12) + glow * 0.08 + ring * 0.22 * (0.35 + mic) + dots * 0.14 * (0.3 + mic)), 0.42);
}

float3 emitLiquidMirror(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float sway = (u.music.z > 0.5) ? sin(u.beat.z * TAU) * 0.018 : 0.0;
  float mic = liveWeight(u);
  float wob = sin(p.x * u.wave.y + u.time * 0.32 + u.ear.y * mic * 2.0) * 0.10;
  float wob2 = sin(p.x * u.wave.y * 0.62 - u.time * 0.21 + 1.7) * 0.14;
  float wob3 = sin(p.x * u.wave.y * 1.3 + u.time * 0.17) * 0.05;
  float b1 = exp(-pow((p.y - wob - sway) / 0.055, 2.0));
  float b2 = exp(-pow((p.y - 0.20 - wob2 - sway * 0.6) / 0.08, 2.0));
  float b3 = exp(-pow((p.y + 0.16 - wob3 + sway * 0.4) / 0.045, 2.0));
  float sheen = pow(0.5 + 0.5 * sin(p.x * 3.0 - p.y * 8.0 + u.time * 0.4), 6.0);
  float3 col = ramp(0.25 + p.y * 0.8 + u.time * 0.03, u);
  return capPeak(col * (b1 * 0.28 + b2 * 0.18 + b3 * 0.2) * (0.55 + sheen * 0.18) * (0.65 + k * 0.35), 0.35);
}

float3 emitTealDust(float2 p, constant FrameUniforms &u) {
  float3 acc = float3(0.0);
  float scale = max(u.wave.y, 2.0);
  float2 gp = p * scale;
  float2 id = floor(gp);
  float2 f = fract(gp) - 0.5;
  float mic = liveWeight(u);
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      float2 cell = id + float2(float(i), float(j));
      float h = hash21(cell);
      if (h < 0.62 - mic * 0.06) continue;
      float2 motion = float2(
        sin(u.time * 0.15 + h * TAU),
        cos(u.time * 0.12 + h * 11.0)
      ) * 0.32;
      float2 d = f - float2(float(i), float(j)) - motion;
      float star = exp(-dot(d, d) * 28.0);
      acc += ramp(h, u) * star * (0.55 + 0.45 * sin(u.time * 0.8 + h * 20.0) + kick(u) * 0.85 + u.ear.z * mic * 0.4);
    }
  }
  return capPeak(acc * 0.62, 0.42);
}

float3 emitGreenRays(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float mic = liveWeight(u);
  float wave = sampleMicWave(p.x, u);
  if (mic < 0.02) wave += 0.07 * sin(p.x * 9.0 + u.time * 2.2) * clockEnvelope(u);
  float thick = max(u.wave.z, 0.003);
  float line = exp(-pow((p.y - wave) / thick, 2.0));
  float a = atan2(p.y, p.x);
  float ray = pow(max(cos(a), 0.0), 52.0) * exp(-length(p) * (1.35 - k * 0.25));
  float streak = exp(-pow((abs(p.y) - abs(p.x) * 0.08) / 0.0045, 2.0)) * smoothstep(0.95, 0.05, length(p));
  float3 col = ramp(0.22 + micEnergy(u), u);
  return capPeak(col * (line * (0.85 + k * 0.55) + ray * 0.38 + streak * 0.22), 0.44);
}

float3 emitOrbGrid(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float mic = liveWeight(u);
  float r = length(p);
  float core = exp(-pow(r / (0.14 + k * 0.02 + u.ear.y * mic * 0.03), 2.0));
  float fuzz = pow(0.5 + 0.5 * sin(atan2(p.y, p.x) * 9.0 + r * 22.0 - u.time * 0.5), 14.0);
  float3 blue = ramp(0.15 + r * 0.4, u);
  float3 orb = capPeak(blue * core * fuzz * (0.55 + k * 0.35), 0.48);
  float2 g = float2(p.x * 1.35 + 0.55, p.y * 0.9);
  float2 cell = fract(g * 14.0) - 0.5;
  float2 id = floor(g * 14.0);
  float h = hash21(id);
  float wing = smoothstep(0.18, 0.02, abs(p.x)) * smoothstep(0.72, 0.28, abs(p.y));
  float dt = exp(-dot(cell, cell) * 180.0) * wing * step(0.35, h);
  float3 red = mix(u.color1.rgb, u.color2.rgb, h);
  return capPeak(orb + red * dt * (0.42 + k * 0.3), 0.46);
}

float3 emitNeonComet(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float turn = phraseTurn(u);
  float3 acc = float3(0.0);
  for (int i = 0; i < 6; i++) {
    float fi = float(i) / 6.0;
    float ang = fi * TAU + turn * 0.35 + sin(u.time * 0.2 + fi * 8.0) * 0.4;
    float2 dir = float2(cos(ang), sin(ang));
    float along = dot(p, dir);
    float across = length(p - dir * along);
    float head = exp(-pow((along - 0.22 - k * 0.06) / 0.018, 2.0));
    float tail = exp(-pow(across / 0.0035, 2.0)) * smoothstep(0.42, -0.05, along);
    acc += ramp(fi + u.music.x * 0.2, u) * (head * 0.35 + tail * 0.55);
  }
  return capPeak(acc, 0.43);
}

float3 emitPulseRings(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float r = length(p);
  float travel = (u.music.z > 0.5) ? u.beat.z * 4.0 : u.time * 1.1;
  float ring = pow(0.5 + 0.5 * sin(r * u.wave.y * 2.4 - travel), 28.0);
  float ring2 = pow(0.5 + 0.5 * sin(r * u.wave.y * 3.6 - travel * 1.3 + 0.8), 32.0);
  float fade = smoothstep(0.92, 0.04, r);
  float3 col = ramp(r * 1.2 + u.music.x * 0.15, u);
  return capPeak(col * (ring + ring2 * 0.65) * fade * (0.5 + k * 0.45), 0.4);
}

float3 emitStarLattice(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float2 q = float2(p.x * 1.2 + 0.35, p.y * 0.75 + 0.1);
  float2 cell = fract(q * 10.0) - 0.5;
  float2 id = floor(q * 10.0);
  float persp = 1.0 / (0.35 + abs(q.y) * 1.4);
  float dt = exp(-dot(cell, cell) * (120.0 * persp));
  float3 col = ramp(hash21(id) + u.time * 0.02, u);
  float field = dt * smoothstep(1.05, 0.08, length(p));
  return capPeak(col * field * (0.48 + k * 0.4), 0.4);
}

float3 emitShockRings(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float mic = liveWeight(u);
  float bass = max(u.ear.y, u.link.z * 0.85) * mic;
  float r = length(p);
  float shock = pow(0.5 + 0.5 * sin(r * 18.0 - u.time * 2.4 - k * 2.5 - bass * 3.0), 26.0);
  float fade = smoothstep(0.88, 0.02, r);
  float3 col = ramp(0.1 + bass, u);
  return capPeak(col * shock * fade * (0.55 + k * 0.55), 0.42);
}

float3 emitWireWeb(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float turn = phraseTurn(u);
  float warp = sin(p.x * u.wave.y + turn) + sin(p.y * u.wave.y * 0.9 - turn * 0.7);
  float grid = pow(abs(sin(warp * 3.2)), 22.0);
  float diag = pow(abs(sin((p.x + p.y) * u.wave.y * 0.8 + u.time * 0.25)), 24.0);
  float3 col = ramp(0.35 + u.music.x * 0.25, u);
  return capPeak(col * (grid * 0.55 + diag * 0.35) * (0.45 + k * 0.4), 0.38);
}

float3 emitDeepMandala(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float turn = phraseTurn(u);
  float r = length(p);
  float a = atan2(p.y, p.x);
  float n = max(u.shape.x, 6.0);
  float slice = TAU / n;
  float aa = abs(safeMod(a + slice * 0.5, slice) - slice * 0.5);
  float spoke = exp(-pow((aa * max(r, 0.03)) / max(u.wave.z, 0.0025), 2.0));
  float lace = pow(0.5 + 0.5 * cos(a * n * 2.0 + r * 16.0 - turn), 18.0);
  float fade = smoothstep(0.9, 0.03, r);
  float3 col = ramp(a / TAU + r + turn * 0.05, u);
  return capPeak(col * (spoke * 0.65 + lace * 0.28) * fade * (0.5 + k * 0.45), 0.4);
}

float3 emitSpectrumHalo(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float mic = liveWeight(u);
  float r = length(p);
  float targetR = u.shape.y + u.ear.y * mic * 0.06 + k * 0.02;
  float rim = exp(-pow((r - targetR) / 0.008, 2.0));
  float ang = atan2(p.y, p.x);
  int bins = int(clamp(u.shape.x, 12.0, 32.0));
  float slice = TAU / float(bins);
  int idx = int(floor(safeMod(ang + PI, TAU) / slice));
  float fi = float(idx) / float(bins);
  float h = mic * mix(u.ear.y, u.ear.z, fi) + (1.0 - mic) * (0.12 + 0.08 * sin(u.time + fi * 9.0));
  float tick = exp(-pow(safeMod(ang + PI, slice) / (slice * 0.08), 2.0));
  float3 col = ramp(fi + h, u);
  return capPeak(col * rim * tick * (0.55 + k * 0.45), 0.44);
}

float3 emitFractalTunnel(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float d = downbeat(u);
  float turn = phraseTurn(u);
  float r = max(length(p), 0.002);
  float z = log(r);
  float ang = atan2(p.y, p.x);
  float travel = u.time * 0.65 + turn;
  float rings = pow(0.5 + 0.5 * sin(z * 9.0 - travel), 14.0);
  float ringsInner = pow(0.5 + 0.5 * sin(z * 18.0 - travel * 1.35 + 0.7), 18.0);
  float spokes = pow(0.5 + 0.5 * cos(ang * 8.0 + turn * 0.5), 12.0);
  float fade = smoothstep(0.95, 0.05, r);
  float mask = (rings * 0.72 + ringsInner * 0.42) * fade + spokes * exp(-r * 1.5) * 0.16;
  float3 col = ramp(z * 0.15 + ang / TAU + u.music.x * 0.2, u);
  return capPeak(col * mask * (0.55 + k * 0.35 + d * 0.18), 0.4);
}

float3 emitSpectrumBars(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float mic = liveWeight(u);
  int bars = int(clamp(u.shape.x, 8.0, 24.0));
  float barW = 1.55 / float(bars);
  float x = p.x + 0.78;
  if (x < 0.0 || x > 1.55) return float3(0.0);
  int idx = int(floor(x / barW));
  if (idx < 0 || idx >= bars) return float3(0.0);
  float fi = float(idx) / float(bars);
  float h = mic * mix(u.ear.y, u.ear.z, fi) + (1.0 - mic) * (0.1 + 0.07 * sin(u.time * 1.5 + fi * 8.0));
  h += u.link.z * mic * (1.0 - fi) * 0.55 + u.link.w * mic * 0.38;
  h += k * 0.2;
  h = clamp(h, 0.02, 0.52);
  float baseY = -0.58;
  float top = baseY + h;
  float cx = (float(idx) + 0.5) * barW;
  float inBar = step(baseY, p.y) * step(p.y, top) * step(abs(x - cx), barW * 0.42);
  float edge = smoothstep(barW * 0.45, barW * 0.32, abs(x - cx));
  float3 col = ramp(fi + u.time * 0.03 + micEnergy(u) * 0.2, u);
  float cap = exp(-pow((p.y - top) / 0.012, 2.0));
  return capPeak(col * (inBar * edge + cap * 0.28) * (0.65 + k * 0.35), 0.42);
}

float3 emitVortexPulse(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float d = downbeat(u);
  float turn = phraseTurn(u);
  float r = length(p);
  float ang = atan2(p.y, p.x);
  float twist = 3.1 + 0.55 * sin(turn) + u.link.w * liveWeight(u) * 0.35;
  float spiral = ang - log(max(r, 0.004)) * twist + u.time * 0.45;
  float arm = exp(-pow(sin(spiral * 4.0) / 0.10, 2.0));
  float armInner = exp(-pow(sin(spiral * 4.0 + 1.7) / 0.15, 2.0));
  float fade = smoothstep(0.88, 0.02, r);
  float core = exp(-pow(r / (0.028 + k * 0.01), 2.0));
  float3 col = ramp(0.1 + r * 0.7 + u.music.x * 0.3, u);
  return capPeak(col * ((arm * 0.62 + armInner * 0.22) * fade * (0.55 + k * 0.4) + core * (0.15 + d * 0.12)), 0.4);
}

float3 emitHueWheel(float2 p, constant FrameUniforms &u) {
  float r = length(p);
  float a = atan2(p.y, p.x);
  float n = max(u.shape.x, 3.0);
  float slice = TAU / n;
  float aa = abs(safeMod(a + slice * 0.5, slice) - slice * 0.5);
  float spoke = exp(-pow((aa * max(r, 0.04)) / max(u.wave.z, 0.003), 2.0));
  float rim = exp(-pow((r - u.shape.y) / 0.012, 2.0));
  float hub = exp(-pow(r / 0.05, 2.0));
  float glow = spoke * smoothstep(u.shape.y + 0.08, 0.0, r);
  float k = kick(u);
  float d = downbeat(u);
  float3 col = ramp(u.time * 0.07 + r * 0.5 + float(int(floor(safeMod(a + PI, TAU) / slice))), u);
  return capPeak(col * (glow * (0.45 + k * 0.4) + rim * (0.35 + d * 0.45) + hub * 0.08), 0.4);
}

float3 emitMode(float2 p, int mode, constant FrameUniforms &u) {
  if (mode == 0) return emitTunnelVision(p, u);
  if (mode == 1) return emitTealDust(p, u);
  if (mode == 2) return emitGreenRays(p, u);
  if (mode == 3) return emitOrbGrid(p, u);
  if (mode == 4) return emitWaveformGlow(p, u);
  if (mode == 5) return emitLiquidMirror(p, u);
  if (mode == 6) return emitPlasmaDrift(p, u);
  if (mode == 7) return emitSpectrumSpiral(p, u);
  if (mode == 8) return emitKaleidoBass(p, u);
  if (mode == 9) return emitFractalTunnel(p, u);
  if (mode == 10) return emitSpectrumBars(p, u);
  if (mode == 11) return emitVortexPulse(p, u);
  if (mode == 12) return emitHueWheel(p, u);
  if (mode == 13) return emitNeonComet(p, u);
  if (mode == 14) return emitPulseRings(p, u);
  if (mode == 15) return emitStarLattice(p, u);
  if (mode == 16) return emitShockRings(p, u);
  if (mode == 17) return emitWireWeb(p, u);
  if (mode == 18) return emitDeepMandala(p, u);
  if (mode == 19) return emitSpectrumHalo(p, u);
  return emitPlasmaDrift(p, u);
}


fragment float4 warpFragment(
    Varyings in [[stage_in]],
    constant FrameUniforms &u [[buffer(0)]],
    texture2d<float> prevTex [[texture(0)]]
) {
    constexpr sampler samp(filter::linear, address::clamp_to_zero);
    float2 p0 = toP(in.uv, u);
    float spin = u.time * u.flow.w;
    float2 spun = rot2(p0, -spin);
    float2 folded = foldKaleido(spun, u.center.z, u.center.w);
    float2 representative = rot2(folded, spin);
    float2 srcP = advect(representative, u);
    float2 src = toUV(srcP, u);

    float3 col = blurAt(src, u.persist.y, prevTex, samp, u);
    float2 motion = src - in.uv;
    float motionLen = length(motion);
    float2 motionDir = motionLen > 1e-5 ? motion / motionLen : float2(1.0, 0.0);
    float ca = u.persist.w / max(u.resolution.y, 1.0);
    col.r = mix(col.r, samplePrev(src + motionDir * ca, prevTex, samp).r, 0.7);
    col.b = mix(col.b, samplePrev(src - motionDir * ca, prevTex, samp).b, 0.7);

    // Preset switch: start from a dimmed copy so the old picture is not added
    // to the new one. Two frames cover a dropped ping-pong write.
    if (u.music.w > 0.01) {
        col *= u.music.w;
    }

    float center = smoothstep(0.78, 0.06, length(p0));
    // Linear-space trail decay (~0.90–0.96 retained per 60 Hz frame). persist.x
    // is seconds-to-half-ish; map preset decayTau into that band.
    float frameKeep = mix(0.90, 0.96, clamp(u.persist.x * 0.85, 0.0, 1.0));
    float keep = pow(frameKeep, u.deltaTime * 60.0);
    col *= keep;
    float hue = clamp(u.persist.z * u.deltaTime + downbeat(u) * 0.02 * (1.0 - liveWeight(u)) + u.ear.z * liveWeight(u) * 0.03, 0.0, 0.12);
    col = mix(col, col.gbr, hue);

    float r = length(p0);
    float holeMask = 1.0 - smoothstep(0.0, max(u.hole.x, 0.001), r);
    col *= exp(-u.deltaTime * u.hole.y * holeMask * 3.0);

    float w = smoothstep(0.0, 1.0, u.tempo.w);
    int modeA = int(u.tempo.y + 0.5);
    int modeB = int(u.tempo.z + 0.5);
    float3 emittedA = emitMode(spun, modeA, u);
    float3 emittedB = emitMode(spun, modeB, u);
    float3 e = mix(emittedA, emittedB, w);
    float mic = liveWeight(u);
    float hit = max(u.ear.x, u.link.y * 0.45);
    float clockBoost = pulseAmt(u) * 0.35 + downbeat(u) * 0.08;
    float micBoost = min(hit, 1.2) * 0.45 + min(u.ear.w, 1.2) * 0.15;
    float react = min(mix(clockBoost, micBoost, mic), 0.65);
    e *= u.style.z * (0.55 + react);
    float stamp = u.shape.w * (0.42 + react * 0.25);
    float lumaNow = luma3(col);
    float room = 1.0 / (1.0 + max(lumaNow - 0.22, 0.0) * (2.2 + center * 1.8));
    stamp *= room * mix(1.0, 0.35, center * smoothstep(0.28, 0.85, lumaNow));
    float3 layer = capPeak(e * stamp, 0.55);
    col = max(col, layer);
    col = capLuma(col, 0.75);
    return float4(col, 1.0);
}

fragment float4 presentFragment(
    Varyings in [[stage_in]],
    constant FrameUniforms &u [[buffer(0)]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> meanLuma [[texture(1)]]
) {
    constexpr sampler samp(filter::linear, address::clamp_to_edge);
    // Display zoom around the center. The feedback warp is unchanged, so this
    // does not ratchet. Outside the picture fades to black instead of sampling
    // past the texture.
    float zoom = u.wave.x;
    if (zoom < 0.5 || zoom > 2.0) zoom = 1.0;
    float2 zuv = (in.uv - 0.5) / zoom + 0.5;
    float2 lo = smoothstep(float2(-0.012), float2(0.0), zuv);
    float2 hi = float2(1.0) - smoothstep(float2(1.0), float2(1.012), zuv);
    float3 c = source.sample(samp, clamp(zuv, float2(0.0), float2(1.0))).rgb;
    c *= lo.x * lo.y * hi.x * hi.y;
    float satAmt = clamp(u.grade.z, 0.8, 1.6);
    c = boostSat(c, satAmt);
    float v = length((in.uv - 0.5) * float2(1.15, 1.35));
    c *= mix(1.0, smoothstep(0.95, 0.22, v), clamp(u.grade.w, 0.0, 1.0));
    // Gain never above 1.0. grade.x carries CPU-smoothed frame gain-down only.
    float mean = meanLuma.sample(samp, float2(0.5)).r;
    float presetGain = min(max(u.style.x, 0.0), 1.0);
    float frameCap = min(max(u.grade.x, 0.0), 1.0);
    float instant = presetGain * frameCap;
    if (mean > 1e-4) {
        float down = min(1.0, 0.25 / mean);
        instant = min(instant, down);
    }
    c *= instant;
    c = capPeak(c, 0.92);
    // bgra8Unorm drawable: linear in, display gamma once — no extra pow(1/2.2).
    return float4(clamp(c, 0.0, 1.0), 1.0);
}

/// One pixel: mean luminance of a coarse grid. The present pass reads it
/// in the same command buffer, after this write.
fragment float4 reduceLumaFragment(
    Varyings in [[stage_in]],
    texture2d<float> source [[texture(0)]]
) {
    constexpr sampler samp(filter::linear, address::clamp_to_edge);
    float acc = 0.0;
    for (int y = 0; y < 12; ++y) {
        for (int x = 0; x < 16; ++x) {
            float2 uv = (float2(float(x), float(y)) + 0.5) / float2(16.0, 12.0);
            float3 sampleColor = max(source.sample(samp, uv).rgb, float3(0.0));
            acc += dot(sampleColor, float3(0.2126, 0.7152, 0.0722));
        }
    }
    return float4(acc / 192.0, 0.0, 0.0, 1.0);
}
