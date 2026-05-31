//! Dev CLI: compress a video through the same pipeline as the Flutter plugin.
//!
//! Usage:
//!   cargo run --release -p video_forge --bin vp_compress -- \
//!     /path/to/input.mp4 /path/to/output.mp4

use std::env;

use video_forge::jobs::progress::ProgressReporter;
use video_forge::jobs::registry::CancellationToken;
use video_forge::pipeline::run_compress;
use video_forge::types::{CompressOptions, VideoCodec, VideoQuality};

fn main() {
    env_logger::init();

    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("usage: vp_compress <input> <output> [--hw] [--no-audio]");
        std::process::exit(1);
    }

    let prefer_hw = args.iter().any(|a| a == "--hw");
    let include_audio = !args.iter().any(|a| a == "--no-audio");
    let options = CompressOptions {
        input_path: args[1].clone(),
        output_path: Some(args[2].clone()),
        quality: VideoQuality::Medium,
        codec: VideoCodec::H264,
        prefer_hardware_encoder: prefer_hw,
        include_audio,
        ..Default::default()
    };

    let token = CancellationToken::new();
    let mut reporter = ProgressReporter::noop("cli");

    match run_compress(options, token, &mut reporter) {
        Ok(result) => {
            println!(
                "ok: {} bytes, encoder={}, hw={}",
                result.file_size, result.encoder_name, result.used_hardware_acceleration
            );
        }
        Err(e) => {
            eprintln!("compress failed: {e}");
            std::process::exit(1);
        }
    }
}
