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
    let m = f32(mask_r8[idx] & 0xffu) / 255.0 * params.strength;
    if (m < 0.02) {
        output_rgba[idx] = input_rgba[idx];
        return;
    }
    let orig = unpack_rgba(input_rgba[idx]);
    // Warm rose multiply (matches CPU makeup.rs).
    let tr = 220.0;
    let tg = 120.0;
    let tb = 130.0;
    let blushed = vec4f(
        mix(orig.x, orig.x * tr / 255.0, m),
        mix(orig.y, orig.y * tg / 255.0, m),
        mix(orig.z, orig.z * tb / 255.0, m),
        orig.w,
    );
    output_rgba[idx] = pack_rgba(blushed);
}
