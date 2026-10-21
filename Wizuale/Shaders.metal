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
    float4 wave;     // edge (unused), frequency, thickness, radiusOffset
    float4 shape;    // count, radius, softness, intensity
    float4 grade;    // sparkle, contrast (unused), saturation, vignette
    float4 style;    // exposure, baseLevel, emissionGain, pulseAmount
    float4 tempo;    // bpm, modeFrom, modeTo, modeT
    float4 hole;     // centerHole, centerDark, grain, unused
    float4 beat;     // kick, downbeat, beatPhase, barPhase  (0 when no matched tempo)
    float4 music;    // phrasePhase, beatsPerBar, realTempo (1 = matched), unused
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
  float drive = 1.0 + loud * mic * 0.85;
  // Onset carries the kick. Flux only fills in if the onset gate missed it.
  float hit = max(u.ear.x, u.link.y * 0.45);
  a += (u.flow.y + (body * 1.35 + hit * 0.45) * mic) * dt * drive;
  a += u.flow.z * dt * drive / (r + 0.28);
  float warpAmt = u.warp.x + (body * 0.95 + hit * 0.62) * mic;
  a += sin(r * u.warp.y - u.time * u.warp.z * drive) * warpAmt * dt * drive;
  // `punch` is a zoom rate, multiplied by dt below. It integrates for the
  // length of the hit and then stops, so the frame slams forward and settles.
  // The mic hit replaces the clock while the phone is live, so the two don't stack.
  float clockZoom = clockEnvelope(u) * 2.2;
  float micZoom = hit * 4.0 + body * 0.36;
  float punch = mix(clockZoom, micZoom, mic);
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
  float3 c = samplePrev(uv, prevTex, samp) * 0.40;
  c += samplePrev(uv + float2(t.x, 0.0), prevTex, samp) * 0.15;
  c += samplePrev(uv - float2(t.x, 0.0), prevTex, samp) * 0.15;
  c += samplePrev(uv + float2(0.0, t.y), prevTex, samp) * 0.15;
  c += samplePrev(uv - float2(0.0, t.y), prevTex, samp) * 0.15;
  return c;
}

float3 emitSpiral(float2 p, constant FrameUniforms &u) {
  float r = length(p);
  float a = atan2(p.y, p.x);
  float n = max(u.shape.x, 1.0);
  float k = kick(u);
  float d = downbeat(u);
  float arm = pow(max(cos(a * n * 0.5), 0.0), 6.0);
  float phase = a * n - log(max(r, 0.004)) * u.wave.y + u.time * 0.55 + k * 0.55;
  float ridge = exp(-pow(sin(phase) / 0.10, 2.0));
  float strand = exp(-pow(sin(a * n * 2.0 + r * 22.0 - u.time * 0.4) / 0.07, 2.0));
  float core = exp(-pow(r / 0.02, 2.0));
  float halo = exp(-pow((r - 0.20) / (0.028 + k * 0.05), 2.0)) * k;
  float3 col = ramp(0.02 + r * 1.7 + d * 0.08, u);
  float body = ridge * arm * 0.85 + strand * arm * 0.45 + core * 0.55 + halo * 0.5;
  return col * body * (1.0 + k * 0.75 + d * 0.35);
}

float3 emitPetals(float2 p, constant FrameUniforms &u) {
  float r = length(p);
  float a = atan2(p.y, p.x);
  float n = max(u.shape.x, 1.0);
  float k = kick(u);
  float d = downbeat(u);
  float petal = pow(max(0.0, cos(a * n)), max(u.shape.z, 0.5));
  float breathe = 0.02 * sin(u.time * 0.7 + a * 2.0);
  float radius = u.shape.y + u.wave.w + petal * 0.20 + breathe + k * 0.02;
  float thick = max(u.wave.z, 0.0025);
  float contour = exp(-pow((r - radius) / thick, 2.0));
  float body = exp(-pow((r - radius) / (thick * 9.0), 2.0)) * (0.25 + 0.75 * petal);
  float inner = exp(-pow((r - radius * 0.55) / 0.05, 2.0)) * petal;
  float core = exp(-pow(r / 0.07, 2.0));
  float3 col = ramp(petal * 0.65 + r * 0.4 + u.time * 0.02, u);
  float3 lineCol = mix(u.color1.rgb, float3(1.0, 0.96, 0.45), 0.62);
  return (col * body * 0.16 + lineCol * contour * 1.45 * (1.0 + k * 0.9) + col * inner * 0.22 + col * core * 0.2) * (1.0 + d * 0.25);
}

float3 emitEmber(float2 p, constant FrameUniforms &u) {
  float r = length(p);
  float a = atan2(p.y, p.x);
  float k = kick(u);
  float d = downbeat(u);
  float lobe = 0.5 + 0.5 * sin(a * max(u.shape.x, 2.0) + u.time * 0.45);
  float wob = 0.05 * sin(a * u.wave.y - u.time * 0.8) + 0.025 * sin(a * u.wave.y * 2.3 + u.time * 1.3);
  float radius = u.shape.y + wob + lobe * 0.045 + u.wave.w + k * 0.03;
  float thick = max(u.wave.z, 0.006);
  float ring = exp(-pow((r - radius) / thick, 2.0));
  float glow = exp(-pow((r - u.shape.y) / (thick * 6.5), 2.0)) * (0.28 + 0.85 * lobe);
  float core = exp(-pow(r / 0.09, 2.0)) * 0.22;
  float2 cell = floor(p * 78.0);
  float2 f = fract(p * 78.0) - 0.5;
  float h = hash21(cell + floor(u.time * 6.0));
  float spark = step(0.972 - d * 0.045, h) * exp(-dot(f, f) * 16.0);
  spark *= smoothstep(0.55, 0.12, abs(r - u.shape.y));
  float3 col = mix(u.color0.rgb, u.color1.rgb, lobe);
  col = mix(col, u.color2.rgb, smoothstep(0.12, 0.42, r));
  float3 body = col * (ring * 0.7 * (1.0 + k * 0.8) + glow * 0.22 * (1.0 + k * 0.55) + core);
  return (body + float3(1.0, 0.92, 0.75) * spark * (0.35 + u.grade.x)) * (1.0 + d * 0.15);
}

float3 emitTunnel(float2 p, constant FrameUniforms &u) {
  float r = length(p);
  float a = atan2(p.y, p.x);
  float n = max(u.shape.x, 1.0);
  float k = kick(u);
  float d = downbeat(u);
  // One ring cycle per beat when the tempo is real. sin(phase * TAU) wraps cleanly.
  float travel = (u.music.z > 0.5) ? (u.beat.z * TAU) : (u.time * 1.4);
  float rings = pow(0.5 + 0.5 * sin(log(max(r, 0.002)) * u.wave.y - travel), 10.0);
  float beams = pow(0.5 + 0.5 * cos(a * n), max(u.shape.z, 0.6));
  float streak = pow(0.5 + 0.5 * cos(a * n * 0.5 - r * 8.0 + u.time * 0.6), 18.0);
  float fade = smoothstep(0.85, 0.05, r);
  float3 col = ramp(r * 1.4 + u.time * 0.05 + a * 0.05, u);
  float m = (rings * 0.85 + streak * 0.95) * fade + beams * exp(-r * 2.2) * 0.22;
  m += exp(-pow(r / 0.02, 2.0)) * 0.45;
  return col * m * (1.0 + k * 0.55 + d * 0.3);
}

float3 emitSilk(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float sway = (u.music.z > 0.5) ? sin(u.beat.z * TAU) * 0.018 : 0.0;
  float wob = sin(p.x * u.wave.y + u.time * 0.32) * 0.10;
  float wob2 = sin(p.x * u.wave.y * 0.62 - u.time * 0.21 + 1.7) * 0.14;
  float wob3 = sin(p.x * u.wave.y * 1.3 + u.time * 0.17) * 0.05;
  float b1 = exp(-pow((p.y - wob - sway) / 0.055, 2.0));
  float b2 = exp(-pow((p.y - 0.20 - wob2 - sway * 0.6) / 0.08, 2.0));
  float b3 = exp(-pow((p.y + 0.16 - wob3 + sway * 0.4) / 0.045, 2.0));
  float sheen = pow(0.5 + 0.5 * sin(p.x * 3.0 - p.y * 8.0 + u.time * 0.4), 6.0);
  float3 col = ramp(0.25 + p.y * 0.8 + u.time * 0.03, u);
  return col * (b1 * 0.42 + b2 * 0.28 + b3 * 0.34) * (0.8 + sheen * 0.35) * (1.0 + k * 0.5);
}

float3 emitWheel(float2 p, constant FrameUniforms &u) {
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
  return col * (glow * (0.7 + k * 0.65) + rim * (0.55 + d * 0.85) + hub * (0.35 + k * 0.3));
}

float3 emitAurora(float2 p, constant FrameUniforms &u) {
  float y1 = sin(p.x * u.wave.y + u.time * 0.18) * 0.10 + sin(p.x * 2.0 - u.time * 0.11) * 0.05;
  float y2 = 0.16 + sin(p.x * u.wave.y * 0.7 - u.time * 0.14 + 1.2) * 0.08;
  float y3 = -0.14 + sin(p.x * 1.6 + u.time * 0.09) * 0.07;
  float b1 = exp(-pow((p.y - y1) / 0.16, 2.0));
  float b2 = exp(-pow((p.y - y2) / 0.11, 2.0));
  float b3 = exp(-pow((p.y - y3) / 0.13, 2.0));
  float k = kick(u);
  float d = downbeat(u);
  float3 c1 = u.color0.rgb * b1;
  float3 c2 = u.color1.rgb * b2;
  float3 c3 = u.color2.rgb * b3;
  return (c1 * 0.32 + c2 * 0.24 + c3 * 0.28) * (1.0 + k * 0.6 + d * 0.25);
}

float3 emitBloom(float2 p, constant FrameUniforms &u) {
  float3 acc = float3(0.0);
  for (int i = 0; i < 5; i++) {
    float fi = float(i);
    float2 c = float2(
      sin(u.time * (0.13 + fi * 0.017) + fi * 1.7) * (0.28 + fi * 0.04),
      cos(u.time * (0.11 + fi * 0.02) + fi * 2.2) * (0.16 + fi * 0.03)
    );
    float rad = (0.10 + 0.035 * sin(u.time * 0.4 + fi)) * (1.0 + kick(u) * 0.28);
    float blob = exp(-dot(p - c, p - c) / max(rad * rad, 0.004));
    acc += ramp(fi * 0.17 + u.time * 0.02, u) * blob;
  }
  return acc * 0.34 * (1.0 + kick(u) * 0.5 + downbeat(u) * 0.2);
}

float3 emitBorder(float2 p, constant FrameUniforms &u) {
  float a = atan2(p.y, p.x);
  float k = kick(u);
  float d = downbeat(u);
  float wobble = 0.035 * sin(a * u.wave.y + u.time * 0.55) + 0.018 * sin(a * u.wave.y * 2.2 - u.time * 0.4);
  float2 scale = float2(0.78, 0.42) * (1.0 + wobble) * (1.0 + k * 0.045);
  float er = length(p / scale);
  float thick = 0.045;
  float line = exp(-pow((er - 1.0) / thick, 2.0));
  float glow = exp(-pow((er - 1.0) / (thick * 3.2), 2.0));
  float rim = smoothstep(0.72, 0.98, er);
  float3 col = ramp(a / TAU + u.time * 0.04 + er * 0.15, u);
  return col * (line * (1.05 + k * 0.75) + glow * (0.32 + d * 0.4)) * rim;
}

float3 emitDrift(float2 p, constant FrameUniforms &u) {
  float3 acc = float3(0.0);
  float scale = max(u.wave.y, 2.0);
  float2 gp = p * scale;
  float2 id = floor(gp);
  float2 f = fract(gp) - 0.5;
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      float2 cell = id + float2(float(i), float(j));
      float h = hash21(cell);
      if (h < 0.78) continue;
      float2 motion = float2(
        sin(u.time * 0.15 + h * TAU),
        cos(u.time * 0.12 + h * 11.0)
      ) * 0.32;
      float2 d = f - float2(float(i), float(j)) - motion;
      float star = exp(-dot(d, d) * 28.0);
      acc += ramp(h, u) * star * (0.55 + 0.45 * sin(u.time * 0.8 + h * 20.0) + kick(u) * 0.85);
    }
  }
  float dust = exp(-pow(length(p) / 0.55, 2.0));
  return acc * (0.35 + dust);
}

// Oscilloscope rose plus a ribbon. Feedback rotation turns them into a spirograph.
float3 emitScope(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float d = downbeat(u);
  float turn = phraseTurn(u);
  float r = length(p);
  float ang = atan2(p.y, p.x);
  float lobes = 5.0 + 2.0 * sin(turn);
  float radius = 0.30 + 0.10 * sin(ang * lobes + u.time * 0.85) + k * 0.028;
  float rose = exp(-pow((r - radius) / 0.0075, 2.0));
  float ribbonY = sin(p.x * (7.0 + 1.5 * sin(turn)) + u.time * 1.1) * (0.11 + k * 0.035);
  float ribbon = exp(-pow((p.y - ribbonY) / 0.008, 2.0));
  float3 col = ramp(0.08 + ang / TAU + u.music.x * 0.2, u);
  float3 line = mix(col, u.color1.rgb, 0.35);
  return line * rose * (0.95 + d * 0.45) + col * ribbon * 0.55 * (1.0 + k * 0.35);
}

// One motif, mirrored on both axes. The preset's kaleidoscope repeats it again.
float3 emitMirror(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float d = downbeat(u);
  float turn = phraseTurn(u);
  float2 q = float2(abs(p.x), abs(p.y));
  float arc = exp(-pow((length(q - float2(0.20, 0.06)) - 0.14) / 0.007, 2.0));
  float spoke = exp(-pow((q.y - 0.02 * sin(q.x * 10.0 + turn)) / 0.006, 2.0));
  spoke *= smoothstep(0.62, 0.04, q.x);
  float gem = exp(-pow(length(q - float2(0.12, 0.28)) / (0.02 + k * 0.012), 2.0));
  float3 col = ramp(q.x + q.y + u.music.x * 0.35, u);
  return col * (arc * (1.05 + k * 0.6) + spoke * 0.7 + gem * (0.45 + d * 0.5));
}

// Contours of a plasma field. The field itself is not filled, so trails stay thin.
float3 emitPlasma(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float d = downbeat(u);
  float turn = phraseTurn(u);
  float field = sin(p.x * 5.4 + turn) + sin(p.y * 4.5 - u.time * 0.32) + sin((p.x + p.y) * 3.3 + turn * 0.45);
  float ridge = pow(abs(sin(field * 2.15)), 16.0);
  float3 col = ramp(0.5 + 0.5 * sin(field * 0.5) + u.music.x * 0.25, u);
  return col * ridge * (0.85 + k * 0.55 + d * 0.28);
}

float3 emitWarpStars(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float d = downbeat(u);
  float turn = phraseTurn(u);
  float3 acc = float3(0.0);
  float2 gp = p * 13.0;
  float2 cellId = floor(gp);
  float2 cellFract = fract(gp) - 0.5;
  for (int gy = -1; gy <= 1; gy++) {
    for (int gx = -1; gx <= 1; gx++) {
      float2 cell = cellId + float2(float(gx), float(gy));
      float h = hash21(cell);
      if (h < 0.52) continue;
      float twinkle = 0.45 + 0.55 * sin(u.time * (0.55 + h) + turn + h * 19.0);
      float2 glide = 0.18 * float2(sin(u.time * 0.09 + h * 6.2), cos(u.time * 0.07 + h * 3.7));
      float2 delta = cellFract - float2(float(gx), float(gy)) - glide;
      float star = exp(-dot(delta, delta) * 42.0);
      acc += ramp(h + u.music.x * 0.22, u) * star * twinkle * (0.7 + k * 0.85 + d * 0.35);
    }
  }
  return acc * smoothstep(1.05, 0.12, length(p));
}

// Two octaves of log-radius rings, so zooming reads as a nested well.
float3 emitWell(float2 p, constant FrameUniforms &u) {
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
  return col * mask * (1.0 + k * 0.5 + d * 0.28);
}

// Soft blobs. A long decay and a slow spin smear them into color bleeds.
float3 emitBleed(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float d = downbeat(u);
  float turn = phraseTurn(u);
  float3 acc = float3(0.0);
  for (int band = 0; band < 3; band++) {
    float fi = float(band);
    float ang = turn * 0.35 + fi * 2.094 + u.time * 0.11;
    float2 origin = 0.20 * float2(cos(ang), sin(ang * 0.85));
    float rad = 0.15 + 0.035 * sin(u.time * 0.28 + fi + turn) + k * 0.03;
    float blob = exp(-dot(p - origin, p - origin) / max(rad * rad, 0.008));
    acc += ramp(fi * 0.33 + u.music.x * 0.4, u) * blob;
  }
  return acc * (0.26 + d * 0.07);
}

float3 emitVortex(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float d = downbeat(u);
  float turn = phraseTurn(u);
  float r = length(p);
  float ang = atan2(p.y, p.x);
  float twist = 3.1 + 0.55 * sin(turn);
  float spiral = ang - log(max(r, 0.004)) * twist + u.time * 0.45;
  float arm = exp(-pow(sin(spiral * 4.0) / 0.10, 2.0));
  float armInner = exp(-pow(sin(spiral * 4.0 + 1.7) / 0.15, 2.0));
  float fade = smoothstep(0.88, 0.02, r);
  float core = exp(-pow(r / (0.028 + k * 0.01), 2.0));
  float3 col = ramp(0.1 + r * 0.7 + u.music.x * 0.3, u);
  return col * ((arm * 0.82 + armInner * 0.32) * fade * (1.0 + k * 0.55) + core * (0.4 + d * 0.35));
}

float3 emitMesh(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float d = downbeat(u);
  float turn = phraseTurn(u);
  float2 warped = p;
  warped.x += sin(p.y * 7.0 + turn) * (0.04 + k * 0.02);
  warped.y += sin(p.x * 6.0 - u.time * 0.35) * (0.032 + d * 0.014);
  float vertical = pow(abs(sin(warped.x * 16.0)), 26.0);
  float horizontal = pow(abs(sin(warped.y * 12.0)), 26.0);
  float grid = max(vertical, horizontal);
  float3 col = ramp(0.2 + p.x * 0.25 + u.music.x * 0.3, u);
  return col * grid * (0.82 + k * 0.45);
}

float3 emitWater(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float d = downbeat(u);
  float turn = phraseTurn(u);
  float2 origin = 0.11 * float2(sin(turn), cos(turn * 0.8));
  float r = length(p - origin);
  float inner = pow(0.5 + 0.5 * sin(r * 26.0 - u.time * 1.7 + turn), 20.0);
  float outer = pow(0.5 + 0.5 * sin(r * 15.0 - u.time * 1.1 + 1.1), 18.0);
  float fade = smoothstep(0.98, 0.06, r);
  float3 col = ramp(0.35 + r * 0.55 + u.music.x * 0.2, u);
  return col * (inner * 0.9 + outer * 0.4) * fade * (1.0 + k * 0.6 + d * 0.25);
}

float3 emitFlame(float2 p, constant FrameUniforms &u) {
  float k = kick(u);
  float d = downbeat(u);
  float turn = phraseTurn(u);
  float3 acc = float3(0.0);
  for (int band = 0; band < 4; band++) {
    float fi = float(band);
    float sway = sin(p.y * (3.2 + fi * 0.4) - u.time * (0.55 + fi * 0.08) + turn) * (0.055 + k * 0.02);
    float x = p.x - (fi - 1.5) * 0.15 - sway;
    float width = 0.04 + 0.02 * sin(u.time * 0.45 + fi + turn) + k * 0.012;
    float tongue = exp(-pow(x / max(width, 0.012), 2.0));
    float rise = smoothstep(-0.48, 0.02, p.y) * smoothstep(0.58, -0.02, p.y);
    float3 col = mix(u.color0.rgb, u.color1.rgb, smoothstep(-0.25, 0.28, p.y));
    col = mix(col, u.color2.rgb, smoothstep(0.12, 0.5, p.y));
    acc += col * tongue * rise * (0.5 + d * 0.22);
  }
  float wick = exp(-pow(p.x / 0.028, 2.0)) * exp(-pow((p.y + 0.38) / 0.07, 2.0));
  acc += u.color2.rgb * wick * (0.4 + k * 0.45);
  return acc * 0.48;
}

// Mode numbers match VisualMode in Presets.swift:
// 0 spiral, 1 petals, 2 ember, 3 tunnel, 4 silk, 5 wheel, 6 aurora, 7 bloom, 8 border, 9 drift,
// 10 scope, 11 mirror, 12 plasma, 13 warp stars, 14 fractal well, 15 color bleed,
// 16 vortex, 17 mesh, 18 water, 19 flame.
float3 emitMode(float2 p, int mode, constant FrameUniforms &u) {
  if (mode == 0) return emitSpiral(p, u);
  if (mode == 1) return emitPetals(p, u);
  if (mode == 2) return emitEmber(p, u);
  if (mode == 3) return emitTunnel(p, u);
  if (mode == 4) return emitSilk(p, u);
  if (mode == 5) return emitWheel(p, u);
  if (mode == 6) return emitAurora(p, u);
  if (mode == 7) return emitBloom(p, u);
  if (mode == 8) return emitBorder(p, u);
  if (mode == 9) return emitDrift(p, u);
  if (mode == 10) return emitScope(p, u);
  if (mode == 11) return emitMirror(p, u);
  if (mode == 12) return emitPlasma(p, u);
  if (mode == 13) return emitWarpStars(p, u);
  if (mode == 14) return emitWell(p, u);
  if (mode == 15) return emitBleed(p, u);
  if (mode == 16) return emitVortex(p, u);
  if (mode == 17) return emitMesh(p, u);
  if (mode == 18) return emitWater(p, u);
  if (mode == 19) return emitFlame(p, u);
  return emitDrift(p, u);
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

    float keep = exp(-u.deltaTime / max(u.persist.x, 0.05));
    col *= keep;
    col = max(col - float3(0.00065) * (u.deltaTime * 60.0), float3(0.0));
    float mic = liveWeight(u);
    float hit = max(u.ear.x, u.link.y * 0.45);
    // A short lift of the history on a hit. It fades with the picture, so it cannot run away.
    col *= 1.0 + mix(clockEnvelope(u) * 0.10, hit * 0.30, mic);
    float hue = clamp(u.persist.z * u.deltaTime + downbeat(u) * 0.03 * (1.0 - mic) + u.ear.z * mic * 0.055, 0.0, 0.10);
    col = mix(col, col.gbr, hue);

    float r = length(p0);
    float holeMask = 1.0 - smoothstep(0.0, max(u.hole.x, 0.001), r);
    col *= exp(-u.deltaTime * u.hole.y * holeMask * 3.0);

    float n = hash21(in.position.xy + fract(u.time * 17.13)) - 0.5;
    col += n * u.hole.z;
    float high = u.ear.z * mic;
    float glitter = hash21(floor(in.position.xy * 0.35) + floor(u.time * 11.0));
    float specks = step(0.988, glitter) * high;
    col += specks * ramp(glitter + u.ear.y, u) * 0.65;

    float w = smoothstep(0.0, 1.0, u.tempo.w);
    int modeA = int(u.tempo.y + 0.5);
    int modeB = int(u.tempo.z + 0.5);
    float3 e = emitMode(spun, modeA, u);
    if (modeA != modeB) {
        e = mix(e, emitMode(spun, modeB, u), w);
    }
    float clockBoost = pulseAmt(u) * 0.85 + downbeat(u) * 0.2;
    float micBoost = hit * 1.65 + u.ear.w * 0.55 + u.link.w * 0.35 + high * 0.35;
    e *= u.style.z * (1.0 + mix(clockBoost, micBoost, mic));
    col += max(e, float3(0.0)) * u.shape.w;
    col += u.baseColor.rgb * u.style.y * u.deltaTime;
    col = clamp(col, float3(0.0), float3(4.0));
    return float4(col, 1.0);
}

fragment float4 presentFragment(
    Varyings in [[stage_in]],
    constant FrameUniforms &u [[buffer(0)]],
    texture2d<float> source [[texture(0)]]
) {
    constexpr sampler samp(filter::linear, address::clamp_to_edge);
    float3 c = source.sample(samp, in.uv).rgb;
    float luma = dot(c, float3(0.2126, 0.7152, 0.0722));
    c = max(mix(float3(luma), c, max(u.grade.z, 0.0)), float3(0.0));
    float v = length((in.uv - 0.5) * float2(1.15, 1.35));
    c *= mix(1.0, smoothstep(0.95, 0.22, v), clamp(u.grade.w, 0.0, 1.0));
    // Whole-frame lift. The stroke-only pulse was too small to read from a couch.
    float mic = liveWeight(u);
    float hit = max(u.ear.x, u.link.y * 0.45);
    float body = max(u.ear.y, u.link.z * 0.85);
    float flash = mix(clockEnvelope(u) * 0.36, hit * 0.88 + body * 0.34, mic);
    c *= u.style.x * (1.0 + flash);
    c = pow(max(c, float3(0.0)), float3(1.25));
    c = c / (1.0 + c);
    c = pow(clamp(c, 0.0, 1.0), float3(1.0 / 2.2));
    float n = hash21(in.position.xy + fract(u.time * 9.0)) - 0.5;
    c += n / 255.0;
    return float4(c, 1.0);
}
