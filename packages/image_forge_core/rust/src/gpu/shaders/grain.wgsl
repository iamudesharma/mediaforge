struct Params {
    width: u32,
    height: u32,
    strength: f32,
    seed: u32,
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

fn hash(p: vec2u) -> f32 {
    var h = p.x * 1664525u + p.y * 1013904223u + params.seed;
    h = h ^ (h >> 16u);
    return f32(h & 0xffffu) / 65535.0 - 0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
    let x = gid.x;
    let y = gid.y;
    if (x >= params.width || y >= params.height) {
        return;
    }
    let idx = y * params.width + x;
    let px = unpack_rgba(rgba[idx]);
    let noise = hash(vec2u(x, y)) * params.strength * 28.0;
    let rgb = clamp(px.xyz + vec3f(noise), vec3f(0.0), vec3f(255.0));
    rgba[idx] = pack_rgba(vec4f(rgb, px.w));
}
