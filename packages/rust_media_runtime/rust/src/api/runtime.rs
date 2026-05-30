use parking_lot::{Condvar, Mutex, RwLock};
use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU32, AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};
use flutter_rust_bridge::frb;

use ffmpeg_next::codec::context::Context as CodecContext;
use ffmpeg_next::util::frame::video::Video as VideoFrameImpl;
use ffmpeg_next::{init as ffmpeg_init, Rational};

use crate::presenter_runtime::{PresenterRuntime, SeekController};
use crate::video_decode::{
    flush_decoder, open_video_pipelines, push_rgba_frame, CATCHUP_SKIP_NON_KEYFRAME_MS,
    HwPipeline, SwPipeline,
};
use crate::vt_hw_decode;

macro_rules! runtime_log {
    ($($arg:tt)*) => {
        eprintln!($($arg)*);
    };
}

static FFMPEG_INIT: std::sync::Once = std::sync::Once::new();

/// Default longest edge for decoded preview frames (matches MediaRuntime).
pub const DEFAULT_PREVIEW_MAX_EDGE: u32 = 720;
/// When audio clock leads latest decoded video PTS by more than this, enter catch-up.
pub const AV_LAG_THRESHOLD_MS: u64 = 500;
/// Cap on decoded RGBA frames waiting for the UI.
pub const VIDEO_FRAME_QUEUE_CAP: usize = 32;

fn hw_decode_enabled() -> bool {
    !matches!(
        std::env::var("VFP_DISABLE_HW_DECODE").as_deref(),
        Ok("1") | Ok("true") | Ok("yes")
    )
}

/// Phase 0 diagnostic: which decoders exist in the **linked** FFmpeg build.
#[derive(Debug, Clone)]
#[frb]
pub struct DecodeCapabilities {
    /// HEVC + VideoToolbox hwaccel available in linked FFmpeg.
    pub hevc_videotoolbox: bool,
    /// H.264 + VideoToolbox hwaccel available in linked FFmpeg.
    pub h264_videotoolbox: bool,
    /// True when `VFP_DISABLE_HW_DECODE` is set.
    pub hw_decode_disabled_env: bool,
    /// libavutil version string (e.g. `59.39.100`).
    pub ffmpeg_version: String,
    /// Human-readable readiness for 4K iPhone HEVC preview.
    pub ready_for_hevc_hw: bool,
    /// Hint when HW decoders are missing from the dylib FFmpeg.
    pub hint: String,
}

fn ffmpeg_version_string() -> String {
    unsafe {
        let ptr = ffmpeg_next::ffi::av_version_info();
        if ptr.is_null() {
            return "unknown".into();
        }
        std::ffi::CStr::from_ptr(ptr)
            .to_string_lossy()
            .into_owned()
    }
}

/// Probe linked FFmpeg (caller must have initialized FFmpeg, or use [`probe_decode_capabilities`]).
fn probe_decode_capabilities_inner() -> DecodeCapabilities {
    let hevc_vt = vt_hw_decode::hevc_videotoolbox_hw_available();
    let h264_vt = vt_hw_decode::h264_videotoolbox_hw_available();
    let hw_decode_disabled_env = !hw_decode_enabled();
    let ffmpeg_version = ffmpeg_version_string();
    let ready_for_hevc_hw = hevc_vt && !hw_decode_disabled_env;
    let hint = if hw_decode_disabled_env {
        "HW decode disabled via VFP_DISABLE_HW_DECODE".into()
    } else if hevc_vt {
        "HEVC VideoToolbox hwaccel available — expect [VideoDecoder] Hardware decode (hevc + VT) on 4K iPhone files".into()
    } else {
        #[cfg(any(target_os = "macos", target_os = "ios"))]
        {
            "HEVC VideoToolbox hwaccel missing. Rebuild FFmpeg with --enable-videotoolbox --enable-hwaccel=hevc_videotoolbox (scripts/build-ffmpeg-macos-vt.sh). Software 4K HEVC will lag audio.".into()
        }
        #[cfg(not(any(target_os = "macos", target_os = "ios")))]
        {
            "VideoToolbox decoders are Apple-only; software decode expected on this OS.".into()
        }
    };
    DecodeCapabilities {
        hevc_videotoolbox: hevc_vt,
        h264_videotoolbox: h264_vt,
        hw_decode_disabled_env,
        ffmpeg_version,
        ready_for_hevc_hw,
        hint,
    }
}

/// Probe linked FFmpeg once (safe to call from Dart at startup).
pub fn probe_decode_capabilities() -> DecodeCapabilities {
    ensure_ffmpeg_initialized();
    probe_decode_capabilities_inner()
}

fn log_decode_capabilities(cap: &DecodeCapabilities) {
    runtime_log!(
        "[Phase0] FFmpeg {} | hevc_videotoolbox={} h264_videotoolbox={} hw_env_disabled={} ready_for_hevc_hw={}",
        cap.ffmpeg_version,
        cap.hevc_videotoolbox,
        cap.h264_videotoolbox,
        cap.hw_decode_disabled_env,
        cap.ready_for_hevc_hw
    );
    runtime_log!("[Phase0] {}", cap.hint);
}

pub fn ensure_ffmpeg_initialized() {
    FFMPEG_INIT.call_once(|| {
        let _ = env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).try_init();
        let _ = ffmpeg_init();
        runtime_log!("[rust_media_runtime] env_logger and FFmpeg initialized");
        let cap = probe_decode_capabilities_inner();
        log_decode_capabilities(&cap);
    });
}

/// State of the playback clock.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlaybackState {
    Idle,
    Playing,
    Paused,
    Seeking,
    Ended,
}

struct PlaybackClockInner {
    state: PlaybackState,
    media_time_ms: u64,
    last_presented_pts_ms: u64,
    rate: f64,
    last_updated_instant: Option<Instant>,
}

/// Thread-safe master clock for media playback.
pub struct PlaybackClock {
    inner: RwLock<PlaybackClockInner>,
}

impl PlaybackClock {
    pub fn new() -> Self {
        runtime_log!("[PlaybackClock] Initializing new master clock");
        Self {
            inner: RwLock::new(PlaybackClockInner {
                state: PlaybackState::Idle,
                media_time_ms: 0,
                last_presented_pts_ms: 0,
                rate: 1.0,
                last_updated_instant: None,
            }),
        }
    }

    pub fn start(&self) {
        let mut inner = self.inner.write();
        inner.state = PlaybackState::Playing;
        inner.last_updated_instant = Some(Instant::now());
        runtime_log!(
            "[PlaybackClock] Playback started rate={} media_time_ms={}",
            inner.rate,
            inner.media_time_ms
        );
    }

    pub fn pause(&self) {
        self.update_time_internal();
        let mut inner = self.inner.write();
        inner.state = PlaybackState::Paused;
        inner.last_updated_instant = None;
        runtime_log!(
            "[PlaybackClock] Playback paused media_time_ms={}",
            inner.media_time_ms
        );
    }

    pub fn seek(&self, time_ms: u64) {
        let mut inner = self.inner.write();
        let was_playing = inner.state == PlaybackState::Playing;
        inner.state = PlaybackState::Seeking;
        inner.media_time_ms = time_ms;
        // Clear stale presented PTS so hard resync does not compare against pre-seek video.
        inner.last_presented_pts_ms = 0;
        inner.last_updated_instant = None;
        runtime_log!("[PlaybackClock] Seek requested to target_ms={} was_playing={}", time_ms, was_playing);
    }

    /// Clears a stale presented PTS after backward seek (presented >> audio).
    pub fn reset_presented_pts_for_seek(&self, to_ms: u64) {
        let mut inner = self.inner.write();
        inner.last_presented_pts_ms = to_ms;
    }

    /// Called when the seek is complete — resumes the appropriate playback state.
    pub fn seek_complete(&self, was_playing: bool) {
        let mut inner = self.inner.write();
        if inner.state == PlaybackState::Seeking {
            if was_playing {
                inner.state = PlaybackState::Playing;
                inner.last_updated_instant = Some(Instant::now());
                runtime_log!("[PlaybackClock] Seek complete — resuming playback media_time_ms={}", inner.media_time_ms);
            } else {
                inner.state = PlaybackState::Paused;
                runtime_log!("[PlaybackClock] Seek complete — staying paused media_time_ms={}", inner.media_time_ms);
            }
        }
    }

    pub fn set_rate(&self, rate: f64) {
        self.update_time_internal();
        let mut inner = self.inner.write();
        inner.rate = rate;
        runtime_log!("[PlaybackClock] Playback rate changed rate={}", rate);
    }

    pub fn get_state(&self) -> PlaybackState {
        self.inner.read().state
    }

    pub fn get_media_time_ms(&self) -> u64 {
        self.update_time_internal();
        self.inner.read().media_time_ms
    }

    pub fn get_last_presented_pts_ms(&self) -> u64 {
        self.inner.read().last_presented_pts_ms
    }

    pub fn advance_presented_pts(&self, pts_ms: u64) {
        let mut inner = self.inner.write();
        if pts_ms > inner.last_presented_pts_ms {
            inner.last_presented_pts_ms = pts_ms;
        }
    }

    /// Keep the wall clock aligned with the audio sample clock during playback.
    pub fn sync_from_audio_ms(&self, audio_ms: u64) {
        if audio_ms == 0 {
            return;
        }
        let mut inner = self.inner.write();
        if inner.state == PlaybackState::Playing {
            inner.media_time_ms = audio_ms;
            inner.last_updated_instant = Some(Instant::now());
        }
    }

    fn update_time_internal(&self) {
        let mut inner = self.inner.write();
        if inner.state == PlaybackState::Playing {
            if let Some(last) = inner.last_updated_instant {
                let elapsed = last.elapsed().as_secs_f64() * 1000.0 * inner.rate;
                inner.media_time_ms = inner.media_time_ms.saturating_add(elapsed as u64);
                inner.last_updated_instant = Some(Instant::now());
            }
        }
    }
}

/// A simplified demuxed media packet.
#[derive(Debug, Clone)]
pub struct MediaPacket {
    pub pts_ms: u64,
    pub dts_ms: u64,
    pub stream_index: usize,
    pub is_keyframe: bool,
    pub data: Vec<u8>,
}

/// Queue packet item that supports both simulated and real FFmpeg packets.
pub enum QueuePacket {
    Real(ffmpeg_next::Packet, u64), // Packet, pts_ms
    Simulated(MediaPacket),
    /// Flush sentinel: tells decoder threads to drain and reset their codec context.
    Flush,
}

struct PacketQueueInner {
    queue: VecDeque<QueuePacket>,
    is_closed: bool,
}

/// Thread-safe bounded packet queue with condition variable synchronization.
pub struct PacketQueue {
    inner: Mutex<PacketQueueInner>,
    cond_not_empty: Condvar,
    cond_not_full: Condvar,
    max_size: usize,
}

impl PacketQueue {
    pub fn new(max_size: usize) -> Self {
        runtime_log!("[PacketQueue] Creating queue with max_size={}", max_size);
        Self {
            inner: Mutex::new(PacketQueueInner {
                queue: VecDeque::new(),
                is_closed: false,
            }),
            cond_not_empty: Condvar::new(),
            cond_not_full: Condvar::new(),
            max_size,
        }
    }

    pub fn push(&self, packet: QueuePacket) -> bool {
        let mut inner = self.inner.lock();
        if inner.queue.len() >= self.max_size && !inner.is_closed {
            runtime_log!("[PacketQueue] Queue is full (len={}/{}), waiting to push...", inner.queue.len(), self.max_size);
        }
        while inner.queue.len() >= self.max_size && !inner.is_closed {
            self.cond_not_full.wait(&mut inner);
        }
        if inner.is_closed {
            runtime_log!("[PacketQueue] Push failed: Queue is closed");
            return false;
        }
        inner.queue.push_back(packet);
        self.cond_not_empty.notify_one();
        true
    }

    pub fn pop(&self) -> Option<QueuePacket> {
        let mut inner = self.inner.lock();
        if inner.queue.is_empty() && !inner.is_closed {
            runtime_log!("[PacketQueue] Queue is empty, waiting to pop...");
        }
        while inner.queue.is_empty() && !inner.is_closed {
            self.cond_not_empty.wait(&mut inner);
        }
        if inner.queue.is_empty() && inner.is_closed {
            runtime_log!("[PacketQueue] Pop returned None (Queue closed)");
            return None;
        }
        let packet = inner.queue.pop_front();
        self.cond_not_full.notify_one();
        packet
    }

    pub fn flush(&self) {
        let mut inner = self.inner.lock();
        let cleared = inner.queue.len();
        inner.is_closed = false;
        inner.queue.clear();
        self.cond_not_full.notify_all();
        runtime_log!("[PacketQueue] Queue flushed, cleared {} packets", cleared);
    }

    pub fn close(&self) {
        let mut inner = self.inner.lock();
        let cleared = inner.queue.len();
        inner.is_closed = true;
        inner.queue.clear();
        self.cond_not_empty.notify_all();
        self.cond_not_full.notify_all();
        runtime_log!("[PacketQueue] Queue closed, cleared {} packets", cleared);
    }

    pub fn len(&self) -> usize {
        self.inner.lock().queue.len()
    }

    pub fn is_empty(&self) -> bool {
        self.inner.lock().queue.is_empty()
    }
}

#[frb(ignore)]
pub trait HasPts {
    fn pts_ms(&self) -> u64;
}

#[frb(ignore)]
impl HasPts for MediaVideoFrame {
    fn pts_ms(&self) -> u64 {
        self.pts_ms
    }
}

#[frb(ignore)]
impl HasPts for AudioFrame {
    fn pts_ms(&self) -> u64 {
        self.pts_ms
    }
}

/// Bounded thread-safe frame queue with drop-oldest behavior on overflow.
pub struct FrameQueue<T> {
    queue: Mutex<VecDeque<T>>,
    max_size: usize,
}

impl<T> FrameQueue<T> {
    pub fn new(max_size: usize) -> Self {
        runtime_log!("[FrameQueue] Creating frame queue with max_size={}", max_size);
        Self {
            queue: Mutex::new(VecDeque::new()),
            max_size,
        }
    }

    pub fn dequeue(&self) -> Option<T> {
        self.queue.lock().pop_front()
    }

    pub fn flush(&self) {
        self.queue.lock().clear();
    }

    pub fn len(&self) -> usize {
        self.queue.lock().len()
    }

    pub fn is_empty(&self) -> bool {
        self.queue.lock().is_empty()
    }

    pub fn max_size(&self) -> usize {
        self.max_size
    }
}

impl<T: HasPts> FrameQueue<T> {
    /// Enqueue a frame. Drops the oldest frame if the queue is full and returns it.
    /// Inserts in sorted PTS order.
    pub fn enqueue(&self, frame: T) -> Option<T> {
        let mut queue = self.queue.lock();
        let mut dropped = None;
        if queue.len() >= self.max_size {
            dropped = queue.pop_front();
        }
        let pos = queue.binary_search_by_key(&frame.pts_ms(), |f| f.pts_ms())
            .unwrap_or_else(|e| e);
        queue.insert(pos, frame);
        dropped
    }
}

impl FrameQueue<MediaVideoFrame> {
    /// Like [`FrameQueue::enqueue`] but logs when the queue drops a frame.
    pub fn enqueue_video(&self, frame: MediaVideoFrame) -> Option<MediaVideoFrame> {
        let dropped = self.enqueue(frame);
        if let Some(ref old) = dropped {
            release_media_video_frame_pixel_buffer(old);
            runtime_log!(
                "[VideoDecoder] Dropped oldest frame (PTS: {}ms) — queue full ({}/{})",
                old.pts_ms,
                self.len(),
                self.max_size()
            );
        }
        dropped
    }

    pub fn flush_video(&self) {
        let mut q = self.queue.lock();
        for f in q.drain(..) {
            release_media_video_frame_pixel_buffer(&f);
        }
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn release_media_video_frame_pixel_buffer(frame: &MediaVideoFrame) {
    if frame.pixel_buffer_ptr != 0 {
        unsafe {
            crate::vt_pixel_buffer::release_pixel_buffer(
                frame.pixel_buffer_ptr as *mut std::ffi::c_void,
            );
        }
    }
}

#[cfg(not(any(target_os = "macos", target_os = "ios")))]
fn release_media_video_frame_pixel_buffer(_frame: &MediaVideoFrame) {}

impl FrameQueue<MediaVideoFrame> {
    pub fn dequeue_best_for_time(&self, current_time: u64) -> Option<MediaVideoFrame> {
        let mut queue = self.queue.lock();
        let mut best_frame = None;
        let mut skipped_count = 0;
        while let Some(front) = queue.front() {
            if front.pts_ms <= current_time {
                best_frame = queue.pop_front();
                if best_frame.is_some() {
                    skipped_count += 1;
                }
            } else {
                break;
            }
        }
        if skipped_count > 2 {
            runtime_log!(
                "[MediaPlaybackEngine] Skipped {} video frames to catch up with current_time: {}ms",
                skipped_count - 1,
                current_time
            );
        }
        if best_frame.is_none() && current_time == 0 {
            if let Some(front) = queue.front() {
                if front.pts_ms == 0 {
                    best_frame = queue.pop_front();
                }
            }
        }
        best_frame
    }

    /// Returns the PTS of the newest frame in the queue (back of the sorted deque).
    /// Returns 0 if the queue is empty. Used for A/V lag diagnostics.
    pub fn latest_pts(&self) -> u64 {
        self.queue.lock().back().map(|f| f.pts_ms).unwrap_or(0)
    }
}

/// Decoded video frame for presentation.
///
/// **RGBA path:** [pixels] is `width × height × 4`, [pixel_buffer_ptr] is 0.
/// **Apple HW path:** [pixel_buffer_ptr] is a retained BGRA `CVPixelBuffer*`; [pixels] is empty.
#[derive(Debug)]
#[frb(non_opaque)]
pub struct MediaVideoFrame {
    pub pts_ms: u64,
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
    pub pixel_buffer_ptr: u64,
}

/// Hand off `CVPixelBuffer` to Flutter without releasing on [MediaVideoFrame] drop.
#[frb(non_opaque)]
pub struct PixelBufferHandoff {
    pub pts_ms: u64,
    pub width: u32,
    pub height: u32,
    pub pixel_buffer_ptr: u64,
}

pub fn media_video_frame_into_pixel_buffer_handoff(
    mut frame: MediaVideoFrame,
) -> Option<PixelBufferHandoff> {
    if frame.pixel_buffer_ptr == 0 {
        return None;
    }
    let handoff = PixelBufferHandoff {
        pts_ms: frame.pts_ms,
        width: frame.width,
        height: frame.height,
        pixel_buffer_ptr: frame.pixel_buffer_ptr,
    };
    frame.pixel_buffer_ptr = 0;
    Some(handoff)
}

/// Decoded audio frame (stereo PCM f32 samples).
#[derive(Debug, Clone)]
pub struct AudioFrame {
    pub pts_ms: u64,
    pub sample_rate: u32,
    pub channels: u32,
    pub samples: Vec<f32>,
}

#[allow(dead_code)]
#[frb(ignore)]
struct SendSafeStream(pub cpal::Stream);
unsafe impl Send for SendSafeStream {}
unsafe impl Sync for SendSafeStream {}

/// Decodes audio packets from a PacketQueue into an Audio FrameQueue.
struct AudioPlayerState {
    frame_queue: Arc<FrameQueue<AudioFrame>>,
    clock: Arc<PlaybackClock>,
    current_frame: Option<AudioFrame>,
    current_sample_idx: usize,
    waveform: Arc<Mutex<Vec<f32>>>,
    /// Sample-accurate audio master clock (ms). Updated once per cpal buffer callback.
    audio_clock_ms: Arc<AtomicU64>,
    /// Local copies for clock math (avoid locking each callback)
    sr: u64,
    ch: u64,
}

#[frb]
pub struct AudioRuntime {
    packet_queue: Arc<PacketQueue>,
    frame_queue: Arc<FrameQueue<AudioFrame>>,
    _clock: Arc<PlaybackClock>,
    is_running: Arc<AtomicBool>,
    thread_handle: Mutex<Option<thread::JoinHandle<()>>>,
    audio_params: Arc<Mutex<Option<(ffmpeg_next::codec::Parameters, Rational)>>>,
    #[frb(ignore)]
    cpal_stream: Mutex<Option<SendSafeStream>>,
    waveform: Arc<Mutex<Vec<f32>>>,
    /// Sample-accurate audio playback position in ms — preferred as the master clock.
    /// Updated by the cpal callback; zero until audio starts playing.
    #[frb(ignore)]
    pub audio_clock_ms: Arc<AtomicU64>,
}

impl AudioRuntime {
    pub fn new(
        packet_queue: Arc<PacketQueue>,
        frame_queue: Arc<FrameQueue<AudioFrame>>,
        clock: Arc<PlaybackClock>,
    ) -> Self {
        Self {
            packet_queue,
            frame_queue,
            _clock: clock,
            is_running: Arc::new(AtomicBool::new(false)),
            thread_handle: Mutex::new(None),
            audio_params: Arc::new(Mutex::new(None)),
            cpal_stream: Mutex::new(None),
            waveform: Arc::new(Mutex::new(vec![0.0; 20])),
            audio_clock_ms: Arc::new(AtomicU64::new(0)),
        }
    }

    pub fn start(&self) {
        if self.is_running.swap(true, Ordering::SeqCst) {
            runtime_log!("[AudioRuntime] Already running");
            return;
        }

        runtime_log!("[AudioRuntime] Starting decoding loop");
        
        // Initialize cpal audio stream
        use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
        let host = cpal::default_host();
        let mut sample_rate = 48000;
        let mut channels = 2;
        let mut cpal_stream_opt = None;

        if let Some(device) = host.default_output_device() {
            if let Ok(config) = device.default_output_config() {
                sample_rate = config.sample_rate().0;
                channels = config.channels() as usize;

                let audio_clock_ms_arc = self.audio_clock_ms.clone();
                let player_state = Arc::new(Mutex::new(AudioPlayerState {
                    frame_queue: self.frame_queue.clone(),
                    clock: self._clock.clone(),
                    current_frame: None,
                    current_sample_idx: 0,
                    waveform: self.waveform.clone(),
                    audio_clock_ms: audio_clock_ms_arc,
                    sr: sample_rate as u64,
                    ch: channels as u64,
                }));

                let player_state_cb = player_state.clone();
                let stream_res = device.build_output_stream(
                    &config.into(),
                    move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                        let mut state = player_state_cb.lock();
                        let is_playing = state.clock.get_state() == PlaybackState::Playing;
                        let is_seeking = state.clock.get_state() == PlaybackState::Seeking;

                        // Update sample-accurate audio master clock once per buffer.
                        // Formula: frame_pts + samples_consumed_in_frame / (sample_rate * channels)
                        if is_playing {
                            if let Some(ref frame) = state.current_frame {
                                let sr = state.sr.max(1);
                                let ch = state.ch.max(1);
                                let offset_ms = (state.current_sample_idx as u64 * 1000) / (sr * ch);
                                let audio_ms =
                                    frame.pts_ms.saturating_add(offset_ms);
                                state.audio_clock_ms.store(audio_ms, Ordering::Relaxed);
                                state.clock.sync_from_audio_ms(audio_ms);
                            }
                        }

                        if is_seeking {
                            state.current_frame = None;
                            state.current_sample_idx = 0;
                            for sample in data.iter_mut() {
                                *sample = 0.0;
                            }
                            return;
                        }

                        if !is_playing {
                            for sample in data.iter_mut() {
                                *sample = 0.0;
                            }
                            return;
                        }

                        let mut max_amplitude = 0.0f32;
                        let mut sample_count = 0;

                        for sample in data.iter_mut() {
                            if let Some(frame) = &state.current_frame {
                                if state.current_sample_idx < frame.samples.len() {
                                    let val = frame.samples[state.current_sample_idx];
                                    *sample = val;
                                    let abs_val = val.abs();
                                    if abs_val > max_amplitude {
                                        max_amplitude = abs_val;
                                    }
                                    state.current_sample_idx += 1;
                                    sample_count += 1;
                                    continue;
                                }
                            }

                            // Try to dequeue next frame
                            state.current_frame = state.frame_queue.dequeue();
                            state.current_sample_idx = 0;

                            if let Some(frame) = &state.current_frame {
                                if state.current_sample_idx < frame.samples.len() {
                                    let val = frame.samples[state.current_sample_idx];
                                    *sample = val;
                                    let abs_val = val.abs();
                                    if abs_val > max_amplitude {
                                        max_amplitude = abs_val;
                                    }
                                    state.current_sample_idx += 1;
                                    sample_count += 1;
                                } else {
                                    *sample = 0.0;
                                }
                            } else {
                                *sample = 0.0;
                            }
                        }

                        if sample_count > 0 {
                            let mut wf = state.waveform.lock();
                            wf.remove(0);
                            wf.push(max_amplitude * 40.0 + 5.0);
                        }
                    },
                    move |err| {
                        runtime_log!("[AudioStream] Playback error: {:?}", err);
                    },
                    None
                );

                match stream_res {
                    Ok(stream) => {
                        if let Err(e) = stream.play() {
                            runtime_log!("[AudioRuntime] Failed to start cpal stream: {:?}", e);
                        } else {
                            runtime_log!("[AudioRuntime] cpal audio stream started successfully: rate={} channels={}", sample_rate, channels);
                            cpal_stream_opt = Some(SendSafeStream(stream));
                        }
                    }
                    Err(e) => {
                        runtime_log!("[AudioRuntime] Failed to build cpal output stream: {:?}", e);
                    }
                }
            }
        }
        *self.cpal_stream.lock() = cpal_stream_opt;

        let packet_queue = self.packet_queue.clone();
        let frame_queue = self.frame_queue.clone();
        let is_running = self.is_running.clone();
        let audio_params = self.audio_params.clone();

        let handle = thread::spawn(move || {
            runtime_log!("[AudioDecoder] Started audio decoder thread");
            let mut decoder_state = None;
            let mut frame_count = 0;
            let mut resampler = None;

            if let Some((params, tb)) = &*audio_params.lock() {
                if let Ok(dec_ctx) = CodecContext::from_parameters(params.clone()) {
                    match dec_ctx.decoder().audio() {
                        Ok(dec) => {
                            runtime_log!("[AudioDecoder] FFmpeg audio decoder initialized");

                            let in_format = dec.format();
                            let in_layout = dec.channel_layout();
                            let in_rate = dec.rate();
                            let out_layout = if channels == 1 {
                                ffmpeg_next::ChannelLayout::MONO
                            } else {
                                ffmpeg_next::ChannelLayout::STEREO
                            };

                            match ffmpeg_next::software::resampling::Context::get(
                                in_format,
                                in_layout,
                                in_rate,
                                ffmpeg_next::util::format::sample::Sample::F32(ffmpeg_next::format::sample::Type::Packed),
                                out_layout,
                                sample_rate as u32,
                            ) {
                                Ok(r) => {
                                    runtime_log!("[AudioDecoder] FFmpeg audio resampler initialized: {:?} {:?} {} -> F32 packed {} channels {}Hz", in_format, in_layout, in_rate, channels, sample_rate);
                                    resampler = Some(r);
                                }
                                Err(e) => {
                                    runtime_log!("[AudioDecoder] Failed to initialize audio resampler: {:?}", e);
                                }
                            }

                            decoder_state = Some((dec, *tb));
                        }
                        Err(e) => {
                            runtime_log!("[AudioDecoder] Failed to initialize audio decoder: {:?}", e);
                        }
                    }
                }
            }

            let mut last_queue_full_log = Instant::now() - Duration::from_secs(5);
            while is_running.load(Ordering::SeqCst) {
                if frame_queue.len() >= frame_queue.max_size {
                    if last_queue_full_log.elapsed() >= Duration::from_secs(5) {
                        runtime_log!("[AudioDecoder] Frame queue is full ({}/{}), throttling decoder...", frame_queue.len(), frame_queue.max_size);
                        last_queue_full_log = Instant::now();
                    }
                    thread::sleep(Duration::from_millis(10));
                    continue;
                }
                if let Some(queue_packet) = packet_queue.pop() {
                    match queue_packet {
                        QueuePacket::Real(pkt, pts_ms) => {
                            if let Some((ref mut decoder, tb)) = decoder_state {
                                match decoder.send_packet(&pkt) {
                                    Ok(_) => {
                                        let mut decoded = ffmpeg_next::util::frame::audio::Audio::empty();
                                        while decoder.receive_frame(&mut decoded).is_ok() {
                                            frame_count += 1;
                                            
                                            let frame_pts_ms = decoded.pts().map(|pts| {
                                                (pts as f64 * tb.0 as f64 / tb.1 as f64 * 1000.0) as u64
                                            }).unwrap_or(pts_ms);

                                            if frame_count % 500 == 0 {
                                                runtime_log!("[AudioDecoder] Decoded {} audio frames, current PTS: {}ms", frame_count, frame_pts_ms);
                                            }

                                            let mut samples = Vec::new();
                                            if let Some(ref mut r) = resampler {
                                                let mut resampled = ffmpeg_next::util::frame::audio::Audio::empty();
                                                if let Ok(_) = r.run(&decoded, &mut resampled) {
                                                    let nb = resampled.samples();
                                                    let data = resampled.data(0);
                                                    let need = nb * channels * std::mem::size_of::<f32>();
                                                    if data.len() >= need {
                                                        let slice = unsafe {
                                                            std::slice::from_raw_parts(data.as_ptr() as *const f32, nb * channels)
                                                        };
                                                        samples.extend_from_slice(slice);
                                                    }
                                                }
                                            }

                                            // Package stereo f32 samples
                                            let audio_frame = AudioFrame {
                                                pts_ms: frame_pts_ms,
                                                sample_rate: sample_rate as u32,
                                                channels: channels as u32,
                                                samples,
                                            };
                                            if let Some(dropped) = frame_queue.enqueue(audio_frame) {
                                                if frame_count % 100 == 0 {
                                                    runtime_log!("[AudioDecoder] Dropped oldest audio frame (PTS: {}ms) from full queue", dropped.pts_ms);
                                                }
                                            }
                                        }
                                    }
                                    Err(e) => {
                                        runtime_log!("[AudioDecoder] send_packet error: {:?}", e);
                                    }
                                }
                            }
                        }
                        QueuePacket::Simulated(packet) => {
                            frame_count += 1;
                            if frame_count % 500 == 0 {
                                runtime_log!("[AudioDecoder] Generated {} simulated audio frames, PTS: {}ms", frame_count, packet.pts_ms);
                            }
                            let audio_frame = AudioFrame {
                                pts_ms: packet.pts_ms,
                                sample_rate: sample_rate as u32,
                                channels: channels as u32,
                                samples: vec![0.0; 1024],
                            };
                            let _ = frame_queue.enqueue(audio_frame);
                        }
                        QueuePacket::Flush => {
                            runtime_log!("[AudioDecoder] Received Flush sentinel — flushing audio decoder state");
                            if let Some((ref mut decoder, _)) = decoder_state {
                                // Drain remaining frames
                                let _ = decoder.send_eof();
                                let mut tmp = ffmpeg_next::util::frame::audio::Audio::empty();
                                while decoder.receive_frame(&mut tmp).is_ok() {}
                                // Flush internal codec buffers (resets AAC/opus state)
                                unsafe {
                                    ffmpeg_next::ffi::avcodec_flush_buffers(decoder.as_mut_ptr());
                                }
                                runtime_log!("[AudioDecoder] Codec flush complete — ready for post-seek audio");
                            }
                            frame_queue.flush();
                        }
                    }
                } else {
                    thread::sleep(Duration::from_millis(5));
                }
            }
            runtime_log!("[AudioDecoder] Audio decoder thread exited. Total frames: {}", frame_count);
        });

        *self.thread_handle.lock() = Some(handle);
    }

    pub fn stop(&self) {
        if !self.is_running.swap(false, Ordering::SeqCst) {
            return;
        }
        runtime_log!("[AudioRuntime] Stopping decoding loop and cpal stream");
        *self.cpal_stream.lock() = None;
        self.packet_queue.close();
        if let Some(handle) = self.thread_handle.lock().take() {
            let _ = handle.join();
        }
    }
}


/// Decodes video packets from a PacketQueue into a Video FrameQueue.

pub struct VideoRuntime {
    packet_queue: Arc<PacketQueue>,
    frame_queue: Arc<FrameQueue<MediaVideoFrame>>,
    _clock: Arc<PlaybackClock>,
    /// Set by [`MediaPlaybackEngine`] so the decoder can measure A/V lag.
    audio_clock_ms: Mutex<Option<Arc<AtomicU64>>>,
    preview_max_edge: Arc<AtomicU32>,
    is_running: Arc<AtomicBool>,
    thread_handle: Mutex<Option<thread::JoinHandle<()>>>,
    video_params: Arc<Mutex<Option<(ffmpeg_next::codec::Parameters, Rational)>>>,
}

impl VideoRuntime {
    pub fn new(
        packet_queue: Arc<PacketQueue>,
        frame_queue: Arc<FrameQueue<MediaVideoFrame>>,
        clock: Arc<PlaybackClock>,
        preview_max_edge: u32,
    ) -> Self {
        Self {
            packet_queue,
            frame_queue,
            _clock: clock,
            audio_clock_ms: Mutex::new(None),
            preview_max_edge: Arc::new(AtomicU32::new(preview_max_edge.max(1))),
            is_running: Arc::new(AtomicBool::new(false)),
            thread_handle: Mutex::new(None),
            video_params: Arc::new(Mutex::new(None)),
        }
    }

    #[frb(ignore)]
    pub fn set_audio_clock(&self, audio_clock_ms: Arc<AtomicU64>) {
        *self.audio_clock_ms.lock() = Some(audio_clock_ms);
    }

    pub fn start(&self) {
        if self.is_running.swap(true, Ordering::SeqCst) {
            runtime_log!("[VideoRuntime] Already running");
            return;
        }

        runtime_log!("[VideoRuntime] Starting decoding loop");
        let packet_queue = self.packet_queue.clone();
        let frame_queue = self.frame_queue.clone();
        let is_running = self.is_running.clone();
        let video_params = self.video_params.clone();
        let audio_clock_ms = self
            .audio_clock_ms
            .lock()
            .clone()
            .unwrap_or_else(|| Arc::new(AtomicU64::new(0)));
        let preview_max_edge = self.preview_max_edge.clone();

        let handle = thread::spawn(move || {
            runtime_log!("[VideoDecoder] Started video decoder thread");
            let mut frame_count = 0u64;

            let mut hw_state: Option<HwPipeline> = None;
            let mut sw_state: Option<SwPipeline> = None;
            let mut hw_sw_frame = VideoFrameImpl::empty();
            let mut require_keyframe = false;

            let reopen_decoders = |hw: &mut Option<HwPipeline>, sw: &mut Option<SwPipeline>| {
                *hw = None;
                *sw = None;
                if let Some((params, tb)) = video_params.lock().clone() {
                    let max_edge = preview_max_edge.load(Ordering::Relaxed);
                    let (h, s) = open_video_pipelines(&params, tb, max_edge, hw_decode_enabled());
                    *hw = h;
                    *sw = s;
                }
            };

            reopen_decoders(&mut hw_state, &mut sw_state);

            let mut last_queue_full_log = Instant::now() - Duration::from_secs(5);
            let mut last_lag_log = Instant::now() - Duration::from_secs(5);
            let mut last_catchup_log = Instant::now() - Duration::from_secs(5);

            fn video_decode_lag_ms(
                audio_clock_ms: &AtomicU64,
                frame_queue: &FrameQueue<MediaVideoFrame>,
            ) -> u64 {
                let audio_ms = audio_clock_ms.load(Ordering::Relaxed);
                let latest = frame_queue.latest_pts();
                audio_ms.saturating_sub(latest)
            }

            fn pop_packet_for_decode(
                packet_queue: &PacketQueue,
                lag_ms: u64,
                require_keyframe: &mut bool,
            ) -> Option<QueuePacket> {
                loop {
                    let pkt = packet_queue.pop()?;
                    match pkt {
                        QueuePacket::Flush | QueuePacket::Simulated(_) => return Some(pkt),
                        QueuePacket::Real(p, pts_ms) => {
                            if crate::video_decode::packet_dropped_in_catchup(
                                p.is_key(),
                                lag_ms,
                                *require_keyframe,
                            ) {
                                continue;
                            }
                            *require_keyframe = false;
                            return Some(QueuePacket::Real(p, pts_ms));
                        }
                    }
                }
            }

            while is_running.load(Ordering::SeqCst) {
                let lag_ms = video_decode_lag_ms(&audio_clock_ms, &frame_queue);
                let decode_behind = lag_ms > CATCHUP_SKIP_NON_KEYFRAME_MS;

                if decode_behind && last_catchup_log.elapsed() >= Duration::from_secs(2) {
                    let mode = crate::video_decode::catchup_mode_label(lag_ms);
                    runtime_log!(
                        "[CatchUp] mode={} lag={}ms latest_decoded={}ms VQ={} pkt={}",
                        mode,
                        lag_ms,
                        frame_queue.latest_pts(),
                        frame_queue.len(),
                        packet_queue.len()
                    );
                    last_catchup_log = Instant::now();
                }

                if frame_queue.len() >= frame_queue.max_size() && !decode_behind {
                    if last_queue_full_log.elapsed() >= Duration::from_secs(5) {
                        runtime_log!(
                            "[VideoDecoder] Frame queue full ({}/{}), throttling",
                            frame_queue.len(),
                            frame_queue.max_size()
                        );
                        last_queue_full_log = Instant::now();
                    }
                    thread::sleep(Duration::from_millis(10));
                    continue;
                }

                if let Some(queue_packet) =
                    pop_packet_for_decode(&packet_queue, lag_ms, &mut require_keyframe)
                {
                    match queue_packet {
                        QueuePacket::Real(pkt, pts_ms) => {
                            if let Some(ref mut hw) = hw_state {
                                if hw.dec.send_packet(&pkt).is_ok() {
                                    let mut decoded = VideoFrameImpl::empty();
                                    while hw.dec.receive_frame(&mut decoded).is_ok() {
                                        frame_count += 1;
                                        if frame_count % 150 == 0 {
                                            runtime_log!(
                                                "[VideoDecoder] Decoded {} frames (HW path)",
                                                frame_count
                                            );
                                        }
                                        let mut pushed = false;
                                        if let Some(ref vt) = hw.vt {
                                            pushed = crate::video_decode::push_vt_pixel_frame(
                                                &decoded,
                                                pts_ms,
                                                vt,
                                                hw.tb,
                                                hw.out_w,
                                                hw.out_h,
                                                &frame_queue,
                                            );
                                        }
                                        if !pushed {
                                            if vt_hw_decode::is_hw_pixel_format(decoded.format()) {
                                                if hw.xfer.transfer_to_sw(&decoded, &mut hw_sw_frame)
                                                {
                                                    push_rgba_frame(
                                                        &hw_sw_frame,
                                                        pts_ms,
                                                        &mut hw.rgba_scaler,
                                                        hw.out_w,
                                                        hw.out_h,
                                                        hw.tb,
                                                        &frame_queue,
                                                    );
                                                }
                                            } else {
                                                push_rgba_frame(
                                                    &decoded,
                                                    pts_ms,
                                                    &mut hw.rgba_scaler,
                                                    hw.out_w,
                                                    hw.out_h,
                                                    hw.tb,
                                                    &frame_queue,
                                                );
                                            }
                                        }
                                    }
                                }
                            } else if let Some((ref mut sw_dec, ref mut scaler, tb, out_w, out_h)) =
                                sw_state
                            {
                                match sw_dec.send_packet(&pkt) {
                                    Ok(_) => {
                                        let mut decoded = VideoFrameImpl::empty();
                                        while sw_dec.receive_frame(&mut decoded).is_ok() {
                                            frame_count += 1;
                                            if frame_count % 150 == 0 {
                                                runtime_log!(
                                                    "[VideoDecoder] Decoded {} frames (SW path)",
                                                    frame_count
                                                );
                                            }
                                            push_rgba_frame(
                                                &decoded,
                                                pts_ms,
                                                scaler,
                                                out_w,
                                                out_h,
                                                tb,
                                                &frame_queue,
                                            );
                                        }
                                    }
                                    Err(e) => {
                                        runtime_log!("[VideoDecoder] SW send_packet error: {:?}", e);
                                    }
                                }
                            }

                            // Periodic A/V lag log: shows how far behind video decode is
                            if last_lag_log.elapsed() >= Duration::from_secs(5) {
                                let latest_video_pts = frame_queue.latest_pts();
                                let audio_ms = audio_clock_ms.load(Ordering::Relaxed);
                                runtime_log!(
                                    "[VideoDecoder] A/V lag check: audio_clock={}ms latest_decoded_pts={}ms lag={}ms VQ={}",
                                    audio_ms,
                                    latest_video_pts,
                                    audio_ms.saturating_sub(latest_video_pts),
                                    frame_queue.len()
                                );
                                last_lag_log = Instant::now();
                            }
                        }
                        QueuePacket::Simulated(packet) => {
                            frame_count += 1;
                            let video_frame = MediaVideoFrame {
                                pts_ms: packet.pts_ms,
                                width: 1280,
                                height: 720,
                                pixels: vec![255; 1280 * 720 * 4],
                                pixel_buffer_ptr: 0,
                            };
                            let _ = frame_queue.enqueue(video_frame);
                        }
                        QueuePacket::Flush => {
                            runtime_log!(
                                "[VideoDecoder] Flush — reopening decoders and scalers for post-seek"
                            );
                            if let Some(ref mut hw) = hw_state {
                                flush_decoder(&mut hw.dec);
                            }
                            if let Some((ref mut sw_dec, ..)) = sw_state {
                                flush_decoder(sw_dec);
                            }
                            frame_queue.flush_video();
                            require_keyframe = true;
                            reopen_decoders(&mut hw_state, &mut sw_state);
                            runtime_log!(
                                "[VideoDecoder] Post-seek pipelines ready hw={} sw={}",
                                hw_state.is_some(),
                                sw_state.is_some()
                            );
                        }
                    }
                } else {
                    thread::sleep(Duration::from_millis(5));
                }
            }
            runtime_log!("[VideoDecoder] Video decoder thread exited. Total frames: {}", frame_count);
        });

        *self.thread_handle.lock() = Some(handle);
    }


    pub fn stop(&self) {
        if !self.is_running.swap(false, Ordering::SeqCst) {
            return;
        }
        runtime_log!("[VideoRuntime] Stopping decoding loop");
        self.packet_queue.close();
        if let Some(handle) = self.thread_handle.lock().take() {
            let _ = handle.join();
        }
    }
}

/// Simulates presenting a video frame to a GPU texture.
pub struct GpuPresenter {
    texture_id: AtomicU32,
}

impl GpuPresenter {
    pub fn new(texture_id: u32) -> Self {
        runtime_log!("[GpuPresenter] Creating presenter for texture_id={}", texture_id);
        Self {
            texture_id: AtomicU32::new(texture_id),
        }
    }

    #[frb(ignore)]
    pub fn present_frame(&self, _frame: &MediaVideoFrame) -> anyhow::Result<()> {
        Ok(())
    }
}

struct PlaybackSession {
    demuxer_thread: Option<thread::JoinHandle<()>>,
    is_running: Arc<AtomicBool>,
}

/// Unified playback engine facade that wraps all internal components.
pub struct MediaPlaybackEngine {
    clock: Arc<PlaybackClock>,
    video_packet_queue: Arc<PacketQueue>,
    audio_packet_queue: Arc<PacketQueue>,
    video_frame_queue: Arc<FrameQueue<MediaVideoFrame>>,
    audio_frame_queue: Arc<FrameQueue<AudioFrame>>,
    video_runtime: VideoRuntime,
    audio_runtime: AudioRuntime,
    presenter: GpuPresenter,
    presenter_runtime: PresenterRuntime,
    seek_target_ms: Arc<AtomicI64>,
    seek_was_playing: Arc<AtomicBool>,
    demuxer_active: Arc<AtomicBool>,
    seek_controller: Arc<SeekController>,
    session: Mutex<Option<PlaybackSession>>,
    duration_ms: Mutex<u64>,
    preview_max_edge: u32,
}

impl MediaPlaybackEngine {
    pub fn new(texture_id: u32, max_queue_size: usize, preview_max_edge: u32) -> Self {
        ensure_ffmpeg_initialized();
        let preview_max_edge = if preview_max_edge == 0 {
            DEFAULT_PREVIEW_MAX_EDGE
        } else {
            preview_max_edge
        };
        runtime_log!(
            "[MediaPlaybackEngine] Initializing texture_id={} max_queue_size={} preview_max_edge={}",
            texture_id,
            max_queue_size,
            preview_max_edge
        );
        let clock = Arc::new(PlaybackClock::new());
        let video_packet_queue = Arc::new(PacketQueue::new(max_queue_size));
        let audio_packet_queue = Arc::new(PacketQueue::new(max_queue_size));
        let video_frame_queue = Arc::new(FrameQueue::new(VIDEO_FRAME_QUEUE_CAP));
        let audio_frame_queue = Arc::new(FrameQueue::new(max_queue_size.min(32)));
        
        let audio_runtime = AudioRuntime::new(
            audio_packet_queue.clone(),
            audio_frame_queue.clone(),
            clock.clone(),
        );
        let video_runtime = VideoRuntime::new(
            video_packet_queue.clone(),
            video_frame_queue.clone(),
            clock.clone(),
            preview_max_edge,
        );
        video_runtime.set_audio_clock(audio_runtime.audio_clock_ms.clone());
        let presenter = GpuPresenter::new(texture_id);
        let seek_target_ms = Arc::new(AtomicI64::new(-1));
        let seek_was_playing = Arc::new(AtomicBool::new(false));
        let demuxer_active = Arc::new(AtomicBool::new(false));
        let seek_controller = Arc::new(SeekController::new(
            seek_target_ms.clone(),
            seek_was_playing.clone(),
            demuxer_active.clone(),
            clock.clone(),
            audio_runtime.audio_clock_ms.clone(),
            video_packet_queue.clone(),
            audio_packet_queue.clone(),
            video_frame_queue.clone(),
            audio_frame_queue.clone(),
        ));

        Self {
            clock,
            video_packet_queue,
            audio_packet_queue,
            video_frame_queue,
            audio_frame_queue,
            video_runtime,
            audio_runtime,
            presenter,
            presenter_runtime: PresenterRuntime::new(),
            seek_target_ms,
            seek_was_playing,
            demuxer_active,
            seek_controller,
            session: Mutex::new(None),
            duration_ms: Mutex::new(0),
            preview_max_edge,
        }
    }

    pub fn open_file(&self, path: String) -> anyhow::Result<()> {
        runtime_log!("[MediaPlaybackEngine] Opening custom video file path={}", path);
        
        // Stop any current demuxer session
        self.stop_demuxer_session();

        let mut ictx = ffmpeg_next::format::input(&path)?;
        let duration_ms = if ictx.duration() >= 0 {
            (ictx.duration() / 1000) as u64
        } else {
            0
        };
        *self.duration_ms.lock() = duration_ms;
        runtime_log!("[MediaPlaybackEngine] Opened file duration={}ms", duration_ms);

        let video_stream = ictx.streams().best(ffmpeg_next::media::Type::Video);
        let audio_stream = ictx.streams().best(ffmpeg_next::media::Type::Audio);

        if let Some(ref s) = video_stream {
            *self.video_runtime.video_params.lock() = Some((s.parameters(), s.time_base()));
        }
        if let Some(ref s) = audio_stream {
            *self.audio_runtime.audio_params.lock() = Some((s.parameters(), s.time_base()));
        }

        self.demuxer_active.store(true, Ordering::Relaxed);
        self.seek_target_ms.store(-1, Ordering::Release);

        let is_running = Arc::new(AtomicBool::new(true));
        let is_running_demux = is_running.clone();
        let seek_target_ms_demux = self.seek_target_ms.clone();
        let seek_was_playing_demux = self.seek_was_playing.clone();
        
        let video_pq = self.video_packet_queue.clone();
        let audio_pq = self.audio_packet_queue.clone();
        
        let video_idx = video_stream.map(|s| s.index());
        let audio_idx = audio_stream.map(|s| s.index());

        self.video_packet_queue.flush();
        self.audio_packet_queue.flush();
        self.video_frame_queue.flush_video();
        self.audio_frame_queue.flush();

        let clock_demux = self.clock.clone();
        let audio_clock_demux = self.audio_runtime.audio_clock_ms.clone();
        let video_fq_demux = self.video_frame_queue.clone();

        let demuxer_thread = thread::spawn(move || {
            runtime_log!("[Demuxer] Started demuxer thread");
            let mut video_count = 0u64;
            let mut audio_count = 0u64;

            'demux: loop {
                // Check for a pending seek before reading the next packet
                let seek_ms = seek_target_ms_demux.load(Ordering::Acquire);
                if seek_ms >= 0 {
                    seek_target_ms_demux.store(-1, Ordering::Release);
                    let was_playing = seek_was_playing_demux.load(Ordering::Relaxed);
                    runtime_log!("[Demuxer] Executing file seek to {}ms was_playing={}", seek_ms, was_playing);

                    // Convert ms to AV_TIME_BASE units (microseconds)
                    let seek_ts = (seek_ms as i64) * 1000;
                    let seek_result = unsafe {
                        // AVSEEK_FLAG_BACKWARD ensures we land on a keyframe at or before the target
                        ffmpeg_next::ffi::avformat_seek_file(
                            ictx.as_mut_ptr(),
                            -1, // any stream
                            i64::MIN,
                            seek_ts,
                            seek_ts,
                            ffmpeg_next::ffi::AVSEEK_FLAG_BACKWARD as i32,
                        )
                    };

                    if seek_result < 0 {
                        runtime_log!("[Demuxer] File seek failed result={}", seek_result);
                    } else {
                        runtime_log!("[Demuxer] File seek succeeded — flushing decoder caches and queues");
                        // Send Flush sentinel so decoder threads reset HEVC/GOP state
                        let _ = video_pq.push(QueuePacket::Flush);
                        let _ = audio_pq.push(QueuePacket::Flush);
                    }

                    // Resume the clock now that seek is done
                    clock_demux.seek_complete(was_playing);
                    runtime_log!("[Demuxer] Seek to {}ms complete, resuming demux", seek_ms);
                }

                // Check if the engine wants us to stop
                if !is_running_demux.load(Ordering::SeqCst) {
                    runtime_log!("[Demuxer] Demuxer thread stop requested");
                    break 'demux;
                }

                // Read the next packet from the container
                let mut packet = ffmpeg_next::Packet::empty();
                match packet.read(&mut ictx) {
                    Ok(()) => {
                        let stream_idx = packet.stream();
                        let is_video = Some(stream_idx) == video_idx;
                        let is_audio = Some(stream_idx) == audio_idx;

                        if is_video || is_audio {
                            let pts_ms = packet.pts().map(|pts| {
                                let tb = ictx.stream(stream_idx).map(|s| s.time_base()).unwrap_or(Rational(1, 1000));
                                (pts as f64 * tb.0 as f64 / tb.1 as f64 * 1000.0) as u64
                            }).unwrap_or(0);

                            let q_pkt = QueuePacket::Real(packet, pts_ms);

                            if is_video {
                                // Slow decode backpressure: avoid filling 2000 packets while VQ is empty.
                                while is_running_demux.load(Ordering::SeqCst) {
                                    let pkt_len = video_pq.len();
                                    let vq_len = video_fq_demux.len();
                                    let audio_ms = audio_clock_demux.load(Ordering::Relaxed);
                                    let lag = audio_ms.saturating_sub(video_fq_demux.latest_pts());
                                    if pkt_len < 400
                                        || vq_len > 0
                                        || lag <= AV_LAG_THRESHOLD_MS
                                    {
                                        break;
                                    }
                                    thread::sleep(Duration::from_millis(20));
                                }
                                video_count += 1;
                                let pushed = video_pq.push(q_pkt);
                                if !pushed {
                                    runtime_log!("[Demuxer] Video queue closed — stopping demux");
                                    break 'demux;
                                }
                            } else {
                                audio_count += 1;
                                let pushed = audio_pq.push(q_pkt);
                                if !pushed {
                                    runtime_log!("[Demuxer] Audio queue closed — stopping demux");
                                    break 'demux;
                                }
                            }
                        }
                    }
                    Err(ffmpeg_next::Error::Eof) => {
                        runtime_log!(
                            "[Demuxer] End of file reached. video={} audio={}. Waiting for seek or stop.",
                            video_count, audio_count
                        );
                        // Wait for either a seek or a stop signal instead of exiting
                        loop {
                            if !is_running_demux.load(Ordering::SeqCst) {
                                break 'demux;
                            }
                            if seek_target_ms_demux.load(Ordering::Acquire) >= 0 {
                                break; // re-enter outer loop to process the seek
                            }
                            thread::sleep(Duration::from_millis(20));
                        }
                    }
                    Err(e) => {
                        runtime_log!("[Demuxer] Error reading packet: {:?} — stopping", e);
                        break 'demux;
                    }
                }
            }
            runtime_log!(
                "[Demuxer] Demuxer thread finished. Total packets: video={}, audio={}",
                video_count,
                audio_count
            );
        });

        *self.session.lock() = Some(PlaybackSession {
            demuxer_thread: Some(demuxer_thread),
            is_running,
        });

        Ok(())
    }

    fn stop_demuxer_session(&self) {
        self.demuxer_active.store(false, Ordering::Relaxed);
        self.seek_target_ms.store(-1, Ordering::Release);
        let mut session_guard = self.session.lock();
        if let Some(mut session) = session_guard.take() {
            session.is_running.store(false, Ordering::SeqCst);
            self.video_packet_queue.close();
            self.audio_packet_queue.close();
            if let Some(handle) = session.demuxer_thread.take() {
                let _ = handle.join();
            }
        }
    }

    pub fn start(&self) {
        runtime_log!("[MediaPlaybackEngine] Starting runtimes");
        self.video_runtime.start();
        self.audio_runtime.start();
        self.clock.start();
        self.presenter_runtime.start(
            self.clock.clone(),
            self.video_frame_queue.clone(),
            self.audio_runtime.audio_clock_ms.clone(),
            self.seek_controller.clone(),
        );
    }

    pub fn pause(&self) {
        runtime_log!("[MediaPlaybackEngine] Pausing clock");
        self.presenter_runtime.stop();
        self.clock.pause();
    }

    pub fn set_rate(&self, rate: f64) {
        runtime_log!("[MediaPlaybackEngine] Setting playback rate to {}", rate);
        self.clock.set_rate(rate);
    }

    pub fn stop(&self) {
        runtime_log!("[MediaPlaybackEngine] Stopping runtimes");
        self.presenter_runtime.stop();
        self.clock.pause();
        self.stop_demuxer_session();
        self.video_runtime.stop();
        self.audio_runtime.stop();
    }

    pub fn seek(&self, time_ms: u64) {
        runtime_log!("[MediaPlaybackEngine] Seeking to {}ms", time_ms);
        self.presenter_runtime.clear_display_frame();
        self.seek_controller.request_seek(time_ms, "ui_seek");
    }

    pub fn push_video_packet(&self, packet: MediaPacket) -> bool {
        self.video_packet_queue.push(QueuePacket::Simulated(packet))
    }

    pub fn push_audio_packet(&self, packet: MediaPacket) -> bool {
        self.audio_packet_queue.push(QueuePacket::Simulated(packet))
    }

    /// Returns the frame selected by [`PresenterRuntime`] (~30 fps), not the raw decode queue.
    pub fn take_video_frame(&self) -> Option<MediaVideoFrame> {
        self.presenter_runtime.take_display_frame()
    }

    pub fn take_audio_frame(&self) -> Option<AudioFrame> {
        self.audio_frame_queue.dequeue()
    }

    pub fn get_audio_waveform(&self) -> Vec<f32> {
        self.audio_runtime.waveform.lock().clone()
    }

    pub fn get_duration_ms(&self) -> u64 {
        *self.duration_ms.lock()
    }

    /// Master playback position in ms.
    ///
    /// Uses the sample-accurate **audio device clock** when audio is actively
    /// playing — this eliminates drift between the wall clock and the hardware
    /// audio output, which is the primary reason video lags behind audio.
    ///
    /// Falls back to the software wall clock during buffering, pause, and seek.
    pub fn get_media_time_ms(&self) -> u64 {
        // Prefer audio sample counter (hardware-paced, zero-drift)
        if self.audio_runtime.is_running.load(Ordering::Relaxed) {
            let audio_ms = self.audio_runtime.audio_clock_ms.load(Ordering::Relaxed);
            if audio_ms > 0 {
                return audio_ms;
            }
        }
        // Fall back to software wall clock
        self.clock.get_media_time_ms()
    }

    /// Audio clock in ms (for Dart diagnostics / A/V drift display).
    /// Returns 0 until audio begins playing.
    pub fn get_audio_clock_ms(&self) -> u64 {
        self.audio_runtime.audio_clock_ms.load(Ordering::Relaxed)
    }

    /// Wall-clock playback position (Instant-based), without audio preference.
    pub fn get_wall_clock_ms(&self) -> u64 {
        self.clock.get_media_time_ms()
    }

    /// PTS of the newest decoded video frame still in the queue (0 if empty).
    pub fn get_latest_decoded_video_pts_ms(&self) -> u64 {
        self.video_frame_queue.latest_pts()
    }

    /// Audio clock minus latest decoded video PTS (0 when in sync).
    pub fn get_av_drift_ms(&self) -> u64 {
        let audio = self.get_audio_clock_ms();
        let video = self.get_latest_decoded_video_pts_ms();
        audio.saturating_sub(video)
    }

    pub fn get_last_presented_pts_ms(&self) -> u64 {
        self.clock.get_last_presented_pts_ms()
    }

    pub fn get_playback_state(&self) -> PlaybackState {
        self.clock.get_state()
    }

    pub fn get_video_packet_queue_len(&self) -> usize {
        self.video_packet_queue.len()
    }

    pub fn get_audio_packet_queue_len(&self) -> usize {
        self.audio_packet_queue.len()
    }

    pub fn get_video_frame_queue_len(&self) -> usize {
        self.video_frame_queue.len()
    }

    pub fn get_audio_frame_queue_len(&self) -> usize {
        self.audio_frame_queue.len()
    }

    #[frb(ignore)]
    pub fn present_frame(&self, frame: &MediaVideoFrame) -> anyhow::Result<()> {
        self.presenter.present_frame(frame)?;
        Ok(())
    }

    /// Presenter tick interval in ms (~30 fps).
    pub fn presenter_interval_ms(&self) -> u64 {
        crate::presenter_runtime::PRESENTER_INTERVAL_MS
    }

    /// Audio-vs-presented drift (ms) that triggers automatic demuxer hard resync.
    pub fn hard_resync_drift_threshold_ms(&self) -> u64 {
        crate::presenter_runtime::HARD_RESYNC_DRIFT_MS
    }

    /// Phase 0: snapshot of linked FFmpeg / VideoToolbox decoder availability.
    pub fn get_decode_capabilities(&self) -> DecodeCapabilities {
        probe_decode_capabilities()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_playback_clock() {
        let clock = PlaybackClock::new();
        assert_eq!(clock.get_state(), PlaybackState::Idle);

        clock.start();
        assert_eq!(clock.get_state(), PlaybackState::Playing);

        thread::sleep(Duration::from_millis(15));
        let t1 = clock.get_media_time_ms();
        assert!(t1 > 0);

        clock.pause();
        assert_eq!(clock.get_state(), PlaybackState::Paused);
        let t2 = clock.get_media_time_ms();
        thread::sleep(Duration::from_millis(15));
        let t3 = clock.get_media_time_ms();
        assert_eq!(t2, t3);

        clock.seek(500);
        assert_eq!(clock.get_media_time_ms(), 500);
    }

    #[test]
    fn test_packet_queue() {
        let queue = PacketQueue::new(2);
        assert_eq!(queue.len(), 0);

        let p1 = MediaPacket {
            pts_ms: 100,
            dts_ms: 100,
            stream_index: 0,
            is_keyframe: true,
            data: vec![0],
        };
        let p2 = MediaPacket {
            pts_ms: 200,
            dts_ms: 200,
            stream_index: 0,
            is_keyframe: false,
            data: vec![0],
        };

        assert!(queue.push(QueuePacket::Simulated(p1)));
        assert!(queue.push(QueuePacket::Simulated(p2)));
        assert_eq!(queue.len(), 2);

        let popped = queue.pop().unwrap();
        match popped {
            QueuePacket::Simulated(p) => assert_eq!(p.pts_ms, 100),
            _ => panic!("Expected simulated packet"),
        }

        queue.close();
        assert!(!queue.push(QueuePacket::Simulated(MediaPacket {
            pts_ms: 300,
            dts_ms: 300,
            stream_index: 0,
            is_keyframe: false,
            data: vec![0],
        })));
    }

    #[test]
    fn test_frame_queue() {
        let queue = FrameQueue::new(2);
        let f1 = MediaVideoFrame {
            pts_ms: 100,
            width: 10,
            height: 10,
            pixels: vec![0],
            pixel_buffer_ptr: 0,
        };
        let f2 = MediaVideoFrame {
            pts_ms: 200,
            width: 10,
            height: 10,
            pixels: vec![0],
            pixel_buffer_ptr: 0,
        };
        let f3 = MediaVideoFrame {
            pts_ms: 300,
            width: 10,
            height: 10,
            pixels: vec![0],
            pixel_buffer_ptr: 0,
        };

        assert!(queue.enqueue(f1).is_none());
        assert!(queue.enqueue(f2).is_none());
        
        // Overflow drops and returns the oldest frame
        let dropped = queue.enqueue(f3).unwrap();
        assert_eq!(dropped.pts_ms, 100);

        let popped = queue.dequeue().unwrap();
        assert_eq!(popped.pts_ms, 200);
    }

    #[test]
    fn test_dequeue_best_for_time_keeps_latest_at_or_before_clock() {
        let queue = FrameQueue::new(8);
        for pts in [100u64, 200, 300, 400] {
            queue.enqueue(MediaVideoFrame {
                pts_ms: pts,
                width: 4,
                height: 4,
                pixels: vec![0; 16],
                pixel_buffer_ptr: 0,
            });
        }
        let at_250 = queue.dequeue_best_for_time(250).unwrap();
        assert_eq!(at_250.pts_ms, 200);
        let at_500 = queue.dequeue_best_for_time(500).unwrap();
        assert_eq!(at_500.pts_ms, 400);
        assert!(queue.is_empty());
    }

    #[test]
    fn test_probe_decode_capabilities() {
        let cap = probe_decode_capabilities();
        assert!(!cap.ffmpeg_version.is_empty());
        runtime_log!(
            "[Phase0 test] hevc_vt={} ready={}",
            cap.hevc_videotoolbox,
            cap.ready_for_hevc_hw
        );
    }
}
