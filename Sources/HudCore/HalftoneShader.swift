import Foundation

/// The halftone surface, ported 1:1 from MiniMate's AGSL scene renderer.
///
/// Kept as a source string rather than a `.metal` resource on purpose: Metal compiles this at
/// runtime via `makeLibrary(source:)`, which needs no `metal` CLI, so the macOS preview tool
/// builds and runs with Command Line Tools alone. CI, which has full Xcode, can precompile the
/// same text into a `.metallib` later without the text itself moving.
///
/// Structural differences from the AGSL original, all behaviour-preserving:
///   * AGSL's loose `uniform` list becomes one `Uniforms` struct. Colours are `float4` and touches
///     are packed `float4(x, y, age, active)` so Metal's 16-byte alignment rules cannot bite.
///   * The scene body's local `dot` is renamed `dotMask`; in MSL that name would shadow the
///     builtin `dot()`.
///   * The two passes (scene, then lens) are two fragment functions over a fullscreen triangle,
///     which is what AGSL's RuntimeShader + RenderEffect chain did.
public let halftoneShaderSource = #"""
#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------- uniforms

struct Uniforms {
    float2 resolution;
    float  time;          // uTime: scaled time
    float  now;           // uNow
    float4 params;        // uP0..uP3, in the order the scene declared its controls
    float4 c0;            // uC0..uC3; .w unused
    float4 c1;
    float4 c2;
    float4 c3;
    float4 touches[8];    // uTouches.xy, uTouchAges, uTouchActive — packed
    float  touchCount;
    float  touchStrength;
    float  aberration;
    float  grain;
};

struct LensUniforms {
    float2 size;
    float  amount;
};

// ---------------------------------------------------------------- header helpers

static inline float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

static inline float2 rot(float2 p, float a) {
    float c = cos(a), s = sin(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

/// Filmic tone curve. Linear output clips to white the moment anything is lit brightly.
static inline float3 aces(float3 x) {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

/// Touch displacement, shared by every scene so interaction feels consistent across the set.
static inline float2 touchWarp(float2 q, constant Uniforms &U) {
    for (int i = 0; i < 8; i++) {
        if (float(i) < U.touchCount) {
            float  age = U.touches[i].z;
            float2 d   = q - U.touches[i].xy;
            float  l   = max(length(d), 0.008);
            // Held contacts stay at full strength; released ones fade over about a second.
            float  life = max(U.touches[i].w, exp(-age * 2.6));
            float  wave = sin(l * 40.0 - age * 8.0) * exp(-l * 6.0) * life;
            q += d / l * wave * 0.030 * U.touchStrength;
        }
    }
    return q;
}

// ---------------------------------------------------------------- scene: halftone
//
// "A field of dots, breathing."
// Controls, in order: pitch (uP0), speed (uP1), contrast (uP2), angle (uP3).

static inline float3 scene(float2 p, float2 uv, float t, constant Uniforms &U) {
    float2 q = rot(p, U.params.w);
    float2 g = q * U.params.x;
    float2 f = fract(g) - 0.5;

    // The dot's size follows one slow wave across the field, which is the entire idea: a
    // halftone is a picture drawn in dot area, so the wave has to be in the area.
    float wave = sin(q.x * 3.0 + t * U.params.y) * 0.5
               + sin(q.y * 2.2 - t * U.params.y * 0.7) * 0.5;
    float radius  = (0.16 + 0.30 * (wave * 0.5 + 0.5)) * U.params.z;
    float dotMask = smoothstep(radius, radius - 0.06, length(f));
    return mix(U.c0.rgb, U.c2.rgb, dotMask);
}

// ---------------------------------------------------------------- fullscreen triangle

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut fullscreen_vertex(uint vid [[vertex_id]]) {
    // One oversized triangle covering the clip volume: no vertex buffer, no index buffer.
    float2 pts[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
    VertexOut out;
    out.position = float4(pts[vid], 0.0, 1.0);
    return out;
}

// ---------------------------------------------------------------- footer: the scene pass

fragment half4 scene_fragment(VertexOut in [[stage_in]],
                              constant Uniforms &U [[buffer(0)]]) {
    float2 fragCoord = in.position.xy;
    float2 res = U.resolution;
    float2 uv  = fragCoord / res;
    float2 p   = (fragCoord - 0.5 * res) / min(res.x, res.y);
    float2 wp  = touchWarp(p, U);
    float2 wuv = uv + (wp - p);

    float3 c = aces(scene(wp, wuv, U.time, U));

    // Grain goes on after tone mapping so it sits in the image rather than being crushed by it,
    // and eases off in the highlights, where sensor noise genuinely is less visible.
    float g = hash(fragCoord + fract(U.time) * 917.0) - 0.5;
    c += g * U.grain * 0.055 * (1.0 - 0.6 * dot(c, float3(0.2126, 0.7152, 0.0722)));

    float r = length(p);
    c *= 1.0 - 0.26 * r * r;
    return half4(half3(clamp(c, 0.0, 1.0)), 1.0h);
}

// ---------------------------------------------------------------- the lens pass
//
// Dispersion needs the image sampled at three slightly different points. Doing that inside the
// scene shader means evaluating the whole scene three times per pixel; here the scene is drawn
// once and the three samples are texture reads off the result. The offset is radial and grows
// toward the edges, because that is what a lens does.

fragment half4 lens_fragment(VertexOut in [[stage_in]],
                             texture2d<float> content [[texture(0)]],
                             constant LensUniforms &L [[buffer(0)]]) {
    constexpr sampler smp(filter::linear, coord::pixel, address::clamp_to_edge);

    float2 p   = in.position.xy;
    float2 mid = L.size * 0.5;
    float2 d   = p - mid;
    float  radius = length(d) / max(length(mid), 1.0);
    float2 dir = d / max(length(d), 0.001);
    float2 offset = dir * L.amount * (0.35 + radius) * min(L.size.x, L.size.y) * 0.0055;
    float2 low  = float2(0.5);
    float2 high = L.size - float2(0.5);

    float4 mids = content.sample(smp, p);
    return half4(half(content.sample(smp, clamp(p + offset, low, high)).r),
                 half(mids.g),
                 half(content.sample(smp, clamp(p - offset, low, high)).b),
                 half(mids.a));
}
"""#
