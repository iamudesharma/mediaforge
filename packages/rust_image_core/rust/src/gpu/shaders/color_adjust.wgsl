struct Params {
    width: u32,
    height: u32,
    brightness: f32,
    contrast: f32,
    saturation: f32,
    hue_degrees: f32,
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

fn rgb_to_hsv(rgb: vec3f) -> vec3f {
    let c = rgb / 255.0;
    let max_c = max(max(c.x, c.y), c.z);
    let min_c = min(min(c.x, c.y), c.z);
    let delta = max_c - min_c;

    var h = 0.0;
    if (delta > 0.0001) {
        if (max_c == c.x) {
            h = 60.0 * (((c.y - c.z) / delta) % 6.0);
        } else if (max_c == c.y) {
            h = 60.0 * (((c.z - c.x) / delta) + 2.0);
        } else {
            h = 60.0 * (((c.x - c.y) / delta) + 4.0);
        }
    }
    if (h < 0.0) {
        h = h + 360.0;
    }
    let s = select(0.0, delta / max_c, max_c > 0.0);
    return vec3f(h, s, max_c);
}

fn hsv_to_rgb(hsv: vec3f) -> vec3f {
    let h = hsv.x;
    let s = hsv.y;
    let v = hsv.z;
    let c = v * s;
    let x = c * (1.0 - abs((h / 60.0) % 2.0 - 1.0));
    let m = v - c;

    var rgb = vec3f(0.0);
    if (h < 60.0) {
        rgb = vec3f(c, x, 0.0);
    } else if (h < 120.0) {
        rgb = vec3f(x, c, 0.0);
    } else if (h < 180.0) {
        rgb = vec3f(0.0, c, x);
    } else if (h < 240.0) {
        rgb = vec3f(0.0, x, c);
    } else if (h < 300.0) {
        rgb = vec3f(x, 0.0, c);
    } else {
        rgb = vec3f(c, 0.0, x);
    }
    return (rgb + vec3f(m)) * 255.0;
}

fn adjust_rgb(rgb: vec3f) -> vec3f {
    var c = rgb / 255.0;
    c = c + vec3f(params.brightness);
    c = (c - 0.5) * params.contrast + 0.5;
    let luma = dot(c, vec3f(0.2126, 0.7152, 0.0722));
    c = mix(vec3f(luma), c, params.saturation);

    if (abs(params.hue_degrees) > 0.001) {
        var hsv = rgb_to_hsv(clamp(c, vec3f(0.0), vec3f(1.0)) * 255.0);
        hsv.x = (hsv.x + params.hue_degrees) % 360.0;
        if (hsv.x < 0.0) {
            hsv.x = hsv.x + 360.0;
        }
        c = hsv_to_rgb(hsv) / 255.0;
    }

    return clamp(c, vec3f(0.0), vec3f(1.0)) * 255.0;
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
    let rgb = adjust_rgb(px.xyz);
    rgba[idx] = pack_rgba(vec4f(rgb, px.w));
}
