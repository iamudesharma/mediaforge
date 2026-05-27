mod presets;

pub use presets::CompressionPreset;

use flutter_rust_bridge::frb;

#[frb]
#[derive(Clone, Debug, PartialEq)]
pub enum VideoCodec {
    H264,
    Hevc,
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
    /// 1280p, messaging app uploads.
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
    pub fast_start: bool,
    pub fragmented_mp4: bool,
    pub prefer_hardware_encoder: bool,
    /// Inclusive clip start in milliseconds (0 = beginning).
    pub start_ms: Option<u64>,
    /// Inclusive clip end in milliseconds (None = end of file).
    pub end_ms: Option<u64>,
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
}

#[frb]
#[derive(Clone, Debug)]
pub struct BatchThumbnailResult {
    pub paths: Vec<String>,
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
}

#[frb]
#[derive(Clone, Debug)]
pub struct BatchThumbnailBytesResult {
    pub frames: Vec<Vec<u8>>,
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
            prefer_hardware_encoder: true,
            start_ms: None,
            end_ms: None,
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
