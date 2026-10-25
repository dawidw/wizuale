#!/usr/bin/env python3
"""Generate missing Study of Space MilkDrop presets (motifs from studyofspace/poster-bg)."""
from __future__ import annotations

import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "Wizuale/Resources/Presets/files"

HEADER = """MILKDROP_PRESET_VERSION=201
PSVERSION=2
PSVERSION_WARP=2
PSVERSION_COMP=2
[preset00]
fRating=5.000000
fGammaAdj=1.000
fDecay=1.000
fVideoEchoZoom=1.000
fVideoEchoAlpha=0.000
nVideoEchoOrientation=1
nWaveMode=0
bAdditiveWaves=0
bWaveDots=0
bWaveThick=0
bModWaveAlphaByVolume=0
bMaximizeWaveColor=0
bTexWrap=0
bDarkenCenter=0
bRedBlueStereo=0
bBrighten=0
bDarken=0
bSolarize=0
bInvert=0
fWaveAlpha=0.000
fWaveScale=0.010
fWaveSmoothing=0.750
fWaveParam=0.000
fModWaveAlphaStart=0.750
fModWaveAlphaEnd=0.950
fWarpAnimSpeed=1.000
fWarpScale=1.000
fZoomExponent=0.01000
fShader=0.000
zoom=1.00000
rot=0.00000
cx=0.500
cy=0.500
dx=0.00000
dy=0.00000
warp=0.00000
sx=1.00000
sy=1.00000
wave_r=0.000
wave_g=0.000
wave_b=0.000
wave_x=0.000
wave_y=0.000
ob_size=0.000
ob_r=0.000
ob_g=0.000
ob_b=0.000
ob_a=0.000
ib_size=0.000
ib_r=0.000
ib_g=0.000
ib_b=0.000
ib_a=0.000
nMotionVectorsX=12.000
nMotionVectorsY=9.000
mv_dx=0.000
mv_dy=0.000
mv_l=0.900
mv_r=1.000
mv_g=1.000
mv_b=1.000
mv_a=0.000
b1n=0.000
b2n=0.000
b3n=0.000
b1x=1.000
b2x=1.000
b3x=1.000
b1ed=0.250
wavecode_0_enabled=0
wavecode_0_samples=512
wavecode_0_sep=0
wavecode_0_bSpectrum=0
wavecode_0_bUseDots=0
wavecode_0_bDrawThick=0
per_frame_init_1=dir=1;
per_frame_init_2=lastb=0;
per_frame_init_3=pulse=0;
per_frame_init_4=acc=0;
per_frame_init_5=spin=0;
per_frame_init_6=bc=0;
per_frame_init_7=rnd=0.3;
per_frame_1=trig = above(bass, bass_att*1.12 + 0.04)*above(time - lastb, 0.22);
per_frame_2=trig = max(trig, below(bass+mid+treb, 0.15)*above(time - lastb, 0.55));
per_frame_3=lastb = if(trig, time, lastb);
per_frame_4=pulse = max(pulse*0.86, trig);
per_frame_5=bc = if(trig, bc + 1, bc);
per_frame_6=bc = if(above(bc, 63), 0, bc);
per_frame_7=rnd = if(trig, rand(1000)*0.001, rnd);
per_frame_8=dir = if(trig*below(rand(4),1), -dir, dir);
per_frame_9=fr = max(fps, 15);
per_frame_10=acc = acc + (0.5 + 1.3*min(bass_att,2) + 3*pulse)/fr;
per_frame_11=spin = spin + dir*(0.12 + 0.5*min(bass_att,2) + 1.5*pulse)/fr;
per_frame_12=q1 = min(bass, 2.5);
per_frame_13=q2 = min(mid, 2.5);
per_frame_14=q3 = min(treb, 2.5);
per_frame_15=q4 = pulse;
per_frame_16=q5 = acc;
per_frame_17=q6 = spin;
per_frame_18=q7 = bc;
per_frame_19=q8 = rnd;
per_frame_20=wave_a = 0;
"""

PER_FRAME_TAIL = {
    "default": "per_frame_21=zoom = 1.02 + 0.05*pulse;\nper_frame_22=rot = 0.02*dir;\n",
    "scroll": "per_frame_21=dy = 0.005*dir*(1.0 + q4);\nper_frame_22=zoom = 1.0 + 0.04*pulse;\n",
    "spin": "per_frame_21=zoom = 1.03 + 0.06*pulse;\nper_frame_22=rot = 0.04*dir + 0.05*pulse*dir;\n",
}

COMP = """comp_1=`shader_body
comp_2=`{
comp_3=`float2 u = uv;
comp_4=`
comp_5=`float2 off = (u - 0.5)*0.014*q4;
comp_6=`float3 c;
comp_7=`c.x = tex2D(sampler_main, u + off).x;
comp_8=`c.y = tex2D(sampler_main, u).y;
comp_9=`c.z = tex2D(sampler_main, u - off).z;
comp_10=`ret = saturate(c);
comp_11=`}
"""

WARPS: dict[str, list[str]] = {
    "mosaic": [
        "warp_1=`shader_body", "warp_2=`{", "warp_3=`float2 p = uv_orig - 0.5;",
        "warp_4=`p.x *= texsize.x*texsize.w;", "warp_7=`float3 fb = tex2D(sampler_main, uv).xyz;",
        "warp_8=`float3 col = float3(0.04,0.05,0.09);", "warp_9=`float m = 0.0;",
        "warp_10=`float2 g = p*11.0 + float2(q5*0.2, q5*0.15);",
        "warp_11=`float2 id = floor(g); float2 f = frac(g);",
        "warp_12=`float h = frac(sin(dot(id, float2(127.1,311.7)))*43758.5453);",
        "warp_13=`float flip = step(0.5, frac(h + q7*0.1));",
        "warp_14=`float2 uv2 = f; uv2.x = lerp(uv2.x, 1.0-uv2.x, flip);",
        "warp_15=`float3 c0 = float3(0.93,0.89,0.81); float3 c1 = float3(0.85,0.23,0.23);",
        "warp_16=`float3 c2 = float3(0.55,0.55,0.47);",
        "warp_17=`col = lerp(c0, c1, step(0.35, h)); col = lerp(col, c2, step(0.7, h));",
        "warp_18=`m = smoothstep(0.02, 0.12, min(uv2.x, uv2.y))*smoothstep(0.02, 0.12, min(1.0-uv2.x, 1.0-uv2.y));",
        "warp_19=`m *= 0.75 + 0.25*q4;", "warp_20=`ret = saturate(lerp(fb*0.93 - 0.004, col, saturate(m)));", "warp_21=`}",
    ],
    "blob": [
        "warp_1=`shader_body", "warp_2=`{", "warp_3=`float2 p = uv_orig - 0.5;",
        "warp_4=`p.x *= texsize.x*texsize.w;", "warp_7=`float3 fb = tex2D(sampler_main, uv).xyz;",
        "warp_8=`float3 col = float3(0.08,0.07,0.06);", "warp_9=`float m = 0.0;",
        "warp_10=`float2 c = float2(0.12*sin(q5*0.6), 0.08*cos(q5*0.8))*(1.0+q4);",
        "warp_11=`float d = length(p - c);", "warp_12=`float R = 0.32 + 0.08*q1;",
        "warp_13=`float halo = smoothstep(R+0.25, R, d);",
        "warp_14=`float3 ink = float3(0.76,0.45,0.31); float3 paper = float3(0.91,0.86,0.78);",
        "warp_15=`col = lerp(paper, ink, smoothstep(R, R-0.18, d));",
        "warp_16=`col = lerp(col, float3(0.95,0.55,0.35), halo*0.35);",
        "warp_17=`m = smoothstep(R+0.3, R-0.05, d);", "warp_18=`ret = saturate(lerp(fb*0.93 - 0.004, col, saturate(m)));", "warp_19=`}",
    ],
    "diagonals": [
        "warp_1=`shader_body", "warp_2=`{", "warp_3=`float2 p = uv_orig - 0.5;",
        "warp_4=`p.x *= texsize.x*texsize.w;", "warp_7=`float3 fb = tex2D(sampler_main, uv).xyz;",
        "warp_8=`float3 col = float3(0.95,0.93,0.86);", "warp_9=`float m = 0.0;",
        "warp_10=`float2 g = (p + float2(q5*0.03,0))*4.5;",
        "warp_11=`float2 id = floor(g); float2 f = frac(g);",
        "warp_12=`float tri = step(f.x, f.y);",
        "warp_13=`float3 red = float3(0.9,0.23,0.18); float3 blue = float3(0.11,0.31,0.62); float3 blk = float3(0.09,0.09,0.09);",
        "warp_14=`col = lerp(red, blue, tri); col = lerp(col, blk, step(0.85, frac(sin(dot(id, float2(12.9,78.2)))*43758.5)));",
        "warp_15=`m = 0.8;", "warp_16=`ret = saturate(lerp(fb*0.93 - 0.004, col, saturate(m)));", "warp_17=`}",
    ],
    "steps": [
        "warp_1=`shader_body", "warp_2=`{", "warp_3=`float2 p = uv_orig - 0.5;",
        "warp_4=`p.x *= texsize.x*texsize.w;", "warp_7=`float3 fb = tex2D(sampler_main, uv).xyz;",
        "warp_8=`float3 col = float3(0.05,0.06,0.12);", "warp_9=`float m = 0.0;",
        "warp_10=`float n = 5.0; float bw = 1.6/n; float x = p.x + 0.45;",
        "warp_11=`float k = floor(x/bw); float h = (k+1.0)/n;",
        "warp_12=`h *= 0.85 + 0.12*sin(q5*0.5 + k);",
        "warp_13=`float3 c0 = float3(0.93,0.36,0.24); float3 c1 = float3(0.17,0.17,0.26);",
        "warp_14=`col = lerp(c0, c1, step(h, p.y + 0.35));",
        "warp_15=`m = step(abs(frac(x/bw)-0.5), 0.48);", "warp_16=`ret = saturate(lerp(fb*0.93 - 0.004, col, saturate(m)));", "warp_17=`}",
    ],
    "construct": [
        "warp_1=`shader_body", "warp_2=`{", "warp_3=`float2 p = uv_orig - 0.5;",
        "warp_4=`p.x *= texsize.x*texsize.w;", "warp_7=`float3 fb = tex2D(sampler_main, uv).xyz;",
        "warp_8=`float3 col = float3(0.93,0.91,0.85);", "warp_9=`float m = 0.0;",
        "warp_10=`float2 r1 = abs(p - float2(-0.25,0.1))/float2(0.35,0.12);",
        "warp_11=`float2 r2 = abs(p - float2(0.2,-0.05))/float2(0.08,0.45);",
        "warp_12=`float a = max(r1.x,r1.y); float b = max(r2.x,r2.y);",
        "warp_13=`float3 red = float3(0.84,0.16,0.12); float3 blk = float3(0.07,0.07,0.07);",
        "warp_14=`col = lerp(col, red, step(a,1.0)); col = lerp(col, blk, step(b,1.0));",
        "warp_15=`m = max(step(a,1.0), step(b,1.0));", "warp_16=`ret = saturate(lerp(fb*0.93 - 0.004, col, saturate(m)));", "warp_17=`}",
    ],
    "cutout": [
        "warp_1=`shader_body", "warp_2=`{", "warp_3=`float2 p = uv_orig - 0.5;",
        "warp_4=`p.x *= texsize.x*texsize.w;", "warp_7=`float3 fb = tex2D(sampler_main, uv).xyz;",
        "warp_8=`float3 col = float3(0.91,0.87,0.78);", "warp_9=`float m = 0.0;",
        "warp_10=`float d = length(p*float2(1.0,1.3) - float2(0.05*sin(q5),0));",
        "warp_11=`float ang = atan2(p.y, p.x) + q6*0.2;",
        "warp_12=`float pet = 0.28 + 0.06*sin(ang*5.0);",
        "warp_13=`float3 ink = float3(0.1,0.1,0.1); float3 acc = float3(0.84,0.16,0.12);",
        "warp_14=`col = lerp(col, acc, smoothstep(pet+0.02, pet-0.02, d));",
        "warp_15=`col = lerp(col, ink, smoothstep(0.12, 0.08, abs(d-pet*0.5)));",
        "warp_16=`m = smoothstep(0.45, 0.2, d);", "warp_17=`ret = saturate(lerp(fb*0.93 - 0.004, col, saturate(m)));", "warp_18=`}",
    ],
    "jarema": [
        "warp_1=`shader_body", "warp_2=`{", "warp_3=`float2 p = uv_orig - 0.5;",
        "warp_4=`p.x *= texsize.x*texsize.w;", "warp_7=`float3 fb = tex2D(sampler_main, uv).xyz;",
        "warp_8=`float3 col = float3(0.96,0.91,0.84);", "warp_9=`float m = 0.0;",
        "warp_10=`float2 c0 = float2(sin(q5*0.4), cos(q5*0.5))*0.22;",
        "warp_11=`float2 c1 = float2(sin(q5*0.4+1.7), cos(q5*0.5+2.1))*0.28;",
        "warp_12=`float d0=length(p-c0); float d1=length(p-c1);",
        "warp_13=`col = lerp(col, float3(0.17,0.36,0.62), smoothstep(0.14,0.08,d0));",
        "warp_14=`col = lerp(col, float3(0.85,0.28,0.17), smoothstep(0.12,0.06,d1));",
        "warp_15=`m = max(smoothstep(0.16,0.1,d0), smoothstep(0.14,0.08,d1));",
        "warp_16=`ret = saturate(lerp(fb*0.93 - 0.004, col, saturate(m)));", "warp_17=`}",
    ],
    "relief": [
        "warp_1=`shader_body", "warp_2=`{", "warp_3=`float2 p = uv_orig - 0.5;",
        "warp_4=`p.x *= texsize.x*texsize.w;", "warp_7=`float3 fb = tex2D(sampler_main, uv).xyz;",
        "warp_8=`float3 col = float3(0.12,0.1,0.08);", "warp_9=`float m = 0.0;",
        "warp_10=`float bands = sin(p.y*18.0 + q5*0.3)*0.5+0.5;",
        "warp_11=`float3 wood1 = float3(0.91,0.85,0.66); float3 wood2 = float3(0.66,0.48,0.28);",
        "warp_12=`col = lerp(wood2, wood1, bands);",
        "warp_13=`float ridge = smoothstep(0.48,0.52, sin(p.x*8.0+q6));",
        "warp_14=`col = lerp(col, wood1*1.1, ridge*0.35);",
        "warp_15=`m = 0.85;", "warp_16=`ret = saturate(lerp(fb*0.93 - 0.004, col, saturate(m)));", "warp_17=`}",
    ],
    "weave": [
        "warp_1=`shader_body", "warp_2=`{", "warp_3=`float2 p = uv_orig - 0.5;",
        "warp_4=`p.x *= texsize.x*texsize.w;", "warp_7=`float3 fb = tex2D(sampler_main, uv).xyz;",
        "warp_8=`float3 col = float3(0.91,0.88,0.82);", "warp_9=`float m = 0.0;",
        "warp_10=`float2 g = p*14.0;", "warp_11=`float wx = step(0.5, frac(g.x + q5*0.1));",
        "warp_12=`float wy = step(0.5, frac(g.y));", "warp_13=`float over = wx*wy + (1.0-wx)*(1.0-wy);",
        "warp_14=`float3 a = float3(0.42,0.18,0.12); float3 b = float3(0.55,0.48,0.36);",
        "warp_15=`col = lerp(a, b, over);", "warp_16=`m = 0.8;", "warp_17=`ret = saturate(lerp(fb*0.93 - 0.004, col, saturate(m)));", "warp_18=`}",
    ],
}

PRESETS = [
    ("Study of Space - Mosaic.milk", "mosaic", "default"),
    ("Study of Space - Halo Blob.milk", "blob", "spin"),
    ("Study of Space - Triangles.milk", "diagonals", "default"),
    ("Study of Space - Steps.milk", "steps", "scroll"),
    ("Study of Space - Constructivist.milk", "construct", "default"),
    ("Study of Space - Paper Cutout.milk", "cutout", "spin"),
    ("Study of Space - Organic Rhythm.milk", "jarema", "spin"),
    ("Study of Space - Wooden Relief.milk", "relief", "scroll"),
    ("Study of Space - Woven Strips.milk", "weave", "default"),
]


def write_preset(name: str, warp_key: str, tail_key: str) -> None:
    lines = [HEADER, PER_FRAME_TAIL[tail_key]]
    lines.extend(WARPS[warp_key])
    lines.append(COMP)
    path = OUT / name
    path.write_text("\n".join(lines), encoding="utf-8")
    print("wrote", path.name)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for fname, warp, tail in PRESETS:
        write_preset(fname, warp, tail)


if __name__ == "__main__":
    main()
