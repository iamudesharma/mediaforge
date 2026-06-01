struct Params {
    width: u32,
    height: u32,
    radius: u32,
    strength: f32,
    preserve_detail: f32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> horiz_blurred: array<u32>;
@group(0) @binding(2) var<storage, read> mask_r8: array<u32>;
@group(0) @binding(3) var<storage, read_write> original_and_output: array<u32>;

fn unpack_rgba(packed: u32) -> vec4f {
    let r = f32(packed & 0xffu);
    let g = f32((packed >> 8u) & 0xffu);
    let b = f32((packed >> 16u) & 0xffu);
    let a = f32((packed >> 24u) & 0xffu);
    return vec4f(r, g, b, a);
}

fn pack_rgba(c: vec4f) -> u32 {
    let r = u32(clamp(c.x, 0.0, 255.0));
    let g = u32(clamp(c.y, 0.0, 255.0));
    let b = u32(clamp(c.z, 0.0, 255.0));
    let a = u32(clamp(c.w, 0.0, 255.0));
    return r | (g << 8u) | (b << 16u) | (a << 24u);
}

fn mask_at(x: u32, y: u32) -> f32 {
    let idx = y * params.width + x;
    let packed = mask_r8[idx];
    return f32(packed & 0xffu) / 255.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
    let x = gid.x;
    let y = gid.y;
    if (x >= params.width || y >= params.height) {
        return;
    }
    let r = i32(params.radius);
    let out_idx = y * params.width + x;
    let m = mask_at(x, y);

    if (m < 0.02 || params.strength <= 0.001) {
        return;
    }

    var sum = vec4f(0.0);
    var n = 0.0;
    for (var dy = -r; dy <= r; dy = dy + 1) {
        let cy = u32(clamp(i32(y) + dy, 0, i32(params.height) - 1));
        let idx = cy * params.width + x;
        sum = sum + unpack_rgba(horiz_blurred[idx]);
        n = n + 1.0;
    }
    let blurred = sum / n;
    let orig = unpack_rgba(original_and_output[out_idx]);
    let max_blend = 0.48;
    let preserve = clamp(params.preserve_detail, 0.0, 1.0);
    let blend_cap = params.strength * max_blend * (1.0 - preserve * 0.35);
    let blend = clamp(m * blend_cap, 0.0, max_blend);
    original_and_output[out_idx] = pack_rgba(mix(orig, blurred, blend));
}
