mod presets;

pub use presets::CompressionPreset;

use flutter_rust_bridge::frb;

#[frb]
#[derive(Clone, Debug, PartialEq)]
pub enum VideoCodec {
    H264,
    Hevc,
}

/// PR #4: output container profile. Replaces the legacy
/// [CompressOptions::fast_start] + [CompressOptions::fragmented_mp4]
/// booleans with an explicit enum so callers can pick HLS / fMP4
/// without inventing new flags.
#[frb]
#[derive(Clone, Debug, PartialEq)]
pub enum OutputProfile {
    /// Single progressive MP4. `fast_start: true` (default) moves the
    /// moov atom to the front of the file so the asset can play before
    /// the download completes. Equivalent to the old
    /// `fast_start: true, fragmented_mp4: false`.
    ProgressiveMp4 {
        /// Move the moov atom to the front of the file so playback
        /// can start before the download completes. Default: `true`.
        fast_start: bool,
    },
    /// Fragmented MP4 (CMAF-style). Each fragment is independently
    /// decodable, so the asset is seekable as soon as the first
    /// fragment is downloaded. Pair with HLS / DASH for adaptive
    /// streaming or with social-media uploads that expect fMP4 input.
    /// `fragment_duration_ms` controls the target fragment length
    /// (FFmpeg `movflags=+frag_keyframe+frag_duration_ms=N`).
    FragmentedMp4 {
        /// Target fragment length in milliseconds. Default: `2000`
        /// (matches the HLS default segment length).
        fragment_duration_ms: u32,
    },
    /// HTTP Live Streaming (HLS, m3u8 + .ts segments). The output
    /// directory must already exist; FFmpeg writes
    /// `playlist.m3u8` + `segment_NNN.ts` alongside the output path
    /// (the output path is used as a prefix — e.g. `/out/playlist.m3u8`
    /// produces segments at `/out/playlistN.ts`).
    Hls {
        /// Target segment length in milliseconds. Default: `6000`
        /// (Apple's recommended HLS segment length).
        segment_duration_ms: u32,
        /// When `true`, FFmpeg also writes a `master.m3u8` with
        /// `#EXT-X-STREAM-INF` tags for adaptive bitrate ladders.
        /// Currently a single rendition is emitted; the master
        /// playlist is correct in shape but lists only one variant.
        master_playlist: bool,
        /// HLS protocol version. Default: `6` (HLSv6, supports
        /// fMP4 / CMAF segments). Use `3` for legacy clients.
        hls_version: u8,
    },
}

impl Default for OutputProfile {
    fn default() -> Self {
        OutputProfile::ProgressiveMp4 { fast_start: true }
    }
}

#[frb]
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum VideoQuality {
    Low,
    Medium,
    High,
    Custom,
    /// 1080p, social feed / story style.
    Instagram,
    /// 720p, small files for messaging.
    Whatsapp,
    /// 720p (max 1280×720), messaging app uploads.
    Telegram,
    /// 1080p, higher bitrate for video platforms.
    Youtube,
    /// High quality, large output.
    Lossless,
}

#[frb]
#[derive(Clone, Debug, PartialEq)]
pub enum ProcessingPhase {
    Probing,
    Decoding,
    Encoding,
    Muxing,
    Thumbnail,
    Done,
    Cancelled,
    Failed,
}

#[frb]
#[derive(Clone, Debug, PartialEq)]
pub enum ThumbnailFormat {
    Jpeg,
    Webp,
}

#[frb]
#[derive(Clone, Debug)]
pub struct ProgressEvent {
    pub job_id: String,
    pub phase: ProcessingPhase,
    pub percent: f32,
    pub frame: u64,
    pub fps: f32,
    pub eta_ms: u64,
}

#[frb]
#[derive(Clone, Debug)]
pub struct MediaInfo {
    pub duration_ms: u64,
    pub width: u32,
    pub height: u32,
    pub rotation: i32,
    pub fps: f32,
    pub video_codec: String,
    pub audio_codec: Option<String>,
    pub bitrate: u64,
    pub file_size: u64,
    /// True for iPhone / camera Dolby Vision HEVC (preview uses software decode on Apple).
    pub has_dolby_vision: bool,
    /// When true, UI should use session RGBA decode (skip VideoToolbox seek on Apple).
    pub prefer_software_preview: bool,
}

#[frb]
#[derive(Clone, Debug)]
pub struct CompressOptions {
    pub input_path: String,
    pub output_path: Option<String>,
    pub quality: VideoQuality,
    pub codec: VideoCodec,
    pub crf: Option<u8>,
    pub target_bitrate: Option<u64>,
    pub max_width: Option<u32>,
    pub max_height: Option<u32>,
    pub max_fps: Option<f32>,
    pub include_audio: bool,
    /// PR #4 (deprecated): use [output_profile] instead. Retained for
    /// one release so existing 2.x callers keep compiling.
    /// `true` + `fragmented_mp4 = false` -> `ProgressiveMp4 { fast_start: true }`.
    /// `fragmented_mp4 = true` (regardless of fast_start) -> `FragmentedMp4 { fragment_duration_ms: 2000 }`.
    pub fast_start: bool,
    /// PR #4 (deprecated): see [output_profile].
    pub fragmented_mp4: bool,
    /// PR #4: output container profile. When `None`, the deprecated
    /// `fast_start` + `fragmented_mp4` booleans are used. When `Some`,
    /// `output_profile` wins. New code should always set this.
    pub output_profile: Option<OutputProfile>,
    pub prefer_hardware_encoder: bool,
    /// Inclusive clip start in milliseconds (0 = beginning).
    pub start_ms: Option<u64>,
    /// Inclusive clip end in milliseconds (None = end of file).
    pub end_ms: Option<u64>,
    /// Pre-rasterized overlay PNGs (Flutter) composited on each encoded frame.
    pub burn_in_overlays: Vec<BurnInOverlay>,
    /// External background audio mixed on export (streaming decode; empty = no added tracks).
    pub audio_tracks: Vec<AudioTrackInput>,
    /// When true, omit the source file’s embedded audio from the mix (only added tracks).
    pub mute_original_audio: bool,
}

/// Background audio lane for export mux (paths must be local FFmpeg-readable files).
#[frb]
#[derive(Clone, Debug, Default)]
pub struct AudioTrackInput {
    pub source_path: String,
    pub source_start_ms: u64,
    pub duration_ms: u64,
    pub timeline_start_ms: u64,
    pub volume: f32,
    pub muted: bool,
}

/// One overlay layer for export burn-in (image PNG v1; text vector v2).
#[frb]
#[derive(Clone, Debug, Default)]
pub struct BurnInOverlay {
    pub content: OverlayContent,
    /// Visible on [start_ms, end_ms) in source timeline milliseconds.
    pub start_ms: u64,
    pub end_ms: u64,
    pub transform: TransformTracks,
    pub effects: OverlayEffects,
}

/// Raster image or vector text payload.
#[frb]
#[derive(Clone, Debug)]
pub enum OverlayContent {
    Image(ImageOverlayData),
    Text(TextOverlayData),
}

impl Default for OverlayContent {
    fn default() -> Self {
        OverlayContent::Image(ImageOverlayData::default())
    }
}

/// Pre-rasterized PNG from Flutter (stickers / legacy bake).
#[frb]
#[derive(Clone, Debug, Default)]
pub struct ImageOverlayData {
    pub path: String,
    /// Normalized anchor 0–1 (top-left origin), matches Flutter compositor.
    pub anchor_x: f32,
    pub anchor_y: f32,
}

/// Vector text rendered at export resolution via cosmic-text (Category 2).
#[frb]
#[derive(Clone, Debug)]
pub struct TextOverlayData {
    pub text: String,
    pub anchor_x: f32,
    pub anchor_y: f32,
    /// Logical font size at 1080p reference height; scaled to output resolution.
    pub font_size: f32,
    /// CSS-style weight 100–900.
    pub font_weight: u32,
    pub italic: bool,
    pub color_r: u8,
    pub color_g: u8,
    pub color_b: u8,
    pub color_a: u8,
    pub letter_spacing: f32,
    /// Max layout width in normalized frame units (1.0 = full output width).
    pub max_width: f32,
    pub padding: f32,
    pub corner_radius: f32,
    pub show_background: bool,
    pub background_r: u8,
    pub background_g: u8,
    pub background_b: u8,
    pub background_a: u8,
    pub glow_intensity: f32,
    pub text_align: TextAlign,
    pub content_animation: TextContentAnimation,
    pub content_animation_duration_ms: u64,
}

impl Default for TextOverlayData {
    fn default() -> Self {
        Self {
            text: String::new(),
            anchor_x: 0.5,
            anchor_y: 0.5,
            font_size: 32.0,
            font_weight: 600,
            italic: false,
            color_r: 255,
            color_g: 255,
            color_b: 255,
            color_a: 255,
            letter_spacing: 0.0,
            max_width: 0.5,
            padding: 12.0,
            corner_radius: 16.0,
            show_background: true,
            background_r: 0,
            background_g: 0,
            background_b: 0,
            background_a: 230,
            glow_intensity: 0.0,
            text_align: TextAlign::Center,
            content_animation: TextContentAnimation::None,
            content_animation_duration_ms: 0,
        }
    }
}

/// Category 2 content animations (glyph/word visibility — not rigid transforms).
#[frb]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum TextContentAnimation {
    #[default]
    None,
    Typewriter,
    WordReveal,
    CharacterStagger,
}

#[frb]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum TextAlign {
    #[default]
    Left,
    Center,
    Right,
}

/// GPU-style overlay post-effects (v3 — CPU implementation during burn-in).
#[frb]
#[derive(Clone, Debug, Default)]
pub struct OverlayEffects {
    pub effects: Vec<OverlayEffect>,
}

#[frb]
#[derive(Clone, Debug)]
pub struct OverlayEffect {
    pub kind: OverlayEffectKind,
    /// 0–1 strength.
    pub intensity: f32,
    /// Ms relative to overlay [start_ms]; 0 = overlay start.
    pub start_ms: u64,
    /// 0 = entire visible duration after [start_ms].
    pub duration_ms: u64,
}

#[frb]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum OverlayEffectKind {
    #[default]
    None,
    Glitch,
    Glow,
    ChromaticAberration,
    RgbSplit,
    MotionBlur,
    Shake,
}

/// Sparse transform animation tracks (normalized coordinates).
#[frb]
#[derive(Clone, Debug, Default)]
pub struct TransformTracks {
    pub tracks: Vec<AnimationTrack>,
}

/// One animated scalar property over a time window (relative to overlay [start_ms]).
#[frb]
#[derive(Clone, Debug)]
pub struct AnimationTrack {
    pub property: TransformProperty,
    pub from: f32,
    pub to: f32,
    pub start_ms: u64,
    pub duration_ms: u64,
    pub easing: Easing,
}

/// Transform channel. Translate values are fractions of output frame size (1.0 = full width/height).
#[frb]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TransformProperty {
    TranslateX,
    TranslateY,
    Scale,
    Rotation,
    Opacity,
}

/// Easing curve applied to track progress t in [0, 1].
#[frb]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Easing {
    Linear,
    EaseIn,
    EaseOut,
    EaseInOut,
    Overshoot,
    Bounce,
}

#[frb]
#[derive(Clone, Debug)]
pub struct CompressResult {
    pub output_path: String,
    pub duration_ms: u64,
    pub file_size: u64,
    pub used_hardware_acceleration: bool,
    pub encoder_name: String,
    /// How frames reached the encoder: `vt_zero_copy`, `vt_gpu_scale`, `hw_decode+swscale`, `swscale`, `direct`.
    pub pipeline_mode: String,
}

#[frb]
#[derive(Clone, Debug)]
pub struct ThumbnailOptions {
    pub input_path: String,
    pub output_path: Option<String>,
    pub position_ms: u64,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub format: ThumbnailFormat,
}

#[frb]
#[derive(Clone, Debug)]
pub struct BatchThumbnailOptions {
    pub input_path: String,
    pub output_dir: String,
    /// When set, length must equal [positions_ms]; each index is written to this path
    /// instead of [output_dir]/thumb_XXXX.ext.
    pub output_paths: Option<Vec<String>>,
    pub positions_ms: Vec<u64>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub format: ThumbnailFormat,
    /// PR #3 (opt-in): when `Some(n) > 0`, the batch opens up to `n`
    /// parallel demuxer instances and shards the positions across them
    /// (decode stays single-threaded per demuxer; encode is already
    /// parallel via rayon). Default 0 = single-demuxer. Useful for
    /// filmstrip batches on long-GOP iPhone HEVC where the demuxer
    /// open + first-frame-decode is the bottleneck.
    pub parallel_decoder_count: Option<u8>,
}

#[frb]
#[derive(Clone, Debug)]
pub struct BatchThumbnailResult {
    pub paths: Vec<String>,
    /// PR #3: per-position decode status. Same length as
    /// `positions_ms` in the request. Use this to flag approximate
    /// thumbnails in a UI filmstrip.
    pub decoded_status: Vec<ThumbnailDecodeStatus>,
}

/// PR #3: per-position status surfaced from the Rust decode pipeline.
#[frb]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ThumbnailDecodeStatus {
    /// Frame decoded at or after the requested position. Most common.
    Exact,
    /// The demuxer ran out of packets before reaching the requested
    /// position. The thumbnail is the closest decoded keyframe; the
    /// UI should flag it as approximate.
    NearestKeyframe,
}

/// In-memory thumbnail (JPEG/WebP bytes) — no filesystem write.
#[frb]
#[derive(Clone, Debug)]
pub struct ThumbnailBytesOptions {
    pub input_path: String,
    pub position_ms: u64,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub format: ThumbnailFormat,
}

/// Batch in-memory thumbnails for UI previews (filmstrip, scrubber fallback).
#[frb]
#[derive(Clone, Debug)]
pub struct BatchThumbnailBytesOptions {
    pub input_path: String,
    pub positions_ms: Vec<u64>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub format: ThumbnailFormat,
    /// PR #3 (opt-in): see [BatchThumbnailOptions::parallel_decoder_count].
    pub parallel_decoder_count: Option<u8>,
}

#[frb]
#[derive(Clone, Debug)]
pub struct BatchThumbnailBytesResult {
    pub frames: Vec<Vec<u8>>,
    /// PR #3: per-position decode status. Same length as
    /// `positions_ms` in the request.
    pub decoded_status: Vec<ThumbnailDecodeStatus>,
}

/// Single decoded preview frame (RGBA8888) for texture upload — Sprint V1.1.
#[frb]
#[derive(Clone, Debug)]
pub struct PreviewFrameRgba {
    pub pts_ms: u64,
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

/// PR #5: preview frame paired with a `ReleaseToken` so the Dart
/// side can hand the underlying buffer back to the Rust pool via a
/// `Finalizer` (no manual `bufferPoolRelease` call required from
/// app code). New code should prefer this struct; the bare
/// [PreviewFrameRgba] is kept for back-compat.
#[frb]
#[derive(Clone, Debug)]
pub struct PreviewFrameRgbaBuf {
    pub pts_ms: u64,
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
    /// Stable token for [crate::pool::release_buffer_by_token]. The
    /// value `0` means "no token" (the buffer will be released by
    /// the explicit `bufferPoolRelease` path instead).
    pub release_token: u64,
}

/// Apple HW preview frame: BGRA `CVPixelBuffer` pointer for zero-copy texture present (V1.4).
#[frb]
#[derive(Clone, Debug)]
pub struct PreviewFramePixelBuffer {
    pub pts_ms: u64,
    pub width: u32,
    pub height: u32,
    /// Native `CVPixelBuffer*` address; call [crate::api::release_preview_pixel_buffer] if not presented.
    pub pixel_buffer_ptr: u64,
}

#[frb]
#[derive(Clone, Debug)]
pub enum PlaybackFrame {
    Rgba(PreviewFrameRgba),
    PixelBuffer(PreviewFramePixelBuffer),
}

#[frb]
#[derive(Clone, Debug)]
pub enum JobResult {
    Compress(CompressResult),
    Empty,
}

impl Default for CompressOptions {
    fn default() -> Self {
        Self {
            input_path: String::new(),
            output_path: None,
            quality: VideoQuality::Medium,
            codec: VideoCodec::H264,
            crf: None,
            target_bitrate: None,
            max_width: None,
            max_height: None,
            max_fps: None,
            include_audio: true,
            fast_start: true,
            fragmented_mp4: false,
            output_profile: None,
            prefer_hardware_encoder: true,
            start_ms: None,
            end_ms: None,
            burn_in_overlays: Vec::new(),
            audio_tracks: Vec::new(),
            mute_original_audio: false,
        }
    }
}

/// Resolve the effective output profile. The new `output_profile` field
/// wins when set; otherwise we honor the legacy `fast_start` /
/// `fragmented_mp4` booleans for callers that have not yet migrated.
pub fn effective_output_profile(opts: &CompressOptions) -> OutputProfile {
    if let Some(profile) = opts.output_profile.clone() {
        return profile;
    }
    if opts.fragmented_mp4 {
        OutputProfile::FragmentedMp4 {
            fragment_duration_ms: 2000,
        }
    } else {
        OutputProfile::ProgressiveMp4 {
            fast_start: opts.fast_start,
        }
    }
}

impl VideoQuality {
    /// Use hardware encoders for mobile-oriented presets unless user overrides.
    pub fn default_prefer_hardware(&self) -> bool {
        match self {
            Self::Lossless => false,
            Self::Custom => crate::platform::default_prefer_hardware_encoder(),
            Self::Whatsapp | Self::Instagram | Self::Telegram | Self::Youtube => true,
            Self::Low | Self::Medium | Self::High => {
                crate::platform::default_prefer_hardware_encoder()
            }
        }
    }
}

#[derive(Clone, Debug)]
pub struct QualityPreset {
    pub crf: u8,
    pub max_bitrate: u64,
    pub max_dimension: u32,
    pub max_fps: f32,
}
