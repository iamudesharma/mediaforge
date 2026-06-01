// RGBA-packed storage buffer → BGRA8Unorm storage texture swizzle.
//
// Reads pixels from a packed RGBA `array<u32>` (same encoding as the rest of
// the beauty pipeline) and writes them to a `bgra8unorm` storage texture so
// Flutter's `Texture` widget (which reads BGRA via `CVPixelBuffer`) sees the
// same bytes the CPU would have produced.

struct Params {
    width: u32,
    height: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> input_rgba: array<u32>;
@group(0) @binding(2) var output_bgra: texture_storage_2d<bgra8unorm, write>;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
    let x = gid.x;
    let y = gid.y;
    if (x >= params.width || y >= params.height) {
        return;
    }
    let idx = y * params.width + x;
    let packed = input_rgba[idx];
    let r = f32(packed & 0xffu);
    let g = f32((packed >> 8u) & 0xffu);
    let b = f32((packed >> 16u) & 0xffu);
    let a = f32((packed >> 24u) & 0xffu);
    // wgpu bgra8unorm writes interpret vec4.x/y/z/w as R/G/B/A in the
    // shader but store in B/G/R/A byte order. To get our input's
    // (r, g, b, a) into the buffer as (B, G, R, A), pass vec4(b, g, r, a).
    textureStore(output_bgra, vec2u(x, y), vec4f(b, g, r, a));
}
