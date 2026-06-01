struct Params {
    width: u32,
    height: u32,
    radius: u32,
    strength: f32,
    preserve_detail: f32,
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
    let x = gid.x;
    let y = gid.y;
    if (x >= params.width || y >= params.height) {
        return;
    }
    let r = i32(params.radius);
    let out_idx = y * params.width + x;

    var sum = vec4f(0.0);
    var n = 0.0;
    for (var dx = -r; dx <= r; dx = dx + 1) {
        let cx = u32(clamp(i32(x) + dx, 0, i32(params.width) - 1));
        let idx = y * params.width + cx;
        sum = sum + unpack_rgba(input_rgba[idx]);
        n = n + 1.0;
    }
    output_rgba[out_idx] = pack_rgba(sum / n);
}
