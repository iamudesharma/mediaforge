use flutter_rust_bridge::frb;
use crate::frb_generated::StreamSink;

use crate::error::{Result, VideoProcessorError};
use crate::jobs::progress::ProgressReporter;
use crate::jobs::registry::{registry, CancellationToken};
use crate::pipeline;
use crate::types::*;

#[frb(init)]
pub fn init_app() {
    let _ = env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).try_init();
    let _ = crate::ffmpeg::ensure_ffmpeg_initialized();
}

/// Initialize the native video processor (call once at app startup).
#[frb]
pub fn initialize() -> Result<()> {
    init_app();
    Ok(())
}

/// Probe media metadata (fast mp4parse path, FFmpeg fallback).
#[frb]
pub fn get_media_info(path: String) -> Result<MediaInfo> {
    pipeline::probe_media_info(&path)
}

/// Stream-copy a remote URL to a local file under [dest_dir] (opt-in; saves repeated HTTP opens).
#[frb(sync)]
pub fn prefetch_remote_input(url: String, dest_dir: String) -> Result<String> {
    use std::path::Path;
    crate::ffmpeg::prefetch_remote_input(&url, Path::new(dest_dir.trim()))
}

/// Start compression in the background; returns job id immediately.
#[frb]
pub async fn start_compress(
    options: CompressOptions,
    progress: StreamSink<ProgressEvent>,
) -> Result<String> {
    let reg = registry();
    let _permit = reg.acquire_permit().await?;
    let (job_id, token) = reg.register();

    let jid = job_id.clone();
    let mut reporter = ProgressReporter::new(job_id.clone(), progress);
    reporter.emit(
        ProcessingPhase::Probing,
        0.0,
        0,
        0.0,
        0,
        true,
    );

    let handle = tokio::task::spawn_blocking(move || {
        let result = pipeline::run_compress(options, token.clone(), &mut reporter);
        match &result {
            Ok(r) => reg.complete(
                &jid,
                Ok(JobResult::Compress(r.clone())),
            ),
            Err(VideoProcessorError::Cancelled) => {
                reporter.cancelled();
                reg.complete(&jid, Err(VideoProcessorError::Cancelled));
            }
            Err(e) => {
                reporter.failed();
                reg.complete(&jid, Err(e.clone()));
            }
        }
        drop(_permit);
        result
    });

    // Detach; result retrieved via wait_for_job
    tokio::spawn(async move {
        let _ = handle.await;
    });

    Ok(job_id)
}

/// Wait for a job to complete and return its result.
#[frb]
pub async fn wait_for_job(job_id: String) -> Result<JobResult> {
    let reg = registry();
    let id = job_id.clone();
    tokio::task::spawn_blocking(move || {
        reg.wait_result(&id, std::time::Duration::from_secs(86_400))
    })
    .await
    .map_err(|e| VideoProcessorError::Internal(e.to_string()))?
}

/// Cancel a running job by id.
#[frb]
pub fn cancel_job(job_id: String) -> Result<bool> {
    let reg = registry();
    if reg.cancel(&job_id) {
        Ok(true)
    } else {
        Err(VideoProcessorError::JobNotFound(job_id))
    }
}

/// Extract a single thumbnail at the given position.
#[frb]
pub async fn thumbnail(options: ThumbnailOptions) -> Result<String> {
    let token = CancellationToken::new();
    tokio::task::spawn_blocking(move || pipeline::extract_thumbnail(options, token))
        .await
        .map_err(|e| VideoProcessorError::Internal(e.to_string()))?
}

/// Extract multiple thumbnails in one pass.
#[frb]
pub async fn batch_thumbnails(options: BatchThumbnailOptions) -> Result<BatchThumbnailResult> {
    let token = CancellationToken::new();
    tokio::task::spawn_blocking(move || pipeline::extract_batch_thumbnails(options, token))
        .await
        .map_err(|e| VideoProcessorError::Internal(e.to_string()))?
}

/// Thumbnail as encoded image bytes (JPEG/WebP) — no filesystem write (UI previews).
#[frb]
pub async fn thumbnail_bytes(options: ThumbnailBytesOptions) -> Result<Vec<u8>> {
    let token = CancellationToken::new();
    tokio::task::spawn_blocking(move || pipeline::extract_thumbnail_bytes(options, token))
        .await
        .map_err(|e| VideoProcessorError::Internal(e.to_string()))?
}

/// Batch thumbnails as in-memory frames for filmstrip / scrub previews.
#[frb]
pub async fn batch_thumbnail_bytes(
    options: BatchThumbnailBytesOptions,
) -> Result<BatchThumbnailBytesResult> {
    let token = CancellationToken::new();
    tokio::task::spawn_blocking(move || pipeline::extract_batch_thumbnail_bytes(options, token))
        .await
        .map_err(|e| VideoProcessorError::Internal(e.to_string()))?
}

/// Decode one preview frame as RGBA8888 (texture / in-memory scrub — no JPEG write).
#[frb]
pub async fn decode_preview_frame_rgba(
    input_path: String,
    position_ms: u64,
    max_edge: Option<u32>,
) -> Result<PreviewFrameRgba> {
    tokio::task::spawn_blocking(move || {
        pipeline::decode_preview_frame_rgba(&input_path, position_ms, max_edge)
    })
    .await
    .map_err(|e| VideoProcessorError::Internal(e.to_string()))?
}

/// Decode one preview frame as a BGRA `CVPixelBuffer` (Apple VideoToolbox — V1.4).
#[frb]
pub async fn decode_preview_frame_pixel_buffer(
    input_path: String,
    position_ms: u64,
    max_edge: Option<u32>,
) -> Result<PreviewFramePixelBuffer> {
    tokio::task::spawn_blocking(move || {
        pipeline::decode_preview_frame_pixel_buffer(&input_path, position_ms, max_edge)
    })
    .await
    .map_err(|e| VideoProcessorError::Internal(e.to_string()))?
}

/// Release a native preview pixel buffer not adopted by [rust_gpu_texture].
#[frb(sync)]
pub fn release_preview_pixel_buffer(pixel_buffer_ptr: u64) {
    pipeline::release_preview_pixel_buffer(pixel_buffer_ptr);
}

/// Returns the number of active jobs.
#[frb]
pub fn active_job_count() -> u32 {
    registry().active_count() as u32
}

/// Cleanup completed job state.
#[frb]
pub fn cleanup_job(job_id: String) -> Result<()> {
    registry().cleanup(&job_id);
    Ok(())
}

// Re-export error mapping for FRB
impl VideoProcessorError {
    #[frb]
    pub fn error_code(&self) -> String {
        self.code().to_string()
    }

    #[frb]
    pub fn error_message(&self) -> String {
        self.to_string()
    }
}

pub use crate::pipeline::preview::VideoPreviewSession;

impl VideoPreviewSession {
    #[frb(sync)]
    pub fn create(
        input_path: String,
        max_edge: Option<u32>,
        prefer_hw: bool,
    ) -> Result<VideoPreviewSession> {
        VideoPreviewSession::new(input_path, max_edge, prefer_hw)
    }

    pub async fn next_frame_rgba(&self) -> Result<Option<PreviewFrameRgba>> {
        self.read_next_rgba()
    }

    pub async fn next_frame_pixel_buffer(&self) -> Result<Option<PreviewFramePixelBuffer>> {
        self.read_next_pixel_buffer()
    }

    pub async fn seek_and_decode_rgba(&self, position_ms: u64) -> Result<PreviewFrameRgba> {
        self.seek_and_read_rgba(position_ms)
    }

    pub async fn seek_and_decode_pixel_buffer(
        &self,
        position_ms: u64,
    ) -> Result<PreviewFramePixelBuffer> {
        self.seek_and_read_pixel_buffer(position_ms)
    }

    pub fn start_playback(
        &self,
        rate: f64,
        progress: crate::frb_generated::StreamSink<PlaybackFrame, flutter_rust_bridge::for_generated::SseCodec>,
    ) -> Result<()> {
        self.start_playback_inner(rate, progress)
    }

    #[frb(sync)]
    pub fn pause_playback(&self) -> Result<()> {
        self.pause_playback_inner()
    }

    /// Updates preview scale for subsequent decode/scrub/playback frames (no demuxer reopen).
    #[frb(sync)]
    pub fn set_preview_max_edge(&self, max_edge: Option<u32>) -> Result<()> {
        self.set_max_edge_inner(max_edge)
    }

    #[frb(sync)]
    pub fn close(&self) {
        self.shutdown();
    }
}

/// Releases a buffer back to the video processor's native pool.
#[frb(sync)]
pub fn buffer_pool_release(buf: Vec<u8>) {
    crate::pool::release_buffer(buf);
}

/// Acquires a buffer from the video processor's native pool with a minimum capacity.
#[frb(sync)]
pub fn buffer_pool_acquire(min_capacity: u32) -> Vec<u8> {
    crate::pool::acquire_buffer(min_capacity as usize)
}

/// Returns the current statistics of the video processor's buffer pool (count, total bytes).
#[frb(sync)]
pub fn buffer_pool_stats() -> (usize, usize) {
    crate::pool::pool_stats()
}

