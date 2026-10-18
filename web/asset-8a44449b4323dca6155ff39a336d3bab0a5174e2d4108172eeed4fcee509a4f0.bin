//#vertex
// Entities (dropped items, particles, night creatures) pulled from one storage buffer, 12 floats each:
// x, y, z, size, rotation, kind, a, b, c, light, e1, e2.  36 vertices per entity (a cube; sprites use 6).
// kind 0 block item cube (a,b,c = top/side/bottom tiles), 1 flat block sprite (a = tile),
// 2 item icon sprite (a = icon), 3 debris particle (a = tile, b,c = texel offset), 4/5 creature body/head (a,b = facing).
@group(2) @binding(9) var<storage, read> ents: array<f32>;

struct EntOut {
    @builtin(position) position: vec4<f32>,
    @location(0) rel: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) info: vec4<f32>,   // kind, tile, face, flash
    @location(4) extra: vec4<f32>,  // light, texel offset, age
};

fn faceBasis(face: u32, n: ptr<function, vec3<f32>>, u: ptr<function, vec3<f32>>, v: ptr<function, vec3<f32>>) {
    if (face == 0u) { *n = vec3<f32>(1.0, 0.0, 0.0); *u = vec3<f32>(0.0, 0.0, -1.0); *v = vec3<f32>(0.0, 1.0, 0.0); }
    else if (face == 1u) { *n = vec3<f32>(-1.0, 0.0, 0.0); *u = vec3<f32>(0.0, 0.0, 1.0); *v = vec3<f32>(0.0, 1.0, 0.0); }
    else if (face == 2u) { *n = vec3<f32>(0.0, 1.0, 0.0); *u = vec3<f32>(1.0, 0.0, 0.0); *v = vec3<f32>(0.0, 0.0, -1.0); }
    else if (face == 3u) { *n = vec3<f32>(0.0, -1.0, 0.0); *u = vec3<f32>(1.0, 0.0, 0.0); *v = vec3<f32>(0.0, 0.0, 1.0); }
    else if (face == 4u) { *n = vec3<f32>(0.0, 0.0, 1.0); *u = vec3<f32>(1.0, 0.0, 0.0); *v = vec3<f32>(0.0, 1.0, 0.0); }
    else { *n = vec3<f32>(0.0, 0.0, -1.0); *u = vec3<f32>(-1.0, 0.0, 0.0); *v = vec3<f32>(0.0, 1.0, 0.0); }
}

@vertex fn vs_main(@builtin(vertex_index) index: u32) -> EntOut {
    let e = index / 36u;
    let k = index % 36u;
    let b = e * 12u;
    let pos = vec3<f32>(ents[b], ents[b + 1u], ents[b + 2u]);
    let size = ents[b + 3u];
    let rot = ents[b + 4u];
    let kind = u32(ents[b + 5u] + 0.5);
    let a = ents[b + 6u]; let bb = ents[b + 7u]; let c = ents[b + 8u];
    var corners = array<vec2<f32>, 6>(vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(1.0, 1.0),
                                      vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 1.0), vec2<f32>(0.0, 1.0));
    let cuv = corners[k % 6u];
    var face = k / 6u;
    var n: vec3<f32>; var u: vec3<f32>; var v: vec3<f32>;
    var local: vec3<f32>;
    var tile = a;
    var o: EntOut;
    var scale = vec3<f32>(size);
    var centre = pos + vec3<f32>(0.0, size * 0.5, 0.0);
    var cosr = cos(rot); var sinr = sin(rot);
    if (kind == 1u || kind == 2u) {
        // Flat sprite spinning around Y (double-sided; only the first six vertices make a quad).
        n = vec3<f32>(0.0, 0.0, 1.0); u = vec3<f32>(1.0, 0.0, 0.0); v = vec3<f32>(0.0, 1.0, 0.0);
        local = (u * (cuv.x - 0.5) + v * (cuv.y - 0.5)) * size;
        if (face > 0u) { local = vec3<f32>(0.0); }
        face = 4u;
    } else {
        faceBasis(face, &n, &u, &v);
        if (kind == 4u || kind == 5u) {
            // Creature: a narrow body (kind 4) and a head (kind 5) standing on pos, turned toward
            // its facing direction, with a slight walking bob.
            let bob = abs(sin(ents[b + 10u] * 7.0)) * 0.05;
            if (kind == 4u) {
                scale = vec3<f32>(0.56, 1.08, 0.34);
                centre = pos + vec3<f32>(0.0, 0.54 + bob, 0.0);
            } else {
                scale = vec3<f32>(0.5, 0.5, 0.5);
                centre = pos + vec3<f32>(0.0, 1.34 + bob, 0.0);
            }
            let f = normalize(vec2<f32>(a, bb) + vec2<f32>(1e-4, 0.0));
            cosr = f.y; sinr = f.x;
        }
        local = (n * 0.5 + u * (cuv.x - 0.5) + v * (cuv.y - 0.5)) * scale;
        if (kind == 0u) {
            if (face == 2u) { tile = a; } else if (face == 3u) { tile = c; } else { tile = bb; }
        }
    }
    // Rotate around Y: local +z turns toward (sin, cos).
    let rx = local.x * cosr + local.z * sinr;
    let rz = -local.x * sinr + local.z * cosr;
    let world = centre + vec3<f32>(rx, local.y, rz);
    let rn = vec3<f32>(n.x * cosr + n.z * sinr, n.y, -n.x * sinr + n.z * cosr);
    o.rel = world - frame.camera.xyz;
    o.position = frame.viewProj * vec4<f32>(o.rel, 1.0);
    o.normal = rn;
    o.uv = vec2<f32>(cuv.x, 1.0 - cuv.y);
    var flash = 0.0;
    if (kind == 4u || kind == 5u) { flash = c; }
    o.info = vec4<f32>(f32(kind), tile, f32(face), flash);
    o.extra = vec4<f32>(ents[b + 9u], bb, c, ents[b + 10u]);
    return o;
}

//#fragment
@group(2) @binding(0) var albedoTex: texture_2d<f32>;
@group(2) @binding(1) var itemTex: texture_2d<f32>;
@group(2) @binding(8) var linearSampler: sampler;
@group(2) @binding(10) var<storage, read> lights: array<f32>;

struct EntOut {
    @builtin(position) position: vec4<f32>,
    @location(0) rel: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) info: vec4<f32>,
    @location(4) extra: vec4<f32>,
};

fn atlasTexel(tile: f32, uv: vec2<f32>) -> vec4<f32> {
    let cell = vec2<f32>(tile % 8.0, floor(tile / 8.0));
    let t = clamp(vec2<i32>(cell * 32.0 + floor(clamp(uv, vec2<f32>(0.0), vec2<f32>(0.999)) * 32.0)), vec2<i32>(0), vec2<i32>(255, 127));
    return textureLoad(albedoTex, t, 0);
}

fn torchLight(world: vec3<f32>, n: vec3<f32>) -> vec3<f32> {
    let count = i32(lights[0]);
    var acc = vec3<f32>(0.0);
    for (var i = 0; i < count; i++) {
        let lp = vec3<f32>(lights[4 + i * 4], lights[5 + i * 4], lights[6 + i * 4]) + vec3<f32>(0.5, 0.55, 0.5);
        let reach = 13.0 * lights[7 + i * 4] / 15.0;
        let toL = lp - world;
        let d = length(toL);
        if (d < reach) {
            let fall = 1.0 - d / reach;
            acc += vec3<f32>(1.0, 0.62, 0.30) * fall * fall * (max(dot(n, toL / max(d, 1e-3)), 0.0) * 0.65 + 0.35) * 2.2;
        }
    }
    return acc;
}

@fragment fn fs_main(input: EntOut) -> @location(0) vec4<f32> {
    let kind = u32(input.info.x + 0.5);
    let tile = round(input.info.y);
    var n = normalize(input.normal);
    var albedo = vec3<f32>(1.0);
    var emissive = vec3<f32>(0.0);
    if (kind == 2u) {
        let cell = vec2<f32>(tile % 8.0, floor(tile / 8.0));
        let t = clamp(vec2<i32>(cell * 32.0 + floor(clamp(input.uv, vec2<f32>(0.0), vec2<f32>(0.999)) * 32.0)), vec2<i32>(0), vec2<i32>(255, 127));
        let s = textureLoad(itemTex, t, 0);
        if (s.a < 0.5) { discard; }
        albedo = s.rgb;
    } else if (kind == 4u || kind == 5u) {
        // Creature: dark mottled hide; the head carries two glowing eyes on the side facing its target.
        let face = u32(input.info.z + 0.5);
        let q = floor(input.uv * vec2<f32>(8.0, 8.0));
        let mott = hash21(q + vec2<f32>(input.info.z * 13.0, f32(kind) * 5.0));
        albedo = mix(vec3<f32>(0.035, 0.03, 0.06), vec3<f32>(0.09, 0.065, 0.13), mott);
        if (kind == 5u && face == 4u) {
            let eyeY = abs(input.uv.y - 0.45) < 0.08;
            let eyeL = abs(input.uv.x - 0.28) < 0.1;
            let eyeR = abs(input.uv.x - 0.72) < 0.1;
            if (eyeY && (eyeL || eyeR)) { emissive = vec3<f32>(1.6, 0.5, 2.4); }
        }
        if (input.info.w > 0.5) { albedo = albedo + vec3<f32>(0.5, 0.02, 0.02); }
    } else {
        var uv = input.uv;
        if (kind == 3u) { uv = (input.extra.yz + uv) / 8.0 + vec2<f32>(0.0625); }
        let s = atlasTexel(tile, uv);
        if (s.a < 0.5) { discard; }
        albedo = s.rgb;
        if (tile == 29.0) { emissive = s.rgb * smoothstep(0.35, 0.7, s.r) * 4.0; }
    }
    // Sprites are double-sided: light the side facing the camera.
    if ((kind == 1u || kind == 2u) && dot(n, input.rel) > 0.0) { n = -n; }
    let world = input.rel + frame.camera.xyz;
    let l = normalize(frame.sunDir.xyz);
    let ndl = max(dot(n, l), 0.0) * 0.85 + 0.15;
    let hemi = mix(frame.ambient.rgb * 0.55, frame.ambient.rgb, n.y * 0.5 + 0.5);
    var color = albedo * (frame.sunColor.rgb * ndl * input.extra.x + hemi + torchLight(world, n) + vec3<f32>(0.02, 0.022, 0.03)) + emissive;
    color = applyFog(color, input.rel);
    return vec4<f32>(color, length(input.rel) / DEPTH_SCALE);
}
