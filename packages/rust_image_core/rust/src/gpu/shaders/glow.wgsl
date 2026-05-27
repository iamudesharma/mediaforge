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

fn luma(c: vec4f) -> f32 {
    return dot(c.xyz, vec3f(0.299, 0.587, 0.114)) / 255.0;
}

fn gate_luma(c: vec4f) -> vec3f {
    let lum = luma(c);
    if (lum < 0.55) {
        return vec3f(0.0);
    }
    let factor = clamp((lum - 0.55) / 0.45, 0.0, 1.0);
    return c.xyz * factor;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
    let x = gid.x;
    let y = gid.y;
    if (x >= params.width || y >= params.height) {
        return;
    }
    let idx = y * params.width + x;
    let orig = unpack_rgba(input_rgba[idx]);
    
    // Gaussian weights for radius 5 (standard deviation 2.5)
    let w = array<f32, 6>(0.164, 0.151, 0.119, 0.080, 0.046, 0.022);
    
    var blurred = vec3f(0.0);
    var weight_sum = 0.0;
    
    for (var i = -5; i <= 5; i = i + 1) {
        let weight = w[abs(i)];
        
        // Horizontal sample
        let cx = u32(clamp(i32(x) + i, 0, i32(params.width) - 1));
        let idx_h = y * params.width + cx;
        let px_h = unpack_rgba(input_rgba[idx_h]);
        blurred = blurred + gate_luma(px_h) * weight;
        weight_sum = weight_sum + weight;
        
        // Vertical sample
        let cy = u32(clamp(i32(y) + i, 0, i32(params.height) - 1));
        let idx_v = cy * params.width + x;
        let px_v = unpack_rgba(input_rgba[idx_v]);
        blurred = blurred + gate_luma(px_v) * weight;
        weight_sum = weight_sum + weight;
    }
    
    let bloom = (blurred / weight_sum) / 255.0; // normalize
    let bloom_factor = params.strength * 0.8;
    
    let base = orig.xyz / 255.0;
    let bloom_scaled = bloom * bloom_factor;
    
    // Screen blend: 1 - (1 - base) * (1 - bloom)
    let blended = 1.0 - (1.0 - base) * (1.0 - bloom_scaled);
    let final_rgb = blended * 255.0;
    
    output_rgba[idx] = pack_rgba(vec4f(final_rgb, orig.w));
}
