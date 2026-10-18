//#vertex
// Progressive mining cracks: the six faces of the targeted block, slightly enlarged, drawn after the
// translucent pass with a manual depth test against the opaque scene (like the outline).
// frame.params2 = (progress 0..1, block min x, y, z relative to the camera).
struct CrackOut { @builtin(position) position: vec4<f32>, @location(0) rel: vec3<f32>, @location(1) uv: vec2<f32>, @location(2) face: f32 };

@vertex fn vs_main(@builtin(vertex_index) index: u32) -> CrackOut {
    let face = index / 6u;
    var corners = array<vec2<f32>, 6>(vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 0.0), vec2<f32>(1.0, 1.0),
                                      vec2<f32>(0.0, 0.0), vec2<f32>(1.0, 1.0), vec2<f32>(0.0, 1.0));
    let c = corners[index % 6u];
    var n = vec3<f32>(0.0); var u = vec3<f32>(0.0); var v = vec3<f32>(0.0);
    if (face == 0u) { n = vec3<f32>(1.0, 0.0, 0.0); u = vec3<f32>(0.0, 0.0, -1.0); v = vec3<f32>(0.0, 1.0, 0.0); }
    else if (face == 1u) { n = vec3<f32>(-1.0, 0.0, 0.0); u = vec3<f32>(0.0, 0.0, 1.0); v = vec3<f32>(0.0, 1.0, 0.0); }
    else if (face == 2u) { n = vec3<f32>(0.0, 1.0, 0.0); u = vec3<f32>(1.0, 0.0, 0.0); v = vec3<f32>(0.0, 0.0, -1.0); }
    else if (face == 3u) { n = vec3<f32>(0.0, -1.0, 0.0); u = vec3<f32>(1.0, 0.0, 0.0); v = vec3<f32>(0.0, 0.0, 1.0); }
    else if (face == 4u) { n = vec3<f32>(0.0, 0.0, 1.0); u = vec3<f32>(1.0, 0.0, 0.0); v = vec3<f32>(0.0, 1.0, 0.0); }
    else { n = vec3<f32>(0.0, 0.0, -1.0); u = vec3<f32>(-1.0, 0.0, 0.0); v = vec3<f32>(0.0, 1.0, 0.0); }
    let local = (n * 0.5 + u * (c.x - 0.5) + v * (c.y - 0.5)) * 1.004 + vec3<f32>(0.5);
    var o: CrackOut;
    o.rel = frame.params2.yzw + local;
    o.position = frame.viewProj * vec4<f32>(o.rel, 1.0);
    o.uv = c;
    o.face = f32(face);
    return o;
}

//#fragment
@group(2) @binding(3) var sceneTex: texture_2d<f32>;
struct CrackOut { @builtin(position) position: vec4<f32>, @location(0) rel: vec3<f32>, @location(1) uv: vec2<f32>, @location(2) face: f32 };

@fragment fn fs_main(input: CrackOut) -> @location(0) vec4<f32> {
    let size = vec2<f32>(textureDimensions(sceneTex));
    let p = clamp(vec2<i32>(input.position.xy), vec2<i32>(0), vec2<i32>(size) - vec2<i32>(1));
    let behind = textureLoad(sceneTex, p, 0).a * DEPTH_SCALE;
    if (length(input.rel) > behind + 0.06) { discard; }
    let progress = frame.params2.x;
    // Pixel-art cracks on a 16x16 grid: Voronoi cell borders revealed outward from the centre as
    // the block weakens, in ten visible stages.
    let stage = floor(progress * 10.0) / 10.0;
    let px = (floor(input.uv * 16.0) + 0.5) / 16.0;
    var d1 = 9.0; var d2 = 9.0; var id1 = 0.0; var id2 = 0.0;
    for (var j = -1; j <= 3; j++) {
        for (var i = -1; i <= 3; i++) {
            let cell = vec2<f32>(f32(i), f32(j));
            let h = hash21(cell + input.face * 7.31);
            let pt = (cell + vec2<f32>(h, hash21(cell * 1.7 + 3.1 + input.face))) / 3.0;
            let d = length(px - pt);
            let id = cell.x * 5.0 + cell.y + 11.0;
            if (d < d1) { d2 = d1; id2 = id1; d1 = d; id1 = id; } else if (d < d2) { d2 = d; id2 = id; }
        }
    }
    let edge = (d2 - d1) < 0.06;
    let reveal = hash21(vec2<f32>(min(id1, id2), max(id1, id2)) + input.face * 3.0) * 0.6 + length(px - 0.5) * 0.8;
    if (!edge || reveal > stage * 1.25 + 0.05) { discard; }
    // Dark fissures; the newest (outermost) ones are slightly fainter.
    let fresh = clamp((stage * 1.25 + 0.05 - reveal) * 6.0, 0.4, 1.0);
    return vec4<f32>(0.0, 0.0, 0.0, 0.78 * fresh);
}
