use std::time::{Duration, Instant};

use crate::api::image::{
    DrawLine, ImageFilter, OutputFormat, PreviewQuality, ProcessingBackend,
    ResizeAlgorithm, RgbaImageBuffer, TextOverlay,
};
use crate::{buffer, decode, filters, resize, thumbnail, utils};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BenchBackend {
    Cpu,
    Gpu,
    Na,
}

impl BenchBackend {
    pub fn label(self) -> &'static str {
        match self {
            BenchBackend::Cpu => "cpu",
            BenchBackend::Gpu => "gpu",
            BenchBackend::Na => "n/a",
        }
    }

    pub fn to_processing(self) -> Option<ProcessingBackend> {
        match self {
            BenchBackend::Cpu => Some(ProcessingBackend::Cpu),
            BenchBackend::Gpu => Some(ProcessingBackend::Gpu),
            BenchBackend::Na => None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct BenchStats {
    pub name: String,
    pub backend: BenchBackend,
    pub iterations: u32,
    pub mean_ms: f64,
    pub median_ms: f64,
    pub p95_ms: f64,
    pub min_ms: f64,
    pub max_ms: f64,
    pub path: String,
}

#[derive(Debug, Clone)]
pub struct BenchReport {
    pub image_label: String,
    pub width: u32,
    pub height: u32,
    pub iterations: u32,
    pub warmup_iterations: u32,
    pub build_profile: String,
    pub rayon_threads: String,
    pub runtime_flags: String,
    pub gpu_available: bool,
    pub rows: Vec<BenchStats>,
}

pub struct BenchConfig {
    pub iterations: u32,
    pub warmup_iterations: u32,
    pub cooldown_ms: u64,
    pub preview_max_edge: u32,
    pub jpeg_quality: u8,
    pub preview_profiles: PreviewProfileMode,
    pub only: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PreviewProfileMode {
    Fast,
    Quality,
    Both,
}

impl Default for BenchConfig {
    fn default() -> Self {
        Self {
            iterations: 10,
            warmup_iterations: 1,
            cooldown_ms: 0,
            preview_max_edge: 1280,
            jpeg_quality: 85,
            preview_profiles: PreviewProfileMode::Both,
            only: None,
        }
    }
}

pub fn matches_only(name: &str, only: Option<&str>) -> bool {
    match only {
        None => true,
        Some(filter) => {
            name == filter || name.contains(filter) || filter.contains(name)
        }
    }
}

pub fn build_profile_label() -> String {
    if cfg!(debug_assertions) {
        "debug".into()
    } else {
        "release".into()
    }
}

pub fn rayon_threads_label() -> String {
    std::env::var("RAYON_NUM_THREADS").unwrap_or_else(|_| "default".into())
}

pub fn run_all(image_bytes: &[u8], config: &BenchConfig) -> Result<BenchReport, String> {
    crate::runtime::configure_runtime();
    let info = decode::probe(image_bytes)?;
    let gpu_available = crate::backend::gpu_available();
    let only = config.only.as_deref();

    let mut rows = Vec::new();

    push_bytes(
        &mut rows, config, only, "probe_image", BenchBackend::Na, image_bytes,
        |_| { let _ = decode::probe(image_bytes)?; Ok(()) },
    )?;

    push_bytes(
        &mut rows, config, only, "decode_jpeg", BenchBackend::Na, image_bytes,
        |b| { let _ = utils::decode(b)?; Ok(()) },
    )?;

    push_bytes(
        &mut rows, config, only, "compress_jpeg", BenchBackend::Na, image_bytes,
        |b| {
            let img = utils::decode(b)?;
            let _ = crate::compress::encode_jpeg(&img, config.jpeg_quality)?;
            Ok(())
        },
    )?;

    push_bytes(
        &mut rows, config, only, "decode_to_rgba", BenchBackend::Na, image_bytes,
        |b| { let _ = buffer::decode_to_rgba(b, true, None)?; Ok(()) },
    )?;

    push_bytes(
        &mut rows, config, only, "decode_progressive", BenchBackend::Na, image_bytes,
        |b| { let _ = decode::decode_progressive(b, config.preview_max_edge, true)?; Ok(()) },
    )?;

    push_bytes(
        &mut rows, config, only, "apply_filter_blur_bytes", BenchBackend::Na, image_bytes,
        |b| {
            let img = utils::decode(b)?;
            let buf = RgbaImageBuffer::from_dynamic(img);
            let _ = filters::apply_rgba(buf, ImageFilter::Blur { radius: 4 })?;
            Ok(())
        },
    )?;

    push_bytes(
        &mut rows, config, only, "crop_image", BenchBackend::Na, image_bytes,
        |b| {
            let img = utils::decode(b)?;
            let w = img.width() / 2;
            let h = img.height() / 2;
            let _ = crate::crop::crop(img, w / 4, h / 4, w, h)?;
            Ok(())
        },
    )?;

    push_bytes(
        &mut rows, config, only, "rotate_image_90", BenchBackend::Na, image_bytes,
        |b| {
            let img = utils::decode(b)?;
            let _ = crate::rotate::rotate(img, crate::api::image::Rotation::Rotate90);
            Ok(())
        },
    )?;

    for backend in [BenchBackend::Cpu, BenchBackend::Gpu] {
        if backend == BenchBackend::Gpu && !gpu_available {
            continue;
        }
        let pb = backend.to_processing().unwrap();

        push_bytes(
            &mut rows, config, only, "resize_image_50pct", backend, image_bytes,
            |b| {
                let img = utils::decode(b)?;
                let w = (img.width() / 2).max(1);
                let h = (img.height() / 2).max(1);
                let resized = resize::resize(img, w, h, ResizeAlgorithm::Lanczos3, pb)?;
                let _ = crate::compress::encode_jpeg(&resized, config.jpeg_quality)?;
                Ok(())
            },
        )?;

        push_bytes(
            &mut rows, config, only, "thumbnail_512", backend, image_bytes,
            |b| {
                let _ = thumbnail::thumbnail(
                    b, 512, OutputFormat::Jpeg, config.jpeg_quality,
                    ResizeAlgorithm::Lanczos3, pb,
                )?;
                Ok(())
            },
        )?;
    }

    for backend in [BenchBackend::Cpu, BenchBackend::Gpu] {
        if backend == BenchBackend::Gpu && !gpu_available {
            continue;
        }
        let pb = backend.to_processing().unwrap();

        push_rgba(
            &mut rows, config, only, "resize_rgba_50pct", backend, image_bytes,
            |buf| {
                let w = (buf.width / 2).max(1);
                let h = (buf.height / 2).max(1);
                let _ = buffer::resize_rgba(buf, w, h, ResizeAlgorithm::Lanczos3, pb)?;
                Ok(())
            },
        )?;

        push_rgba(
            &mut rows, config, only, "filter_rgba_blur", backend, image_bytes,
            |buf| {
                let _ = buffer::filter_rgba_with_backend(buf, ImageFilter::Blur { radius: 4 }, pb)?;
                Ok(())
            },
        )?;

        push_rgba(
            &mut rows, config, only, "filter_rgba_sharpen", backend, image_bytes,
            |buf| {
                let _ = buffer::filter_rgba_with_backend(buf, ImageFilter::Sharpen, pb)?;
                Ok(())
            },
        )?;

        push_rgba(
            &mut rows, config, only, "filter_rgba_brightness", backend, image_bytes,
            |buf| {
                let _ = buffer::filter_rgba_with_backend(buf, ImageFilter::Brightness { amount: 25 }, pb)?;
                Ok(())
            },
        )?;

        push_rgba(
            &mut rows, config, only, "filter_rgba_contrast", backend, image_bytes,
            |buf| {
                let _ = buffer::filter_rgba_with_backend(buf, ImageFilter::Contrast { amount: 1.2 }, pb)?;
                Ok(())
            },
        )?;

        push_rgba(
            &mut rows, config, only, "filter_rgba_saturation", backend, image_bytes,
            |buf| {
                let _ = buffer::filter_rgba_with_backend(buf, ImageFilter::Saturation { amount: 1.3 }, pb)?;
                Ok(())
            },
        )?;

        push_rgba(
            &mut rows, config, only, "filter_rgba_vignette", backend, image_bytes,
            |buf| {
                let _ = buffer::filter_rgba_with_backend(buf, ImageFilter::Vignette { amount: 0.45 }, pb)?;
                Ok(())
            },
        )?;
    }

    if matches!(config.preview_profiles, PreviewProfileMode::Fast | PreviewProfileMode::Both) {
        push_rgba(
            &mut rows, config, only, "encode_rgba_preview_fast", BenchBackend::Na, image_bytes,
            |buf| {
                let _ = buffer::encode_rgba_preview(buf, config.preview_max_edge, config.jpeg_quality, PreviewQuality::Fast)?;
                Ok(())
            },
        )?;
        push_rgba(
            &mut rows, config, only, "fit_max_edge_rgba_fast", BenchBackend::Na, image_bytes,
            |buf| {
                let _ = buffer::fit_max_edge_rgba(buf.clone(), config.preview_max_edge, PreviewQuality::Fast)?;
                Ok(())
            },
        )?;
    }

    if matches!(config.preview_profiles, PreviewProfileMode::Quality | PreviewProfileMode::Both) {
        push_rgba(
            &mut rows, config, only, "encode_rgba_preview_quality", BenchBackend::Na, image_bytes,
            |buf| {
                let _ = buffer::encode_rgba_preview(buf, config.preview_max_edge, config.jpeg_quality, PreviewQuality::Quality)?;
                Ok(())
            },
        )?;
        push_rgba(
            &mut rows, config, only, "fit_max_edge_rgba_quality", BenchBackend::Na, image_bytes,
            |buf| {
                let _ = buffer::fit_max_edge_rgba(buf.clone(), config.preview_max_edge, PreviewQuality::Quality)?;
                Ok(())
            },
        )?;
    }

    push_rgba(
        &mut rows, config, only, "encode_rgba_jpeg", BenchBackend::Na, image_bytes,
        |buf| {
            let _ = buffer::encode_from_rgba(buf.clone(), OutputFormat::Jpeg, config.jpeg_quality)?;
            Ok(())
        },
    )?;

    push_rgba(
        &mut rows, config, only, "crop_rgba", BenchBackend::Na, image_bytes,
        |buf| {
            let w = (buf.width / 2).max(1);
            let h = (buf.height / 2).max(1);
            let _ = buffer::crop_rgba(buf.clone(), w / 4, h / 4, w, h)?;
            Ok(())
        },
    )?;

    push_rgba(
        &mut rows, config, only, "draw_line_rgba", BenchBackend::Na, image_bytes,
        |buf| {
            let _ = buffer::draw_line_rgba(buf.clone(),
                DrawLine { x0: 0, y0: 0, x1: buf.width.min(400), y1: buf.height.min(400), color_r: 255, color_g: 0, color_b: 0, color_a: 255 },
            )?;
            Ok(())
        },
    )?;

    push_rgba(
        &mut rows, config, only, "draw_text_rgba", BenchBackend::Na, image_bytes,
        |buf| {
            let _ = buffer::draw_text_rgba(buf.clone(),
                TextOverlay { text: "Bench".into(), x: 40, y: 40, font_size: 32.0, color_r: 255, color_g: 255, color_b: 255, color_a: 255 },
            )?;
            Ok(())
        },
    )?;

    Ok(BenchReport {
        image_label: format!("{}x{}", info.width, info.height),
        width: info.width,
        height: info.height,
        iterations: config.iterations,
        warmup_iterations: config.warmup_iterations,
        build_profile: build_profile_label(),
        rayon_threads: rayon_threads_label(),
        runtime_flags: crate::runtime::runtime_flags_label(),
        gpu_available,
        rows,
    })
}

fn cooldown_between_ops(config: &BenchConfig) {
    if config.cooldown_ms > 0 {
        std::thread::sleep(Duration::from_millis(config.cooldown_ms));
    }
}

fn push_bytes(
    rows: &mut Vec<BenchStats>, config: &BenchConfig, only: Option<&str>,
    name: &str, backend: BenchBackend, image_bytes: &[u8],
    mut op: impl FnMut(&[u8]) -> Result<(), String>,
) -> Result<(), String> {
    if !matches_only(name, only) { return Ok(()); }
    rows.push(run_bytes(name, backend, config, image_bytes, &mut op)?);
    cooldown_between_ops(config);
    Ok(())
}

fn push_rgba(
    rows: &mut Vec<BenchStats>, config: &BenchConfig, only: Option<&str>,
    name: &str, backend: BenchBackend, image_bytes: &[u8],
    mut op: impl FnMut(RgbaImageBuffer) -> Result<(), String>,
) -> Result<(), String> {
    if !matches_only(name, only) { return Ok(()); }
    rows.push(run_rgba_op(name, backend, config, image_bytes, &mut op)?);
    cooldown_between_ops(config);
    Ok(())
}

fn run_bytes(
    name: &str, backend: BenchBackend, config: &BenchConfig, image_bytes: &[u8],
    op: &mut impl FnMut(&[u8]) -> Result<(), String>,
) -> Result<BenchStats, String> {
    let path = execution_path_label(name, backend, None);
    for _ in 0..config.warmup_iterations {
        op(&image_bytes.to_vec()).map_err(|e| format!("{name} warmup failed: {e}"))?;
    }
    let mut samples = Vec::with_capacity(config.iterations as usize);
    for _ in 0..config.iterations {
        let fresh = image_bytes.to_vec();
        let start = Instant::now();
        op(&fresh).map_err(|e| format!("{name} failed: {e}"))?;
        samples.push(start.elapsed());
    }
    Ok(stats_from_samples(name, backend, config.iterations, &samples, path))
}

fn run_rgba_op(
    name: &str, backend: BenchBackend, config: &BenchConfig, image_bytes: &[u8],
    op: &mut impl FnMut(RgbaImageBuffer) -> Result<(), String>,
) -> Result<BenchStats, String> {
    let pb = backend.to_processing();
    let path = execution_path_label(name, backend, pb);
    for _ in 0..config.warmup_iterations {
        let buf = buffer::decode_to_rgba(&image_bytes.to_vec(), true, None)?;
        op(clone_rgba(&buf))?;
    }
    let mut samples = Vec::with_capacity(config.iterations as usize);
    for _ in 0..config.iterations {
        let buf = buffer::decode_to_rgba(&image_bytes.to_vec(), true, None)?;
        let input = clone_rgba(&buf);
        let start = Instant::now();
        op(input)?;
        samples.push(start.elapsed());
    }
    Ok(stats_from_samples(name, backend, config.iterations, &samples, path))
}

fn clone_rgba(b: &RgbaImageBuffer) -> RgbaImageBuffer {
    RgbaImageBuffer { width: b.width, height: b.height, pixels: b.pixels.clone() }
}

fn execution_path_label(name: &str, _backend: BenchBackend, pb: Option<ProcessingBackend>) -> String {
    if let Some(pb) = pb {
        if name.contains("filter") {
            let filter = filter_for_bench_name(name);
            return crate::perf::filter_execution_path(&filter, pb).to_string();
        }
        if name.contains("resize") || name.contains("thumbnail") {
            return crate::perf::resolve_bytes_resize_path(pb).to_string();
        }
    }
    if name.contains("fit_max_edge") || name.contains("encode_rgba_preview") {
        return "cpu_resize".to_string();
    }
    "cpu".to_string()
}

fn filter_for_bench_name(name: &str) -> ImageFilter {
    if name.contains("blur") {
        ImageFilter::Blur { radius: 4 }
    } else if name.contains("sharpen") {
        ImageFilter::Sharpen
    } else if name.contains("brightness") {
        ImageFilter::Brightness { amount: 25 }
    } else if name.contains("contrast") {
        ImageFilter::Contrast { amount: 1.2 }
    } else if name.contains("saturation") {
        ImageFilter::Saturation { amount: 1.3 }
    } else {
        ImageFilter::Blur { radius: 4 }
    }
}

fn percentile(sorted: &[f64], p: f64) -> f64 {
    if sorted.is_empty() { return 0.0; }
    if sorted.len() == 1 { return sorted[0]; }
    let rank = (p / 100.0) * (sorted.len() - 1) as f64;
    let lo = rank.floor() as usize;
    let hi = rank.ceil() as usize;
    let frac = rank - lo as f64;
    sorted[lo] * (1.0 - frac) + sorted[hi] * frac
}

fn stats_from_samples(name: &str, backend: BenchBackend, iterations: u32, samples: &[Duration], path: String) -> BenchStats {
    let mut ms: Vec<f64> = samples.iter().map(|d| d.as_secs_f64() * 1000.0).collect();
    let mean = ms.iter().sum::<f64>() / ms.len() as f64;
    let min = ms.iter().cloned().fold(f64::INFINITY, f64::min);
    let max = ms.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
    ms.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let median = percentile(&ms, 50.0);
    let p95 = percentile(&ms, 95.0);
    BenchStats { name: name.to_string(), backend, iterations, mean_ms: mean, median_ms: median, p95_ms: p95, min_ms: min, max_ms: max, path }
}

pub fn format_report_table(report: &BenchReport) -> String {
    let mut out = String::new();
    out.push_str(&format!(
        "image_forge_core benchmark — {} ({}×{}) — profile={} — warmup={} — timed={} — {} — GPU: {}\n\n",
        report.image_label, report.width, report.height,
        report.build_profile, report.warmup_iterations, report.iterations,
        report.runtime_flags, report.gpu_available
    ));
    out.push_str(&format!(
        "{:<32} {:<6} {:>8} {:>8} {:>8} {:>8} {:>8} {:<14}\n",
        "operation", "backend", "mean", "median", "p95", "min", "max", "path"
    ));
    out.push_str(&format!("{}\n", "-".repeat(100)));
    for r in &report.rows {
        out.push_str(&format!(
            "{:<32} {:<6} {:>8.2} {:>8.2} {:>8.2} {:>8.2} {:>8.2} {:<14}\n",
            r.name, r.backend.label(), r.mean_ms, r.median_ms, r.p95_ms, r.min_ms, r.max_ms, r.path
        ));
    }
    out
}

pub fn format_report_csv(report: &BenchReport) -> String {
    let mut out = String::from(
        "operation,backend,iterations,warmup,build_profile,rayon_threads,mean_ms,median_ms,p95_ms,min_ms,max_ms,path,width,height,gpu_available\n",
    );
    for r in &report.rows {
        out.push_str(&format!(
            "{},{},{},{},{},{},{:.3},{:.3},{:.3},{:.3},{:.3},{},{},{},{}\n",
            r.name, r.backend.label(), r.iterations, report.warmup_iterations,
            report.build_profile, report.rayon_threads,
            r.mean_ms, r.median_ms, r.p95_ms, r.min_ms, r.max_ms,
            r.path, report.width, report.height, report.gpu_available
        ));
    }
    out
}

pub fn parse_preview_profile(s: &str) -> Result<PreviewProfileMode, String> {
    match s.to_ascii_lowercase().as_str() {
        "fast" => Ok(PreviewProfileMode::Fast),
        "quality" => Ok(PreviewProfileMode::Quality),
        "both" => Ok(PreviewProfileMode::Both),
        _ => Err(format!("unknown preview profile {s:?} (use fast|quality|both)")),
    }
}

pub fn synthetic_jpeg_bytes(width: u32, height: u32, quality: u8) -> Result<Vec<u8>, String> {
    let mut pixels = vec![0u8; (width * height * 4) as usize];
    for y in 0..height {
        for x in 0..width {
            let i = ((y * width + x) * 4) as usize;
            pixels[i] = (x % 256) as u8;
            pixels[i + 1] = (y % 256) as u8;
            pixels[i + 2] = 128;
            pixels[i + 3] = 255;
        }
    }
    let img = image::RgbaImage::from_raw(width, height, pixels)
        .ok_or_else(|| "synthetic image dimensions invalid".to_string())?;
    crate::compress::encode_jpeg(&image::DynamicImage::ImageRgba8(img), quality)
}
