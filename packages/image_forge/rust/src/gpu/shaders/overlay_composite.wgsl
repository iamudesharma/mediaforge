struct Params {
    width: u32,
    height: u32,
    opacity: f32,
    blend_mode: u32, // 0 normal, 1 multiply, 2 screen
    _pad: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> base_rgba: array<u32>;
@group(0) @binding(2) var<storage, read> overlay_rgba: array<u32>;
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

fn blend(base: vec4f, over: vec4f, mode: u32) -> vec4f {
    let a = over.w * params.opacity;
    if (a < 0.001) {
        return base;
    }
    var src = vec3f(over.x, over.y, over.z);
    let dst = vec3f(base.x, base.y, base.z);
    if (mode == 1u) {
        src = src * dst / 255.0;
    } else if (mode == 2u) {
        src = 255.0 - (255.0 - src) * (255.0 - dst) / 255.0;
    }
    let out_rgb = dst * (1.0 - a) + src * a;
    return vec4f(out_rgb, base.w);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
    let x = gid.x;
    let y = gid.y;
    if (x >= params.width || y >= params.height) {
        return;
    }
    let idx = y * params.width + x;
    let base = unpack_rgba(base_rgba[idx]);
    let over = unpack_rgba(overlay_rgba[idx]);
    output_rgba[idx] = pack_rgba(blend(base, over, params.blend_mode));
}
