//#vertex
struct PostOut { @builtin(position) position: vec4<f32>, @location(0) uv: vec2<f32> };
@vertex fn vs_main(@builtin(vertex_index) index: u32) -> PostOut {
    let x = f32((index << 1u) & 2u); let y = f32(index & 2u);
    var o: PostOut;
    o.position = vec4<f32>(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
    o.uv = vec2<f32>(x, y);
    return o;
}

//#fragment
struct UserUniforms { texel: vec4<f32>, params: vec4<f32>, params2: vec4<f32>, };
@group(1) @binding(0) var<uniform> post: UserUniforms;
@group(2) @binding(0) var source: texture_2d<f32>;
@group(2) @binding(1) var bloomTex: texture_2d<f32>;
@group(2) @binding(8) var linearSampler: sampler;
struct PostOut { @builtin(position) position: vec4<f32>, @location(0) uv: vec2<f32> };

fn tap(uv: vec2<f32>) -> vec3<f32> { return textureSampleLevel(source, linearSampler, uv, 0.0).rgb; }
fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }

// mode (params.x): 0 copy, 1 bloom prefilter+downsample, 2 downsample, 3 upsample (additive), 4 composite.
@fragment fn fs_main(input: PostOut) -> @location(0) vec4<f32> {
    let mode = post.params.x;
    let uv = input.uv;
    let t = post.texel.xy;
    if (mode < 0.5) {
        return textureSampleLevel(source, linearSampler, uv, 0.0);
    }
    if (mode < 2.5) {
        // 13-tap downsample (Jimenez 2014); the first pass applies a soft threshold and a Karis average.
        let a = tap(uv + t * vec2<f32>(-2.0, -2.0)); let b = tap(uv + t * vec2<f32>(0.0, -2.0)); let c = tap(uv + t * vec2<f32>(2.0, -2.0));
        let d = tap(uv + t * vec2<f32>(-1.0, -1.0)); let e = tap(uv + t * vec2<f32>(1.0, -1.0));
        let f = tap(uv + t * vec2<f32>(-2.0, 0.0)); let g = tap(uv); let h = tap(uv + t * vec2<f32>(2.0, 0.0));
        let i = tap(uv + t * vec2<f32>(-1.0, 1.0)); let j = tap(uv + t * vec2<f32>(1.0, 1.0));
        let k = tap(uv + t * vec2<f32>(-2.0, 2.0)); let l = tap(uv + t * vec2<f32>(0.0, 2.0)); let m = tap(uv + t * vec2<f32>(2.0, 2.0));
        var col: vec3<f32>;
        if (mode < 1.5) {
            let g0 = (d + e + i + j) * 0.25; let g1 = (a + b + f + g) * 0.25; let g2 = (b + c + g + h) * 0.25;
            let g3 = (f + g + k + l) * 0.25; let g4 = (g + h + l + m) * 0.25;
            let w0 = 1.0 / (1.0 + luma(g0)); let w1 = 1.0 / (1.0 + luma(g1)); let w2 = 1.0 / (1.0 + luma(g2));
            let w3 = 1.0 / (1.0 + luma(g3)); let w4 = 1.0 / (1.0 + luma(g4));
            col = (g0 * w0 * 0.5 + (g1 * w1 + g2 * w2 + g3 * w3 + g4 * w4) * 0.125) / (w0 * 0.5 + (w1 + w2 + w3 + w4) * 0.125);
            let threshold = post.params.y;
            let knee = threshold * 0.5;
            let br = max(col.r, max(col.g, col.b));
            var soft = clamp(br - threshold + knee, 0.0, 2.0 * knee);
            soft = soft * soft / (4.0 * knee + 1e-4);
            col *= max(soft, br - threshold) / max(br, 1e-4);
        } else {
            col = (d + e + i + j) * 0.125 + (a + c + k + m) * 0.03125 + (b + f + h + l) * 0.0625 + g * 0.125;
        }
        return vec4<f32>(max(col, vec3<f32>(0.0)), 1.0);
    }
    if (mode < 3.5) {
        // 3x3 tent upsample, added onto the next larger level.
        var col = tap(uv) * 4.0;
        col += (tap(uv + vec2<f32>(-t.x, 0.0)) + tap(uv + vec2<f32>(t.x, 0.0)) + tap(uv + vec2<f32>(0.0, -t.y)) + tap(uv + vec2<f32>(0.0, t.y))) * 2.0;
        col += tap(uv + vec2<f32>(-t.x, -t.y)) + tap(uv + vec2<f32>(t.x, -t.y)) + tap(uv + vec2<f32>(-t.x, t.y)) + tap(uv + vec2<f32>(t.x, t.y));
        return vec4<f32>(col / 16.0 * post.params.z, 1.0);
    }
    // Composite: exposure, restrained bloom, ACES filmic curve, gentle grading, vignette and dither.
    let scene = textureSampleLevel(source, linearSampler, uv, 0.0).rgb;
    let bloom = textureSampleLevel(bloomTex, linearSampler, uv, 0.0).rgb;
    let exposure = post.params.y;
    var c = (scene + bloom * post.params.z) * exposure;
    if (post.params.w > 0.5) { c *= vec3<f32>(0.75, 0.95, 1.05); }
    let A = 2.51; let B = 0.03; let C = 2.43; let D = 0.59; let E = 0.14;
    c = clamp((c * (A * c + B)) / (c * (C * c + D) + E), vec3<f32>(0.0), vec3<f32>(1.0));
    // Slight saturation lift keeps foliage rich after the filmic shoulder.
    let lum = luma(c);
    c = mix(vec3<f32>(lum), c, 1.02);
    let centre = uv - 0.5;
    c *= 1.0 - dot(centre, centre) * post.params2.x;
    c = pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
    let n = fract(52.9829189 * fract(dot(input.position.xy, vec2<f32>(0.06711056, 0.00583715))));
    c += (n - 0.5) / 255.0;
    return vec4<f32>(c, 1.0);
}
