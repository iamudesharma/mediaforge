//! Benchmark harness for rust_media_runtime — audio/video decode, seek, overlay mixing.
//!
//! Usage:
//!   cargo run --release -p rust_media_runtime --bin media_bench -- \
//!     --fixtures-dir benchmark-results/fixtures \
//!     --output benchmark-results/media-bench.json
//!
//! Operations measured (per video fixture):
//!   - probe_capabilities  — one-time FFmpeg decoder probe
//!   - open_file           — container open + stream detection
//!   - first_video_frame   — latency to first decoded video frame after start
//!   - video_decode_fps    — sustained video frame decode throughput
//!   - audio_decode_fps    — sustained audio frame decode throughput
//!   - seek_recovery       — seek + decoder recovery time at 25/50/75%
//!   - add_overlay         — overlay audio track setup time
//!   - stop                — engine shutdown time

use std::fs;
use std::path::{Path, PathBuf};
use std::time::Instant;

use serde::Serialize;
use rust_media_runtime::api::runtime;

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
    label: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    frames: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    fps: Option<f64>,
}

#[derive(Debug, Serialize)]
struct MediaBenchReport {
    platform: String,
    timestamp_utc: String,
    decode_capabilities: CapSummary,
    rows: Vec<BenchRow>,
}

#[derive(Debug, Serialize)]
struct CapSummary {
    ffmpeg_version: String,
    hevc_vt: bool,
    h264_vt: bool,
    hw_disabled: bool,
    ready_for_hevc_hw: bool,
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
    #[allow(dead_code)]
    network_url: String,
}

fn main() {
    env_logger::init();

    let args: Vec<String> = std::env::args().collect();
    let fixtures_dir = arg_value(&args, "--fixtures-dir")
        .unwrap_or_else(|| "benchmark-results/fixtures".into());
    let output = arg_value(&args, "--output")
        .unwrap_or_else(|| "benchmark-results/media-bench.json".into());
    let config = arg_value(&args, "--config")
        .unwrap_or_else(|| "tools/benchmark/fixtures.json".into());
    let only = arg_value(&args, "--only");

    let fixtures: FixturesFile = serde_json::from_str(
        &fs::read_to_string(&config).unwrap_or_else(|e| panic!("read {config}: {e}")),
    )
    .expect("parse fixtures.json");

    let out_dir = PathBuf::from(&output).parent().unwrap_or(Path::new(".")).to_path_buf();
    fs::create_dir_all(&out_dir).ok();

    eprintln!("==> Initializing FFmpeg");
    runtime::ensure_ffmpeg_initialized();

    let cap = runtime::probe_decode_capabilities();
    let cap_summary = CapSummary {
        ffmpeg_version: cap.ffmpeg_version.clone(),
        hevc_vt: cap.hevc_videotoolbox,
        h264_vt: cap.h264_videotoolbox,
        hw_disabled: cap.hw_decode_disabled_env,
        ready_for_hevc_hw: cap.ready_for_hevc_hw,
    };

    let mut rows: Vec<BenchRow> = Vec::new();

    // One-time probe capability benchmark
    rows.push(time_probe_capabilities());

    for tier in &fixtures.tiers {
        let local_path = PathBuf::from(&fixtures_dir).join(&tier.local_file);
        if !local_path.exists() {
            eprintln!("skip {} (missing {})", tier.id, local_path.display());
            continue;
        }

        if let Some(ref filter) = only {
            if !tier.id.contains(filter.as_str()) {
                continue;
            }
        }

        rows.extend(run_tier(
            tier,
            local_path.to_string_lossy().as_ref(),
        ));
    }

    let report = MediaBenchReport {
        platform: std::env::consts::OS.to_string(),
        timestamp_utc: chrono_lite_utc(),
        decode_capabilities: cap_summary,
        rows,
    };

    let json = serde_json::to_string_pretty(&report).expect("serialize");
    fs::write(&output, &json).expect("write output");
    eprintln!("Wrote {} ({} rows)", output, report.rows.len());
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
    Path::new(input)
        .exists()
        .then(|| fs::metadata(input).map(|m| m.len()).unwrap_or(0))
        .unwrap_or(0)
}

fn time_probe_capabilities() -> BenchRow {
    let t0 = Instant::now();
    let cap = runtime::probe_decode_capabilities();
    let elapsed = t0.elapsed().as_millis() as u64;

    BenchRow {
        scenario_id: "probe_capabilities".into(),
        source: "n/a".into(),
        tier: "n/a".into(),
        tier_label: "n/a".into(),
        operation: "probe_capabilities".into(),
        input: "ffmpeg_linked_lib".into(),
        input_bytes: 0,
        duration_ms: elapsed,
        success: true,
        error: None,
        output_bytes: None,
        label: Some(format!(
            "FFmpeg {} HEVC_VT={} H264_VT={}",
            cap.ffmpeg_version, cap.hevc_videotoolbox, cap.h264_videotoolbox
        )),
        frames: None,
        fps: None,
    }
}

fn run_tier(tier: &FixtureTier, input: &str) -> Vec<BenchRow> {
    let mut rows = Vec::new();
    let prefix = format!("media_{}", tier.id);
    let ib = input_bytes(input);

    eprintln!("==> media_bench / {id}: {label}", id = tier.id, label = tier.label);

    // 1. Open file
    let engine = runtime::MediaPlaybackEngine::new(0, 1024, 1080);
    rows.push(time_open_file(&prefix, tier, input, ib, &engine));

    let duration_ms = engine.get_duration_ms();
    if duration_ms == 0 {
        eprintln!("  skip decode: file has zero duration");
        rows.push(time_stop(&prefix, tier, input, ib, &engine));
        return rows;
    }

    // 2. First video frame latency (start engine, wait for first frame)
    rows.push(time_first_video_frame(&prefix, tier, input, ib, &engine, duration_ms));

    // 3. Video decode throughput (count frames over ~3s window)
    rows.push(time_video_decode_fps(&prefix, tier, input, ib, &engine, duration_ms));

    // 4. Audio frame throughput
    rows.push(time_audio_decode_fps(&prefix, tier, input, ib, &engine, duration_ms));

    // 5. Seek + recovery at multiple positions
    for (pct, label) in [(25u64, "25_pct"), (50, "50_pct"), (75, "75_pct")] {
        let target_ms = (duration_ms as f64 * pct as f64 / 100.0) as u64;
        rows.push(time_seek_recovery(
            &format!("{prefix}_seek_{label}"),
            tier, input, ib, &engine, target_ms,
        ));
    }

    // 6. Stop
    rows.push(time_stop(&prefix, tier, input, ib, &engine));

    rows
}

fn time_open_file(
    prefix: &str, tier: &FixtureTier, input: &str, input_bytes: u64,
    engine: &runtime::MediaPlaybackEngine,
) -> BenchRow {
    let t0 = Instant::now();
    let result = engine.open_file(input.to_string());
    let elapsed = t0.elapsed().as_millis() as u64;

    match result {
        Ok(()) => {
            let dur = engine.get_duration_ms();
            BenchRow {
                scenario_id: format!("{prefix}_open"),
                source: "local".into(),
                tier: tier.id.clone(),
                tier_label: tier.label.clone(),
                operation: "open_file".into(),
                input: input.into(),
                input_bytes,
                duration_ms: elapsed,
                success: true,
                error: None,
                output_bytes: None,
                label: Some(format!("duration={}ms", dur)),
                frames: None,
                fps: None,
            }
        }
        Err(e) => bench_err(prefix, tier, "open_file", input, input_bytes, elapsed, e.to_string()),
    }
}

fn time_first_video_frame(
    prefix: &str, tier: &FixtureTier, input: &str, input_bytes: u64,
    engine: &runtime::MediaPlaybackEngine, _duration_ms: u64,
) -> BenchRow {
    let t0 = Instant::now();
    engine.start();

    // Poll for first video frame (with timeout)
    let timeout_ms = 10000u64;
    let start = Instant::now();
    let mut got_frame = false;
    loop {
        if let Some(_frame) = engine.take_video_frame() {
            got_frame = true;
            break;
        }
        if start.elapsed().as_millis() as u64 > timeout_ms {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(16));
    }
    let elapsed = t0.elapsed().as_millis() as u64;

    if got_frame {
        BenchRow {
            scenario_id: format!("{prefix}_first_frame"),
            source: "local".into(),
            tier: tier.id.clone(),
            tier_label: tier.label.clone(),
            operation: "first_video_frame".into(),
            input: input.into(),
            input_bytes,
            duration_ms: elapsed,
            success: true,
            error: None,
            output_bytes: None,
            label: None,
            frames: None,
            fps: None,
        }
    } else {
        bench_err(prefix, tier, "first_video_frame", input, input_bytes, elapsed,
            "timeout: no video frame after 10s".into())
    }
}

fn time_video_decode_fps(
    prefix: &str, tier: &FixtureTier, input: &str, input_bytes: u64,
    engine: &runtime::MediaPlaybackEngine, _duration_ms: u64,
) -> BenchRow {
    // Count video frames over a ~3s measurement window
    let measure_ms = 3000u64;
    let poll_interval_ms = 16u64;
    let max_polls = measure_ms / poll_interval_ms;

    let mut frame_count = 0u64;
    let mut missed = 0u64;

    for _ in 0..max_polls {
        if let Some(_frame) = engine.take_video_frame() {
            frame_count += 1;
        } else {
            missed += 1;
        }
        std::thread::sleep(std::time::Duration::from_millis(poll_interval_ms));
    }

    let elapsed = (max_polls * poll_interval_ms) as u64;
    let fps = if elapsed > 0 {
        frame_count as f64 * 1000.0 / elapsed as f64
    } else {
        0.0
    };

    BenchRow {
        scenario_id: format!("{prefix}_video_fps"),
        source: "local".into(),
        tier: tier.id.clone(),
        tier_label: tier.label.clone(),
        operation: "video_decode_fps".into(),
        input: input.into(),
        input_bytes,
        duration_ms: elapsed,
        success: frame_count > 0,
        error: if frame_count == 0 { Some("no frames decoded".into()) } else { None },
        output_bytes: None,
        label: Some(format!("polls={} missed={}", frame_count + missed, missed)),
        frames: Some(frame_count),
        fps: Some((fps * 10.0).round() / 10.0),
    }
}

fn time_audio_decode_fps(
    prefix: &str, tier: &FixtureTier, input: &str, input_bytes: u64,
    engine: &runtime::MediaPlaybackEngine, _duration_ms: u64,
) -> BenchRow {
    let measure_ms = 3000u64;
    let poll_interval_ms = 16u64;
    let max_polls = measure_ms / poll_interval_ms;

    let mut frame_count = 0u64;
    let mut total_samples = 0u64;

    for _ in 0..max_polls {
        if let Some(frame) = engine.take_audio_frame() {
            frame_count += 1;
            total_samples += frame.samples.len() as u64;
        }
        std::thread::sleep(std::time::Duration::from_millis(poll_interval_ms));
    }

    let elapsed = (max_polls * poll_interval_ms) as u64;
    let fps = if elapsed > 0 {
        frame_count as f64 * 1000.0 / elapsed as f64
    } else {
        0.0
    };

    BenchRow {
        scenario_id: format!("{prefix}_audio_fps"),
        source: "local".into(),
        tier: tier.id.clone(),
        tier_label: tier.label.clone(),
        operation: "audio_decode_fps".into(),
        input: input.into(),
        input_bytes,
        duration_ms: elapsed,
        success: frame_count > 0,
        error: if frame_count == 0 { Some("no audio frames decoded".into()) } else { None },
        output_bytes: Some(total_samples * 4), // f32 = 4 bytes per sample
        label: Some(format!("frames={} samples={}", frame_count, total_samples)),
        frames: Some(frame_count),
        fps: Some((fps * 10.0).round() / 10.0),
    }
}

fn time_seek_recovery(
    prefix: &str, tier: &FixtureTier, input: &str, input_bytes: u64,
    engine: &runtime::MediaPlaybackEngine, target_ms: u64,
) -> BenchRow {
    let t0 = Instant::now();
    engine.seek(target_ms);

    // Wait for at least one video frame after seek (recovery)
    let timeout_ms = 5000u64;
    let start = Instant::now();
    let mut got_frame = false;
    loop {
        if let Some(_frame) = engine.take_video_frame() {
            got_frame = true;
            break;
        }
        if start.elapsed().as_millis() as u64 > timeout_ms {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(16));
    }
    let elapsed = t0.elapsed().as_millis() as u64;

    if got_frame {
        BenchRow {
            scenario_id: format!("{prefix}"),
            source: "local".into(),
            tier: tier.id.clone(),
            tier_label: tier.label.clone(),
            operation: "seek_recovery".into(),
            input: input.into(),
            input_bytes,
            duration_ms: elapsed,
            success: true,
            error: None,
            output_bytes: None,
            label: Some(format!("target={}ms", target_ms)),
            frames: None,
            fps: None,
        }
    } else {
        bench_err(prefix, tier, "seek_recovery", input, input_bytes, elapsed,
            format!("timeout: seek to {}ms failed", target_ms))
    }
}

fn time_stop(
    prefix: &str, tier: &FixtureTier, input: &str, input_bytes: u64,
    engine: &runtime::MediaPlaybackEngine,
) -> BenchRow {
    let t0 = Instant::now();
    engine.stop();
    let elapsed = t0.elapsed().as_millis() as u64;

    BenchRow {
        scenario_id: format!("{prefix}_stop"),
        source: "local".into(),
        tier: tier.id.clone(),
        tier_label: tier.label.clone(),
        operation: "stop".into(),
        input: input.into(),
        input_bytes,
        duration_ms: elapsed,
        success: true,
        error: None,
        output_bytes: None,
        label: None,
        frames: None,
        fps: None,
    }
}

fn bench_err(
    prefix: &str, tier: &FixtureTier, operation: &str,
    input: &str, input_bytes: u64, elapsed: u64, error: String,
) -> BenchRow {
    BenchRow {
        scenario_id: format!("{prefix}_{operation}"),
        source: "local".into(),
        tier: tier.id.clone(),
        tier_label: tier.label.clone(),
        operation: operation.into(),
        input: input.into(),
        input_bytes,
        duration_ms: elapsed,
        success: false,
        error: Some(error),
        output_bytes: None,
        label: None,
        frames: None,
        fps: None,
    }
}
