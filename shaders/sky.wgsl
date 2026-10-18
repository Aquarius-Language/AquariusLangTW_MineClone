//#vertex
struct SkyOut { @builtin(position) position: vec4<f32>, @location(0) ndc: vec2<f32> };
@vertex fn vs_main(@builtin(vertex_index) index: u32) -> SkyOut {
    let x = f32((index << 1u) & 2u); let y = f32(index & 2u);
    var o: SkyOut;
    o.position = vec4<f32>(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
    o.ndc = vec2<f32>(x * 2.0 - 1.0, 1.0 - y * 2.0);
    return o;
}

//#fragment
struct SkyOut { @builtin(position) position: vec4<f32>, @location(0) ndc: vec2<f32> };

fn cloudDensity(p: vec2<f32>, t: f32) -> f32 {
    let wind = vec2<f32>(t * 1.6, t * 0.6);
    let q = (p + wind) * 0.0045;
    let base = fbm2(q, select(3, 5, frame.params.y > 0.5));
    let coverage = frame.params2.x;
    return smoothstep(1.0 - coverage, 1.0 - coverage + 0.32, base);
}

@fragment fn fs_main(input: SkyOut) -> @location(0) vec4<f32> {
    let far = frame.invViewProj * vec4<f32>(input.ndc, 1.0, 1.0);
    let dir = normalize(far.xyz / far.w);
    var col = skyColor(dir, true);
    let night = frame.params2.w;
    // Stars fade in at night and twinkle slowly.
    if (night > 0.01 && dir.y > 0.0) {
        let cell = floor(dir * 420.0);
        let h = hash31(cell);
        let twinkle = 0.7 + 0.3 * sin(frame.camera.w * (1.0 + h * 3.0) + h * 40.0);
        let star = smoothstep(0.9975, 1.0, h) * twinkle * night * smoothstep(0.0, 0.25, dir.y);
        col += vec3<f32>(0.9, 0.95, 1.1) * star * 2.5;
    }
    // A single cloud layer: ray/plane intersection, fbm density, sun-facing lighting.
    if (dir.y > 0.01) {
        let height = 190.0 - frame.camera.y;
        let dist = height / dir.y;
        let p = frame.camera.xz + dir.xz * dist;
        let t = frame.camera.w;
        let d = cloudDensity(p, t);
        if (d > 0.001) {
            let sun = normalize(frame.sunDir.xyz);
            let toward = cloudDensity(p + sun.xz * 22.0, t);
            let light = clamp(1.0 - toward * 0.75, 0.25, 1.0);
            let day = frame.sunDir.w;
            let lit = frame.sunColor.rgb * light * 0.55 + frame.ambient.rgb * 0.9;
            let silver = pow(max(dot(dir, sun), 0.0), 8.0) * 0.6 * day;
            var cloud = lit * (0.85 + silver) + vec3<f32>(0.01, 0.012, 0.02) * night;
            // Thin out toward the horizon so distant cloud sheets do not wash out the sky gradient.
            let fade = exp(-dist * 0.0011) * smoothstep(0.02, 0.22, dir.y);
            cloud = mix(cloud, col * 1.3, 0.25);
            col = mix(col, cloud, d * 0.92 * fade);
        }
    }
    if (frame.params.x > 0.5) { col = vec3<f32>(0.02, 0.09, 0.13) * (0.25 + frame.sunDir.w); }
    return vec4<f32>(col, 1.0);
}
