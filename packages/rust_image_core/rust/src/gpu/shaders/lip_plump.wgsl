struct Params {
    width: u32,
    height: u32,
    strength: f32,
    lip_cx: f32,
    lip_cy: f32,
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

fn pixel_idx(xi: i32, yi: i32) -> u32 {
    return u32(yi) * params.width + u32(xi);
}

fn sample_bilinear(x: f32, y: f32) -> vec4f {
    let x0 = i32(floor(x));
    let y0 = i32(floor(y));
    let x1 = min(x0 + 1, i32(params.width) - 1);
    let y1 = min(y0 + 1, i32(params.height) - 1);
    let tx = x - f32(x0);
    let ty = y - f32(y0);
    let c00 = unpack_rgba(input_rgba[pixel_idx(x0, y0)]);
    let c10 = unpack_rgba(input_rgba[pixel_idx(x1, y0)]);
    let c01 = unpack_rgba(input_rgba[pixel_idx(x0, y1)]);
    let c11 = unpack_rgba(input_rgba[pixel_idx(x1, y1)]);
    let c0 = mix(c00, c10, tx);
    let c1 = mix(c01, c11, tx);
    return mix(c0, c1, ty);
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
    if (m < 0.05 || params.strength <= 0.001) {
        output_rgba[idx] = input_rgba[idx];
        return;
    }
    let w = f32(params.width);
    let h = f32(params.height);
    let cx = params.lip_cx * w;
    let cy = params.lip_cy * h;
    let fx = f32(x);
    let fy = f32(y);
    let dx = fx - cx;
    let dy = fy - cy;
    let dist = max(length(vec2f(dx, dy)), 1.0);
    let max_push = 0.15 * params.strength;
    let push = max_push * m * 40.0 / dist;
    let sx = clamp(fx - dx / dist * push, 0.0, w - 1.0);
    let sy = clamp(fy - dy / dist * push, 0.0, h - 1.0);
    output_rgba[idx] = pack_rgba(sample_bilinear(sx, sy));
}
