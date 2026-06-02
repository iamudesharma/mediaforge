#!/usr/bin/env bun
/**
 * Unified benchmark orchestrator — runs all three Rust crates and FFmpeg CLI baselines.
 *
 * Usage (from repo root):
 *   bun run benchmark/tools/run.ts
 *   bun run benchmark/tools/run.ts --skip-network
 *   bun run benchmark/tools/run.ts --skip-ffmpeg
 *   bun run benchmark/tools/run.ts --prefer-hardware
 *   bun run benchmark/tools/run.ts --skip-image
 *   bun run benchmark/tools/run.ts --skip-media-runtime
 *   bun run benchmark/tools/run.ts --skip-video
 */
import { spawnSync } from "child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
  statSync,
  rmSync,
} from "fs";
import { join, basename } from "path";

const root = join(import.meta.dir, "../.."); // repo root (benchmark/tools/ → root)
const repoRoot = root;
const outDir = join(root, "benchmark-results");
const fixturesDir = join(outDir, "fixtures");
const workDir = join(outDir, "bench-work");
const configPath = join(root, "benchmark/tools/fixtures.json");

const skipNetwork = process.argv.includes("--skip-network");
const skipFfmpeg = process.argv.includes("--skip-ffmpeg");
const skipImage = process.argv.includes("--skip-image");
const skipVideo = process.argv.includes("--skip-video");
const skipMediaRuntime = process.argv.includes("--skip-media-runtime");
const preferHardware = process.argv.includes("--prefer-hardware");

// ── Types ──

interface FixtureTier {
  id: string;
  label: string;
  local_file: string;
  network_url: string;
}

interface BenchRow {
  scenario_id: string;
  source: string;
  tier: string;
  tier_label: string;
  operation: string;
  input: string;
  input_bytes: number;
  duration_ms: number;
  success: boolean;
  error?: string;
  output_bytes?: number;
  encoder?: string;
  used_hardware?: boolean;
  pipeline_mode?: string;
  label?: string;
  frames?: number;
  fps?: number;
}

interface ImageRow {
  operation: string;
  backend: string;
  mean_ms: number;
  min_ms: number;
  max_ms: number;
  path: string;
}

interface RustReport {
  platform: string;
  timestamp_utc: string;
  compress_preset: string;
  rows: BenchRow[];
}

interface MediaReport {
  platform: string;
  timestamp_utc: string;
  decode_capabilities: {
    ffmpeg_version: string;
    hevc_vt: boolean;
    h264_vt: boolean;
    hw_disabled: boolean;
    ready_for_hevc_hw: boolean;
  };
  rows: BenchRow[];
}

interface FfmpegRow {
  tier: string;
  tier_label: string;
  input: string;
  input_bytes: number;
  compress_ms: number;
  thumbnail_ms: number;
  decode_audio_ms?: number;
  mix_audio_ms?: number;
  success: boolean;
  error?: string;
}

interface ImageReport {
  width: number;
  height: number;
  iterations: number;
  gpu_available: boolean;
  rows: ImageRow[];
}

// ── Helpers ──

function run(cmd: string, args: string[], cwd = root): boolean {
  const r = spawnSync(cmd, args, { cwd, stdio: "inherit", env: process.env });
  return r.status === 0;
}

function runCapture(cmd: string, args: string[], cwd = root): string {
  const r = spawnSync(cmd, args, {
    cwd,
    stdio: ["ignore", "pipe", "inherit"],
    env: process.env,
  });
  if (r.status !== 0) return "";
  return r.stdout.toString().trim();
}

function msSince(start: number): number {
  return Math.round(performance.now() - start);
}

function fmtMs(ms: number, success: boolean): string {
  return success ? `${ms.toLocaleString()} ms` : "failed";
}

// ── FFmpeg CLI baselines ──

function ffmpegCompress(
  input: string,
  output: string,
): { ms: number; ok: boolean; err?: string } {
  const start = performance.now();
  const ok = run("ffmpeg", [
    "-hide_banner", "-loglevel", "error", "-y",
    "-i", input,
    "-c:v", "libx264", "-crf", "23", "-preset", "medium",
    "-vf", "scale=1280:-2",
    "-c:a", "aac", "-b:a", "128k",
    "-movflags", "+faststart",
    output,
  ]);
  return { ms: msSince(start), ok, err: ok ? undefined : "ffmpeg compress failed" };
}

function ffmpegThumbnail(
  input: string,
  output: string,
): { ms: number; ok: boolean; err?: string } {
  const start = performance.now();
  const ok = run("ffmpeg", [
    "-hide_banner", "-loglevel", "error", "-y",
    "-ss", "2",
    "-i", input,
    "-frames:v", "1",
    "-vf", "scale=640:-2",
    "-q:v", "2",
    output,
  ]);
  return { ms: msSince(start), ok, err: ok ? undefined : "ffmpeg thumbnail failed" };
}

function ffmpegDecodeAudio(
  input: string,
): { ms: number; ok: boolean; err?: string } {
  const start = performance.now();
  const ok = run("ffmpeg", [
    "-hide_banner", "-loglevel", "error", "-y",
    "-i", input,
    "-vn",
    "-c:a", "pcm_f32le", "-ar", "48000", "-ac", "2",
    "-f", "null",
    "-",
  ]);
  return { ms: msSince(start), ok, err: ok ? undefined : "ffmpeg decode audio failed" };
}

function ffmpegMixAudio(
  track1: string,
  track2: string,
): { ms: number; ok: boolean; err?: string } {
  const start = performance.now();
  const ok = run("ffmpeg", [
    "-hide_banner", "-loglevel", "error", "-y",
    "-i", track1,
    "-i", track2,
    "-filter_complex", "[0:a][1:a]amix=inputs=2:duration=first:weights=0.7 0.3[a]",
    "-map", "[a]",
    "-c:a", "pcm_f32le", "-ar", "48000", "-ac", "2",
    "-f", "null",
    "-",
  ]);
  return { ms: msSince(start), ok, err: ok ? undefined : "ffmpeg mix audio failed" };
}

// ── Main orchestration ──

function main() {
  mkdirSync(outDir, { recursive: true });
  mkdirSync(fixturesDir, { recursive: true });
  mkdirSync(workDir, { recursive: true });

  console.log("==> Downloading fixtures (if needed)");
  if (!run("bash", [join(root, "benchmark/tools/download-fixtures.sh")])) {
    console.warn("Fixture download had issues; continuing with available files.");
  }

  const config = JSON.parse(readFileSync(configPath, "utf8")) as {
    tiers: FixtureTier[];
    audio_tracks?: { id: string; label: string; local_file: string; network_url: string }[];
  };

  // ── 1. Video processor benchmarks (vp_bench) ──
  let rustRows: BenchRow[] = [];
  let rustCompressPreset = "n/a";
  if (!skipVideo) {
    console.log("==> Building vp_bench (release)");
    const videoManifest = join(repoRoot, "packages/video_forge/Cargo.toml");
    if (
      !run("cargo", [
        "build", "--release", "--manifest-path", videoManifest, "--bin", "vp_bench",
      ])
    ) {
      process.exit(1);
    }

    const benchArgs = [
      "run", "--release", "--manifest-path", videoManifest, "--bin", "vp_bench", "--",
      "--fixtures-dir", fixturesDir,
      "--output", join(outDir, "rust-bench.json"),
      "--config", configPath,
    ];
    if (skipNetwork) benchArgs.push("--skip-network");
    if (preferHardware) benchArgs.push("--prefer-hardware");

    console.log(
      preferHardware
        ? "==> Running video processor benchmarks (hardware encoder preferred)"
        : "==> Running video processor benchmarks (software encoder)",
    );
    if (!run("cargo", benchArgs)) {
      process.exit(1);
    }

    const rustJson = readFileSync(join(outDir, "rust-bench.json"), "utf8");
    const rustReport: RustReport = JSON.parse(rustJson);
    rustRows = rustReport.rows;
    rustCompressPreset = rustReport.compress_preset;
  }

  // ── 2. Media runtime benchmarks (media_bench) ──
  let mediaRows: BenchRow[] = [];
  let mediaCaps: MediaReport["decode_capabilities"] | null = null;
  if (!skipMediaRuntime) {
    console.log("==> Building media_bench (release)");
    const mediaManifest = join(repoRoot, "packages/media_forge/rust/Cargo.toml");
    if (
      !run("cargo", [
        "build", "--release",
        "--manifest-path", mediaManifest,
        "--bin", "media_bench",
      ])
    ) {
      console.warn("media_bench build failed; skipping media runtime benchmarks.");
    } else {
      const mediaArgs = [
        "run", "--release",
        "--manifest-path", mediaManifest,
        "--bin", "media_bench", "--",
        "--fixtures-dir", fixturesDir,
        "--output", join(outDir, "media-bench.json"),
        "--config", configPath,
      ];

      console.log("==> Running media runtime benchmarks");
      if (!run("cargo", mediaArgs)) {
        console.warn("media_bench run failed; benchmark may be incomplete.");
      } else {
        const mediaJson = readFileSync(join(outDir, "media-bench.json"), "utf8");
        const mediaReport: MediaReport = JSON.parse(mediaJson);
        mediaRows = mediaReport.rows;
        mediaCaps = mediaReport.decode_capabilities;
      }
    }
  }

  // ── 3. Image benchmarks (image_forge_benchmark) ──
  let imageReport: ImageReport | null = null;
  if (!skipImage) {
    const imageManifest = join(repoRoot, "packages/image_forge/rust/Cargo.toml");
    const imageCsv = join(outDir, "image-bench.csv");
    console.log("==> Running image benchmarks");
    runCapture("cargo", [
      "run", "--manifest-path", imageManifest,
      "--release", "--features", "gpu",
      "--bin", "image_forge_benchmark",
      "--", "--synthetic", "--iterations", "5", "--csv", imageCsv,
    ]);

    if (existsSync(imageCsv)) {
      imageReport = parseImageCsv(readFileSync(imageCsv, "utf8"));
    } else {
      console.warn("Image benchmark failed to produce CSV output.");
    }
  }

  // ── 4. FFmpeg CLI baselines ──
  const ffmpegRows: FfmpegRow[] = [];
  if (!skipFfmpeg) {
    console.log("==> Running FFmpeg CLI baselines");

    // Audio decode: benchmark the BGM mp3 file (pure audio, no video)
    let audioDecodeMs: number | undefined;
    const bgmTrack = config.audio_tracks?.[0];
    if (bgmTrack) {
      const bgmPath = join(fixturesDir, bgmTrack.local_file);
      if (existsSync(bgmPath)) {
        const a = ffmpegDecodeAudio(bgmPath);
        audioDecodeMs = a.ok ? a.ms : undefined;
        console.log(`  audio_decode (BGM mp3): ${a.ms}ms`);
      }
    }

    // Audio mix: mix BGM with itself (2-track amix)
    let audioMixMs: number | undefined;
    if (bgmTrack) {
      const bgmPath = join(fixturesDir, bgmTrack.local_file);
      if (existsSync(bgmPath)) {
        const mix = ffmpegMixAudio(bgmPath, bgmPath);
        audioMixMs = mix.ok ? mix.ms : undefined;
        console.log(`  audio_mix (2-track amix, BGM×2): ${mix.ms}ms`);
      }
    }

    for (const tier of config.tiers) {
      const input = join(fixturesDir, tier.local_file);
      if (!existsSync(input)) continue;
      const ib = statSync(input).size;
      const outV = join(workDir, `ffmpeg_${tier.id}_out.mp4`);
      const outT = join(workDir, `ffmpeg_${tier.id}_thumb.jpg`);
      try { rmSync(outV, { force: true }); rmSync(outT, { force: true }); } catch (_) {}

      const c = ffmpegCompress(input, outV);
      const t = ffmpegThumbnail(input, outT);

      ffmpegRows.push({
        tier: tier.id,
        tier_label: tier.label,
        input: basename(input),
        input_bytes: ib,
        compress_ms: c.ms,
        thumbnail_ms: t.ms,
        decode_audio_ms: audioDecodeMs,
        mix_audio_ms: audioMixMs,
        success: c.ok && t.ok,
        error: c.err ?? t.err,
      });
      console.log(
        `  ${tier.id}: compress ${c.ms}ms, thumb ${t.ms}ms`,
      );
    }
    writeFileSync(join(outDir, "ffmpeg-bench.json"), JSON.stringify(ffmpegRows, null, 2));
  }

  // ── 5. Unified markdown output ──
  const md = renderUnifiedMarkdown(
    config, rustRows, rustCompressPreset,
    imageReport, mediaRows, mediaCaps,
    ffmpegRows, preferHardware,
  );
  writeFileSync(join(root, "benchmark-results/benchmarks.md"), md);

  // ── 6. Combined JSON ──
  writeFileSync(
    join(outDir, "results.json"),
    JSON.stringify(
      {
        generated_at: new Date().toISOString(),
        platform: process.platform,
        compress_preset: rustCompressPreset,
        image: imageReport,
        video: { rows: rustRows.filter((r) => r.operation !== "media_decode") },
        media_runtime: { rows: mediaRows, decode_capabilities: mediaCaps },
        ffmpeg_cli: ffmpegRows,
      },
      null,
      2,
    ),
  );

  console.log(`\n==> Wrote ${join(outDir, "benchmarks.md")}`);
  console.log(`==> Wrote ${join(outDir, "results.json")}`);
}

// ── Image benchmark CSV parser ──
function parseImageCsv(raw: string): ImageReport | null {
  const lines = raw.trim().split("\n");
  if (lines.length < 2) return null;

  const headers = lines[0].split(",");
  const idx = (name: string) => headers.indexOf(name);

  let width = 0, height = 0, iterations = 0, gpuAvailable = false;
  const rows: ImageRow[] = [];

  for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split(",");
    if (cols.length < headers.length) continue;

    const op = cols[idx("operation")];
    const backend = cols[idx("backend")];
    const mean = parseFloat(cols[idx("mean_ms")]);
    const min = parseFloat(cols[idx("min_ms")]);
    const max = parseFloat(cols[idx("max_ms")]);
    const path = cols[idx("path")];

    if (isNaN(mean)) continue;

    // Extract dimensions from first valid row
    if (width === 0) {
      width = parseInt(cols[idx("width")]) || 0;
      height = parseInt(cols[idx("height")]) || 0;
      iterations = parseInt(cols[idx("iterations")]) || 0;
      gpuAvailable = cols[idx("gpu_available")] === "true";
    }

    rows.push({ operation: op, backend, mean_ms: mean, min_ms: min, max_ms: max, path });
  }

  if (width === 0 || rows.length === 0) return null;
  return { width, height, iterations, gpu_available: gpuAvailable, rows };
}

// ── Unified markdown renderer ──

function renderUnifiedMarkdown(
  config: { tiers: FixtureTier[]; audio_tracks?: any[] },
  rustRows: BenchRow[],
  compressPreset: string,
  imageReport: ImageReport | null,
  mediaRows: BenchRow[],
  mediaCaps: MediaReport["decode_capabilities"] | null,
  ffmpegRows: FfmpegRow[],
  preferHardware: boolean,
): string {
  const hwMode = preferHardware || compressPreset.toLowerCase().includes("hardware");
  const ok = (r: BenchRow) => r.success;

  // ── Image section ──
  const imageSection = () => {
    if (!imageReport) return "_Image benchmarks skipped._";
    const { width, height, iterations, gpu_available: gpu, rows } = imageReport;
    const byBackend = (b: string) => rows.filter((r) => r.backend === b);
    const cpu = byBackend("cpu");
    const gpuRows = byBackend("gpu");
    const na = byBackend("n/a");

    const cmpRow = (cpuOp: string, label: string) => {
      const c = cpu.find((r) => r.operation === cpuOp);
      const g = gpuRows.find((r) => r.operation === cpuOp);
      const cMs = c ? `${c.mean_ms.toFixed(1)} ms` : "—";
      const gMs = g ? `${g.mean_ms.toFixed(1)} ms` : "—";
      let speedup = "";
      if (c && g && c.mean_ms > 0 && g.mean_ms > 0) {
        const ratio = c.mean_ms / g.mean_ms;
        speedup = ratio > 1
          ? ` (${ratio.toFixed(1)}× faster)`
          : ` (${(g.mean_ms / c.mean_ms).toFixed(1)}× slower)`;
      }
      return `| ${label} | ${cMs} | ${gMs} |${speedup} |`;
    };

    const naTable = na.map((r) =>
      `| ${r.operation} | ${r.mean_ms.toFixed(1)} ms | ${r.min_ms.toFixed(1)} ms | ${r.max_ms.toFixed(1)} ms |`,
    ).join("\n");

    return `## Image processing (image_forge)

> ${width}×${height} · ${iterations} iterations · GPU: ${gpu ? "available" : "unavailable"} · \`cargo run --release --features gpu\`

### CPU vs GPU (RGBA pipeline)

| Operation | CPU (mean) | GPU (mean) | Speedup |
|-----------|-----------|-----------|---------|
${cmpRow("resize_rgba_50pct", "Resize 50%")}
${cmpRow("filter_rgba_blur", "Blur (r=4)")}
${cmpRow("filter_rgba_sharpen", "Sharpen")}
${cmpRow("filter_rgba_brightness", "Brightness")}
${cmpRow("filter_rgba_contrast", "Contrast")}
${cmpRow("filter_rgba_saturation", "Saturation")}
${cmpRow("filter_rgba_preset_dramatic", "Dramatic preset")}

### Bytes APIs (backend = n/a)

| Operation | Mean | Min | Max |
|-----------|------|-----|-----|
${naTable}`;
  };

  // ── Video compression section ──
  const videoSection = () => {
    if (rustRows.length === 0) return "_Video benchmarks skipped._";
    const byOp = (op: string) => rustRows.filter((r) => r.operation === op && ok(r));
    const compressRows = byOp("compress");
    const thumbRows = byOp("thumbnail");
    const batchRows = byOp("batch_thumbnails_10");
    const probeRows = byOp("probe");

    const hdr = hwMode
      ? ["| Tier | Label | Encoder · pipeline (local) | Local file | Network URL |",
         "|------|-------|--------------------------|------------|-------------|"]
      : ["| Tier | Label | Local file | Network URL |",
         "|------|-------|------------|-------------|"];

    const tiers = ["small", "medium", "large"];
    for (const tier of tiers) {
      const label = compressRows.find((r) => r.tier === tier)?.tier_label ?? tier;
      const local = compressRows.find((r) => r.source === "local" && r.tier === tier);
      const net = compressRows.find((r) => r.source === "network" && r.tier === tier);
      const enc = local?.encoder
        ? `${local.encoder}${local.used_hardware ? " (HW)" : " (SW)"}${local.pipeline_mode ? ` · ${local.pipeline_mode}` : ""}`
        : "—";
      if (hwMode) {
        hdr.push(`| **${tier}** | ${label} | ${enc} | ${local ? fmtMs(local.duration_ms, true) : "—"} | ${skipNetwork ? "skipped" : net ? fmtMs(net.duration_ms, true) : "—"} |`);
      } else {
        hdr.push(`| **${tier}** | ${label} | ${local ? fmtMs(local.duration_ms, true) : "—"} | ${skipNetwork ? "skipped" : net ? fmtMs(net.duration_ms, true) : "—"} |`);
      }
    }

    // vs FFmpeg comparison
    const speedupLines: string[] = [];
    for (const fr of ffmpegRows) {
      const ours = compressRows.find((r) => r.source === "local" && r.tier === fr.tier);
      if (!ours || !fr.success) continue;
      const ratio = fr.compress_ms / ours.duration_ms;
      const pct = ((1 - ours.duration_ms / fr.compress_ms) * 100).toFixed(0);
      const faster = ours.duration_ms < fr.compress_ms;
      speedupLines.push(
        `- **${fr.tier}** (${fr.tier_label}): flutter_video_forge **${fmtMs(ours.duration_ms, true)}** vs FFmpeg CLI **${fr.compress_ms.toLocaleString()} ms** — ${faster ? `${pct}% faster` : `${Math.abs(Number(pct))}% slower`} (×${ratio.toFixed(2)})`,
      );
    }

    // Thumbnail comparison
    const thumbVsFF: string[] = [];
    for (const fr of ffmpegRows) {
      const ours = thumbRows.find((r) => r.source === "local" && r.tier === fr.tier);
      if (!ours || !fr.success) continue;
      const faster = ours.duration_ms < fr.thumbnail_ms;
      const pct = ((1 - ours.duration_ms / fr.thumbnail_ms) * 100).toFixed(0);
      thumbVsFF.push(`- **${fr.tier}**: flutter_video_forge **${fmtMs(ours.duration_ms, true)}** vs FFmpeg CLI **${fr.thumbnail_ms.toLocaleString()} ms** — ${faster ? `${pct}% faster` : `${Math.abs(Number(pct))}% slower`}`);
    }

    return `## Video compression & thumbnails (video_forge)

> Compress: medium preset, H.264 ${hwMode ? "hardware preferred" : "software"} · \`cargo run --release --bin vp_bench\`

### Compression

${hdr.join("\n")}

### Compress vs FFmpeg CLI (local files, same CRF 23 / medium / 1280px wide)

${speedupLines.length ? speedupLines.join("\n") : "_FFmpeg baseline not run._"}

### Thumbnail (1 frame @ 2s, 640px wide JPEG)

| Tier | Local file | Network URL |
|------|------------|-------------|
${tiers.map((tier) => {
  const local = thumbRows.find((r) => r.source === "local" && r.tier === tier);
  const net = thumbRows.find((r) => r.source === "network" && r.tier === tier);
  return `| **${tier}** | ${local ? fmtMs(local.duration_ms, true) : "—"} | ${skipNetwork ? "skipped" : net ? fmtMs(net.duration_ms, true) : "—"} |`;
}).join("\n")}

### Thumbnail vs FFmpeg CLI (local)

${thumbVsFF.length ? thumbVsFF.join("\n") : "_FFmpeg baseline not run._"}

### Batch thumbnails (10 frames @ 1s interval, 320px wide)

| Tier | Local file | Network URL |
|------|------------|-------------|
${tiers.map((tier) => {
  const local = batchRows.find((r) => r.source === "local" && r.tier === tier);
  const net = batchRows.find((r) => r.source === "network" && r.tier === tier);
  const label = local?.tier_label ?? tier;
  return `| **${tier}** (${label}) | ${local ? fmtMs(local.duration_ms, true) : "—"} | ${skipNetwork ? "skipped" : net ? fmtMs(net.duration_ms, true) : "—"} |`;
}).join("\n")}

### Metadata probe

| Tier | Local file | Network URL |
|------|------------|-------------|
${tiers.map((tier) => {
  const local = probeRows.find((r) => r.source === "local" && r.tier === tier);
  const net = probeRows.find((r) => r.source === "network" && r.tier === tier);
  return `| **${tier}** | ${local ? fmtMs(local.duration_ms, true) : "—"} | ${skipNetwork ? "skipped" : net ? fmtMs(net.duration_ms, true) : "—"} |`;
}).join("\n")}`;
  };

  // ── Media runtime section ──
  const mediaSection = () => {
    if (mediaRows.length === 0) return "_Media runtime benchmarks skipped._";
    const byOp = (op: string) => mediaRows.filter((r) => r.operation === op && ok(r));
    const caps = mediaCaps;

    const openRows = byOp("open_file");
    const firstFrameRows = byOp("first_video_frame");
    const videoFpsRows = byOp("video_decode_fps");
    const audioFpsRows = byOp("audio_decode_fps");
    const seekRows = byOp("seek_recovery");
    const tiers = ["small", "medium", "large"];

    // Video decode FPS table
    const decodeFpsLines = tiers.map((tier) => {
      const r = videoFpsRows.find((x) => x.tier === tier);
      const a = audioFpsRows.find((x) => x.tier === tier);
      const label = r?.tier_label ?? tier;
      return `| **${tier}** | ${label} | ${r ? `${r.fps?.toFixed(1) ?? "—"} fps` : "—"} | ${a ? `${a.fps?.toFixed(1) ?? "—"} fps` : "—"} |`;
    }).join("\n");

    // Seek recovery table
    const seekLines: string[] = [];
    for (const tier of tiers) {
      const seeks = seekRows.filter((r) => r.tier === tier);
      if (seeks.length === 0) continue;
      const label = seeks[0]?.tier_label ?? tier;
      const parts = seeks.map((s) => {
        const target = s.label?.match(/target=(\d+)ms/)?.at(1) ?? "?";
        return `${target}ms: ${fmtMs(s.duration_ms, s.success)}`;
      }).join(" · ");
      seekLines.push(`| **${tier}** | ${label} | ${parts} |`);
    }

    return `## Media runtime (media_forge)

> Real-time decode/mix engine · \`cargo run --release --bin media_bench\`

### Decode capabilities

| Metric | Value |
|--------|-------|
| FFmpeg version | ${caps?.ffmpeg_version ?? "—"} |
| HEVC VideoToolbox | ${caps?.hevc_vt ?? "—"} |
| H.264 VideoToolbox | ${caps?.h264_vt ?? "—"} |
| HW decode disabled | ${caps?.hw_disabled ?? "—"} |
| Ready for HEVC HW | ${caps?.ready_for_hevc_hw ?? "—"} |

### File open & first frame latency

| Tier | Label | Open | First video frame |
|------|-------|------|-------------------|
${tiers.map((tier) => {
  const o = openRows.find((r) => r.tier === tier);
  const f = firstFrameRows.find((r) => r.tier === tier);
  const label = o?.tier_label ?? tier;
  return `| **${tier}** | ${label} | ${o ? fmtMs(o.duration_ms, o.success) : "—"} | ${f ? fmtMs(f.duration_ms, f.success) : "—"} |`;
}).join("\n")}

### Decode throughput (sustained ~3s window)

| Tier | Label | Video decode | Audio decode |
|------|-------|-------------|-------------|
${decodeFpsLines}

### Seek recovery latency

| Tier | Label | 25% · 50% · 75% |
|------|-------|-----------------|
${seekLines.length ? seekLines.join("\n") : "| — | — | — |"}`;
  };

  // ── Audio decode & mix (FFmpeg CLI baseline) ──
  const audioFfmpegSection = () => {
    if (ffmpegRows.length === 0) return "";
    const r = ffmpegRows[0]; // audio values are global, same for all tiers
    const hasAudioDecode = r.decode_audio_ms != null;
    const hasAudioMix = r.mix_audio_ms != null;

    if (!hasAudioDecode && !hasAudioMix) return "";

    const decodeMs = hasAudioDecode ? `${r.decode_audio_ms!.toLocaleString()} ms` : "—";
    const mixMs = hasAudioMix ? `${r.mix_audio_ms!.toLocaleString()} ms` : "—";
    const mixColHdr = hasAudioMix ? " Audio mix |" : "";
    const mixColSep = hasAudioMix ? "---------|" : "";
    const mixColVal = hasAudioMix ? ` ${mixMs} |` : "";

    return `## Audio decode & mixing (FFmpeg CLI baseline)

> PCM f32le 48kHz stereo decode of ~1min MP3 (SoundHelix-Song-1.mp3) · 2-track amix for overlay simulation

| Operation | Duration |${mixColHdr}
|-----------|----------|${mixColSep}
| Audio decode (BGM MP3) | ${decodeMs} |${mixColVal}`;
  };

  // ── Assemble final markdown ──
  const sections = [
    `# Unified Benchmark Results

> Auto-generated by \`bun run benchmark/tools/run.ts\` on **${process.platform}** at \`${new Date().toISOString()}\`.
> Re-run locally: \`bun run benchmark/tools/run.ts${preferHardware ? " --prefer-hardware" : ""}\`

## Summary

| Package | Role | Approach |
|---------|------|----------|
| **image_forge** | Image processing | Rust native, CPU vs GPU (Metal/Vulkan wgpu) |
| **video_forge** | Video compress/thumbnails | Rust + FFmpeg, HW & SW encode, vs FFmpeg CLI |
| **media_forge** | Media playback runtime | Real-time decode/mix, cpal audio, VideoToolbox HW decode |
`,
    imageSection(),
    videoSection(),
    mediaSection(),
    audioFfmpegSection(),
    `## Methodology

1. **Image** — 1280×720 synthetic JPEG, 5 iterations, \`cargo run --release --features gpu --bin image_forge_benchmark\`
2. **Video** — Big Buck Bunny 360p/720p/1080p ~10s, \`vp_bench\` binary → \`run_compress\`, \`extract_thumbnail\`, \`probe_media_info\`
3. **Media runtime** — Same fixtures, \`media_bench\` binary → open, decode FPS, seek recovery
4. **FFmpeg CLI** — \`ffmpeg -crf 23 -preset medium\` compress; \`-ss 2 -frames:v 1\` thumbnail; \`pcm_f32le\` audio decode; \`amix\` overlay mix
5. **Hardware** — ${hwMode ? "enabled (\`--prefer-hardware\` → VideoToolbox / MediaCodec / NVENC / VAAPI)" : "software only; pass \`--prefer-hardware\` for HW encoders"}

## Reproduce

\`\`\`bash
# Full suite
bun run benchmark/tools/run.ts
# With hardware encoders
bun run benchmark/tools/run.ts --prefer-hardware
# Skip sections
bun run benchmark/tools/run.ts --skip-image --skip-network --skip-ffmpeg
# Image-only
bun run benchmark/tools/run.ts --skip-video --skip-media-runtime --skip-ffmpeg
\`\`\`

Raw JSON: \`benchmark-results/rust-bench.json\`, \`benchmark-results/media-bench.json\`, \`benchmark-results/ffmpeg-bench.json\`, \`benchmark-results/results.json\`.

## Competitor notes (qualitative)

| Package | Backend | Notes |
|---------|---------|-------|
| **image_forge** | Rust + wgpu | GPU filters (blur, sharpen, presets) on Metal/Vulkan; CPU fallback via rayon |
| **flutter_video_processor** | Rust + FFmpeg | Background jobs, progress, cancel, network URLs, batch thumbnails |
| **media_forge** | Rust + FFmpeg + cpal | Real-time decode + audio mixing, VT HW decode on Apple, paused-seek display |
| **FFmpeg CLI** | FFmpeg | Public baseline for FFmpeg-based plugins |
| **video_compress** | OS media APIs | Fast on mobile when HW path fits; fewer codec knobs |
| **ffmpeg_kit** | FFmpeg CLI wrapped | Similar encode quality; heavier bundle; command-string API |

_Publish numbers from a dedicated benchmark machine — run the script above on release candidates._`,
  ];

  return sections.filter(Boolean).join("\n\n");
}

main();
