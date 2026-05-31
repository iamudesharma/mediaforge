//! Benchmark harness for video_forge_kit (same Rust pipeline as the Flutter plugin).
//!
//! Usage:
//!   cargo run --release -p video_forge --bin vp_bench -- \
//!     --fixtures-dir benchmark-results/fixtures \
//!     --output benchmark-results/rust-bench.json
//!
//!   # Use platform hardware encoders (VideoToolbox / MediaCodec / NVENC / VAAPI) with software fallback:
//!   cargo run --release -p video_forge --bin vp_bench -- --prefer-hardware

use std::fs;
use std::path::{Path, PathBuf};
use std::time::Instant;

use serde::Serialize;
use video_forge::jobs::progress::ProgressReporter;
use video_forge::jobs::registry::CancellationToken;
use video_forge::pipeline::{extract_batch_thumbnails, extract_thumbnail, probe_media_info, run_compress};
use video_forge::types::{
    BatchThumbnailOptions, CompressOptions, ThumbnailFormat, ThumbnailOptions, VideoCodec,
    VideoQuality,
};

#[derive(Debug, Serialize, Clone)]
struct BenchRow {
    scenario_id: String,
    source: String,
    tier: String,
    tier_label: String,
    operation: String,
    input: String,
    input_bytes: u64,
    duration_ms: u64,
    success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    output_bytes: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    encoder: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    used_hardware: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pipeline_mode: Option<String>,
}

#[derive(Debug, Serialize)]
struct BenchReport {
    platform: String,
    rust_version: String,
    timestamp_utc: String,
    compress_preset: String,
    rows: Vec<BenchRow>,
}

#[derive(Debug, serde::Deserialize)]
struct FixturesFile {
    tiers: Vec<FixtureTier>,
}

#[derive(Debug, serde::Deserialize)]
struct FixtureTier {
    id: String,
    label: String,
    local_file: String,
    network_url: String,
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let fixtures_dir = arg_value(&args, "--fixtures-dir")
        .unwrap_or_else(|| "benchmark-results/fixtures".into());
    let output = arg_value(&args, "--output")
        .unwrap_or_else(|| "benchmark-results/rust-bench.json".into());
    let config = arg_value(&args, "--config")
        .unwrap_or_else(|| "tools/benchmark/fixtures.json".into());
    let skip_network = args.iter().any(|a| a == "--skip-network");
    let prefer_hardware = args.iter().any(|a| a == "--prefer-hardware");

    let fixtures: FixturesFile = serde_json::from_str(
        &fs::read_to_string(&config).unwrap_or_else(|e| panic!("read {config}: {e}")),
    )
    .expect("parse fixtures.json");

    let out_dir = PathBuf::from(&output).parent().unwrap_or(Path::new(".")).to_path_buf();
    fs::create_dir_all(&out_dir).ok();
    let work = out_dir.join("bench-work");
    fs::create_dir_all(&work).ok();

    let mut rows = Vec::new();

    for tier in &fixtures.tiers {
        let local_path = PathBuf::from(&fixtures_dir).join(&tier.local_file);
        if local_path.exists() {
            rows.extend(run_tier(
                &tier.id,
                &tier.label,
                "local",
                local_path.to_string_lossy().as_ref(),
                &work,
                prefer_hardware,
            ));
        } else {
            eprintln!("skip local {} (missing {})", tier.id, local_path.display());
        }

        if !skip_network {
            rows.extend(run_tier(
                &tier.id,
                &tier.label,
                "network",
                &tier.network_url,
                &work,
                prefer_hardware,
            ));
        }
    }

    let report = BenchReport {
        platform: std::env::consts::OS.to_string(),
        rust_version: env!("CARGO_PKG_VERSION").to_string(),
        timestamp_utc: chrono_lite_utc(),
        compress_preset: compress_preset_label(prefer_hardware),
        rows,
    };

    let json = serde_json::to_string_pretty(&report).expect("serialize");
    fs::write(&output, &json).expect("write output");
    println!("Wrote {} ({} rows)", output, report.rows.len());
}

fn compress_preset_label(prefer_hardware: bool) -> String {
    if prefer_hardware {
        "medium · h264 · hardware encoder (prefer_hardware_encoder) · include_audio".into()
    } else {
        "medium · h264 · software encoder · include_audio".into()
    }
}

fn arg_value(args: &[String], flag: &str) -> Option<String> {
    args.iter()
        .position(|a| a == flag)
        .and_then(|i| args.get(i + 1))
        .cloned()
}

fn chrono_lite_utc() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("{secs}")
}

fn input_bytes(input: &str) -> u64 {
    let p = Path::new(input);
    if p.exists() {
        fs::metadata(p).map(|m| m.len()).unwrap_or(0)
    } else {
        0
    }
}

fn run_tier(
    id: &str,
    label: &str,
    source: &str,
    input: &str,
    work: &Path,
    prefer_hardware: bool,
) -> Vec<BenchRow> {
    let mut rows = Vec::new();
    let prefix = format!("{source}_{id}");
    let ib = input_bytes(input);

    eprintln!("==> {source} / {id}: {label}");

    rows.push(time_probe(&prefix, source, id, label, input, ib));
    rows.push(time_compress(
        &prefix,
        source,
        id,
        label,
        input,
        ib,
        work,
        prefer_hardware,
    ));
    rows.push(time_thumbnail(&prefix, source, id, label, input, ib, work));
    rows.push(time_batch_thumbnails(&prefix, source, id, label, input, ib, work));

    rows
}

fn time_probe(
    prefix: &str,
    source: &str,
    tier: &str,
    tier_label: &str,
    input: &str,
    input_bytes: u64,
) -> BenchRow {
    let t0 = Instant::now();
    let result = probe_media_info(input);
    let elapsed = t0.elapsed().as_millis() as u64;
    match result {
        Ok(info) => BenchRow {
            scenario_id: format!("{prefix}_probe"),
            source: source.into(),
            tier: tier.into(),
            tier_label: tier_label.into(),
            operation: "probe".into(),
            input: input.into(),
            input_bytes,
            duration_ms: elapsed,
            success: true,
            error: None,
            output_bytes: None,
            encoder: Some(format!("{} {}x{}", info.video_codec, info.width, info.height)),
            used_hardware: None,
            pipeline_mode: None,
        },
        Err(e) => bench_err(
            prefix, source, tier, tier_label, "probe", input, input_bytes, elapsed, e.to_string(),
        ),
    }
}

fn time_compress(
    prefix: &str,
    source: &str,
    tier: &str,
    tier_label: &str,
    input: &str,
    input_bytes: u64,
    work: &Path,
    prefer_hardware: bool,
) -> BenchRow {
    let out = work.join(format!("{prefix}_compressed.mp4"));
    let _ = fs::remove_file(&out);

    let options = CompressOptions {
        input_path: input.to_string(),
        output_path: Some(out.to_string_lossy().into_owned()),
        quality: VideoQuality::Medium,
        codec: VideoCodec::H264,
        prefer_hardware_encoder: prefer_hardware,
        include_audio: true,
        ..Default::default()
    };

    let t0 = Instant::now();
    let token = CancellationToken::new();
    let mut reporter = ProgressReporter::noop("bench");
    let result = run_compress(options, token, &mut reporter);
    let elapsed = t0.elapsed().as_millis() as u64;

    match result {
        Ok(r) => BenchRow {
            scenario_id: format!("{prefix}_compress"),
            source: source.into(),
            tier: tier.into(),
            tier_label: tier_label.into(),
            operation: "compress".into(),
            input: input.into(),
            input_bytes,
            duration_ms: elapsed,
            success: true,
            error: None,
            output_bytes: Some(r.file_size),
            encoder: Some(r.encoder_name),
            used_hardware: Some(r.used_hardware_acceleration),
            pipeline_mode: Some(r.pipeline_mode),
        },
        Err(e) => {
            let _ = fs::remove_file(&out);
            bench_err(
                prefix,
                source,
                tier,
                tier_label,
                "compress",
                input,
                input_bytes,
                elapsed,
                e.to_string(),
            )
        }
    }
}

fn time_thumbnail(
    prefix: &str,
    source: &str,
    tier: &str,
    tier_label: &str,
    input: &str,
    input_bytes: u64,
    work: &Path,
) -> BenchRow {
    let out = work.join(format!("{prefix}_thumb.jpg"));
    let _ = fs::remove_file(&out);

    let options = ThumbnailOptions {
        input_path: input.to_string(),
        output_path: Some(out.to_string_lossy().into_owned()),
        position_ms: 2000,
        width: Some(640),
        height: None,
        format: ThumbnailFormat::Jpeg,
    };

    let t0 = Instant::now();
    let result = extract_thumbnail(options, CancellationToken::new());
    let elapsed = t0.elapsed().as_millis() as u64;

    match result {
        Ok(path) => {
            let size = fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
            BenchRow {
                scenario_id: format!("{prefix}_thumbnail"),
                source: source.into(),
                tier: tier.into(),
                tier_label: tier_label.into(),
                operation: "thumbnail".into(),
                input: input.into(),
                input_bytes,
                duration_ms: elapsed,
                success: true,
                error: None,
                output_bytes: Some(size),
                encoder: None,
                used_hardware: None,
                pipeline_mode: None,
            }
        }
        Err(e) => bench_err(
            prefix,
            source,
            tier,
            tier_label,
            "thumbnail",
            input,
            input_bytes,
            elapsed,
            e.to_string(),
        ),
    }
}

fn time_batch_thumbnails(
    prefix: &str,
    source: &str,
    tier: &str,
    tier_label: &str,
    input: &str,
    input_bytes: u64,
    work: &Path,
) -> BenchRow {
    let dir = work.join(format!("{prefix}_thumbs"));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).ok();

    let positions_ms: Vec<u64> = (0..10).map(|i| i * 1000).collect();
    let options = BatchThumbnailOptions {
        input_path: input.to_string(),
        output_dir: dir.to_string_lossy().into_owned(),
        output_paths: None,
        positions_ms,
        width: Some(320),
        height: None,
        format: ThumbnailFormat::Jpeg,
    };

    let t0 = Instant::now();
    let result = extract_batch_thumbnails(options, CancellationToken::new());
    let elapsed = t0.elapsed().as_millis() as u64;

    match result {
        Ok(r) => {
            let total: u64 = r
                .paths
                .iter()
                .filter_map(|p| fs::metadata(p).ok())
                .map(|m| m.len())
                .sum();
            BenchRow {
                scenario_id: format!("{prefix}_batch_10"),
                source: source.into(),
                tier: tier.into(),
                tier_label: tier_label.into(),
                operation: "batch_thumbnails_10".into(),
                input: input.into(),
                input_bytes,
                duration_ms: elapsed,
                success: true,
                error: None,
                output_bytes: Some(total),
                encoder: Some(format!("{} frames", r.paths.len())),
                used_hardware: None,
                pipeline_mode: None,
            }
        }
        Err(e) => bench_err(
            prefix,
            source,
            tier,
            tier_label,
            "batch_thumbnails_10",
            input,
            input_bytes,
            elapsed,
            e.to_string(),
        ),
    }
}

fn bench_err(
    prefix: &str,
    source: &str,
    tier: &str,
    tier_label: &str,
    operation: &str,
    input: &str,
    input_bytes: u64,
    elapsed: u64,
    error: String,
) -> BenchRow {
    BenchRow {
        scenario_id: format!("{prefix}_{operation}"),
        source: source.into(),
        tier: tier.into(),
        tier_label: tier_label.into(),
        operation: operation.into(),
        input: input.into(),
        input_bytes,
        duration_ms: elapsed,
        success: false,
        error: Some(error),
        output_bytes: None,
        encoder: None,
        used_hardware: None,
        pipeline_mode: None,
    }
}
