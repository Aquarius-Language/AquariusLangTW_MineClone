//#vertex
struct OutlineOut { @builtin(position) position: vec4<f32>, @location(0) rel: vec3<f32> };
// Twelve cube edges, each a screen-space ribbon of constant pixel width (6 vertices per edge).
@vertex fn vs_main(@builtin(vertex_index) index: u32) -> OutlineOut {
    let edge = index / 6u; let k = index % 6u;
    var ends = array<vec3<f32>, 24>(
        vec3<f32>(0.0,0.0,0.0), vec3<f32>(1.0,0.0,0.0), vec3<f32>(0.0,1.0,0.0), vec3<f32>(1.0,1.0,0.0),
        vec3<f32>(0.0,0.0,1.0), vec3<f32>(1.0,0.0,1.0), vec3<f32>(0.0,1.0,1.0), vec3<f32>(1.0,1.0,1.0),
        vec3<f32>(0.0,0.0,0.0), vec3<f32>(0.0,1.0,0.0), vec3<f32>(1.0,0.0,0.0), vec3<f32>(1.0,1.0,0.0),
        vec3<f32>(0.0,0.0,1.0), vec3<f32>(0.0,1.0,1.0), vec3<f32>(1.0,0.0,1.0), vec3<f32>(1.0,1.0,1.0),
        vec3<f32>(0.0,0.0,0.0), vec3<f32>(0.0,0.0,1.0), vec3<f32>(1.0,0.0,0.0), vec3<f32>(1.0,0.0,1.0),
        vec3<f32>(0.0,1.0,0.0), vec3<f32>(0.0,1.0,1.0), vec3<f32>(1.0,1.0,0.0), vec3<f32>(1.0,1.0,1.0));
    let grow = 0.004;
    let a = frame.params2.yzw + (ends[edge * 2u] - 0.5) * (1.0 + grow * 2.0) + 0.5;
    let b = frame.params2.yzw + (ends[edge * 2u + 1u] - 0.5) * (1.0 + grow * 2.0) + 0.5;
    let ca = frame.viewProj * vec4<f32>(a, 1.0);
    let cb = frame.viewProj * vec4<f32>(b, 1.0);
    let sa = ca.xy / max(ca.w, 1e-3); let sb = cb.xy / max(cb.w, 1e-3);
    var dir = (sb - sa) * frame.screen.xy;
    dir = normalize(dir + vec2<f32>(1e-5));
    let perp = vec2<f32>(-dir.y, dir.x) * 1.6 * frame.screen.zw * 2.0;
    var side = array<f32, 6>(-1.0, 1.0, 1.0, -1.0, 1.0, -1.0);
    var useB = array<u32, 6>(0u, 0u, 1u, 0u, 1u, 1u);
    let pick = useB[k];
    var c = select(ca, cb, pick == 1u);
    c = vec4<f32>(c.xy + perp * side[k] * c.w, c.z, c.w);
    var o: OutlineOut;
    o.position = c;
    o.rel = select(a, b, pick == 1u);
    return o;
}

//#fragment
@group(2) @binding(3) var sceneTex: texture_2d<f32>;
struct OutlineOut { @builtin(position) position: vec4<f32>, @location(0) rel: vec3<f32> };
@fragment fn fs_main(input: OutlineOut) -> @location(0) vec4<f32> {
    let size = vec2<f32>(textureDimensions(sceneTex));
    let p = clamp(vec2<i32>(input.position.xy), vec2<i32>(0), vec2<i32>(size) - vec2<i32>(1));
    let behind = textureLoad(sceneTex, p, 0).a * DEPTH_SCALE;
    if (length(input.rel) > behind + 0.08) { discard; }
    return vec4<f32>(0.02, 0.02, 0.025, 0.55);
}
