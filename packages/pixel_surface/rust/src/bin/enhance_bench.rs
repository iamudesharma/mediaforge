//! GPU video enhancement benchmark (Apple Silicon / Metal).
//!
//! Measures the enhancement stage alone on synthetic sources across the
//! resolution matrix in the spec, so the "GPU ms/frame" number is measured
//! rather than assumed. Decode, audio and compositing are deliberately out of
//! scope here — use the player-level protocol in
//! `packages/media_forge_player/docs/VIDEO_ENHANCEMENT.md` for end-to-end
//! playback metrics (CPU, memory, dropped frames, A/V drift, energy).
//!
//! ```sh
//! cd packages/pixel_surface/rust
//! cargo run --release --features gpu --bin enhance_bench -- --frames 240
//! cargo run --release --features gpu --bin enhance_bench -- --mode high_quality
//! ```

#[cfg(not(all(target_vendor = "apple", feature = "gpu")))]
fn main() {
    eprintln!(
        "enhance_bench requires Apple Metal: run with \
         `cargo run --release --features gpu --bin enhance_bench`"
    );
}

#[cfg(all(target_vendor = "apple", feature = "gpu"))]
fn main() {
    apple::main();
}

#[cfg(all(target_vendor = "apple", feature = "gpu"))]
mod apple {
    use std::ffi::c_void;
    use std::time::Instant;

    use pixel_surface::enhance::plan::{self, PlanRequest};
    use pixel_surface::enhance::{
        create_backend, EnhancementBackend, EnhancementMode, FrameHandle, FrameSize,
    };
    use pixel_surface::metal::Device;
    use pixel_surface::metal_iosurface::{
        self, create_bgra_iosurface_pixel_buffer_metal, IosurfacePixelBuffer,
    };

    type CVPixelBufferRef = *mut c_void;

    /// Source → display pairs from the spec's validation matrix.
    const MATRIX: &[(FrameSize, FrameSize)] = &[
        (FrameSize::new(854, 480), FrameSize::new(1920, 1080)),
        (FrameSize::new(1280, 720), FrameSize::new(1920, 1080)),
        (FrameSize::new(1280, 720), FrameSize::new(3840, 2160)),
        (FrameSize::new(1920, 1080), FrameSize::new(3840, 2160)),
    ];

    fn parse(args: &[String], flag: &str) -> Option<String> {
        args.iter()
            .position(|a| a == flag)
            .and_then(|i| args.get(i + 1))
            .cloned()
    }

    fn fill_pattern(buffer: &IosurfacePixelBuffer, width: u32, height: u32) {
        unsafe {
            metal_iosurface::with_bgra_pixels_mut(buffer.pixel_buffer, |pixels, stride| {
                for y in 0..height as usize {
                    for x in 0..width as usize {
                        // Diagonal ramp + checker: a plausible mix of smooth
                        // gradient and high-frequency detail for the scaler.
                        let v = ((x * 3 + y * 5) % 256) as u8;
                        let i = y * stride + x * 4;
                        pixels[i] = v;
                        pixels[i + 1] = v.wrapping_add(1);
                        pixels[i + 2] = v.wrapping_add(2);
                        pixels[i + 3] = 255;
                    }
                }
            })
            .expect("fill source");
        }
    }

    fn percentile(sorted: &[f32], p: f64) -> f32 {
        if sorted.is_empty() {
            return 0.0;
        }
        let idx = ((sorted.len() - 1) as f64 * p).round() as usize;
        sorted[idx]
    }

    struct Row {
        mode: EnhancementMode,
        source: FrameSize,
        requested: FrameSize,
        planned: FrameSize,
        path: String,
        bypass: Option<&'static str>,
        mean: f32,
        p50: f32,
        p95: f32,
        passes: u32,
    }

    pub fn main() {
        let args: Vec<String> = std::env::args().skip(1).collect();
        let frames: usize = parse(&args, "--frames")
            .and_then(|v| v.parse().ok())
            .unwrap_or(180);
        let only_mode = parse(&args, "--mode").map(|m| EnhancementMode::from_wire(&m));

        let device = match Device::system_default() {
            Some(d) => d,
            None => {
                eprintln!("no Metal device");
                std::process::exit(1);
            }
        };

        let mut backend = create_backend();
        let caps = backend.capabilities();
        println!(
            "# GPU video enhancement bench\n\nbackend={} adapter={} modes={:?}\nframes per case={} warmup=10\n",
            caps.backend, caps.reason, caps.modes, frames
        );

        let modes: Vec<EnhancementMode> = EnhancementMode::ALL
            .into_iter()
            .filter(|m| m.is_active())
            .filter(|m| only_mode.map(|o| o == *m).unwrap_or(true))
            .collect();

        let mut rows = Vec::new();
        for (source, display) in MATRIX {
            let src = make_source(&device, source);
            fill_pattern(&src, source.width, source.height);
            for &mode in &modes {
                let plan = plan::plan(
                    PlanRequest::new(mode).with_viewport(Some(*display)),
                    *source,
                );
                if !plan.is_active() {
                    rows.push(Row {
                        mode,
                        source: *source,
                        requested: *display,
                        planned: *source,
                        path: "-".into(),
                        bypass: plan.bypass_reason,
                        mean: 0.0,
                        p50: 0.0,
                        p95: 0.0,
                        passes: 0,
                    });
                    continue;
                }

                // Warm-up: allocate the ring and compile any lazy pipelines.
                for _ in 0..10 {
                    let _ = run(&mut backend, &src, *source, &plan);
                }

                let mut samples = Vec::with_capacity(frames);
                let mut passes = 0u32;
                for _ in 0..frames {
                    let t0 = Instant::now();
                    match run(&mut backend, &src, *source, &plan) {
                        Ok((_, reported)) => {
                            passes = reported;
                            samples.push(t0.elapsed().as_secs_f32() * 1000.0);
                        }
                        Err(err) => {
                            eprintln!("case {mode} {source:?}→{display:?} failed: {err}");
                            break;
                        }
                    }
                }
                if samples.is_empty() {
                    continue;
                }
                let mut sorted = samples.clone();
                sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
                let mean = samples.iter().sum::<f32>() / samples.len() as f32;
                rows.push(Row {
                    mode,
                    source: *source,
                    requested: *display,
                    planned: plan.target,
                    path: match plan.scaler {
                        plan::Scaler::Lanczos3 => "metal_lanczos_cas".into(),
                        plan::Scaler::CatmullRom => "metal_catmull_cas".into(),
                        plan::Scaler::None => "metal_cas".into(),
                    },
                    bypass: None,
                    mean,
                    p50: percentile(&sorted, 0.5),
                    p95: percentile(&sorted, 0.95),
                    passes,
                });
            }
        }

        println!("| mode | source | display | planned | path | passes | mean ms | p50 ms | p95 ms |");
        println!("| --- | --- | --- | --- | --- | --- | --- | --- | --- |");
        for row in &rows {
            let bypass = row.bypass.map(|r| format!(" (bypass: {r})")).unwrap_or_default();
            println!(
                "| {} | {}×{} | {}×{} | {}×{}{} | {} | {} | {:.3} | {:.3} | {:.3} |",
                row.mode,
                row.source.width,
                row.source.height,
                row.requested.width,
                row.requested.height,
                row.planned.width,
                row.planned.height,
                bypass,
                row.path,
                row.passes,
                row.mean,
                row.p50,
                row.p95
            );
        }
        println!(
            "\nDeadline check (30 fps = 33.3 ms, 60 fps = 16.7 ms): the stage must stay \
             well under the source interval, because the player also has to decode, \
             composite and present in the same budget."
        );
    }

    fn make_source(device: &Device, size: &FrameSize) -> IosurfacePixelBuffer {
        create_bgra_iosurface_pixel_buffer_metal(device, size.width, size.height)
            .expect("source surface")
    }

    /// One enhanced frame. Releases the output surface before returning, so
    /// the ring recycles exactly as it does in playback and the caller never
    /// holds a second reference to the same `+1`.
    fn run(
        backend: &mut Box<dyn EnhancementBackend>,
        source: &IosurfacePixelBuffer,
        size: FrameSize,
        plan: &plan::EnhancementPlan,
    ) -> Result<(FrameSize, u32), String> {
        let handed_off = metal_iosurface::retain_pixel_buffer(source.pixel_buffer);
        let frame = backend
            .process(FrameHandle::CvPixelBuffer(handed_off as usize), size, plan)
            .map_err(|e| e.to_string())?;
        let result = (frame.size, frame.passes);
        release(frame.handle);
        Ok(result)
    }

    fn release(handle: FrameHandle) {
        if let FrameHandle::CvPixelBuffer(p) = handle {
            metal_iosurface::release_pixel_buffer(p as CVPixelBufferRef);
        }
    }
}
