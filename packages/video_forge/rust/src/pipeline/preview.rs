//! Single-frame preview decode for texture display (Sprint V1.1+).
//!
//! V1.1: RGBA via thumbnail CPU path. V1.4: Apple VideoToolbox → BGRA `CVPixelBuffer`.
//! Sprint 1: Persistent thread-safe decoder session `VideoPreviewSession` via single background thread.

use std::sync::mpsc::{channel, Receiver, Sender};
use std::thread;

use ffmpeg_next::codec::context::Context as CodecContext;
use ffmpeg_next::codec::discard::Discard;
use ffmpeg_next::format::Pixel;
use ffmpeg_next::software::scaling::context::Context as ScalerContext;
use ffmpeg_next::util::frame::video::Video as VideoFrame;
use ffmpeg_next::Rational;

use crate::error::{Result, VideoForgeError};
use crate::ffmpeg::{
    apply_preview_scrub_decoder_settings, apply_thumbnail_decoder_settings,
    ensure_ffmpeg_initialized, ensure_input_accessible, flush_video_decoder, map_ffmpeg_error,
    ms_to_stream_ts, open_input, open_input_for_preview, open_video_decoder,
    preview_needs_clean_seek, seek_stream_backward, should_use_hw_preview,
};
use crate::jobs::registry::CancellationToken;
use crate::pipeline::thumbnail::{thumb_dimensions, video_to_rgb};
use crate::types::{PlaybackFrame, PreviewFramePixelBuffer, PreviewFrameRgba};

#[cfg(any(target_os = "ios", target_os = "macos"))]
use super::preview_hw;

#[cfg(any(target_os = "ios", target_os = "macos"))]
pub use preview_hw::hw_preview_enabled;

#[cfg(not(any(target_os = "ios", target_os = "macos")))]
pub fn hw_preview_enabled() -> bool {
    false
}

/// Frames before target where we stop skipping non-keyframes (session scrub).
const PREVIEW_GOP_APPROACH_MS: u64 = 280;

/// Playback: accept frames at or after (wall target − margin).
const PLAYBACK_CATCHUP_MARGIN_MS: u64 = 40;

/// Playback: seek to keyframe when wall-clock drift exceeds this (ms).
const PLAYBACK_SEEK_CATCHUP_MS: u64 = 400;

/// Max sequential decodes to drop before forcing a seek during playback.
const PLAYBACK_MAX_SKIP_DECODES: u32 = 48;

fn playback_target_pts_ms(
    start_inst: std::time::Instant,
    start_pts_ms: u64,
    rate: f64,
) -> u64 {
    let elapsed_ms = start_inst.elapsed().as_secs_f64() * 1000.0 * rate;
    start_pts_ms.saturating_add(elapsed_ms as u64)
}

fn release_playback_rgba(frame: PreviewFrameRgba) {
    crate::pool::release_buffer(frame.rgba);
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
fn release_playback_pixel_buffer(frame: PreviewFramePixelBuffer) {
    release_preview_pixel_buffer(frame.pixel_buffer_ptr);
}

/// Decode one preview frame at [position_ms], scaled so the longest edge is at most [max_edge].
pub fn decode_preview_frame_rgba(
    input_path: &str,
    position_ms: u64,
    max_edge: Option<u32>,
) -> Result<PreviewFrameRgba> {
    let token = CancellationToken::new();
    let max_w = max_edge;
    // Use the cache-aware variant so repeated calls on the same path
    // skip the FFmpeg open (the dominant cost for iPhone HEVC + DV
    // MOV with deep probe budgets). The cache is a no-op if disabled.
    let rgb = crate::pipeline::thumbnail::decode_scrub_rgb_frame_at_cached(
        input_path.trim(),
        position_ms,
        max_w,
        None,
        token,
    )?;
    let rgba = rgb24_to_rgba8888(&rgb.data, rgb.width, rgb.height)?;
    Ok(PreviewFrameRgba {
        pts_ms: position_ms,
        width: rgb.width,
        height: rgb.height,
        rgba,
    })
}

/// Apple HW path: VideoToolbox decode → BGRA `CVPixelBuffer` (hand off via [pixel_buffer_ptr]).
pub fn decode_preview_frame_pixel_buffer(
    input_path: &str,
    position_ms: u64,
    max_edge: Option<u32>,
) -> Result<PreviewFramePixelBuffer> {
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        return preview_hw::decode_preview_pixel_buffer(input_path, position_ms, max_edge);
    }
    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    {
        let _ = (input_path, position_ms, max_edge);
        Err(VideoForgeError::Internal(
            "HW preview decode is only available on Apple platforms".into(),
        ))
    }
}

/// Release a preview buffer when not presented to the texture plugin.
#[cfg(any(target_os = "ios", target_os = "macos"))]
pub fn release_preview_pixel_buffer(ptr: u64) {
    if ptr == 0 {
        return;
    }
    unsafe {
        crate::ffmpeg::vt_pipeline::release_pixel_buffer(ptr as *mut std::ffi::c_void);
    }
}

#[cfg(not(any(target_os = "ios", target_os = "macos")))]
pub fn release_preview_pixel_buffer(_ptr: u64) {}

fn rgb24_to_rgba8888(rgb: &[u8], width: u32, height: u32) -> Result<Vec<u8>> {
    let w = width as usize;
    let h = height as usize;
    let expected = w * h * 3;
    if rgb.len() < expected {
        return Err(VideoForgeError::Internal(format!(
            "RGB buffer too small: got {} need {expected}",
            rgb.len()
        )));
    }
    let mut rgba = crate::pool::acquire_rgba_buffer(width, height);
    rgba.clear();
    rgba.reserve(w * h * 4);
    for i in 0..(w * h) {
        let si = i * 3;
        rgba.push(rgb[si]);
        rgba.push(rgb[si + 1]);
        rgba.push(rgb[si + 2]);
        rgba.push(255);
    }
    Ok(rgba)
}

fn frame_pts_ms(frame: &VideoFrame, tb: Rational) -> u64 {
    let pts = frame.timestamp().unwrap_or(0);
    let ms = pts as f64 * tb.0 as f64 / tb.1 as f64 * 1000.0;
    ms.max(0.0) as u64
}

// Commands sent from frontend FFI to background thread.
enum SessionCommand {
    NextFrameRgba {
        reply: Sender<Result<Option<PreviewFrameRgba>>>,
    },
    NextFramePixelBuffer {
        reply: Sender<Result<Option<PreviewFramePixelBuffer>>>,
    },
    SeekAndDecodeRgba {
        position_ms: u64,
        reply: Sender<Result<PreviewFrameRgba>>,
    },
    SeekAndDecodePixelBuffer {
        position_ms: u64,
        reply: Sender<Result<PreviewFramePixelBuffer>>,
    },
    StartPlayback {
        rate: f64,
        sink: crate::frb_generated::StreamSink<PlaybackFrame, flutter_rust_bridge::for_generated::SseCodec>,
    },
    PausePlayback,
    SetMaxEdge {
        max_edge: Option<u32>,
    },
}

/// Persistent, single-threaded video playback decoder session.
pub struct VideoPreviewSession {
    cmd_tx: std::sync::Arc<parking_lot::Mutex<Sender<SessionCommand>>>,
    worker: Option<thread::JoinHandle<()>>,
}

// Ensure the FFI-exposed handle is Send. Since access to cmd_tx is locked
// and the FFmpeg context only runs on a single background worker thread, this is fully safe.
unsafe impl Send for VideoPreviewSession {}

impl VideoPreviewSession {
    pub fn new(
        input_path: String,
        max_edge: Option<u32>,
        prefer_hw: bool,
    ) -> Result<Self> {
        let (cmd_tx, cmd_rx) = channel::<SessionCommand>();

        let worker = thread::Builder::new()
            .name("video_preview_worker".into())
            .spawn(move || {
                if let Err(e) = run_worker(input_path, max_edge, prefer_hw, cmd_rx) {
                    log::error!("video preview worker finished with error: {:?}", e);
                }
            })
            .map_err(|e| {
                VideoForgeError::Internal(format!(
                    "failed to spawn preview worker thread: {e}"
                ))
            })?;

        Ok(Self {
            cmd_tx: std::sync::Arc::new(parking_lot::Mutex::new(cmd_tx)),
            worker: Some(worker),
        })
    }

    pub fn read_next_rgba(&self) -> Result<Option<PreviewFrameRgba>> {
        let (reply_tx, reply_rx) = channel();
        self.cmd_tx
            .lock()
            .send(SessionCommand::NextFrameRgba { reply: reply_tx })
            .map_err(|_| VideoForgeError::Internal("worker thread hung up".into()))?;
        reply_rx
            .recv()
            .map_err(|_| VideoForgeError::Internal("worker thread hung up".into()))?
    }

    pub fn read_next_pixel_buffer(&self) -> Result<Option<PreviewFramePixelBuffer>> {
        let (reply_tx, reply_rx) = channel();
        self.cmd_tx
            .lock()
            .send(SessionCommand::NextFramePixelBuffer { reply: reply_tx })
            .map_err(|_| VideoForgeError::Internal("worker thread hung up".into()))?;
        reply_rx
            .recv()
            .map_err(|_| VideoForgeError::Internal("worker thread hung up".into()))?
    }

    pub fn seek_and_read_rgba(&self, position_ms: u64) -> Result<PreviewFrameRgba> {
        let (reply_tx, reply_rx) = channel();
        self.cmd_tx
            .lock()
            .send(SessionCommand::SeekAndDecodeRgba {
                position_ms,
                reply: reply_tx,
            })
            .map_err(|_| VideoForgeError::Internal("worker thread hung up".into()))?;
        reply_rx
            .recv()
            .map_err(|_| VideoForgeError::Internal("worker thread hung up".into()))?
    }

    pub fn seek_and_read_pixel_buffer(
        &self,
        position_ms: u64,
    ) -> Result<PreviewFramePixelBuffer> {
        let (reply_tx, reply_rx) = channel();
        self.cmd_tx
            .lock()
            .send(SessionCommand::SeekAndDecodePixelBuffer {
                position_ms,
                reply: reply_tx,
            })
            .map_err(|_| VideoForgeError::Internal("worker thread hung up".into()))?;
        reply_rx
            .recv()
            .map_err(|_| VideoForgeError::Internal("worker thread hung up".into()))?
    }

    pub fn start_playback_inner(&self, rate: f64, sink: crate::frb_generated::StreamSink<PlaybackFrame, flutter_rust_bridge::for_generated::SseCodec>) -> Result<()> {
        self.cmd_tx
            .lock()
            .send(SessionCommand::StartPlayback { rate, sink })
            .map_err(|_| VideoForgeError::Internal("worker thread hung up".into()))
    }

    pub fn pause_playback_inner(&self) -> Result<()> {
        self.cmd_tx
            .lock()
            .send(SessionCommand::PausePlayback)
            .map_err(|_| VideoForgeError::Internal("worker thread hung up".into()))
    }

    pub fn set_max_edge_inner(&self, max_edge: Option<u32>) -> Result<()> {
        self.cmd_tx
            .lock()
            .send(SessionCommand::SetMaxEdge { max_edge })
            .map_err(|_| VideoForgeError::Internal("worker thread hung up".into()))
    }

    pub fn shutdown(&self) {
        // Worker drops when the Sender drops.
    }
}

impl Drop for VideoPreviewSession {
    fn drop(&mut self) {
        // Drop the sender channel first. This closes command reception
        // causing the worker thread loop to exit naturally.
        if let Some(worker) = self.worker.take() {
            // Drop locks to ensure sender is released.
            drop(self.cmd_tx.lock());
            let _ = worker.join();
        }
    }
}

/// State that tracks whether we've fallen back to software decode.
struct WorkerState {
    playing: bool,
    playback_rate: f64,
    playback_sink: Option<crate::frb_generated::StreamSink<PlaybackFrame, flutter_rust_bridge::for_generated::SseCodec>>,
    playback_start_instant: Option<std::time::Instant>,
    playback_start_pts_ms: u64,
    current_pts_ms: u64,
    pending_cmd: Option<SessionCommand>,
    /// Set to `true` after a HW decode failure triggers fallback to software.
    using_sw_fallback: bool,
    /// iPhone HEVC / DV — flush/seek recovery before full demuxer reopen.
    reliable_sw_preview: bool,
    decode_error_streak: u32,
}

struct PreviewWorkerLogGuard;

impl PreviewWorkerLogGuard {
    fn enter() -> Self {
        crate::ffmpeg::log::preview_worker_thread_enter();
        Self
    }
}

impl Drop for PreviewWorkerLogGuard {
    fn drop(&mut self) {
        crate::ffmpeg::log::preview_worker_thread_exit();
    }
}

fn run_worker(
    input_path: String,
    max_edge: Option<u32>,
    prefer_hw: bool,
    cmd_rx: Receiver<SessionCommand>,
) -> Result<()> {
    let _log_guard = PreviewWorkerLogGuard::enter();
    ensure_ffmpeg_initialized()?;
    let input = input_path.trim();
    ensure_input_accessible(input)?;
    let mut preview_max_edge = max_edge;

    let iphone_container = {
        let lower = input.to_ascii_lowercase();
        lower.ends_with(".mov") || lower.ends_with(".m4v")
    };
    let mut ictx = if iphone_container {
        open_input_for_preview(input)?
    } else {
        open_input(input)?
    };
    let stream = ictx
        .streams()
        .best(ffmpeg_next::media::Type::Video)
        .ok_or_else(|| VideoForgeError::InvalidInput("no video stream".into()))?;
    let stream_idx = stream.index();
    let tb = stream.time_base();
    let params = stream.parameters();

    let use_hw = should_use_hw_preview(prefer_hw, &params, input);
    if prefer_hw && !use_hw {
        log::info!(
            "preview: using software decode for this asset (Dolby Vision / HW preview disabled)"
        );
    }

    let (mut decoder, mut hw) = if use_hw {
        open_video_decoder(params.clone(), true)
            .map_err(|e| VideoForgeError::Internal(e.to_string()))?
    } else {
        let mut dec_ctx = CodecContext::from_parameters(params.clone()).map_err(map_ffmpeg_error)?;
        if preview_needs_clean_seek(&params, input) {
            apply_preview_scrub_decoder_settings(&mut dec_ctx);
        } else {
            apply_thumbnail_decoder_settings(&mut dec_ctx);
        }
        let decoder = dec_ctx.decoder().video().map_err(map_ffmpeg_error)?;
        (decoder, None)
    };

    let mut session_use_hw = use_hw;
    let reliable_sw_preview = preview_needs_clean_seek(&params, input);

    let mut color_scaler: Option<ScalerContext> = None;
    let mut color_src_key: Option<(u32, u32, Pixel, u32, u32)> = None;

    let mut state = WorkerState {
        playing: false,
        playback_rate: 1.0,
        playback_sink: None,
        playback_start_instant: None,
        playback_start_pts_ms: 0,
        current_pts_ms: 0,
        pending_cmd: None,
        using_sw_fallback: false,
        reliable_sw_preview,
        decode_error_streak: 0,
    };

    loop {
        // Read next command
        let cmd = if let Some(p) = state.pending_cmd.take() {
            Some(p)
        } else if state.playing {
            // Check command channel non-blockingly while playing
            cmd_rx.try_recv().ok()
        } else {
            // Block until next command when paused
            cmd_rx.recv().ok()
        };

        if let Some(cmd) = cmd {
            match cmd {
                SessionCommand::NextFrameRgba { reply } => {
                    let res = do_next_frame_rgba(
                        &mut ictx,
                        &mut decoder,
                        stream_idx,
                        tb,
                        preview_max_edge,
                        &mut color_scaler,
                        &mut color_src_key,
                    );
                    if let Ok(Some(ref f)) = res {
                        state.current_pts_ms = f.pts_ms;
                    }
                    let _ = reply.send(res);
                }
                SessionCommand::NextFramePixelBuffer { reply } => {
                    let res = do_next_frame_pixel_buffer(
                        &mut ictx,
                        &mut decoder,
                        stream_idx,
                        tb,
                        preview_max_edge,
                        &mut hw,
                    );
                    if let Ok(Some(ref f)) = res {
                        state.current_pts_ms = f.pts_ms;
                    }
                    let _ = reply.send(res);
                }
                SessionCommand::SeekAndDecodeRgba { position_ms, reply } => {
                    state.playing = false;
                    let mut res = do_seek_and_decode_rgba(
                        input,
                        &mut ictx,
                        &mut decoder,
                        stream_idx,
                        tb,
                        position_ms,
                        preview_max_edge,
                        &mut hw,
                        &mut color_scaler,
                        &mut color_src_key,
                        false,
                        state.reliable_sw_preview,
                    );
                    if res.is_err() && session_use_hw && !state.using_sw_fallback {
                        if let Ok(new_decoder) = fallback_to_sw_decode(
                            input,
                            &mut ictx,
                            &mut decoder,
                            stream_idx,
                            &mut hw,
                            &mut color_scaler,
                            &mut color_src_key,
                            position_ms,
                        ) {
                            decoder = new_decoder;
                            state.using_sw_fallback = true;
                            session_use_hw = false;
                            res = do_seek_and_decode_rgba(
                                input,
                                &mut ictx,
                                &mut decoder,
                                stream_idx,
                                tb,
                                position_ms,
                                preview_max_edge,
                                &mut hw,
                                &mut color_scaler,
                                &mut color_src_key,
                                false,
                                true,
                            );
                        }
                    }
                    if let Ok(ref f) = res {
                        state.current_pts_ms = f.pts_ms;
                        state.decode_error_streak = 0;
                    }
                    let _ = reply.send(res);
                }
                SessionCommand::SeekAndDecodePixelBuffer { position_ms, reply } => {
                    state.playing = false;
                    if !session_use_hw || state.using_sw_fallback {
                        let _ = reply.send(Err(VideoForgeError::Internal(
                            "PREVIEW_RGBA_ONLY".into(),
                        )));
                        continue;
                    }
                    let mut res = do_seek_and_decode_pixel_buffer(
                        &mut ictx,
                        &mut decoder,
                        stream_idx,
                        tb,
                        position_ms,
                        preview_max_edge,
                        &mut hw,
                    );
                    if res.is_err() && session_use_hw && !state.using_sw_fallback {
                        log::warn!(
                            "HW preview seek failed at {position_ms}ms, falling back to software: {:?}",
                            res.as_ref().err()
                        );
                        if let Ok(new_decoder) = fallback_to_sw_decode(
                            input,
                            &mut ictx,
                            &mut decoder,
                            stream_idx,
                            &mut hw,
                            &mut color_scaler,
                            &mut color_src_key,
                            position_ms,
                        ) {
                            decoder = new_decoder;
                            state.using_sw_fallback = true;
                            session_use_hw = false;
                            res = Err(VideoForgeError::Internal(
                                "PREVIEW_RGBA_ONLY".into(),
                            ));
                        }
                    }
                    if let Ok(ref f) = res {
                        state.current_pts_ms = f.pts_ms;
                    }
                    let _ = reply.send(res);
                }
                SessionCommand::StartPlayback { rate, sink } => {
                    state.playing = true;
                    state.playback_rate = rate;
                    state.playback_sink = Some(sink);
                    state.playback_start_instant = Some(std::time::Instant::now());
                    state.playback_start_pts_ms = state.current_pts_ms;
                }
                SessionCommand::PausePlayback => {
                    state.playing = false;
                    state.playback_sink = None;
                }
                SessionCommand::SetMaxEdge { max_edge } => {
                    preview_max_edge = max_edge;
                    color_scaler.take();
                    color_src_key.take();
                }
            }
        } else if state.playing {
            let has_hw = session_use_hw && !state.using_sw_fallback;
            let start_inst = state.playback_start_instant.unwrap();
            let target_pts_ms =
                playback_target_pts_ms(start_inst, state.playback_start_pts_ms, state.playback_rate);

            let res_frame: std::result::Result<Option<PlaybackFrame>, VideoForgeError> = if has_hw {
                match do_next_playback_frame_pixel_buffer(
                    &mut ictx,
                    &mut decoder,
                    stream_idx,
                    tb,
                    preview_max_edge,
                    &mut hw,
                    target_pts_ms,
                    state.current_pts_ms,
                ) {
                    Ok(Some(f)) => {
                        state.current_pts_ms = f.pts_ms;
                        state.decode_error_streak = 0;
                        Ok(Some(PlaybackFrame::PixelBuffer(f)))
                    }
                    Ok(None) => Ok(None),
                    Err(e) => Err(e),
                }
            } else {
                match do_next_playback_frame_rgba(
                    &mut ictx,
                    &mut decoder,
                    stream_idx,
                    tb,
                    preview_max_edge,
                    &mut color_scaler,
                    &mut color_src_key,
                    target_pts_ms,
                    state.current_pts_ms,
                ) {
                    Ok(Some(f)) => {
                        state.current_pts_ms = f.pts_ms;
                        state.decode_error_streak = 0;
                        Ok(Some(PlaybackFrame::Rgba(f)))
                    }
                    Ok(None) => Ok(None),
                    Err(e) => Err(e),
                }
            };

            match res_frame {
                Ok(Some(frame)) => {
                    let pts = match &frame {
                        PlaybackFrame::Rgba(f) => f.pts_ms,
                        PlaybackFrame::PixelBuffer(f) => f.pts_ms,
                    };

                    let start_inst = state.playback_start_instant.unwrap();
                    let start_pts = state.playback_start_pts_ms;

                    // Align output timing with wall-clock time
                    loop {
                        let elapsed = start_inst.elapsed().as_secs_f64() * 1000.0 * state.playback_rate;
                        let target_pts = start_pts as f64 + elapsed;

                        if pts as f64 <= target_pts {
                            break;
                        }

                        // Sleep in small increments and check for commands to keep loop highly responsive
                        let diff_ms = (pts as f64 - target_pts) / state.playback_rate;
                        let sleep_chunk = diff_ms.min(5.0);
                        if sleep_chunk <= 0.5 {
                            break;
                        }
                        std::thread::sleep(std::time::Duration::from_secs_f64(sleep_chunk / 1000.0));

                        let peek_cmd = cmd_rx.try_recv().ok();
                        if let Some(peek) = peek_cmd {
                            state.pending_cmd = Some(peek);
                            break;
                        }
                    }

                    if state.pending_cmd.is_some() {
                        // Dispose frame resources if command arrived during wait
                        match frame {
                            PlaybackFrame::PixelBuffer(f) => {
                                release_preview_pixel_buffer(f.pixel_buffer_ptr);
                            }
                            PlaybackFrame::Rgba(f) => {
                                crate::pool::release_buffer(f.rgba);
                            }
                        }
                        continue;
                    }

                    // Push the frame to Dart FFI sink (fails if Dart cancelled the stream).
                    if let Some(ref sink) = state.playback_sink {
                        if sink.add(frame).is_err() {
                            log::debug!(
                                "playback sink closed (Dart unsubscribed or isolate gone)"
                            );
                            state.playing = false;
                            state.playback_sink = None;
                        }
                    }
                }
                Ok(None) => {
                    state.playing = false;
                    state.playback_sink = None;
                }
                Err(e) => {
                    // HW decode failure — attempt fallback to software decode
                    if has_hw && !state.using_sw_fallback {
                        log::warn!(
                            "HW decode failed during playback, falling back to software decode: {:?}",
                            e
                        );
                        match fallback_to_sw_decode(
                            input,
                            &mut ictx,
                            &mut decoder,
                            stream_idx,
                            &mut hw,
                            &mut color_scaler,
                            &mut color_src_key,
                            state.current_pts_ms,
                        ) {
                            Ok(new_decoder) => {
                                decoder = new_decoder;
                                state.using_sw_fallback = true;
                                session_use_hw = false;
                                state.reliable_sw_preview = true;
                                state.playback_start_instant =
                                    Some(std::time::Instant::now());
                                state.playback_start_pts_ms = state.current_pts_ms;
                                log::info!(
                                    "Successfully fell back to software decode at {}ms",
                                    state.current_pts_ms
                                );
                                continue;
                            }
                            Err(fallback_err) => {
                                log::error!(
                                    "Software fallback also failed: {:?} (original error: {:?})",
                                    fallback_err,
                                    e
                                );
                            }
                        }
                    } else if state.reliable_sw_preview {
                        state.decode_error_streak += 1;
                        if state.decode_error_streak < 3 {
                            log::warn!(
                                "playback decode failed at {}ms, flush+seek recovery ({}): {:?}",
                                state.current_pts_ms,
                                state.decode_error_streak,
                                e
                            );
                            let _ = recover_sw_decoder_at(
                                &mut ictx,
                                &mut decoder,
                                stream_idx,
                                tb,
                                state.current_pts_ms,
                            );
                            state.playback_start_instant = Some(std::time::Instant::now());
                            state.playback_start_pts_ms = state.current_pts_ms;
                            continue;
                        }
                        log::warn!(
                            "playback decode failed, reopening demuxer at {}ms: {:?}",
                            state.current_pts_ms,
                            e
                        );
                        state.decode_error_streak = 0;
                        if let Ok(new_decoder) = fallback_to_sw_decode(
                            input,
                            &mut ictx,
                            &mut decoder,
                            stream_idx,
                            &mut hw,
                            &mut color_scaler,
                            &mut color_src_key,
                            state.current_pts_ms,
                        ) {
                            decoder = new_decoder;
                            state.playback_start_instant = Some(std::time::Instant::now());
                            state.playback_start_pts_ms = state.current_pts_ms;
                            continue;
                        }
                    }
                    log::error!("Error decoding frame in native loop: {:?}", e);
                    state.playing = false;
                    state.playback_sink = None;
                }
            }
        }
    }
}

/// Re-open input and decoder as software-only after a HW decode failure.
///
/// This flushes the current HW decoder, reopens the input context (to reset
/// demuxer state), creates a fresh software decoder, and seeks to the last
/// known good position so playback can continue without restarting.
fn recover_sw_decoder_at(
    ictx: &mut ffmpeg_next::format::context::Input,
    decoder: &mut ffmpeg_next::codec::decoder::Video,
    stream_idx: usize,
    tb: Rational,
    position_ms: u64,
) -> Result<()> {
    flush_video_decoder(decoder);
    do_seek(ictx, decoder, stream_idx, tb, position_ms)
}

fn fallback_to_sw_decode(
    input: &str,
    ictx: &mut ffmpeg_next::format::context::Input,
    old_decoder: &mut ffmpeg_next::codec::decoder::Video,
    stream_idx: usize,
    hw: &mut Option<crate::ffmpeg::HwFrameTransfer>,
    color_scaler: &mut Option<ScalerContext>,
    color_src_key: &mut Option<(u32, u32, Pixel, u32, u32)>,
    current_pts_ms: u64,
) -> Result<ffmpeg_next::codec::decoder::Video> {
    // 1. Flush and drop the HW decoder
    let _ = old_decoder.send_eof();

    // 2. Drop HW transfer state (releases VT device context)
    hw.take();

    // 3. Re-open the input context (resets demuxer/probe state)
    let lower = input.to_ascii_lowercase();
    let iphone_container = lower.ends_with(".mov") || lower.ends_with(".m4v");
    *ictx = if iphone_container {
        open_input_for_preview(input)?
    } else {
        open_input(input)?
    };
    let stream = ictx
        .streams()
        .best(ffmpeg_next::media::Type::Video)
        .ok_or_else(|| VideoForgeError::InvalidInput("no video stream".into()))?;
    let tb = stream.time_base();
    let params = stream.parameters();
    let reliable_sw = preview_needs_clean_seek(&params, input);

    // 4. Create a software-only decoder
    let mut dec_ctx = CodecContext::from_parameters(params).map_err(map_ffmpeg_error)?;
    if reliable_sw {
        apply_preview_scrub_decoder_settings(&mut dec_ctx);
    } else {
        apply_thumbnail_decoder_settings(&mut dec_ctx);
    }
    let new_decoder = dec_ctx.decoder().video().map_err(map_ffmpeg_error)?;

    // 5. Reset color scaler (pixel format may change after HW→SW switch)
    *color_scaler = None;
    *color_src_key = None;

    // 6. Seek to the last known position to resume playback
    let seek_ts = ms_to_stream_ts(current_pts_ms, tb);
    let _ = seek_stream_backward(ictx, stream_idx, seek_ts);

    Ok(new_decoder)
}

fn do_seek(
    ictx: &mut ffmpeg_next::format::context::Input,
    decoder: &mut ffmpeg_next::codec::decoder::Video,
    stream_idx: usize,
    tb: Rational,
    position_ms: u64,
) -> Result<()> {
    let seek_ts = ms_to_stream_ts(position_ms, tb);
    if seek_stream_backward(ictx, stream_idx, seek_ts).is_err() && position_ms > 0 {
        let _ = seek_stream_backward(ictx, stream_idx, 0);
    }
    flush_video_decoder(decoder);
    Ok(())
}

fn do_next_frame_rgba(
    ictx: &mut ffmpeg_next::format::context::Input,
    decoder: &mut ffmpeg_next::codec::decoder::Video,
    stream_idx: usize,
    tb: Rational,
    max_edge: Option<u32>,
    color_scaler: &mut Option<ScalerContext>,
    color_src_key: &mut Option<(u32, u32, Pixel, u32, u32)>,
) -> Result<Option<PreviewFrameRgba>> {
    let mut frame = VideoFrame::empty();

    // Read packets sequentially
    for (s, packet) in ictx.packets() {
        if s.index() != stream_idx {
            continue;
        }
        decoder.send_packet(&packet).map_err(map_ffmpeg_error)?;

        if decoder.receive_frame(&mut frame).is_ok() {
            let pts_ms = frame_pts_ms(&frame, tb);
            let rgb = video_to_rgb(&frame, max_edge, None, color_scaler, color_src_key)?;
            let rgba = rgb24_to_rgba8888(&rgb.data, rgb.width, rgb.height)?;
            return Ok(Some(PreviewFrameRgba {
                pts_ms,
                width: rgb.width,
                height: rgb.height,
                rgba,
            }));
        }
    }

    // Flush decoder
    let _ = decoder.send_eof();
    if decoder.receive_frame(&mut frame).is_ok() {
        let pts_ms = frame_pts_ms(&frame, tb);
        let rgb = video_to_rgb(&frame, max_edge, None, color_scaler, color_src_key)?;
        let rgba = rgb24_to_rgba8888(&rgb.data, rgb.width, rgb.height)?;
        return Ok(Some(PreviewFrameRgba {
            pts_ms,
            width: rgb.width,
            height: rgb.height,
            rgba,
        }));
    }

    Ok(None)
}

/// Seek near [target_pts_ms] and decode the first frame at/after the catch-up window.
fn seek_and_decode_playback_rgba(
    ictx: &mut ffmpeg_next::format::context::Input,
    decoder: &mut ffmpeg_next::codec::decoder::Video,
    stream_idx: usize,
    tb: Rational,
    target_pts_ms: u64,
    max_edge: Option<u32>,
    color_scaler: &mut Option<ScalerContext>,
    color_src_key: &mut Option<(u32, u32, Pixel, u32, u32)>,
) -> Result<Option<PreviewFrameRgba>> {
    do_seek(ictx, decoder, stream_idx, tb, target_pts_ms)?;
    decoder.skip_frame(Discard::NonKey);
    let min_pts = target_pts_ms.saturating_sub(PLAYBACK_CATCHUP_MARGIN_MS);

    let mut frame = VideoFrame::empty();
    for (s, packet) in ictx.packets() {
        if s.index() != stream_idx {
            continue;
        }
        decoder.send_packet(&packet).map_err(map_ffmpeg_error)?;

        while decoder.receive_frame(&mut frame).is_ok() {
            let frame_pts = frame_pts_ms(&frame, tb);
            if frame_pts < min_pts {
                decoder.skip_frame(Discard::NonKey);
                continue;
            }
            decoder.skip_frame(Discard::None);
            let rgb = video_to_rgb(&frame, max_edge, None, color_scaler, color_src_key)?;
            let rgba = rgb24_to_rgba8888(&rgb.data, rgb.width, rgb.height)?;
            return Ok(Some(PreviewFrameRgba {
                pts_ms: frame_pts,
                width: rgb.width,
                height: rgb.height,
                rgba,
            }));
        }
    }

    decoder.skip_frame(Discard::None);
    let _ = decoder.send_eof();
    if decoder.receive_frame(&mut frame).is_ok() {
        let frame_pts = frame_pts_ms(&frame, tb);
        if frame_pts >= min_pts {
            let rgb = video_to_rgb(&frame, max_edge, None, color_scaler, color_src_key)?;
            let rgba = rgb24_to_rgba8888(&rgb.data, rgb.width, rgb.height)?;
            return Ok(Some(PreviewFrameRgba {
                pts_ms: frame_pts,
                width: rgb.width,
                height: rgb.height,
                rgba,
            }));
        }
    }
    Ok(None)
}

/// Sequential playback with wall-clock catch-up: drop stale frames or seek when far behind.
fn do_next_playback_frame_rgba(
    ictx: &mut ffmpeg_next::format::context::Input,
    decoder: &mut ffmpeg_next::codec::decoder::Video,
    stream_idx: usize,
    tb: Rational,
    max_edge: Option<u32>,
    color_scaler: &mut Option<ScalerContext>,
    color_src_key: &mut Option<(u32, u32, Pixel, u32, u32)>,
    target_pts_ms: u64,
    current_pts_ms: u64,
) -> Result<Option<PreviewFrameRgba>> {
    let min_pts = target_pts_ms.saturating_sub(PLAYBACK_CATCHUP_MARGIN_MS);

    if target_pts_ms.saturating_sub(current_pts_ms) > PLAYBACK_SEEK_CATCHUP_MS {
        return seek_and_decode_playback_rgba(
            ictx,
            decoder,
            stream_idx,
            tb,
            target_pts_ms,
            max_edge,
            color_scaler,
            color_src_key,
        );
    }

    for _ in 0..PLAYBACK_MAX_SKIP_DECODES {
        let Some(frame) = do_next_frame_rgba(
            ictx,
            decoder,
            stream_idx,
            tb,
            max_edge,
            color_scaler,
            color_src_key,
        )?
        else {
            return Ok(None);
        };

        if frame.pts_ms >= min_pts {
            return Ok(Some(frame));
        }

        let skipped_pts = frame.pts_ms;
        release_playback_rgba(frame);

        if target_pts_ms.saturating_sub(skipped_pts) > PLAYBACK_SEEK_CATCHUP_MS {
            return seek_and_decode_playback_rgba(
                ictx,
                decoder,
                stream_idx,
                tb,
                target_pts_ms,
                max_edge,
                color_scaler,
                color_src_key,
            );
        }
    }

    seek_and_decode_playback_rgba(
        ictx,
        decoder,
        stream_idx,
        tb,
        target_pts_ms,
        max_edge,
        color_scaler,
        color_src_key,
    )
}

fn do_next_frame_pixel_buffer(
    ictx: &mut ffmpeg_next::format::context::Input,
    decoder: &mut ffmpeg_next::codec::decoder::Video,
    stream_idx: usize,
    tb: Rational,
    max_edge: Option<u32>,
    hw: &mut Option<crate::ffmpeg::HwFrameTransfer>,
) -> Result<Option<PreviewFramePixelBuffer>> {
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        let mut frame = VideoFrame::empty();
        let hw_transfer = hw.as_mut().ok_or_else(|| {
            VideoForgeError::Internal("VideoToolbox preview decode unavailable".into())
        })?;

        for (s, packet) in ictx.packets() {
            if s.index() != stream_idx {
                continue;
            }
            decoder.send_packet(&packet).map_err(map_ffmpeg_error)?;

            if decoder.receive_frame(&mut frame).is_ok() {
                if !crate::ffmpeg::hw_decode::is_hw_pixel_format(frame.format()) {
                    return Err(VideoForgeError::Internal(
                        "HW preview decode did not produce a VideoToolbox frame".into(),
                    ));
                }
                let pts_ms = frame_pts_ms(&frame, tb);
                let src_w = frame.width();
                let src_h = frame.height();
                let (out_w, out_h) = thumb_dimensions(src_w, src_h, max_edge, None);

                hw_transfer.ensure_transfer_session()?;
                let session = hw_transfer.transfer_session().ok_or_else(|| {
                    VideoForgeError::Internal("VT transfer session missing".into())
                })?;

                unsafe {
                    let pb =
                        crate::ffmpeg::vt_pipeline::transfer_vt_frame_to_bgra_pixel_buffer(
                            session,
                            &frame,
                            out_w as usize,
                            out_h as usize,
                        )?;
                    let ptr = crate::ffmpeg::vt_pipeline::retain_pixel_buffer_for_handoff(pb);
                    return Ok(Some(PreviewFramePixelBuffer {
                        pts_ms,
                        width: out_w,
                        height: out_h,
                        pixel_buffer_ptr: ptr,
                    }));
                }
            }
        }

        // Flush decoder
        let _ = decoder.send_eof();
        if decoder.receive_frame(&mut frame).is_ok() {
            if !crate::ffmpeg::hw_decode::is_hw_pixel_format(frame.format()) {
                return Err(VideoForgeError::Internal(
                    "HW preview decode did not produce a VideoToolbox frame".into(),
                ));
            }
            let pts_ms = frame_pts_ms(&frame, tb);
            let src_w = frame.width();
            let src_h = frame.height();
            let (out_w, out_h) = thumb_dimensions(src_w, src_h, max_edge, None);

            hw_transfer.ensure_transfer_session()?;
            let session = hw_transfer.transfer_session().ok_or_else(|| {
                VideoForgeError::Internal("VT transfer session missing".into())
            })?;

            unsafe {
                let pb =
                    crate::ffmpeg::vt_pipeline::transfer_vt_frame_to_bgra_pixel_buffer(
                        session,
                        &frame,
                        out_w as usize,
                        out_h as usize,
                    )?;
                let ptr = crate::ffmpeg::vt_pipeline::retain_pixel_buffer_for_handoff(pb);
                return Ok(Some(PreviewFramePixelBuffer {
                    pts_ms,
                    width: out_w,
                    height: out_h,
                    pixel_buffer_ptr: ptr,
                }));
            }
        }

        Ok(None)
    }

    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    {
        let _ = (ictx, decoder, stream_idx, tb, max_edge, hw);
        Err(VideoForgeError::Internal(
            "HW preview decode is only available on Apple platforms".into(),
        ))
    }
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
fn vt_frame_to_pixel_buffer(
    frame: &VideoFrame,
    tb: Rational,
    max_edge: Option<u32>,
    hw: &mut crate::ffmpeg::HwFrameTransfer,
) -> Result<PreviewFramePixelBuffer> {
    if !crate::ffmpeg::hw_decode::is_hw_pixel_format(frame.format()) {
        return Err(VideoForgeError::Internal(
            "HW preview decode did not produce a VideoToolbox frame".into(),
        ));
    }
    let pts_ms = frame_pts_ms(frame, tb);
    let src_w = frame.width();
    let src_h = frame.height();
    let (out_w, out_h) = thumb_dimensions(src_w, src_h, max_edge, None);

    hw.ensure_transfer_session()?;
    let session = hw.transfer_session().ok_or_else(|| {
        VideoForgeError::Internal("VT transfer session missing".into())
    })?;

    unsafe {
        let pb = crate::ffmpeg::vt_pipeline::transfer_vt_frame_to_bgra_pixel_buffer(
            session,
            frame,
            out_w as usize,
            out_h as usize,
        )?;
        let ptr = crate::ffmpeg::vt_pipeline::retain_pixel_buffer_for_handoff(pb);
        Ok(PreviewFramePixelBuffer {
            pts_ms,
            width: out_w,
            height: out_h,
            pixel_buffer_ptr: ptr,
        })
    }
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
fn seek_and_decode_playback_pixel_buffer(
    ictx: &mut ffmpeg_next::format::context::Input,
    decoder: &mut ffmpeg_next::codec::decoder::Video,
    stream_idx: usize,
    tb: Rational,
    target_pts_ms: u64,
    max_edge: Option<u32>,
    hw: &mut Option<crate::ffmpeg::HwFrameTransfer>,
) -> Result<Option<PreviewFramePixelBuffer>> {
    let hw_transfer = hw.as_mut().ok_or_else(|| {
        VideoForgeError::Internal("VideoToolbox preview decode unavailable".into())
    })?;

    do_seek(ictx, decoder, stream_idx, tb, target_pts_ms)?;
    decoder.skip_frame(Discard::NonKey);
    let min_pts = target_pts_ms.saturating_sub(PLAYBACK_CATCHUP_MARGIN_MS);

    let mut frame = VideoFrame::empty();
    for (s, packet) in ictx.packets() {
        if s.index() != stream_idx {
            continue;
        }
        decoder.send_packet(&packet).map_err(map_ffmpeg_error)?;

        while decoder.receive_frame(&mut frame).is_ok() {
            let frame_pts = frame_pts_ms(&frame, tb);
            if frame_pts < min_pts {
                decoder.skip_frame(Discard::NonKey);
                continue;
            }
            decoder.skip_frame(Discard::None);
            return Ok(Some(vt_frame_to_pixel_buffer(
                &frame,
                tb,
                max_edge,
                hw_transfer,
            )?));
        }
    }

    decoder.skip_frame(Discard::None);
    Ok(None)
}

fn do_next_playback_frame_pixel_buffer(
    ictx: &mut ffmpeg_next::format::context::Input,
    decoder: &mut ffmpeg_next::codec::decoder::Video,
    stream_idx: usize,
    tb: Rational,
    max_edge: Option<u32>,
    hw: &mut Option<crate::ffmpeg::HwFrameTransfer>,
    target_pts_ms: u64,
    current_pts_ms: u64,
) -> Result<Option<PreviewFramePixelBuffer>> {
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        let min_pts = target_pts_ms.saturating_sub(PLAYBACK_CATCHUP_MARGIN_MS);

        if target_pts_ms.saturating_sub(current_pts_ms) > PLAYBACK_SEEK_CATCHUP_MS {
            return seek_and_decode_playback_pixel_buffer(
                ictx,
                decoder,
                stream_idx,
                tb,
                target_pts_ms,
                max_edge,
                hw,
            );
        }

        for _ in 0..PLAYBACK_MAX_SKIP_DECODES {
            let Some(frame) = do_next_frame_pixel_buffer(
                ictx,
                decoder,
                stream_idx,
                tb,
                max_edge,
                hw,
            )?
            else {
                return Ok(None);
            };

            if frame.pts_ms >= min_pts {
                return Ok(Some(frame));
            }

            let skipped_pts = frame.pts_ms;
            release_playback_pixel_buffer(frame);

            if target_pts_ms.saturating_sub(skipped_pts) > PLAYBACK_SEEK_CATCHUP_MS {
                return seek_and_decode_playback_pixel_buffer(
                    ictx,
                    decoder,
                    stream_idx,
                    tb,
                    target_pts_ms,
                    max_edge,
                    hw,
                );
            }
        }

        return seek_and_decode_playback_pixel_buffer(
            ictx,
            decoder,
            stream_idx,
            tb,
            target_pts_ms,
            max_edge,
            hw,
        );
    }

    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    {
        let _ = (target_pts_ms, current_pts_ms);
        do_next_frame_pixel_buffer(ictx, decoder, stream_idx, tb, max_edge, hw)
    }
}

fn do_seek_and_decode_rgba(
    input: &str,
    ictx: &mut ffmpeg_next::format::context::Input,
    decoder: &mut ffmpeg_next::codec::decoder::Video,
    stream_idx: usize,
    tb: Rational,
    position_ms: u64,
    max_edge: Option<u32>,
    hw: &mut Option<crate::ffmpeg::HwFrameTransfer>,
    color_scaler: &mut Option<ScalerContext>,
    color_src_key: &mut Option<(u32, u32, Pixel, u32, u32)>,
    clean_seek: bool,
    reliable_sw_preview: bool,
) -> Result<PreviewFrameRgba> {
    if clean_seek {
        *decoder = fallback_to_sw_decode(
            input,
            ictx,
            decoder,
            stream_idx,
            hw,
            color_scaler,
            color_src_key,
            position_ms,
        )?;
    } else {
        do_seek(ictx, decoder, stream_idx, tb, position_ms)?;
    }
    decoder.skip_frame(Discard::NonKey);

    let gop_approach = PREVIEW_GOP_APPROACH_MS;

    let mut frame = VideoFrame::empty();
    let mut captured = false;
    let mut pts_ms = position_ms;
    let mut final_rgb = None;

    for (s, packet) in ictx.packets() {
        if s.index() != stream_idx {
            continue;
        }
        decoder.send_packet(&packet).map_err(map_ffmpeg_error)?;

        while decoder.receive_frame(&mut frame).is_ok() {
            let frame_pts = frame_pts_ms(&frame, tb);

            let approach = position_ms.saturating_sub(gop_approach);
            if frame_pts < approach {
                decoder.skip_frame(Discard::NonKey);
            } else {
                decoder.skip_frame(Discard::None);
            }

            if frame_pts >= position_ms {
                pts_ms = frame_pts;
                let rgb = video_to_rgb(&frame, max_edge, None, color_scaler, color_src_key)?;
                final_rgb = Some(rgb);
                captured = true;
                break;
            }
        }
        if captured {
            break;
        }
    }

    decoder.skip_frame(Discard::None);

    if !captured {
        if reliable_sw_preview && !clean_seek {
            *decoder = fallback_to_sw_decode(
                input,
                ictx,
                decoder,
                stream_idx,
                hw,
                color_scaler,
                color_src_key,
                position_ms,
            )?;
            return do_seek_and_decode_rgba(
                input,
                ictx,
                decoder,
                stream_idx,
                tb,
                position_ms,
                max_edge,
                hw,
                color_scaler,
                color_src_key,
                true,
                reliable_sw_preview,
            );
        }
        return Err(VideoForgeError::InvalidInput(format!(
            "could not decode frame at {position_ms}ms"
        )));
    }

    let rgb = final_rgb.unwrap();
    let rgba = rgb24_to_rgba8888(&rgb.data, rgb.width, rgb.height)?;
    Ok(PreviewFrameRgba {
        pts_ms,
        width: rgb.width,
        height: rgb.height,
        rgba,
    })
}

fn do_seek_and_decode_pixel_buffer(
    ictx: &mut ffmpeg_next::format::context::Input,
    decoder: &mut ffmpeg_next::codec::decoder::Video,
    stream_idx: usize,
    tb: Rational,
    position_ms: u64,
    max_edge: Option<u32>,
    hw: &mut Option<crate::ffmpeg::HwFrameTransfer>,
) -> Result<PreviewFramePixelBuffer> {
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        if hw.is_none() {
            return Err(VideoForgeError::Internal(
                "pixel-buffer preview requires VideoToolbox decode (use RGBA path)".into(),
            ));
        }

        do_seek(ictx, decoder, stream_idx, tb, position_ms)?;
        decoder.skip_frame(Discard::NonKey);

        let mut frame = VideoFrame::empty();
        let mut captured = false;
        let mut pts_ms = position_ms;

        let hw_transfer = hw.as_mut().ok_or_else(|| {
            VideoForgeError::Internal("VideoToolbox preview decode unavailable".into())
        })?;

        for (s, packet) in ictx.packets() {
            if s.index() != stream_idx {
                continue;
            }
            decoder.send_packet(&packet).map_err(map_ffmpeg_error)?;

            while decoder.receive_frame(&mut frame).is_ok() {
                let frame_pts = frame_pts_ms(&frame, tb);

                let approach = position_ms.saturating_sub(PREVIEW_GOP_APPROACH_MS);
                if frame_pts < approach {
                    decoder.skip_frame(Discard::NonKey);
                } else {
                    decoder.skip_frame(Discard::None);
                }

                if frame_pts >= position_ms {
                    pts_ms = frame_pts;
                    captured = true;
                    break;
                }
            }
            if captured {
                break;
            }
        }

        decoder.skip_frame(Discard::None);

        if !captured {
            return Err(VideoForgeError::InvalidInput(format!(
                "could not decode HW frame at {position_ms}ms"
            )));
        }

        if !crate::ffmpeg::hw_decode::is_hw_pixel_format(frame.format()) {
            flush_video_decoder(decoder);
            return Err(VideoForgeError::Internal(
                "HW preview decode did not produce a VideoToolbox frame (decoder flushed)"
                    .into(),
            ));
        }

        let src_w = frame.width();
        let src_h = frame.height();
        let (out_w, out_h) = thumb_dimensions(src_w, src_h, max_edge, None);

        hw_transfer.ensure_transfer_session()?;
        let session = hw_transfer.transfer_session().ok_or_else(|| {
            VideoForgeError::Internal("VT transfer session missing".into())
        })?;

        unsafe {
            let pb =
                crate::ffmpeg::vt_pipeline::transfer_vt_frame_to_bgra_pixel_buffer(
                    session,
                    &frame,
                    out_w as usize,
                    out_h as usize,
                )?;
            let ptr = crate::ffmpeg::vt_pipeline::retain_pixel_buffer_for_handoff(pb);
            Ok(PreviewFramePixelBuffer {
                pts_ms,
                width: out_w,
                height: out_h,
                pixel_buffer_ptr: ptr,
            })
        }
    }

    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    {
        let _ = (ictx, decoder, stream_idx, tb, position_ms, max_edge, hw);
        Err(VideoForgeError::Internal(
            "HW preview decode is only available on Apple platforms".into(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rgb24_to_rgba_dimensions() {
        let rgb = vec![255u8, 0, 0, 0, 255, 0];
        let rgba = rgb24_to_rgba8888(&rgb, 2, 1).unwrap();
        assert_eq!(rgba.len(), 8);
        assert_eq!(&rgba[0..4], &[255, 0, 0, 255]);
        assert_eq!(&rgba[4..8], &[0, 255, 0, 255]);
    }

    #[test]
    fn playback_target_pts_advances_with_elapsed_time() {
        let start = std::time::Instant::now();
        let t0 = playback_target_pts_ms(start, 1000, 1.0);
        assert_eq!(t0, 1000);
        std::thread::sleep(std::time::Duration::from_millis(50));
        let t1 = playback_target_pts_ms(start, 1000, 1.0);
        assert!(t1 >= 1040, "expected ~50ms advance, got {t1}");
        let t2 = playback_target_pts_ms(start, 1000, 2.0);
        assert!(t2 >= t1);
    }

    #[test]
    fn playback_catchup_constants_ordering() {
        assert!(PLAYBACK_CATCHUP_MARGIN_MS < PLAYBACK_SEEK_CATCHUP_MS);
        assert!(PLAYBACK_MAX_SKIP_DECODES > 0);
    }
}
