//! Run API benchmarks from the command line (no Flutter).
//!
//! ```bash
//! cd image_forge/rust
//! cargo run --release --features gpu --bin image_forge_benchmark
//! cargo run --release --features gpu --bin image_forge_benchmark -- \
//!   --synthetic -n 10 --only filter_rgba_blur --warmup 1
//! ```

use std::fs;
use std::path::PathBuf;

use image_forge_core::benchmark::{self, BenchConfig, PreviewProfileMode};

fn main() {
    if let Err(e) = run() {
        eprintln!("benchmark failed: {e}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    image_forge_core::runtime::configure_runtime();
    let args: Vec<String> = std::env::args().collect();
    let mut image_path: Option<PathBuf> = None;
    let mut iterations = 10u32;
    let mut warmup_iterations = 1u32;
    let mut cooldown_ms = 0u64;
    let mut csv_path: Option<PathBuf> = None;
    let mut synthetic = false;
    let mut preview_max_edge = 1280u32;
    let mut preview_profiles = PreviewProfileMode::Both;
    let mut only: Option<String> = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--image" | "-i" => {
                i += 1;
                image_path = Some(PathBuf::from(args.get(i).ok_or("--image requires a path")?));
            }
            "--iterations" | "-n" => {
                i += 1;
                iterations = args
                    .get(i)
                    .ok_or("--iterations requires a number")?
                    .parse()
                    .map_err(|_| "invalid iterations")?;
            }
            "--warmup" => {
                i += 1;
                warmup_iterations = args
                    .get(i)
                    .ok_or("--warmup requires a number")?
                    .parse()
                    .map_err(|_| "invalid warmup iterations")?;
            }
            "--cooldown-ms" => {
                i += 1;
                cooldown_ms = args
                    .get(i)
                    .ok_or("--cooldown-ms requires a number")?
                    .parse()
                    .map_err(|_| "invalid cooldown-ms")?;
            }
            "--only" => {
                i += 1;
                only = Some(
                    args.get(i)
                        .ok_or("--only requires an operation name or substring")?
                        .to_string(),
                );
            }
            "--preview-profile" => {
                i += 1;
                let s = args
                    .get(i)
                    .ok_or("--preview-profile requires fast|quality|both")?;
                preview_profiles = benchmark::parse_preview_profile(s)?;
            }
            "--csv" => {
                i += 1;
                csv_path = Some(PathBuf::from(args.get(i).ok_or("--csv requires a path")?));
            }
            "--synthetic" => synthetic = true,
            "--preview-max-edge" => {
                i += 1;
                preview_max_edge = args
                    .get(i)
                    .ok_or("--preview-max-edge requires a number")?
                    .parse()
                    .map_err(|_| "invalid preview max edge")?;
            }
            "--help" | "-h" => {
                print_help();
                return Ok(());
            }
            other => return Err(format!("unknown argument: {other} (try --help)")),
        }
        i += 1;
    }

    let image_bytes = if let Some(path) = image_path {
        fs::read(&path).map_err(|e| format!("read {}: {e}", path.display()))?
    } else if synthetic {
        benchmark::synthetic_jpeg_bytes(1280, 720, 85)?
    } else {
        print_help();
        return Err("provide --image PATH or --synthetic".into());
    };

    let config = BenchConfig {
        iterations,
        warmup_iterations,
        cooldown_ms,
        preview_max_edge,
        jpeg_quality: 85,
        preview_profiles,
        only,
    };

    println!(
        "Running warmup={} + timed={} per operation (fresh input each timed run)…\n",
        warmup_iterations, iterations
    );
    if let Some(ref filter) = config.only {
        println!("Filter: only operations matching {:?}\n", filter);
    }

    let report = benchmark::run_all(&image_bytes, &config)?;
    let table = benchmark::format_report_table(&report);
    println!("{table}");

    if let Some(path) = csv_path {
        fs::write(&path, benchmark::format_report_csv(&report))
            .map_err(|e| format!("write csv: {e}"))?;
        println!("Wrote {}", path.display());
    }

    Ok(())
}

fn print_help() {
    eprintln!(
        r#"image_forge_benchmark — measure each API (CPU vs GPU where supported)

Usage:
  cargo run --release --features gpu --bin image_forge_benchmark -- [OPTIONS]

Options:
  -i, --image PATH          Input JPEG/PNG (required unless --synthetic)
  --synthetic               Built-in 1280×720 JPEG
  -n, --iterations N        Timed runs per operation (default: 10)
  --warmup N                Discarded runs before timing (default: 1, GPU/Metal warmup)
  --cooldown-ms N           Pause between operations (default: 0)
  --only NAME               Run operations whose name contains NAME (e.g. filter_rgba_blur)
  --preview-profile MODE    fast | quality | both (default: both)
  --preview-max-edge N      Preview encode/fit max edge (default: 1280)
  --csv PATH                Write CSV (includes median, p95, build profile)
  -h, --help                Show this help

Runbook (comparable numbers):
  • Always use --release (and --features gpu for GPU rows).
  • Plug in AC power; close heavy background apps.
  • Optional: RAYON_NUM_THREADS=8 or RUST_IMAGE_RAYON_THREADS=4 cargo run --release ...
  • Disable buffer pool A/B: RUST_IMAGE_NO_POOL=1 cargo run --release ...
  • Isolate one op: --only filter_rgba_blur -n 10 --warmup 2

Each timed iteration uses a fresh buffer clone; warmup runs are not included in stats.
GPU cases are skipped if Metal/Vulkan is unavailable.
"#
    );
}
