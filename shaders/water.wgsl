//#vertex
// Terrain quads are pulled from a per-chunk storage buffer: a 4-float header (chunk origin)
// followed by three exact-integer floats per quad (see src/mesher.aqua).
@group(2) @binding(9) var<storage, read> quads: array<f32>;

struct Varyings {
    @builtin(position) position: vec4<f32>,
    @location(0) rel: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) info: vec4<f32>,   // tile, ao (0..3), sky (0..15), flags
    @location(4) tangent: vec3<f32>,
};

fn faceAxes(face: u32, n: ptr<function, vec3<f32>>, u: ptr<function, vec3<f32>>, v: ptr<function, vec3<f32>>, o: ptr<function, vec3<f32>>) {
    *o = vec3<f32>(0.0);
    if (face == 0u) { *n = vec3<f32>(1.0, 0.0, 0.0); *u = vec3<f32>(0.0, 0.0, 1.0); *v = vec3<f32>(0.0, 1.0, 0.0); *o = vec3<f32>(1.0, 0.0, 0.0); }
    else if (face == 1u) { *n = vec3<f32>(-1.0, 0.0, 0.0); *u = vec3<f32>(0.0, 0.0, 1.0); *v = vec3<f32>(0.0, 1.0, 0.0); }
    else if (face == 2u) { *n = vec3<f32>(0.0, 1.0, 0.0); *u = vec3<f32>(1.0, 0.0, 0.0); *v = vec3<f32>(0.0, 0.0, 1.0); *o = vec3<f32>(0.0, 1.0, 0.0); }
    else if (face == 3u) { *n = vec3<f32>(0.0, -1.0, 0.0); *u = vec3<f32>(1.0, 0.0, 0.0); *v = vec3<f32>(0.0, 0.0, 1.0); }
    else if (face == 4u) { *n = vec3<f32>(0.0, 0.0, 1.0); *u = vec3<f32>(1.0, 0.0, 0.0); *v = vec3<f32>(0.0, 1.0, 0.0); *o = vec3<f32>(0.0, 0.0, 1.0); }
    else if (face == 5u) { *n = vec3<f32>(0.0, 0.0, -1.0); *u = vec3<f32>(1.0, 0.0, 0.0); *v = vec3<f32>(0.0, 1.0, 0.0); }
    else if (face == 6u) { *n = vec3<f32>(0.7071, 0.0, -0.7071); *u = vec3<f32>(1.0, 0.0, 1.0); *v = vec3<f32>(0.0, 1.0, 0.0); }
    else { *n = vec3<f32>(0.7071, 0.0, 0.7071); *u = vec3<f32>(-1.0, 0.0, 1.0); *v = vec3<f32>(0.0, 1.0, 0.0); *o = vec3<f32>(1.0, 0.0, 0.0); }
}

@vertex fn vs_main(@builtin(vertex_index) index: u32) -> Varyings {
    let q = index / 6u;
    let base = 4u + q * 3u;
    let f0 = u32(quads[base]);
    let f1 = u32(quads[base + 1u]);
    let f2 = u32(quads[base + 2u]);
    let lx = f32(f0 % 32u); let lz = f32((f0 / 32u) % 32u); let ly = f32((f0 / 1024u) % 256u); let face = f0 / 262144u;
    let w = f32(f1 % 128u + 1u); let h = f32((f1 / 128u) % 128u + 1u); let tile = (f1 / 16384u) % 32u; let flags = f1 / 524288u;
    // Faces whose (u x v) points inward use the opposite winding; plants' back sides set flag 4.
    var reversed = face == 0u || face == 2u || face == 5u;
    if ((flags & 4u) != 0u) { reversed = !reversed; }
    var order = array<u32, 6>(0u, 1u, 2u, 0u, 2u, 3u);
    if ((flags & 1u) != 0u) { order = array<u32, 6>(1u, 2u, 3u, 1u, 3u, 0u); }
    if (reversed) {
        if ((flags & 1u) != 0u) { order = array<u32, 6>(1u, 3u, 2u, 1u, 0u, 3u); } else { order = array<u32, 6>(0u, 2u, 1u, 0u, 3u, 2u); }
    }
    let corner = order[index % 6u];
    let cu = select(0.0, 1.0, corner == 1u || corner == 2u);
    let cv = select(0.0, 1.0, corner >= 2u);
    var n: vec3<f32>; var uAxis: vec3<f32>; var vAxis: vec3<f32>; var off: vec3<f32>;
    faceAxes(face, &n, &uAxis, &vAxis, &off);
    if ((flags & 4u) != 0u) { n = -n; }
    var local = vec3<f32>(lx, ly, lz) + off + uAxis * (cu * w) + vAxis * (cv * h);
    if ((flags & 2u) != 0u) { local.y -= 0.125; }
    let origin = vec3<f32>(quads[0], 0.0, quads[1]);
    var world = origin + local;
    let t = frame.camera.w;
    // Gentle wind: leaves sway as a whole canopy, plants bend at the tips.
    if (tile == 7u) {
        let phase = dot(world, vec3<f32>(0.35, 0.2, 0.27));
        world += vec3<f32>(sin(t * 1.3 + phase), 0.0, cos(t * 1.1 + phase * 1.3)) * 0.035;
    } else if (tile == 13u || tile == 14u) {
        let phase = dot(floor(world), vec3<f32>(1.7, 0.0, 2.3));
        let gust = 0.6 + 0.4 * sin(t * 0.4 + world.x * 0.05);
        world += vec3<f32>(sin(t * 1.9 + phase), 0.0, cos(t * 1.6 + phase)) * 0.09 * cv * gust;
    }
    let ao = f32((f2 >> (corner * 2u)) & 3u);
    let sky = f32((f2 >> (8u + corner * 4u)) & 15u);
    var o: Varyings;
    o.rel = world - frame.camera.xyz;
    o.position = frame.viewProj * vec4<f32>(o.rel, 1.0);
    o.normal = n;
    o.tangent = normalize(uAxis);
    // Texture v points down the image; side faces keep the grass fringe on top.
    var uv = vec2<f32>(cu * w, cv * h);
    if (face != 2u && face != 3u) { uv.y = h - uv.y; }
    if ((flags & 2u) != 0u && face != 2u) { uv.y -= 0.125; }
    o.uv = uv;
    o.info = vec4<f32>(f32(tile), ao, sky, f32(flags));
    return o;
}

//#fragment
@group(2) @binding(0) var albedoTex: texture_2d<f32>;
@group(2) @binding(2) var shadowTex: texture_2d<f32>;
@group(2) @binding(3) var sceneTex: texture_2d<f32>;
@group(2) @binding(8) var linearSampler: sampler;
struct Varyings {
    @builtin(position) position: vec4<f32>,
    @location(0) rel: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) info: vec4<f32>,
    @location(4) tangent: vec3<f32>,
};

fn sceneDepthAt(uv: vec2<f32>) -> f32 {
    let size = vec2<f32>(textureDimensions(sceneTex));
    let p = clamp(vec2<i32>(uv * size), vec2<i32>(0), vec2<i32>(size) - vec2<i32>(1));
    return textureLoad(sceneTex, p, 0).a * DEPTH_SCALE;
}
fn sceneColorAt(uv: vec2<f32>) -> vec3<f32> { return textureSampleLevel(sceneTex, linearSampler, uv, 0.0).rgb; }

fn sunShadow(rel: vec3<f32>) -> f32 {
    if (frame.sunColor.w < 0.5) { return 1.0; }
    let p = frame.shadowMat * vec4<f32>(rel + vec3<f32>(0.0, 0.05, 0.0), 1.0);
    let uv = vec2<f32>(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) { return 1.0; }
    let size = frame.params.z;
    let d = decodeDepth(textureLoad(shadowTex, vec2<i32>(uv * size), 0));
    return select(0.0, 1.0, p.z - 0.0008 <= d);
}

// Sum of travelling waves plus fine noise; returns a world-space normal for the water surface.
fn waveNormal(xz: vec2<f32>, t: f32, strength: f32) -> vec3<f32> {
    var g = vec2<f32>(0.0);
    var dirs = array<vec2<f32>, 4>(vec2<f32>(0.8, 0.6), vec2<f32>(-0.4, 0.9), vec2<f32>(0.95, -0.3), vec2<f32>(-0.7, -0.7));
    var freq = array<f32, 4>(0.55, 0.9, 1.6, 2.7);
    var amp = array<f32, 4>(0.06, 0.04, 0.025, 0.012);
    var spd = array<f32, 4>(1.1, 1.4, 1.9, 2.6);
    for (var i = 0; i < 4; i++) {
        let d = dirs[i];
        let ph = dot(d, xz) * freq[i] + t * spd[i];
        g += d * cos(ph) * freq[i] * amp[i];
    }
    let e = 0.15;
    let n0 = noise2(xz * 1.7 + vec2<f32>(t * 0.6, t * 0.35));
    let nx = noise2((xz + vec2<f32>(e, 0.0)) * 1.7 + vec2<f32>(t * 0.6, t * 0.35));
    let nz = noise2((xz + vec2<f32>(0.0, e)) * 1.7 + vec2<f32>(t * 0.6, t * 0.35));
    g += vec2<f32>(nx - n0, nz - n0) / e * 0.05;
    return normalize(vec3<f32>(-g.x * strength, 1.0, -g.y * strength));
}

// Screen-space reflection against the opaque scene (colour + linear depth in alpha).
fn traceReflection(rel: vec3<f32>, r: vec3<f32>) -> vec4<f32> {
    if (frame.params.y < 0.5) { return vec4<f32>(0.0); }
    var p = rel;
    let stepLen = 0.9;
    var prevDepth = length(p);
    for (var i = 0; i < 28; i++) {
        p += r * stepLen * (1.0 + f32(i) * 0.18);
        let clip = frame.viewProj * vec4<f32>(p, 1.0);
        if (clip.w <= 0.0) { break; }
        let ndc = clip.xyz / clip.w;
        let uv = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
        if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) { break; }
        let sd = sceneDepthAt(uv);
        let pd = length(p);
        if (pd > sd && pd - sd < 2.5 + f32(i) * 0.4 && sd < frame.horizon.w * 1.2) {
            let edge = smoothstep(0.0, 0.12, min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y)));
            return vec4<f32>(sceneColorAt(uv), edge);
        }
        prevDepth = pd;
    }
    return vec4<f32>(0.0);
}

@fragment fn fs_main(input: Varyings) -> @location(0) vec4<f32> {
    let tile = round(input.info.x);
    let screenUV = input.position.xy * frame.screen.zw;
    let fragDist = length(input.rel);
    let behind = sceneDepthAt(screenUV);
    // Manual depth test against the opaque pass (water and glass draw into a separate target).
    if (fragDist > behind + 0.02) { discard; }
    let v = normalize(-input.rel);
    let world = input.rel + frame.camera.xyz;
    let l = normalize(frame.sunDir.xyz);
    let t = frame.camera.w;
    let skyLight = pow(input.info.z / 15.0, 2.0);
    if (tile == 8.0) {
        // Glass: tinted pass-through with frame texture and a faint Fresnel reflection.
        let c = vec2<f32>(0.0, 1.0);
        let coord = (c * 32.0 + clamp(fract(input.uv) * 32.0, vec2<f32>(0.5), vec2<f32>(31.5))) / vec2<f32>(256.0, 128.0);
        let tex = textureSampleLevel(albedoTex, linearSampler, coord, 0.0);
        let n = normalize(input.normal);
        let behindCol = sceneColorAt(screenUV);
        let lit = frame.sunColor.rgb * max(dot(n, l), 0.0) * 0.6 + frame.ambient.rgb * (0.4 + 0.6 * skyLight);
        let fres = 0.04 + 0.96 * pow(1.0 - max(dot(n, v), 0.0), 5.0);
        var col = mix(behindCol * vec3<f32>(0.92, 0.97, 1.0), tex.rgb * lit, tex.a);
        col = mix(col, skyColor(reflect(-v, n), false), fres * 0.5);
        return vec4<f32>(applyFog(col, input.rel), fragDist / DEPTH_SCALE);
    }
    // Water surface.
    let top = input.normal.y > 0.5;
    let fromBelow = frame.params.x > 0.5;
    var n = normalize(input.normal);
    if (top) {
        let fade = 1.0 - smoothstep(30.0, 140.0, fragDist);
        n = waveNormal(world.xz, t, 0.6 + 0.6 * fade);
        if (fromBelow) { n = -n; }
    }
    let ndv = max(dot(n, v), 0.0);
    // Refraction: offset by the surface slope, rejecting samples that land in front of the water.
    let offset = n.xz * 0.025 * clamp((behind - fragDist) * 0.5, 0.0, 1.0);
    var refrUV = screenUV + offset;
    var refrDepth = sceneDepthAt(refrUV);
    if (refrDepth < fragDist) { refrUV = screenUV; refrDepth = behind; }
    let thickness = max(refrDepth - fragDist, 0.0);
    let behindCol = sceneColorAt(refrUV);
    let absorb = vec3<f32>(0.38, 0.11, 0.07);
    let transmit = exp(-absorb * thickness);
    let day = frame.sunDir.w;
    let deepColor = vec3<f32>(0.010, 0.050, 0.075) * (frame.ambient.rgb * 1.6 + frame.sunColor.rgb * 0.08) * (0.3 + 0.7 * skyLight);
    var refracted = behindCol * transmit + deepColor * (vec3<f32>(1.0) - transmit);
    if (fromBelow) { refracted = behindCol * exp(-absorb * 0.5); }
    // Reflection: screen-space trace with the analytic sky as fallback.
    let r = reflect(-v, n);
    let sky = skyColor(normalize(vec3<f32>(r.x, max(r.y, 0.02), r.z)), false) * (0.35 + 0.65 * skyLight);
    let ssr = traceReflection(input.rel, r);
    let reflection = mix(sky, ssr.rgb, ssr.a);
    var fresnel = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
    if (fromBelow) { fresnel = 0.0; }
    let shadow = sunShadow(input.rel);
    let h = normalize(v + l);
    let spec = pow(max(dot(n, h), 0.0), 900.0) * 30.0 + pow(max(dot(n, h), 0.0), 120.0) * 0.6;
    var col = mix(refracted, reflection, fresnel) + frame.sunColor.rgb * spec * shadow * fresnel * 4.0;
    // Soft shoreline foam where the water is shallow.
    if (top && !fromBelow) {
        let foam = smoothstep(0.35, 0.0, thickness) * (0.55 + 0.45 * noise2(world.xz * 3.0 + vec2<f32>(t * 0.5, 0.0)));
        col = mix(col, (frame.sunColor.rgb * max(l.y, 0.0) + frame.ambient.rgb) * 0.8, foam * 0.35);
    }
    return vec4<f32>(applyFog(col, input.rel), fragDist / DEPTH_SCALE);
}
