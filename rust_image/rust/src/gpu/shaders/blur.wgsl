struct Params {
    width: u32,
    height: u32,
    radius: u32,
    dir_x: i32,
    dir_y: i32,
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

    if (r <= 0) {
        output_rgba[out_idx] = input_rgba[out_idx];
        return;
    }

    let sigma = f32(r) / 2.0;
    let two_sigma_sq = 2.0 * sigma * sigma;

    var sum = vec4f(0.0);
    var weight_sum = 0.0;

    for (var i = -r; i <= r; i = i + 1) {
        let nx = i32(x) + i * params.dir_x;
        let ny = i32(y) + i * params.dir_y;

        // Clamp coordinates to image borders
        let cx = u32(clamp(nx, 0, i32(params.width) - 1));
        let cy = u32(clamp(ny, 0, i32(params.height) - 1));

        let idx = cy * params.width + cx;
        let color = unpack_rgba(input_rgba[idx]);

        let dist = f32(i);
        let weight = exp(-(dist * dist) / two_sigma_sq);

        sum = sum + color * weight;
        weight_sum = weight_sum + weight;
    }

    output_rgba[out_idx] = pack_rgba(sum / weight_sum);
}
