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
@group(2) @binding(1) var materialTex: texture_2d<f32>;
@group(2) @binding(2) var shadowTex: texture_2d<f32>;
@group(2) @binding(8) var linearSampler: sampler;
// Player-placed light sources: [count, 0, 0, 0] then (x, y, z, level) per light, nearest first.
@group(2) @binding(10) var<storage, read> lights: array<f32>;

struct Varyings {
    @builtin(position) position: vec4<f32>,
    @location(0) rel: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) info: vec4<f32>,
    @location(4) tangent: vec3<f32>,
};

const ATLAS_COLS: f32 = 8.0;
const ATLAS_ROWS: f32 = 4.0;
const TILE_PX: f32 = 32.0;

// Atlas lookup with crisp texels, explicit gradients (no seams at tile wraps) and mip-aware insets.
fn atlasCoord(uv: vec2<f32>, tile: f32, lod: f32) -> vec2<f32> {
    let cell = vec2<f32>(tile % ATLAS_COLS, floor(tile / ATLAS_COLS));
    let texel = fract(uv) * TILE_PX;
    let inset = 0.5 * exp2(max(lod, 0.0));
    let t = clamp(texel, vec2<f32>(inset), vec2<f32>(TILE_PX - inset));
    return (cell * TILE_PX + t) / vec2<f32>(ATLAS_COLS * TILE_PX, ATLAS_ROWS * TILE_PX);
}

fn crisp(uv: vec2<f32>, fw: vec2<f32>) -> vec2<f32> {
    // Pixel-art anti-aliasing: snap to texel centres, blending only across the texel edge.
    let px = uv * TILE_PX;
    let f = fract(px);
    let snapped = floor(px) + 0.5 + clamp((f - 0.5) / max(fw * TILE_PX, vec2<f32>(1e-4)), vec2<f32>(-0.5), vec2<f32>(0.5));
    return snapped / TILE_PX;
}

fn shadowFactor(rel: vec3<f32>, n: vec3<f32>, pixel: vec2<f32>) -> f32 {
    if (frame.sunColor.w < 0.5) { return 1.0; }
    let size = frame.params.z;
    let ndl = max(dot(n, frame.sunDir.xyz), 0.0);
    let offset = n * (0.035 + 0.06 * (1.0 - ndl));
    let p = frame.shadowMat * vec4<f32>(rel + offset, 1.0);
    let uv = vec2<f32>(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0 || p.z >= 1.0) { return 1.0; }
    let bias = 0.0006;
    let radius = frame.params.w;
    let angle = ign(pixel) * 6.2831853;
    let rot = mat2x2<f32>(cos(angle), sin(angle), -sin(angle), cos(angle));
    var lit = 0.0;
    var taps = array<vec2<f32>, 12>(
        vec2<f32>(-0.326, -0.406), vec2<f32>(-0.840, -0.074), vec2<f32>(-0.696, 0.457), vec2<f32>(-0.203, 0.621),
        vec2<f32>(0.962, -0.195), vec2<f32>(0.473, -0.480), vec2<f32>(0.519, 0.767), vec2<f32>(0.185, -0.893),
        vec2<f32>(0.507, 0.064), vec2<f32>(0.896, 0.412), vec2<f32>(-0.322, -0.933), vec2<f32>(-0.792, -0.598));
    for (var i = 0; i < 12; i++) {
        let o = rot * taps[i] * radius;
        let tc = clamp(vec2<i32>(uv * size + o), vec2<i32>(0), vec2<i32>(i32(size) - 1));
        let d = decodeDepth(textureLoad(shadowTex, tc, 0));
        lit += select(0.0, 1.0, p.z - bias <= d);
    }
    let edgeFade = smoothstep(0.0, 0.06, min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y)));
    return mix(1.0, lit / 12.0, edgeFade);
}

fn ggx(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, rough: f32, f0: f32) -> f32 {
    let h = normalize(v + l);
    let nh = max(dot(n, h), 0.0); let nl = max(dot(n, l), 0.0); let nv = max(dot(n, v), 1e-3); let vh = max(dot(v, h), 0.0);
    let a = rough * rough; let a2 = a * a;
    let d = a2 / (PI * pow(nh * nh * (a2 - 1.0) + 1.0, 2.0));
    let k = (rough + 1.0) * (rough + 1.0) / 8.0;
    let g = (nl / (nl * (1.0 - k) + k)) * (nv / (nv * (1.0 - k) + k));
    let f = f0 + (1.0 - f0) * pow(1.0 - vh, 5.0);
    return d * g * f / (4.0 * nl * nv + 1e-4) * nl;
}

@fragment fn fs_main(input: Varyings) -> @location(0) vec4<f32> {
    let tile = round(input.info.x);
    let flags = u32(round(input.info.w));
    let dx = dpdx(input.uv); let dy = dpdy(input.uv);
    let fw = abs(dx) + abs(dy);
    let lod = log2(max(max(length(dx), length(dy)) * TILE_PX, 1e-4));
    let uvc = crisp(input.uv, fw);
    let coord = atlasCoord(uvc, tile, lod);
    let scale = vec2<f32>(1.0 / ATLAS_COLS, 1.0 / ATLAS_ROWS);
    let albedoSample = textureSampleGrad(albedoTex, linearSampler, coord, dx * scale, dy * scale);
    let material = textureSampleGrad(materialTex, linearSampler, coord, dx * scale, dy * scale);
    if ((tile == 7.0 || tile == 13.0 || tile == 14.0 || tile == 29.0) && albedoSample.a < 0.5) { discard; }
    var albedo = albedoSample.rgb;
    // Gentle per-block tint variation keeps large fields from looking stamped.
    let blockPos = floor(input.rel + frame.camera.xyz - input.normal * 0.01);
    let vary = hash31(blockPos) * 0.08 - 0.04;
    albedo *= 1.0 + vary;
    if (tile == 0.0 || tile == 7.0 || tile == 13.0) {
        // Grass and leaves follow a slow "biome" colour field.
        let field = noise2((blockPos.xz) * 0.012);
        albedo *= mix(vec3<f32>(1.06, 1.02, 0.86), vec3<f32>(0.86, 1.0, 0.96), field);
    }
    // Tangent-space normal map.
    var n = normalize(input.normal);
    let t = normalize(input.tangent - n * dot(input.tangent, n));
    let b = cross(n, t);
    let mn = vec2<f32>(material.r * 2.0 - 1.0, material.g * 2.0 - 1.0) * 0.8;
    var sideSign = 1.0;
    if (abs(n.y) < 0.5) { sideSign = -1.0; }
    let nm = normalize(t * mn.x + b * mn.y * sideSign + n * sqrt(max(1.0 - dot(mn, mn), 0.0)));
    let rough = clamp(material.b, 0.08, 1.0);
    let cavity = mix(0.75, 1.0, material.a);

    let v = normalize(-input.rel);
    let l = normalize(frame.sunDir.xyz);
    let plant = tile == 13.0 || tile == 14.0;
    var ndl = max(dot(nm, l), 0.0);
    if (plant || tile == 7.0) { ndl = max(ndl, 0.35 * max(dot(-nm, l), 0.0)) * 0.9 + 0.1 * max(l.y, 0.0); } // thin foliage transmits light
    let shadow = shadowFactor(input.rel, n, input.position.xy);
    let ao = mix(0.35, 1.0, pow(input.info.y / 3.0, 1.1));
    let skyLight = pow(input.info.z / 15.0, 2.2);

    let direct = frame.sunColor.rgb * ndl * shadow;
    let spec = ggx(nm, v, l, rough, 0.04) * shadow;
    // Hemisphere ambient: cool sky above, warm bounce below, scaled by sky access and AO.
    let hemi = mix(vec3<f32>(0.32, 0.27, 0.2) * frame.ambient.rgb * 0.7, frame.ambient.rgb, nm.y * 0.5 + 0.5);
    let ambient = hemi * skyLight * ao + vec3<f32>(0.018, 0.02, 0.026) * ao;
    // Torches and lit furnaces: warm point lights with a soft wrap, no occlusion beyond AO.
    let world = input.rel + frame.camera.xyz;
    let lightCount = i32(lights[0]);
    var torch = vec3<f32>(0.0);
    for (var i = 0; i < lightCount; i++) {
        let lp = vec3<f32>(lights[4 + i * 4], lights[5 + i * 4], lights[6 + i * 4]) + vec3<f32>(0.5, 0.55, 0.5);
        let level = lights[7 + i * 4] / 15.0;
        let toL = lp - world;
        let d = length(toL);
        let reach = 13.0 * level;
        if (d < reach) {
            let fall = 1.0 - d / reach;
            let wrap = max(dot(nm, toL / max(d, 1e-3)), 0.0) * 0.65 + 0.35;
            torch += vec3<f32>(1.0, 0.62, 0.30) * (fall * fall) * wrap * 2.2;
        }
    }
    var color = albedo * (direct + ambient + torch * ao) * cavity + frame.sunColor.rgb * spec * 0.25 * skyLight;
    // Emissive texels: torch flames and the glowing mouth of a lit furnace.
    if (tile == 29.0) {
        let glow = smoothstep(0.35, 0.7, albedoSample.r) * step(albedoSample.b, albedoSample.r * 0.8);
        color += albedoSample.rgb * glow * 6.0;
    } else if (tile == 31.0) {
        let glow = smoothstep(0.25, 0.6, albedoSample.r - albedoSample.b);
        color += albedoSample.rgb * glow * 4.0;
    }
    color = applyFog(color, input.rel);
    return vec4<f32>(color, length(input.rel) / DEPTH_SCALE);
}
