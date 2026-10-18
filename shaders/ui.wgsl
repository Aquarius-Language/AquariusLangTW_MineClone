//#vertex
struct UserUniforms { screen: vec4<f32>, params: vec4<f32>, };
@group(1) @binding(0) var<uniform> ui: UserUniforms;
struct UiOut {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) mode: f32,
};
// Vertices use the shared 12-float layout: pixel position, (mode, 0, 0), UV, RGBA.
@vertex fn vs_main(input: VertexInput) -> UiOut {
    var o: UiOut;
    let p = input.position.xy / ui.screen.xy;
    o.position = vec4<f32>(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
    o.uv = input.texcoord;
    o.color = input.color;
    o.mode = input.normal.x;
    return o;
}

//#fragment
struct UserUniforms { screen: vec4<f32>, params: vec4<f32>, };
@group(1) @binding(0) var<uniform> ui: UserUniforms;
@group(2) @binding(0) var fontTex: texture_2d<f32>;
@group(2) @binding(1) var albedoTex: texture_2d<f32>;
@group(2) @binding(2) var itemTex: texture_2d<f32>;
@group(2) @binding(8) var linearSampler: sampler;
struct UiOut {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) mode: f32,
};
// mode 0: flat colour, 1: font glyph (exact texels), 2: block atlas (sRGB texture, already linear on sampling),
// 3: item icon atlas (pixel art, exact texels).
@fragment fn fs_main(input: UiOut) -> @location(0) vec4<f32> {
    let fsize = vec2<f32>(textureDimensions(fontTex));
    let glyph = textureLoad(fontTex, clamp(vec2<i32>(input.uv * fsize), vec2<i32>(0), vec2<i32>(fsize) - vec2<i32>(1)), 0);
    let block = textureSampleLevel(albedoTex, linearSampler, input.uv, 0.0);
    let isize = vec2<f32>(textureDimensions(itemTex));
    let icon = textureLoad(itemTex, clamp(vec2<i32>(input.uv * isize), vec2<i32>(0), vec2<i32>(isize) - vec2<i32>(1)), 0);
    var c = input.color;
    if (input.mode > 2.5) {
        c = vec4<f32>(pow(icon.rgb, vec3<f32>(1.0 / 2.2)) * input.color.rgb, icon.a * input.color.a);
    } else if (input.mode > 1.5) {
        // Atlas colours are linear; the UI target stores display values, so re-encode.
        c = vec4<f32>(pow(block.rgb, vec3<f32>(1.0 / 2.2)) * input.color.rgb, block.a * input.color.a);
    } else if (input.mode > 0.5) {
        c = vec4<f32>(input.color.rgb, input.color.a * glyph.a);
    }
    return c;
}
