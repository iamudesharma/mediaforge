struct Params {
    width: u32,
    height: u32,
    strength: f32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> input_rgba: array<u32>;
@group(0) @binding(2) var<storage, read_write> output_rgba: array<u32>;

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

fn sample_at(x: i32, y: i32) -> vec4f {
    let cx = u32(clamp(x, 0, i32(params.width) - 1));
    let cy = u32(clamp(y, 0, i32(params.height) - 1));
    let idx = cy * params.width + cx;
    return unpack_rgba(input_rgba[idx]);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
    let x = gid.x;
    let y = gid.y;
    if (x >= params.width || y >= params.height) {
        return;
    }

    let ix = i32(x);
    let iy = i32(y);
    let center = sample_at(ix, iy);
    let left = sample_at(ix - 1, iy);
    let right = sample_at(ix + 1, iy);
    let up = sample_at(ix, iy - 1);
    let down = sample_at(ix, iy + 1);

    // Unsharp-style 4-neighbor sharpen (matches classic conv::sharpen spirit).
    let s = params.strength;
    let rgb = center.xyz * (1.0 + 4.0 * s)
        - s * (left.xyz + right.xyz + up.xyz + down.xyz);
    let out_idx = y * params.width + x;
    output_rgba[out_idx] = pack_rgba(vec4f(clamp(rgb, vec3f(0.0), vec3f(255.0)), center.w));
}
