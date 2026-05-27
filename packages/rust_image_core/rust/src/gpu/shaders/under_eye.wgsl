struct Params {
    width: u32,
    height: u32,
    strength: f32,
    _pad: f32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> input_rgba: array<u32>;
@group(0) @binding(2) var<storage, read> mask_r8: array<u32>;
@group(0) @binding(3) var<storage, read_write> output_rgba: array<u32>;

fn unpack_rgba(packed: u32) -> vec4f {
    return vec4f(
        f32(packed & 0xffu),
        f32((packed >> 8u) & 0xffu),
        f32((packed >> 16u) & 0xffu),
        f32((packed >> 24u) & 0xffu),
    );
}

fn pack_rgba(c: vec4f) -> u32 {
    let r = u32(clamp(c.x, 0.0, 255.0));
    let g = u32(clamp(c.y, 0.0, 255.0));
    let b = u32(clamp(c.z, 0.0, 255.0));
    let a = u32(clamp(c.w, 0.0, 255.0));
    return r | (g << 8u) | (b << 16u) | (a << 24u);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
    let x = gid.x;
    let y = gid.y;
    if (x >= params.width || y >= params.height) {
        return;
    }
    let idx = y * params.width + x;
    let m = f32(mask_r8[idx] & 0xffu) / 255.0;
    if (m < 0.02 || params.strength <= 0.001) {
        output_rgba[idx] = input_rgba[idx];
        return;
    }
    var sum = vec4f(0.0);
    var n = 0.0;
    for (var dy = -2; dy <= 2; dy = dy + 1) {
        for (var dx = -2; dx <= 2; dx = dx + 1) {
            let cx = u32(clamp(i32(x) + dx, 0, i32(params.width) - 1));
            let cy = u32(clamp(i32(y) + dy, 0, i32(params.height) - 1));
            let j = cy * params.width + cx;
            sum = sum + unpack_rgba(input_rgba[j]);
            n = n + 1.0;
        }
    }
    let blurred = sum / n;
    let orig = unpack_rgba(input_rgba[idx]);
    let blend = clamp(m * params.strength * 0.50, 0.0, 0.50);
    output_rgba[idx] = pack_rgba(mix(orig, blurred, blend));
}
