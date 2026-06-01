struct Params {
    width: u32,
    height: u32,
    amount: f32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read_write> rgba: array<u32>;

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
    let x = gid.x;
    let y = gid.y;
    if (x >= params.width || y >= params.height) {
        return;
    }
    let a = clamp(params.amount, 0.0, 1.0);
    if (a < 0.001) {
        return;
    }

    let w = f32(params.width);
    let h = f32(params.height);
    let cx = w * 0.5;
    let cy = h * 0.5;
    let max_r = sqrt(cx * cx + cy * cy);

    let dx = f32(x) - cx;
    let dy = f32(y) - cy;
    let dist = sqrt(dx * dx + dy * dy) / max_r;
    let darken = clamp(dist * dist * a * 0.85, 0.0, 0.95);

    let idx = y * params.width + x;
    let px = unpack_rgba(rgba[idx]);
    let factor = 1.0 - darken;
    let rgb = px.xyz * factor;
    rgba[idx] = pack_rgba(vec4f(rgb, px.w));
}
