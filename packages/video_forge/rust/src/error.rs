use thiserror::Error;

#[derive(Debug, Clone, Error)]
pub enum VideoForgeError {
    #[error("invalid input: {0}")]
    InvalidInput(String),
    #[error("file not found: {0}")]
    FileNotFound(String),
    #[error("unsupported codec: {0}")]
    UnsupportedCodec(String),
    #[error("job not found: {0}")]
    JobNotFound(String),
    #[error("job cancelled")]
    Cancelled,
    #[error("I/O error: {0}")]
    IoError(String),
    #[error("ffmpeg error: {0}")]
    FfmpegError(String),
    #[error("queue full: max concurrent jobs reached")]
    QueueFull,
    #[error("internal error: {0}")]
    Internal(String),
}

impl VideoForgeError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::InvalidInput(_) => "invalid_input",
            Self::FileNotFound(_) => "file_not_found",
            Self::UnsupportedCodec(_) => "unsupported_codec",
            Self::JobNotFound(_) => "job_not_found",
            Self::Cancelled => "cancelled",
            Self::IoError(_) => "io_error",
            Self::FfmpegError(_) => "ffmpeg_error",
            Self::QueueFull => "queue_full",
            Self::Internal(_) => "internal",
        }
    }
}

pub type Result<T> = std::result::Result<T, VideoForgeError>;

/// Deprecated alias for [`VideoForgeError`] kept for one release to avoid breaking
/// downstream callers (e.g. `video_forge_kit`, `media_studio`) that still match
/// on the old name. New code should use [`VideoForgeError`].
#[deprecated(
    since = "2.0.0",
    note = "renamed to `VideoForgeError`; will be removed in 2.1.0"
)]
pub type VideoProcessorError = VideoForgeError;
