// Shared frame uniforms and lighting helpers. Prepended to every world shader (vertex and fragment).
struct UserUniforms {
    viewProj: mat4x4<f32>,
    invViewProj: mat4x4<f32>,
    shadowMat: mat4x4<f32>,
    camera: vec4<f32>,
    sunDir: vec4<f32>,
    sunColor: vec4<f32>,
    ambient: vec4<f32>,
    horizon: vec4<f32>,
    screen: vec4<f32>,
    params: vec4<f32>,
    params2: vec4<f32>,
};
@group(1) @binding(0) var<uniform> frame: UserUniforms;

const PI: f32 = 3.14159265;
const DEPTH_SCALE: f32 = 1024.0;

fn hash21(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(0.1031, 0.1030));
    q += dot(q, q.yx + 33.33);
    return fract((q.x + q.y) * q.x);
}
fn hash31(p: vec3<f32>) -> f32 {
    var q = fract(p * 0.1031);
    q += dot(q, q.zyx + 31.32);
    return fract((q.x + q.y) * q.z);
}
fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash21(i); let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0)); let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var s = 0.0; var a = 0.5; var q = p;
    for (var i = 0; i < octaves; i++) {
        s += noise2(q) * a; q = q * 2.03 + vec2<f32>(17.1, 9.3); a *= 0.5;
    }
    return s;
}
// Interleaved gradient noise: stable per-pixel dither for shadow taps and banding.
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }

fn sunElevation() -> f32 { return frame.sunDir.y; }

// Analytic sky: Rayleigh-like gradient, warm horizon near a low sun, Mie halo and night tones.
fn skyColor(dir: vec3<f32>, sunVisible: bool) -> vec3<f32> {
    let day = frame.sunDir.w;
    let night = frame.params2.w;
    let up = clamp(dir.y, -0.25, 1.0);
    let mu = max(up, 0.0);
    let zenithDay = vec3<f32>(0.10, 0.26, 0.72);
    let horizonDay = vec3<f32>(0.52, 0.66, 0.86);
    let zenithNight = vec3<f32>(0.004, 0.007, 0.020);
    let horizonNight = vec3<f32>(0.020, 0.030, 0.060);
    var zenith = mix(zenithNight, zenithDay, day);
    var horizon = mix(horizonNight, horizonDay, day);
    // Sunset/sunrise warmth concentrated around the sun's azimuth.
    let sun = normalize(frame.sunDir.xyz);
    let low = smoothstep(0.45, 0.0, abs(sun.y + 0.02)) * (1.0 - night * 0.8);
    let toward = pow(max(dot(normalize(vec3<f32>(dir.x, 0.0, dir.z) + vec3<f32>(1e-4)), normalize(vec3<f32>(sun.x, 0.0, sun.z) + vec3<f32>(1e-4))), 0.0), 3.0);
    horizon = mix(horizon, mix(vec3<f32>(0.30, 0.17, 0.17), vec3<f32>(0.55, 0.15, 0.03), toward), low * (0.7 + 0.3 * toward));
    zenith = mix(zenith, vec3<f32>(0.16, 0.20, 0.42), low * 0.4);
    var col = mix(horizon, zenith, pow(mu, 0.42 + 0.45 * low));
    // Haze band and ground below the horizon.
    col = mix(col, horizon * 0.9, exp(-mu * 18.0) * 0.4);
    if (up < 0.0) { col = mix(col, horizon * vec3<f32>(0.45, 0.47, 0.5), clamp(-up * 6.0, 0.0, 1.0)); }
    let cosTheta = max(dot(dir, sun), 0.0);
    let halo = (pow(cosTheta, 6.0) * 0.18 * (1.0 - 0.6 * low) + pow(cosTheta, 48.0) * 0.55) * day;
    col += frame.sunColor.rgb * halo * 0.25 * select(0.6, 1.0, sun.y > 0.0);
    if (sunVisible) {
        let disc = smoothstep(0.9993, 0.99965, cosTheta) * day;
        col += vec3<f32>(18.0, 15.0, 11.0) * disc;
        // Moon opposite the sun.
        let moonDir = -sun;
        let mc = max(dot(dir, moonDir), 0.0);
        col += vec3<f32>(1.4, 1.5, 1.7) * smoothstep(0.99955, 0.99975, mc) * night;
        col += vec3<f32>(0.05, 0.06, 0.08) * pow(mc, 64.0) * night;
    }
    return col * 1.15;
}

// Aerial perspective: distance haze plus a soft wall at the render distance so chunk edges never show.
fn applyFog(color: vec3<f32>, rel: vec3<f32>) -> vec3<f32> {
    let dist = length(rel);
    let dir = rel / max(dist, 1e-4);
    let radius = frame.horizon.w;
    let haze = (1.0 - exp(-dist * 0.00055 * frame.ambient.w * (1.0 + 1.5 * exp(-max(frame.camera.y + rel.y - 56.0, 0.0) * 0.03)))) * 0.85;
    let edge = smoothstep(radius * 0.78, radius * 0.99, dist);
    let f = clamp(max(haze, edge), 0.0, 1.0);
    var fogCol = skyColor(normalize(vec3<f32>(dir.x, max(dir.y, -0.02) * 0.6, dir.z)), false);
    if (frame.params.x > 0.5) {
        // Underwater: short blue-green visibility.
        let w = 1.0 - exp(-dist * 0.09);
        return mix(color, vec3<f32>(0.02, 0.09, 0.13) * (0.25 + frame.sunDir.w), w);
    }
    return mix(color, fogCol, f);
}

fn decodeDepth(c: vec4<f32>) -> f32 { return c.r + c.g / 1024.0; }
