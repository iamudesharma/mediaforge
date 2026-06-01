struct Params {
    width: u32,
    height: u32,
    strength: f32,
    lut_size: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> input_rgba: array<u32>;
@group(0) @binding(2) var<storage, read_write> output_rgba: array<u32>;
@group(0) @binding(3) var<storage, read> lut_rgba: array<u32>;

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

fn lut_at(r: u32, g: u32, b: u32) -> vec3f {
    let size = params.lut_size;
    let idx = r + g * size + b * size * size;
    let px = unpack_rgba(lut_rgba[idx]);
    return px.xyz;
}

fn sample_lut_trilinear(rgb: vec3f) -> vec3f {
    let size = f32(params.lut_size);
    let max_i = params.lut_size - 1u;
    let scaled = clamp(rgb / 255.0 * size, vec3f(0.0), vec3f(size - 0.001));
    let c0 = floor(scaled);
    let c1 = min(c0 + vec3f(1.0), vec3f(f32(max_i)));
    let f = scaled - c0;

    let r0 = u32(c0.x);
    let g0 = u32(c0.y);
    let b0 = u32(c0.z);
    let r1 = u32(c1.x);
    let g1 = u32(c1.y);
    let b1 = u32(c1.z);

    let c000 = lut_at(r0, g0, b0);
    let c100 = lut_at(r1, g0, b0);
    let c010 = lut_at(r0, g1, b0);
    let c110 = lut_at(r1, g1, b0);
    let c001 = lut_at(r0, g0, b1);
    let c101 = lut_at(r1, g0, b1);
    let c011 = lut_at(r0, g1, b1);
    let c111 = lut_at(r1, g1, b1);

    let c00 = mix(c000, c100, f.x);
    let c01 = mix(c001, c101, f.x);
    let c10 = mix(c010, c110, f.x);
    let c11 = mix(c011, c111, f.x);
    let c0m = mix(c00, c10, f.y);
    let c1m = mix(c01, c11, f.y);
    return mix(c0m, c1m, f.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
    let x = gid.x;
    let y = gid.y;
    if (x >= params.width || y >= params.height) {
        return;
    }
    let idx = y * params.width + x;
    let src = unpack_rgba(input_rgba[idx]);
    let graded = sample_lut_trilinear(src.xyz);
    let t = clamp(params.strength, 0.0, 1.0);
    let out_rgb = mix(src.xyz, graded, t);
    output_rgba[idx] = pack_rgba(vec4f(out_rgb, src.w));
}
