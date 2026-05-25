struct Params {
    src_width: u32,
    src_height: u32,
    dst_width: u32,
    dst_height: u32,
    filter_nearest: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> src_rgba: array<u32>;
@group(0) @binding(2) var<storage, read_write> dst_rgba: array<u32>;

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

fn sample_bilinear(x: f32, y: f32) -> vec4f {
    let max_x = f32(params.src_width - 1u);
    let max_y = f32(params.src_height - 1u);
    let cx = clamp(x, 0.0, max_x);
    let cy = clamp(y, 0.0, max_y);

    if (params.filter_nearest == 1u) {
        let ix = u32(round(cx));
        let iy = u32(round(cy));
        let idx = iy * params.src_width + ix;
        return unpack_rgba(src_rgba[idx]);
    }

    let x0 = u32(floor(cx));
    let y0 = u32(floor(cy));
    let x1 = min(x0 + 1u, params.src_width - 1u);
    let y1 = min(y0 + 1u, params.src_height - 1u);
    let tx = cx - f32(x0);
    let ty = cy - f32(y0);

    let c00 = unpack_rgba(src_rgba[y0 * params.src_width + x0]);
    let c10 = unpack_rgba(src_rgba[y0 * params.src_width + x1]);
    let c01 = unpack_rgba(src_rgba[y1 * params.src_width + x0]);
    let c11 = unpack_rgba(src_rgba[y1 * params.src_width + x1]);

    let c0 = mix(c00, c10, tx);
    let c1 = mix(c01, c11, tx);
    return mix(c0, c1, ty);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
    let x = gid.x;
    let y = gid.y;
    if (x >= params.dst_width || y >= params.dst_height) {
        return;
    }

    let fx = (f32(x) + 0.5) * f32(params.src_width) / f32(params.dst_width) - 0.5;
    let fy = (f32(y) + 0.5) * f32(params.src_height) / f32(params.dst_height) - 0.5;
    let color = sample_bilinear(fx, fy);
    let idx = y * params.dst_width + x;
    dst_rgba[idx] = pack_rgba(color);
}
