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
    o.position = frame.shadowMat * vec4<f32>(o.rel, 1.0);
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
@group(2) @binding(8) var linearSampler: sampler;
struct Varyings {
    @builtin(position) position: vec4<f32>,
    @location(0) rel: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) info: vec4<f32>,
    @location(4) tangent: vec3<f32>,
};
// Depth is packed into two half floats (coarse + fine) for about 20 bits of precision.
@fragment fn fs_main(input: Varyings) -> @location(0) vec4<f32> {
    let tile = round(input.info.x);
    if (tile == 7.0 || tile == 13.0 || tile == 14.0 || tile == 29.0) {
        let cell = vec2<f32>(tile % 8.0, floor(tile / 8.0));
        let c = (cell * 32.0 + clamp(fract(input.uv) * 32.0, vec2<f32>(1.0), vec2<f32>(31.0))) / vec2<f32>(256.0, 128.0);
        if (textureSampleLevel(albedoTex, linearSampler, c, 1.0).a < 0.5) { discard; }
    }
    let d = input.position.z;
    let hi = floor(d * 1024.0) / 1024.0;
    return vec4<f32>(hi, fract(d * 1024.0), 0.0, 1.0);
}
