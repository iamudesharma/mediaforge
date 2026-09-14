// GPU video enhancement passes (experimental).
//
// Two stages, both simple compute kernels over a BGRA8 storage texture:
//
//   scale_h / scale_v  — separable resampling (Catmull-Rom or Lanczos-3)
//   sharpen            — contrast-adaptive unsharp + optional output dither
//
// All textures are `bgra8unorm`, so the shader always works in logical RGBA
// order and Metal handles the channel swizzle. That is what keeps the decode
// IOSurface → enhancement → presentation path free of CPU copies and RGBA
// round-trips.
//
// Colour notes: the shader is transfer-function agnostic and never converts
// colour space. It works on whatever the decoder already produced (8-bit
// display-referred BGRA today), so an HDR source is not silently tone-mapped
// here — that decision belongs to the decode/transfer stage.

struct Params {
    src_w: u32,
    src_h: u32,
    dst_w: u32,
    dst_h: u32,
    // 1 = Catmull-Rom (4 taps), 2 = Lanczos-3 (6 taps).
    // (`filter` is a WGSL reserved keyword — hence `filter_kind`.)
    filter_kind: u32,
    // Contrast-adaptive sharpening strength, 0.0 ..= 1.0.
    sharpen: f32,
    // Output dither amplitude in LSB (0.0 disables the dither stage).
    dither: f32,
    _pad: f32,
};

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var src_tex: texture_2d<f32>;
@group(0) @binding(2) var dst_tex: texture_storage_2d<bgra8unorm, write>;

const FILTER_CATMULL_ROM: u32 = 1u;
const FILTER_LANCZOS3: u32 = 2u;
const TAPS: u32 = 6u;
const PI: f32 = 3.141592653589793;

// Uniform Catmull-Rom (B = 0, C = 0.5). Support (-2, 2), so taps -1..2.
fn catmull_rom(s: f32) -> f32 {
    let x = abs(s);
    if (x >= 2.0) {
        return 0.0;
    }
    if (x >= 1.0) {
        return -0.5 * x * x * x + 2.5 * x * x - 4.0 * x + 2.0;
    }
    return 1.5 * x * x * x - 2.5 * x * x + 1.0;
}

// Lanczos-3. Support (-3, 3), so taps -2..3.
fn lanczos3(s: f32) -> f32 {
    let x = abs(s);
    if (x < 1e-6) {
        return 1.0;
    }
    if (x >= 3.0) {
        return 0.0;
    }
    let px = PI * x;
    return (sin(px) / px) * (sin(px / 3.0) / (px / 3.0));
}

fn kernel(s: f32) -> f32 {
    if (params.filter_kind == FILTER_LANCZOS3) {
        return lanczos3(s);
    }
    return catmull_rom(s);
}

fn tap_offset(i: u32) -> f32 {
    // Catmull-Rom uses -1..2; Lanczos-3 uses -2..3. Both live inside the
    // 6-tap window below, and out-of-support taps evaluate to 0.
    if (params.filter_kind == FILTER_LANCZOS3) {
        return f32(i) - 2.0;
    }
    return f32(i) - 1.0;
}

fn store_pixel(coord: vec2<i32>, rgb: vec3<f32>) {
    textureStore(
        dst_tex,
        coord,
        vec4<f32>(clamp(rgb, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0),
    );
}

// Horizontal resample. Destination is (dst_w, src_h): rows pass through 1:1.
@compute @workgroup_size(8, 8)
fn scale_h(@builtin(global_invocation_id) gid: vec3<u32>) {
    if (gid.x >= params.dst_w || gid.y >= params.src_h) {
        return;
    }
    let y = i32(gid.y);
    let max_x = i32(params.src_w) - 1;
    // Continuous source coordinate of this output pixel centre.
    let sx = (f32(gid.x) + 0.5) * f32(params.src_w) / f32(params.dst_w) - 0.5;
    let base = floor(sx);

    var acc = vec3<f32>(0.0);
    var wsum = 0.0;
    for (var i = 0u; i < TAPS; i = i + 1u) {
        let off = tap_offset(i);
        let w = kernel(sx - (base + off));
        if (w != 0.0) {
            let x = clamp(i32(base) + i32(off), 0, max_x);
            acc = acc + textureLoad(src_tex, vec2<i32>(x, y), 0).rgb * w;
            wsum = wsum + w;
        }
    }
    if (wsum == 0.0) {
        // Degenerate kernel (uniform input) — fall back to nearest.
        acc = textureLoad(src_tex, vec2<i32>(clamp(i32(base), 0, max_x), y), 0).rgb;
        wsum = 1.0;
    }
    store_pixel(vec2<i32>(i32(gid.x), y), acc / wsum);
}

// Vertical resample. Destination is (src_w, dst_h): columns pass through 1:1.
@compute @workgroup_size(8, 8)
fn scale_v(@builtin(global_invocation_id) gid: vec3<u32>) {
    if (gid.x >= params.src_w || gid.y >= params.dst_h) {
        return;
    }
    let x = i32(gid.x);
    let max_y = i32(params.src_h) - 1;
    let sy = (f32(gid.y) + 0.5) * f32(params.src_h) / f32(params.dst_h) - 0.5;
    let base = floor(sy);

    var acc = vec3<f32>(0.0);
    var wsum = 0.0;
    for (var i = 0u; i < TAPS; i = i + 1u) {
        let off = tap_offset(i);
        let w = kernel(sy - (base + off));
        if (w != 0.0) {
            let y = clamp(i32(base) + i32(off), 0, max_y);
            acc = acc + textureLoad(src_tex, vec2<i32>(x, y), 0).rgb * w;
            wsum = wsum + w;
        }
    }
    if (wsum == 0.0) {
        acc = textureLoad(src_tex, vec2<i32>(x, clamp(i32(base), 0, max_y)), 0).rgb;
        wsum = 1.0;
    }
    store_pixel(vec2<i32>(x, i32(gid.y)), acc / wsum);
}

fn load_rgb(coord: vec2<i32>) -> vec3<f32> {
    let c = clamp(
        coord,
        vec2<i32>(0, 0),
        vec2<i32>(i32(params.src_w) - 1, i32(params.src_h) - 1),
    );
    return textureLoad(src_tex, c, 0).rgb;
}

fn luminance(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn hash2(p: vec2<i32>) -> f32 {
    var h = u32(p.x) * 374761393u + u32(p.y) * 668265263u;
    h = (h ^ (h >> 13u)) * 1274126177u;
    h = h ^ (h >> 16u);
    return f32(h & 0xFFFFFFu) / f32(0xFFFFFFu);
}

// Contrast-adaptive unsharp mask plus optional triangular dither.
//
// The amount is gated by local contrast, so flat areas get the full detail
// lift while already-contrasty edges are left alone. That is what keeps film
// grain from being amplified into noise and avoids halos on hard edges.
@compute @workgroup_size(8, 8)
fn sharpen(@builtin(global_invocation_id) gid: vec3<u32>) {
    if (gid.x >= params.dst_w || gid.y >= params.dst_h) {
        return;
    }
    let dst = vec2<i32>(i32(gid.x), i32(gid.y));
    // The sharpen stage always runs at the final resolution and reads a
    // same-sized source (either the scaler output or the untouched input).
    let src = vec2<i32>(
        clamp(
            i32((f32(dst.x) + 0.5) * f32(params.src_w) / f32(params.dst_w)),
            0,
            i32(params.src_w) - 1,
        ),
        clamp(
            i32((f32(dst.y) + 0.5) * f32(params.src_h) / f32(params.dst_h)),
            0,
            i32(params.src_h) - 1,
        ),
    );

    let a = load_rgb(src + vec2<i32>(-1, -1));
    let b = load_rgb(src + vec2<i32>(0, -1));
    let c = load_rgb(src + vec2<i32>(1, -1));
    let d = load_rgb(src + vec2<i32>(-1, 0));
    let e = load_rgb(src);
    let f = load_rgb(src + vec2<i32>(1, 0));
    let g = load_rgb(src + vec2<i32>(-1, 1));
    let h = load_rgb(src + vec2<i32>(0, 1));
    let i = load_rgb(src + vec2<i32>(1, 1));

    var detail = vec3<f32>(0.0);
    var amount = 0.0;
    if (params.sharpen > 0.0) {
        // 4-neighbour blur with unit DC gain, so the mask adds no brightness.
        let blur = (b + d + f + h) * 0.25;
        detail = e - blur;
        let lo = min(
            min(min(luminance(a), luminance(b)), min(luminance(c), luminance(d))),
            min(min(luminance(e), luminance(f)), min(luminance(g), luminance(h))),
        );
        let hi = max(
            max(max(luminance(a), luminance(b)), max(luminance(c), luminance(d))),
            max(max(luminance(e), luminance(f)), max(luminance(g), luminance(h))),
        );
        let contrast = max(hi, luminance(i)) - min(lo, luminance(i));
        // Full strength in smooth areas, tapering to nothing on hard edges.
        let gate = 1.0 - smoothstep(0.10, 0.50, contrast);
        amount = params.sharpen * 2.0 * gate;
    }

    var out_rgb = e + detail * amount;

    if (params.dither > 0.0) {
        // Triangular noise (±1 LSB) turns quantization steps into a fine
        // dither, which is what suppresses banding in smooth gradients.
        let n = (hash2(dst) + hash2(dst + vec2<i32>(1, 7))) - 1.0;
        out_rgb = out_rgb + vec3<f32>(n * params.dither / 255.0);
    }

    store_pixel(dst, out_rgb);
}
