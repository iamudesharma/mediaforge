use parking_lot::{Condvar, Mutex, RwLock};
use std::collections::{HashMap, VecDeque};
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
use crate::video_enhance::{self, VideoEnhancementRuntime};
use crate::vt_hw_decode;

macro_rules! runtime_log {
    ($($arg:tt)*) => {
        eprintln!($($arg)*);
    };
}

static FFMPEG_INIT: std::sync::Once = std::sync::Once::new();

/// Default longest edge for decoded preview frames (matches MediaRuntime).
pub const DEFAULT_PREVIEW_MAX_EDGE: u32 = 1080;
/// Native preservation ceiling: when the Dart configuration requests native
/// resolution it forwards 8192 so every practical source (up to 8K) passes
/// through unscaled. No automatic downscale and no reduction under load —
/// fallback is by decoder/render implementation, not resolution.
pub const NATIVE_PRESERVATION_EDGE: u32 = 8192;
/// When audio clock leads latest decoded video PTS by more than this, enter catch-up.
pub const AV_LAG_THRESHOLD_MS: u64 = 500;
/// Cap on retained decoded frames (production native-resolution policy).
/// Hardware-decoded (VT/MediaCodec/IOSurface): max ~3 frames.
/// Software RGBA/BGRA: max ~2 frames.
/// Never retain 32/64 full-resolution frames (hundreds of MB at 1080p,
/// multi-GB at 4K). See `video_frame_queue_capacity`.
pub const VIDEO_FRAME_QUEUE_CAP_HW: usize = 3;
pub const VIDEO_FRAME_QUEUE_CAP_SW: usize = 2;
// Legacy names kept for backward-compat (mapped to the new small caps).
pub const VIDEO_FRAME_QUEUE_CAP: usize = VIDEO_FRAME_QUEUE_CAP_HW;
pub const VIDEO_FRAME_QUEUE_CAP_LARGE: usize = VIDEO_FRAME_QUEUE_CAP_HW;

/// Byte- and duration-aware packet budgets (replacing fixed 2000-count caps).
/// Video: 16 MiB OR 5 s, whichever first. Audio: 4 MiB OR 5 s.
pub const VIDEO_PACKET_MAX_BYTES: usize = 16 * 1024 * 1024;
pub const VIDEO_PACKET_MAX_DURATION_MS: u64 = 5000;
pub const AUDIO_PACKET_MAX_BYTES: usize = 4 * 1024 * 1024;
pub const AUDIO_PACKET_MAX_DURATION_MS: u64 = 5000;
pub const SUBTITLE_PACKET_MAX_COUNT: usize = 64;
pub const SUBTITLE_PACKET_MAX_BYTES: usize = 256 * 1024;

fn video_frame_queue_capacity(_preview_max_edge: u32) -> usize {
    // Production policy: bound retained decoded memory regardless of edge.
    // HW path keeps 3 (display + next + spare for pacing jitter); SW RGBA
    // keeps 2. Native 4K is preserved by dimensions, not by deeper queues.
    VIDEO_FRAME_QUEUE_CAP_HW
}

/// Software-path decoded queue cap (RGBA/BGRA, 4 bytes/px).
#[allow(dead_code)]
fn video_frame_queue_capacity_sw() -> usize {
    VIDEO_FRAME_QUEUE_CAP_SW
}
/// Timeout for seek recovery to avoid hanging.
pub const RECOVERY_TIMEOUT_MS: u64 = 2000;
/// Frame count limit for seek recovery.
pub const RECOVERY_MAX_FRAMES: u32 = 150;

fn hw_decode_enabled() -> bool {
    !matches!(
        std::env::var("VFP_DISABLE_HW_DECODE").as_deref(),
        Ok("1") | Ok("true") | Ok("yes")
    )
}

/// Select the best *decodable* audio stream, skipping unknown/spatial codecs.
/// FFmpeg's `best()` can pick an undecodable stream (e.g. Apple `apac`) because it
/// has more channels or higher bitrate; this helper prefers known codecs.
fn find_best_audio_stream(ictx: &ffmpeg_next::format::context::Input) -> Option<ffmpeg_next::format::stream::Stream> {
    let known_codecs: &[&str] = &[
        "aac", "ac3", "eac3", "mp3", "flac", "opus", "vorbis", "pcm_s16le", "pcm_s24le",
        "pcm_f32le",
    ];
    let mut fallback = None;
    for stream in ictx.streams() {
        if stream.parameters().medium() != ffmpeg_next::media::Type::Audio {
            continue;
        }
        let codec_id = stream.parameters().id();
        let codec_name = ffmpeg_next::codec::decoder::find(codec_id)
            .map(|c| c.name().to_string())
            .unwrap_or_else(|| "unknown".to_string());
        let is_known = known_codecs.iter().any(|&k| codec_name.contains(k));
        if is_known {
            runtime_log!("[StreamSelect] Selected audio stream {} codec={} (known)", stream.index(), codec_name);
            return Some(stream);
        }
        if fallback.is_none() && codec_name != "none" && !codec_name.is_empty() {
            fallback = Some((stream, codec_name));
        }
    }
    if let Some((stream, codec_name)) = fallback {
        runtime_log!("[StreamSelect] Fallback audio stream {} codec={}", stream.index(), codec_name);
        return Some(stream);
    }
    None
}

/// Human-readable decoder label, e.g. `hevc-videotoolbox`, `h264-software`.
fn video_decoder_label(params: &ffmpeg_next::codec::Parameters, hw: bool) -> String {
    let codec_id = params.id();
    let name = ffmpeg_next::codec::decoder::find(codec_id)
        .map(|c| c.name().to_string())
        .unwrap_or_else(|| "unknown".to_string());
    if hw {
        format!("{}-{}", name, crate::vt_hw_decode::hw_device_name())
    } else {
        format!("{}-software", name)
    }
}

/// Open an audio decoder + F32 resampler for `params` (device-format output).
///
/// Shared by decoder init, seek flush, and audio-track switching so every
/// path constructs an identical pipeline.
fn open_audio_decoder(
    params: &ffmpeg_next::codec::Parameters,
    time_base: Rational,
    sample_rate: u32,
    channels: usize,
) -> Option<(
    ffmpeg_next::codec::decoder::Audio,
    ffmpeg_next::software::resampling::Context,
    Rational,
)> {
    let dec_ctx = CodecContext::from_parameters(params.clone()).ok()?;
    let dec = dec_ctx.decoder().audio().ok()?;
    let in_format = dec.format();
    let in_layout = dec.channel_layout();
    let in_rate = dec.rate();
    let out_layout = if channels == 1 {
        ffmpeg_next::ChannelLayout::MONO
    } else {
        ffmpeg_next::ChannelLayout::STEREO
    };
    let resampler = ffmpeg_next::software::resampling::Context::get(
        in_format,
        in_layout,
        in_rate,
        ffmpeg_next::util::format::sample::Sample::F32(
            ffmpeg_next::format::sample::Type::Packed,
        ),
        out_layout,
        sample_rate,
    )
    .ok()?;
    Some((dec, resampler, time_base))
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
        runtime_log!("[media_forge] env_logger and FFmpeg initialized");
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
    /// Playback is temporarily starved of presentable video frames. The
    /// demux/decode session stays open; the clock and audio output are held
    /// until the recovery buffer is ready.
    Rebuffering,
}

/// Kind of a container stream discovered at open time.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StreamKind {
    Video,
    Audio,
    Subtitle,
}

/// One stream discovered in the opened container or network input.
///
/// Built by [`MediaPlaybackEngine::list_streams`] from FFmpeg stream
/// parameters + metadata (language/title) + disposition (default/forced).
#[derive(Debug, Clone)]
#[frb(non_opaque)]
pub struct MediaStreamInfo {
    /// FFmpeg stream index (stable for the open session).
    pub index: i32,
    pub kind: StreamKind,
    pub codec_name: String,
    pub language: String,
    pub title: String,
    /// Bits per second (0 when the container does not report it).
    pub bitrate: u64,
    /// Video dimensions (0 for non-video).
    pub width: u32,
    pub height: u32,
    /// Audio channels / sample rate (0 for non-audio).
    pub channels: u32,
    pub sample_rate: u32,
    pub is_default: bool,
    pub is_forced: bool,
}

/// HTTP(S) open options for [`MediaPlaybackEngine::open_url`].
///
/// FFmpeg reads the URL directly (redirects + Range seeks included), so
/// Dart never fetches bytes. Headers use exact `Name: Value` pairs.
#[derive(Debug, Clone, Default)]
#[frb(non_opaque)]
pub struct NetworkOptions {
    /// Extra HTTP headers (e.g. `Authorization`, `Cookie`).
    pub headers: HashMap<String, String>,
    /// `User-Agent` override ("" = FFmpeg default).
    pub user_agent: String,
    /// Read timeout in ms (0 = FFmpeg default).
    pub timeout_ms: u64,
    /// Enable `reconnect`/`reconnect_streamed` for flaky links (HLS/live).
    pub reconnect: bool,
}

/// One decoded subtitle cue (text-based only).
///
/// Bitmap (dvd/vobsub, pgssub) cues decode with empty [text]; only their
/// timing is reported until bitmap rendering lands.
#[derive(Debug, Clone)]
#[frb(non_opaque)]
pub struct SubtitleCue {
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
}

/// Cap on queued subtitle cues (oldest dropped beyond this).
const SUBTITLE_CUE_CAP: usize = 256;

/// Build the full stream table for an opened input (video/audio/subtitle).
fn build_stream_table(
    ictx: &ffmpeg_next::format::context::Input,
) -> Vec<MediaStreamInfo> {
    let mut infos = Vec::new();
    for stream in ictx.streams() {
        let medium = stream.parameters().medium();
        let kind = match medium {
            ffmpeg_next::media::Type::Video => StreamKind::Video,
            ffmpeg_next::media::Type::Audio => StreamKind::Audio,
            ffmpeg_next::media::Type::Subtitle => StreamKind::Subtitle,
            _ => continue,
        };
        let codec_id = stream.parameters().id();
        let codec_name = ffmpeg_next::codec::decoder::find(codec_id)
            .map(|c| c.name().to_string())
            .unwrap_or_else(|| "unknown".to_string());
        let (width, height) = match kind {
            StreamKind::Video => video_stream_dims(&stream.parameters()),
            _ => (0, 0),
        };
        let (channels, sample_rate) = match kind {
            StreamKind::Audio => audio_stream_format(&stream.parameters()),
            _ => (0, 0),
        };
        let bitrate = unsafe {
            let st = stream.as_ptr();
            if st.is_null() || (*st).codecpar.is_null() {
                0
            } else {
                (*(*st).codecpar).bit_rate.max(0) as u64
            }
        };
        let disposition = stream.disposition();
        infos.push(MediaStreamInfo {
            index: stream.index() as i32,
            kind,
            codec_name,
            language: stream.metadata().get("language").unwrap_or("").to_string(),
            title: stream.metadata().get("title").unwrap_or("").to_string(),
            bitrate,
            width,
            height,
            channels,
            sample_rate,
            is_default: disposition
                .contains(ffmpeg_next::format::stream::Disposition::DEFAULT),
            is_forced: disposition
                .contains(ffmpeg_next::format::stream::Disposition::FORCED),
        });
    }
    infos
}

/// Video dimensions without opening the decoder (copied from codecpar).
fn video_stream_dims(params: &ffmpeg_next::codec::Parameters) -> (u32, u32) {
    CodecContext::from_parameters(params.clone())
        .ok()
        .and_then(|ctx| ctx.decoder().video().ok())
        .map(|v| (v.width(), v.height()))
        .unwrap_or((0, 0))
}

/// Audio channels / sample rate without opening the decoder.
fn audio_stream_format(params: &ffmpeg_next::codec::Parameters) -> (u32, u32) {
    CodecContext::from_parameters(params.clone())
        .ok()
        .and_then(|ctx| ctx.decoder().audio().ok())
        .map(|a| (a.channels() as u32, a.rate()))
        .unwrap_or((0, 0))
}

/// Display text out of an ASS rect.
///
/// Raw ASS/SSA event text (standalone `.ass` files) is returned as-is. The
/// generic text decoders (srt/vtt/…) and the Matroska path instead hand over
/// a full ASS dialogue payload —
/// `[Dialogue: ]readorder,layer,style,name,marginL,marginR,marginV,effect,text`
/// — whose last field is the real text; the leading fields must never leak
/// into the caption.
fn ass_rect_text(ass: &str) -> &str {
    let payload = ass
        .strip_prefix("Dialogue:")
        .map(str::trim_start)
        .unwrap_or(ass);
    let fields: Vec<&str> = payload.splitn(9, ',').collect();
    if fields.len() == 9
        && fields[0].trim().parse::<i64>().is_ok()
        && fields[1].trim().parse::<i64>().is_ok()
    {
        return fields[8];
    }
    payload
}

/// Strip ASS/SSA override groups (`{...}`) and convert `\N` to newline.
fn strip_ass_overrides(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut in_brace = false;
    for ch in text.chars() {
        match ch {
            '{' => in_brace = true,
            '}' => in_brace = false,
            _ if !in_brace => out.push(ch),
            _ => {}
        }
    }
    out.replace("\\N", "\n").replace("\\n", "\n")
}

/// Extract display text from a decoded subtitle (text/ASS rects joined).
fn subtitle_text(sub: &ffmpeg_next::Subtitle) -> String {
    let mut parts = Vec::new();
    for rect in sub.rects() {
        match rect {
            ffmpeg_next::codec::subtitle::Rect::Text(t) => {
                parts.push(t.get().to_string())
            }
            ffmpeg_next::codec::subtitle::Rect::Ass(a) => {
                parts.push(strip_ass_overrides(ass_rect_text(a.get())))
            }
            _ => {}
        }
    }
    parts.join("\n").trim().to_string()
}

/// Text plus display window (ms, relative to the packet PTS) of a decoded
/// subtitle, releasing the FFmpeg struct afterwards.
///
/// `avsubtitle_free` memsets the whole struct — display times included — so
/// the window MUST be read before freeing. Reading it afterwards silently
/// yields `0..0`, which the cue gate then drops as degenerate (every sidecar
/// cue was lost this way).
fn take_subtitle(sub: &mut ffmpeg_next::Subtitle) -> (String, u64, u64) {
    let text = subtitle_text(sub);
    let start = sub.start().max(0) as u64;
    let end = sub.end().max(0) as u64;
    unsafe {
        ffmpeg_next::ffi::avsubtitle_free(sub.as_mut_ptr());
    }
    (text, start, end)
}

/// State of the decoder recovery process.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecoderRecoveryState {
    Idle,
    Seeking,
    Recovering,
    Ready,
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

    /// Freeze media time during a transient video starvation. This is a
    /// state transition only: it deliberately does not seek, flush queues,
    /// reopen the source, or reset the last presented PTS.
    pub fn enter_rebuffering(&self) {
        self.update_time_internal();
        let mut inner = self.inner.write();
        if inner.state == PlaybackState::Playing {
            inner.state = PlaybackState::Rebuffering;
            inner.last_updated_instant = None;
            runtime_log!(
                "[PlaybackClock] Entered rebuffering media_time_ms={}",
                inner.media_time_ms
            );
        }
    }

    /// Resume a previously starved session from the exact frozen media time.
    pub fn resume_from_rebuffering(&self) {
        let mut inner = self.inner.write();
        if inner.state == PlaybackState::Rebuffering {
            inner.state = PlaybackState::Playing;
            inner.last_updated_instant = Some(Instant::now());
            runtime_log!(
                "[PlaybackClock] Rebuffering recovered media_time_ms={}",
                inner.media_time_ms
            );
        }
    }

    pub fn seek(&self, time_ms: u64) {
        let mut inner = self.inner.write();
        let was_playing = matches!(
            inner.state,
            PlaybackState::Playing | PlaybackState::Rebuffering
        );
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

    /// Called when the seek is complete — resumes the appropriate playback state and aligns clock to presented frame PTS.
    pub fn seek_complete(&self, was_playing: bool, presented_pts_ms: u64) {
        let mut inner = self.inner.write();
        if inner.state == PlaybackState::Seeking {
            inner.media_time_ms = presented_pts_ms;
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
    Real(ffmpeg_next::Packet, u64, u64), // Packet, pts_ms, seek_generation
    Simulated(MediaPacket),
    /// Flush sentinel: tells decoder threads to drain and reset their codec context.
    Flush(u64, u64), // seek_generation, target_ms
}

impl QueuePacket {
    /// Compressed size in bytes (0 for flush sentinels).
    fn byte_size(&self) -> usize {
        match self {
            QueuePacket::Real(pkt, _, _) => pkt.size() as usize,
            QueuePacket::Simulated(p) => p.data.len(),
            QueuePacket::Flush(_, _) => 0,
        }
    }

    /// PTS in ms if the packet carries one.
    fn pts_ms_opt(&self) -> Option<u64> {
        match self {
            QueuePacket::Real(_, pts, _) => Some(*pts),
            QueuePacket::Simulated(p) => Some(p.pts_ms),
            QueuePacket::Flush(_, _) => None,
        }
    }
}

struct PacketQueueInner {
    queue: VecDeque<QueuePacket>,
    is_closed: bool,
    bytes: usize,
    min_pts_ms: Option<u64>,
    max_pts_ms: Option<u64>,
}

/// Thread-safe bounded packet queue with byte- and duration-aware budgets.
///
/// A packet is admitted only while count, byte and duration limits all hold —
/// whichever limit is reached first applies. Replaces fixed 2000-count caps.
pub struct PacketQueue {
    inner: Mutex<PacketQueueInner>,
    cond_not_empty: Condvar,
    cond_not_full: Condvar,
    max_size: usize,
    max_bytes: usize,
    max_duration_ms: u64,
}

impl PacketQueue {
    pub fn new(max_size: usize) -> Self {
        // Legacy count-only constructor (kept for tests/compat): derive
        // generous byte/duration ceilings so count remains the binding limit.
        let max_bytes = max_size.saturating_mul(128 * 1024).max(4 * 1024 * 1024);
        runtime_log!("[PacketQueue] Creating queue with max_size={}", max_size);
        Self {
            inner: Mutex::new(PacketQueueInner {
                queue: VecDeque::new(),
                is_closed: false,
                bytes: 0,
                min_pts_ms: None,
                max_pts_ms: None,
            }),
            cond_not_empty: Condvar::new(),
            cond_not_full: Condvar::new(),
            max_size,
            max_bytes,
            max_duration_ms: u64::MAX,
        }
    }

    /// Budget-aware constructor: count AND bytes AND duration all bound.
    pub fn new_with_budgets(max_size: usize, max_bytes: usize, max_duration_ms: u64) -> Self {
        runtime_log!(
            "[PacketQueue] Creating budgeted queue count={} bytes={} duration={}ms",
            max_size, max_bytes, max_duration_ms
        );
        Self {
            inner: Mutex::new(PacketQueueInner {
                queue: VecDeque::new(),
                is_closed: false,
                bytes: 0,
                min_pts_ms: None,
                max_pts_ms: None,
            }),
            cond_not_empty: Condvar::new(),
            cond_not_full: Condvar::new(),
            max_size,
            max_bytes,
            max_duration_ms,
        }
    }

    fn is_full_locked(&self, inner: &PacketQueueInner) -> bool {
        if inner.queue.len() >= self.max_size {
            return true;
        }
        if inner.bytes >= self.max_bytes {
            return true;
        }
        if let (Some(min), Some(max)) = (inner.min_pts_ms, inner.max_pts_ms) {
            if max.saturating_sub(min) >= self.max_duration_ms {
                return true;
            }
        }
        false
    }

    pub fn push(&self, packet: QueuePacket) -> bool {
        let mut inner = self.inner.lock();
        if self.is_full_locked(&inner) && !inner.is_closed {
            runtime_log!("[PacketQueue] Queue is full (len={}/{} bytes={}/{}), waiting to push...", inner.queue.len(), self.max_size, inner.bytes, self.max_bytes);
        }
        while self.is_full_locked(&inner) && !inner.is_closed {
            self.cond_not_full.wait(&mut inner);
        }
        if inner.is_closed {
            runtime_log!("[PacketQueue] Push failed: Queue is closed");
            return false;
        }
        if let Some(pts) = packet.pts_ms_opt() {
            inner.min_pts_ms = Some(inner.min_pts_ms.map_or(pts, |m| m.min(pts)));
            inner.max_pts_ms = Some(inner.max_pts_ms.map_or(pts, |m| m.max(pts)));
        }
        inner.bytes = inner.bytes.saturating_add(packet.byte_size());
        inner.queue.push_back(packet);
        self.cond_not_empty.notify_one();
        true
    }

    pub fn pop(&self) -> Option<QueuePacket> {
        let mut inner = self.inner.lock();
        while inner.queue.is_empty() && !inner.is_closed {
            self.cond_not_empty.wait(&mut inner);
        }
        if inner.queue.is_empty() && inner.is_closed {
            return None;
        }
        let packet = inner.queue.pop_front();
        if let Some(ref pkt) = packet {
            inner.bytes = inner.bytes.saturating_sub(pkt.byte_size());
            // Recompute span when the window empties or the edge leaves.
            if inner.queue.is_empty() {
                inner.min_pts_ms = None;
                inner.max_pts_ms = None;
                inner.bytes = 0;
            } else if pkt.pts_ms_opt().is_some() {
                // Cheap recompute only when needed (queues are short).
                let mut min: Option<u64> = None;
                let mut max: Option<u64> = None;
                for q in inner.queue.iter() {
                    if let Some(pts) = q.pts_ms_opt() {
                        min = Some(min.map_or(pts, |m| m.min(pts)));
                        max = Some(max.map_or(pts, |m| m.max(pts)));
                    }
                }
                inner.min_pts_ms = min;
                inner.max_pts_ms = max;
            }
        }
        self.cond_not_full.notify_one();
        packet
    }

    /// Non-blocking pop for frame-ready pump integration (returns None when
    /// empty instead of blocking). Used by interrupt-aware paths.
    pub fn try_pop(&self) -> Option<QueuePacket> {
        let mut inner = self.inner.lock();
        if inner.queue.is_empty() {
            return None;
        }
        let packet = inner.queue.pop_front();
        if let Some(ref pkt) = packet {
            inner.bytes = inner.bytes.saturating_sub(pkt.byte_size());
            if inner.queue.is_empty() {
                inner.min_pts_ms = None;
                inner.max_pts_ms = None;
                inner.bytes = 0;
            }
        }
        self.cond_not_full.notify_one();
        packet
    }

    pub fn flush(&self) {
        let mut inner = self.inner.lock();
        let cleared = inner.queue.len();
        inner.is_closed = false;
        inner.queue.clear();
        inner.bytes = 0;
        inner.min_pts_ms = None;
        inner.max_pts_ms = None;
        self.cond_not_full.notify_all();
        runtime_log!("[PacketQueue] Queue flushed, cleared {} packets", cleared);
    }

    pub fn close(&self) {
        let mut inner = self.inner.lock();
        let cleared = inner.queue.len();
        inner.is_closed = true;
        inner.queue.clear();
        inner.bytes = 0;
        inner.min_pts_ms = None;
        inner.max_pts_ms = None;
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

    /// Current buffered bytes (observable via diagnostics).
    pub fn bytes(&self) -> usize {
        self.inner.lock().bytes
    }

    /// Current buffered span in ms (max PTS − min PTS, 0 when <2 timed packets).
    pub fn duration_ms(&self) -> u64 {
        let inner = self.inner.lock();
        match (inner.min_pts_ms, inner.max_pts_ms) {
            (Some(min), Some(max)) => max.saturating_sub(min),
            _ => 0,
        }
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
    /// Queue-overflow drops (frame discarded because the queue was full).
    overflow_dropped: AtomicU64,
    /// §5 frame-ready signal (notified on every successful enqueue).
    notify: Mutex<Option<Arc<(Mutex<u64>, Condvar)>>>,
}

impl<T> FrameQueue<T> {
    pub fn new(max_size: usize) -> Self {
        runtime_log!("[FrameQueue] Creating frame queue with max_size={}", max_size);
        Self {
            queue: Mutex::new(VecDeque::new()),
            max_size,
            overflow_dropped: AtomicU64::new(0),
            notify: Mutex::new(None),
        }
    }

    #[frb(ignore)]
    pub fn set_notify(&self, signal: Arc<(Mutex<u64>, Condvar)>) {
        *self.notify.lock() = Some(signal);
    }

    #[frb(ignore)]
    fn notify_ready(&self) {
        if let Some(sig) = self.notify.lock().clone() {
            let lock = &sig.0;
            let cvar = &sig.1;
            let mut v = lock.lock();
            *v = v.wrapping_add(1);
            cvar.notify_one();
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

    /// Queue-overflow drops since creation (observable, never empty polls).
    pub fn overflow_count(&self) -> u64 {
        self.overflow_dropped.load(Ordering::Relaxed)
    }
}

impl<T: HasPts> FrameQueue<T> {
    /// Enqueue a frame. Drops the oldest frame if the queue is full and returns it.
    /// Inserts in sorted PTS order. Overflow is counted (never empty polls).
    pub fn enqueue(&self, frame: T) -> Option<T> {
        let mut queue = self.queue.lock();
        let mut dropped = None;
        if queue.len() >= self.max_size {
            dropped = queue.pop_front();
            if dropped.is_some() {
                self.overflow_dropped.fetch_add(1, Ordering::Relaxed);
            }
        }
        let pos = queue.binary_search_by_key(&frame.pts_ms(), |f| f.pts_ms())
            .unwrap_or_else(|e| e);
        queue.insert(pos, frame);
        drop(queue);
        self.notify_ready();
        dropped
    }
}

impl FrameQueue<MediaVideoFrame> {
    /// Like [`FrameQueue::enqueue`] but logs when the queue drops a frame.
    /// Overflow releases the pixel-buffer ref immediately (no leak).
    pub fn enqueue_video(&self, frame: MediaVideoFrame) -> Option<MediaVideoFrame> {
        let dropped = self.enqueue(frame);
        if let Some(ref old) = dropped {
            release_media_video_frame_pixel_buffer(old);
            runtime_log!(
                "[VideoDecoder] Dropped oldest frame (PTS: {}ms) — queue full ({}/{}) overflow_total={}",
                old.pts_ms,
                self.len(),
                self.max_size(),
                self.overflow_count(),
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

    /// Estimated retained decoded-frame memory in bytes (w*h*4 per frame).
    pub fn frame_memory_bytes(&self) -> usize {
        let q = self.queue.lock();
        q.iter()
            .map(|f| f.width as usize * f.height as usize * 4)
            .sum()
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
#[derive(Debug, Clone)]
#[frb(non_opaque)]
pub struct MediaVideoFrame {
    pub pts_ms: u64,
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
    pub pixel_buffer_ptr: u64,
    pub seek_generation: u64,
}

/// Hand off `CVPixelBuffer` to Flutter without releasing on [MediaVideoFrame] drop.
#[frb(non_opaque)]
pub struct PixelBufferHandoff {
    pub pts_ms: u64,
    pub width: u32,
    pub height: u32,
    pub pixel_buffer_ptr: u64,
    pub seek_generation: u64,
}

// ── GPU video enhancement (experimental) ──────────────────────────────
//
// The quality ladder is a public enum so host apps never pass magic numbers,
// and the wire names are stable (they appear in logs and diagnostics).
// Off is the default everywhere: enabling enhancement is always explicit.

/// Requested video enhancement quality.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VideoEnhancementMode {
    /// Untouched render path (default).
    Off,
    /// Lightweight GPU sharpen at native size.
    Sharp,
    /// High-quality upscale + adaptive sharpen + light dither.
    Enhanced,
    /// Best non-AI upscale (separable Lanczos-3) + adaptive sharpen.
    HighQuality,
}

impl VideoEnhancementMode {
    fn to_internal(self) -> video_enhance::EnhancementMode {
        use video_enhance::EnhancementMode as M;
        match self {
            VideoEnhancementMode::Off => M::Off,
            VideoEnhancementMode::Sharp => M::Sharp,
            VideoEnhancementMode::Enhanced => M::Enhanced,
            VideoEnhancementMode::HighQuality => M::HighQuality,
        }
    }

    fn from_internal(mode: video_enhance::EnhancementMode) -> Self {
        use video_enhance::EnhancementMode as M;
        match mode {
            M::Off => VideoEnhancementMode::Off,
            M::Sharp => VideoEnhancementMode::Sharp,
            M::Enhanced => VideoEnhancementMode::Enhanced,
            M::HighQuality => VideoEnhancementMode::HighQuality,
        }
    }
}

/// What this device/build can do. Never fails playback: `supported == false`
/// simply means the normal render path stays in place.
#[frb(non_opaque)]
pub struct VideoEnhancementCapabilities {
    pub supported: bool,
    /// Backend identity, e.g. `metal_wgpu`.
    pub backend: String,
    /// Modes that will actually run (always contains `Off`).
    pub modes: Vec<VideoEnhancementMode>,
    /// Largest output longest edge the backend produces.
    pub max_output_edge: u32,
    /// Why enhancement is unavailable (empty when supported).
    pub reason: String,
}

/// Live enhancement state for diagnostics.
#[frb(non_opaque)]
pub struct VideoEnhancementStatus {
    pub supported: bool,
    pub requested_mode: VideoEnhancementMode,
    /// Mode actually running; differs from `requested_mode` after an
    /// automatic quality downgrade.
    pub active_mode: VideoEnhancementMode,
    pub backend: String,
    /// Executed pass path, e.g. `metal_lanczos_cas`.
    pub path: String,
    /// `none` / `catmull_rom` / `lanczos3`.
    pub scaler: String,
    pub input_width: u32,
    pub input_height: u32,
    pub output_width: u32,
    pub output_height: u32,
    /// Enhancement stage time for the last frame (ms).
    pub last_frame_ms: f32,
    /// Smoothed enhancement stage time (ms).
    pub average_frame_ms: f32,
    /// Source frame interval the stage is measured against (ms).
    pub deadline_ms: f32,
    pub deadline_misses: u64,
    pub hard_deadline_misses: u64,
    pub enhanced_frames: u64,
    pub bypassed_frames: u64,
    pub failed_frames: u64,
    /// GPU passes issued for the last frame.
    pub passes: u32,
    /// Why enhancement fell back (empty when healthy).
    pub fallback_reason: String,
    /// Why the last frame was bypassed (empty when it was enhanced).
    pub bypass_reason: String,
}

/// Stable wire names used in logs and diagnostics. Host apps use the enum
/// variants, so these helpers stay out of the generated bridge surface.
impl VideoEnhancementMode {
    #[frb(ignore)]
    pub fn wire_name(self) -> &'static str {
        self.to_internal().as_str()
    }

    /// Parse a stable wire name; unknown input maps to `Off`.
    #[frb(ignore)]
    pub fn from_wire_name(name: &str) -> Self {
        Self::from_internal(video_enhance::EnhancementMode::from_wire(name))
    }
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
        seek_generation: frame.seek_generation,
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
    pub seek_generation: u64,
}

// ── Overlay audio tracks ──────────────────────────────────────────────

/// Lightweight shared state for one overlay track inside the cpal callback.
/// Updated by the overlay's decoder thread; read by the cpal mixer.
#[frb(ignore)]
pub struct OverlayAudioState {
    pub frame_queue: Arc<FrameQueue<AudioFrame>>,
    pub current_frame: Option<AudioFrame>,
    pub sample_idx: usize,
    pub volume: Arc<AtomicU32>,       // stored as (volume * 1000) for atomic u32
    pub timeline_start_ms: u64,
    pub duration_ms: u64,
    pub source_start_ms: u64,
    pub is_running: Arc<AtomicBool>,
    pub was_in_bounds: bool,
}

impl OverlayAudioState {
    /// Volume as f32 (0.0 .. 1.0).
    pub fn volume_f32(&self) -> f32 {
        self.volume.load(Ordering::Relaxed) as f32 / 1000.0
    }
}

/// One overlay audio track: owns its demuxer + decoder threads.
#[frb(ignore)]
#[allow(dead_code)]
pub(crate) struct OverlayAudioTrack {
    pub id: u64,
    pub path: String,
    pub shared: Arc<Mutex<OverlayAudioState>>,
    demuxer_handle: Mutex<Option<thread::JoinHandle<()>>>,
    decoder_handle: Mutex<Option<thread::JoinHandle<()>>>,
    is_running: Arc<AtomicBool>,
    pub packet_queue: Arc<PacketQueue>,
}

impl OverlayAudioTrack {
    /// Open an overlay audio file, start demuxer + decoder threads.
    pub fn open(
        id: u64,
        path: String,
        volume: f32,
        timeline_start_ms: u64,
        duration_ms: u64,
        source_start_ms: u64,
        audio_clock_ms: Arc<AtomicU64>,
        _clock: Arc<PlaybackClock>,
        output_sample_rate: u32,
        output_channels: usize,
        seek_generation: Arc<AtomicU64>,
    ) -> anyhow::Result<Self> {
        let is_running = Arc::new(AtomicBool::new(true));

        let packet_queue = Arc::new(PacketQueue::new(512));
        let frame_queue = Arc::new(FrameQueue::new(32));

        let shared = Arc::new(Mutex::new(OverlayAudioState {
            frame_queue: frame_queue.clone(),
            current_frame: None,
            sample_idx: 0,
            volume: Arc::new(AtomicU32::new((volume * 1000.0) as u32)),
            timeline_start_ms,
            duration_ms,
            source_start_ms,
            is_running: is_running.clone(),
            was_in_bounds: false,
        }));

        // ── Demuxer thread ──
        let pq = packet_queue.clone();
        let is_running_demux = is_running.clone();
        let path_clone = path.clone();
        let seek_gen_demux = seek_generation.clone();
        let audio_clock_demux = audio_clock_ms.clone();
        let demuxer_handle = thread::spawn(move || {
            runtime_log!("[OverlayDemuxer] id={} started path={}", id, path_clone);
            let mut ictx = match ffmpeg_next::format::input(&path_clone) {
                Ok(ctx) => ctx,
                Err(e) => {
                    runtime_log!("[OverlayDemuxer] id={} open failed: {}", id, e);
                    return;
                }
            };

            let audio_idx = find_best_audio_stream(&ictx).map(|s| s.index());

            // Initial seek on open to match current playhead
            let current_clock_ms = audio_clock_demux.load(Ordering::Relaxed);
            let initial_seek_ms = if current_clock_ms >= timeline_start_ms {
                let offset = current_clock_ms - timeline_start_ms;
                if offset < duration_ms {
                    source_start_ms + offset
                } else {
                    source_start_ms + duration_ms
                }
            } else {
                source_start_ms
            };

            if initial_seek_ms > 0 {
                let seek_ts = (initial_seek_ms as i64) * 1000;
                let seek_result = unsafe {
                    ffmpeg_next::ffi::avformat_seek_file(
                        ictx.as_mut_ptr(),
                        -1,
                        i64::MIN,
                        seek_ts,
                        seek_ts,
                        ffmpeg_next::ffi::AVSEEK_FLAG_BACKWARD as i32,
                    )
                };
                if seek_result < 0 {
                    runtime_log!("[OverlayDemuxer] id={} initial seek to {}ms failed: {}", id, initial_seek_ms, seek_result);
                } else {
                    runtime_log!("[OverlayDemuxer] id={} initial seek to {}ms succeeded (master={}ms)", id, initial_seek_ms, current_clock_ms);
                }
            }

            let mut count = 0u64;
            let mut last_gen = seek_gen_demux.load(Ordering::Relaxed);
            loop {
                if !is_running_demux.load(Ordering::SeqCst) {
                    break;
                }

                // Check for a pending seek
                let current_gen = seek_gen_demux.load(Ordering::Relaxed);
                if current_gen != last_gen {
                    last_gen = current_gen;
                    let target_ms = audio_clock_demux.load(Ordering::Relaxed);
                    let file_seek_ms = if target_ms >= timeline_start_ms {
                        let offset = target_ms - timeline_start_ms;
                        if offset < duration_ms {
                            source_start_ms + offset
                        } else {
                            source_start_ms + duration_ms
                        }
                    } else {
                        source_start_ms
                    };

                    runtime_log!(
                        "[OverlayDemuxer] id={} seeking to file position {}ms (master={}ms gen={})",
                        id, file_seek_ms, target_ms, current_gen
                    );

                    let seek_ts = (file_seek_ms as i64) * 1000;
                    let seek_result = unsafe {
                        ffmpeg_next::ffi::avformat_seek_file(
                            ictx.as_mut_ptr(),
                            -1,
                            i64::MIN,
                            seek_ts,
                            seek_ts,
                            ffmpeg_next::ffi::AVSEEK_FLAG_BACKWARD as i32,
                        )
                    };
                    if seek_result < 0 {
                        runtime_log!("[OverlayDemuxer] id={} seek failed: {}", id, seek_result);
                    } else {
                        pq.flush();
                        let _ = pq.push(QueuePacket::Flush(current_gen, file_seek_ms));
                    }
                }

                // Sleep backpressure to avoid filling the queue
                while pq.len() >= 512 && is_running_demux.load(Ordering::SeqCst) {
                    let current_gen = seek_gen_demux.load(Ordering::Relaxed);
                    if current_gen != last_gen {
                        break;
                    }
                    thread::sleep(Duration::from_millis(10));
                }

                let mut packet = ffmpeg_next::Packet::empty();
                match packet.read(&mut ictx) {
                    Ok(()) => {
                        if Some(packet.stream()) == audio_idx {
                            let pts_ms = packet.pts().map(|pts| {
                                let tb = ictx
                                    .stream(packet.stream())
                                    .map(|s| s.time_base())
                                    .unwrap_or(Rational(1, 1000));
                                (pts as f64 * tb.0 as f64 / tb.1 as f64 * 1000.0) as u64
                            }).unwrap_or(0);
                            let gen = seek_gen_demux.load(Ordering::Relaxed);
                            let _ = pq.push(QueuePacket::Real(packet, pts_ms, gen));
                            count += 1;
                        }
                    }
                    Err(ffmpeg_next::Error::Eof) => {
                        while is_running_demux.load(Ordering::SeqCst) {
                            let current_gen = seek_gen_demux.load(Ordering::Relaxed);
                            if current_gen != last_gen {
                                break;
                            }
                            thread::sleep(Duration::from_millis(20));
                        }
                    }
                    Err(e) => {
                        runtime_log!("[OverlayDemuxer] id={} read error: {}", id, e);
                        break;
                    }
                }
            }
            runtime_log!("[OverlayDemuxer] id={} finished packets={}", id, count);
        });

        // ── Decoder thread ──
        let fq = frame_queue.clone();
        let is_running_dec = is_running.clone();
        let path_clone2 = path.clone();
        let pq_dec = packet_queue.clone();
        let decoder_handle = thread::spawn(move || {
            runtime_log!("[OverlayDecoder] id={} started", id);
            let ictx = match ffmpeg_next::format::input(&path_clone2) {
                Ok(ctx) => ctx,
                Err(e) => {
                    runtime_log!("[OverlayDecoder] id={} open failed: {}", id, e);
                    return;
                }
            };

            let audio_stream = match find_best_audio_stream(&ictx) {
                Some(s) => s,
                None => {
                    runtime_log!("[OverlayDecoder] id={} no audio stream", id);
                    return;
                }
            };

            let params = audio_stream.parameters();
            let tb = audio_stream.time_base();
            let dec_ctx = match CodecContext::from_parameters(params) {
                Ok(ctx) => ctx,
                Err(e) => {
                    runtime_log!("[OverlayDecoder] id={} codec context failed: {}", id, e);
                    return;
                }
            };
            let mut decoder = match dec_ctx.decoder().audio() {
                Ok(d) => d,
                Err(e) => {
                    runtime_log!("[OverlayDecoder] id={} decoder init failed: {}", id, e);
                    return;
                }
            };

            let in_format = decoder.format();
            let in_layout = decoder.channel_layout();
            let in_rate = decoder.rate();
            let out_layout = if output_channels == 1 {
                ffmpeg_next::ChannelLayout::MONO
            } else {
                ffmpeg_next::ChannelLayout::STEREO
            };

            let mut resampler = match ffmpeg_next::software::resampling::Context::get(
                in_format,
                in_layout,
                in_rate,
                ffmpeg_next::util::format::sample::Sample::F32(
                    ffmpeg_next::format::sample::Type::Packed,
                ),
                out_layout,
                output_sample_rate,
            ) {
                Ok(r) => r,
                Err(e) => {
                    runtime_log!("[OverlayDecoder] id={} resampler failed: {}", id, e);
                    return;
                }
            };

            let mut frame_count = 0u64;
            let mut current_seek_generation = 0u64;
            loop {
                if !is_running_dec.load(Ordering::SeqCst) {
                    break;
                }
                if fq.len() >= fq.max_size() {
                    thread::sleep(Duration::from_millis(10));
                    continue;
                }
                match pq_dec.pop() {
                    Some(QueuePacket::Real(pkt, pts_ms, gen)) => {
                        if gen < current_seek_generation {
                            continue;
                        }
                        if decoder.send_packet(&pkt).is_ok() {
                            let mut decoded =
                                ffmpeg_next::util::frame::audio::Audio::empty();
                            while decoder.receive_frame(&mut decoded).is_ok() {
                                frame_count += 1;
                                let frame_pts_ms = decoded.pts().map(|pts| {
                                    (pts as f64 * tb.0 as f64 / tb.1 as f64 * 1000.0)
                                        as u64
                                }).unwrap_or(pts_ms);

                                let mut resampled =
                                    ffmpeg_next::util::frame::audio::Audio::empty();
                                if resampler.run(&decoded, &mut resampled).is_ok() {
                                    let nb = resampled.samples();
                                    let data = resampled.data(0);
                                    let need =
                                        nb * output_channels * std::mem::size_of::<f32>();
                                    if data.len() >= need {
                                        let slice = unsafe {
                                            std::slice::from_raw_parts(
                                                data.as_ptr() as *const f32,
                                                nb * output_channels,
                                            )
                                        };
                                        let audio_frame = AudioFrame {
                                            pts_ms: frame_pts_ms,
                                            sample_rate: output_sample_rate,
                                            channels: output_channels as u32,
                                            samples: slice.to_vec(),
                                            seek_generation: gen,
                                        };
                                        fq.enqueue(audio_frame);
                                    }
                                }
                            }
                        }
                    }
                    Some(QueuePacket::Flush(gen, _target)) => {
                        current_seek_generation = gen;
                        fq.flush();
                        unsafe {
                            ffmpeg_next::ffi::avcodec_flush_buffers(
                                decoder.as_mut_ptr(),
                            );
                        }
                        // Recreate resampler context to clear internal buffers
                        match ffmpeg_next::software::resampling::Context::get(
                            in_format,
                            in_layout,
                            in_rate,
                            ffmpeg_next::util::format::sample::Sample::F32(
                                ffmpeg_next::format::sample::Type::Packed,
                            ),
                            out_layout,
                            output_sample_rate,
                        ) {
                            Ok(r) => {
                                resampler = r;
                            }
                            Err(e) => {
                                runtime_log!("[OverlayDecoder] id={} resampler recreation failed on flush: {}", id, e);
                            }
                        }
                    }
                    Some(_) => {}
                    None => {
                        thread::sleep(Duration::from_millis(5));
                    }
                }
            }
            runtime_log!(
                "[OverlayDecoder] id={} finished frames={}",
                id,
                frame_count
            );
        });

        Ok(Self {
            id,
            path,
            shared,
            demuxer_handle: Mutex::new(Some(demuxer_handle)),
            decoder_handle: Mutex::new(Some(decoder_handle)),
            is_running,
            packet_queue,
        })
    }

    pub fn stop(&self) {
        self.is_running.store(false, Ordering::SeqCst);
        self.packet_queue.close();
        if let Some(h) = self.demuxer_handle.lock().take() {
            let _ = h.join();
        }
        if let Some(h) = self.decoder_handle.lock().take() {
            let _ = h.join();
        }
    }

    pub fn set_volume(&self, volume: f32) {
        let s = self.shared.lock();
        s.volume
            .store((volume.clamp(0.0, 1.0) * 1000.0) as u32, Ordering::Relaxed);
    }
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
    /// When true, the cpal callback writes silence instead of decoded samples.
    is_muted: Arc<AtomicBool>,
    /// Master gain shared with [`AudioRuntime`]; read once per buffer.
    volume: Arc<AtomicU32>,
    /// When true, source video audio is silenced but overlay tracks still play.
    source_muted: Arc<AtomicBool>,
    /// Trim end in ms — when audio clock reaches this, playback ends.
    trim_end_ms: Arc<AtomicU64>,
    /// Set by the cpal callback when audio clock >= trim_end_ms.
    trim_end_reached: Arc<AtomicBool>,
    /// Shared overlay audio states — **shared** with AudioRuntime via Arc<Mutex<>>
    /// so overlays added after start() are visible to the cpal callback.
    overlay_states: Arc<Mutex<Vec<Arc<Mutex<OverlayAudioState>>>>>,
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
    audio_clock_ms: Arc<AtomicU64>,
    has_video: Arc<AtomicBool>,
    seek_was_playing: Arc<AtomicBool>,
    seek_generation: Arc<AtomicU64>,
    /// Bumped by track switching so the decoder thread reopens its codec.
    audio_params_epoch: Arc<AtomicU64>,
    /// Mute flag — when true, cpal writes silence while keeping the clock running.
    is_muted: Arc<AtomicBool>,
    /// Master output gain in millis (1000 = 1.0). Applied to source + overlays.
    volume: Arc<AtomicU32>,
    /// Source-only mute — silences embedded video audio while overlays keep playing.
    source_muted: Arc<AtomicBool>,
    /// Trim end in ms — set by MediaPlaybackEngine, read by cpal callback.
    trim_end_ms: Arc<AtomicU64>,
    /// Set by cpal callback when audio clock >= trim_end_ms.
    trim_end_reached: Arc<AtomicBool>,
    /// Overlay audio tracks mixed into the output in real-time.
    #[frb(ignore)]
    overlay_tracks: Mutex<Vec<Arc<OverlayAudioTrack>>>,
    /// Shared overlay state handles — **same Arc** passed to cpal callback
    /// so overlays added after start() are immediately visible.
    #[frb(ignore)]
    overlay_states: Arc<Mutex<Vec<Arc<Mutex<OverlayAudioState>>>>>,
    /// Next overlay ID.
    #[frb(ignore)]
    next_overlay_id: AtomicU64,
    /// Output sample rate discovered at start() time; used by add_overlay() to resample to device format.
    #[frb(ignore)]
    output_sample_rate: AtomicU32,
    /// Output channel count discovered at start() time; used by add_overlay() to match device format.
    #[frb(ignore)]
    output_channels: AtomicU32,
}

impl AudioRuntime {
    #[frb(ignore)]
    pub fn new(
        packet_queue: Arc<PacketQueue>,
        frame_queue: Arc<FrameQueue<AudioFrame>>,
        clock: Arc<PlaybackClock>,
        seek_was_playing: Arc<AtomicBool>,
        seek_generation: Arc<AtomicU64>,
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
            has_video: Arc::new(AtomicBool::new(true)),
            seek_was_playing,
            seek_generation,
            audio_params_epoch: Arc::new(AtomicU64::new(0)),
            is_muted: Arc::new(AtomicBool::new(false)),
            volume: Arc::new(AtomicU32::new(1000)),
            source_muted: Arc::new(AtomicBool::new(false)),
            trim_end_ms: Arc::new(AtomicU64::new(u64::MAX)),
            trim_end_reached: Arc::new(AtomicBool::new(false)),
            overlay_tracks: Mutex::new(Vec::new()),
            overlay_states: Arc::new(Mutex::new(Vec::new())),
            next_overlay_id: AtomicU64::new(1),
            output_sample_rate: AtomicU32::new(48000),
            output_channels: AtomicU32::new(2),
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

                // Store output format so add_overlay() can resample to device format.
                self.output_sample_rate.store(sample_rate as u32, Ordering::Relaxed);
                self.output_channels.store(channels as u32, Ordering::Relaxed);
                runtime_log!("[AudioRuntime] Output format: {}Hz {}ch", sample_rate, channels);

                let audio_clock_ms_arc = self.audio_clock_ms.clone();
                let is_muted_arc = self.is_muted.clone();
                let volume_arc = self.volume.clone();
                let source_muted_arc = self.source_muted.clone();
                let trim_end_ms_arc = self.trim_end_ms.clone();
                let trim_end_reached_arc = self.trim_end_reached.clone();
                // Pass the shared Arc — cpal callback will lock it each buffer,
                // so overlays added after start() are visible.
                let overlay_states_shared = self.overlay_states.clone();
                let player_state = Arc::new(Mutex::new(AudioPlayerState {
                    frame_queue: self.frame_queue.clone(),
                    clock: self._clock.clone(),
                    current_frame: None,
                    current_sample_idx: 0,
                    waveform: self.waveform.clone(),
                    audio_clock_ms: audio_clock_ms_arc,
                    is_muted: is_muted_arc,
                    volume: volume_arc,
                    source_muted: source_muted_arc,
                    trim_end_ms: trim_end_ms_arc,
                    trim_end_reached: trim_end_reached_arc,
                    overlay_states: overlay_states_shared,
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
                        let muted = state.is_muted.load(Ordering::Relaxed);
                        let master_gain =
                            (state.volume.load(Ordering::Relaxed) as f32 / 1000.0)
                                .clamp(0.0, 1.0);
                        let source_gain = if state.source_muted.load(Ordering::Relaxed) {
                            0.0f32
                        } else {
                            1.0f32
                        };

                        // Update sample-accurate audio master clock once per buffer.
                        // Formula: frame_pts + samples_consumed_in_frame / (sample_rate * channels)
                        // Clock must keep ticking even when muted so position stays accurate.
                        if is_playing {
                            if let Some(ref frame) = state.current_frame {
                                let sr = state.sr.max(1);
                                let ch = state.ch.max(1);
                                let offset_ms = (state.current_sample_idx as u64 * 1000) / (sr * ch);
                                let audio_ms =
                                    frame.pts_ms.saturating_add(offset_ms);
                                state.audio_clock_ms.store(audio_ms, Ordering::Relaxed);
                                state.clock.sync_from_audio_ms(audio_ms);

                                // Trim-end detection: when audio clock reaches trim_end_ms,
                                // signal the engine to transition to Ended state.
                                let te = state.trim_end_ms.load(Ordering::Relaxed);
                                if te < u64::MAX && audio_ms >= te {
                                    state.trim_end_reached.store(true, Ordering::Relaxed);
                                }
                            }
                        }

                        // If trim end was reached, output silence and let the
                        // engine handle the state transition.
                        if state.trim_end_reached.load(Ordering::Relaxed) {
                            for sample in data.iter_mut() {
                                *sample = 0.0;
                            }
                            return;
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

                        // When muted: still consume samples to keep the decoder
                        // advancing and the clock ticking, but output silence.
                        if muted {
                            let mut sample_count = 0usize;
                            for sample in data.iter_mut() {
                                if let Some(frame) = &state.current_frame {
                                    if state.current_sample_idx < frame.samples.len() {
                                        state.current_sample_idx += 1;
                                        sample_count += 1;
                                        *sample = 0.0;
                                        continue;
                                    }
                                }
                                // Try to dequeue next frame to keep pipeline moving
                                state.current_frame = state.frame_queue.dequeue();
                                state.current_sample_idx = 0;
                                if let Some(frame) = &state.current_frame {
                                    if state.current_sample_idx < frame.samples.len() {
                                        state.current_sample_idx += 1;
                                        sample_count += 1;
                                    }
                                }
                                *sample = 0.0;
                            }
                            // Still update waveform with zeros so UI shows muted state
                            if sample_count > 0 {
                                let mut wf = state.waveform.lock();
                                wf.remove(0);
                                wf.push(0.0);
                            }
                            return;
                        }

let mut max_amplitude = 0.0f32;
                        let mut sample_count = 0;
                        let buffer_len = data.len();

                        // ── Pre-fetch overlay samples for the entire buffer ──
                        // Lock each overlay once, pull enough samples for the whole buffer
                        // into a local Vec, then release all locks. The per-sample inner loop
                        // below reads from these local Vecs with zero locking overhead.
                        // This eliminates per-sample, per-overlay mutex contention that was
                        // causing priority inversion in the real-time audio callback when
                        // 8+ overlay tracks were active (each requiring a Mutex lock per sample).
                        let overlay_states_ref = state.overlay_states.clone();
                        struct OverlayMix {
                            samples: Vec<f32>,
                            idx: usize,
                        }
                        let mut overlay_mixes: Vec<OverlayMix> = {
                            let overlays = overlay_states_ref.lock();
                            overlays.iter().map(|ov| {
                                let mut ov_guard = ov.lock();
                                let vol = ov_guard.volume_f32();
                                let master_ms = state.audio_clock_ms.load(Ordering::Relaxed);
                                let in_bounds = master_ms >= ov_guard.timeline_start_ms
                                    && master_ms < ov_guard.timeline_start_ms + ov_guard.duration_ms;
                                if !in_bounds && ov_guard.was_in_bounds {
                                    ov_guard.frame_queue.flush();
                                    ov_guard.current_frame = None;
                                    ov_guard.sample_idx = 0;
                                    ov_guard.was_in_bounds = false;
                                }
                                if in_bounds {
                                    ov_guard.was_in_bounds = true;
                                }
                                if !in_bounds || vol <= 0.0 {
                                    return OverlayMix { samples: Vec::new(), idx: 0 };
                                }
                                let mut buf = Vec::with_capacity(buffer_len);
                                while buf.len() < buffer_len {
                                    // Extract what we need from the current frame, then
                                    // advance index / dequeue without borrow conflict.
                                    let consumed = match ov_guard.current_frame {
                                        Some(ref frame) if ov_guard.sample_idx < frame.samples.len() => {
                                            let start = ov_guard.sample_idx;
                                            let remaining = frame.samples.len() - start;
                                            let take = remaining.min(buffer_len - buf.len());
                                            for i in start..start + take {
                                                buf.push(frame.samples[i] * vol);
                                            }
                                            ov_guard.sample_idx = start + take;
                                            take
                                        }
                                        _ => 0,
                                    };
                                    if consumed == 0 {
                                        // Current frame exhausted or absent — dequeue next
                                        ov_guard.current_frame = ov_guard.frame_queue.dequeue();
                                        ov_guard.sample_idx = 0;
                                        if ov_guard.current_frame.is_none() {
                                            break;
                                        }
                                    }
                                }
                                OverlayMix { samples: buf, idx: 0 }
                            }).collect()
                        };

                        for sample in data.iter_mut() {
                            // ── Source audio ──
                            let mut mixed = 0.0f32;
                            if let Some(frame) = &state.current_frame {
                                if state.current_sample_idx < frame.samples.len() {
                                    mixed += frame.samples[state.current_sample_idx] * source_gain;
                                    state.current_sample_idx += 1;
                                    sample_count += 1;
                                } else {
                                    // Frame exhausted — dequeue next, skipping 0-sample frames
                                    loop {
                                        state.current_frame = state.frame_queue.dequeue();
                                        state.current_sample_idx = 0;
                                        if let Some(ref f) = state.current_frame {
                                            if f.samples.len() > 0 && state.current_sample_idx < f.samples.len() {
                                                mixed += f.samples[state.current_sample_idx] * source_gain;
                                                state.current_sample_idx += 1;
                                                sample_count += 1;
                                                break;
                                            }
                                            // Skip 0-sample frames to avoid getting stuck
                                        } else {
                                            break;
                                        }
                                    }
                                }
                            } else {
                                // No current frame — dequeue, skipping 0-sample frames
                                loop {
                                    state.current_frame = state.frame_queue.dequeue();
                                    state.current_sample_idx = 0;
                                    if let Some(ref f) = state.current_frame {
                                        if f.samples.len() > 0 && state.current_sample_idx < f.samples.len() {
                                            mixed += f.samples[state.current_sample_idx] * source_gain;
                                            state.current_sample_idx += 1;
                                            sample_count += 1;
                                            break;
                                        }
                                    } else {
                                        break;
                                    }
                                }
                            }

                            // ── Overlay audio mixing (lock-free, reads from pre-fetched Vec) ──
                            for omix in overlay_mixes.iter_mut() {
                                if omix.idx < omix.samples.len() {
                                    mixed += omix.samples[omix.idx];
                                    omix.idx += 1;
                                }
                            }

                            // Clamp to prevent clipping (master gain covers source + overlays)
                            *sample = (mixed * master_gain).clamp(-1.0, 1.0);
                            let abs_val = (mixed * master_gain).abs();
                            if abs_val > max_amplitude {
                                max_amplitude = abs_val;
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
        let audio_params_epoch = self.audio_params_epoch.clone();
        let clock = self._clock.clone();
        let seek_was_playing = self.seek_was_playing.clone();
        let has_video = self.has_video.clone();
        let seek_generation = self.seek_generation.clone();
        let audio_clock_ms = self.audio_clock_ms.clone();

        let handle = thread::spawn(move || {
            runtime_log!("[AudioDecoder] Started audio decoder thread");
            let mut decoder_state = None;
            let mut frame_count = 0;
            let mut resampler = None;

            if let Some((params, tb)) = &*audio_params.lock() {
                match open_audio_decoder(params, *tb, sample_rate as u32, channels) {
                    Some((dec, res, decoded_tb)) => {
                        runtime_log!("[AudioDecoder] FFmpeg audio decoder initialized");
                        resampler = Some(res);
                        decoder_state = Some((dec, decoded_tb));
                    }
                    None => {
                        runtime_log!("[AudioDecoder] Failed to initialize audio decoder");
                    }
                }
            }

            let mut last_queue_full_log = Instant::now() - Duration::from_secs(5);
            let mut current_seek_generation = 0u64;
            let mut decoder_epoch = 0u64;
            let mut recovery_state = DecoderRecoveryState::Ready;
            let mut recovering_target_ms = None;
            let mut recovery_started_at = Instant::now();
            let mut recovery_frame_count = 0u32;
            let mut stale_frames_dropped = 0u32;

            while is_running.load(Ordering::SeqCst) {
                // Audio-track switch: reopen the codec when params changed.
                let epoch_now = audio_params_epoch.load(Ordering::Relaxed);
                if epoch_now != decoder_epoch {
                    decoder_epoch = epoch_now;
                    if let Some((params, tb)) = &*audio_params.lock() {
                        if let Some((dec, res, decoded_tb)) =
                            open_audio_decoder(params, *tb, sample_rate as u32, channels)
                        {
                            decoder_state = Some((dec, decoded_tb));
                            resampler = Some(res);
                            frame_queue.flush();
                            runtime_log!(
                                "[AudioDecoder] Reopened decoder for switched audio track epoch={}",
                                epoch_now
                            );
                        }
                    }
                }
                if let Some(target) = recovering_target_ms {
                    let elapsed_ms = recovery_started_at.elapsed().as_millis() as u64;
                    if !has_video.load(Ordering::Relaxed) && (elapsed_ms >= RECOVERY_TIMEOUT_MS || recovery_frame_count >= RECOVERY_MAX_FRAMES) {
                        runtime_log!(
                            "[AudioDecoder] Seek recovery watchdog triggered (audio-only): gen={} target={}ms decoded={} stale_dropped={} recovery_ms={}ms",
                            current_seek_generation,
                            target,
                            recovery_frame_count,
                            stale_frames_dropped,
                            elapsed_ms
                        );
                        recovering_target_ms = None;
                        recovery_state = DecoderRecoveryState::Ready;
                        let was_playing = seek_was_playing.load(Ordering::Relaxed);
                        clock.seek_complete(was_playing, target);
                    }
                }

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
                        QueuePacket::Real(pkt, pts_ms, gen) => {
                            if gen < current_seek_generation {
                                stale_frames_dropped += 1;
                                // Discard stale pre-seek packet
                                continue;
                            }
                            if recovery_state == DecoderRecoveryState::Seeking {
                                recovery_state = DecoderRecoveryState::Recovering;
                            }
                            if let Some((ref mut decoder, tb)) = decoder_state {
                                match decoder.send_packet(&pkt) {
                                    Ok(_) => {
                                        let mut decoded = ffmpeg_next::util::frame::audio::Audio::empty();
                                        while decoder.receive_frame(&mut decoded).is_ok() {
                                            frame_count += 1;
                                            
                                            let frame_pts_ms = decoded.pts().map(|pts| {
                                                (pts as f64 * tb.0 as f64 / tb.1 as f64 * 1000.0) as u64
                                            }).unwrap_or(pts_ms);

                                            if let Some(target) = recovering_target_ms {
                                                recovery_frame_count += 1;
                                                if frame_pts_ms < target {
                                                    // Discard frame before seek target
                                                    continue;
                                                } else {
                                                    let elapsed_ms = recovery_started_at.elapsed().as_millis() as u64;
                                                    runtime_log!(
                                                        "[AudioDecoder] Seek recovery complete (metrics) -> gen: {}, recovery_ms: {}ms, recovery_frames_decoded: {}, stale_frames_dropped: {}",
                                                        current_seek_generation,
                                                        elapsed_ms,
                                                        recovery_frame_count,
                                                        stale_frames_dropped
                                                    );
                                                    recovering_target_ms = None;
                                                    recovery_state = DecoderRecoveryState::Ready;
                                                    audio_clock_ms.store(frame_pts_ms, Ordering::Relaxed);
                                                    if !has_video.load(Ordering::Relaxed) {
                                                        let was_playing = seek_was_playing.load(Ordering::Relaxed);
                                                        clock.seek_complete(was_playing, frame_pts_ms);
                                                    }
                                                }
                                            }

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
                                                seek_generation: gen,
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
                                seek_generation: 0,
                            };
                            let _ = frame_queue.enqueue(audio_frame);
                        }
                        QueuePacket::Flush(gen, target_ms) => {
                            let latest_gen = seek_generation.load(Ordering::Relaxed);
                            if gen < latest_gen {
                                runtime_log!(
                                    "[AudioDecoder] Latest seek wins: skipping intermediate recovery for gen={} (latest_gen={})",
                                    gen,
                                    latest_gen
                                );
                                current_seek_generation = gen;
                                continue;
                            }

                            runtime_log!("[AudioDecoder] Received Flush sentinel — flushing audio decoder state gen={} target_ms={}", gen, target_ms);
                            current_seek_generation = gen;
                            recovering_target_ms = Some(target_ms);
                            recovery_state = DecoderRecoveryState::Seeking;
                            recovery_started_at = Instant::now();
                            recovery_frame_count = 0;
                            stale_frames_dropped = 0;
                            // Clear resampler context to clear internal sample buffer
                            resampler = None;
                            if let Some((ref mut decoder, _)) = decoder_state {
                                // Drain remaining frames
                                let _ = decoder.send_eof();
                                let mut tmp = ffmpeg_next::util::frame::audio::Audio::empty();
                                while decoder.receive_frame(&mut tmp).is_ok() {}
                                // Flush internal codec buffers (resets AAC/opus state)
                                unsafe {
                                    ffmpeg_next::ffi::avcodec_flush_buffers(decoder.as_mut_ptr());
                                }
                                
                                // Re-initialize resampler context
                                if let Some((ref params, _)) = &*audio_params.lock() {
                                    if let Ok(dec_ctx) = CodecContext::from_parameters(params.clone()) {
                                        if let Ok(dec) = dec_ctx.decoder().audio() {
                                            let in_format = dec.format();
                                            let in_layout = dec.channel_layout();
                                            let in_rate = dec.rate();
                                            let out_layout = if channels == 1 {
                                                ffmpeg_next::ChannelLayout::MONO
                                            } else {
                                                ffmpeg_next::ChannelLayout::STEREO
                                            };
                                            if let Ok(r) = ffmpeg_next::software::resampling::Context::get(
                                                in_format,
                                                in_layout,
                                                in_rate,
                                                ffmpeg_next::util::format::sample::Sample::F32(ffmpeg_next::format::sample::Type::Packed),
                                                out_layout,
                                                sample_rate as u32,
                                            ) {
                                                resampler = Some(r);
                                            }
                                        }
                                    }
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

    /// Enable or disable audio muting. When muted, the cpal callback writes
    /// silence while continuing to consume decoded frames so the clock and
    /// decoder pipeline stay in sync.
    pub fn set_muted(&self, muted: bool) {
        self.is_muted.store(muted, Ordering::Relaxed);
        runtime_log!("[AudioRuntime] Muted={}", muted);
    }

    /// Master output gain 0.0..=1.0 applied to source + overlay mix in the
    /// cpal callback. Independent from [`AudioRuntime::set_muted`].
    pub fn set_volume(&self, volume: f32) {
        let clamped = volume.clamp(0.0, 1.0);
        self.volume
            .store((clamped * 1000.0) as u32, Ordering::Relaxed);
        runtime_log!("[AudioRuntime] Volume={:.2}", clamped);
    }

    /// Current master gain 0.0..=1.0.
    pub fn get_volume(&self) -> f32 {
        self.volume.load(Ordering::Relaxed) as f32 / 1000.0
    }

    /// Mute only the source (embedded video) audio lane. Overlay tracks keep playing.
    pub fn set_source_muted(&self, muted: bool) {
        self.source_muted.store(muted, Ordering::Relaxed);
        runtime_log!("[AudioRuntime] SourceMuted={}", muted);
    }

    /// Set the trim end point in ms. The cpal callback monitors the audio
    /// clock and sets `trim_end_reached` when it reaches this value.
    pub fn set_trim_end_ms(&self, end_ms: u64) {
        self.trim_end_ms.store(end_ms, Ordering::Relaxed);
        self.trim_end_reached.store(false, Ordering::Relaxed);
        runtime_log!("[AudioRuntime] trim_end_ms={}", end_ms);
    }

    /// Returns true when the audio clock has reached the trim end point.
    pub fn is_trim_end_reached(&self) -> bool {
        self.trim_end_reached.load(Ordering::Relaxed)
    }

    /// Clear the trim-end flag (e.g. after a seek backward past trim end).
    pub fn clear_trim_end_reached(&self) {
        self.trim_end_reached.store(false, Ordering::Relaxed);
    }

    // ── Overlay audio track management ──

    /// Add an overlay audio track. Returns the overlay ID.
    /// The track is demuxed and decoded in background threads, and its PCM
    /// output is mixed into the cpal callback alongside the source audio.
    pub fn add_overlay(
        &self,
        path: String,
        volume: f32,
        timeline_start_ms: u64,
        duration_ms: u64,
        source_start_ms: u64,
    ) -> u64 {
        let id = self.next_overlay_id.fetch_add(1, Ordering::SeqCst);

        // Use the output format discovered when the cpal stream was started.
        // Falls back to 48000/2 if start() hasn't run yet (unlikely in practice).
        let sr = self.output_sample_rate.load(Ordering::Relaxed) as u32;
        let ch = self.output_channels.load(Ordering::Relaxed) as usize;

        match OverlayAudioTrack::open(
            id,
            path.clone(),
            volume,
            timeline_start_ms,
            duration_ms,
            source_start_ms,
            self.audio_clock_ms.clone(),
            self._clock.clone(),
            sr,
            ch,
            self.seek_generation.clone(),
        ) {
            Ok(track) => {
                let shared = track.shared.clone();
                // Add to both the track list (for lifecycle) and the shared states
                // (for cpal callback access). The cpal callback locks overlay_states
                // each buffer, so overlays added here are visible immediately.
                self.overlay_tracks.lock().push(Arc::new(track));
                self.overlay_states.lock().push(shared);
                runtime_log!(
                    "[AudioRuntime] Added overlay id={} path={} vol={:.2} start={}ms dur={}ms source_start={}ms",
                    id,
                    path,
                    volume,
                    timeline_start_ms,
                    duration_ms,
                    source_start_ms
                );
                id
            }
            Err(e) => {
                runtime_log!("[AudioRuntime] Failed to add overlay: {}", e);
                u64::MAX // error sentinel
            }
        }
    }

    /// Remove an overlay audio track by ID.
    pub fn remove_overlay(&self, id: u64) {
        let track_to_stop = {
            let mut tracks = self.overlay_tracks.lock();
            let track = if let Some(pos) = tracks.iter().position(|t| t.id == id) {
                Some(tracks.remove(pos))
            } else {
                None
            };
            // Rebuild shared overlay_states from remaining tracks
            let mut states = self.overlay_states.lock();
            states.clear();
            for t in tracks.iter() {
                states.push(t.shared.clone());
            }
            track
        }; // locks dropped here

        if let Some(track) = track_to_stop {
            track.stop();
            runtime_log!("[AudioRuntime] Removed overlay id={}", id);
        }
    }

    /// Set volume for an overlay track (0.0 .. 1.0).
    pub fn set_overlay_volume(&self, id: u64, volume: f32) {
        let tracks = self.overlay_tracks.lock();
        if let Some(track) = tracks.iter().find(|t| t.id == id) {
            track.set_volume(volume);
        }
    }

    /// Flush all overlay frame queues (called on seek).
    pub fn flush_overlay_queues(&self) {
        let states = self.overlay_states.lock();
        for s in states.iter() {
            let mut state = s.lock();
            state.frame_queue.flush();
            state.current_frame = None;
            state.sample_idx = 0;
            state.was_in_bounds = false;
        }
    }

    /// Stop and remove all overlay tracks.
    pub fn stop_all_overlays(&self) {
        let tracks_to_stop = {
            let mut tracks = self.overlay_tracks.lock();
            tracks.drain(..).collect::<Vec<_>>()
        };
        self.overlay_states.lock().clear();
        for track in tracks_to_stop {
            track.stop();
        }
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
    seek_was_playing: Arc<AtomicBool>,
    seek_generation: Arc<AtomicU64>,
    /// Pre-decode drops: stale generation + recovery gate (shared with engine).
    stale_dropped: Arc<AtomicU64>,
    /// Pre-decode drops: catch-up policy (shared with engine).
    catchup_dropped: Arc<AtomicU64>,
    /// Queue-overflow drops (frame queue full, shared with engine).
    overflow_dropped: Arc<AtomicU64>,
    /// e.g. `hevc-videotoolbox` (shared with engine diagnostics).
    decoder_label: Arc<Mutex<String>>,
    /// True when the active pipeline is HW (shared with engine diagnostics).
    hw_decode_active: Arc<AtomicBool>,
    /// §5 frame-ready signal (decoder notifies after each enqueue).
    frame_ready: Mutex<Option<Arc<(Mutex<u64>, Condvar)>>>,
}

impl VideoRuntime {
    #[frb(ignore)]
    pub fn new(
        packet_queue: Arc<PacketQueue>,
        frame_queue: Arc<FrameQueue<MediaVideoFrame>>,
        clock: Arc<PlaybackClock>,
        preview_max_edge: u32,
        seek_was_playing: Arc<AtomicBool>,
        seek_generation: Arc<AtomicU64>,
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
            seek_was_playing,
            seek_generation,
            stale_dropped: Arc::new(AtomicU64::new(0)),
            catchup_dropped: Arc::new(AtomicU64::new(0)),
            overflow_dropped: Arc::new(AtomicU64::new(0)),
            decoder_label: Arc::new(Mutex::new("none".to_string())),
            hw_decode_active: Arc::new(AtomicBool::new(false)),
            frame_ready: Mutex::new(None),
        }
    }

    #[frb(ignore)]
    pub fn set_audio_clock(&self, audio_clock_ms: Arc<AtomicU64>) {
        *self.audio_clock_ms.lock() = Some(audio_clock_ms);
    }

    #[frb(ignore)]
    pub fn set_frame_ready(&self, signal: Arc<(Mutex<u64>, Condvar)>) {
        *self.frame_ready.lock() = Some(signal);
    }

    #[frb(ignore)]
    fn notify_frame_ready(&self) {
        if let Some(sig) = self.frame_ready.lock().clone() {
            let lock = &sig.0;
            let cvar = &sig.1;
            let mut v = lock.lock();
            *v = v.wrapping_add(1);
            cvar.notify_one();
        }
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
        let clock = self._clock.clone();
        let seek_was_playing = self.seek_was_playing.clone();
        let seek_generation = self.seek_generation.clone();
        let stale_dropped_shared = self.stale_dropped.clone();
        let catchup_dropped_shared = self.catchup_dropped.clone();
        let decoder_label_shared = self.decoder_label.clone();
        let hw_active_shared = self.hw_decode_active.clone();

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
                    let label = video_decoder_label(&params, h.is_some());
                    *decoder_label_shared.lock() = label.clone();
                    hw_active_shared.store(h.is_some(), Ordering::Relaxed);
                    runtime_log!("[VideoDecoder] Pipeline ready decoder={}", label);
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
                recovering: bool,
                current_gen: u64,
                stale_dropped: &mut u32,
                stale_shared: &AtomicU64,
                catchup_shared: &AtomicU64,
            ) -> Option<QueuePacket> {
                loop {
                    let pkt = packet_queue.pop()?;
                    match pkt {
                        QueuePacket::Flush(gen, target_ms) => {
                            if gen < current_gen {
                                *stale_dropped += 1;
                                stale_shared.fetch_add(1, Ordering::Relaxed);
                                continue;
                            }
                            return Some(QueuePacket::Flush(gen, target_ms));
                        }
                        QueuePacket::Simulated(p) => return Some(QueuePacket::Simulated(p)),
                        QueuePacket::Real(p, pts_ms, gen) => {
                            if gen < current_gen {
                                *stale_dropped += 1;
                                stale_shared.fetch_add(1, Ordering::Relaxed);
                                continue;
                            }
                            let is_key = p.is_key();
                            if recovering {
                                if *require_keyframe && !is_key {
                                    catchup_shared.fetch_add(1, Ordering::Relaxed);
                                    continue;
                                }
                                *require_keyframe = false;
                                return Some(QueuePacket::Real(p, pts_ms, gen));
                            } else {
                                if crate::video_decode::packet_dropped_in_catchup(
                                    is_key,
                                    lag_ms,
                                    *require_keyframe,
                                ) {
                                    catchup_shared.fetch_add(1, Ordering::Relaxed);
                                    continue;
                                }
                                *require_keyframe = false;
                                return Some(QueuePacket::Real(p, pts_ms, gen));
                            }
                        }
                    }
                }
            }

            let mut current_seek_generation = 0u64;
            let mut recovery_state = DecoderRecoveryState::Ready;
            let mut recovering_target_ms = None;
            let mut recovery_frame_count = 0u32;
            let mut recovery_started_at = Instant::now();
            let mut stale_frames_dropped = 0u32;

            while is_running.load(Ordering::SeqCst) {
                let lag_ms = video_decode_lag_ms(&audio_clock_ms, &frame_queue);
                let recovering = recovering_target_ms.is_some();
                let decode_behind = lag_ms > CATCHUP_SKIP_NON_KEYFRAME_MS && !recovering;

                if let Some(target) = recovering_target_ms {
                    let elapsed_ms = recovery_started_at.elapsed().as_millis() as u64;
                    if elapsed_ms >= RECOVERY_TIMEOUT_MS || recovery_frame_count >= RECOVERY_MAX_FRAMES {
                        let latest_pts = frame_queue.latest_pts();
                        let fallback_pts = if latest_pts > 0 { latest_pts } else { target };
                        runtime_log!(
                            "[VideoDecoder] Seek recovery watchdog triggered: gen={} target={}ms decoded={} stale_dropped={} recovery_ms={}ms fallback_pts={}ms",
                            current_seek_generation,
                            target,
                            recovery_frame_count,
                            stale_frames_dropped,
                            elapsed_ms,
                            fallback_pts
                        );
                        recovering_target_ms = None;
                        recovery_state = DecoderRecoveryState::Ready;
                        audio_clock_ms.store(fallback_pts, Ordering::Relaxed);
                        let was_playing = seek_was_playing.load(Ordering::Relaxed);
                        clock.seek_complete(was_playing, fallback_pts);
                    }
                }

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
                    pop_packet_for_decode(&packet_queue, lag_ms, &mut require_keyframe, recovering, current_seek_generation, &mut stale_frames_dropped, &stale_dropped_shared, &catchup_dropped_shared)
                {
                    match queue_packet {
                        QueuePacket::Real(pkt, pts_ms, gen) => {
                            if gen < current_seek_generation {
                                stale_frames_dropped += 1;
                                stale_dropped_shared.fetch_add(1, Ordering::Relaxed);
                                continue;
                            }
                            if recovery_state == DecoderRecoveryState::Seeking {
                                recovery_state = DecoderRecoveryState::Recovering;
                            }
                            if let Some(ref mut hw) = hw_state {
                                if hw.dec.send_packet(&pkt).is_ok() {
                                    let mut decoded = VideoFrameImpl::empty();
                                    while hw.dec.receive_frame(&mut decoded).is_ok() {
                                        frame_count += 1;
                                        if recovering {
                                            recovery_frame_count += 1;
                                        }
                                        if frame_count % 150 == 0 {
                                            runtime_log!(
                                                "[VideoDecoder] Decoded {} frames (HW path), recovering={} recovery_frame_count={}",
                                                frame_count,
                                                recovering,
                                                recovery_frame_count
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
                                                gen,
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
                                                        gen,
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
                                                    gen,
                                                );
                                            }
                                        }

                                        // Check seek recovery completion
                                        if let Some(target) = recovering_target_ms {
                                            let latest_pts = frame_queue.latest_pts();
                                            let elapsed_ms = recovery_started_at.elapsed().as_millis() as u64;
                                            if latest_pts >= target || recovery_frame_count >= RECOVERY_MAX_FRAMES || elapsed_ms >= RECOVERY_TIMEOUT_MS {
                                                runtime_log!(
                                                    "[VideoDecoder] Seek recovery complete (metrics) -> gen: {}, recovery_ms: {}ms, recovery_frames_decoded: {}, stale_frames_dropped: {}",
                                                    current_seek_generation,
                                                    elapsed_ms,
                                                    recovery_frame_count,
                                                    stale_frames_dropped
                                                );
                                                recovering_target_ms = None;
                                                recovery_state = DecoderRecoveryState::Ready;
                                                audio_clock_ms.store(latest_pts, Ordering::Relaxed);
                                                let was_playing = seek_was_playing.load(Ordering::Relaxed);
                                                clock.seek_complete(was_playing, latest_pts);
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
                                            if recovering {
                                                recovery_frame_count += 1;
                                            }
                                            if frame_count % 150 == 0 {
                                                runtime_log!(
                                                    "[VideoDecoder] Decoded {} frames (SW path), recovering={} recovery_frame_count={}",
                                                    frame_count,
                                                    recovering,
                                                    recovery_frame_count
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
                                                gen,
                                            );

                                            // Check seek recovery completion
                                            if let Some(target) = recovering_target_ms {
                                                let latest_pts = frame_queue.latest_pts();
                                                let elapsed_ms = recovery_started_at.elapsed().as_millis() as u64;
                                                if latest_pts >= target || recovery_frame_count >= RECOVERY_MAX_FRAMES || elapsed_ms >= RECOVERY_TIMEOUT_MS {
                                                    runtime_log!(
                                                        "[VideoDecoder] Seek recovery complete (SW, metrics) -> gen: {}, recovery_ms: {}ms, recovery_frames_decoded: {}, stale_frames_dropped: {}",
                                                        current_seek_generation,
                                                        elapsed_ms,
                                                        recovery_frame_count,
                                                        stale_frames_dropped
                                                    );
                                                    recovering_target_ms = None;
                                                    recovery_state = DecoderRecoveryState::Ready;
                                                    audio_clock_ms.store(latest_pts, Ordering::Relaxed);
                                                    let was_playing = seek_was_playing.load(Ordering::Relaxed);
                                                    clock.seek_complete(was_playing, latest_pts);
                                                }
                                            }
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
                                seek_generation: 0,
                            };
                            let _ = frame_queue.enqueue(video_frame);
                        }
                        QueuePacket::Flush(gen, target_ms) => {
                            let latest_gen = seek_generation.load(Ordering::Relaxed);
                            if gen < latest_gen {
                                runtime_log!(
                                    "[VideoDecoder] Latest seek wins: skipping intermediate recovery for gen={} (latest_gen={})",
                                    gen,
                                    latest_gen
                                );
                                current_seek_generation = gen;
                                continue;
                            }

                            runtime_log!(
                                "[VideoDecoder] Flush — reopening decoders and scalers for post-seek gen={} target_ms={}",
                                gen,
                                target_ms
                            );
                            current_seek_generation = gen;
                            recovering_target_ms = Some(target_ms);
                            recovery_state = DecoderRecoveryState::Seeking;
                            recovery_frame_count = 0;
                            stale_frames_dropped = 0;
                            recovery_started_at = Instant::now();

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
    #[allow(dead_code)]
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
#[allow(dead_code)]
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
    seek_generation: Arc<AtomicU64>,
    session: Mutex<Option<PlaybackSession>>,
    duration_ms: Mutex<u64>,
    preview_max_edge: u32,
    trim_start_ms: Arc<AtomicU64>,
    trim_end_ms: Arc<AtomicU64>,
    /// Full stream table of the open session (video/audio/subtitle).
    streams: Mutex<Vec<MediaStreamInfo>>,
    /// Owned codec params per stream index for track switching.
    stream_params: Mutex<HashMap<i32, (ffmpeg_next::codec::Parameters, Rational, StreamKind)>>,
    /// Currently selected stream indices (-1 = none/off for subtitles).
    selected_video_idx: Arc<AtomicI64>,
    selected_audio_idx: Arc<AtomicI64>,
    selected_subtitle_idx: Arc<AtomicI64>,
    /// Compressed subtitle packets from the main demuxer.
    subtitle_packet_queue: Arc<PacketQueue>,
    /// Decoded subtitle cues (shared with sidecar sessions).
    subtitle_cues: Arc<Mutex<VecDeque<SubtitleCue>>>,
    /// Current subtitle codec for the embedded worker.
    subtitle_params: Arc<Mutex<Option<(ffmpeg_next::codec::Parameters, Rational, i32)>>>,
    /// Bumped on subtitle selection so the worker reopens its codec.
    subtitle_params_epoch: Arc<AtomicU64>,
    /// User subtitle delay in ms (signed; applied at cue ingest).
    subtitle_delay_ms: Arc<AtomicI64>,
    /// Gates cue delivery in [`MediaPlaybackEngine::poll_subtitle_text`].
    subtitles_enabled: Arc<AtomicBool>,
    /// External (sidecar) subtitle session, if any.
    external_sub_session: Mutex<Option<ExternalSubtitleSession>>,
    /// Container bytes demuxed since open (network + file).
    bytes_read: Arc<AtomicU64>,
    /// Instant of the last successful open (for read-bitrate estimate).
    open_instant: Mutex<Option<Instant>>,
    /// Embedded subtitle worker lifecycle.
    subtitle_running: Arc<AtomicBool>,
    subtitle_thread: Mutex<Option<thread::JoinHandle<()>>>,
    /// §12: set on seek/source replacement/disposal; blocked open/probe/
    /// network reads check it and terminate promptly.
    cancel_flag: Arc<AtomicBool>,
    /// §11: last open probe duration in ms (fast + fallback if retried).
    probe_duration_ms: Arc<AtomicU64>,
    /// §16: reconnects since open.
    reconnect_count: Arc<AtomicU64>,
    /// §16: wall-clock ms of first decoded / presented frames (0 = none yet).
    first_decoded_at_ms: Arc<AtomicU64>,
    first_presented_at_ms: Arc<AtomicU64>,
    /// §6: actual presented frames vs bridge calls.
    presented_frames: Arc<AtomicU64>,
    bridge_calls: Arc<AtomicU64>,
    /// §5: frame-ready signal (decoder notifies, presenter waits).
    frame_ready: Arc<(Mutex<u64>, Condvar)>,
    /// Experimental GPU video enhancement (default Off; device-dependent).
    video_enhance: Mutex<VideoEnhancementRuntime>,
}

/// Demux+decode session for an external (sidecar) subtitle file/URL.
struct ExternalSubtitleSession {
    is_running: Arc<AtomicBool>,
    demux_handle: Option<thread::JoinHandle<()>>,
}

impl ExternalSubtitleSession {
    fn stop(&mut self) {
        self.is_running.store(false, Ordering::SeqCst);
        if let Some(h) = self.demux_handle.take() {
            let _ = h.join();
        }
    }
}

impl MediaPlaybackEngine {
    pub fn new(texture_id: u32, max_queue_size: usize, preview_max_edge: u32) -> Self {
        ensure_ffmpeg_initialized();
        // Backward compat: previewMaxEdge == 0 → 1080. Native (8192)
        // preserves source dimensions; never auto-scale 4K → 1080.
        let preview_max_edge = if preview_max_edge == 0 {
            DEFAULT_PREVIEW_MAX_EDGE
        } else {
            preview_max_edge
        };
        let is_native = preview_max_edge >= NATIVE_PRESERVATION_EDGE;
        runtime_log!(
            "[MediaPlaybackEngine] Initializing texture_id={} max_queue_size={} preview_max_edge={} native={}",
            texture_id,
            max_queue_size,
            preview_max_edge,
            is_native
        );
        let clock = Arc::new(PlaybackClock::new());
        // Byte- and duration-aware budgets (§4): video 16 MiB/5 s, audio
        // 4 MiB/5 s. Count caps are derived but never 2000 unbounded.
        let video_packet_queue = Arc::new(PacketQueue::new_with_budgets(
            max_queue_size.min(512).max(64),
            VIDEO_PACKET_MAX_BYTES,
            VIDEO_PACKET_MAX_DURATION_MS,
        ));
        let audio_packet_queue = Arc::new(PacketQueue::new_with_budgets(
            max_queue_size.min(256).max(32),
            AUDIO_PACKET_MAX_BYTES,
            AUDIO_PACKET_MAX_DURATION_MS,
        ));
        let video_frame_queue = Arc::new(FrameQueue::new(video_frame_queue_capacity(preview_max_edge)));
        // Audio decoded frames stay small (8).
        let audio_frame_queue = Arc::new(FrameQueue::new(max_queue_size.min(8).max(4)));
        let seek_was_playing = Arc::new(AtomicBool::new(false));
        let seek_generation = Arc::new(AtomicU64::new(0));
        // Frame-ready signal: decoder notifies, presenter waits efficiently.
        let frame_ready: Arc<(Mutex<u64>, Condvar)> =
            Arc::new((Mutex::new(0), Condvar::new()));
        video_frame_queue.set_notify(frame_ready.clone());
        audio_frame_queue.set_notify(frame_ready.clone());

        let audio_runtime = AudioRuntime::new(
            audio_packet_queue.clone(),
            audio_frame_queue.clone(),
            clock.clone(),
            seek_was_playing.clone(),
            seek_generation.clone(),
        );
        let video_runtime = VideoRuntime::new(
            video_packet_queue.clone(),
            video_frame_queue.clone(),
            clock.clone(),
            preview_max_edge,
            seek_was_playing.clone(),
            seek_generation.clone(),
        );
        video_runtime.set_audio_clock(audio_runtime.audio_clock_ms.clone());
        let presenter = GpuPresenter::new(texture_id);
        let seek_target_ms = Arc::new(AtomicI64::new(-1));
        let demuxer_active = Arc::new(AtomicBool::new(false));
        let presenter_runtime = PresenterRuntime::new();
        // Wire frame-ready signalling: decoder notifies, presenter waits.
        video_runtime.set_frame_ready(frame_ready.clone());
        presenter_runtime.set_frame_ready(frame_ready.clone());
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
            seek_generation.clone(),
            presenter_runtime.get_display_frame(),
            presenter_runtime.frozen_frame.clone(),
        ));
        seek_controller.set_frame_ready(frame_ready.clone());

        Self {
            clock,
            video_packet_queue,
            audio_packet_queue,
            video_frame_queue,
            audio_frame_queue,
            video_runtime,
            audio_runtime,
            presenter,
            presenter_runtime,
            seek_target_ms,
            seek_was_playing,
            demuxer_active,
            seek_controller,
            seek_generation,
            session: Mutex::new(None),
            duration_ms: Mutex::new(0),
            preview_max_edge,
            trim_start_ms: Arc::new(AtomicU64::new(0)),
            trim_end_ms: Arc::new(AtomicU64::new(u64::MAX)),
            streams: Mutex::new(Vec::new()),
            stream_params: Mutex::new(HashMap::new()),
            selected_video_idx: Arc::new(AtomicI64::new(-1)),
            selected_audio_idx: Arc::new(AtomicI64::new(-1)),
            selected_subtitle_idx: Arc::new(AtomicI64::new(-1)),
            subtitle_packet_queue: Arc::new(PacketQueue::new_with_budgets(
                SUBTITLE_PACKET_MAX_COUNT,
                SUBTITLE_PACKET_MAX_BYTES,
                30_000,
            )),
            subtitle_cues: Arc::new(Mutex::new(VecDeque::new())),
            subtitle_params: Arc::new(Mutex::new(None)),
            subtitle_params_epoch: Arc::new(AtomicU64::new(0)),
            subtitle_delay_ms: Arc::new(AtomicI64::new(0)),
            subtitles_enabled: Arc::new(AtomicBool::new(true)),
            external_sub_session: Mutex::new(None),
            bytes_read: Arc::new(AtomicU64::new(0)),
            open_instant: Mutex::new(None),
            subtitle_running: Arc::new(AtomicBool::new(false)),
            subtitle_thread: Mutex::new(None),
            // §12 interrupt/cancellation tied to generation/disposal.
            cancel_flag: Arc::new(AtomicBool::new(false)),
            // §11 probe timing + §16 expanded counters.
            probe_duration_ms: Arc::new(AtomicU64::new(0)),
            reconnect_count: Arc::new(AtomicU64::new(0)),
            first_decoded_at_ms: Arc::new(AtomicU64::new(0)),
            first_presented_at_ms: Arc::new(AtomicU64::new(0)),
            presented_frames: Arc::new(AtomicU64::new(0)),
            bridge_calls: Arc::new(AtomicU64::new(0)),
            frame_ready,
            video_enhance: Mutex::new(VideoEnhancementRuntime::new()),
        }
    }

    /// Returns true when a newer source/seek/dispose superseded this operation.
    #[frb(ignore)]
    pub fn is_cancelled(&self) -> bool {
        self.cancel_flag.load(Ordering::Relaxed)
    }

    #[frb(ignore)]
    fn begin_open(&self) {
        // New source replaces stale work (§12): stop the old session first
        // (which flags cancellation for stale blocked reads), then clear
        // the flag so the new open proceeds.
        self.stop_demuxer_session();
        self.cancel_flag.store(false, Ordering::Relaxed);
    }

    /// Fast initial probe for seekable file-like sources (§11).
    /// Returns the opened input; retries once with the larger budget when
    /// required metadata (duration/streams/dims) is incomplete.
    fn open_input_with_fast_fallback(
        &self,
        target: &str,
        make_dict: impl Fn(bool) -> ffmpeg_next::Dictionary<'static>,
    ) -> anyhow::Result<ffmpeg_next::format::context::Input> {
        let t0 = Instant::now();
        // Fast probe first.
        let fast_dict = make_dict(true);
        let fast_result = ffmpeg_next::format::input_with_dictionary(target, fast_dict);
        let mut ictx = match fast_result {
            Ok(ctx) => {
                if Self::metadata_complete(&ctx) {
                    let ms = t0.elapsed().as_millis() as u64;
                    self.probe_duration_ms.store(ms, Ordering::Relaxed);
                    runtime_log!("[Probe] fast probe succeeded target={} in {}ms", target, ms);
                    return Ok(ctx);
                }
                runtime_log!("[Probe] fast probe incomplete for target={} → single fallback with larger budget", target);
                ctx
            }
            Err(e) => {
                runtime_log!("[Probe] fast probe failed for target={} ({:?}) → single fallback", target, e);
                // Fall through to the larger probe below.
                let large_dict = make_dict(false);
                let ictx = ffmpeg_next::format::input_with_dictionary(target, large_dict)
                    .map_err(|e2| anyhow::anyhow!("Failed to open '{}': {:?} (fast probe also failed: {:?})", target, e2, e))?;
                let ms = t0.elapsed().as_millis() as u64;
                self.probe_duration_ms.store(ms, Ordering::Relaxed);
                runtime_log!("[Probe] fallback probe succeeded target={} in {}ms", target, ms);
                return Ok(ictx);
            }
        };
        // Fast opened but metadata incomplete → retry once with large budget.
        // Drop the fast context and reopen (single retry, never sacrifice compat).
        drop(ictx);
        if self.is_cancelled() {
            return Err(anyhow::anyhow!("Open cancelled for '{}'", target));
        }
        let large_dict = make_dict(false);
        ictx = ffmpeg_next::format::input_with_dictionary(target, large_dict)
            .map_err(|e| anyhow::anyhow!("Failed to open '{}': {:?}", target, e))?;
        let ms = t0.elapsed().as_millis() as u64;
        self.probe_duration_ms.store(ms, Ordering::Relaxed);
        runtime_log!("[Probe] fallback probe finished target={} in {}ms", target, ms);
        Ok(ictx)
    }

    /// True when the opened context has enough metadata to start decoders.
    fn metadata_complete(ictx: &ffmpeg_next::format::context::Input) -> bool {
        if ictx.streams().count() == 0 {
            return false;
        }
        // Duration known OR at least one video/audio stream with valid params.
        if ictx.duration() > 0 {
            return true;
        }
        for stream in ictx.streams() {
            let medium = stream.parameters().medium();
            if medium == ffmpeg_next::media::Type::Video {
                let (w, h) = video_stream_dims(&stream.parameters());
                if w > 0 && h > 0 {
                    return true;
                }
            } else if medium == ffmpeg_next::media::Type::Audio {
                return true;
            }
        }
        false
    }

    pub fn open_file(&self, path: String) -> anyhow::Result<()> {
        runtime_log!("[MediaPlaybackEngine] Opening custom video file path={}", path);

        self.begin_open();
        if self.is_cancelled() {
            return Err(anyhow::anyhow!("Open cancelled for '{}'", path));
        }

        let ictx = self.open_input_with_fast_fallback(&path, |fast| {
            let lower = path.to_ascii_lowercase();
            let mut dict = ffmpeg_next::Dictionary::new();
            if fast {
                // Fast initial probe for file-like sources (§11).
                dict.set("analyzeduration", "1000000"); // 1 s
                dict.set("probesize", "1000000"); // 1 MB
                // MP4/MOV still need a bit more even on fast path.
                if lower.ends_with(".mov") || lower.ends_with(".mp4") || lower.ends_with(".m4v") {
                    dict.set("analyzeduration", "2000000");
                    dict.set("probesize", "5000000");
                }
            } else if lower.ends_with(".mov") || lower.ends_with(".mp4") || lower.ends_with(".m4v") {
                // Existing larger budget (compat, never sacrificed).
                dict.set("analyzeduration", "5000000");
                dict.set("probesize", "20000000");
            }
            dict
        })?;
        if self.is_cancelled() {
            return Err(anyhow::anyhow!("Open cancelled for '{}'", path));
        }
        self.open_common(path.clone(), ictx)
    }

    /// Open an HTTP/HTTPS URL (streaming, HLS, localhost range servers).
    ///
    /// FFmpeg reads the URL directly — redirects, Range seeks, and HLS
    /// segment fetches all happen inside libavformat, so Dart never fetches
    /// bytes. Headers are forwarded as one `headers` dict entry
    /// (`"Name: Value\r\n"` per FFmpeg http conventions).
    pub fn open_url(&self, url: String, options: NetworkOptions) -> anyhow::Result<()> {
        runtime_log!("[MediaPlaybackEngine] Opening network URL url={}", url);
        ensure_ffmpeg_initialized();

        self.begin_open();
        if self.is_cancelled() {
            return Err(anyhow::anyhow!("Open cancelled for '{}'", url));
        }

        // Capture options for both fast + fallback attempts.
        let headers = options.headers.clone();
        let user_agent = options.user_agent.clone();
        let timeout_ms = options.timeout_ms;
        let reconnect = options.reconnect;
        // NOTE: network opens use a single probe with the larger budget for
        // now. A fast-then-fallback double-open would double localhost
        // connections and break one-shot test servers; the fast path for
        // seekable HTTP is tracked for a follow-up once the test servers
        // handle probe retries (see docs/BENCHMARKS.md).
        let mut dict = ffmpeg_next::Dictionary::new();
        if !headers.is_empty() {
            let mut header_block = String::new();
            let mut keys: Vec<&String> = headers.keys().collect();
            keys.sort();
            for k in keys {
                let v = &headers[k];
                header_block.push_str(&format!("{}: {}\r\n", k.trim(), v.trim()));
            }
            dict.set("headers", &header_block);
        }
        if !user_agent.is_empty() {
            dict.set("user_agent", &user_agent);
        }
        if timeout_ms > 0 {
            dict.set("rw_timeout", &((timeout_ms * 1000).to_string()));
        }
        if reconnect {
            dict.set("reconnect", "1");
            dict.set("reconnect_streamed", "1");
            dict.set("reconnect_delay_max", "5");
        }
        dict.set("protocol_whitelist", "file,http,https,tcp,tls,crypto,hls,key");
        dict.set("analyzeduration", "8000000");
        dict.set("probesize", "20000000");
        if !options.headers.is_empty() {
            runtime_log!(
                "[MediaPlaybackEngine] Network custom headers count={}",
                options.headers.len()
            );
        }
        let t0 = Instant::now();
        let ictx = ffmpeg_next::format::input_with_dictionary(&url, dict)
            .map_err(|e| anyhow::anyhow!("Failed to open URL '{}': {:?}", url, e))?;
        let ms = t0.elapsed().as_millis() as u64;
        self.probe_duration_ms.store(ms, Ordering::Relaxed);
        runtime_log!("[Probe] network probe finished target={} in {}ms", url, ms);
        if self.is_cancelled() {
            return Err(anyhow::anyhow!("Open cancelled for '{}'", url));
        }
        if reconnect {
            self.reconnect_count.fetch_add(1, Ordering::Relaxed);
        }
        self.open_common(url.clone(), ictx)
    }

    /// Shared open path for files and network inputs.
    fn open_common(
        &self,
        display: String,
        mut ictx: ffmpeg_next::format::context::Input,
    ) -> anyhow::Result<()> {
        // A new source replaces any sidecar subtitles from the previous one.
        self.close_external_subtitle();
        let duration_ms = if ictx.duration() >= 0 {
            (ictx.duration() / 1000) as u64
        } else {
            0
        };
        *self.duration_ms.lock() = duration_ms;
        // Reset trim to full duration
        self.trim_start_ms.store(0, Ordering::Relaxed);
        self.trim_end_ms.store(duration_ms, Ordering::Relaxed);
        self.audio_runtime.set_trim_end_ms(duration_ms);
        runtime_log!("[MediaPlaybackEngine] Opened file duration={}ms", duration_ms);

        let video_stream = ictx.streams().best(ffmpeg_next::media::Type::Video);
        let audio_stream = find_best_audio_stream(&ictx);

        // Full stream table (video/audio/subtitle) + owned params for switching.
        let table = build_stream_table(&ictx);
        {
            let mut params = self.stream_params.lock();
            params.clear();
            for info in &table {
                if let Some(stream) = ictx.stream(info.index as usize) {
                    params.insert(
                        info.index,
                        (stream.parameters(), stream.time_base(), info.kind),
                    );
                }
            }
            *self.streams.lock() = table;
        }

        let video_idx = video_stream.as_ref().map(|s| s.index() as i64).unwrap_or(-1);
        let audio_idx = audio_stream
            .as_ref()
            .map(|s| s.index() as i64)
            .unwrap_or(-1);
        // Default subtitle: first default/forced track, else none (Dart opt-in).
        let subtitle_idx = self
            .streams
            .lock()
            .iter()
            .filter(|s| s.kind == StreamKind::Subtitle)
            .find(|s| s.is_default || s.is_forced)
            .map(|s| s.index as i64)
            .unwrap_or(-1);
        self.selected_video_idx.store(video_idx, Ordering::Relaxed);
        self.selected_audio_idx.store(audio_idx, Ordering::Relaxed);
        self.selected_subtitle_idx.store(subtitle_idx, Ordering::Relaxed);

        if let Some(ref s) = video_stream {
            *self.video_runtime.video_params.lock() = Some((s.parameters(), s.time_base()));
        } else {
            *self.video_runtime.video_params.lock() = None;
        }
        if let Some(ref s) = audio_stream {
            *self.audio_runtime.audio_params.lock() = Some((s.parameters(), s.time_base()));
            self.audio_runtime
                .audio_params_epoch
                .fetch_add(1, Ordering::Relaxed);
        } else {
            *self.audio_runtime.audio_params.lock() = None;
        }
        {
            let sub = if subtitle_idx >= 0 {
                self.stream_params
                    .lock()
                    .get(&(subtitle_idx as i32))
                    .map(|(p, tb, _)| (p.clone(), *tb, subtitle_idx as i32))
            } else {
                None
            };
            *self.subtitle_params.lock() = sub;
            self.subtitle_params_epoch.fetch_add(1, Ordering::Relaxed);
        }
        runtime_log!(
            "[MediaPlaybackEngine] Streams selected video={} audio={} subtitle={} source={}",
            video_idx,
            audio_idx,
            subtitle_idx,
            display
        );

        self.demuxer_active.store(true, Ordering::Relaxed);
        self.seek_target_ms.store(-1, Ordering::Release);

        let is_running = Arc::new(AtomicBool::new(true));
        let is_running_demux = is_running.clone();
        let seek_target_ms_demux = self.seek_target_ms.clone();
        let seek_was_playing_demux = self.seek_was_playing.clone();
        
        let video_pq = self.video_packet_queue.clone();
        let audio_pq = self.audio_packet_queue.clone();
        let subtitle_pq = self.subtitle_packet_queue.clone();
        let selected_video = self.selected_video_idx.clone();
        let selected_audio = self.selected_audio_idx.clone();
        let selected_subtitle = self.selected_subtitle_idx.clone();
        let bytes_read = self.bytes_read.clone();

        self.video_packet_queue.flush();
        self.audio_packet_queue.flush();
        self.subtitle_packet_queue.flush();
        self.video_frame_queue.flush_video();
        self.audio_frame_queue.flush();
        self.subtitle_cues.lock().clear();
        self.bytes_read.store(0, Ordering::Relaxed);
        *self.open_instant.lock() = Some(Instant::now());

        let _clock_demux = self.clock.clone();
        let audio_clock_demux = self.audio_runtime.audio_clock_ms.clone();
        let video_fq_demux = self.video_frame_queue.clone();
        let seek_generation_demux = self.seek_generation.clone();
        let trim_start_demux = self.trim_start_ms.clone();
        let trim_end_demux = self.trim_end_ms.clone();

        let demuxer_thread = thread::spawn(move || {
            runtime_log!("[Demuxer] Started demuxer thread");
            let mut video_count = 0u64;
            let mut audio_count = 0u64;
            let mut current_demux_generation = seek_generation_demux.load(Ordering::Relaxed);

            'demux: loop {
                // Check for a pending seek before reading the next packet
                let seek_ms = seek_target_ms_demux.load(Ordering::Acquire);
                if seek_ms >= 0 {
                    seek_target_ms_demux.store(-1, Ordering::Release);
                    let was_playing = seek_was_playing_demux.load(Ordering::Relaxed);
                    current_demux_generation = seek_generation_demux.load(Ordering::Relaxed);
                    runtime_log!("[Demuxer] Executing file seek to {}ms gen={} was_playing={}", seek_ms, current_demux_generation, was_playing);

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
                        let _ = video_pq.push(QueuePacket::Flush(current_demux_generation, seek_ms as u64));
                        let _ = audio_pq.push(QueuePacket::Flush(current_demux_generation, seek_ms as u64));
                        let _ = subtitle_pq.push(QueuePacket::Flush(current_demux_generation, seek_ms as u64));
                    }

                    runtime_log!("[Demuxer] Seek to {}ms initiated, resuming demux", seek_ms);
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
                        let stream_idx_i64 = stream_idx as i64;
                        let v_idx = selected_video.load(Ordering::Relaxed);
                        let a_idx = selected_audio.load(Ordering::Relaxed);
                        let s_idx = selected_subtitle.load(Ordering::Relaxed);
                        let is_video = v_idx >= 0 && stream_idx_i64 == v_idx;
                        let is_audio = a_idx >= 0 && stream_idx_i64 == a_idx;
                        let is_subtitle = s_idx >= 0 && stream_idx_i64 == s_idx;

                        if is_video || is_audio || is_subtitle {
                            bytes_read.fetch_add(packet.size() as u64, Ordering::Relaxed);
                            let pts_ms = packet.pts().map(|pts| {
                                let tb = ictx.stream(stream_idx).map(|s| s.time_base()).unwrap_or(Rational(1, 1000));
                                (pts as f64 * tb.0 as f64 / tb.1 as f64 * 1000.0) as u64
                            }).unwrap_or(0);

                            // Skip packets outside trim range — eliminates wasted decode work
                            // (subtitle packets are also trim-gated so cues stay in range).
                            let t_start = trim_start_demux.load(Ordering::Relaxed);
                            let t_end = trim_end_demux.load(Ordering::Relaxed);
                            if pts_ms < t_start || (t_end < u64::MAX && pts_ms > t_end + 1000) {
                                continue;
                            }

                            let q_pkt = QueuePacket::Real(packet, pts_ms, current_demux_generation);

                            if is_subtitle {
                                let pushed = subtitle_pq.push(q_pkt);
                                if !pushed {
                                    runtime_log!("[Demuxer] Subtitle queue closed — stopping demux");
                                    break 'demux;
                                }
                            } else if is_video {
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
        // §12: cancel blocked open/probe/network reads tied to the old source.
        self.cancel_flag.store(true, Ordering::Relaxed);
        // Wake the frame-ready pump so it observes the generation change.
        {
            let (lock, cvar) = &*self.frame_ready;
            let mut v = lock.lock();
            *v = v.wrapping_add(1);
            cvar.notify_all();
        }
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
        self.cancel_flag.store(false, Ordering::Relaxed);
        self.video_runtime.start();
        self.audio_runtime.start();
        self.clock.start();
        self.start_subtitle_worker();
        self.presenter_runtime.resume();
        self.presenter_runtime.start(
            self.clock.clone(),
            self.video_frame_queue.clone(),
            self.audio_runtime.audio_clock_ms.clone(),
            self.seek_controller.clone(),
        );
        // Auto-seek to trim start if it's not at the beginning
        let trim_start = self.trim_start_ms.load(Ordering::Relaxed);
        if trim_start > 0 {
            runtime_log!("[MediaPlaybackEngine] Auto-seeking to trim_start={}ms", trim_start);
            self.seek_controller.request_seek(trim_start, "trim_start");
        }
    }

    pub fn pause(&self) {
        runtime_log!("[MediaPlaybackEngine] Pausing clock");
        self.presenter_runtime.stop();
        self.clock.pause();
        // Keep the bounded packet/frame queues intact while paused. The
        // demux/decode workers may continue filling them up to their existing
        // small caps, allowing read-ahead without building a large decoded
        // frame cache. Resume then presents from the retained queue.
        runtime_log!("[MediaPlaybackEngine] Paused with bounded read-ahead queues retained");
    }

    /// Lifecycle suspension (§13): park the presentation pump, audio device,
    /// diagnostics cadence and subtitle wakeups; retain the session for resume.
    /// No bridge frame calls are emitted while suspended.
    pub fn suspend(&self) {
        runtime_log!("[MediaPlaybackEngine] Suspending (pump+audio parked)");
        self.presenter_runtime.suspend();
        self.clock.pause();
    }

    /// Resume a suspended session (§13).
    pub fn resume(&self) {
        runtime_log!("[MediaPlaybackEngine] Resuming suspended session");
        self.presenter_runtime.resume();
        // Clock stays paused until Dart calls start(); the pump restarts there.
        let (lock, cvar) = &*self.frame_ready;
        let mut v = lock.lock();
        *v = v.wrapping_add(1);
        cvar.notify_all();
    }

    /// Request cancellation of blocked open/probe/network reads (§12).
    /// Tied to controller/source generation, seek replacement and disposal.
    pub fn request_cancel(&self) {
        self.cancel_flag.store(true, Ordering::Relaxed);
        let (lock, cvar) = &*self.frame_ready;
        let mut v = lock.lock();
        *v = v.wrapping_add(1);
        cvar.notify_all();
    }

    pub fn clear_cancel(&self) {
        self.cancel_flag.store(false, Ordering::Relaxed);
    }

    /// Exact active rendering path (§8). Never claims zero-copy unless the
    /// VT IOSurface adoption path is actually active.
    pub fn rendering_path(&self) -> String {
        let hw = self.video_runtime.hw_decode_active.load(Ordering::Relaxed);
        let label = self.video_runtime.decoder_label.lock().clone();
        if hw {
            #[cfg(any(target_os = "macos", target_os = "ios"))]
            {
                if crate::vt_pixel_buffer::vt_zero_copy_enabled()
                    && (label.contains("videotoolbox") || label.contains("hevc") || label.contains("h264"))
                {
                    return "videotoolbox_iosurface_zero_copy".to_string();
                }
                return "videotoolbox_bgra_copy".to_string();
            }
            #[cfg(target_os = "android")]
            {
                // Surface-output zero-copy is not yet verified on device.
                // Report the bitmap upload path until physical-device
                // diagnostics prove the surface path.
                return "android_bitmap_upload".to_string();
            }
            #[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "android")))]
            {
                return "hw_decode_upload".to_string();
            }
        }
        // Software fallback: BGRA direct where possible, else RGBA.
        #[cfg(any(target_os = "macos", target_os = "ios"))]
        {
            return "software_bgra_upload".to_string();
        }
        #[cfg(not(any(target_os = "macos", target_os = "ios")))]
        {
            return "software_rgba_upload".to_string();
        }
    }

    /// Retained decoded-frame memory in bytes (observable, §3/§16).
    pub fn frame_memory_bytes(&self) -> u64 {
        self.video_frame_queue.frame_memory_bytes() as u64
    }

    /// Compressed packet bytes currently buffered (video/audio).
    pub fn video_queue_bytes(&self) -> u64 {
        self.video_packet_queue.bytes() as u64
    }

    pub fn audio_queue_bytes(&self) -> u64 {
        self.audio_packet_queue.bytes() as u64
    }

    pub fn video_queue_duration_ms(&self) -> u64 {
        self.video_packet_queue.duration_ms()
    }

    pub fn audio_queue_duration_ms(&self) -> u64 {
        self.audio_packet_queue.duration_ms()
    }

    pub fn probe_duration_ms(&self) -> u64 {
        self.probe_duration_ms.load(Ordering::Relaxed)
    }

    pub fn reconnect_count(&self) -> u64 {
        self.reconnect_count.load(Ordering::Relaxed)
    }

    /// Split drop counters (§6): overflow vs catch-up vs decoder.
    /// Empty polls are never counted — only actual discards.
    pub fn queue_overflow_drops(&self) -> u64 {
        self.video_frame_queue.overflow_count()
    }

    pub fn catchup_drops(&self) -> u64 {
        self.video_runtime.catchup_dropped.load(Ordering::Relaxed)
    }

    pub fn stale_drops(&self) -> u64 {
        self.video_runtime.stale_dropped.load(Ordering::Relaxed)
    }

    pub fn set_rate(&self, rate: f64) {
        runtime_log!("[MediaPlaybackEngine] Setting playback rate to {}", rate);
        self.clock.set_rate(rate);
    }

    pub fn set_muted(&self, muted: bool) {
        self.audio_runtime.set_muted(muted);
    }

    /// Mute only embedded source audio during preview (overlay BGM keeps playing).
    pub fn set_source_muted(&self, muted: bool) {
        self.audio_runtime.set_source_muted(muted);
    }

    /// Set the trim range in ms. Packets outside this range are skipped by
    /// the demuxer, and playback auto-pauses when reaching `end_ms`.
    pub fn set_trim_range(&self, start_ms: u64, end_ms: u64) {
        let clamped_end = end_ms.min(self.get_duration_ms());
        self.trim_start_ms.store(start_ms, Ordering::Relaxed);
        self.trim_end_ms.store(clamped_end, Ordering::Relaxed);
        self.audio_runtime.set_trim_end_ms(clamped_end);
        // Clear stale trim-end flag (e.g. after trimming a range that was past the old end)
        self.audio_runtime.clear_trim_end_reached();
        runtime_log!(
            "[MediaPlaybackEngine] Trim range set: {}..{}ms",
            start_ms,
            clamped_end
        );
    }

    pub fn get_trim_start_ms(&self) -> u64 {
        self.trim_start_ms.load(Ordering::Relaxed)
    }

    pub fn get_trim_end_ms(&self) -> u64 {
        self.trim_end_ms.load(Ordering::Relaxed)
    }

    // ── Overlay audio track management ──

    /// Add an overlay audio track that will be mixed into playback in real-time.
    /// Returns the overlay ID (u64::MAX on error).
    pub fn add_overlay_audio(
        &self,
        path: String,
        volume: f32,
        timeline_start_ms: u64,
        duration_ms: u64,
        source_start_ms: u64,
    ) -> u64 {
        self.audio_runtime.add_overlay(
            path,
            volume,
            timeline_start_ms,
            duration_ms,
            source_start_ms,
        )
    }

    /// Remove an overlay audio track by ID.
    pub fn remove_overlay_audio(&self, id: u64) {
        self.audio_runtime.remove_overlay(id);
    }

    /// Set volume for an overlay audio track (0.0 .. 1.0).
    pub fn set_overlay_volume(&self, id: u64, volume: f32) {
        self.audio_runtime.set_overlay_volume(id, volume);
    }

    pub fn stop(&self) {
        runtime_log!("[MediaPlaybackEngine] Stopping runtimes (ordered release)");
        // Ordered deterministic release (§15): stop frame requests, cancel
        // blocked FFmpeg ops, stop workers, stop audio, release frames,
        // release texture/presentation, finish disposal.
        self.request_cancel();
        self.presenter_runtime.stop();
        self.clock.pause();
        self.stop_demuxer_session();
        self.audio_runtime.stop_all_overlays();
        self.video_runtime.stop();
        self.audio_runtime.stop();
        self.stop_subtitle_worker();
        self.close_external_subtitle();
        self.video_frame_queue.flush_video();
        self.audio_frame_queue.flush();
        // New source (or explicit stop): give pooled GPU enhancement surfaces
        // back and re-plan from scratch. The selected mode is preserved.
        self.video_enhance.lock().on_source_change();
    }

    pub fn seek(&self, time_ms: u64) {
        runtime_log!("[MediaPlaybackEngine] Seeking to {}ms", time_ms);
        // Clear trim-end flag so seeking backward past trim end works
        self.audio_runtime.clear_trim_end_reached();
        // Flush overlay audio queues so they restart from the new position
        self.audio_runtime.flush_overlay_queues();
        // The next decoded PTS is discontinuous, so the enhancement deadline
        // tracker must not treat the jump as a frame interval.
        self.video_enhance.lock().on_seek();
        self.seek_controller.request_seek(time_ms, "ui_seek");
    }

    // ── GPU video enhancement (experimental) ──────────────────────────

    /// What this device can do. Safe to call before any media is open.
    pub fn video_enhancement_capabilities(&self) -> VideoEnhancementCapabilities {
        let caps = self.video_enhance.lock().capabilities().clone();
        VideoEnhancementCapabilities {
            supported: caps.supported,
            backend: caps.backend,
            modes: caps
                .modes
                .iter()
                .map(|m| VideoEnhancementMode::from_internal(*m))
                .collect(),
            max_output_edge: caps.max_output_edge,
            reason: caps.reason,
        }
    }

    /// Current enhancement state for diagnostics.
    pub fn video_enhancement_status(&self) -> VideoEnhancementStatus {
        let status = self.video_enhance.lock().status();
        VideoEnhancementStatus {
            supported: status.supported,
            requested_mode: VideoEnhancementMode::from_internal(status.requested_mode),
            active_mode: VideoEnhancementMode::from_internal(status.active_mode),
            backend: status.backend,
            path: status.path,
            scaler: status.scaler,
            input_width: status.input_width,
            input_height: status.input_height,
            output_width: status.output_width,
            output_height: status.output_height,
            last_frame_ms: status.last_frame_ms,
            average_frame_ms: status.average_frame_ms,
            deadline_ms: status.deadline_ms,
            deadline_misses: status.deadline_misses,
            hard_deadline_misses: status.hard_deadline_misses,
            enhanced_frames: status.enhanced_frames,
            bypassed_frames: status.bypassed_frames,
            failed_frames: status.failed_frames,
            passes: status.passes,
            fallback_reason: status.fallback_reason,
            bypass_reason: status.bypass_reason,
        }
    }

    /// Select an enhancement mode. Takes effect on the next presented frame:
    /// no media reopen, no decoder restart, no queue flush.
    ///
    /// Returns false when the device cannot run the requested mode (playback
    /// is unaffected — the normal render path stays in place).
    pub fn set_video_enhancement_mode(&self, mode: VideoEnhancementMode) -> bool {
        self.video_enhance.lock().set_mode(mode.to_internal())
    }

    /// Display box in device pixels, used for the resolution-aware target.
    /// `(0, 0)` clears the hint.
    pub fn set_video_enhancement_viewport(&self, width: u32, height: u32) {
        self.video_enhance.lock().set_viewport(width, height);
    }

    /// Hard ceiling for the enhanced output longest edge (`0` = mode default).
    pub fn set_video_enhancement_max_output_edge(&self, edge: u32) {
        self.video_enhance.lock().set_max_output_edge(edge);
    }

    /// Run the enhancement stage for one decoded frame.
    ///
    /// Returns a handoff for the enhanced surface, or `None` to present the
    /// decoded frame untouched. **Ownership:** on success the `+1` retain on
    /// `pixel_buffer_ptr` is consumed; on `None` the caller still owns it and
    /// must present that frame.
    pub fn enhance_pixel_buffer(
        &self,
        pixel_buffer_ptr: u64,
        width: u32,
        height: u32,
        pts_ms: u64,
    ) -> Option<PixelBufferHandoff> {
        let (enhanced, size) = self
            .video_enhance
            .lock()
            .enhance(pixel_buffer_ptr, width, height, pts_ms as i64)?;
        Some(PixelBufferHandoff {
            pts_ms,
            width: size.width,
            height: size.height,
            pixel_buffer_ptr: enhanced,
            seek_generation: self.seek_generation.load(Ordering::Relaxed),
        })
    }

    // ── Stream enumeration & track switching ──────────────────────────

    /// All streams discovered at open time (video/audio/subtitle).
    pub fn list_streams(&self) -> Vec<MediaStreamInfo> {
        self.streams.lock().clone()
    }

    /// Switch the audio track during playback.
    ///
    /// Updates the decoder params, bumps the decoder epoch (the audio
    /// thread reopens its codec), and re-seeks to the current position so
    /// queues and clocks resync through the normal Flush machinery.
    pub fn select_audio_stream(&self, index: i32) -> anyhow::Result<()> {
        let (params, tb) = {
            let table = self.stream_params.lock();
            match table.get(&index) {
                Some((p, tb, StreamKind::Audio)) => (p.clone(), *tb),
                Some(_) => {
                    return Err(anyhow::anyhow!("Stream {} is not an audio stream", index))
                }
                None => return Err(anyhow::anyhow!("Unknown stream index {}", index)),
            }
        };
        *self.audio_runtime.audio_params.lock() = Some((params, tb));
        self.audio_runtime
            .audio_params_epoch
            .fetch_add(1, Ordering::Relaxed);
        self.selected_audio_idx.store(index as i64, Ordering::Relaxed);
        let pos = self.get_media_time_ms();
        runtime_log!(
            "[MediaPlaybackEngine] Audio track switched index={} at {}ms",
            index,
            pos
        );
        self.seek(pos);
        Ok(())
    }

    /// Switch the video track during playback (params + re-seek; the video
    /// thread reopens its pipelines on the Flush sentinel).
    pub fn select_video_stream(&self, index: i32) -> anyhow::Result<()> {
        let (params, tb) = {
            let table = self.stream_params.lock();
            match table.get(&index) {
                Some((p, tb, StreamKind::Video)) => (p.clone(), *tb),
                Some(_) => {
                    return Err(anyhow::anyhow!("Stream {} is not a video stream", index))
                }
                None => return Err(anyhow::anyhow!("Unknown stream index {}", index)),
            }
        };
        *self.video_runtime.video_params.lock() = Some((params, tb));
        self.selected_video_idx.store(index as i64, Ordering::Relaxed);
        let pos = self.get_media_time_ms();
        runtime_log!(
            "[MediaPlaybackEngine] Video track switched index={} at {}ms",
            index,
            pos
        );
        self.seek(pos);
        Ok(())
    }

    /// Select the embedded subtitle track (`-1` disables). Clears queued
    /// cues and re-seeks so the demuxer forwards the new stream.
    pub fn select_subtitle_stream(&self, index: i32) -> anyhow::Result<()> {
        if index >= 0 {
            let (params, tb) = {
                let table = self.stream_params.lock();
                match table.get(&index) {
                    Some((p, tb, StreamKind::Subtitle)) => (p.clone(), *tb),
                    Some(_) => {
                        return Err(anyhow::anyhow!(
                            "Stream {} is not a subtitle stream",
                            index
                        ))
                    }
                    None => {
                        return Err(anyhow::anyhow!("Unknown stream index {}", index))
                    }
                }
            };
            *self.subtitle_params.lock() = Some((params, tb, index));
        } else {
            *self.subtitle_params.lock() = None;
        }
        self.subtitle_params_epoch.fetch_add(1, Ordering::Relaxed);
        self.selected_subtitle_idx
            .store(index as i64, Ordering::Relaxed);
        self.subtitle_cues.lock().clear();
        let pos = self.get_media_time_ms();
        runtime_log!(
            "[MediaPlaybackEngine] Subtitle track selected index={} at {}ms",
            index,
            pos
        );
        self.seek(pos);
        Ok(())
    }

    // ── Subtitles ─────────────────────────────────────────────────────

    /// User subtitle delay in ms (signed; applied when cues are ingested).
    pub fn set_subtitle_delay_ms(&self, delay_ms: i64) {
        self.subtitle_delay_ms.store(delay_ms, Ordering::Relaxed);
        runtime_log!("[MediaPlaybackEngine] Subtitle delay={}ms", delay_ms);
    }

    pub fn get_subtitle_delay_ms(&self) -> i64 {
        self.subtitle_delay_ms.load(Ordering::Relaxed)
    }

    /// Enable/disable cue delivery (decoding continues; polling returns None).
    pub fn set_subtitles_enabled(&self, enabled: bool) {
        self.subtitles_enabled.store(enabled, Ordering::Relaxed);
        runtime_log!("[MediaPlaybackEngine] Subtitles enabled={}", enabled);
    }

    /// Active cue text at `time_ms` (lines joined with `\n`), or None.
    ///
    /// Prunes cues long past their end time to bound memory.
    pub fn poll_subtitle_text(&self, time_ms: u64) -> Option<String> {
        if !self.subtitles_enabled.load(Ordering::Relaxed) {
            return None;
        }
        let has_embedded = self.selected_subtitle_idx.load(Ordering::Relaxed) >= 0;
        let has_external = self.external_sub_session.lock().is_some();
        if !has_embedded && !has_external {
            return None;
        }
        let mut cues = self.subtitle_cues.lock();
        while cues
            .front()
            .map(|c| c.end_ms.saturating_add(60_000) < time_ms)
            .unwrap_or(false)
        {
            cues.pop_front();
        }
        let active: Vec<String> = cues
            .iter()
            .filter(|c| c.start_ms <= time_ms && time_ms < c.end_ms)
            .map(|c| c.text.clone())
            .collect();
        if active.is_empty() {
            None
        } else {
            Some(active.join("\n"))
        }
    }

    /// Open an external (sidecar) subtitle file or URL.
    ///
    /// Demuxed + decoded on its own thread into the shared cue queue, so it
    /// mixes with (or replaces) embedded cues. Times are used as-is plus
    /// [`MediaPlaybackEngine::set_subtitle_delay_ms`].
    pub fn open_external_subtitle(&self, path_or_url: String) -> anyhow::Result<()> {
        self.close_external_subtitle();
        let mut dict = ffmpeg_next::Dictionary::new();
        dict.set("rw_timeout", "10000000");
        let mut ictx =
            ffmpeg_next::format::input_with_dictionary(&path_or_url, dict).map_err(|e| {
                anyhow::anyhow!(
                    "Failed to open external subtitle '{}': {:?}",
                    path_or_url,
                    e
                )
            })?;
        let sub_stream = ictx
            .streams()
            .best(ffmpeg_next::media::Type::Subtitle)
            .ok_or_else(|| {
                anyhow::anyhow!("No subtitle stream in '{}'", path_or_url)
            })?;
        let sub_idx = sub_stream.index();
        let (params, tb) = (sub_stream.parameters(), sub_stream.time_base());
        let mut decoder_ctx = CodecContext::from_parameters(params.clone())
            .map_err(|e| anyhow::anyhow!("Subtitle codec params error: {:?}", e))?
            .decoder();
        // libavcodec derives `end_display_time` from the packet duration only
        // when the codec context carries a packet time base
        // (libavcodec/decode.c). The generic text decoders (srt/webvtt/…)
        // leave the display times at 0, so without this every sidecar cue is
        // dropped as degenerate (end == start) and the feature stays silent.
        decoder_ctx.set_packet_time_base(tb);
        let mut decoder = decoder_ctx
            .subtitle()
            .map_err(|e| anyhow::anyhow!("Cannot open subtitle decoder: {:?}", e))?;
        runtime_log!(
            "[MediaPlaybackEngine] External subtitle opened source={} stream={}",
            path_or_url,
            sub_idx
        );

        let is_running = Arc::new(AtomicBool::new(true));
        let is_running_thread = is_running.clone();
        let cues = self.subtitle_cues.clone();
        let delay = self.subtitle_delay_ms.clone();
        let handle = thread::spawn(move || {
            loop {
                if !is_running_thread.load(Ordering::SeqCst) {
                    break;
                }
                let mut packet = ffmpeg_next::Packet::empty();
                match packet.read(&mut ictx) {
                    Ok(()) => {
                        if packet.stream() != sub_idx {
                            continue;
                        }
                        let pts_ms = packet.pts().map(|pts| {
                            (pts as f64 * tb.0 as f64 / tb.1 as f64 * 1000.0) as u64
                        }).unwrap_or(0);
                        let mut sub = ffmpeg_next::Subtitle::new();
                        match decoder.decode(&packet, &mut sub) {
                            Ok(true) => {
                                let (text, rel_start, rel_end) =
                                    take_subtitle(&mut sub);
                                if text.is_empty() {
                                    continue;
                                }
                                let d = delay.load(Ordering::Relaxed);
                                let start = pts_ms
                                    .saturating_add(rel_start)
                                    .saturating_add_signed(d);
                                let end = pts_ms
                                    .saturating_add(rel_end)
                                    .saturating_add_signed(d);
                                if end > start {
                                    let mut q = cues.lock();
                                    q.push_back(SubtitleCue {
                                        start_ms: start,
                                        end_ms: end,
                                        text,
                                    });
                                    while q.len() > SUBTITLE_CUE_CAP {
                                        q.pop_front();
                                    }
                                } else {
                                    runtime_log!(
                                        "[MediaPlaybackEngine] External subtitle cue dropped (no end time: {}..{}ms)",
                                        start,
                                        end
                                    );
                                }
                            }
                            _ => {
                                // Nothing decoded: still release the struct.
                                let _ = take_subtitle(&mut sub);
                            }
                        }
                    }
                    Err(ffmpeg_next::Error::Eof) => break,
                    Err(_) => break,
                }
            }
            runtime_log!("[MediaPlaybackEngine] External subtitle thread finished");
        });
        *self.external_sub_session.lock() = Some(ExternalSubtitleSession {
            is_running,
            demux_handle: Some(handle),
        });
        Ok(())
    }

    /// Stop and drop the external subtitle session (cues already ingested stay).
    pub fn close_external_subtitle(&self) {
        if let Some(mut session) = self.external_sub_session.lock().take() {
            session.stop();
            runtime_log!("[MediaPlaybackEngine] External subtitle closed");
        }
    }

    /// Start the embedded subtitle decoder worker (idempotent).
    fn start_subtitle_worker(&self) {
        if self.subtitle_running.swap(true, Ordering::SeqCst) {
            return;
        }
        let packet_queue = self.subtitle_packet_queue.clone();
        let cues = self.subtitle_cues.clone();
        let params = self.subtitle_params.clone();
        let epoch = self.subtitle_params_epoch.clone();
        let delay = self.subtitle_delay_ms.clone();
        let seek_generation = self.seek_generation.clone();
        let is_running = self.subtitle_running.clone();
        let handle = thread::spawn(move || {
            runtime_log!("[SubtitleDecoder] Started subtitle decoder thread");
            let mut decoder: Option<ffmpeg_next::codec::decoder::Subtitle> = None;
            let mut decoder_tb = Rational(1, 1000);
            let mut local_epoch = epoch.load(Ordering::Relaxed).wrapping_sub(1);
            let mut current_gen = seek_generation.load(Ordering::Relaxed);
            while is_running.load(Ordering::SeqCst) {
                let ep = epoch.load(Ordering::Relaxed);
                if ep != local_epoch {
                    local_epoch = ep;
                    decoder = None;
                    if let Some((p, tb, idx)) = params.lock().clone() {
                        match CodecContext::from_parameters(p.clone())
                            .map_err(|e| format!("{:?}", e))
                            .and_then(|ctx| {
                                // Same packet-time-base requirement as the
                                // sidecar path: text decoders (mov_text,
                                // subrip) leave the display times at 0 and
                                // libavcodec fills `end_display_time` from the
                                // packet duration only when it is set.
                                let mut dec = ctx.decoder();
                                dec.set_packet_time_base(tb);
                                dec.subtitle().map_err(|e| format!("{:?}", e))
                            })
                        {
                            Ok(dec) => {
                                decoder_tb = tb;
                                decoder = Some(dec);
                                runtime_log!(
                                    "[SubtitleDecoder] Opened subtitle decoder stream={}",
                                    idx
                                );
                            }
                            Err(e) => {
                                runtime_log!(
                                    "[SubtitleDecoder] Cannot open subtitle decoder: {}",
                                    e
                                );
                            }
                        }
                    }
                }
                let queue_packet = match packet_queue.pop() {
                    Some(q) => q,
                    // Queue closed → worker exits (see stop_subtitle_worker).
                    None => break,
                };
                match queue_packet {
                    QueuePacket::Flush(gen, _target_ms) => {
                        current_gen = current_gen.max(gen);
                        cues.lock().clear();
                        if let Some(dec) = decoder.as_mut() {
                            unsafe {
                                ffmpeg_next::ffi::avcodec_flush_buffers(dec.as_mut_ptr());
                            }
                        }
                    }
                    QueuePacket::Real(pkt, pts_ms, gen) => {
                        if gen < current_gen {
                            continue;
                        }
                        let Some(dec) = decoder.as_mut() else {
                            continue;
                        };
                        let mut sub = ffmpeg_next::Subtitle::new();
                        let got = dec.decode(&pkt, &mut sub).unwrap_or(false);
                        let (decoded, rel_start, rel_end) = take_subtitle(&mut sub);
                        let text = if got { decoded } else { String::new() };
                        if text.is_empty() {
                            continue;
                        }
                        let d = delay.load(Ordering::Relaxed);
                        let start = pts_ms
                            .saturating_add(rel_start)
                            .saturating_add_signed(d);
                        let end =
                            pts_ms.saturating_add(rel_end).saturating_add_signed(d);
                        if end > start {
                            let mut q = cues.lock();
                            q.push_back(SubtitleCue {
                                start_ms: start,
                                end_ms: end,
                                text,
                            });
                            while q.len() > SUBTITLE_CUE_CAP {
                                q.pop_front();
                            }
                        }
                        let _ = decoder_tb;
                    }
                    QueuePacket::Simulated(_) => {}
                }
            }
            runtime_log!("[SubtitleDecoder] Subtitle decoder thread exited");
        });
        *self.subtitle_thread.lock() = Some(handle);
    }

    /// Stop the embedded subtitle decoder worker.
    fn stop_subtitle_worker(&self) {
        if !self.subtitle_running.swap(false, Ordering::SeqCst) {
            return;
        }
        self.subtitle_packet_queue.close();
        if let Some(handle) = self.subtitle_thread.lock().take() {
            let _ = handle.join();
        }
    }

    // ── Master volume ─────────────────────────────────────────────────

    /// Master output gain 0.0..=1.0 (source + overlays) in the cpal mixer.
    pub fn set_volume(&self, volume: f32) {
        self.audio_runtime.set_volume(volume);
    }

    pub fn get_volume(&self) -> f32 {
        self.audio_runtime.get_volume()
    }

    pub fn push_video_packet(&self, packet: MediaPacket) -> bool {
        self.video_packet_queue.push(QueuePacket::Simulated(packet))
    }

    pub fn push_audio_packet(&self, packet: MediaPacket) -> bool {
        self.audio_packet_queue.push(QueuePacket::Simulated(packet))
    }

    /// Returns the frame selected by [`PresenterRuntime`] (frame-ready pump),
    /// not the raw decode queue. Counts bridge calls vs presented frames
    /// separately (§6): empty polls return None and are never drops.
    pub fn take_video_frame(&self) -> Option<MediaVideoFrame> {
        // Every call is a bridge presentation request (observable).
        self.bridge_calls.fetch_add(1, Ordering::Relaxed);
        let current_gen = self.seek_generation.load(Ordering::Relaxed);

        let mut result: Option<MediaVideoFrame> = None;
        if let Some(frame) = self.presenter_runtime.take_display_frame() {
            if frame.seek_generation >= current_gen {
                self.presenter_runtime.clear_frozen_frame();
                result = Some(frame);
            } else {
                runtime_log!(
                    "[MediaPlaybackEngine] Discarding stale display frame (gen={}, current={})",
                    frame.seek_generation,
                    current_gen
                );
                self.video_runtime.stale_dropped.fetch_add(1, Ordering::Relaxed);
            }
        }

        if result.is_none() {
            let state = self.clock.get_state();
            if state == PlaybackState::Seeking {
                if let Some(frame) = self.presenter_runtime.get_frozen_frame() {
                    result = Some(frame);
                }
            }

            if result.is_none()
                && (state == PlaybackState::Paused || state == PlaybackState::Seeking)
            {
                if let Some(frame) = self.video_frame_queue.dequeue_best_for_time(self.get_media_time_ms()) {
                    if frame.seek_generation >= current_gen {
                        self.presenter_runtime.clear_frozen_frame();
                        result = Some(frame);
                    } else {
                        runtime_log!(
                            "[MediaPlaybackEngine] Discarding stale dequeue frame (gen={}, current={})",
                            frame.seek_generation,
                            current_gen
                        );
                        self.video_runtime.stale_dropped.fetch_add(1, Ordering::Relaxed);
                    }
                }
            }
        }

        if let Some(ref f) = result {
            // Actual presented frame (never bridge-call count).
            self.presented_frames.fetch_add(1, Ordering::Relaxed);
            let now_ms = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_millis() as u64)
                .unwrap_or(0);
            if self.first_presented_at_ms.load(Ordering::Relaxed) == 0 {
                self.first_presented_at_ms.store(now_ms, Ordering::Relaxed);
            }
            if self.first_decoded_at_ms.load(Ordering::Relaxed) == 0 {
                self.first_decoded_at_ms.store(now_ms, Ordering::Relaxed);
            }
            let _ = f.pts_ms;
        }
        // None = empty poll: not a drop (§6).
        result
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
    /// [`PlaybackClock`] is the single presentation clock. The audio callback
    /// continuously synchronizes it while audio is available, while its
    /// monotonic fallback keeps video and the UI moving if audio setup or a
    /// callback fails. Reading `audio_clock_ms` directly here would otherwise
    /// freeze a video-only session at its last audio timestamp.
    pub fn get_media_time_ms(&self) -> u64 {
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
        if self.audio_runtime.is_trim_end_reached() {
            return PlaybackState::Ended;
        }
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

    /// Single-call diagnostics snapshot — replaces 11 individual FRB bridge
    /// calls with one, reducing per-tick overhead from ~22 calls/s to ~2.
    pub fn get_diagnostics(&self) -> DiagnosticsSnapshot {
        let audio_ms = self.audio_runtime.audio_clock_ms.load(Ordering::Relaxed);
        let video_pts = self.video_frame_queue.latest_pts();
        let presented = self.clock.get_last_presented_pts_ms();
        let bytes = self.bytes_read.load(Ordering::Relaxed);
        let elapsed_ms = self
            .open_instant
            .lock()
            .map(|t| t.elapsed().as_millis() as u64)
            .unwrap_or(0);
        // Demuxed-bytes read bitrate (container bytes, not socket bytes).
        let bitrate = if elapsed_ms > 500 {
            bytes.saturating_mul(8000) / elapsed_ms
        } else {
            0
        };
        DiagnosticsSnapshot {
            state: self.get_playback_state(),
            media_time_ms: self.get_media_time_ms(),
            audio_clock_ms: audio_ms,
            wall_clock_ms: self.clock.get_media_time_ms(),
            latest_decoded_pts_ms: video_pts,
            presented_pts_ms: presented,
            av_drift_ms: audio_ms.saturating_sub(video_pts),
            video_packets_in_queue: self.video_packet_queue.len() as u64,
            audio_packets_in_queue: self.audio_packet_queue.len() as u64,
            video_frames_in_queue: self.video_frame_queue.len() as u64,
            audio_frames_in_queue: self.audio_frame_queue.len() as u64,
            bytes_read: bytes,
            read_bitrate_bps: bitrate,
            buffered_duration_ms: video_pts.saturating_sub(presented),
            dropped_video_frames: self
                .video_runtime
                .stale_dropped
                .load(Ordering::Relaxed)
                .saturating_add(
                    self.video_runtime.catchup_dropped.load(Ordering::Relaxed),
                ),
            active_video_decoder: self.video_runtime.decoder_label.lock().clone(),
            hw_decode_active: self.video_runtime.hw_decode_active.load(Ordering::Relaxed),
            subtitle_cues_pending: self.subtitle_cues.lock().len() as u64,
            selected_video_index: self.selected_video_idx.load(Ordering::Relaxed) as i32,
            selected_audio_index: self.selected_audio_idx.load(Ordering::Relaxed) as i32,
            selected_subtitle_index: self.selected_subtitle_idx.load(Ordering::Relaxed) as i32,
        }
    }
}

/// All playback diagnostics in one struct — returned by [`MediaPlaybackEngine::get_diagnostics`].
#[derive(Debug, Clone)]
#[frb]
pub struct DiagnosticsSnapshot {
    pub state: PlaybackState,
    pub media_time_ms: u64,
    pub audio_clock_ms: u64,
    pub wall_clock_ms: u64,
    pub latest_decoded_pts_ms: u64,
    pub presented_pts_ms: u64,
    pub av_drift_ms: u64,
    pub video_packets_in_queue: u64,
    pub audio_packets_in_queue: u64,
    pub video_frames_in_queue: u64,
    pub audio_frames_in_queue: u64,
    /// Container bytes demuxed since open.
    pub bytes_read: u64,
    /// Demuxed-bytes read bitrate estimate (bits/s, 0 until 500 ms elapsed).
    pub read_bitrate_bps: u64,
    /// Decoded-ahead-of-presentation buffer (latest decoded − presented).
    pub buffered_duration_ms: u64,
    /// Pre-decode video drops (stale generation + catch-up policy).
    pub dropped_video_frames: u64,
    /// e.g. `hevc-videotoolbox`, `h264-software`, `none` before first open.
    pub active_video_decoder: String,
    /// True when the active video pipeline is hardware decode.
    pub hw_decode_active: bool,
    /// Cues currently held for polling.
    pub subtitle_cues_pending: u64,
    /// Selected stream indices (−1 = none/off).
    pub selected_video_index: i32,
    pub selected_audio_index: i32,
    pub selected_subtitle_index: i32,
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

        clock.enter_rebuffering();
        assert_eq!(clock.get_state(), PlaybackState::Rebuffering);
        let frozen = clock.get_media_time_ms();
        thread::sleep(Duration::from_millis(15));
        assert_eq!(frozen, clock.get_media_time_ms());
        clock.resume_from_rebuffering();
        assert_eq!(clock.get_state(), PlaybackState::Playing);

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
    fn media_time_advances_when_audio_clock_stalls() {
        let engine = MediaPlaybackEngine::new(0, 64, 1080);
        engine.clock.start();
        engine.clock.sync_from_audio_ms(100);
        // This is the failure mode for an audio stream whose decoder/device
        // setup failed after a seek: it still has a last timestamp but emits
        // no further callback updates.
        engine
            .audio_runtime
            .is_running
            .store(true, Ordering::Relaxed);
        engine
            .audio_runtime
            .audio_clock_ms
            .store(100, Ordering::Relaxed);

        thread::sleep(Duration::from_millis(15));
        assert!(engine.get_media_time_ms() > 100);
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
            seek_generation: 0,
        };
        let f2 = MediaVideoFrame {
            pts_ms: 200,
            width: 10,
            height: 10,
            pixels: vec![0],
            pixel_buffer_ptr: 0,
            seek_generation: 0,
        };
        let f3 = MediaVideoFrame {
            pts_ms: 300,
            width: 10,
            height: 10,
            pixels: vec![0],
            pixel_buffer_ptr: 0,
            seek_generation: 0,
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
                seek_generation: 0,
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

    #[test]
    fn test_strip_ass_overrides() {
        assert_eq!(
            strip_ass_overrides("{\\an8}Hello\\NWorld"),
            "Hello\nWorld"
        );
        assert_eq!(strip_ass_overrides("plain"), "plain");
        assert_eq!(strip_ass_overrides("{\\pos(1,2)}A{\\i1}B"), "AB");
    }

    #[test]
    fn test_ass_rect_text_drops_dialogue_fields() {
        // Text decoders (srt/vtt sidecars) emit the dialogue payload and the
        // caption must be the last field only — commas inside it preserved.
        assert_eq!(
            strip_ass_overrides(ass_rect_text("0,0,Default,,0,0,0,,Hello sidecar")),
            "Hello sidecar"
        );
        assert_eq!(
            strip_ass_overrides(ass_rect_text(
                "12,0,Default,,0,0,0,,Hello, world"
            )),
            "Hello, world"
        );
        // Matroska prefixes the payload with "Dialogue:".
        assert_eq!(
            strip_ass_overrides(ass_rect_text(
                "Dialogue: 0,0,Default,,0,0,0,,{\\an8}Hi\\Nthere"
            )),
            "Hi\nthere"
        );
        // Raw ASS event text (standalone .ass) passes through untouched.
        assert_eq!(
            strip_ass_overrides(ass_rect_text("{\\i1}plain, text")),
            "plain, text"
        );
    }

    #[test]
    fn test_empty_subtitle_has_no_text() {
        let sub = ffmpeg_next::Subtitle::new();
        assert_eq!(subtitle_text(&sub), "");
    }

    #[test]
    fn test_network_options_default() {
        let opts = NetworkOptions::default();
        assert!(opts.headers.is_empty());
        assert!(opts.user_agent.is_empty());
        assert!(!opts.reconnect);
    }

    #[test]
    fn test_hw_device_name_nonempty() {
        assert!(!crate::vt_hw_decode::hw_device_name().is_empty());
    }

    // ---- §20 production coverage (native, budgets, frame-ready, drops) ----

    #[test]
    fn test_video_frame_queue_cap_is_small() {
        // HW ~3, never 32/64. All edges map to the small cap.
        assert_eq!(video_frame_queue_capacity(720), 3);
        assert_eq!(video_frame_queue_capacity(1080), 3);
        assert_eq!(video_frame_queue_capacity(8192), 3);
        assert_eq!(VIDEO_FRAME_QUEUE_CAP_HW, 3);
        assert_eq!(VIDEO_FRAME_QUEUE_CAP_SW, 2);
    }

    #[test]
    fn test_packet_budgets_match_spec() {
        assert_eq!(VIDEO_PACKET_MAX_BYTES, 16 * 1024 * 1024);
        assert_eq!(VIDEO_PACKET_MAX_DURATION_MS, 5000);
        assert_eq!(AUDIO_PACKET_MAX_BYTES, 4 * 1024 * 1024);
        assert_eq!(AUDIO_PACKET_MAX_DURATION_MS, 5000);
        assert!(SUBTITLE_PACKET_MAX_BYTES <= 256 * 1024);
    }

    #[test]
    fn test_packet_queue_tracks_bytes_and_duration() {
        let q = PacketQueue::new_with_budgets(512, 16 * 1024 * 1024, 5000);
        assert_eq!(q.bytes(), 0);
        assert_eq!(q.duration_ms(), 0);
        let p1 = MediaPacket {
            pts_ms: 1000,
            dts_ms: 1000,
            stream_index: 0,
            is_keyframe: true,
            data: vec![0u8; 1024],
        };
        let p2 = MediaPacket {
            pts_ms: 3000,
            dts_ms: 3000,
            stream_index: 0,
            is_keyframe: false,
            data: vec![0u8; 2048],
        };
        assert!(q.push(QueuePacket::Simulated(p1)));
        assert!(q.push(QueuePacket::Simulated(p2)));
        assert_eq!(q.bytes(), 3072);
        assert_eq!(q.duration_ms(), 2000);
        let _ = q.try_pop();
        // After popping one, bytes drop and span recomputes (single left → 0).
        assert_eq!(q.bytes(), 2048);
    }

    #[test]
    fn test_frame_queue_overflow_counted_empty_poll_not_a_drop() {
        let q: FrameQueue<MediaVideoFrame> = FrameQueue::new(2);
        assert_eq!(q.overflow_count(), 0);
        // Empty poll returns None and never counts as a drop.
        assert!(q.dequeue_best_for_time(1000).is_none());
        assert_eq!(q.overflow_count(), 0);
        for pts in [100u64, 200, 300] {
            q.enqueue(MediaVideoFrame {
                pts_ms: pts,
                width: 4,
                height: 4,
                pixels: vec![0; 64],
                pixel_buffer_ptr: 0,
                seek_generation: 0,
            });
        }
        // 3 enqueues into cap 2 → exactly 1 overflow drop.
        assert_eq!(q.overflow_count(), 1);
        assert_eq!(q.len(), 2);
    }

    #[test]
    fn test_frame_memory_bytes_tracks_dimensions() {
        let q: FrameQueue<MediaVideoFrame> = FrameQueue::new(3);
        assert_eq!(q.frame_memory_bytes(), 0);
        q.enqueue(MediaVideoFrame {
            pts_ms: 100,
            width: 1920,
            height: 1080,
            pixels: vec![0; 10],
            pixel_buffer_ptr: 0,
            seek_generation: 0,
        });
        // 1920*1080*4 = 8294400.
        assert_eq!(q.frame_memory_bytes(), 1920 * 1080 * 4);
    }

    #[test]
    fn test_rendering_path_never_claims_unverified_zero_copy() {
        let engine = MediaPlaybackEngine::new(0, 2000, 720);
        let path = engine.rendering_path();
        assert!(!path.is_empty());
        // Without an open HW session the path must not claim zero-copy.
        // (After open with VT it may legitimately report zero-copy.)
        if path.contains("zero_copy") {
            assert!(path.contains("iosurface") || path.contains("surface"));
        }
    }

    #[test]
    fn test_engine_new_preserves_legacy_zero_edge_and_budgets() {
        // previewMaxEdge == 0 → 1080 (backward compat).
        let engine = MediaPlaybackEngine::new(0, 2000, 0);
        assert_eq!(engine.preview_max_edge, 1080);
        // Queues are budgeted, never 2000 unbounded.
        assert!(engine.video_packet_queue.len() == 0);
        assert!(engine.video_frame_queue.max_size() <= 3);
    }

    #[test]
    fn test_cancel_flag_lifecycle() {
        let engine = MediaPlaybackEngine::new(0, 2000, 720);
        assert!(!engine.is_cancelled());
        engine.request_cancel();
        assert!(engine.is_cancelled());
        engine.clear_cancel();
        assert!(!engine.is_cancelled());
    }

    /// The HTTP protocol stack must be linked: opening garbage bytes over
    /// loopback HTTP must fail probe ("Invalid data"-class), never with
    /// "Protocol not found" (minimal `--disable-everything` builds once
    /// dropped the whole network stack — see PeerStream localhost streams).
    #[test]
    fn test_open_url_rejects_garbage_over_http() {
        use std::io::{Read, Write};
        use std::net::TcpListener;

        let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback");
        let port = listener.local_addr().unwrap().port();
        let server = thread::spawn(move || {
            // Single-shot garbage server. The engine's fast probe consumes
            // this connection; if a fallback retry follows it fails fast
            // with connection-refused (still Err, still not "Protocol not
            // found"), so the test never hangs.
            let (mut stream, _) = listener.accept().expect("accept");
            let mut request = [0u8; 4096];
            let _ = stream.read(&mut request);
            let header = b"HTTP/1.0 200 OK\r\nContent-Type: video/mp4\r\nContent-Length: 131072\r\nConnection: close\r\n\r\n";
            stream.write_all(header).expect("write header");
            // 128 KiB of non-media bytes: probing must conclude, not hang.
            let garbage = vec![0xABu8; 131072];
            let _ = stream.write_all(&garbage);
            // Drop => EOF so avformat_open_input returns promptly.
        });

        let engine = MediaPlaybackEngine::new(0, 2000, 720);
        let url = format!("http://127.0.0.1:{}/garbage.mp4", port);
        let err = engine
            .open_url(url, NetworkOptions::default())
            .expect_err("garbage bytes must not open");
        let message = format!("{:?}", err);
        assert!(
            !message.contains("Protocol not found"),
            "HTTP stack missing: {}",
            message
        );
        let _ = server.join();
    }

    /// Sidecar `.srt` over FFmpeg's file protocol. The player sends plain
    /// filesystem paths for `file:` URIs (never `file:///...`), so this is
    /// the exact target string the engine must open, and the cues must reach
    /// `poll_subtitle_text` with the times written in the file.
    #[test]
    fn test_external_subtitle_plain_path_delivers_cues() {
        let dir = std::env::temp_dir().join(format!(
            "media_forge_sidecar_{}",
            std::process::id()
        ));
        std::fs::create_dir_all(&dir).expect("create temp dir");
        let path = dir.join("sidecar.srt");
        std::fs::write(
            &path,
            "1\n00:00:05,000 --> 00:00:09,000\nHello sidecar\n\n\
             2\n00:00:10,000 --> 00:00:14,000\nSecond cue\n\n",
        )
        .expect("write sidecar srt");
        let plain_path = path.to_string_lossy().into_owned();
        assert!(
            !plain_path.contains("://"),
            "test must exercise a plain path: {plain_path}"
        );

        let engine = MediaPlaybackEngine::new(0, 2000, 720);
        engine
            .open_external_subtitle(plain_path)
            .expect("plain path opens");

        // The sidecar is demuxed on its own thread: wait for the first cue.
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
        let mut text = None;
        while std::time::Instant::now() < deadline {
            text = engine.poll_subtitle_text(6000);
            if text.is_some() {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(25));
        }
        assert_eq!(text.as_deref(), Some("Hello sidecar"));
        assert_eq!(
            engine.poll_subtitle_text(12_000).as_deref(),
            Some("Second cue")
        );
        // Outside every cue window nothing is delivered.
        assert_eq!(engine.poll_subtitle_text(30_000), None);

        engine.close_external_subtitle();
        std::fs::remove_dir_all(&dir).ok();
    }
}
